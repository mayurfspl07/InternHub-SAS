"""Admin-only student attendance management APIs.

Two endpoints:
  GET /api/admin/students
      Paginated list of all interns with attendance overview stats.

  GET /api/admin/students/{user_id}/attendance
      Full attendance records for a specific intern, filterable by date range,
      with monthly summary and user profile info.

Both endpoints require admin role (admin or superadmin).
"""
from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import case, func
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
from utils import isoformat_utc, local_today, month_range

router = APIRouter(prefix="/api/admin/students", tags=["Admin - Student Attendance"])
DbSession = Annotated[Session, Depends(get_db)]

PAGE_SIZE = 20
REPORT_MAX_PAGE_SIZE = 10_000


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
        "check_in_photo_url": f"/api/attendance/{r.id}/photo/checkin" if r.check_in_photo else None,
        "check_out_photo_url": (
            f"/api/attendance/{r.id}/photo/checkout"
            if show_checkout and r.check_out_photo
            else None
        ),
    }


def _student_overview(db: Session, u: User, window_days: int = 30) -> dict:
    since = local_today() - timedelta(days=window_days - 1)
    rows = (
        db.query(Attendance)
        .filter(Attendance.user_id == u.id, Attendance.date >= since)
        .all()
    )
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
        "window_days": window_days,
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


# ---------------------------------------------------------------------------
# Endpoint 1: GET /api/admin/students
# ---------------------------------------------------------------------------

@router.get("")
async def list_students(request: Request, db: DbSession):
    """
    Admin-only: paginated intern list with attendance overview.

    Query params:
      page        int   default 1
      page_size   int   default 20, max 200
      search      str   filter by name / email / department (case-insensitive)
      is_active   str   "true" or "false"
      sort        str   "name" (default) | "joining_date"
      window_days int   trailing calendar days for attendance stats (default 30, max 365)
    """
    admin = get_optional_user(request, db)
    if not admin or admin.role not in (UserRole.ADMIN, UserRole.SUPERADMIN):
        raise HTTPException(status_code=403, detail="Admin access required.")

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

    search = params.get("search", "").strip()
    if search:
        like = f"%{search}%"
        q = q.filter(User.name.ilike(like) | User.email.ilike(like) | User.department.ilike(like))

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
            "is_active": is_active_raw or None,
            "sort": sort,
            "window_days": window_days,
        },
    }


# ---------------------------------------------------------------------------
# Endpoint 2: GET /api/admin/students/{user_id}/attendance
# ---------------------------------------------------------------------------

@router.get("/{user_id}/attendance")
async def student_attendance(user_id: int, request: Request, db: DbSession):
    """
    Admin-only: full paginated attendance for one intern with date filters.

    Query params:
      start       YYYY-MM-DD   inclusive start (default: 30 days ago)
      end         YYYY-MM-DD   inclusive end   (default: today)
      month       YYYY-MM      overrides start/end to the full calendar month
      status      str          present|late|half_day|absent|on_leave|excused
      page        int          default 1
      page_size   int          default 31, max 10000

    Response:
      student         profile
      records         paginated attendance rows (full detail incl. photos, GPS)
      monthly_summary per-month aggregate over the date window
      totals          aggregate counts + hours over the full window (ignores status filter)
      page / total / filters
    """
    admin = get_optional_user(request, db)
    if not admin or admin.role not in (UserRole.ADMIN, UserRole.SUPERADMIN):
        raise HTTPException(status_code=403, detail="Admin access required.")

    student = db.get(User, user_id)
    if not student or student.is_deleted:
        raise HTTPException(status_code=404, detail="User not found.")
    if student.role != UserRole.INTERN:
        raise HTTPException(status_code=400, detail="This endpoint is only for intern users.")

    params = request.query_params
    today = local_today()

    month_param = params.get("month", "").strip()
    start_s = params.get("start", "").strip()
    end_s = params.get("end", "").strip()

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
                raise HTTPException(status_code=422, detail="Invalid start date. Use YYYY-MM-DD.")
        else:
            start_date = today - timedelta(days=29)

        if end_s:
            try:
                end_date = date.fromisoformat(end_s)
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid end date. Use YYYY-MM-DD.")
        else:
            end_date = today

    if start_date > end_date:
        raise HTTPException(status_code=422, detail="start must be on or before end.")

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

    # --- Paginated records (optionally status-filtered) ---
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

    # Monthly summary is always computed over the full date window (not filtered by status)
    monthly_summary = _monthly_summary_for_user(db, user_id, start_date, end_date)

    total = q.count()
    records = q.offset((page - 1) * page_size).limit(page_size).all()
    total_pages = max(1, (total + page_size - 1) // page_size)

    # Aggregate totals over full window (not affected by status filter)
    all_rows = (
        db.query(Attendance.status, Attendance.hours_worked)
        .filter(
            Attendance.user_id == user_id,
            Attendance.date >= start_date,
            Attendance.date <= end_date,
        )
        .all()
    )
    totals: dict = {
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
            "month": month_param or None,
            "status": status_filter,
        },
    }
