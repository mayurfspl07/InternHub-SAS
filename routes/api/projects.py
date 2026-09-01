"""JSON project and task endpoints."""
from datetime import date, datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import case, func, select

from database import get_db
from dependencies import get_optional_user
from models import (
    Project,
    ProjectAssignment,
    ProjectComment,
    ProjectLink,
    ProjectMentorAssignment,
    ProjectStatus,
    ProjectStatusBucket,
    Task,
    TaskAttachment,
    TaskComment,
    TaskPriority,
    TaskStatus,
    TaskStatusBucket,
    TaskStatusCategory,
    User,
    UserRole,
    BinEntityType,
)
from recycle_bin import move_to_bin
from utils import (
    push_notification,
    record_audit,
    isoformat_utc,
    get_or_seed_org_task_statuses,
    get_or_seed_org_project_statuses,
    get_org_done_statuses,
    save_task_attachment,
    attachment_abs_path,
)
from routes.api.schemas import (
    ProjectCreatePayload,
    ProjectUpdatePayload,
    ProjectAssignPayload,
    TaskCreatePayload,
    TaskUpdatePayload,
    TaskStatusPayload,
    TaskCommentPayload,
    ProjectBoardCommentPayload,
    ProjectLinkPayload,
    get_payload,
)

router = APIRouter(prefix="/api/projects", tags=["Projects"])
task_router = APIRouter(prefix="/api/tasks", tags=["Tasks"])
DbSession = Annotated[Session, Depends(get_db)]
PAGE_SIZE = 12

_STATUS_LABELS = {
    "todo": "to do",
    "in_progress": "in progress",
    "review": "review",
    "done": "done",
    "completed": "completed",
}


def _status_label(status: str) -> str:
    return _STATUS_LABELS.get(status, status.replace("_", " "))


def _validate_org_task_status(db: Session, org_id: int | None, status: str) -> str:
    """Validate status against organization buckets, with fallback to TaskStatus.ALL."""
    norm_status = str(status).strip()
    if norm_status == "completed":
        norm_status = "done"

    if org_id is not None:
        buckets = get_or_seed_org_task_statuses(db, org_id)
        valid_slugs = {b.slug for b in buckets}.union({"todo", "in_progress", "done"})
        if norm_status in valid_slugs:
            return norm_status
        raise HTTPException(status_code=422, detail="Invalid status.")

    if norm_status in TaskStatus.ALL:
        return norm_status
    raise HTTPException(status_code=422, detail="Invalid status.")


def _validate_org_project_status(db: Session, org_id: int | None, status: str) -> str:
    """Validate project status against organization buckets, with fallback to ProjectStatus.ALL."""
    norm_status = str(status).strip()
    if org_id is not None:
        buckets = get_or_seed_org_project_statuses(db, org_id)
        valid_slugs = {b.slug for b in buckets}.union(ProjectStatus.ALL)
        if norm_status in valid_slugs:
            return norm_status
        raise HTTPException(status_code=422, detail=f"Invalid project status '{norm_status}'.")

    if norm_status in ProjectStatus.ALL:
        return norm_status
    raise HTTPException(status_code=422, detail=f"Invalid project status '{norm_status}'.")


