"""User profile overview for dialogs and exports."""
from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import Attendance, LeaveRequest, LeaveStatus, Project, ProjectAssignment, Task, User
from utils import get_leave_balance, isoformat_utc, local_today

router = APIRouter(prefix="/api/users", tags=["Users"])
DbSession = Annotated[Session, Depends(get_db)]


def _user_dict(u: User) -> dict:
    return {
        "id": u.id,
        "name": u.name,
        "email": u.email,
        "role": u.role,
        "is_active": u.is_active,
        "bio": u.bio,
        "department": u.department,
        "phone": u.phone,
        "job_title": u.job_title,
        "joining_date": u.joining_date.isoformat() if u.joining_date else None,
        "skills": u.skills_list(),
        "created_at": isoformat_utc(u.created_at),
    }


def _can_view_leave_data(viewer: User, target: User) -> bool:
    if not target.is_intern:
        return False
    if viewer.is_admin or viewer.is_mentor:
        return True
    return viewer.id == target.id


def _profile_leave_dict(lr: LeaveRequest) -> dict:
    return {
        "id": lr.id,
        "start_date": lr.start_date.isoformat(),
        "end_date": lr.end_date.isoformat(),
        "days": lr.days,
        "leave_type": lr.leave_type,
        "reason": lr.reason,
        "status": lr.status,
        "reviewer_name": lr.reviewer.name if lr.reviewer else None,
        "reviewed_at": isoformat_utc(lr.reviewed_at),
        "created_at": isoformat_utc(lr.created_at),
    }


def _leave_summary(requests: list[LeaveRequest]) -> dict:
    approved = [r for r in requests if r.status == LeaveStatus.APPROVED]
    rejected = [r for r in requests if r.status == LeaveStatus.REJECTED]
    pending = [r for r in requests if r.status == LeaveStatus.PENDING]
    return {
        "total": len(requests),
        "approved": len(approved),
        "rejected": len(rejected),
        "pending": len(pending),
        "days_taken": sum(r.days for r in approved),
    }


def _intern_leave_payload(db: Session, target: User) -> dict:
    leave_rows = (
        db.query(LeaveRequest)
        .options(joinedload(LeaveRequest.reviewer))
        .filter(LeaveRequest.user_id == target.id, LeaveRequest.is_deleted == False)
        .order_by(LeaveRequest.created_at.desc())
        .all()
    )
    summary = _leave_summary(leave_rows)
    return {
        "leave_requests": [_profile_leave_dict(lr) for lr in leave_rows],
        "leave_summary": summary,
        "leave_balance": get_leave_balance(db, target.id),
        "leave_stats": {
            "leave_total": summary["total"],
            "leave_approved": summary["approved"],
            "leave_rejected": summary["rejected"],
            "leave_pending": summary["pending"],
            "leave_days_taken": summary["days_taken"],
        },
    }


def _can_view_profile(viewer: User, target: User, db: Session) -> bool:
    if viewer.id == target.id:
        return True
    role = (viewer.role or "").strip().lower()
    target_role = (target.role or "").strip().lower()
    # Staff can open profiles from admin, team, attendance, etc.
    if role == "admin":
        return True
    if role == "mentor":
        return target_role in ("intern", "mentor", "admin")
    # Interns may view users on shared projects (mentor + teammates).
    shared = (
        db.query(ProjectAssignment)
        .filter(
            ProjectAssignment.user_id == viewer.id,
            ProjectAssignment.project_id.in_(
                db.query(ProjectAssignment.project_id).filter_by(user_id=target.id)
            ),
        )
        .first()
    )
    if shared:
        return True
    mentor_shared = (
        db.query(Project)
        .filter(
            Project.is_deleted == False,
            Project.mentor_id == target.id,
            Project.id.in_(
                db.query(ProjectAssignment.project_id).filter_by(user_id=viewer.id)
            ),
        )
        .first()
    )
    return mentor_shared is not None


def _project_dict(p: Project) -> dict:
    intern_count = len(p.assignments)
    return {
        "id": p.id,
        "name": p.name,
        "status": p.status,
        "progress": p.progress_pct,
        "start_date": p.start_date.isoformat() if p.start_date else None,
        "end_date": p.end_date.isoformat() if p.end_date else None,
        "intern_count": intern_count,
    }


def _task_dict(t: Task, project_name: str | None = None) -> dict:
    return {
        "id": t.id,
        "title": t.title,
        "project_id": t.project_id,
        "project_name": project_name,
        "status": t.status,
        "priority": t.priority,
        "due_date": t.deadline.isoformat() if t.deadline else None,
    }


def _att_dict(r: Attendance) -> dict:
    return {
        "date": r.date.isoformat(),
        "check_in": r.check_in.strftime("%H:%M") if r.check_in else None,
        "check_out": r.check_out.strftime("%H:%M") if r.check_out else None,
        "hours": r.duration_hours,
        "status": r.status,
    }


