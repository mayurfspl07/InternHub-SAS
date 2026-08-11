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
    Priority order:
    1. Missed checkout → absent (0 hours, can't verify)
    2. hours < 5       → absent (not enough time regardless of when they arrived)
    3. check-in ≥ noon → late   (overrides present/half_day)
    4. hours ≥ 7       → present
    5. hours ≥ 5       → half_day
    """
    from config import Config

    hw = hours_worked if isinstance(hours_worked, Decimal) else Decimal(str(hours_worked))

    if checkout_missed:
        return "absent"

    if hw < Config.HALF_DAY_HOURS:
        return "absent"

    if check_in_time >= Config.NOON_CUTOFF:
        return "late"

    if hw >= Config.FULL_DAY_HOURS:
        return "present"

    return "half_day"


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


def determine_attendance_status(check_in_dt: datetime, late_hour: int = 9) -> str:
    """Provisional status at check-in (finalized at checkout)."""
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
    writer.writerow(["Date", "Name", "Email", "Check In", "Check Out", "Hours", "Status", "Missed Checkout"])
    for r in records:
        checkout_display = ""
        if r.check_out and not r.checkout_missed:
            checkout_display = r.check_out.strftime("%H:%M")
        writer.writerow([
            r.date.isoformat(),
            r.user.name if r.user else "",
            r.user.email if r.user else "",
            r.check_in.strftime("%H:%M") if r.check_in else "",
            checkout_display,
            r.hours_worked if r.hours_worked is not None else 0,
            r.status,
            "yes" if r.checkout_missed else "no",
        ])
    return buf.getvalue()


def auto_checkout_missed_sessions(db: "Session") -> int:
    """Close prior days' open sessions as missed checkout → absent.

    Only processes records with date strictly before today so a midday server
    restart does not mark interns still working today as absent.
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
    if updated:
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
    done_statuses = (TaskStatus.DONE, TaskStatus.COMPLETED)
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


def get_leave_balance(db: "Session", user_id: int) -> dict:
    from models import LeaveRequest
    from config import Config
    year = local_today().year
    approved = db.query(LeaveRequest).filter(
        LeaveRequest.user_id == user_id,
        LeaveRequest.status == "approved",
        LeaveRequest.is_deleted == False,
        LeaveRequest.start_date >= date(year, 1, 1),
        LeaveRequest.start_date <= date(year, 12, 31),
    ).all()
    used = sum(_business_days(lr.start_date, lr.end_date) for lr in approved)
    quota = Config.LEAVE_QUOTA_DAYS
    return {"used": used, "quota": quota, "remaining": max(0, quota - used)}


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


def scoped_audit_query(db: "Session", user):
    """Return an AuditLog query filtered by role."""
    from sqlalchemy import or_

    from models import AuditLog

    q = db.query(AuditLog)
    if user.is_admin:
        return q

    project_ids = get_user_project_ids(db, user) or [-1]

    if user.is_mentor:
        intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        return q.filter(
            or_(
                AuditLog.project_id.in_(project_ids),
                AuditLog.actor_id.in_(intern_ids),
                AuditLog.affected_user_id.in_(intern_ids),
            )
        )

    # Intern: activity on projects they belong to.
    return q.filter(AuditLog.project_id.in_(project_ids))


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
# Login rate limiting (in-memory, resets on restart)
# ---------------------------------------------------------------------------

_login_attempts: dict[str, list[float]] = defaultdict(list)


def check_login_rate_limit(ip: str, max_attempts: int, window: int) -> bool:
    """Returns True if the IP is allowed, False if rate-limited."""
    now = _time_module.time()
    attempts = [t for t in _login_attempts[ip] if now - t < window]
    _login_attempts[ip] = attempts
    if len(attempts) >= max_attempts:
        return False
    _login_attempts[ip].append(now)
    return True


def reset_login_attempts(ip: str) -> None:
    _login_attempts.pop(ip, None)


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
            db.query(User).filter(User.role != UserRole.ADMIN).delete(synchronize_session=False)
        )
        counts["admins_preserved"] = (
            db.query(User).filter(User.role == UserRole.ADMIN).count()
        )
    else:
        counts[User.__tablename__] = db.query(User).delete(synchronize_session=False)
        counts["admins_preserved"] = 0

    db.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))

    db.commit()
    return counts
