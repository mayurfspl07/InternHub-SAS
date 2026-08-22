"""JSON dashboard endpoints for All Roles (Admin, Mentor, Intern, SuperAdmin)."""
from calendar import monthrange
from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import case, func, or_
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import (
    Announcement,
    Attendance,
    AuditLog,
    LeaveRequest,
    Organization,
    OrganizationMembership,
    OrganizationType,
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

# Domain routers
router = APIRouter(prefix="/api/dashboard", tags=["Dashboard"])
admin_dashboard_router = APIRouter(prefix="/api/admin/dashboard", tags=["Admin Dashboard"])
mentor_dashboard_router = APIRouter(prefix="/api/mentor/dashboard", tags=["Mentor Dashboard"])
intern_dashboard_router = APIRouter(prefix="/api/intern/dashboard", tags=["Intern Dashboard"])
superadmin_dashboard_router = APIRouter(prefix="/api/superadmin/dashboard", tags=["Superadmin Dashboard"])

# Root alias routers
root_admin_dashboard_router = APIRouter(prefix="/admin/dashboard", tags=["Admin Dashboard"])
root_mentor_dashboard_router = APIRouter(prefix="/mentor/dashboard", tags=["Mentor Dashboard"])
root_intern_dashboard_router = APIRouter(prefix="/intern/dashboard", tags=["Intern Dashboard"])
root_superadmin_dashboard_router = APIRouter(prefix="/superadmin/dashboard", tags=["Superadmin Dashboard"])

DbSession = Annotated[Session, Depends(get_db)]


def _resolve_org_id(request: Request, user: User, db: Session) -> int | None:
    """Resolve active tenant organization id from request or user membership."""
    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if header_org and str(header_org).isdigit():
        return int(header_org)
    mem = (
        db.query(OrganizationMembership)
        .filter_by(user_id=user.id, is_active=True, is_deleted=False)
        .first()
    )
    if mem and mem.organization_id:
        return mem.organization_id
    first_org = (
        db.query(Organization)
        .filter_by(is_deleted=False, status="active")
        .order_by(Organization.id.asc())
        .first()
    )
    return first_org.id if first_org else 1


# ---------------------------------------------------------------------------
# Role Data Builders
# ---------------------------------------------------------------------------

def _build_admin_dashboard(request: Request, user: User, db: Session) -> dict:
    if not (user.is_admin or user.is_superadmin or user.is_platform_admin):
        raise HTTPException(status_code=403, detail="Forbidden: Admin access required.")

    org_id = _resolve_org_id(request, user, db)
    org = db.get(Organization, org_id) if org_id else None
    today = local_today()
    window_start = today - timedelta(days=29)

    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")

    # 1. Interns & Mentors count
    if header_org and str(header_org).isdigit():
        target_org = int(header_org)
        intern_ids = [
            m.user_id
            for m in db.query(OrganizationMembership.user_id)
            .filter_by(organization_id=target_org, role="intern", is_active=True)
            .all()
        ]
        mentor_ids = [
            m.user_id
            for m in db.query(OrganizationMembership.user_id)
            .filter_by(organization_id=target_org, role="mentor", is_active=True)
            .all()
        ]
        if not intern_ids:
            intern_ids = [u.id for u in db.query(User.id).filter(User.role == "intern", User.is_active == True, User.is_deleted == False).all()]
        if not mentor_ids:
            mentor_ids = [u.id for u in db.query(User.id).filter(User.role == "mentor", User.is_active == True, User.is_deleted == False).all()]
    else:
        intern_ids = [u.id for u in db.query(User.id).filter(User.role == "intern", User.is_active == True, User.is_deleted == False).all()]
        mentor_ids = [u.id for u in db.query(User.id).filter(User.role == "mentor", User.is_active == True, User.is_deleted == False).all()]

    intern_scope = intern_ids or [-1]

    # 2. Today's Attendance & Present List
    present_statuses = ("present", "late", "half_day")
    today_attendances = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter(Attendance.user_id.in_(intern_scope), Attendance.date == today)
        .all()
    )
    present_today_count = sum(1 for att in today_attendances if att.status in present_statuses)
    on_leave_today_count = sum(1 for att in today_attendances if att.status == "on_leave")
    absent_today_count = max(0, len(intern_ids) - present_today_count - on_leave_today_count)

    present_today_list = [
        {
            "user_id": att.user_id,
            "name": att.user.name if att.user else f"Intern #{att.user_id}",
            "email": att.user.email if att.user else None,
            "department": att.user.department if att.user else None,
            "status": att.status,
            "check_in": att.check_in.strftime("%H:%M") if att.check_in else None,
            "check_out": att.check_out.strftime("%H:%M") if att.check_out else None,
            "hours_worked": att.duration_hours,
            "check_in_photo_url": (
                att.check_in_photo
                if att.check_in_photo and att.check_in_photo.startswith(("http://", "https://"))
                else (f"/api/attendance/{att.id}/photo/checkin" if att.check_in_photo else None)
            ),
        }
        for att in today_attendances
        if att.status in present_statuses
    ]

    # 3. Projects & Project Status
    proj_q = db.query(Project).filter_by(is_deleted=False)
    if header_org and str(header_org).isdigit():
        proj_q = proj_q.filter((Project.organization_id == int(header_org)) | (Project.organization_id.is_(None)))
    elif org_id is not None and not user.is_admin:
        proj_q = proj_q.filter((Project.organization_id == org_id) | (Project.organization_id.is_(None)))
    all_projects = proj_q.options(joinedload(Project.mentor), joinedload(Project.tasks), joinedload(Project.assignments)).order_by(Project.created_at.desc()).all()

    project_status = {}
    for p in all_projects:
        project_status[p.status] = project_status.get(p.status, 0) + 1

    active_projects_list = [
        {
            "id": p.id,
            "name": p.name,
            "description": p.description,
            "status": p.status,
            "mentor_id": p.mentor_id,
            "mentor_name": p.mentor.name if p.mentor else None,
            "members_count": len(p.assignments),
            "tasks_count": len([t for t in p.tasks if not t.is_deleted]),
            "completed_tasks_count": len([t for t in p.tasks if not t.is_deleted and t.status in ("done", "completed")]),
            "created_at": isoformat_utc(p.created_at),
        }
        for p in all_projects
        if p.status == "active"
    ][:15]

    # 4. Tasks & Task Status
    task_q = db.query(Task).join(Project, Task.project_id == Project.id).filter(Task.is_deleted == False)
    if header_org and str(header_org).isdigit():
        task_q = task_q.filter((Project.organization_id == int(header_org)) | (Project.organization_id.is_(None)))
    elif org_id is not None and not user.is_admin:
        task_q = task_q.filter((Project.organization_id == org_id) | (Project.organization_id.is_(None)))

    task_rows = task_q.with_entities(Task.status, func.count(Task.id)).group_by(Task.status).all()
    task_status = {s: c for s, c in task_rows}
    done_statuses = ("done", "completed")
    open_tasks_count = sum(c for s, c in task_status.items() if s not in done_statuses)

    open_tasks_db = (
        task_q.filter(Task.status.notin_(done_statuses))
        .options(joinedload(Task.project), joinedload(Task.assignee))
        .order_by(Task.deadline.is_(None), Task.deadline.asc())
        .limit(25)
        .all()
    )
    open_tasks_list = [
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
        for t in open_tasks_db
    ]
    overdue_tasks_count = sum(1 for t in open_tasks_list if t["is_overdue"])

    # 5. Pending Leave Requests
    leave_q = (
        db.query(LeaveRequest)
        .options(joinedload(LeaveRequest.user))
        .filter(LeaveRequest.status == "pending", LeaveRequest.is_deleted == False)
    )
    if header_org and str(header_org).isdigit():
        leave_q = leave_q.filter((LeaveRequest.organization_id == int(header_org)) | (LeaveRequest.organization_id.is_(None)))
    elif org_id is not None and not user.is_admin:
        leave_q = leave_q.filter((LeaveRequest.organization_id == org_id) | (LeaveRequest.organization_id.is_(None)))
    pending_leaves = leave_q.order_by(LeaveRequest.created_at.desc()).limit(20).all()
    pending_leave_list = [
        {
            "id": l.id,
            "user_id": l.user_id,
            "user_name": l.user.name if l.user else f"Intern #{l.user_id}",
            "department": l.user.department if l.user else None,
            "start_date": l.start_date.isoformat(),
            "end_date": l.end_date.isoformat(),
            "days": l.days,
            "days_count": l.days,
            "leave_type": l.leave_type,
            "reason": l.reason,
            "created_at": isoformat_utc(l.created_at),
        }
        for l in pending_leaves
    ]

    # 6. 30-Day Attendance Chart
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
            Attendance.user_id.in_(intern_scope),
            Attendance.date >= window_start,
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
    total_hours_30d = round(sum(float(row[1] or 0) for row in agg_rows), 1)

    # 7. Recent Activity
    activity_rows = scoped_audit_query(db, user, org_id=org_id).order_by(AuditLog.created_at.desc()).limit(15).all()
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

    stats = {
        "present_today": present_today_count,
        "absent_today": absent_today_count,
        "on_leave_today": on_leave_today_count,
        "total_interns": len(intern_ids),
        "total_mentors": len(mentor_ids),
        "active_projects": project_status.get("active", 0),
        "total_projects": len(all_projects),
        "open_tasks": open_tasks_count,
        "overdue_tasks": overdue_tasks_count,
        "pending_leave": len(pending_leaves),
        "total_hours": total_hours_30d,
        "days_logged": len(attendance_chart),
    }

    return {
        "role": "admin",
        "organization": {
            "id": org.id if org else org_id,
            "name": org.name if org else "Default Org",
            "slug": org.slug if org else "default",
            "type": org.type if org else "business",
        } if org else None,
        "stats": stats,
        "present_today_list": present_today_list,
        "open_tasks": open_tasks_list,
        "active_projects": active_projects_list,
        "pending_leave_requests": pending_leave_list,
        "attendance_chart": attendance_chart,
        "project_status": project_status,
        "task_status": task_status,
        "recent_activity": recent_activity,
        "streak": 0,
    }


