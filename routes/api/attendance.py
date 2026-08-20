"""JSON attendance endpoints."""
import asyncio
from datetime import date, datetime, time
from typing import Annotated

from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Request, UploadFile
from sqlalchemy import and_, case, func
from sqlalchemy.orm import Session, joinedload

import os
from attendance_photos import save_attendance_photo, photo_abs_path
from utils import local_now, local_today, today_str
from geocoding import reverse_geocode
from config import Config
from database import get_db
from dependencies import get_optional_user
from models import Attendance, AttendanceAuditLog, AttendanceStatus, User, UserRole
from utils import (
    apply_checkout_to_record,
    auto_checkout_missed_sessions,
    export_attendance_csv,
    fmt_dt,
    get_mentor_intern_ids,
    is_checkin_blocked,
    local_now,
    local_today,
    log_attendance_edit,
    mentor_can_edit_intern,
    month_range,
    recalculate_attendance_hours_and_status,
    record_audit,
    today_str,
    isoformat_utc,
)
from fastapi.responses import FileResponse, Response
from routes.api.schemas import AttendanceEditRequest, ManualAttendanceRequest, get_payload

router = APIRouter(prefix="/api/attendance", tags=["Attendance"])
DbSession = Annotated[Session, Depends(get_db)]

PAGE_SIZE = 30
REPORT_MAX_PAGE_SIZE = 10000


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
            f"/api/attendance/{r.id}/photo/checkout" if show_checkout and r.check_out_photo else None
        ),
    }


def _normalize_optional_param(value: str | None) -> str | None:
    """Treat missing/blank/null-like query values as omitted."""
    if value is None:
        return None
    cleaned = str(value).strip()
    if not cleaned or cleaned.lower() in ("null", "undefined", "none"):
        return None
    return cleaned


def _year_month_expr(db: Session):
    """Dialect-aware YYYY-MM expression for attendance.date."""
    if db.get_bind().dialect.name == "sqlite":
        return func.strftime("%Y-%m", Attendance.date)
    return func.date_format(Attendance.date, "%Y-%m")


def _monthly_summary(db: Session, attendance_query) -> list[dict]:
    """Aggregate all matching attendance rows by intern and calendar month."""
    year_month = _year_month_expr(db)
    present_statuses = (
        AttendanceStatus.PRESENT,
        AttendanceStatus.LATE,
        AttendanceStatus.HALF_DAY,
    )
    rows = (
        attendance_query.with_entities(
            Attendance.user_id,
            year_month.label("year_month"),
            func.sum(
                case((Attendance.status == AttendanceStatus.PRESENT, 1), else_=0)
            ).label("present"),
            func.sum(
                case((Attendance.status == AttendanceStatus.LATE, 1), else_=0)
            ).label("late"),
            func.sum(
                case((Attendance.status == AttendanceStatus.HALF_DAY, 1), else_=0)
            ).label("half_day"),
            func.sum(
                case((Attendance.status == AttendanceStatus.ABSENT, 1), else_=0)
            ).label("absent"),
            func.sum(
                case((Attendance.status.in_(present_statuses), 1), else_=0)
            ).label("attended"),
            func.count(Attendance.id).label("total_days"),
        )
        .group_by(Attendance.user_id, year_month)
        .order_by(Attendance.user_id, year_month)
        .all()
    )
    summary = []
    for row in rows:
        total_days = int(row.total_days or 0)
        attended = int(row.attended or 0)
        present_rate = round((attended / total_days) * 100, 1) if total_days else 0.0
        summary.append(
            {
                "user_id": row.user_id,
                "year_month": row.year_month,
                "present": int(row.present or 0),
                "late": int(row.late or 0),
                "half_day": int(row.half_day or 0),
                "absent": int(row.absent or 0),
                "present_rate": present_rate,
                "total_days": total_days,
            }
        )
    return summary


def _can_edit_attendance(db: Session, editor: User, record: Attendance) -> bool:
    if editor.is_admin:
        return True
    if editor.is_mentor:
        return mentor_can_edit_intern(db, editor, record.user_id)
    return False


