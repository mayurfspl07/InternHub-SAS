"""Utility helpers: dates, CSV, attendance logic, CSRF, rate limiting, notifications."""
import csv
import hmac
import io
import secrets
import time as _time_module  # stdlib time module; renamed to avoid clash with datetime.time
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo

from config import Config

if TYPE_CHECKING:
    from sqlalchemy.orm import Session


# ---------------------------------------------------------------------------
# Date / time helpers
# ---------------------------------------------------------------------------

APP_TZ = ZoneInfo(Config.TIMEZONE)
IST_TZ = ZoneInfo("Asia/Kolkata")


def to_ist(dt: datetime | None) -> datetime | None:
    """Convert a naive local or timezone-aware datetime into IST (Asia/Kolkata)."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=IST_TZ)
    return dt.astimezone(IST_TZ)


def isoformat_ist(
    dt: datetime | None,
    *,
    timespec: str = "seconds",
) -> str | None:
    """Serialize datetime as IST ISO 8601 string (+05:30)."""
    ist = to_ist(dt)
    if ist is None:
        return None
    return ist.isoformat(timespec=timespec)


def fmt_time_ist(dt: datetime | None, use_12h: bool = True) -> str:
    """Format datetime into IST time string, e.g. '10:30 AM' or '10:30'."""
    ist = to_ist(dt)
    if ist is None:
        return ""
    if use_12h:
        res = ist.strftime("%I:%M %p")
        if res.startswith("0"):
            res = res[1:]
        return res
    return ist.strftime("%H:%M")


def local_now() -> datetime:
    """Naive wall-clock 'now' in the app's business timezone (Config.TIMEZONE).

    Use this — never bare `datetime.now()` — anywhere attendance/shift/day-boundary
    logic needs "the current time". `datetime.now()` returns the *host OS's* local
    time, which differs between a local dev machine and the production server and
    silently shifts "today", late-checkin cutoffs, and month boundaries depending on
    where the process happens to be running.
    """
    return datetime.now(APP_TZ).replace(tzinfo=None)


def local_today() -> date:
    """'Today' in the app's business timezone, independent of the host OS's timezone."""
    return local_now().date()


def today_str() -> str:
    return local_today().isoformat()


def fmt_date(d) -> str:
    if d is None:
        return "—"
    if isinstance(d, str):
        return d
    return d.strftime("%Y-%m-%d")


def fmt_dt(dt) -> str:
    if dt is None:
        return "—"
    return dt.strftime("%Y-%m-%d %H:%M")


def isoformat_utc(
    dt: datetime | None,
    *,
    timespec: str = "microseconds",
    use_z_suffix: bool = True,
) -> str | None:
    """Serialize naive/aware datetimes as UTC ISO 8601 for JSON APIs."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    value = dt.isoformat(timespec=timespec)
    if use_z_suffix:
        return value.replace("+00:00", "Z")
    return value


def fmt_duration(hours: float) -> str:
    if not hours:
        return "—"
    h = int(hours)
    m = int(round((hours - h) * 60))
    return f"{h}h {m}m"


def month_range(year: int, month: int):
    start = date(year, month, 1)
    if month == 12:
        end = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        end = date(year, month + 1, 1) - timedelta(days=1)
    return start, end


# ---------------------------------------------------------------------------
# Attendance helpers
# ---------------------------------------------------------------------------

def _time_on_date(d: date, hour: int, minute: int = 0) -> datetime:
    return datetime.combine(d, datetime.min.time().replace(hour=hour, minute=minute))


def compute_hours_worked(
    check_in: datetime,
    check_out: datetime | None,
    *,
    checkout_missed: bool = False,
) -> float:
    if checkout_missed or not check_out:
        return 0.0
    return round(max(0.0, (check_out - check_in).total_seconds() / 3600), 2)


def is_checkin_blocked(check_in_dt: datetime) -> bool:
    from config import Config
    return check_in_dt.time() >= Config.CHECKIN_BLOCK


def is_late_checkin(check_in_dt: datetime) -> bool:
    from config import Config
    return check_in_dt.time() >= Config.LATE_CUTOFF


def determine_status(
    check_in_time: time,
    hours_worked: Decimal | float,
    checkout_missed: bool,
) -> str:
    """
    Final status after checkout (hours-first priority order):
    1. Missed checkout            → absent  (can't verify work without checkout)
    2. hours > 0, hours < 5       → half_day (showed up but left early)
    3. hours > 0, check-in ≥ 12  → late    (late arrival, even with enough hours)
    4. hours ≥ 7                  → present
    5. 5 ≤ hours < 7              → half_day

    When hours == 0 (no checkout yet — provisional):
    6. check-in ≥ LATE_CUTOFF    → late
    7. otherwise                  → present
    """
    from config import Config

    hw = hours_worked if isinstance(hours_worked, Decimal) else Decimal(str(hours_worked))

    if checkout_missed:
        return "absent"

    if hw > Decimal("0"):
        # Hours are known — use them as primary signal
        if hw < Config.HALF_DAY_HOURS:
            # Showed up but left early → half_day (not absent)
            return "half_day"
        if check_in_time >= Config.NOON_CUTOFF:
            return "late"
        if hw >= Config.FULL_DAY_HOURS:
            return "present"
        return "half_day"

    # No hours yet (no checkout) — provisional status from arrival time only
    if check_in_time >= Config.LATE_CUTOFF:
        return "late"
    return "present"


