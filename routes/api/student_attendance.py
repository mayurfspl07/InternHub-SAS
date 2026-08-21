"""Student attendance management & export APIs for Admin and Mentor roles.

Endpoints:
  GET /api/admin/students
      Paginated list of interns with attendance overview stats (scoped to assigned mentees for mentors).

  GET /api/admin/students/today (alias: /api/admin/attendance/today)
      Today's live attendance for interns, paginated, with summary breakdown.

  GET /api/admin/students/export (alias: /api/admin/attendance/export)
      Attendance CSV export with flexible from_date/to_date, department, status, user_id filters.

  GET /api/admin/students/search (alias: /api/admin/students/overview/search)
      Search students by name/email/dept with custom from_date/to_date attendance overview window.

  GET /api/admin/students/{user_id}/attendance
      Full attendance records for a specific intern with date filters & monthly summary.

Endpoints require admin, superadmin, or mentor role. Mentors only receive data for their assigned interns.
"""
from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import and_, case, func, or_
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import (
    Attendance,
    AttendanceStatus,
    Project,
    ProjectAssignment,
    User,
    UserRole,
)
from utils import (
    export_attendance_csv,
    get_mentor_intern_ids,
    isoformat_utc,
    local_today,
    month_range,
)

router = APIRouter(prefix="/api/admin/students", tags=["Admin - Student Attendance"])
DbSession = Annotated[Session, Depends(get_db)]

PAGE_SIZE = 20
REPORT_MAX_PAGE_SIZE = 10_000


# ---------------------------------------------------------------------------
# Helpers & Serialisers
# ---------------------------------------------------------------------------

def _require_admin_or_mentor(request: Request, db: Session) -> User:
    user = get_optional_user(request, db)
    if not user or user.role not in (UserRole.ADMIN, UserRole.SUPERADMIN, UserRole.MENTOR):
        raise HTTPException(status_code=403, detail="Admin or mentor access required.")
    return user


def _require_admin(request: Request, db: Session) -> User:
    return _require_admin_or_mentor(request, db)


def _att_dict(r: Attendance) -> dict:
    show_checkout = r.check_out is not None and not r.checkout_missed
    return {
        "id": r.id,
        "user_id": r.user_id,
        "user_name": r.user.name if r.user else None,
        "date": r.date.isoformat(),
        "check_in": r.check_in.strftime("%H:%M") if r.check_in else None,
        "check_in_dt": r.check_in.isoformat() if r.check_in else None,
        "check_out": r.check_out.strftime("%H:%M") if show_checkout else None,
        "check_out_dt": r.check_out.isoformat() if show_checkout else None,
        "hours_worked": r.hours_worked,
        "status": r.status,
        "notes": r.notes,
        "checkout_source": r.checkout_source,
        "checkout_missed": r.checkout_missed,
        "check_in_location": (
            {"lat": r.check_in_lat, "lng": r.check_in_lng, "address": r.check_in_address}
            if r.check_in_lat is not None and r.check_in_lng is not None
            else None
        ),
        "check_out_location": (
            {"lat": r.check_out_lat, "lng": r.check_out_lng, "address": r.check_out_address}
            if show_checkout and r.check_out_lat is not None and r.check_out_lng is not None
            else None
        ),
        "check_in_photo_url": (
            r.check_in_photo
            if r.check_in_photo and r.check_in_photo.startswith(("http://", "https://"))
            else (f"/api/attendance/{r.id}/photo/checkin" if r.check_in_photo else None)
        ),
        "check_out_photo_url": (
            r.check_out_photo
            if show_checkout and r.check_out_photo and r.check_out_photo.startswith(("http://", "https://"))
            else (f"/api/attendance/{r.id}/photo/checkout" if show_checkout and r.check_out_photo else None)
        ),
    }