@router.get("/{user_id}/overview")
async def user_overview(user_id: int, request: Request, db: DbSession):
    viewer = get_optional_user(request, db)
    if not viewer:
        raise HTTPException(status_code=401)
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found.")
    if not _can_view_profile(viewer, target, db):
        raise HTTPException(status_code=403, detail="You cannot view this profile.")

    # Full attendance history — used for the "Attendance" export sheet and for the
    # on-screen summary, which itself re-filters to the trailing 30 days client-side.
    attendance_rows = (
        db.query(Attendance)
        .filter(Attendance.user_id == target.id)
        .order_by(Attendance.date.desc())
        .all()
    )
    # Inclusive window: today + previous 29 days = 30 calendar days — used only for the
    # *_30d summary stats below, not for the full attendance list returned to the client.
    since = local_today() - timedelta(days=29)
    recent_attendance_rows = [r for r in attendance_rows if r.date >= since]

    stats: dict = {}
    projects: list[dict] = []
    tasks: list[dict] = []
    interns: list[dict] = []

    if target.is_intern:
        assigned_project_ids = [
            r[0]
            for r in db.query(ProjectAssignment.project_id).filter_by(user_id=target.id).all()
        ]
        proj_rows = (
            db.query(Project)
            .options(joinedload(Project.assignments))
            .filter(Project.id.in_(assigned_project_ids or [-1]), Project.is_deleted == False)
            .order_by(Project.name)
            .all()
        )
        projects = [_project_dict(p) for p in proj_rows]

        task_rows = (
            db.query(Task)
            .options(joinedload(Task.project))
            .filter(Task.assigned_to == target.id, Task.is_deleted == False)
            .order_by(Task.created_at.desc())
            .all()
        )
        tasks = [_task_dict(t, t.project.name if t.project else None) for t in task_rows]
        active_tasks = [t for t in task_rows if t.status not in ("done", "completed")]

        att_summary = {s: 0 for s in ("present", "late", "half_day", "absent", "on_leave")}
        for row in recent_attendance_rows:
            if row.status in att_summary:
                att_summary[row.status] += 1

        stats = {
            "projects": len(projects),
            "active_tasks": len(active_tasks),
            "completed_tasks": len(task_rows) - len(active_tasks),
            "present_30d": att_summary["present"],
            "late_30d": att_summary["late"],
            "half_day_30d": att_summary["half_day"],
            "absent_30d": att_summary["absent"],
            "on_leave_30d": att_summary["on_leave"],
            # Temporary aliases until frontend fully migrates to *_30d.
            "present_14d": att_summary["present"],
            "late_14d": att_summary["late"],
            "half_day_14d": att_summary["half_day"],
            "absent_14d": att_summary["absent"],
            "on_leave_14d": att_summary["on_leave"],
        }

    elif target.is_mentor:
        proj_rows = (
            db.query(Project)
            .options(joinedload(Project.assignments))
            .filter(Project.mentor_id == target.id, Project.is_deleted == False)
            .order_by(Project.name)
            .all()
        )
        projects = [_project_dict(p) for p in proj_rows]
        intern_ids: set[int] = set()
        for p in proj_rows:
            for a in p.assignments:
                intern_ids.add(a.user_id)

        task_rows = (
            db.query(Task)
            .join(Project, Task.project_id == Project.id)
            .options(joinedload(Task.project))
            .filter(Project.mentor_id == target.id, Task.is_deleted == False)
            .order_by(Task.created_at.desc())
            .all()
        )
        tasks = [_task_dict(t, t.project.name if t.project else None) for t in task_rows]

        intern_users = (
            db.query(User)
            .filter(User.id.in_(list(intern_ids) or [-1]))
            .order_by(User.name)
            .all()
        )
        interns = [
            {
                "id": u.id,
                "name": u.name,
                "email": u.email,
                "is_active": u.is_active,
                "department": u.department,
            }
            for u in intern_users
        ]

        stats = {
            "projects": len(projects),
            "running_projects": sum(1 for p in proj_rows if p.status == "active"),
            "interns": len(intern_ids),
            "tasks_assigned": len(task_rows),
        }

    else:
        stats = {"role": "administrator"}

    payload = {
        "user": _user_dict(target),
        "stats": stats,
        "projects": projects,
        "tasks": tasks,
        "attendance": [_att_dict(r) for r in attendance_rows],
        "interns": interns,
    }

    if target.is_intern and _can_view_leave_data(viewer, target):
        leave_data = _intern_leave_payload(db, target)
        payload["leave_requests"] = leave_data["leave_requests"]
        payload["leave_summary"] = leave_data["leave_summary"]
        payload["leave_balance"] = leave_data["leave_balance"]
        payload["stats"].update(leave_data["leave_stats"])

    return payload


@router.get("/{user_id}/leave")
async def user_leave(user_id: int, request: Request, db: DbSession):
    """Standalone leave history for a profile — used as a fallback by the profile dialog
    when /overview's embedded leave data isn't available yet (e.g. still loading)."""
    viewer = get_optional_user(request, db)
    if not viewer:
        raise HTTPException(status_code=401)
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found.")
    if not target.is_intern or not _can_view_leave_data(viewer, target):
        raise HTTPException(status_code=403, detail="You cannot view this user's leave history.")

    leave_data = _intern_leave_payload(db, target)
    return {
        "requests": leave_data["leave_requests"],
        "summary": leave_data["leave_summary"],
        "balance": leave_data["leave_balance"],
    }