def resolve_attendance_status(
    check_in: datetime,
    hours: float,
    *,
    checkout_missed: bool = False,
) -> str:
    """Compatibility wrapper — prefer determine_status()."""
    return determine_status(check_in.time(), hours, checkout_missed)


def recalculate_attendance_hours_and_status(record) -> None:
    """Recompute hours_worked and status from check-in/out flags on a record."""
    from models import Attendance

    assert isinstance(record, Attendance)
    if not record.check_in:
        return
    if record.checkout_missed:
        record.hours_worked = 0.0
        record.status = determine_status(record.check_in.time(), Decimal("0"), True)
        return
    if record.check_out:
        hours = compute_hours_worked(record.check_in, record.check_out)
        record.hours_worked = hours
        record.status = determine_status(record.check_in.time(), hours, False)
    else:
        record.hours_worked = None


def apply_checkout_to_record(record, check_out: datetime, *, source: str = "manual") -> None:
    """Update an attendance row after manual or auto checkout."""
    from models import Attendance

    assert isinstance(record, Attendance)
    missed = source == "auto"
    record.check_out = check_out
    record.checkout_source = source
    record.checkout_missed = missed
    if missed:
        record.hours_worked = 0.0
        record.status = "absent"
    else:
        hours = compute_hours_worked(record.check_in, check_out)
        record.hours_worked = hours
        record.status = determine_status(record.check_in.time(), hours, False)


def determine_attendance_status(check_in_dt: datetime) -> str:
    """Provisional status at check-in (finalized at checkout via determine_status)."""
    return "late" if is_late_checkin(check_in_dt) else "present"


def finalize_checkout_status(check_in: datetime, check_out: datetime, half_day_hours: int = 4) -> str:
    """Legacy helper — prefer resolve_attendance_status."""
    hours = compute_hours_worked(check_in, check_out)
    return resolve_attendance_status(check_in, hours)


def compute_streak(db: "Session", user_id: int) -> int:
    """Count consecutive working days (Mon–Fri) where the user was present/late/half_day.

    Starts from yesterday so an intern who hasn't checked in yet today doesn't
    immediately break a running streak.
    """
    from models import Attendance
    cutoff = local_today() - timedelta(days=90)
    records = db.query(Attendance).filter(
        Attendance.user_id == user_id,
        Attendance.date >= cutoff,
    ).all()
    present_dates = {
        r.date for r in records
        if r.status in ("present", "late", "half_day")
    }
    streak = 0
    # Start from yesterday so a mid-day check doesn't break a perfect streak
    check_date = local_today() - timedelta(days=1)
    while True:
        if check_date.weekday() >= 5:  # skip weekends
            check_date -= timedelta(days=1)
            continue
        if check_date in present_dates:
            streak += 1
            check_date -= timedelta(days=1)
        else:
            break
    return streak


def export_attendance_csv(records) -> str:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["Date", "Name", "Email", "Department", "Check In", "Check Out", "Hours", "Status", "Missed Checkout"])
    for r in records:
        checkout_display = ""
        if r.check_out and not r.checkout_missed:
            checkout_display = r.check_out.strftime("%H:%M")
        dept = (r.user.department or "") if r.user else ""
        writer.writerow([
            r.date.isoformat(),
            r.user.name if r.user else "",
            r.user.email if r.user else "",
            dept,
            r.check_in.strftime("%H:%M") if r.check_in else "",
            checkout_display,
            r.hours_worked if r.hours_worked is not None else 0,
            r.status,
            "yes" if r.checkout_missed else "no",
        ])
    return buf.getvalue()


def auto_checkout_missed_sessions(db: "Session", *, commit: bool = True) -> int:
    """Close prior days' open sessions as missed checkout → absent.

    Only processes records with date strictly before today so a midday server
    restart does not mark interns still working today as absent.

    Args:
        commit: If True (default), commits the transaction after processing.
                Pass False when the caller manages its own commit (e.g. the
                HTTP route that needs to include an audit log in the same tx).
    """
    from models import Attendance

    today = local_today()
    records = (
        db.query(Attendance)
        .filter(
            Attendance.check_out.is_(None),
            Attendance.checkout_missed.is_(False),
            Attendance.date < today,
        )
        .all()
    )
    updated = 0
    for record in records:
        from config import Config
        old_status = record.status
        # Store end-of-shift as the auto-checkout time so it's logically after check-in
        record.check_out = datetime.combine(record.date, time(Config.SHIFT_END_HOUR, 0))
        record.checkout_source = "auto"
        record.checkout_missed = True
        record.hours_worked = float(Decimal("0.0"))
        record.status = "absent"
        log_attendance_edit(
            db,
            record.id,
            None,
            "auto_checkout",
            old_status,
            "absent (missed checkout)",
            "system: midnight auto-checkout",
        )
        updated += 1
    if updated and commit:
        db.commit()
    return updated