def _build_mentor_dashboard(request: Request, user: User, db: Session) -> dict:
    if user.is_intern and not (user.is_mentor or user.is_admin or user.is_superadmin):
        raise HTTPException(status_code=403, detail="Forbidden: Mentor access required.")

    org_id = _resolve_org_id(request, user, db)
    today = local_today()
    window_start = today - timedelta(days=29)

    # 1. Assigned Mentees
    mentee_ids = get_mentor_intern_ids(db, user.id) or []
    if org_id is not None:
        org_mentee_ids = [
            m.user_id
            for m in db.query(OrganizationMembership.user_id)
            .filter_by(organization_id=org_id, role="intern", is_active=True)
            .all()
        ]
        mentee_ids = [uid for uid in mentee_ids if uid in org_mentee_ids]

    mentee_scope = mentee_ids or [-1]
    mentee_users = db.query(User).filter(User.id.in_(mentee_scope), User.is_active == True).all()

    # 2. Mentor Projects
    mentor_project_ids = get_user_project_ids(db, user) or []
    proj_q = db.query(Project).filter(Project.id.in_(mentor_project_ids or [-1]), Project.is_deleted == False)
    if org_id is not None:
        proj_q = proj_q.filter(Project.organization_id == org_id)
    mentor_projects = proj_q.options(joinedload(Project.tasks), joinedload(Project.assignments)).order_by(Project.created_at.desc()).all()

    # 3. Today's Attendance for Mentees
    present_statuses = ("present", "late", "half_day")
    today_attendances = (
        db.query(Attendance)
        .options(joinedload(Attendance.user))
        .filter(Attendance.user_id.in_(mentee_scope), Attendance.date == today)
        .all()
    )
    today_att_map = {att.user_id: att for att in today_attendances}
    present_today_count = sum(1 for att in today_attendances if att.status in present_statuses)
    absent_today_count = max(0, len(mentee_ids) - present_today_count)

    # 4. Mentees Detailed List
    mentee_tasks_q = (
        db.query(Task.assigned_to, func.count(Task.id))
        .filter(Task.assigned_to.in_(mentee_scope), Task.is_deleted == False, Task.status.notin_(("done", "completed")))
        .group_by(Task.assigned_to)
        .all()
    )
    open_tasks_by_mentee = dict(mentee_tasks_q)

    assigned_interns_list = [
        {
            "user_id": u.id,
            "name": u.name,
            "email": u.email,
            "department": u.department,
            "today_status": today_att_map[u.id].status if u.id in today_att_map else "absent",
            "check_in": today_att_map[u.id].check_in.strftime("%H:%M") if (u.id in today_att_map and today_att_map[u.id].check_in) else None,
            "check_out": today_att_map[u.id].check_out.strftime("%H:%M") if (u.id in today_att_map and today_att_map[u.id].check_out) else None,
            "hours_worked": today_att_map[u.id].duration_hours if u.id in today_att_map else 0.0,
            "check_in_photo_url": (
                today_att_map[u.id].check_in_photo
                if (u.id in today_att_map and today_att_map[u.id].check_in_photo and today_att_map[u.id].check_in_photo.startswith(("http://", "https://")))
                else (f"/api/attendance/{today_att_map[u.id].id}/photo/checkin" if (u.id in today_att_map and today_att_map[u.id].check_in_photo) else None)
            ) if u.id in today_att_map else None,
            "open_tasks_count": open_tasks_by_mentee.get(u.id, 0),
            "streak": compute_streak(db, u.id),
        }
        for u in mentee_users
    ]

    present_today_list = [
        m for m in assigned_interns_list if m["today_status"] in present_statuses
    ]

    # 5. Open Tasks in Mentor's Projects / Mentees
    tasks_q = (
        db.query(Task)
        .join(Project, Task.project_id == Project.id)
        .filter(
            Task.is_deleted == False,
            or_(Project.id.in_(mentor_project_ids or [-1]), Task.assigned_to.in_(mentee_scope)),
            Task.status.notin_(("done", "completed")),
        )
        .options(joinedload(Task.project), joinedload(Task.assignee))
        .order_by(Task.deadline.is_(None), Task.deadline.asc())
        .limit(25)
        .all()
    )
    open_tasks_list = [
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
        for t in tasks_q
    ]
    overdue_tasks_count = sum(1 for t in open_tasks_list if t["is_overdue"])

    # 6. Task Status Distribution
    all_mentor_tasks = (
        db.query(Task.status, func.count(Task.id))
        .join(Project, Task.project_id == Project.id)
        .filter(Task.is_deleted == False, Project.id.in_(mentor_project_ids or [-1]))
        .group_by(Task.status)
        .all()
    )
    task_status = dict(all_mentor_tasks)

    # 7. Pending Leave Requests for Mentees
    pending_leaves = (
        db.query(LeaveRequest)
        .options(joinedload(LeaveRequest.user))
        .filter(LeaveRequest.user_id.in_(mentee_scope), LeaveRequest.status == "pending", LeaveRequest.is_deleted == False)
        .order_by(LeaveRequest.created_at.desc())
        .all()
    )
    pending_leave_list = [
        {
            "id": l.id,
            "user_id": l.user_id,
            "user_name": l.user.name if l.user else f"Intern #{l.user_id}",
            "department": l.user.department if l.user else None,
            "start_date": l.start_date.isoformat(),
            "end_date": l.end_date.isoformat(),
            "days": l.days,
            "days_count": l.days,
            "leave_type": l.leave_type,
            "reason": l.reason,
            "created_at": isoformat_utc(l.created_at),
        }
        for l in pending_leaves
    ]

    # 8. Projects summary
    projects_list = [
        {
            "id": p.id,
            "name": p.name,
            "description": p.description,
            "status": p.status,
            "members_count": len(p.assignments),
            "tasks_count": len([t for t in p.tasks if not t.is_deleted]),
            "completed_tasks_count": len([t for t in p.tasks if not t.is_deleted and t.status in ("done", "completed")]),
            "created_at": isoformat_utc(p.created_at),
        }
        for p in mentor_projects
    ]

    # 9. 30-Day Attendance Chart for Mentees
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
            Attendance.user_id.in_(mentee_scope),
            Attendance.date >= window_start,
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
    total_hours_logged = round(sum(float(row[1] or 0) for row in agg_rows), 1)

    # 10. Recent Activity
    activity_rows = scoped_audit_query(db, user, org_id=org_id).order_by(AuditLog.created_at.desc()).limit(15).all()
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

    stats = {
        "present_today": present_today_count,
        "absent_today": absent_today_count,
        "assigned_interns_count": len(mentee_ids),
        "active_projects": len([p for p in mentor_projects if p.status == "active"]),
        "total_projects": len(mentor_projects),
        "open_tasks": len(open_tasks_list),
        "overdue_tasks": overdue_tasks_count,
        "pending_leave": len(pending_leaves),
        "total_hours": total_hours_logged,
        "days_logged": len(attendance_chart),
        "total_interns": len(mentee_ids),
    }

    project_status = {}
    for p in mentor_projects:
        project_status[p.status] = project_status.get(p.status, 0) + 1

    return {
        "role": "mentor",
        "stats": stats,
        "assigned_interns": assigned_interns_list,
        "present_today_list": present_today_list,
        "projects": projects_list,
        "active_projects": projects_list,
        "open_tasks": open_tasks_list,
        "pending_leave_requests": pending_leave_list,
        "attendance_chart": attendance_chart,
        "project_status": project_status,
        "task_status": task_status,
        "recent_activity": recent_activity,
        "streak": 0,
    }


