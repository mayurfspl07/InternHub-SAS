"""JSON search endpoint."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from sqlalchemy import func

from database import get_db
from dependencies import get_optional_user
from models import Project, ProjectAssignment, Task, User
from utils import get_user_project_ids

router = APIRouter(prefix="/api/search", tags=["api-search"])
DbSession = Annotated[Session, Depends(get_db)]


@router.get("")
async def search(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    q = request.query_params.get("q", "").strip()
    results: dict = {"users": [], "projects": [], "tasks": []}

    if q and len(q) >= 2:
        pattern = f"%{q}%"

        if user.is_admin or user.is_mentor:
            user_rows = db.query(User).filter(
                (User.name.ilike(pattern)) | (User.email.ilike(pattern))
            ).order_by(User.name).limit(8).all()
            results["users"] = [
                # Admins see email; mentors see name/role only to protect PII
                {"id": u.id, "name": u.name, "role": u.role, **({"email": u.email} if user.is_admin else {})}
                for u in user_rows
            ]

        if user.is_admin:
            proj_q = db.query(Project).filter(Project.is_deleted == False)
        elif user.is_mentor:
            # Includes co-mentored projects, not just ones where this mentor is primary.
            mentor_project_ids = get_user_project_ids(db, user) or [-1]
            proj_q = db.query(Project).filter(Project.id.in_(mentor_project_ids), Project.is_deleted == False)
        else:
            assigned_ids = db.query(ProjectAssignment.project_id).filter_by(user_id=user.id).subquery()
            proj_q = db.query(Project).filter(Project.id.in_(assigned_ids), Project.is_deleted == False)

        results["projects"] = [
            {"id": p.id, "name": p.name, "status": p.status, "description": p.description}
            for p in proj_q.filter(
                (Project.name.ilike(pattern)) | (func.coalesce(Project.description, "").ilike(pattern))
            ).order_by(Project.created_at.desc()).limit(8).all()
        ]

        task_q = db.query(Task).join(Project, Task.project_id == Project.id).filter(Task.is_deleted == False)
        if user.is_intern:
            task_q = task_q.filter(Task.assigned_to == user.id)
        elif user.is_mentor:
            task_q = task_q.filter(Project.id.in_(mentor_project_ids))
        results["tasks"] = [
            {
                "id": t.id,
                "title": t.title,
                "status": t.status,
                "project_id": t.project_id,
                "project_name": t.project.name if t.project else None,
            }
            for t in task_q.filter(
                (Task.title.ilike(pattern)) | (func.coalesce(Task.description, "").ilike(pattern))
            ).order_by(Task.created_at.desc()).limit(8).all()
        ]

    total = sum(len(v) for v in results.values())
    return {"q": q, "results": results, "total": total}