def auto_checkout_pending(db: "Session", auto_hour: int = 18) -> int:
    """Manual/admin trigger: run missed-session checkout for all past open records."""
    return auto_checkout_missed_sessions(db)


def notify_overdue_tasks(db: "Session") -> int:
    """Remind an intern (and their mentor) once when a task's deadline passes unmet.

    Runs daily. Only ever notifies once per task (overdue_notified_at gate) so a task
    that's been overdue for a week doesn't spam a fresh notification every day — and
    resets if the deadline is later rescheduled, so a re-missed date notifies again.
    """
    from models import Task, TaskStatus

    today = local_today()
    done_statuses = (TaskStatus.DONE,)
    overdue_tasks = (
        db.query(Task)
        .filter(
            Task.is_deleted == False,
            Task.deadline.isnot(None),
            Task.deadline < today,
            Task.status.notin_(done_statuses),
            Task.overdue_notified_at.is_(None),
            Task.assigned_to.isnot(None),
        )
        .all()
    )

    notified = 0
    for task in overdue_tasks:
        intern = task.assignee
        if not intern:
            continue
        project_name = task.project.name if task.project else "a project"
        deadline_str = task.deadline.isoformat()
        link = f"/projects/{task.project_id}"

        push_notification(
            db,
            intern.id,
            f"Your task \"{task.title}\" in {project_name} was due {deadline_str} "
            f"and is now overdue.",
            link=link,
        )
        if intern.mentor_id:
            push_notification(
                db,
                intern.mentor_id,
                f"{intern.name} missed the deadline for \"{task.title}\" in {project_name} "
                f"(was due {deadline_str}).",
                link=link,
            )
        task.overdue_notified_at = datetime.now(timezone.utc).replace(tzinfo=None)
        notified += 1

    if notified:
        db.commit()
    return notified


def log_attendance_edit(
    db: "Session",
    attendance_id: int,
    editor,
    field_name: str,
    old_value: str | None,
    new_value: str | None,
    reason: str,
) -> None:
    from models import AttendanceAuditLog

    db.add(
        AttendanceAuditLog(
            attendance_id=attendance_id,
            editor_id=getattr(editor, "id", None) if editor is not None else None,
            editor_name=getattr(editor, "name", "") or "System",
            field_name=field_name,
            old_value=old_value,
            new_value=new_value,
            reason=reason.strip(),
        )
    )


def mentor_can_edit_intern(db: "Session", mentor, intern_user_id: int) -> bool:
    from models import User

    intern = db.get(User, intern_user_id)
    if not intern or intern.role != "intern":
        return False
    if intern.mentor_id == mentor.id:
        return True
    return intern_user_id in get_mentor_intern_ids(db, mentor.id)


# ---------------------------------------------------------------------------
# Leave balance
# ---------------------------------------------------------------------------

def _business_days(start: date, end: date) -> int:
    """Count weekdays (Mon–Fri) between start and end inclusive."""
    count = 0
    current = start
    while current <= end:
        if current.weekday() < 5:
            count += 1
        current += timedelta(days=1)
    return count


def iter_weekdays(start: date, end: date):
    """Yield each weekday (Mon–Fri) between start and end inclusive."""
    current = start
    while current <= end:
        if current.weekday() < 5:
            yield current
        current += timedelta(days=1)


def sync_attendance_for_approved_leave(db: "Session", leave_request) -> int:
    """Create or update attendance rows as on_leave for each weekday in the leave range."""
    from config import Config
    from models import Attendance, AttendanceStatus, LeaveStatus

    if leave_request.status != LeaveStatus.APPROVED:
        return 0

    synced = 0
    for day in iter_weekdays(leave_request.start_date, leave_request.end_date):
        record = (
            db.query(Attendance)
            .filter_by(user_id=leave_request.user_id, date=day)
            .first()
        )
        if record:
            record.status = AttendanceStatus.ON_LEAVE
            record.hours_worked = 0.0
            record.check_out = None
            record.checkout_missed = False
            record.checkout_source = None
        else:
            check_in = datetime.combine(day, Config.SHIFT_START)
            record = Attendance(
                user_id=leave_request.user_id,
                date=day,
                check_in=check_in,
                status=AttendanceStatus.ON_LEAVE,
                hours_worked=0.0,
                checkout_missed=False,
            )
            db.add(record)
        synced += 1
    return synced


def resolve_user_leave_quota(db: "Session", user_id: int, org_id: int | None = None) -> int:
    """Resolve leave quota for a user:
    1. Check InternshipDurationMaster matching user.internship_duration_months
    2. Check OrganizationSettings.leave_quota_days
    3. Fallback to Config.LEAVE_QUOTA_DAYS (15)
    """
    from models import User, OrganizationMembership, OrganizationSettings, InternshipDurationMaster
    from config import Config

    user = db.get(User, user_id)
    if not user:
        return Config.LEAVE_QUOTA_DAYS

    resolved_org_id = org_id
    if resolved_org_id is None:
        membership = db.query(OrganizationMembership).filter_by(user_id=user_id, is_active=True).first()
        if membership:
            resolved_org_id = membership.organization_id

    duration_months = user.internship_duration_months
    if duration_months is not None and resolved_org_id is not None:
        duration_master = (
            db.query(InternshipDurationMaster)
            .filter_by(organization_id=resolved_org_id, duration_months=duration_months, is_active=True)
            .first()
        )
        if duration_master:
            return duration_master.leaves

    if resolved_org_id is not None:
        settings = db.query(OrganizationSettings).filter_by(organization_id=resolved_org_id).first()
        if settings and settings.leave_quota_days is not None:
            return settings.leave_quota_days

    return Config.LEAVE_QUOTA_DAYS