def _build_intern_dashboard(request: Request, user: User, db: Session) -> dict:
    org_id = _resolve_org_id(request, user, db)
    today = local_today()
    window_start = today - timedelta(days=29)

    # 1. Today's Attendance
    today_att = db.query(Attendance).filter_by(user_id=user.id, date=today).first()
    today_attendance = {
        "has_checked_in": bool(today_att and today_att.check_in),
        "has_checked_out": bool(today_att and today_att.check_out),
        "status": today_att.status if today_att else None,
        "check_in": today_att.check_in.strftime("%H:%M") if (today_att and today_att.check_in) else None,
        "check_out": today_att.check_out.strftime("%H:%M") if (today_att and today_att.check_out) else None,
        "hours_worked": today_att.duration_hours if today_att else 0.0,
        "check_in_photo_url": (
            today_att.check_in_photo
            if (today_att and today_att.check_in_photo and today_att.check_in_photo.startswith(("http://", "https://")))
            else (f"/api/attendance/{today_att.id}/photo/checkin" if (today_att and today_att.check_in_photo) else None)
        ) if today_att else None,
        "check_out_photo_url": (
            today_att.check_out_photo
            if (today_att and today_att.check_out_photo and today_att.check_out_photo.startswith(("http://", "https://")))
            else (f"/api/attendance/{today_att.id}/photo/checkout" if (today_att and today_att.check_out_photo) else None)
        ) if today_att else None,
        "check_in_address": today_att.check_in_address if today_att else None,
    }

    streak = compute_streak(db, user.id)

    # 2. 30-Day Attendance Logs
    rows = (
        db.query(Attendance)
        .filter(Attendance.user_id == user.id, Attendance.date >= window_start, Attendance.date <= today)
        .order_by(Attendance.date.asc())
        .all()
    )
    attendance_chart = [
        {"date": r.date.isoformat(), "hours": r.duration_hours, "status": r.status}
        for r in rows
    ]
    total_hours_worked = round(sum(r.duration_hours for r in rows), 1)

    # 3. Assigned Projects
    assigned_proj_ids = [
        pa.project_id for pa in db.query(ProjectAssignment.project_id).filter_by(user_id=user.id).all()
    ]
    projects_db = (
        db.query(Project)
        .options(joinedload(Project.mentor), joinedload(Project.tasks))
        .filter(Project.id.in_(assigned_proj_ids or [-1]), Project.is_deleted == False)
        .all()
    )
    assigned_projects = [
        {
            "id": p.id,
            "name": p.name,
            "description": p.description,
            "status": p.status,
            "mentor_id": p.mentor_id,
            "mentor_name": p.mentor.name if p.mentor else None,
            "my_tasks_count": len([t for t in p.tasks if t.assigned_to == user.id and not t.is_deleted]),
            "completed_tasks_count": len([t for t in p.tasks if t.assigned_to == user.id and not t.is_deleted and t.status in ("done", "completed")]),
            "created_at": isoformat_utc(p.created_at),
        }
        for p in projects_db
    ]

    project_status = {}
    for p in projects_db:
        project_status[p.status] = project_status.get(p.status, 0) + 1

    # 4. Assigned Tasks
    tasks_db = (
        db.query(Task)
        .options(joinedload(Task.project))
        .filter(Task.assigned_to == user.id, Task.is_deleted == False)
        .order_by(Task.deadline.is_(None), Task.deadline.asc(), Task.created_at.desc())
        .all()
    )
    task_status = {}
    for t in tasks_db:
        task_status[t.status] = task_status.get(t.status, 0) + 1

    assigned_tasks = [
        {
            "id": t.id,
            "title": t.title,
            "description": t.description,
            "status": t.status,
            "priority": t.priority,
            "deadline": t.deadline.isoformat() if t.deadline else None,
            "is_overdue": t.deadline is not None and t.deadline < today and t.status not in ("done", "completed"),
            "project_id": t.project_id,
            "project_name": t.project.name if t.project else None,
            "created_at": isoformat_utc(t.created_at),
        }
        for t in tasks_db
    ]
    open_tasks = [t for t in assigned_tasks if t["status"] not in ("done", "completed")]
    completed_tasks = [t for t in assigned_tasks if t["status"] in ("done", "completed")]
    overdue_tasks = [t for t in open_tasks if t["is_overdue"]]

    # 5. Recent Leave Requests
    leaves = (
        db.query(LeaveRequest)
        .filter_by(user_id=user.id, is_deleted=False)
        .order_by(LeaveRequest.created_at.desc())
        .limit(10)
        .all()
    )
    recent_leave_requests = [
        {
            "id": l.id,
            "start_date": l.start_date.isoformat(),
            "end_date": l.end_date.isoformat(),
            "days": l.days,
            "days_count": l.days,
            "leave_type": l.leave_type,
            "status": l.status,
            "reason": l.reason,
            "created_at": isoformat_utc(l.created_at),
        }
        for l in leaves
    ]
    pending_leave_count = sum(1 for l in leaves if l.status == "pending")

    # 6. Announcements
    announcements_db = (
        db.query(Announcement)
        .filter_by(is_deleted=False)
        .order_by(Announcement.is_pinned.desc(), Announcement.created_at.desc())
        .limit(10)
        .all()
    )
    announcements = [
        {
            "id": a.id,
            "title": a.title,
            "body": a.body,
            "is_pinned": a.is_pinned,
            "created_at": isoformat_utc(a.created_at),
        }
        for a in announcements_db
    ]

    # 7. Recent Activity
    activity_rows = scoped_audit_query(db, user, org_id=org_id).order_by(AuditLog.created_at.desc()).limit(15).all()
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

    present_today = 1 if today_attendance["has_checked_in"] else 0

    stats = {
        "present_today": present_today,
        "total_days_logged": len(rows),
        "total_hours": total_hours_worked,
        "days_logged": len(rows),
        "active_projects": len([p for p in assigned_projects if p["status"] == "active"]),
        "total_projects": len(assigned_projects),
        "assigned_tasks_count": len(assigned_tasks),
        "completed_tasks_count": len(completed_tasks),
        "open_tasks": len(open_tasks),
        "overdue_tasks": len(overdue_tasks),
        "pending_leave": pending_leave_count,
        "total_interns": 0,
    }

    return {
        "role": "intern",
        "today_attendance": today_attendance,
        "streak": streak,
        "stats": stats,
        "assigned_projects": assigned_projects,
        "active_projects": assigned_projects,
        "assigned_tasks": assigned_tasks,
        "open_tasks": open_tasks,
        "attendance_chart": attendance_chart,
        "project_status": project_status,
        "task_status": task_status,
        "recent_leave_requests": recent_leave_requests,
        "announcements": announcements,
        "recent_activity": recent_activity,
    }


