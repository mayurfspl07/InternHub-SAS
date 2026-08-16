"""JSON dashboard endpoint."""
from calendar import monthrange
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import case, func

from database import get_db
from dependencies import get_optional_user
from models import (
    Attendance,
    AuditLog,
    LeaveRequest,
    Project,
    ProjectAssignment,
    Task,
    User,
)
from utils import (
    compute_streak,
    get_mentor_intern_ids,
    get_user_project_ids,
    isoformat_utc,
    local_today,
    scoped_audit_query,
)
from typing import Annotated
from sqlalchemy.orm import Session, joinedload

router = APIRouter(prefix="/api/dashboard", tags=["Dashboard"])
DbSession = Annotated[Session, Depends(get_db)]


@router.get("")
async def dashboard(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Resolve active organization scope
    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    org_id: int | None = None
    if header_org and str(header_org).isdigit():
        org_id = int(header_org)
    else:
        from models import OrganizationMembership
        mem = db.query(OrganizationMembership).filter_by(user_id=user.id, is_active=True, is_deleted=False).first()
        org_id = mem.organization_id if mem else None

    from services.redis_service import RedisService
    if org_id is None:
        raise HTTPException(status_code=400, detail="Organization ID is required for dashboard view")
    cache_key = f"dashboard:{org_id}:{user.id}:{user.role}"

    today = local_today()
    # Inclusive window: today + previous 29 days = 30 calendar days.
    window_start = today - timedelta(days=29)

    # Scope of interns visible to this user (used for attendance + presence counts).
    if user.is_intern:
        intern_ids = [user.id]
    elif user.is_mentor:
        intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        # Filter by organization if org_id is available
        if org_id is not None:
            org_intern_ids = [
                m.user_id for m in db.query(OrganizationMembership.user_id)
                .filter_by(organization_id=org_id, role="intern", is_active=True).all()
            ]
            intern_ids = [uid for uid in intern_ids if uid in org_intern_ids] or [-1]
    else:
        from models import OrganizationMembership
        if org_id is not None:
            intern_ids = [
                m.user_id for m in db.query(OrganizationMembership.user_id).filter_by(organization_id=org_id, role="intern", is_active=True).all()
            ] or [-1]
        else:
            intern_ids = [
                u.id for u in db.query(User.id).filter_by(role="intern", is_active=True).all()
            ] or [-1]

    # ------------------------------------------------------------------
    # Projects (role-scoped)
    # ------------------------------------------------------------------
    if user.is_admin:
        proj_q = db.query(Project).filter_by(is_deleted=False)
    elif user.is_mentor:
        mentor_project_ids = get_user_project_ids(db, user) or [-1]
        proj_q = db.query(Project).filter(Project.id.in_(mentor_project_ids), Project.is_deleted == False)
    else:
        assigned_ids = (
            db.query(ProjectAssignment.project_id).filter_by(user_id=user.id).scalar_subquery()
        )
        proj_q = db.query(Project).filter(Project.id.in_(assigned_ids), Project.is_deleted == False)

    if org_id is not None:
        proj_q = proj_q.filter(Project.organization_id == org_id)

    proj_rows = proj_q.with_entities(Project.status, func.count(Project.id)).group_by(Project.status).all()
    project_status = {s: c for s, c in proj_rows}
    total_projects = sum(project_status.values())
    active_projects = project_status.get("active", 0)

    # ------------------------------------------------------------------
    # Tasks (role-scoped)
    # ------------------------------------------------------------------
    task_q = db.query(Task).join(Project, Task.project_id == Project.id).filter(Task.is_deleted == False)
    if user.is_intern:
        task_q = task_q.filter(Task.assigned_to == user.id)
    elif user.is_mentor:
        task_q = task_q.filter(Project.id.in_(mentor_project_ids))
    task_rows = task_q.with_entities(Task.status, func.count(Task.id)).group_by(Task.status).all()
    task_status = {s: c for s, c in task_rows}
    done_statuses = ("done", "completed")
    open_tasks = sum(c for s, c in task_status.items() if s not in done_statuses)
    overdue_tasks = (
        task_q.filter(
            Task.status.notin_(done_statuses),
            Task.deadline.isnot(None),
            Task.deadline < today,
        ).count()
    )

    # ------------------------------------------------------------------
    # Attendance: last 30 days chart + presence count + streak
    # ------------------------------------------------------------------
    if user.is_intern:
        # Intern sees their own daily hours across the last 30 days.
        rows = (
            db.query(Attendance)
            .filter(
                Attendance.user_id == user.id,
                Attendance.date >= window_start,
                # Upper bound matters: a stray future-dated row (e.g. from a manual
                # attendance entry with a typo'd date) would otherwise stay in this
                # window forever and skew the chart well past "today".
                Attendance.date <= today,
            )
            .order_by(Attendance.date)
            .all()
        )
        attendance_chart = [
            {
                "date": r.date.isoformat(),
                "hours": r.duration_hours,
                "status": r.status,
            }
            for r in rows
        ]
        streak = compute_streak(db, user.id)
        present_today = (
            1
            if db.query(Attendance)
            .filter_by(user_id=user.id, date=today)
            .filter(Attendance.status.in_(("present", "late", "half_day")))
            .first()
            else 0
        )
        total_hours = round(sum(r.duration_hours for r in rows), 1)
        days_logged = len(rows)
    else:
        # Staff: aggregate in SQL instead of loading every attendance row.
        present_statuses = ("present", "late", "half_day")
        agg_rows = (
            db.query(
                Attendance.date,
                func.sum(
                    case(
                        (Attendance.checkout_missed == True, 0.0),
                        else_=func.coalesce(Attendance.hours_worked, 0.0),
                    )
                ),
                func.count(
                    func.distinct(
                        case(
                            (Attendance.status.in_(present_statuses), Attendance.user_id),
                            else_=None,
                        )
                    )
                ),
            )
            .filter(
                Attendance.user_id.in_(intern_ids),
                Attendance.date >= window_start,
                # See note above the intern branch: without this upper bound a stray
                # future-dated row keeps this window open-ended instead of 30 days.
                Attendance.date <= today,
            )
            .group_by(Attendance.date)
            .order_by(Attendance.date)
            .all()
        )
        attendance_chart = [
            {
                "date": row[0].isoformat(),
                "hours": round(float(row[1] or 0), 1),
                "present": int(row[2] or 0),
                "status": "present",
            }
            for row in agg_rows
        ]
        streak = 0
        present_today = (
            db.query(func.count(func.distinct(Attendance.user_id)))
            .filter(
                Attendance.user_id.in_(intern_ids),
                Attendance.date == today,
                Attendance.status.in_(present_statuses),
            )
            .scalar()
            or 0
        )
        total_hours = round(sum(float(row[1] or 0) for row in agg_rows), 1)
        days_logged = len(attendance_chart)

    # Total interns in this user's scope (denominator for attendance rate).
    total_interns = 0 if user.is_intern else len([i for i in intern_ids if i > 0])

    # ------------------------------------------------------------------
    # Pending leave (role-scoped)
    # ------------------------------------------------------------------
    if user.is_intern:
        pending_leave = db.query(LeaveRequest).filter_by(user_id=user.id, status="pending").count()
    elif user.is_mentor:
        pending_leave = (
            db.query(LeaveRequest)
            .filter(LeaveRequest.user_id.in_(intern_ids), LeaveRequest.status == "pending")
            .count()
        )
    else:
        pending_leave = db.query(LeaveRequest).filter_by(status="pending").count()

    stats = {
        "present_today": present_today,
        "active_projects": active_projects,
        "total_projects": total_projects,
        "pending_leave": pending_leave,
        "open_tasks": open_tasks,
        "overdue_tasks": overdue_tasks,
        "total_hours": total_hours,
        "days_logged": days_logged,
        "total_interns": total_interns,
    }

    # ------------------------------------------------------------------
    # Recent activity (role-scoped: intern → their projects, mentor → their projects + interns, admin → all)
    # ------------------------------------------------------------------
    activity_rows = (
        scoped_audit_query(db, user, org_id=org_id)
        .order_by(AuditLog.created_at.desc())
        .limit(15)
        .all()
    )
    recent_activity = [
        {
            "id": a.id,
            "actor_id": a.actor_id,
            "actor_name": a.actor_name,
            "action": a.action,
            "verb": a.verb,
            "target": a.target,
            "target_id": a.target_id,
            "project_id": a.project_id,
            "affected_user_id": a.affected_user_id,
            "created_at": isoformat_utc(a.created_at),
        }
        for a in activity_rows
    ]

    return {
        "stats": stats,
        "attendance_chart": attendance_chart,
        "project_status": project_status,
        "task_status": task_status,
        "recent_activity": recent_activity,
        "streak": streak,
        "role": user.role,
    }


@router.get("/present-today")
async def present_today_list(request: Request, db: DbSession):
    """Interns marked present/late/half-day today, scoped to what this user can see."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    today = local_today()
    if user.is_intern:
        intern_ids = [user.id]
    elif user.is_mentor:
        intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
    else:
        intern_ids = [
            u.id for u in db.query(User.id).filter_by(role="intern", is_active=True).all()
        ] or [-1]

    present_statuses = ("present", "late", "half_day")
    rows = (
        db.query(Attendance)
        .join(User, Attendance.user_id == User.id)
        .filter(
            Attendance.user_id.in_(intern_ids),
            Attendance.date == today,
            Attendance.status.in_(present_statuses),
        )
        .order_by(User.name)
        .all()
    )
    return {
        "interns": [
            {
                "id": r.user_id,
                "name": r.user.name if r.user else None,
                "department": r.user.department if r.user else None,
                "status": r.status,
                "check_in": r.check_in.strftime("%H:%M") if r.check_in else None,
            }
            for r in rows
        ]
    }


@router.get("/open-tasks")
async def open_tasks_list(request: Request, db: DbSession):
    """Open (not done) tasks scoped to this user, grouped by project on the frontend."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    done_statuses = ("done", "completed")
    task_q = (
        db.query(Task)
        .join(Project, Task.project_id == Project.id)
        .filter(Task.is_deleted == False, Task.status.notin_(done_statuses))
    )
    if user.is_intern:
        task_q = task_q.filter(Task.assigned_to == user.id)
    elif user.is_mentor:
        mentor_project_ids = get_user_project_ids(db, user) or [-1]
        task_q = task_q.filter(Project.id.in_(mentor_project_ids))

    today = local_today()
    tasks = (
        task_q.options(joinedload(Task.project), joinedload(Task.assignee))
        .order_by(Project.name, Task.deadline.is_(None), Task.deadline)
        .all()
    )
    return {
        "tasks": [
            {
                "id": t.id,
                "title": t.title,
                "status": t.status,
                "priority": t.priority,
                "deadline": t.deadline.isoformat() if t.deadline else None,
                "is_overdue": t.deadline is not None and t.deadline < today,
                "project_id": t.project_id,
                "project_name": t.project.name if t.project else None,
                "assignee_id": t.assigned_to,
                "assignee_name": t.assignee.name if t.assignee else None,
            }
            for t in tasks
        ]
    }


@router.get("/attendance-chart")
async def attendance_chart_for_month(request: Request, db: DbSession):
    """Attendance chart bounded to one calendar month (default: the current month).

    Replaces the dashboard's rolling 30-day window with a real calendar-month view —
    pass `?month=YYYY-MM` to browse other months, same convention as /attendance/history.
    """
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    today = local_today()
    month_param = request.query_params.get("month")
    if month_param:
        try:
            year, month = (int(part) for part in month_param.split("-", 1))
            date(year, month, 1)  # validates year/month are in range
        except (ValueError, TypeError):
            raise HTTPException(status_code=422, detail="Invalid month, expected YYYY-MM.")
    else:
        year, month = today.year, today.month

    window_start = date(year, month, 1)
    last_day = monthrange(year, month)[1]
    # Never query past "today" — a month that's still in progress (or a future month
    # picked by mistake) should just show whatever data exists so far, not an empty
    # tail of not-yet-happened days that could later get skewed by a stray future row.
    window_end = min(date(year, month, last_day), today)

    if user.is_intern:
        intern_ids = [user.id]
    elif user.is_mentor:
        intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
    else:
        intern_ids = [
            u.id for u in db.query(User.id).filter_by(role="intern", is_active=True).all()
        ] or [-1]

    if user.is_intern:
        rows = (
            db.query(Attendance)
            .filter(
                Attendance.user_id == user.id,
                Attendance.date >= window_start,
                Attendance.date <= window_end,
            )
            .order_by(Attendance.date)
            .all()
        )
        chart = [
            {"date": r.date.isoformat(), "hours": r.duration_hours, "status": r.status}
            for r in rows
        ]
    else:
        present_statuses = ("present", "late", "half_day")
        agg_rows = (
            db.query(
                Attendance.date,
                func.sum(
                    case(
                        (Attendance.checkout_missed == True, 0.0),
                        else_=func.coalesce(Attendance.hours_worked, 0.0),
                    )
                ),
                func.count(
                    func.distinct(
                        case(
                            (Attendance.status.in_(present_statuses), Attendance.user_id),
                            else_=None,
                        )
                    )
                ),
            )
            .filter(
                Attendance.user_id.in_(intern_ids),
                Attendance.date >= window_start,
                Attendance.date <= window_end,
            )
            .group_by(Attendance.date)
            .order_by(Attendance.date)
            .all()
        )
        chart = [
            {
                "date": row[0].isoformat(),
                "hours": round(float(row[1] or 0), 1),
                "present": int(row[2] or 0),
                "status": "present",
            }
            for row in agg_rows
        ]

    total_interns = 0 if user.is_intern else len([i for i in intern_ids if i > 0])

    return {
        "month": f"{year:04d}-{month:02d}",
        "chart": chart,
        "total_interns": total_interns,
    }