def get_leave_balance(db: "Session", user_id: int, org_id: int | None = None) -> dict:
    from models import LeaveRequest, Attendance, AttendanceStatus, LeaveStatus
    from config import Config

    today = local_today()
    year = today.year
    leaves = db.query(LeaveRequest).filter(
        LeaveRequest.user_id == user_id,
        LeaveRequest.is_deleted == False,
        LeaveRequest.start_date >= date(year, 1, 1),
        LeaveRequest.start_date <= date(year, 12, 31),
    ).all()

    approved = [lr for lr in leaves if lr.status in (LeaveStatus.APPROVED, "approved")]
    pending = [lr for lr in leaves if lr.status in (LeaveStatus.PENDING, "pending")]
    pending_days = sum(_business_days(lr.start_date, lr.end_date) for lr in pending)

    used_deducted = 0
    future_approved = 0
    attended_saved = 0

    for lr in approved:
        for day in iter_weekdays(lr.start_date, lr.end_date):
            if day > today:
                future_approved += 1
            else:
                att = db.query(Attendance).filter_by(user_id=user_id, date=day).first()
                if att and att.status in (AttendanceStatus.PRESENT, AttendanceStatus.LATE, AttendanceStatus.HALF_DAY) and ((att.hours_worked and att.hours_worked > 0) or att.check_in_lat is not None):
                    attended_saved += 1
                else:
                    used_deducted += 1

    quota = resolve_user_leave_quota(db, user_id, org_id)
    total_approved = used_deducted + future_approved
    remaining = max(0, quota - total_approved)

    return {
        "used": total_approved,
        "deducted_used": used_deducted,
        "future_approved": future_approved,
        "attended_saved": attended_saved,
        "pending": pending_days,
        "quota": quota,
        "remaining": remaining,
        "available_after_pending": max(0, remaining - pending_days),
    }


def reconcile_past_approved_leaves(db: "Session", target_date: date | None = None) -> dict:
    """Reconcile past approved leave dates:
    - If leave date has passed (or is today) and no attendance check-in exists: ensure Attendance status is ON_LEAVE.
    - If intern actually checked in with present/late/half_day: preserve attendance.
    """
    from models import LeaveRequest, LeaveStatus, Attendance, AttendanceStatus
    from config import Config

    target = target_date or local_today()
    approved_leaves = (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.status.in_([LeaveStatus.APPROVED, "approved"]),
            LeaveRequest.is_deleted == False,
            LeaveRequest.start_date <= target,
        )
        .all()
    )

    reconciled_count = 0
    leave_days_settled = 0
    attended_days = 0

    for lr in approved_leaves:
        end_bound = min(lr.end_date, target)
        for day in iter_weekdays(lr.start_date, end_bound):
            att = db.query(Attendance).filter_by(user_id=lr.user_id, date=day).first()
            if att:
                if att.status in (AttendanceStatus.PRESENT, AttendanceStatus.LATE, AttendanceStatus.HALF_DAY) and ((att.hours_worked and att.hours_worked > 0) or att.check_in_lat is not None):
                    attended_days += 1
                else:
                    if att.status != AttendanceStatus.ON_LEAVE:
                        att.status = AttendanceStatus.ON_LEAVE
                        att.hours_worked = 0.0
                        leave_days_settled += 1
            else:
                check_in_dt = datetime.combine(day, Config.SHIFT_START)
                att = Attendance(
                    organization_id=lr.organization_id or 1,
                    user_id=lr.user_id,
                    date=day,
                    check_in=check_in_dt,
                    status=AttendanceStatus.ON_LEAVE,
                    hours_worked=0.0,
                    checkout_missed=False,
                )
                db.add(att)
                leave_days_settled += 1
        reconciled_count += 1

    try:
        db.commit()
    except Exception:
        db.rollback()

    return {
        "reconciled_requests": reconciled_count,
        "leave_days_settled": leave_days_settled,
        "attended_days": attended_days,
    }


# ---------------------------------------------------------------------------
# Mentor → intern scoping (shared across routes)
# ---------------------------------------------------------------------------

def _mentor_project_id_query(db: "Session", mentor_id: int):
    """Projects where this mentor is primary OR a co-mentor (ProjectMentorAssignment)."""
    from sqlalchemy import or_

    from models import Project, ProjectMentorAssignment

    co_mentor_ids = db.query(ProjectMentorAssignment.project_id).filter_by(user_id=mentor_id)
    return db.query(Project.id).filter(
        or_(Project.mentor_id == mentor_id, Project.id.in_(co_mentor_ids))
    )


