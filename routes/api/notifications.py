"""JSON notification endpoints."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_optional_user
from models import Notification
from utils import isoformat_utc, unread_notification_count

router = APIRouter(prefix="/api/notifications", tags=["Notifications"])
DbSession = Annotated[Session, Depends(get_db)]

PAGE_SIZE = 20


def _notif_dict(n: Notification) -> dict:
    return {
        "id": n.id,
        "message": n.message,
        "link": n.link,
        "is_read": n.is_read,
        "created_at": isoformat_utc(n.created_at),
    }


@router.get("")
async def list_notifications(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    try:
        page = max(1, int(request.query_params.get("page", 1)))
    except ValueError:
        page = 1
    q = db.query(Notification).filter_by(user_id=user.id).order_by(Notification.created_at.desc())
    total = q.count()
    notifications = q.offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE).all()
    total_pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
    unread = unread_notification_count(db, user.id)
    return {
        "notifications": [_notif_dict(n) for n in notifications],
        "page": page,
        "total_pages": total_pages,
        "total": total,
        "unread_count": unread,
    }


@router.get("/unread-count")
async def unread_count(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        return {"count": 0}
    return {"count": unread_notification_count(db, user.id)}


@router.post("/mark-read")
async def mark_all_read(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    db.query(Notification).filter_by(user_id=user.id, is_read=False).update({"is_read": True})
    db.commit()
    return {"ok": True}


@router.delete("/{notif_id}")
async def delete_notification(notif_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    notif = db.query(Notification).filter_by(id=notif_id, user_id=user.id).first()
    if notif:
        db.delete(notif)
        db.commit()
    return {"ok": True}