def _build_superadmin_dashboard(request: Request, user: User, db: Session) -> dict:
    if not (user.is_platform_admin or user.is_superadmin or user.role in ("superadmin", "admin")):
        raise HTTPException(status_code=403, detail="Forbidden: Super Admin access required.")

    # 1. Organizations List & Stats
    all_orgs = db.query(Organization).filter_by(is_deleted=False).order_by(Organization.created_at.desc()).all()
    total_orgs = len(all_orgs)
    business_orgs = sum(1 for o in all_orgs if o.type == OrganizationType.BUSINESS)
    educational_orgs = sum(1 for o in all_orgs if o.type == OrganizationType.EDUCATIONAL_INSTITUTE)

    # 2. Users Stats
    user_role_counts = (
        db.query(User.role, func.count(User.id))
        .filter_by(is_deleted=False, is_active=True)
        .group_by(User.role)
        .all()
    )
    user_roles = dict(user_role_counts)
    total_users = sum(user_roles.values())
    total_admins = user_roles.get("admin", 0)
    total_mentors = user_roles.get("mentor", 0)
    total_interns = user_roles.get("intern", 0)

    # 3. Projects Count
    total_projects = db.query(Project).filter_by(is_deleted=False).count()

    # 4. Org details list with member and project counts
    members_by_org = dict(
        db.query(OrganizationMembership.organization_id, func.count(OrganizationMembership.id))
        .filter_by(is_active=True, is_deleted=False)
        .group_by(OrganizationMembership.organization_id)
        .all()
    )
    projects_by_org = dict(
        db.query(Project.organization_id, func.count(Project.id))
        .filter_by(is_deleted=False)
        .group_by(Project.organization_id)
        .all()
    )

    orgs_list = [
        {
            "id": o.id,
            "name": o.name,
            "slug": o.slug,
            "type": o.type,
            "status": o.status,
            "timezone": o.timezone,
            "logo_url": o.logo_url,
            "user_count": members_by_org.get(o.id, 0),
            "project_count": projects_by_org.get(o.id, 0),
            "created_at": isoformat_utc(o.created_at),
        }
        for o in all_orgs
    ]

    # 5. Recent Platform Activity
    activity_rows = db.query(AuditLog).order_by(AuditLog.created_at.desc()).limit(25).all()
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

    stats = {
        "total_organizations": total_orgs,
        "total_business_orgs": business_orgs,
        "total_educational_orgs": educational_orgs,
        "total_users": total_users,
        "total_admins": total_admins,
        "total_mentors": total_mentors,
        "total_interns": total_interns,
        "total_projects": total_projects,
        "active_subscriptions": total_orgs,
        "present_today": 0,
        "open_tasks": 0,
        "pending_leave": 0,
    }

    return {
        "role": "superadmin",
        "stats": stats,
        "organizations": orgs_list,
        "recent_activity": recent_activity,
        "system_health": {
            "status": "operational",
            "database": "connected",
            "version": "2.0.0",
        },
        "streak": 0,
    }


