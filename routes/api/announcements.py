"""JSON announcements endpoints."""
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import Announcement, Project, ProjectAssignment, ProjectMentorAssignment, BinEntityType
from recycle_bin import move_to_bin
from utils import push_notification, record_audit, isoformat_utc

router = APIRouter(prefix="/api/announcements", tags=["api-announcements"])
DbSession = Annotated[Session, Depends(get_db)]


def _ann_dict(a: Announcement) -> dict:
    return {
        "id": a.id,
        "title": a.title,
        "body": a.body,
        "is_pinned": a.is_pinned,
        "project_id": a.project_id,
        "project_name": a.project.name if a.project else None,
        "author_id": a.author_id,
        "author_name": a.author.name if a.author else None,
        "created_at": isoformat_utc(a.created_at),
    }


@router.get("")
async def list_announcements(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    q = db.query(Announcement).options(
        joinedload(Announcement.author),
        joinedload(Announcement.project),
    ).filter(Announcement.is_deleted == False)

    if user.is_intern:
        # Interns see global announcements and those for their projects
        assigned_ids = [
            r[0] for r in db.query(ProjectAssignment.project_id).filter_by(user_id=user.id).all()
        ]
        q = q.filter((Announcement.project_id == None) | (Announcement.project_id.in_(assigned_ids)))
    elif user.is_mentor:
        mentor_proj_ids = {
            r[0] for r in db.query(Project.id).filter_by(mentor_id=user.id).all()
        }
        # Include projects where this mentor is a co-mentor
        mentor_proj_ids.update(
            r[0]
            for r in db.query(ProjectMentorAssignment.project_id).filter_by(user_id=user.id).all()
        )
        q = q.filter((Announcement.project_id == None) | (Announcement.project_id.in_(mentor_proj_ids)))

    project_id = request.query_params.get("project_id")
    if project_id:
        try:
            q = q.filter(Announcement.project_id == int(project_id))
        except ValueError:
            pass

    announcements = q.order_by(Announcement.is_pinned.desc(), Announcement.created_at.desc()).limit(50).all()
    return [_ann_dict(a) for a in announcements]


@router.post("")
async def create_announcement(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)

    data = await request.json()
    title = str(data.get("title", "")).strip()
    body = str(data.get("body", "")).strip()
    if not title or not body:
        raise HTTPException(status_code=422, detail="Title and body are required.")

    is_pinned = bool(data.get("is_pinned", False))
    project_id = data.get("project_id")
    if project_id:
        try:
            project_id = int(project_id)
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="Invalid project.")
        project = db.get(Project, project_id)
        if not project:
            project_id = None
        elif user.is_mentor and project.mentor_id != user.id and not user.is_admin:
            # Co-mentors may also post to the project
            is_co_mentor = (
                db.query(ProjectMentorAssignment)
                .filter_by(project_id=project_id, user_id=user.id)
                .first()
            )
            if not is_co_mentor:
                raise HTTPException(status_code=403, detail="Cannot post to a project you don't manage.")

    ann = Announcement(
        author_id=user.id,
        title=title,
        body=body,
        is_pinned=is_pinned,
        project_id=project_id,
    )
    db.add(ann)
    db.flush()
    record_audit(
        db,
        user,
        "announcement.create",
        "posted announcement",
        title,
        target_id=ann.id,
        project_id=project_id,
    )
    if is_pinned:
        record_audit(
            db,
            user,
            "announcement.pin",
            "pinned announcement",
            title,
            target_id=ann.id,
            project_id=project_id,
        )
    db.commit()
    db.refresh(ann)
    ann = db.query(Announcement).options(
        joinedload(Announcement.author),
        joinedload(Announcement.project),
    ).filter_by(id=ann.id).first()
    return _ann_dict(ann)


@router.put("/{ann_id}")
async def update_announcement(ann_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    ann = db.get(Announcement, ann_id)
    if not ann or ann.is_deleted:
        raise HTTPException(status_code=404)
    if not user.is_admin and ann.author_id != user.id:
        raise HTTPException(status_code=403)

    data = await request.json()
    content_changed = False
    if "title" in data:
        ann.title = str(data["title"]).strip()
        content_changed = True
    if "body" in data:
        ann.body = str(data["body"]).strip()
        content_changed = True
    pinned_changed = False
    if "is_pinned" in data:
        new_pinned = bool(data["is_pinned"])
        pinned_changed = new_pinned != ann.is_pinned
        ann.is_pinned = new_pinned

    if content_changed:
        record_audit(
            db,
            user,
            "announcement.update",
            "updated announcement",
            ann.title,
            target_id=ann.id,
            project_id=ann.project_id,
        )
    if pinned_changed and ann.is_pinned:
        record_audit(
            db,
            user,
            "announcement.pin",
            "pinned announcement",
            ann.title,
            target_id=ann.id,
            project_id=ann.project_id,
        )
    if not content_changed and not pinned_changed:
        return _ann_dict(ann)

    db.commit()
    ann = db.query(Announcement).options(
        joinedload(Announcement.author),
        joinedload(Announcement.project),
    ).filter_by(id=ann_id).first()
    return _ann_dict(ann)


@router.delete("/{ann_id}")
async def delete_announcement(ann_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    ann = db.get(Announcement, ann_id)
    if not ann or ann.is_deleted:
        raise HTTPException(status_code=404)
    if not user.is_admin and ann.author_id != user.id:
        raise HTTPException(status_code=403)
    record_audit(
        db,
        user,
        "announcement.delete",
        "deleted announcement",
        ann.title,
        target_id=ann.id,
        project_id=ann.project_id,
    )
    move_to_bin(db, user, BinEntityType.ANNOUNCEMENT, ann, title=ann.title)
    db.commit()
    return {"ok": True}