def get_mentor_intern_ids(db: "Session", mentor_id: int) -> list[int]:
    from models import ProjectAssignment, User, UserRole

    direct = [
        r[0]
        for r in db.query(User.id).filter(User.role == UserRole.INTERN, User.mentor_id == mentor_id).all()
    ]
    project_ids = _mentor_project_id_query(db, mentor_id).subquery()
    rows = (
        db.query(ProjectAssignment.user_id)
        .filter(ProjectAssignment.project_id.in_(db.query(project_ids.c.id)))
        .distinct()
        .all()
    )
    project_based = [r[0] for r in rows]
    return list(set(direct + project_based))


def get_user_project_ids(db: "Session", user) -> list[int]:
    """Project IDs visible to this user for activity scoping."""
    from models import Project, ProjectAssignment

    if user.is_admin:
        return [r[0] for r in db.query(Project.id).filter_by(is_deleted=False).all()]
    if user.is_mentor:
        return [
            r[0]
            for r in _mentor_project_id_query(db, user.id).filter(Project.is_deleted == False).all()
        ]
    return [
        r[0]
        for r in db.query(ProjectAssignment.project_id)
        .join(Project, ProjectAssignment.project_id == Project.id)
        .filter(ProjectAssignment.user_id == user.id, Project.is_deleted == False)
        .all()
    ]


def scoped_audit_query(db: "Session", user, org_id: int | None = None):
    """Return an AuditLog query filtered by role and organization."""
    from sqlalchemy import or_
    from models import AuditLog, OrganizationMembership

    q = db.query(AuditLog)
    if org_id is not None:
        q = q.filter(AuditLog.organization_id == org_id)

    if user.is_admin:
        return q

    project_ids = get_user_project_ids(db, user) or [-1]

    if user.is_mentor:
        intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        # Filter by organization if org_id is available
        if org_id is not None:
            org_intern_ids = [
                m.user_id for m in db.query(OrganizationMembership.user_id)
                .filter_by(organization_id=org_id, role="intern", is_active=True).all()
            ]
            intern_ids = [uid for uid in intern_ids if uid in org_intern_ids] or [-1]
        return q.filter(
            or_(
                AuditLog.project_id.in_(project_ids),
                AuditLog.actor_id.in_(intern_ids),
                AuditLog.affected_user_id.in_(intern_ids),
            )
        )

    # Intern: ONLY activities performed by the intern, affecting the intern, or on their assigned projects.
    return q.filter(
        or_(
            AuditLog.actor_id == user.id,
            AuditLog.affected_user_id == user.id,
            AuditLog.project_id.in_(project_ids),
        )
    )


# ---------------------------------------------------------------------------
# CSRF protection
# ---------------------------------------------------------------------------

def get_csrf_token(request) -> str:
    """Return the session CSRF token, generating one if absent."""
    if "_csrf_token" not in request.session:
        request.session["_csrf_token"] = secrets.token_hex(32)
    return request.session["_csrf_token"]


def validate_csrf_token(request, submitted_token: str) -> bool:
    session_token = request.session.get("_csrf_token", "")
    if not session_token or not submitted_token:
        return False
    return hmac.compare_digest(str(session_token), str(submitted_token))


# ---------------------------------------------------------------------------
# Login rate limiting (distributed via RedisService with in-memory fallback)
# ---------------------------------------------------------------------------

def check_login_rate_limit(ip: str, max_attempts: int, window: int) -> bool:
    """Returns True if the IP is allowed, False if rate-limited."""
    from services.redis_service import RedisService
    return not RedisService.is_rate_limited(f"rate_limit:login:{ip}", limit=max_attempts, window_seconds=window)


def reset_login_attempts(ip: str) -> None:
    from services.redis_service import RedisService
    RedisService.delete(f"rate_limit:login:{ip}")


# ---------------------------------------------------------------------------
# Notification helper
# ---------------------------------------------------------------------------

def push_notification(db: "Session", user_id: int, message: str, link: str | None = None) -> None:
    """Create an in-app notification for a user. Caller must commit."""
    from models import Notification
    db.add(Notification(user_id=user_id, message=message, link=link))


def unread_notification_count(db: "Session", user_id: int) -> int:
    from models import Notification
    return db.query(Notification).filter_by(user_id=user_id, is_read=False).count()


def record_audit(
    db: "Session",
    actor,
    action: str,
    verb: str,
    target: str,
    target_id: int | None = None,
    project_id: int | None = None,
    affected_user_id: int | None = None,
) -> None:
    """Write one entry to the audit_logs table and logs/activity.log. Caller must commit."""
    from models import AuditLog

    from log_files import write_activity_log

    actor_id = getattr(actor, "id", None)
    actor_name = getattr(actor, "name", "")
    created_at = datetime.now(timezone.utc)
    db.add(AuditLog(
        actor_id=actor_id,
        actor_name=actor_name,
        action=action,
        verb=verb,
        target=target,
        target_id=target_id,
        project_id=project_id,
        affected_user_id=affected_user_id,
        created_at=created_at,
    ))
    write_activity_log(
        created_at=created_at,
        actor_id=actor_id,
        actor_name=actor_name,
        action=action,
        verb=verb,
        target=target,
        target_id=target_id,
        project_id=project_id,
        affected_user_id=affected_user_id,
    )