@router.get("/project-statuses")
@router.get("/statuses")
async def get_project_statuses_dropdown(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    org_id = _resolve_request_org_id(request, user, db) or 1
    buckets = get_or_seed_org_project_statuses(db, org_id)
    return {"statuses": [b.to_dict() for b in buckets]}


@router.get("/task-statuses")
@router.get("/{project_id}/task-statuses")
async def get_project_task_statuses(
    request: Request,
    db: DbSession,
    project_id: int | None = None,
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    org_id = None
    if project_id:
        project = db.query(Project).filter_by(id=project_id, is_deleted=False).first()
        if project:
            org_id = project.organization_id
    if org_id is None:
        org_id = _resolve_request_org_id(request, user, db) or 1

    buckets = get_or_seed_org_task_statuses(db, org_id)
    return {"statuses": [b.to_dict() for b in buckets]}


def _mentor_user_dict(user: User) -> dict:
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "role": UserRole.MENTOR,
    }


def _ordered_project_mentors(project: Project) -> tuple[list[int], list[dict]]:
    """Return mentor_ids and mentors[] with primary mentor first."""
    mentor_users: dict[int, User] = {}
    assignment_order: list[int] = []

    for ma in sorted(
        project.mentor_assignments,
        key=lambda row: (row.assigned_at, row.id),
    ):
        if ma.user and ma.user.role == UserRole.MENTOR:
            mentor_users.setdefault(ma.user.id, ma.user)
            if ma.user.id not in assignment_order:
                assignment_order.append(ma.user.id)

    if project.mentor and project.mentor.role == UserRole.MENTOR:
        mentor_users.setdefault(project.mentor.id, project.mentor)

    mentor_ids: list[int] = []
    if project.mentor_id and project.mentor_id in mentor_users:
        mentor_ids.append(project.mentor_id)
    for mentor_id in assignment_order:
        if mentor_id not in mentor_ids:
            mentor_ids.append(mentor_id)
    for mentor_id in sorted(mentor_users):
        if mentor_id not in mentor_ids:
            mentor_ids.append(mentor_id)

    mentors = [_mentor_user_dict(mentor_users[mid]) for mid in mentor_ids]
    return mentor_ids, mentors


def _comment_preview(body: str, limit: int = 60) -> str:
    text = body.strip()
    return text if len(text) <= limit else f"{text[:limit].rstrip()}…"


def _notify_new_comment(
    db: Session,
    project: Project,
    commenter: User,
    recipient_ids: set[int],
    message: str,
    link: str,
) -> None:
    """Push a notification to everyone in recipient_ids except the commenter."""
    for uid in recipient_ids:
        if uid == commenter.id:
            continue
        push_notification(db, uid, message, link=link)


def _project_dict(
    p: Project,
    *,
    task_done: int | None = None,
    task_total: int | None = None,
) -> dict:
    mentor_ids, mentors = _ordered_project_mentors(p)
    primary_mentor = p.mentor if p.mentor else None
    intern_members = [
        {"id": a.user.id, "name": a.user.name, "email": a.user.email, "role": a.user.role}
        for a in p.assignments if a.user and a.user.role == UserRole.INTERN
    ]
    if task_total is not None:
        progress = int((task_done or 0) * 100 / task_total) if task_total else 0
        task_count = task_total
    else:
        progress = p.progress_pct
        task_count = p.task_count
    return {
        "id": p.id,
        "name": p.name,
        "description": p.description,
        "start_date": p.start_date.isoformat() if p.start_date else None,
        "end_date": p.end_date.isoformat() if p.end_date else None,
        "status": p.status,
        "mentor_id": mentor_ids[0] if mentor_ids else p.mentor_id,
        "mentor_name": primary_mentor.name if primary_mentor else None,
        "mentor_ids": mentor_ids,
        "mentors": mentors,
        "progress": progress,
        "task_count": task_count,
        "task_done": task_done or 0,
        "task_total": task_total or 0,
        "created_at": isoformat_utc(p.created_at),
        "intern_ids": [a.user_id for a in p.assignments if a.user and a.user.role == UserRole.INTERN],
        "members": intern_members,
    }


def _task_stats_for_projects(db: Session, project_ids: list[int]) -> dict[int, tuple[int, int]]:
    """Return {project_id: (done_count, total_count)} without loading full task rows."""
    if not project_ids:
        return {}
    done_bucket_slugs = {
        r[0] for r in db.query(TaskStatusBucket.slug).filter_by(status_category=TaskStatusCategory.DONE).all()
    }.union({TaskStatus.DONE, "done", "completed"})
    rows = (
        db.query(
            Task.project_id,
            func.count(Task.id),
            func.sum(case((Task.status.in_(done_bucket_slugs), 1), else_=0)),
        )
        .filter(Task.project_id.in_(project_ids), Task.is_deleted == False)
        .group_by(Task.project_id)
        .all()
    )
    return {pid: (int(done or 0), int(total)) for pid, total, done in rows}


def _normalize_mentor_ids(db: Session, raw_mentor_ids, fallback_id: int | None) -> list[int]:
    ids: list[int] = []
    if isinstance(raw_mentor_ids, list):
        for mid in raw_mentor_ids:
            try:
                m_id = int(mid)
            except Exception:
                continue
            mentor = db.get(User, m_id)
            if mentor and mentor.role == UserRole.MENTOR and mentor.is_active:
                ids.append(m_id)
    if fallback_id:
        try:
            f_id = int(fallback_id)
            mentor = db.get(User, f_id)
            if mentor and mentor.role == UserRole.MENTOR and mentor.is_active:
                if f_id not in ids:
                    ids.insert(0, f_id)
        except Exception:
            pass
    deduped: list[int] = []
    seen = set()
    for x in ids:
        if x not in seen:
            seen.add(x)
            deduped.append(x)
    return deduped


def _resolve_mentor_ids(
    db: Session,
    data: dict,
    *,
    user: User,
    project: Project | None = None,
    required: bool = True,
) -> list[int]:
    """Parse mentor_ids / legacy mentor_id from create/update payloads."""
    raw_ids = data.get("mentor_ids")
    fallback_id = data.get("mentor_id")
    if raw_ids is None and fallback_id is None and project is not None:
        fallback_id = project.mentor_id
    if raw_ids is None and fallback_id is None and user.is_mentor:
        fallback_id = user.id

    mentor_ids = _normalize_mentor_ids(db, raw_ids, fallback_id)
    if required and not mentor_ids:
        raise HTTPException(status_code=422, detail="At least one mentor is required.")

    if user.is_mentor and not user.is_admin and user.id not in mentor_ids:
        raise HTTPException(
            status_code=403,
            detail="You must include yourself in mentor assignments.",
        )
    return mentor_ids


def _apply_project_mentors(db: Session, project: Project, mentor_ids: list[int]) -> None:
    project.mentor_id = mentor_ids[0]
    _sync_project_mentors(db, project, mentor_ids)


def _project_load_options():
    return (
        joinedload(Project.mentor),
        joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
        joinedload(Project.tasks),
        joinedload(Project.assignments).joinedload(ProjectAssignment.user),
    )


def _load_project(db: Session, project_id: int) -> Project | None:
    return (
        db.query(Project)
        .options(*_project_load_options())
        .filter_by(id=project_id, is_deleted=False)
        .first()
    )


def _filter_projects_by_mentor(query, db: Session, mentor_id: int):
    co_mentor_project_ids = select(ProjectMentorAssignment.project_id).where(
        ProjectMentorAssignment.user_id == mentor_id
    )
    return query.filter(
        (Project.mentor_id == mentor_id) | (Project.id.in_(co_mentor_project_ids))
    )


def _sync_project_mentors(db: Session, project: Project, mentor_ids: list[int]) -> None:
    target_ids = set(mentor_ids)
    current_ids = {
        ma.user_id for ma in db.query(ProjectMentorAssignment).filter_by(project_id=project.id).all()
    }
    for uid in target_ids - current_ids:
        db.add(ProjectMentorAssignment(project_id=project.id, user_id=uid))
    for uid in current_ids - target_ids:
        row = db.query(ProjectMentorAssignment).filter_by(project_id=project.id, user_id=uid).first()
        if row:
            db.delete(row)


def _task_dict(t: Task, *, user: User, db: Session, project: Project) -> dict:
    due = t.deadline.isoformat() if t.deadline else None
    attachments_list = [a.to_dict() for a in t.attachments] if hasattr(t, "attachments") and t.attachments else []
    return {
        "id": t.id,
        "project_id": t.project_id,
        "title": t.title,
        "description": t.description,
        "created_by_id": t.created_by_id,
        "created_by_name": t.creator.name if t.creator else None,
        "assigned_to": t.assigned_to,
        "assignee_name": t.assignee.name if t.assignee else None,
        "due_date": due,
        "deadline": due,
        "status": t.status,
        "priority": t.priority,
        "is_overdue": t.is_overdue,
        "can_delete": _can_delete_task(db, user, project, t),
        "created_at": isoformat_utc(t.created_at),
        "comment_count": len([c for c in t.comments if not c.is_deleted]) if hasattr(t, "comments") and t.comments else 0,
        "attachment_count": len(attachments_list),
        "attachments": attachments_list,
    }


def _comment_dict(c: TaskComment, attachment_dict: dict | None = None) -> dict:
    author = c.author.name if c.author else None
    data = {
        "id": c.id,
        "task_id": c.task_id,
        "user_id": c.user_id,
        "user_name": author,
        "author_name": author,
        # Deleted comments keep their row (and place in the thread) but drop the body —
        # the point is to show a comment existed and who removed it, not to leak content.
        "body": None if c.is_deleted else c.body,
        "created_at": isoformat_utc(c.created_at),
        "updated_at": isoformat_utc(c.updated_at),
        "is_deleted": c.is_deleted,
        "deleted_at": isoformat_utc(c.deleted_at) if c.deleted_at else None,
        "deleted_by_name": c.deleted_by.name if c.deleted_by else None,
    }
    if attachment_dict is not None:
        data["attachment"] = attachment_dict
    return data


def _visible_projects_query(db, user):
    if user.is_admin:
        return db.query(Project).filter_by(is_deleted=False)
    if user.is_mentor:
        mentor_project_ids = db.query(ProjectMentorAssignment.project_id).filter_by(user_id=user.id).scalar_subquery()
        return db.query(Project).filter(
            (Project.mentor_id == user.id) | (Project.id.in_(mentor_project_ids)),
            Project.is_deleted == False,
        )
    assigned_ids = db.query(ProjectAssignment.project_id).filter_by(user_id=user.id).scalar_subquery()
    return db.query(Project).filter(Project.id.in_(assigned_ids), Project.is_deleted == False)


def _resolve_request_org_id(request: Request, user: User, db: Session) -> int | None:
    header_val = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if header_val and str(header_val).isdigit():
        return int(header_val)
    from models import OrganizationMembership
    mem = db.query(OrganizationMembership).filter_by(user_id=user.id, is_active=True, is_deleted=False).first()
    return mem.organization_id if mem else None


def _can_edit(user, project):
    if user.is_admin:
        return True
    if not user.is_mentor:
        return False
    if project.mentor_id == user.id:
        return True
    return any(ma.user_id == user.id for ma in project.mentor_assignments)


def _is_project_member(db, user, project) -> bool:
    if user.is_admin:
        return True
    if user.is_mentor and project.mentor_id == user.id:
        return True
    if user.is_mentor:
        mentor_assignment = (
            db.query(ProjectMentorAssignment)
            .filter_by(project_id=project.id, user_id=user.id)
            .first()
        )
        if mentor_assignment is not None:
            return True
    return (
        db.query(ProjectAssignment)
        .filter_by(project_id=project.id, user_id=user.id)
        .first()
        is not None
    )


def _can_update_task(user, project, task, db) -> bool:
    return user.is_admin or _can_edit(user, project) or task.assigned_to == user.id


def _can_move_task(user, project, task, db) -> bool:
    """Drag-and-drop status changes: staff, assignee, or any intern on the project."""
    if _can_update_task(user, project, task, db):
        return True
    return user.is_intern and _is_project_member(db, user, project)


def _can_delete_task(db, user, project, task) -> bool:
    if user.is_admin or _can_edit(user, project):
        return True
    return (
        user.is_intern
        and task.created_by_id == user.id
        and _is_project_member(db, user, project)
    )


@router.get("")
async def list_projects(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    params = request.query_params
    status = params.get("status")
    mentor_id = params.get("mentor_id")
    from_date = params.get("from_date") or params.get("start_date") or params.get("from") or params.get("start")
    to_date = params.get("to_date") or params.get("end_date") or params.get("to") or params.get("end")
    search = (params.get("search") or params.get("q") or "").strip()
    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = max(1, min(100, int(params.get("page_size", PAGE_SIZE))))
    except ValueError:
        page_size = PAGE_SIZE

    q = _visible_projects_query(db, user)
    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if header_org and str(header_org).isdigit():
        org_id = int(header_org)
        q = q.filter((Project.organization_id == org_id) | (Project.organization_id.is_(None)))

    if search:
        pattern = f"%{search}%"
        q = q.filter(
            (Project.name.ilike(pattern)) | (func.coalesce(Project.description, "").ilike(pattern))
        )
    if status:
        q = q.filter(Project.status == status)
    if mentor_id and mentor_id.isdigit():
        q = _filter_projects_by_mentor(q, db, int(mentor_id))
    if from_date:
        try:
            from_dt = date.fromisoformat(str(from_date).strip())
            q = q.filter(func.coalesce(Project.start_date, func.date(Project.created_at)) >= from_dt)
        except ValueError:
            pass
    if to_date:
        try:
            to_dt = date.fromisoformat(str(to_date).strip())
            q = q.filter(func.coalesce(Project.end_date, Project.start_date, func.date(Project.created_at)) <= to_dt)
        except ValueError:
            pass

    total = q.count()
    projects = q.options(
        joinedload(Project.mentor),
        joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
        joinedload(Project.assignments).joinedload(ProjectAssignment.user),
    ).order_by(Project.created_at.desc()).offset((page - 1) * page_size).limit(page_size).all()
    task_stats = _task_stats_for_projects(db, [p.id for p in projects])
    total_pages = max(1, (total + page_size - 1) // page_size)
    return {
        "projects": [
            _project_dict(
                p,
                task_done=task_stats.get(p.id, (0, 0))[0],
                task_total=task_stats.get(p.id, (0, 0))[1],
            )
            for p in projects
        ],
        "page": page,
        "page_size": page_size,
        "total_pages": total_pages,
        "total": total,
        "filters": {
            "search": search or None,
            "status": status or None,
            "mentor_id": int(mentor_id) if (mentor_id and mentor_id.isdigit()) else None,
            "from_date": str(from_date).strip() if from_date else None,
            "to_date": str(to_date).strip() if to_date else None,
        },
    }


@router.get("/search")
async def search_projects(request: Request, db: DbSession):
    """Fast scoped project search and autocomplete with optional date and mentor filters."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    params = request.query_params
    q_str = (params.get("q") or params.get("query") or params.get("search") or "").strip()
    status = params.get("status")
    mentor_id = params.get("mentor_id")
    from_date = params.get("from_date") or params.get("start_date") or params.get("from") or params.get("start")
    to_date = params.get("to_date") or params.get("end_date") or params.get("to") or params.get("end")
    try:
        limit = min(50, max(1, int(params.get("limit", 20))))
    except ValueError:
        limit = 20

    q = _visible_projects_query(db, user)
    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if header_org and str(header_org).isdigit():
        org_id = int(header_org)
        q = q.filter((Project.organization_id == org_id) | (Project.organization_id.is_(None)))

    if q_str:
        pattern = f"%{q_str}%"
        q = q.filter(
            (Project.name.ilike(pattern)) | (func.coalesce(Project.description, "").ilike(pattern))
        )
    if status:
        q = q.filter(Project.status == status)
    if mentor_id and mentor_id.isdigit():
        q = _filter_projects_by_mentor(q, db, int(mentor_id))
    if from_date:
        try:
            from_dt = date.fromisoformat(str(from_date).strip())
            q = q.filter(func.coalesce(Project.start_date, func.date(Project.created_at)) >= from_dt)
        except ValueError:
            pass
    if to_date:
        try:
            to_dt = date.fromisoformat(str(to_date).strip())
            q = q.filter(func.coalesce(Project.end_date, Project.start_date, func.date(Project.created_at)) <= to_dt)
        except ValueError:
            pass

    projects = q.options(
        joinedload(Project.mentor),
        joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
        joinedload(Project.assignments).joinedload(ProjectAssignment.user),
    ).order_by(Project.created_at.desc()).limit(limit).all()

    task_stats = _task_stats_for_projects(db, [p.id for p in projects])

    return {
        "query": q_str,
        "total": len(projects),
        "filters": {
            "query": q_str or None,
            "status": status or None,
            "mentor_id": int(mentor_id) if (mentor_id and mentor_id.isdigit()) else None,
            "from_date": str(from_date).strip() if from_date else None,
            "to_date": str(to_date).strip() if to_date else None,
        },
        "projects": [
            _project_dict(
                p,
                task_done=task_stats.get(p.id, (0, 0))[0],
                task_total=task_stats.get(p.id, (0, 0))[1],
            )
            for p in projects
        ],
    }


@router.get("/interns")
@router.get("/interns/dropdown")
async def get_project_interns(request: Request, db: DbSession):
    """Dropdown list of all active interns for project assignment."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    interns = (
        db.query(User)
        .filter(User.role == UserRole.INTERN, User.is_active == True, User.is_deleted == False)
        .order_by(User.name.asc())
        .all()
    )
    items = [
        {
            "id": u.id,
            "name": u.name,
            "email": u.email,
            "role": u.role,
            "department": u.department,
            "job_title": u.job_title,
            "mentor_id": u.mentor_id,
            "is_active": u.is_active,
        }
        for u in interns
    ]
    return {
        "interns": items,
        "total": len(items),
    }


@router.get("/mentors")
@router.get("/mentors/dropdown")
async def get_project_mentors(request: Request, db: DbSession):
    """Dropdown list of all active mentors for project mentor assignment."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    mentors = (
        db.query(User)
        .filter(User.role == UserRole.MENTOR, User.is_active == True, User.is_deleted == False)
        .order_by(User.name.asc())
        .all()
    )
    items = [
        {
            "id": m.id,
            "name": m.name,
            "email": m.email,
            "role": m.role,
            "department": m.department,
            "job_title": m.job_title,
        }
        for m in mentors
    ]
    return {
        "mentors": items,
        "total": len(items),
    }


@router.post("")
async def create_project(request: Request, db: DbSession, data: ProjectCreatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    payload = await get_payload(request, data)
    name = str(payload.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=422, detail="Project name is required.")
    start = None
    if payload.get("start_date"):
        try:
            start = date.fromisoformat(str(payload["start_date"]))
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid start date.")
    end = None
    if payload.get("end_date"):
        try:
            end = date.fromisoformat(str(payload["end_date"]))
        except ValueError:
            pass
    mentor_ids = _resolve_mentor_ids(db, payload, user=user, required=True)
    org_id = _resolve_request_org_id(request, user, db)
    status = _validate_org_project_status(db, org_id, payload.get("status", "planning"))

    project = Project(
        organization_id=org_id,
        name=name,
        description=str(payload.get("description", "")).strip(),
        start_date=start,
        end_date=end,
        status=status,
        mentor_id=mentor_ids[0],
    )
    db.add(project)
    db.commit()
    db.refresh(project)
    _apply_project_mentors(db, project, mentor_ids)
    db.commit()
    record_audit(db, user, "project.create", "created project", name, project_id=project.id)
    # Support both intern_ids and member_ids key names from the frontend
    intern_ids = payload.get("intern_ids") or payload.get("member_ids") or []
    for intern_id in intern_ids:
        try:
            uid = int(intern_id)
        except (TypeError, ValueError):
            continue
        intern = db.get(User, uid)
        if not intern or intern.role != UserRole.INTERN:
            continue
        if not db.query(ProjectAssignment).filter_by(project_id=project.id, user_id=uid).first():
            db.add(ProjectAssignment(project_id=project.id, user_id=uid))
    db.commit()
    project = _load_project(db, project.id)
    return _project_dict(project)


@router.get("/{project_id}")
async def get_project(project_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    project = db.query(Project).options(
        joinedload(Project.mentor),
        joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
        joinedload(Project.tasks).joinedload(Task.assignee),
        joinedload(Project.tasks).joinedload(Task.creator),
        joinedload(Project.tasks).joinedload(Task.comments).joinedload(TaskComment.author),
        joinedload(Project.assignments).joinedload(ProjectAssignment.user),
    ).filter_by(id=project_id, is_deleted=False).first()
    if not project:
        raise HTTPException(status_code=404)

    # Cross-tenant isolation: when explicit X-Organization-Id header is passed
    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if header_org and str(header_org).isdigit():
        req_org = int(header_org)
        if project.organization_id is not None and project.organization_id != req_org:
            raise HTTPException(status_code=404, detail="Project not found.")

    if not _is_project_member(db, user, project):
        raise HTTPException(status_code=403)
    active_tasks = [t for t in project.tasks if not t.is_deleted]
    done_statuses = get_org_done_statuses(db, project.organization_id)
    done_count = sum(
        1 for t in active_tasks if t.status in done_statuses
    )
    return {
        **_project_dict(project, task_done=done_count, task_total=len(active_tasks)),
        "tasks": [
            _task_dict(t, user=user, db=db, project=project)
            for t in active_tasks
        ],
        "can_edit": _can_edit(user, project),
    }


@router.get("/{project_id}/export")
async def export_project(project_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    project = db.query(Project).options(
        joinedload(Project.mentor),
        joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
        joinedload(Project.tasks).joinedload(Task.assignee),
        joinedload(Project.tasks).joinedload(Task.creator),
        joinedload(Project.tasks).joinedload(Task.comments).joinedload(TaskComment.author),
        joinedload(Project.assignments).joinedload(ProjectAssignment.user),
    ).filter_by(id=project_id, is_deleted=False).first()
    if not project:
        raise HTTPException(status_code=404)
    if not _is_project_member(db, user, project):
        raise HTTPException(status_code=403)

    members = []
    mentor_ids = set()
    if project.mentor:
        mentor_ids.add(project.mentor.id)
        members.append({
            "id": project.mentor.id,
            "name": project.mentor.name,
            "email": project.mentor.email,
            "role": "mentor",
        })
    for ma in project.mentor_assignments:
        if ma.user and ma.user.role == UserRole.MENTOR and ma.user.id not in mentor_ids:
            mentor_ids.add(ma.user.id)
            members.append({
                "id": ma.user.id,
                "name": ma.user.name,
                "email": ma.user.email,
                "role": ma.user.role,
            })
    members.extend([
        {"id": a.user.id, "name": a.user.name, "email": a.user.email, "role": a.user.role}
        for a in project.assignments if a.user
    ])
    tasks = []
    for t in [x for x in project.tasks if not x.is_deleted]:
        tasks.append({
            **_task_dict(t, user=user, db=db, project=project),
            "comments": [_comment_dict(c) for c in t.comments if not c.is_deleted],
        })
    return {
        "project": _project_dict(project),
        "members": members,
        "tasks": tasks,
        "exported_at": isoformat_utc(datetime.now(timezone.utc)),
    }


@router.put("/{project_id}")
async def update_project(project_id: int, request: Request, db: DbSession, data: ProjectUpdatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    project = db.get(Project, project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404)
    if not _can_edit(user, project):
        raise HTTPException(status_code=403)

    payload = await get_payload(request, data)
    name = str(payload.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=422, detail="Project name is required.")
    project.name = name
    project.description = str(payload.get("description", "")).strip()
    if payload.get("start_date"):
        try:
            project.start_date = date.fromisoformat(str(payload["start_date"]))
        except ValueError:
            pass
    if "end_date" in payload:
        raw_end = payload["end_date"]
        if raw_end:
            try:
                project.end_date = date.fromisoformat(str(raw_end))
            except ValueError:
                pass  # keep existing end_date on parse error
        else:
            project.end_date = None  # explicit null/empty clears it
    if payload.get("status"):
        project.status = _validate_org_project_status(db, project.organization_id, payload["status"])
    if "mentor_ids" in payload or "mentor_id" in payload:
        mentor_ids = _resolve_mentor_ids(
            db,
            payload,
            user=user,
            project=project,
            required=True,
        )
        _apply_project_mentors(db, project, mentor_ids)
    intern_ids = payload.get("intern_ids")
    if intern_ids is None:
        intern_ids = payload.get("member_ids")
    if intern_ids is not None:
        target_ids = set()
        for i in intern_ids:
            try:
                target_ids.add(int(i))
            except (TypeError, ValueError):
                continue
        current_ids = {
            a.user_id
            for a in db.query(ProjectAssignment).filter_by(project_id=project.id).all()
        }
        for uid in target_ids - current_ids:
            intern = db.get(User, uid)
            if intern and intern.role == "intern":
                db.add(ProjectAssignment(project_id=project.id, user_id=uid))
                push_notification(
                    db, uid,
                    f"You have been assigned to project: {project.name}",
                    link=f"/projects/{project.id}",
                )
        for uid in current_ids - target_ids:
            assignment = (
                db.query(ProjectAssignment)
                .filter_by(project_id=project.id, user_id=uid)
                .first()
            )
            if assignment:
                db.delete(assignment)
    db.commit()
    project = _load_project(db, project.id)
    record_audit(db, user, "project.update", "updated project", project.name, project_id=project.id)
    db.commit()
    return _project_dict(project)


@router.delete("/{project_id}")
async def delete_project(project_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    project = db.get(Project, project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404)
    if not _can_edit(user, project):
        raise HTTPException(status_code=403)
    move_to_bin(db, user, BinEntityType.PROJECT, project, title=project.name)
    record_audit(db, user, "project.delete", "deleted project", project.name, project_id=project.id)
    db.commit()
    return {"ok": True}


@router.post("/{project_id}/assign")
async def assign_intern(project_id: int, request: Request, db: DbSession, data: ProjectAssignPayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    project = db.get(Project, project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404)
    if not _can_edit(user, project):
        raise HTTPException(status_code=403)
    payload = await get_payload(request, data)
    try:
        intern_id = int(payload.get("user_id", 0))
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Invalid user_id.")
    if not intern_id:
        raise HTTPException(status_code=422, detail="user_id required")
    if not db.query(ProjectAssignment).filter_by(project_id=project.id, user_id=intern_id).first():
        intern = db.get(User, intern_id)
        db.add(ProjectAssignment(project_id=project.id, user_id=intern_id))
        push_notification(db, intern_id, f"You have been assigned to project: {project.name}", link=f"/projects/{project.id}")
        record_audit(
            db,
            user,
            "project.assign",
            "assigned intern to project",
            f"{intern.name if intern else intern_id} → {project.name}",
            project_id=project.id,
            affected_user_id=intern_id,
        )
        db.commit()
    return {"ok": True}


@router.delete("/{project_id}/assign/{user_id}")
async def unassign_intern(project_id: int, user_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    project = db.get(Project, project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404)
    if not _can_edit(user, project):
        raise HTTPException(status_code=403)
    assignment = db.query(ProjectAssignment).filter_by(project_id=project.id, user_id=user_id).first()
    if assignment:
        intern = db.get(User, user_id)
        db.delete(assignment)
        record_audit(
            db,
            user,
            "project.unassign",
            "removed intern from project",
            f"{intern.name if intern else user_id} ← {project.name}",
            project_id=project.id,
            affected_user_id=user_id,
        )
        db.commit()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------

@router.post("/{project_id}/tasks")
async def create_task(project_id: int, request: Request, db: DbSession, data: TaskCreatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    project = db.get(Project, project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404)
    if user.is_intern:
        is_assigned = db.query(ProjectAssignment).filter_by(project_id=project.id, user_id=user.id).first()
        if not is_assigned:
            raise HTTPException(status_code=403)

    payload = await get_payload(request, data)
    title = str(payload.get("title", "")).strip()
    if not title:
        raise HTTPException(status_code=422, detail="Task title is required.")
    deadline = None
    deadline_raw = payload.get("due_date") or payload.get("deadline")
    if deadline_raw:
        try:
            deadline = date.fromisoformat(str(deadline_raw))
        except ValueError:
            pass
    assigned_to_raw = payload.get("assigned_to")
    if assigned_to_raw in (None, "", 0, "0"):
        # Interns' tasks default to themselves; staff may leave a task unassigned
        assigned_to = user.id if user.is_intern else None
    else:
        try:
            assigned_to = int(assigned_to_raw)
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="Invalid assignee.")
        if not db.get(User, assigned_to):
            raise HTTPException(status_code=422, detail="Assignee not found.")
    priority = str(payload.get("priority", TaskPriority.MEDIUM))
    if priority not in (TaskPriority.LOW, TaskPriority.MEDIUM, TaskPriority.HIGH):
        priority = TaskPriority.MEDIUM
    org_id = project.organization_id or _resolve_request_org_id(request, user, db) or 1
    raw_status = payload.get("status")
    if raw_status:
        task_status = _validate_org_task_status(db, org_id, raw_status)
    else:
        buckets = get_or_seed_org_task_statuses(db, org_id)
        default_bucket = next((b for b in buckets if b.is_default), None)
        task_status = default_bucket.slug if default_bucket else TaskStatus.TODO

    task = Task(
        project_id=project.id,
        organization_id=org_id,
        created_by_id=user.id,
        title=title,
        description=str(payload.get("description", "")).strip(),
        assigned_to=assigned_to,
        deadline=deadline,
        status=task_status,
        priority=priority,
    )
    db.add(task)
    if assigned_to and assigned_to != user.id:
        push_notification(db, assigned_to, f"New task assigned: {title} (Project: {project.name})", link=f"/projects/{project.id}")
        assignee_user = db.get(User, assigned_to)
        if assignee_user:
            from email_service import send_task_assigned_email
            send_task_assigned_email(db, org_id, task, assignee_user, user)
    record_audit(db, user, "task.create", "created task", title, project_id=project.id)
    db.commit()
    db.refresh(task)
    return _task_dict(task, user=user, db=db, project=project)


@router.put("/tasks/{task_id}")
async def update_task(task_id: int, request: Request, db: DbSession, data: TaskUpdatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    project = task.project
    if not _can_move_task(user, project, task, db):
        raise HTTPException(status_code=403)
    
    payload_dict = await get_payload(request, data)
    if user.is_intern and task.assigned_to != user.id and not _can_edit(user, project):
        if set(payload_dict.keys()) - {"status"}:
            raise HTTPException(status_code=403, detail="You can only update status on this task.")

    title = str(payload_dict.get("title", task.title) if payload_dict.get("title") is not None else task.title).strip()
    if not title:
        raise HTTPException(status_code=422, detail="Task title is required.")
    old_assignee = task.assigned_to
    if "assigned_to" in payload_dict and payload_dict["assigned_to"] is not None:
        raw_assignee = payload_dict["assigned_to"]
        if raw_assignee in (None, "", 0, "0"):
            assigned_to = None  # explicit unassign
        else:
            try:
                assigned_to = int(raw_assignee)
            except (TypeError, ValueError):
                raise HTTPException(status_code=422, detail="Invalid assignee.")
            if not db.get(User, assigned_to):
                raise HTTPException(status_code=422, detail="Assignee not found.")
    else:
        assigned_to = task.assigned_to
    deadline = task.deadline
    deadline_raw = payload_dict.get("due_date") if "due_date" in payload_dict else payload_dict.get("deadline")
    if deadline_raw:  # truthy string value → parse
        try:
            deadline = date.fromisoformat(str(deadline_raw))
        except ValueError:
            pass
    elif "due_date" in payload_dict or "deadline" in payload_dict:
        # Key present but value is None or empty string → clear the deadline
        deadline = None
    old_status = task.status
    if "status" in payload_dict and payload_dict["status"] is not None:
        org_id = project.organization_id or task.organization_id or _resolve_request_org_id(request, user, db) or 1
        new_status = _validate_org_task_status(db, org_id, payload_dict["status"])
    else:
        new_status = task.status
    task.title = title
    if "description" in payload_dict and payload_dict["description"] is not None:
        task.description = str(payload_dict["description"]).strip()
    task.deadline = deadline
    if "priority" in payload_dict and payload_dict["priority"] is not None:
        new_priority = str(payload_dict["priority"])
        task.priority = new_priority if new_priority in (TaskPriority.LOW, TaskPriority.MEDIUM, TaskPriority.HIGH) else task.priority
    task.status = new_status
    task.assigned_to = assigned_to
    if assigned_to and assigned_to != old_assignee:
        push_notification(db, assigned_to, f"Task reassigned to you: {title} (Project: {project.name})", link=f"/projects/{project.id}")
    if old_status != new_status:
        record_audit(
            db,
            user,
            "task.status",
            "changed task status",
            f"{title}: {_status_label(old_status)} → {_status_label(new_status)}",
            project_id=project.id,
        )
    else:
        record_audit(db, user, "task.update", "updated task", title, project_id=project.id)
    db.commit()
    return _task_dict(task, user=user, db=db, project=project)


@router.patch("/tasks/{task_id}/status")
async def update_task_status(task_id: int, request: Request, db: DbSession, data: TaskStatusPayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    project = task.project
    if not _can_move_task(user, project, task, db):
        raise HTTPException(status_code=403)
    payload = await get_payload(request, data)
    new_status_raw = payload.get("status")
    if not new_status_raw:
        raise HTTPException(status_code=422, detail="Status is required.")
    org_id = project.organization_id or task.organization_id or _resolve_request_org_id(request, user, db) or 1
    new_status = _validate_org_task_status(db, org_id, new_status_raw)
    old_status = task.status
    task.status = str(new_status)
    record_audit(
        db,
        user,
        "task.status",
        "changed task status",
        f"{task.title}: {_status_label(old_status)} → {_status_label(task.status)}",
        project_id=project.id,
    )
    db.commit()
    return _task_dict(task, user=user, db=db, project=project)


@task_router.delete("/{task_id}")
@router.delete("/tasks/{task_id}", include_in_schema=False)
async def delete_task(task_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    project = task.project
    if not _can_delete_task(db, user, project, task):
        raise HTTPException(status_code=403)
    move_to_bin(db, user, BinEntityType.TASK, task, title=task.title)
    record_audit(db, user, "task.delete", "deleted task", task.title, project_id=project.id)
    db.commit()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Task comments
# ---------------------------------------------------------------------------

@router.get("/tasks/{task_id}/comments")
async def get_comments(task_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    if not _is_project_member(db, user, task.project):
        raise HTTPException(status_code=403)
    comments = (
        db.query(TaskComment)
        .options(joinedload(TaskComment.author), joinedload(TaskComment.deleted_by))
        .filter_by(task_id=task_id)
        .order_by(TaskComment.created_at)
        .all()
    )
    return [_comment_dict(c) for c in comments]


@router.post("/tasks/{task_id}/attachments")
async def upload_task_attachment(
    task_id: int,
    request: Request,
    db: DbSession,
    file: UploadFile = File(...),
    description: str | None = Form(None),
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    if not _is_project_member(db, user, task.project):
        raise HTTPException(status_code=403)

    if not file or not file.filename:
        raise HTTPException(status_code=422, detail="No file uploaded.")

    content = await file.read()
    try:
        rel_path, safe_name, file_size = save_task_attachment(
            task.id, user.id, file.filename, content
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    mime = file.content_type or "application/octet-stream"
    attachment = TaskAttachment(
        task_id=task.id,
        user_id=user.id,
        file_name=safe_name,
        file_path=rel_path,
        file_size=file_size,
        file_type=mime,
        description=str(description).strip() if description else None,
    )
    db.add(attachment)
    record_audit(
        db,
        user,
        "task.attachment_uploaded",
        "uploaded attachment to task",
        f"{task.title}: {safe_name}",
        project_id=task.project_id,
    )
    db.commit()
    db.refresh(attachment)
    return attachment.to_dict()


@router.get("/tasks/{task_id}/attachments")
async def list_task_attachments(task_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    if not _is_project_member(db, user, task.project):
        raise HTTPException(status_code=403)

    attachments = (
        db.query(TaskAttachment)
        .options(joinedload(TaskAttachment.user))
        .filter_by(task_id=task_id)
        .order_by(TaskAttachment.created_at.desc())
        .all()
    )
    return {
        "task_id": task.id,
        "attachments": [a.to_dict() for a in attachments],
        "total": len(attachments),
    }


@router.get("/tasks/attachments/{attachment_id}/download")
async def download_task_attachment(attachment_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    attachment = db.query(TaskAttachment).options(joinedload(TaskAttachment.task)).filter_by(id=attachment_id).first()
    if not attachment or not attachment.task or attachment.task.is_deleted:
        raise HTTPException(status_code=404, detail="Attachment not found.")

    project = db.get(Project, attachment.task.project_id)
    if not project or not _is_project_member(db, user, project):
        raise HTTPException(status_code=403)

    abs_path = attachment_abs_path(attachment.file_path)
    if not abs_path:
        raise HTTPException(status_code=404, detail="Attachment file not found on disk.")

    return FileResponse(
        path=abs_path,
        media_type=attachment.file_type or "application/octet-stream",
        filename=attachment.file_name,
    )


@router.delete("/tasks/attachments/{attachment_id}")
async def delete_task_attachment(attachment_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    attachment = db.query(TaskAttachment).options(joinedload(TaskAttachment.task)).filter_by(id=attachment_id).first()
    if not attachment or not attachment.task or attachment.task.is_deleted:
        raise HTTPException(status_code=404, detail="Attachment not found.")

    project = db.get(Project, attachment.task.project_id)
    if not project:
        raise HTTPException(status_code=404)

    is_uploader = attachment.user_id == user.id
    is_project_mentor = user.is_mentor and (project.mentor_id == user.id or db.query(ProjectMentorAssignment).filter_by(project_id=project.id, user_id=user.id).first() is not None)
    if not (user.is_admin or is_uploader or is_project_mentor):
        raise HTTPException(status_code=403, detail="Not authorized to delete this attachment.")

    task = attachment.task
    file_name = attachment.file_name
    db.delete(attachment)
    record_audit(
        db,
        user,
        "task.attachment_deleted",
        "deleted attachment on task",
        f"{task.title}: {file_name}",
        project_id=task.project_id,
    )
    db.commit()
    return {"ok": True, "success": True, "message": "Attachment deleted successfully."}


@router.post("/tasks/{task_id}/comments")
async def add_comment(
    task_id: int,
    request: Request,
    db: DbSession,
    body: str | None = Form(None),
    file: UploadFile | None = File(None),
    data: TaskCommentPayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    task = db.query(Task).options(joinedload(Task.project)).filter_by(id=task_id, is_deleted=False).first()
    if not task:
        raise HTTPException(status_code=404)
    if not _is_project_member(db, user, task.project):
        raise HTTPException(status_code=403)

    comment_body = body
    if comment_body is None and data is not None:
        comment_body = data.body
    elif comment_body is None:
        try:
            payload = await get_payload(request, data)
            comment_body = payload.get("body")
        except Exception:
            pass

    comment_text = str(comment_body or "").strip()
    has_file = file is not None and hasattr(file, "filename") and bool(file.filename)
    if not comment_text and not has_file:
        raise HTTPException(status_code=422, detail="Comment body or attachment is required.")
    if len(comment_text) > 1000:
        raise HTTPException(status_code=422, detail="Comment cannot exceed 1000 characters.")

    comment = TaskComment(task_id=task_id, user_id=user.id, body=comment_text or "Attached file")
    db.add(comment)
    db.flush()

    att_dict = None
    if has_file:
        content = await file.read()
        try:
            rel_path, safe_name, file_size = save_task_attachment(task.id, user.id, file.filename, content)
            mime = getattr(file, "content_type", None) or "application/octet-stream"
            att = TaskAttachment(
                task_id=task.id,
                user_id=user.id,
                comment_id=comment.id,
                file_name=safe_name,
                file_path=rel_path,
                file_size=file_size,
                file_type=mime,
                description=f"Attached with comment #{comment.id}",
            )
            db.add(att)
            db.flush()
            att_dict = att.to_dict()
        except Exception:
            pass

    record_audit(db, user, "task.comment", "commented on task", task.title, project_id=task.project_id)

    mentor_ids, _ = _ordered_project_mentors(task.project)
    recipients = set(mentor_ids)
    if task.assigned_to:
        recipients.add(task.assigned_to)
    _notify_new_comment(
        db, task.project, user, recipients,
        f"{user.name} commented on task \"{task.title}\" ({task.project.name}): "
        f"\"{_comment_preview(comment_text or 'Attached file')}\"",
        link=f"/projects/{task.project_id}",
    )

    db.commit()
    db.refresh(comment)
    return _comment_dict(comment, attachment_dict=att_dict)


post_task_comment = add_comment


@router.delete("/tasks/comments/{comment_id}")
async def delete_comment(comment_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    comment = db.get(TaskComment, comment_id)
    if not comment or comment.is_deleted:
        raise HTTPException(status_code=404)
    if comment.user_id != user.id and not user.is_admin:
        raise HTTPException(status_code=403)
    task = db.get(Task, comment.task_id)
    move_to_bin(
        db,
        user,
        BinEntityType.TASK_COMMENT,
        comment,
        title=(comment.body[:200] if comment.body else f"Comment #{comment.id}"),
    )
    comment.deleted_by_id = user.id
    record_audit(
        db,
        user,
        "task.comment_delete",
        "deleted comment on task",
        task.title if task else str(comment.task_id),
        project_id=task.project_id if task else None,
    )
    db.commit()
    return {"ok": True}


@router.get("/{project_id}/comments-board")
async def get_project_comments(project_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")

    project = db.query(Project).filter_by(id=project_id, is_deleted=False).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found.")

    if not (user.is_admin or user.is_mentor or _is_project_member(db, user, project)):
        raise HTTPException(status_code=403, detail="Not authorized.")

    comments = (
        db.query(ProjectComment)
        .options(joinedload(ProjectComment.user), joinedload(ProjectComment.deleted_by))
        .filter_by(project_id=project_id)
        .order_by(ProjectComment.created_at.asc())
        .all()
    )
    return [
        {
            "id": c.id,
            "project_id": c.project_id,
            "user_id": c.user_id,
            "user_name": c.user.name if c.user else "System",
            "user_role": c.user.role if c.user else "",
            # Deleted comments keep their place in the thread but drop the body — the
            # point is to show a comment existed and who removed it, not leak content.
            "body": None if c.is_deleted else c.body,
            "created_at": isoformat_utc(c.created_at),
            "is_deleted": c.is_deleted,
            "deleted_at": isoformat_utc(c.deleted_at) if c.deleted_at else None,
            "deleted_by_name": c.deleted_by.name if c.deleted_by else None,
        }
        for c in comments
    ]


@router.post("/{project_id}/comments-board")
async def create_project_comment(project_id: int, request: Request, db: DbSession, data: ProjectBoardCommentPayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")

    project = db.query(Project).filter_by(id=project_id, is_deleted=False).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found.")

    if not (user.is_admin or user.is_mentor or _is_project_member(db, user, project)):
        raise HTTPException(status_code=403, detail="Not authorized.")

    payload = await get_payload(request, data)
    body = str(payload.get("body", "")).strip()
    if not body:
        raise HTTPException(status_code=422, detail="Comment body cannot be empty.")
    if len(body) > 100:
        raise HTTPException(status_code=422, detail="Comment cannot exceed 100 characters.")

    comment = ProjectComment(
        project_id=project_id,
        user_id=user.id,
        body=body
    )
    db.add(comment)
    db.flush()

    record_audit(
        db,
        user,
        "project.comment",
        "commented on project",
        project.name,
        project_id=project.id
    )

    mentor_ids, _ = _ordered_project_mentors(project)
    intern_ids = {a.user_id for a in project.assignments}
    _notify_new_comment(
        db, project, user, set(mentor_ids) | intern_ids,
        f"{user.name} commented on {project.name}: \"{_comment_preview(body)}\"",
        link=f"/projects/{project.id}",
    )

    db.commit()

    db.refresh(comment)
    return {
        "id": comment.id,
        "project_id": comment.project_id,
        "user_id": comment.user_id,
        "user_name": user.name,
        "user_role": user.role,
        "body": comment.body,
        "created_at": isoformat_utc(comment.created_at),
    }


@router.delete("/comments-board/{comment_id}")
async def delete_project_comment(comment_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")

    comment = db.get(ProjectComment, comment_id)
    if not comment or comment.is_deleted:
        raise HTTPException(status_code=404, detail="Comment not found.")

    project = db.get(Project, comment.project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404, detail="Project not found.")

    is_author = comment.user_id == user.id
    is_project_mentor = (
        user.is_mentor and (
            project.mentor_id == user.id or
            db.query(ProjectMentorAssignment).filter_by(project_id=project.id, user_id=user.id).first() is not None
        )
    )
    if not (user.is_admin or is_author or is_project_mentor):
        raise HTTPException(status_code=403, detail="Not authorized to delete this comment.")

    comment.is_deleted = True
    comment.deleted_at = datetime.now(timezone.utc).replace(tzinfo=None)
    comment.deleted_by_id = user.id
    record_audit(
        db,
        user,
        "project.comment_deleted",
        "deleted comment on project",
        project.name,
        project_id=project.id
    )
    db.commit()
    return {"ok": True}


@router.get("/{project_id}/links")
async def get_project_links(project_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")

    project = db.query(Project).filter_by(id=project_id, is_deleted=False).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found.")

    if not (user.is_admin or user.is_mentor or _is_project_member(db, user, project)):
        raise HTTPException(status_code=403, detail="Not authorized.")

    links = (
        db.query(ProjectLink)
        .options(joinedload(ProjectLink.user), joinedload(ProjectLink.deleted_by))
        .filter_by(project_id=project_id)
        .order_by(ProjectLink.created_at.asc())
        .all()
    )
    return [
        {
            "id": l.id,
            "project_id": l.project_id,
            "user_id": l.user_id,
            "user_name": l.user.name if l.user else "System",
            "user_role": l.user.role if l.user else "",
            # Deleted links keep their place in the list but drop the URL/remark — the
            # point is to show a link existed and who removed it, not leak its target.
            "link": None if l.is_deleted else l.link,
            "remark": None if l.is_deleted else l.remark,
            "created_at": isoformat_utc(l.created_at),
            "is_deleted": l.is_deleted,
            "deleted_at": isoformat_utc(l.deleted_at) if l.deleted_at else None,
            "deleted_by_name": l.deleted_by.name if l.deleted_by else None,
        }
        for l in links
    ]


@router.post("/{project_id}/links")
async def create_project_link(project_id: int, request: Request, db: DbSession, data: ProjectLinkPayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")

    project = db.query(Project).filter_by(id=project_id, is_deleted=False).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found.")

    if not _is_project_member(db, user, project):
        raise HTTPException(status_code=403, detail="Not authorized.")

    payload = await get_payload(request, data)
    link_str = str(payload.get("link", "")).strip()
    remark_str = str(payload.get("remark", "")).strip()

    from urllib.parse import urlparse
    try:
        parsed_url = urlparse(link_str)
        valid_url = all([parsed_url.scheme in ("http", "https"), parsed_url.netloc])
    except Exception:
        valid_url = False

    if not link_str or not valid_url:
        raise HTTPException(status_code=422, detail="Invalid link URL.")
    if not remark_str:
        raise HTTPException(status_code=422, detail="Remark is required.")

    link_record = ProjectLink(
        project_id=project_id,
        user_id=user.id,
        link=link_str,
        remark=remark_str
    )
    db.add(link_record)
    db.flush()

    record_audit(
        db,
        user,
        "project.link_added",
        "added project link",
        link_str,
        project_id=project.id
    )
    db.commit()

    db.refresh(link_record)
    return {
        "id": link_record.id,
        "project_id": link_record.project_id,
        "user_id": link_record.user_id,
        "user_name": user.name,
        "user_role": user.role,
        "link": link_record.link,
        "remark": link_record.remark,
        "created_at": isoformat_utc(link_record.created_at),
    }


@router.delete("/links/{link_id}")
async def delete_project_link(link_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated.")

    link_record = db.get(ProjectLink, link_id)
    if not link_record or link_record.is_deleted:
        raise HTTPException(status_code=404, detail="Link not found.")

    project = db.get(Project, link_record.project_id)
    if not project or project.is_deleted:
        raise HTTPException(status_code=404, detail="Project not found.")

    is_submitter = link_record.user_id == user.id
    if not (user.is_admin or user.is_mentor or is_submitter):
        raise HTTPException(status_code=403, detail="Not authorized to delete this link.")

    link_record.is_deleted = True
    link_record.deleted_at = datetime.now(timezone.utc).replace(tzinfo=None)
    link_record.deleted_by_id = user.id

    record_audit(
        db,
        user,
        "project.link_deleted",
        "deleted project link",
        link_record.link,
        project_id=project.id
    )
    db.commit()
    return {"ok": True}