def _parse_time_on_date(day: date, value: str) -> datetime:
    """Parse HH:MM or ISO datetime onto the attendance date."""
    value = value.strip()
    if "T" in value:
        dt = datetime.fromisoformat(value.replace("Z", ""))
        if dt.date() != day:
            raise ValueError(f"Datetime date {dt.date()} does not match attendance date {day}")
        return dt
    parts = value.split(":")
    if len(parts) < 2:
        raise ValueError("Invalid time")
    hour, minute = int(parts[0]), int(parts[1])
    return datetime.combine(day, time(hour=hour, minute=minute))


@router.get("/today")
async def today_status(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    today = local_today()
    record = db.query(Attendance).filter_by(user_id=user.id, date=today).first()
    return {"record": _att_dict(record) if record else None, "today": today.isoformat()}


@router.post("/check-in")
async def check_in(
    request: Request,
    db: DbSession,
    photo: UploadFile = File(...),
    lat: float = Form(...),
    lng: float = Form(...),
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    today = local_today()
    if db.query(Attendance).filter_by(user_id=user.id, date=today).first():
        raise HTTPException(status_code=409, detail="Already checked in today.")
    now = local_now()
    if is_checkin_blocked(now):
        raise HTTPException(
            status_code=422,
            detail="Check-in is closed after 8:00 PM. Your shift runs 10:00 AM – 7:00 PM.",
        )
    content = await photo.read()
    try:
        photo_path = save_attendance_photo(user.id, user.name, today, "checkin", content)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    address = await asyncio.to_thread(reverse_geocode, lat, lng)

    from utils import determine_attendance_status

    status = determine_attendance_status(now)
    record = Attendance(
        user_id=user.id,
        date=today,
        check_in=now,
        status=status,
        checkout_missed=False,
        checkout_source=None,
        check_in_lat=lat,
        check_in_lng=lng,
        check_in_address=address,
        check_in_photo=photo_path,
    )
    db.add(record)
    record_audit(db, user, "attendance.checkin", "checked in at", fmt_dt(now))
    db.commit()
    db.refresh(record)
    return _att_dict(record)


@router.post("/check-out")
async def check_out(
    request: Request,
    db: DbSession,
    photo: UploadFile = File(...),
    lat: float = Form(...),
    lng: float = Form(...),
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    today = local_today()
    record = db.query(Attendance).filter_by(user_id=user.id, date=today).first()
    if not record:
        raise HTTPException(status_code=404, detail="No check-in found for today.")
    if record.check_out:
        raise HTTPException(status_code=409, detail="Already checked out today.")
    content = await photo.read()
    try:
        photo_path = save_attendance_photo(user.id, user.name, today, "checkout", content)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    address = await asyncio.to_thread(reverse_geocode, lat, lng)

    now = local_now()
    apply_checkout_to_record(record, now, source="manual")
    record.check_out_lat = lat
    record.check_out_lng = lng
    record.check_out_address = address
    record.check_out_photo = photo_path
    record_audit(db, user, "attendance.checkout", "checked out at", fmt_dt(now))
    db.commit()
    db.refresh(record)
    return _att_dict(record)


@router.get("/{attendance_id}/photo/{kind}")
async def get_attendance_photo(attendance_id: int, kind: str, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    if kind not in ("checkin", "checkout"):
        raise HTTPException(status_code=404)
    record = db.get(Attendance, attendance_id)
    if not record:
        raise HTTPException(status_code=404)
    if record.user_id != user.id and not user.is_admin:
        if not user.is_mentor or not mentor_can_edit_intern(db, user, record.user_id):
            raise HTTPException(status_code=403)
    rel_path = record.check_in_photo if kind == "checkin" else record.check_out_photo
    abs_path = photo_abs_path(rel_path) if rel_path else None
    if not abs_path:
        raise HTTPException(status_code=404, detail="No photo for this record.")
    return FileResponse(
        abs_path,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=86400"},
    )


@router.get("/history")
async def history(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    params = request.query_params
    # None means "unfiltered" (admin all-intern view); default to own records for interns.
    user_id: int | None = user.id if user.is_intern else None
    if user.role in ("admin", "mentor"):
        target_id = params.get("user_id")
        if target_id and target_id.isdigit():
            requested_id = int(target_id)
            # Mentors can only view attendance for their own interns
            if user.is_mentor:
                allowed_ids = get_mentor_intern_ids(db, user.id)
                if requested_id not in allowed_ids:
                    raise HTTPException(status_code=403, detail="You can only view attendance for your own interns.")
            user_id = requested_id
        elif user.is_mentor and user_id is None:
            # Mentor without user_id — default to their own scoped interns (show first intern or require param)
            user_id = user.id  # fallback to own record so the response isn’t unexpectedly huge
        # Admins without user_id: user_id stays None → query all interns below

    month = params.get("month", today_str()[:7])
    try:
        year, m = int(month[:4]), int(month[5:7])
    except (ValueError, IndexError):
        year, m = int(today_str()[:4]), int(today_str()[5:7])
    start, end = month_range(year, m)

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = int(params.get("page_size", PAGE_SIZE))
    except ValueError:
        page_size = PAGE_SIZE
    # A calendar month has at most 31 rows per user (UniqueConstraint on user_id+date),
    # so cap generously rather than at PAGE_SIZE — callers that want the full month’s
    # records in one page (e.g. monthly hour totals, the calendar view) rely on this.
    page_size = min(max(1, page_size), REPORT_MAX_PAGE_SIZE)

    from models import UserRole as _UserRole
    q = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter(and_(Attendance.date >= start, Attendance.date <= end))
    )
    if user_id is not None:
        q = q.filter(Attendance.user_id == user_id)
    else:
        # Admin all-interns view — filter to intern role only
        from models import User as _User
        q = q.join(_User, Attendance.user_id == _User.id).filter(_User.role == _UserRole.INTERN)
    q = q.order_by(Attendance.date.desc())

    total = q.count()
    records = q.offset((page - 1) * page_size).limit(page_size).all()
    total_pages = max(1, (total + page_size - 1) // page_size)
    return {
        "records": [_att_dict(r) for r in records],
        "page": page,
        "total_pages": total_pages,
        "total": total,
        "month": f"{year:04d}-{m:02d}",
    }


@router.get("/report")
async def report(request: Request, db: DbSession):
    """Attendance overview for staff.

    Omitting start/end returns all-time records for visible interns.
    Providing start and/or end applies inclusive date filtering.
    """
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    params = request.query_params
    intern_id_raw = _normalize_optional_param(params.get("intern_id"))
    intern_id = int(intern_id_raw) if intern_id_raw and intern_id_raw.isdigit() else None
    start_s = _normalize_optional_param(params.get("start"))
    end_s = _normalize_optional_param(params.get("end"))

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = int(params.get("page_size", PAGE_SIZE))
    except ValueError:
        page_size = PAGE_SIZE
    # Frontend overview requests large pages (e.g. 5000) for all-time grouping.
    page_size = min(max(1, page_size), REPORT_MAX_PAGE_SIZE)

    visible_intern_ids: list[int] | None = None
    if user.is_mentor and not user.is_admin:
        visible_intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        if intern_id is not None and intern_id not in visible_intern_ids:
            raise HTTPException(
                status_code=403,
                detail="You can only view attendance for your own interns.",
            )

    def _scoped_query():
        query = (
            db.query(Attendance)
            .join(User, Attendance.user_id == User.id)
            .filter(User.role == UserRole.INTERN)
        )
        if visible_intern_ids is not None:
            query = query.filter(Attendance.user_id.in_(visible_intern_ids))
        if intern_id:
            query = query.filter(Attendance.user_id == intern_id)
        # Only apply date bounds when explicitly provided — no last-N-days default.
        if start_s:
            try:
                query = query.filter(Attendance.date >= date.fromisoformat(start_s))
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid start date.")
        if end_s:
            try:
                query = query.filter(Attendance.date <= date.fromisoformat(end_s))
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid end date.")
        return query

    # Full-scope month aggregates (not limited to the current page).
    monthly_summary = _monthly_summary(db, _scoped_query())

    q = _scoped_query().options(joinedload(Attendance.user))
    q = q.order_by(Attendance.date.desc(), User.name)
    total = q.count()
    records = q.offset((page - 1) * page_size).limit(page_size).all()
    total_pages = max(1, (total + page_size - 1) // page_size) if total else 1

    interns_q = db.query(User).filter_by(role=UserRole.INTERN, is_active=True)
    if visible_intern_ids is not None:
        interns_q = interns_q.filter(User.id.in_(visible_intern_ids))
    interns = interns_q.order_by(User.name).all()
    return {
        "records": [_att_dict(r) for r in records],
        "interns": [
            {
                "id": u.id,
                "name": u.name,
                "email": u.email,
                "department": u.department,
                "joining_date": u.joining_date.isoformat() if u.joining_date else None,
            }
            for u in interns
        ],
        "monthly_summary": monthly_summary,
        "filters": {"intern_id": intern_id, "start": start_s, "end": end_s},
        "page": page,
        "page_size": page_size,
        "total_pages": total_pages,
        "total": total,
    }


@router.get("/export.csv")
async def export_csv(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    params = request.query_params
    intern_id = params.get("intern_id")
    intern_id = int(intern_id) if intern_id and intern_id.isdigit() else None
    start_s = params.get("start")
    end_s = params.get("end")
    q = db.query(Attendance).options(joinedload(Attendance.user))
    if user.is_intern:
        q = q.filter(Attendance.user_id == user.id)
    elif intern_id:
        q = q.filter(Attendance.user_id == intern_id)
    if start_s:
        try:
            q = q.filter(Attendance.date >= date.fromisoformat(start_s))
        except ValueError:
            pass
    if end_s:
        try:
            q = q.filter(Attendance.date <= date.fromisoformat(end_s))
        except ValueError:
            pass
    if user.is_mentor:
        ids = get_mentor_intern_ids(db, user.id) or [-1]
        # Enforce access: mentor may not export another mentor's intern
        if intern_id is not None and intern_id not in ids:
            raise HTTPException(status_code=403, detail="You can only export attendance for your own interns.")
        q = q.filter(Attendance.user_id.in_(ids))
    records = q.order_by(Attendance.date.desc()).all()
    csv_text = export_attendance_csv(records)
    filename = f"attendance_{local_today().isoformat()}.csv"
    return Response(
        content=csv_text,
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


@router.post("/auto-checkout")
async def trigger_auto_checkout(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    # Record the audit entry before calling auto-checkout so both are committed
    # together in the single db.commit() below (avoids a double-commit).
    count = auto_checkout_missed_sessions(db, commit=False)
    record_audit(
        db,
        user,
        "attendance.auto_checkout",
        "triggered attendance auto-checkout",
        f"{count} record(s)",
    )
    db.commit()
    return {"count": count, "message": f"Auto check-out applied to {count} missed record(s)."}


@router.put("/{record_id}")
async def edit_attendance(record_id: int, request: Request, db: DbSession, data: AttendanceEditRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    record = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter_by(id=record_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="Attendance record not found.")
    if not _can_edit_attendance(db, user, record):
        raise HTTPException(status_code=403, detail="You cannot edit this intern's attendance.")

    if data is not None:
        raw_data = data.model_dump(exclude_unset=True)
    else:
        try:
            raw_data = await request.json()
        except Exception:
            raw_data = {}

    reason = str(raw_data.get("reason", "")).strip()
    if not reason:
        raise HTTPException(status_code=422, detail="A reason is required for attendance edits.")

    status_override = raw_data.get("status_override", "__unset__")
    clearing_override = False
    if status_override == "__unset__":
        status_override = None
    elif status_override in ("", None):
        clearing_override = user.is_admin
        status_override = None
    else:
        status_override = str(status_override).strip().lower()
        if status_override not in ("on_leave", "excused"):
            raise HTTPException(
                status_code=422,
                detail="Status override must be on_leave or excused.",
            )

    if status_override and not user.is_admin:
        raise HTTPException(status_code=403, detail="Only admins can set attendance status overrides.")
    if clearing_override and not user.is_admin:
        raise HTTPException(status_code=403, detail="Only admins can clear attendance status overrides.")

    changes: list[tuple[str, str | None, str | None]] = []
    old_status = record.status

    if "check_in" in raw_data and raw_data["check_in"]:
        try:
            new_in = _parse_time_on_date(record.date, str(raw_data["check_in"]))
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid check-in time.")
        old = record.check_in.strftime("%H:%M") if record.check_in else None
        new = new_in.strftime("%H:%M")
        if old != new:
            changes.append(("check_in", old, new))
            record.check_in = new_in

    if "check_out" in raw_data:
        raw = raw_data["check_out"]
        if raw in (None, "", "clear"):
            if record.check_out:
                old = record.check_out.strftime("%H:%M")
                changes.append(("check_out", old, None))
            record.check_out = None
            record.checkout_missed = False
            record.checkout_source = None
            record.hours_worked = None
        else:
            try:
                new_out = _parse_time_on_date(record.date, str(raw))
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid check-out time.")
            if not record.check_in:
                raise HTTPException(status_code=422, detail="Cannot set check-out: record has no check-in time.")
            if new_out <= record.check_in:
                raise HTTPException(status_code=422, detail="Check-out must be after check-in.")
            old = record.check_out.strftime("%H:%M") if record.check_out and not record.checkout_missed else None
            new = new_out.strftime("%H:%M")
            if old != new:
                changes.append(("check_out", old, new))
            record.check_out = new_out
            record.checkout_missed = False
            record.checkout_source = "manual"

    if not changes and not status_override and not clearing_override:
        raise HTTPException(status_code=422, detail="No changes to save.")

    times_changed = any(c[0] in ("check_in", "check_out") for c in changes)
    if times_changed or clearing_override:
        recalculate_attendance_hours_and_status(record)

    if status_override and user.is_admin:
        if old_status != status_override:
            changes = [c for c in changes if c[0] != "status"]
            changes.append(("status", old_status, status_override))
        record.status = status_override
    elif (times_changed or clearing_override) and record.status != old_status:
        changes.append(("status", old_status, record.status))

    for field_name, old_val, new_val in changes:
        log_attendance_edit(db, record.id, user, field_name, old_val, new_val, reason)

    intern_name = record.user.name if record.user else str(record.user_id)
    record_audit(
        db,
        user,
        "attendance.edit",
        f"edited attendance for {intern_name}",
        reason,
        affected_user_id=record.user_id,
    )
    db.commit()
    db.refresh(record)
    return _att_dict(record)


@router.delete("/{record_id}")
async def delete_attendance(record_id: int, request: Request, db: DbSession):
    """Permanently remove a wrong/duplicate attendance record (admin, or mentor for their own interns)."""
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    record = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter_by(id=record_id)
        .first()
    )
    if not record:
        raise HTTPException(status_code=404, detail="Attendance record not found.")
    if not _can_edit_attendance(db, user, record):
        raise HTTPException(status_code=403, detail="You cannot delete this intern's attendance.")

    try:
        data = await request.json()
    except Exception:
        data = {}
    reason = str(data.get("reason", "")).strip()
    if not reason:
        raise HTTPException(status_code=422, detail="A reason is required to delete an attendance record.")

    intern_name = record.user.name if record.user else str(record.user_id)
    record_audit(
        db,
        user,
        "attendance.delete",
        f"deleted attendance record for {intern_name} ({record.date.isoformat()})",
        reason,
        affected_user_id=record.user_id,
    )
    db.delete(record)
    db.commit()
    return {"ok": True}


@router.get("/{record_id}/audit")
async def attendance_audit_log(record_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    record = db.get(Attendance, record_id)
    if not record:
        raise HTTPException(status_code=404)
    if not _can_edit_attendance(db, user, record):
        raise HTTPException(status_code=403)

    logs = (
        db.query(AttendanceAuditLog)
        .filter_by(attendance_id=record_id)
        .order_by(AttendanceAuditLog.created_at.desc())
        .all()
    )
    return {
        "logs": [
            {
                "id": log.id,
                "editor_id": log.editor_id,
                "editor_name": log.editor_name,
                "field_name": log.field_name,
                "old_value": log.old_value,
                "new_value": log.new_value,
                "reason": log.reason,
                "created_at": isoformat_utc(log.created_at),
            }
            for log in logs
        ]
    }


@router.post("/manual")
async def create_attendance_manual(request: Request, db: DbSession, data: ManualAttendanceRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")
    
    if user.role not in (UserRole.ADMIN, UserRole.SUPERADMIN, UserRole.MENTOR) and not user.is_platform_admin:
        raise HTTPException(status_code=403, detail="Permission denied.")

    payload = await get_payload(request, data)
    user_id = payload.get("user_id")
    date_str = payload.get("date")
    check_in_str = payload.get("check_in")
    check_out_str = payload.get("check_out")
    status_override = payload.get("status_override")
    reason = payload.get("reason")

    if user_id is None:
        raise HTTPException(status_code=422, detail="user_id is required.")
    try:
        user_id = int(user_id)
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Invalid user_id.")

    if user.role == UserRole.MENTOR:
        if not mentor_can_edit_intern(db, user, user_id):
            raise HTTPException(status_code=403, detail="You do not have permission to manage this intern.")

    intern = db.get(User, user_id)
    if not intern or intern.is_deleted:
        raise HTTPException(status_code=404, detail="User not found.")
    if intern.role != UserRole.INTERN:
        raise HTTPException(status_code=400, detail="Target user is not an intern.")

    if not date_str:
        raise HTTPException(status_code=422, detail="date is required.")
    try:
        parsed_date = date.fromisoformat(str(date_str).strip())
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid date format. Use YYYY-MM-DD.")

    if not check_in_str:
        raise HTTPException(status_code=422, detail="check_in time is required.")
    try:
        check_in_time = datetime.strptime(str(check_in_str).strip(), "%H:%M").time()
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid check-in time format. Use HH:MM.")

    check_in_dt = datetime.combine(parsed_date, check_in_time)

    check_out_dt = None
    if check_out_str:
        try:
            check_out_time = datetime.strptime(str(check_out_str).strip(), "%H:%M").time()
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid check-out time format. Use HH:MM.")
        check_out_dt = datetime.combine(parsed_date, check_out_time)
        if check_out_dt <= check_in_dt:
            raise HTTPException(status_code=422, detail="Check-out time must be after check-in time.")

    if status_override:
        status_override = str(status_override).strip().lower()
        if status_override not in ("on_leave", "excused"):
            raise HTTPException(status_code=422, detail="Status override must be 'on_leave' or 'excused'.")

    if not reason or not str(reason).strip():
        raise HTTPException(status_code=422, detail="reason is required and cannot be empty.")
    reason = str(reason).strip()

    existing = db.query(Attendance).filter_by(user_id=user_id, date=parsed_date).first()
    if existing:
        raise HTTPException(status_code=409, detail="Attendance record already exists for this date.")

    record = Attendance(
        user_id=user_id,
        date=parsed_date,
        check_in=check_in_dt,
        check_out=check_out_dt,
        checkout_missed=False,
        checkout_source="manual" if check_out_dt else None,
    )
    db.add(record)
    db.flush()

    recalculate_attendance_hours_and_status(record)

    if status_override:
        if not user.is_admin:
            raise HTTPException(status_code=403, detail="Only admins can apply status overrides.")
        record.status = status_override

    log_attendance_edit(db, record.id, user, "check_in", None, str(check_in_str).strip(), reason)
    if check_out_dt:
        log_attendance_edit(db, record.id, user, "check_out", None, str(check_out_str).strip(), reason)
    log_attendance_edit(db, record.id, user, "status", None, record.status, reason)

    record_audit(
        db,
        user,
        "attendance.create",
        f"created attendance for {intern.name}",
        reason,
        affected_user_id=user_id,
    )

    db.commit()
    return _att_dict(record)