def clear_all_database_data(db: "Session", *, preserve_admin_users: bool = True) -> dict[str, int]:
    """Delete every row from application tables. Schema is left intact.

    When preserve_admin_users is True (default), users with role admin are kept
    so an administrator can clear data without losing their account or session.
    """
    from models import (
        Announcement,
        Attendance,
        AttendanceAuditLog,
        AuditLog,
        Cohort,
        CohortMember,
        InternInviteLink,
        LeaveRequest,
        Notification,
        PerformanceReview,
        Project,
        ProjectAssignment,
        ProjectComment,
        ProjectLink,
        StandupLog,
        Task,
        TaskComment,
        User,
        UserRole,
    )

    from sqlalchemy import text

    counts: dict[str, int] = {}
    db.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))

    for model in (
        ProjectComment,
        ProjectLink,
        TaskComment,
        Notification,
        AttendanceAuditLog,
        Attendance,
        LeaveRequest,
        StandupLog,
        PerformanceReview,
        AuditLog,
        Task,
        ProjectAssignment,
        Announcement,
        CohortMember,
        Cohort,
        InternInviteLink,
        Project,
    ):
        deleted = db.query(model).delete(synchronize_session=False)
        counts[model.__tablename__] = deleted

    db.query(User).update({User.mentor_id: None}, synchronize_session=False)

    if preserve_admin_users:
        counts[User.__tablename__] = (
            db.query(User).filter(~User.role.in_([UserRole.ADMIN, UserRole.SUPERADMIN])).delete(synchronize_session=False)
        )
        counts["admins_preserved"] = (
            db.query(User).filter(User.role.in_([UserRole.ADMIN, UserRole.SUPERADMIN])).count()
        )
    else:
        counts[User.__tablename__] = db.query(User).delete(synchronize_session=False)
        counts["admins_preserved"] = 0

    db.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))

    db.commit()
    return counts


def slugify_status_name(name: str) -> str:
    """Convert a human status name into a clean, URL-safe slug."""
    import re
    s = str(name).strip().lower()
    s = re.sub(r"[^\w\s-]", "", s)
    s = re.sub(r"[\s-]+", "_", s)
    return s.strip("_") or "status"


def get_or_seed_org_task_statuses(db: "Session", org_id: int):
    """Retrieve all TaskStatusBucket entries for an organization, auto-seeding defaults if none exist."""
    from models import TaskStatusBucket, TaskStatusCategory

    statuses = (
        db.query(TaskStatusBucket)
        .filter_by(organization_id=org_id)
        .order_by(TaskStatusBucket.order_index.asc(), TaskStatusBucket.id.asc())
        .all()
    )
    if statuses:
        return statuses

    defaults = [
        TaskStatusBucket(
            organization_id=org_id,
            name="To Do",
            slug="todo",
            color="#94A3B8",
            order_index=0,
            status_category=TaskStatusCategory.TODO,
            is_default=True,
            is_system=True,
        ),
        TaskStatusBucket(
            organization_id=org_id,
            name="In Progress",
            slug="in_progress",
            color="#3B82F6",
            order_index=1,
            status_category=TaskStatusCategory.IN_PROGRESS,
            is_default=False,
            is_system=True,
        ),
        TaskStatusBucket(
            organization_id=org_id,
            name="Review",
            slug="review",
            color="#F59E0B",
            order_index=2,
            status_category=TaskStatusCategory.IN_PROGRESS,
            is_default=False,
            is_system=False,
        ),
        TaskStatusBucket(
            organization_id=org_id,
            name="Completed",
            slug="done",
            color="#10B981",
            order_index=3,
            status_category=TaskStatusCategory.DONE,
            is_default=False,
            is_system=True,
        ),
    ]
    db.add_all(defaults)
    try:
        db.commit()
    except Exception:
        db.rollback()
        return (
            db.query(TaskStatusBucket)
            .filter_by(organization_id=org_id)
            .order_by(TaskStatusBucket.order_index.asc(), TaskStatusBucket.id.asc())
            .all()
        )
    for d in defaults:
        db.refresh(d)
    return defaults


def get_org_done_statuses(db: "Session", org_id: int | None) -> set[str]:
    """Return the set of status slugs that represent completion for the given organization."""
    from models import TaskStatusBucket, TaskStatusCategory

    base_done = {"done", "completed"}
    if org_id is None:
        return base_done

    done_rows = (
        db.query(TaskStatusBucket.slug)
        .filter_by(organization_id=org_id, status_category=TaskStatusCategory.DONE)
        .all()
    )
    if not done_rows:
        count = db.query(TaskStatusBucket).filter_by(organization_id=org_id).count()
        if count == 0:
            get_or_seed_org_task_statuses(db, org_id)
            done_rows = (
                db.query(TaskStatusBucket.slug)
                .filter_by(organization_id=org_id, status_category=TaskStatusCategory.DONE)
                .all()
            )

    return base_done.union({r[0] for r in done_rows})