# ---------------------------------------------------------------------------
# API Endpoints
# ---------------------------------------------------------------------------

@router.get("")
async def dashboard(request: Request, db: DbSession):
    """Dynamic role-based dashboard endpoint."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    if user.is_platform_admin or user.is_superadmin or user.role == "superadmin":
        return _build_superadmin_dashboard(request, user, db)
    elif user.is_admin:
        return _build_admin_dashboard(request, user, db)
    elif user.is_mentor:
        return _build_mentor_dashboard(request, user, db)
    else:
        return _build_intern_dashboard(request, user, db)


@router.get("/admin")
@admin_dashboard_router.get("")
@root_admin_dashboard_router.get("")
async def admin_dashboard(request: Request, db: DbSession):
    """Full single-response Admin Dashboard."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return _build_admin_dashboard(request, user, db)


@router.get("/mentor")
@mentor_dashboard_router.get("")
@root_mentor_dashboard_router.get("")
async def mentor_dashboard(request: Request, db: DbSession):
    """Full single-response Mentor Dashboard."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return _build_mentor_dashboard(request, user, db)


@router.get("/intern")
@intern_dashboard_router.get("")
@root_intern_dashboard_router.get("")
async def intern_dashboard(request: Request, db: DbSession):
    """Full single-response Intern Dashboard."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return _build_intern_dashboard(request, user, db)


@router.get("/superadmin")
@superadmin_dashboard_router.get("")
@root_superadmin_dashboard_router.get("")
async def superadmin_dashboard(request: Request, db: DbSession):
    """Full single-response Super Admin Dashboard."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return _build_superadmin_dashboard(request, user, db)


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
    """Attendance chart bounded to one calendar month (default: the current month)."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    today = local_today()
    month_param = request.query_params.get("month")
    if month_param:
        try:
            year, month = (int(part) for part in month_param.split("-", 1))
            date(year, month, 1)
        except (ValueError, TypeError):
            raise HTTPException(status_code=422, detail="Invalid month, expected YYYY-MM.")
    else:
        year, month = today.year, today.month

    window_start = date(year, month, 1)
    last_day = monthrange(year, month)[1]
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