def _student_overview(db: Session, u: User, window_days: int = 30, start_date: date | None = None, end_date: date | None = None) -> dict:
    if start_date and end_date:
        rows = (
            db.query(Attendance)
            .filter(Attendance.user_id == u.id, Attendance.date >= start_date, Attendance.date <= end_date)
            .all()
        )
        total_window_days = (end_date - start_date).days + 1
    else:
        since = local_today() - timedelta(days=window_days - 1)
        rows = (
            db.query(Attendance)
            .filter(Attendance.user_id == u.id, Attendance.date >= since)
            .all()
        )
        total_window_days = window_days

    summary = {s: 0 for s in ("present", "late", "half_day", "absent", "on_leave", "excused")}
    total_hours = 0.0
    last_checkin = None
    for r in rows:
        if r.status in summary:
            summary[r.status] += 1
        if r.hours_worked:
            total_hours += float(r.hours_worked)
        if r.check_in and (last_checkin is None or r.check_in.isoformat() > last_checkin):
            last_checkin = r.check_in.isoformat()
    attended = summary["present"] + summary["late"] + summary["half_day"]
    total = len(rows)
    return {
        "window_days": total_window_days,
        "start_date": start_date.isoformat() if start_date else None,
        "end_date": end_date.isoformat() if end_date else None,
        "total_records": total,
        "present": summary["present"],
        "late": summary["late"],
        "half_day": summary["half_day"],
        "absent": summary["absent"],
        "on_leave": summary["on_leave"],
        "excused": summary["excused"],
        "attended": attended,
        "attendance_rate": round((attended / total) * 100, 1) if total else 0.0,
        "total_hours": round(total_hours, 2),
        "last_check_in": last_checkin,
    }


def _active_project_count(db: Session, user_id: int) -> int:
    return (
        db.query(ProjectAssignment)
        .join(Project, ProjectAssignment.project_id == Project.id)
        .filter(
            ProjectAssignment.user_id == user_id,
            Project.is_deleted == False,
            Project.status == "active",
        )
        .count()
    )


def _monthly_summary_for_user(db: Session, user_id: int, start: date, end: date) -> list:
    if db.get_bind().dialect.name == "sqlite":
        ym = func.strftime("%Y-%m", Attendance.date)
    else:
        ym = func.date_format(Attendance.date, "%Y-%m")

    present_statuses = (AttendanceStatus.PRESENT, AttendanceStatus.LATE, AttendanceStatus.HALF_DAY)
    rows = (
        db.query(
            ym.label("year_month"),
            func.sum(case((Attendance.status == AttendanceStatus.PRESENT, 1), else_=0)).label("present"),
            func.sum(case((Attendance.status == AttendanceStatus.LATE, 1), else_=0)).label("late"),
            func.sum(case((Attendance.status == AttendanceStatus.HALF_DAY, 1), else_=0)).label("half_day"),
            func.sum(case((Attendance.status == AttendanceStatus.ABSENT, 1), else_=0)).label("absent"),
            func.sum(case((Attendance.status == AttendanceStatus.ON_LEAVE, 1), else_=0)).label("on_leave"),
            func.sum(case((Attendance.status.in_(present_statuses), 1), else_=0)).label("attended"),
            func.sum(
                case((Attendance.hours_worked.isnot(None), Attendance.hours_worked), else_=0)
            ).label("total_hours"),
            func.count(Attendance.id).label("total_days"),
        )
        .filter(
            Attendance.user_id == user_id,
            Attendance.date >= start,
            Attendance.date <= end,
        )
        .group_by(ym)
        .order_by(ym)
        .all()
    )
    result = []
    for row in rows:
        total_days = int(row.total_days or 0)
        attended = int(row.attended or 0)
        result.append({
            "year_month": row.year_month,
            "present": int(row.present or 0),
            "late": int(row.late or 0),
            "half_day": int(row.half_day or 0),
            "absent": int(row.absent or 0),
            "on_leave": int(row.on_leave or 0),
            "attended": attended,
            "total_days": total_days,
            "total_hours": round(float(row.total_hours or 0), 2),
            "attendance_rate": round((attended / total_days) * 100, 1) if total_days else 0.0,
        })
    return result