def get_or_seed_org_project_statuses(db: "Session", org_id: int):
    """Retrieve all ProjectStatusBucket entries for an organization, auto-seeding defaults if none exist."""
    from models import ProjectStatusBucket

    statuses = (
        db.query(ProjectStatusBucket)
        .filter_by(organization_id=org_id)
        .order_by(ProjectStatusBucket.order_index.asc(), ProjectStatusBucket.id.asc())
        .all()
    )
    if statuses:
        return statuses

    defaults = [
        ProjectStatusBucket(
            organization_id=org_id,
            name="Planning",
            slug="planning",
            color="#94A3B8",
            order_index=0,
            is_default=True,
            is_system=True,
        ),
        ProjectStatusBucket(
            organization_id=org_id,
            name="Active",
            slug="active",
            color="#3B82F6",
            order_index=1,
            is_default=False,
            is_system=True,
        ),
        ProjectStatusBucket(
            organization_id=org_id,
            name="On Hold",
            slug="on_hold",
            color="#F59E0B",
            order_index=2,
            is_default=False,
            is_system=False,
        ),
        ProjectStatusBucket(
            organization_id=org_id,
            name="Completed",
            slug="completed",
            color="#10B981",
            order_index=3,
            is_default=False,
            is_system=True,
        ),
    ]
    db.add_all(defaults)
    try:
        db.commit()
    except Exception:
        db.rollback()
        return (
            db.query(ProjectStatusBucket)
            .filter_by(organization_id=org_id)
            .order_by(ProjectStatusBucket.order_index.asc(), ProjectStatusBucket.id.asc())
            .all()
        )
    for d in defaults:
        db.refresh(d)
    return defaults


def get_or_seed_org_internship_durations(db: "Session", org_id: int):
    """Retrieve all InternshipDurationMaster entries for an organization, auto-seeding defaults if none exist."""
    from models import InternshipDurationMaster

    durations = (
        db.query(InternshipDurationMaster)
        .filter_by(organization_id=org_id)
        .order_by(InternshipDurationMaster.order_index.asc(), InternshipDurationMaster.id.asc())
        .all()
    )
    if durations:
        return durations

    defaults = [
        InternshipDurationMaster(
            organization_id=org_id,
            title="1 Month",
            duration_months=1,
            leaves=2,
            order_index=0,
            is_default=False,
            is_active=True,
        ),
        InternshipDurationMaster(
            organization_id=org_id,
            title="3 Months",
            duration_months=3,
            leaves=5,
            order_index=1,
            is_default=True,
            is_active=True,
        ),
        InternshipDurationMaster(
            organization_id=org_id,
            title="6 Months",
            duration_months=6,
            leaves=10,
            order_index=2,
            is_default=False,
            is_active=True,
        ),
    ]
    db.add_all(defaults)
    try:
        db.commit()
    except Exception:
        db.rollback()
        return (
            db.query(InternshipDurationMaster)
            .filter_by(organization_id=org_id)
            .order_by(InternshipDurationMaster.order_index.asc(), InternshipDurationMaster.id.asc())
            .all()
        )
    for d in defaults:
        db.refresh(d)
    return defaults


# ---------------------------------------------------------------------------
# Internship Summary & Attachments
# ---------------------------------------------------------------------------

def get_internship_summary(db: "Session", user: "User", org_id: int | None = None) -> dict:
    """Compute and format complete internship period, duration, and leave stats for an intern."""
    import calendar
    from models import LeaveRequest, LeaveStatus

    start_date = user.joining_date
    end_date = user.internship_end_date
    duration_months = user.internship_duration_months or 3

    if start_date and not end_date:
        new_year = start_date.year + (start_date.month + duration_months - 1) // 12
        new_month = (start_date.month + duration_months - 1) % 12 + 1
        max_day = calendar.monthrange(new_year, new_month)[1]
        new_day = min(start_date.day, max_day)
        end_date = date(new_year, new_month, new_day)

    leaves = (
        db.query(LeaveRequest)
        .filter(
            LeaveRequest.user_id == user.id,
            LeaveRequest.is_deleted == False,
        )
        .all()
    )
    approved_leaves = sum(lr.days for lr in leaves if lr.status == LeaveStatus.APPROVED)
    pending_leaves = sum(lr.days for lr in leaves if lr.status == LeaveStatus.PENDING)
    total_quota = Config.LEAVE_QUOTA_DAYS
    balance_info = get_leave_balance(db, user.id, org_id)
    total_quota = balance_info.get("quota", Config.LEAVE_QUOTA_DAYS)
    remaining_balance = balance_info.get("remaining", 0)

    today = local_today()
    days_remaining = None
    if end_date:
        days_remaining = max(0, (end_date - today).days)

    return {
        "start_date": start_date.isoformat() if start_date else None,
        "end_date": end_date.isoformat() if end_date else None,
        "duration_months": duration_months,
        "duration_label": f"{duration_months} Months" if duration_months else None,
        "approved_leaves": approved_leaves,
        "leaves_used": approved_leaves,
        "pending_leaves": pending_leaves,
        "remaining_leave_balance": remaining_balance,
        "leave_balance": balance_info,
        "total_leave_quota": total_quota,
        "days_remaining": days_remaining,
        "summary_text": f"Internship Period – {duration_months} Months | Approved Leaves – {approved_leaves} Days" if duration_months else None,
    }


def _slugify_filename(name: str) -> str:
    import os
    import re
    stem, ext = os.path.splitext(name)
    clean_stem = re.sub(r"[^\w\s-]", "", stem).strip().lower()
    clean_stem = re.sub(r"[-\s]+", "_", clean_stem) or "file"
    clean_ext = re.sub(r"[^\w.]", "", ext).lower()
    return f"{clean_stem}{clean_ext}"


def save_task_attachment(
    task_id: int,
    user_id: int | None,
    file_name: str,
    content: bytes,
) -> tuple[str, str, int]:
    """Persist task attachment file safely on disk.

    Returns: (rel_path, safe_file_name, file_size)
    """
    import os
    if not content:
        raise ValueError("Attachment content cannot be empty.")
    if len(content) > 20 * 1024 * 1024:
        raise ValueError("File size exceeds 20 MB limit.")

    safe_name = _slugify_filename(file_name)
    timestamp_prefix = datetime.now().strftime("%Y%m%d_%H%M%S")
    stored_name = f"{timestamp_prefix}_{safe_name}"

    rel_path = os.path.join("tasks", str(task_id), stored_name)
    base_dir = os.path.abspath(Config.UPLOADS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))

    if not abs_path.startswith(base_dir):
        raise ValueError("Invalid target path.")

    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "wb") as f:
        f.write(content)

    return rel_path.replace("\\", "/"), file_name, len(content)


def save_assignment_attachment(
    assignment_id: int,
    user_id: int | None,
    file_name: str,
    content: bytes,
) -> tuple[str, str, int]:
    """Persist assignment brief/resources file safely on disk.

    Returns: (rel_path, safe_file_name, file_size)
    """
    import os
    if not content:
        raise ValueError("Attachment content cannot be empty.")
    if len(content) > 25 * 1024 * 1024:
        raise ValueError("File size exceeds 25 MB limit.")

    safe_name = _slugify_filename(file_name)
    timestamp_prefix = datetime.now().strftime("%Y%m%d_%H%M%S")
    stored_name = f"{timestamp_prefix}_{safe_name}"

    rel_path = os.path.join("assignments", str(assignment_id), stored_name)
    base_dir = os.path.abspath(Config.UPLOADS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))

    if not abs_path.startswith(base_dir):
        raise ValueError("Invalid target path.")

    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "wb") as f:
        f.write(content)

    return rel_path.replace("\\", "/"), file_name, len(content)


def save_submission_file(
    submission_id: int,
    user_id: int,
    file_name: str,
    content: bytes,
) -> tuple[str, str, int]:
    """Persist assignment solution submission file safely on disk.

    Returns: (rel_path, safe_file_name, file_size)
    """
    import os
    if not content:
        raise ValueError("Submission file content cannot be empty.")
    if len(content) > 25 * 1024 * 1024:
        raise ValueError("File size exceeds 25 MB limit.")

    safe_name = _slugify_filename(file_name)
    timestamp_prefix = datetime.now().strftime("%Y%m%d_%H%M%S")
    stored_name = f"{timestamp_prefix}_{safe_name}"

    rel_path = os.path.join("submissions", f"{submission_id}_{user_id}", stored_name)
    base_dir = os.path.abspath(Config.UPLOADS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))

    if not abs_path.startswith(base_dir):
        raise ValueError("Invalid target path.")

    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "wb") as f:
        f.write(content)

    return rel_path.replace("\\", "/"), file_name, len(content)


def save_leave_attachment(
    leave_id: int,
    user_id: int,
    file_name: str,
    content: bytes,
) -> tuple[str, str, int]:
    """Persist leave supporting document safely on disk.

    Returns: (rel_path, safe_file_name, file_size)
    """
    import os
    if not content:
        raise ValueError("Attachment content cannot be empty.")
    if len(content) > 20 * 1024 * 1024:
        raise ValueError("File size exceeds 20 MB limit.")

    safe_name = _slugify_filename(file_name)
    timestamp_prefix = datetime.now().strftime("%Y%m%d_%H%M%S")
    stored_name = f"{timestamp_prefix}_{safe_name}"

    rel_path = os.path.join("leave", str(leave_id), stored_name)
    base_dir = os.path.abspath(Config.UPLOADS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))

    if not abs_path.startswith(base_dir):
        raise ValueError("Invalid target path.")

    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "wb") as f:
        f.write(content)

    return rel_path.replace("\\", "/"), file_name, len(content)


def attachment_abs_path(rel_path: str) -> str | None:
    """Safely resolve an attachment relative path to an absolute path on disk."""
    import os
    if not rel_path:
        return None
    base_dir = os.path.abspath(Config.UPLOADS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))
    if not abs_path.startswith(base_dir):
        return None
    if os.path.isfile(abs_path):
        return abs_path
    return None