def _parse_date_range(params) -> tuple[date, date]:
    today = local_today()
    month_param = params.get("month", "").strip()
    start_s = (params.get("from_date") or params.get("start") or params.get("from") or "").strip()
    end_s = (params.get("to_date") or params.get("end") or params.get("to") or "").strip()

    if month_param:
        try:
            yr, mo = int(month_param[:4]), int(month_param[5:7])
            start_date, end_date = month_range(yr, mo)
        except (ValueError, IndexError):
            raise HTTPException(status_code=422, detail="Invalid month format. Use YYYY-MM.")
    else:
        if start_s:
            try:
                start_date = date.fromisoformat(start_s)
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid start/from_date. Use YYYY-MM-DD.")
        else:
            start_date = today - timedelta(days=29)

        if end_s:
            try:
                end_date = date.fromisoformat(end_s)
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid end/to_date. Use YYYY-MM-DD.")
        else:
            end_date = today

    if start_date > end_date:
        raise HTTPException(status_code=422, detail="start/from_date must be on or before end/to_date.")
    return start_date, end_date


# ---------------------------------------------------------------------------
# Endpoint 1: GET /api/admin/students  (Paginated list with overview)
# ---------------------------------------------------------------------------

@router.get("")
async def list_students(request: Request, db: DbSession):
    """
    Paginated intern list with attendance overview stats (admin or mentor).

    Query params:
      page        int   default 1
      page_size   int   default 20, max 200
      search      str   filter by name / email / department (case-insensitive)
      department  str   filter by specific department
      is_active   str   "true" or "false"
      sort        str   "name" (default) | "joining_date"
      window_days int   trailing calendar days for attendance stats (default 30, max 365)
    """
    user = _require_admin_or_mentor(request, db)
    params = request.query_params

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = min(max(1, int(params.get("page_size", PAGE_SIZE))), 200)
    except ValueError:
        page_size = PAGE_SIZE
    try:
        window_days = min(max(1, int(params.get("window_days", 30))), 365)
    except ValueError:
        window_days = 30

    q = db.query(User).filter(User.role == UserRole.INTERN, User.is_deleted == False)

    if user.is_mentor and not user.is_admin:
        mentor_intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        q = q.filter(User.id.in_(mentor_intern_ids))

    search = params.get("search", "").strip()
    if search:
        like = f"%{search}%"
        q = q.filter(User.name.ilike(like) | User.email.ilike(like) | User.department.ilike(like))

    dept = params.get("department", "").strip()
    if dept:
        q = q.filter(User.department.ilike(f"%{dept}%"))

    is_active_raw = params.get("is_active", "").strip().lower()
    if is_active_raw in ("true", "1"):
        q = q.filter(User.is_active == True)
    elif is_active_raw in ("false", "0"):
        q = q.filter(User.is_active == False)

    sort = params.get("sort", "name").strip().lower()
    if sort == "joining_date":
        q = q.order_by(case((User.joining_date.is_(None), 1), else_=0), User.joining_date.desc(), User.name)
    else:
        q = q.order_by(User.name)

    total = q.count()
    total_pages = max(1, (total + page_size - 1) // page_size)
    interns = q.offset((page - 1) * page_size).limit(page_size).all()

    mentor_ids = {u.mentor_id for u in interns if u.mentor_id}
    mentor_map = {}
    if mentor_ids:
        mentors = db.query(User.id, User.name).filter(User.id.in_(mentor_ids)).all()
        mentor_map = {m.id: m.name for m in mentors}

    students = []
    for u in interns:
        students.append({
            "id": u.id,
            "name": u.name,
            "email": u.email,
            "department": u.department,
            "phone": u.phone,
            "job_title": u.job_title,
            "is_active": u.is_active,
            "joining_date": u.joining_date.isoformat() if u.joining_date else None,
            "mentor_id": u.mentor_id,
            "mentor_name": mentor_map.get(u.mentor_id) if u.mentor_id else None,
            "created_at": isoformat_utc(u.created_at),
            "active_projects": _active_project_count(db, u.id),
            "attendance_overview": _student_overview(db, u, window_days),
        })

    return {
        "students": students,
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
        "filters": {
            "search": search or None,
            "department": dept or None,
            "is_active": is_active_raw or None,
            "sort": sort,
            "window_days": window_days,
        },
    }


# ---------------------------------------------------------------------------
# Endpoint 2: GET /api/admin/students/today  (Today's Attendance)
# ---------------------------------------------------------------------------

@router.get("/today")
async def today_attendance(request: Request, db: DbSession):
    """
    Today's live attendance for interns, paginated, with summary (admin or mentor).

    Query params:
      page        int   default 1
      page_size   int   default 20, max 200
      search      str   filter by student name, email, department
      department  str   filter by department
      status      str   filter by status: present, late, half_day, absent, on_leave, not_checked_in, checked_in, checked_out
      is_active   str   "true" or "false" (default true)
    """
    user = _require_admin_or_mentor(request, db)
    params = request.query_params
    today = local_today()

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = min(max(1, int(params.get("page_size", PAGE_SIZE))), 200)
    except ValueError:
        page_size = PAGE_SIZE

    # Base query for interns
    base_q = db.query(User).filter(User.role == UserRole.INTERN, User.is_deleted == False)

    if user.is_mentor and not user.is_admin:
        mentor_intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        base_q = base_q.filter(User.id.in_(mentor_intern_ids))

    search = params.get("search", "").strip()
    if search:
        like = f"%{search}%"
        base_q = base_q.filter(User.name.ilike(like) | User.email.ilike(like) | User.department.ilike(like))

    dept = params.get("department", "").strip()
    if dept:
        base_q = base_q.filter(User.department.ilike(f"%{dept}%"))

    is_active_raw = params.get("is_active", "").strip().lower()
    if is_active_raw in ("false", "0"):
        base_q = base_q.filter(User.is_active == False)
    else:
        # Default show active interns
        base_q = base_q.filter(User.is_active == True)

    all_interns = base_q.order_by(User.name).all()
    intern_ids = [u.id for u in all_interns]

    # Today's attendance map
    today_records = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter(Attendance.date == today, Attendance.user_id.in_(intern_ids or [-1]))
        .all()
    )
    today_map = {r.user_id: r for r in today_records}

    # Summary metrics across all matched interns
    summary = {
        "total_interns": len(all_interns),
        "checked_in": 0,
        "not_checked_in": 0,
        "checked_out": 0,
        "present": 0,
        "late": 0,
        "half_day": 0,
        "absent": 0,
        "on_leave": 0,
        "excused": 0,
    }
    for u in all_interns:
        r = today_map.get(u.id)
        if r:
            summary["checked_in"] += 1
            if r.check_out and not r.checkout_missed:
                summary["checked_out"] += 1
            if r.status in summary:
                summary[r.status] += 1
        else:
            summary["not_checked_in"] += 1

    attended = summary["present"] + summary["late"] + summary["half_day"]
    summary["attended"] = attended
    summary["attendance_rate"] = round((attended / len(all_interns)) * 100, 1) if all_interns else 0.0

    # Build items list with status filtering
    status_filter = params.get("status", "").strip().lower() or None
    items = []
    for u in all_interns:
        r = today_map.get(u.id)
        today_status_val = r.status if r else "not_checked_in"
        is_checked_in_val = r is not None
        is_checked_out_val = r is not None and r.check_out is not None and not r.checkout_missed

        # Status filter checks
        if status_filter:
            if status_filter == "not_checked_in" and is_checked_in_val:
                continue
            elif status_filter == "checked_in" and not is_checked_in_val:
                continue
            elif status_filter == "checked_out" and not is_checked_out_val:
                continue
            elif status_filter in ("present", "late", "half_day", "absent", "on_leave", "excused"):
                if not r or r.status != status_filter:
                    continue

        items.append({
            "student": {
                "id": u.id,
                "name": u.name,
                "email": u.email,
                "department": u.department,
                "phone": u.phone,
                "job_title": u.job_title,
                "is_active": u.is_active,
                "mentor_id": u.mentor_id,
            },
            "today_status": today_status_val,
            "is_checked_in": is_checked_in_val,
            "is_checked_out": is_checked_out_val,
            "attendance": _att_dict(r) if r else None,
        })

    total = len(items)
    total_pages = max(1, (total + page_size - 1) // page_size)
    paginated_items = items[(page - 1) * page_size : page * page_size]

    return {
        "today": today.isoformat(),
        "summary": summary,
        "students": paginated_items,
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
        "filters": {
            "search": search or None,
            "department": dept or None,
            "status": status_filter,
            "is_active": is_active_raw or "true",
        },
    }


# ---------------------------------------------------------------------------
# Endpoint 3: GET /api/admin/students/export  (Attendance CSV Export)
# ---------------------------------------------------------------------------

@router.get("/export")
@router.get("/export.csv")
async def export_admin_attendance(request: Request, db: DbSession):
    """
    Export attendance records as CSV with date filters (admin or mentor).

    Query params:
      from_date / start / from   YYYY-MM-DD (default: 30 days ago)
      to_date / end / to         YYYY-MM-DD (default: today)
      month                      YYYY-MM (overrides from/to date)
      user_id / intern_id        int (optional single intern)
      department                 str (filter by department)
      status                     str (filter status: present, late, absent, etc.)
    """
    user = _require_admin_or_mentor(request, db)
    params = request.query_params
    start_date, end_date = _parse_date_range(params)

    q = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .join(User, Attendance.user_id == User.id)
        .filter(
            User.role == UserRole.INTERN,
            User.is_deleted == False,
            Attendance.date >= start_date,
            Attendance.date <= end_date,
        )
    )

    if user.is_mentor and not user.is_admin:
        mentor_intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        q = q.filter(Attendance.user_id.in_(mentor_intern_ids))

    intern_id = params.get("user_id") or params.get("intern_id") or params.get("student_id")
    if intern_id and intern_id.isdigit():
        requested_id = int(intern_id)
        if user.is_mentor and not user.is_admin and requested_id not in (get_mentor_intern_ids(db, user.id) or []):
            raise HTTPException(status_code=403, detail="You can only export attendance for your own interns.")
        q = q.filter(Attendance.user_id == requested_id)

    dept = params.get("department", "").strip()
    if dept:
        q = q.filter(User.department.ilike(f"%{dept}%"))

    status_filter = params.get("status", "").strip().lower()
    if status_filter:
        q = q.filter(Attendance.status == status_filter)

    records = q.order_by(Attendance.date.desc(), User.name).all()
    csv_text = export_attendance_csv(records)

    filename = f"attendance_export_{start_date.isoformat()}_to_{end_date.isoformat()}.csv"
    return Response(
        content=csv_text,
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


# ---------------------------------------------------------------------------
# Endpoint 4: GET /api/admin/students/search  (Search overview with date filter)
# ---------------------------------------------------------------------------

@router.get("/search")
@router.get("/overview/search")
async def search_student_overview(request: Request, db: DbSession):
    """
    Search students with custom from_date/to_date attendance overview window (admin or mentor).

    Query params:
      q / search                 str (search term across name, email, department)
      from_date / start / from   YYYY-MM-DD (default: 30 days ago)
      to_date / end / to         YYYY-MM-DD (default: today)
      month                      YYYY-MM (overrides from/to date)
      department                 str (filter by department)
      is_active                  str ("true" or "false")
      page                       int (default 1)
      page_size                  int (default 20, max 200)
      sort                       str ("name" | "joining_date" | "attendance_rate")
    """
    user = _require_admin_or_mentor(request, db)
    params = request.query_params
    start_date, end_date = _parse_date_range(params)

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = min(max(1, int(params.get("page_size", PAGE_SIZE))), 200)
    except ValueError:
        page_size = PAGE_SIZE

    q_term = (params.get("q") or params.get("search") or "").strip()
    q = db.query(User).filter(User.role == UserRole.INTERN, User.is_deleted == False)

    if user.is_mentor and not user.is_admin:
        mentor_intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        q = q.filter(User.id.in_(mentor_intern_ids))

    if q_term:
        like = f"%{q_term}%"
        q = q.filter(User.name.ilike(like) | User.email.ilike(like) | User.department.ilike(like))

    dept = params.get("department", "").strip()
    if dept:
        q = q.filter(User.department.ilike(f"%{dept}%"))

    is_active_raw = params.get("is_active", "").strip().lower()
    if is_active_raw in ("true", "1"):
        q = q.filter(User.is_active == True)
    elif is_active_raw in ("false", "0"):
        q = q.filter(User.is_active == False)

    sort = params.get("sort", "name").strip().lower()
    if sort == "joining_date":
        q = q.order_by(case((User.joining_date.is_(None), 1), else_=0), User.joining_date.desc(), User.name)
    else:
        q = q.order_by(User.name)

    total = q.count()
    total_pages = max(1, (total + page_size - 1) // page_size)
    interns = q.offset((page - 1) * page_size).limit(page_size).all()

    mentor_ids = {u.mentor_id for u in interns if u.mentor_id}
    mentor_map = {}
    if mentor_ids:
        mentors = db.query(User.id, User.name).filter(User.id.in_(mentor_ids)).all()
        mentor_map = {m.id: m.name for m in mentors}

    students = []
    for u in interns:
        students.append({
            "id": u.id,
            "name": u.name,
            "email": u.email,
            "department": u.department,
            "phone": u.phone,
            "job_title": u.job_title,
            "is_active": u.is_active,
            "joining_date": u.joining_date.isoformat() if u.joining_date else None,
            "mentor_id": u.mentor_id,
            "mentor_name": mentor_map.get(u.mentor_id) if u.mentor_id else None,
            "created_at": isoformat_utc(u.created_at),
            "active_projects": _active_project_count(db, u.id),
            "attendance_overview": _student_overview(db, u, start_date=start_date, end_date=end_date),
        })

    return {
        "students": students,
        "date_range": {
            "start": start_date.isoformat(),
            "end": end_date.isoformat(),
        },
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
        "filters": {
            "search": q_term or None,
            "department": dept or None,
            "is_active": is_active_raw or None,
            "sort": sort,
            "start": start_date.isoformat(),
            "end": end_date.isoformat(),
        },
    }


# ---------------------------------------------------------------------------
# Endpoint 5: GET /api/admin/students/{user_id}/attendance
# ---------------------------------------------------------------------------

@router.get("/{user_id}/attendance")
async def student_attendance(user_id: int, request: Request, db: DbSession):
    """
    Full paginated attendance for one intern with date filters (admin or mentor).

    Query params:
      from_date / start / from   YYYY-MM-DD inclusive start (default: 30 days ago)
      to_date / end / to         YYYY-MM-DD inclusive end   (default: today)
      month                      YYYY-MM    overrides start/end to full month
      status                     str        present|late|half_day|absent|on_leave|excused
      page                       int        default 1
      page_size                  int        default 31, max 10000
    """
    user = _require_admin_or_mentor(request, db)

    if user.is_mentor and not user.is_admin:
        mentor_intern_ids = get_mentor_intern_ids(db, user.id)
        if user_id not in mentor_intern_ids:
            raise HTTPException(status_code=403, detail="You can only view attendance for your own interns.")

    student = db.get(User, user_id)
    if not student or student.is_deleted:
        raise HTTPException(status_code=404, detail="User not found.")
    if student.role != UserRole.INTERN:
        raise HTTPException(status_code=400, detail="This endpoint is only for intern users.")

    params = request.query_params
    start_date, end_date = _parse_date_range(params)

    status_filter = params.get("status", "").strip().lower() or None
    valid_statuses = {"present", "late", "half_day", "absent", "on_leave", "excused"}
    if status_filter and status_filter not in valid_statuses:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid status. Choose from: {', '.join(sorted(valid_statuses))}.",
        )

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = min(max(1, int(params.get("page_size", 31))), REPORT_MAX_PAGE_SIZE)
    except ValueError:
        page_size = 31

    # Paginated records
    q = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter(
            Attendance.user_id == user_id,
            Attendance.date >= start_date,
            Attendance.date <= end_date,
        )
    )
    if status_filter:
        q = q.filter(Attendance.status == status_filter)
    q = q.order_by(Attendance.date.desc())

    monthly_summary = _monthly_summary_for_user(db, user_id, start_date, end_date)

    total = q.count()
    records = q.offset((page - 1) * page_size).limit(page_size).all()
    total_pages = max(1, (total + page_size - 1) // page_size)

    # Full window totals
    all_rows = (
        db.query(Attendance.status, Attendance.hours_worked)
        .filter(
            Attendance.user_id == user_id,
            Attendance.date >= start_date,
            Attendance.date <= end_date,
        )
        .all()
    )
    totals = {
        "present": 0, "late": 0, "half_day": 0,
        "absent": 0, "on_leave": 0, "excused": 0,
        "total_hours": 0.0,
        "total_days": len(all_rows),
    }
    for row in all_rows:
        if row.status in totals:
            totals[row.status] += 1
        if row.hours_worked:
            totals["total_hours"] += float(row.hours_worked)
    totals["total_hours"] = round(totals["total_hours"], 2)
    attended = totals["present"] + totals["late"] + totals["half_day"]
    totals["attended"] = attended
    totals["attendance_rate"] = (
        round((attended / totals["total_days"]) * 100, 1) if totals["total_days"] else 0.0
    )

    mentor_name = None
    if student.mentor_id:
        mentor = db.get(User, student.mentor_id)
        mentor_name = mentor.name if mentor else None

    return {
        "student": {
            "id": student.id,
            "name": student.name,
            "email": student.email,
            "department": student.department,
            "phone": student.phone,
            "job_title": student.job_title,
            "is_active": student.is_active,
            "joining_date": student.joining_date.isoformat() if student.joining_date else None,
            "mentor_id": student.mentor_id,
            "mentor_name": mentor_name,
        },
        "records": [_att_dict(r) for r in records],
        "monthly_summary": monthly_summary,
        "totals": totals,
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
        "filters": {
            "start": start_date.isoformat(),
            "end": end_date.isoformat(),
            "month": params.get("month") or None,
            "status": status_filter,
        },
    }


# ---------------------------------------------------------------------------
# Alias Router for /api/admin/attendance
# ---------------------------------------------------------------------------
admin_attendance_router = APIRouter(prefix="/api/admin/attendance", tags=["Admin - Attendance Management"])
admin_attendance_router.add_api_route("/today", today_attendance, methods=["GET"], summary="Admin Today Attendance")
admin_attendance_router.add_api_route("/export", export_admin_attendance, methods=["GET"], summary="Admin Export Attendance CSV")
admin_attendance_router.add_api_route("/export.csv", export_admin_attendance, methods=["GET"], summary="Admin Export Attendance CSV File")
admin_attendance_router.add_api_route("/search", search_student_overview, methods=["GET"], summary="Admin Search Attendance Overview")


# ---------------------------------------------------------------------------
# Mentor Routers for /api/mentor/students and /api/mentor/attendance
# ---------------------------------------------------------------------------
mentor_router = APIRouter(prefix="/api/mentor/students", tags=["Mentor - Student Attendance"])
mentor_router.add_api_route("", list_students, methods=["GET"], summary="Mentor Students List")
mentor_router.add_api_route("/today", today_attendance, methods=["GET"], summary="Mentor Today Attendance")
mentor_router.add_api_route("/export", export_admin_attendance, methods=["GET"], summary="Mentor Export Attendance CSV")
mentor_router.add_api_route("/export.csv", export_admin_attendance, methods=["GET"], summary="Mentor Export Attendance CSV File")
mentor_router.add_api_route("/search", search_student_overview, methods=["GET"], summary="Mentor Search Overview")
mentor_router.add_api_route("/overview/search", search_student_overview, methods=["GET"], summary="Mentor Search Overview Alias")
mentor_router.add_api_route("/{user_id}/attendance", student_attendance, methods=["GET"], summary="Mentor Student Attendance Detail")

mentor_attendance_router = APIRouter(prefix="/api/mentor/attendance", tags=["Mentor - Attendance Management"])
mentor_attendance_router.add_api_route("/today", today_attendance, methods=["GET"], summary="Mentor Today Attendance Alias")
mentor_attendance_router.add_api_route("/export", export_admin_attendance, methods=["GET"], summary="Mentor Export Attendance CSV Alias")
mentor_attendance_router.add_api_route("/export.csv", export_admin_attendance, methods=["GET"], summary="Mentor Export Attendance CSV File Alias")
mentor_attendance_router.add_api_route("/search", search_student_overview, methods=["GET"], summary="Mentor Search Attendance Overview Alias")
