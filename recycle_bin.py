"""Recycle bin: soft-delete, restore, and auto-purge helpers."""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING, Any

from config import Config
from models import (
    Announcement,
    BinEntityType,
    BinItem,
    Cohort,
    LeaveRequest,
    PerformanceReview,
    Project,
    StandupLog,
    Task,
    TaskComment,
    User,
)

if TYPE_CHECKING:
    from sqlalchemy.orm import Session


ENTITY_MODELS: dict[str, type] = {
    BinEntityType.PROJECT: Project,
    BinEntityType.TASK: Task,
    BinEntityType.TASK_COMMENT: TaskComment,
    BinEntityType.USER: User,
    BinEntityType.ANNOUNCEMENT: Announcement,
    BinEntityType.COHORT: Cohort,
    BinEntityType.REVIEW: PerformanceReview,
    BinEntityType.STANDUP: StandupLog,
    BinEntityType.LEAVE_REQUEST: LeaveRequest,
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _naive_utc(dt: datetime) -> datetime:
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def _aware_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _default_title(entity_type: str, entity: Any) -> str:
    for attr in ("title", "name", "body", "email"):
        value = getattr(entity, attr, None)
        if value:
            text = str(value).strip()
            if text:
                return text[:200]
    return f"{entity_type.replace('_', ' ').title()} #{entity.id}"


def _snapshot_entity(entity_type: str, entity: Any) -> dict[str, Any]:
    data: dict[str, Any] = {"id": entity.id, "entity_type": entity_type}
    if isinstance(entity, Project):
        data.update(
            {
                "name": entity.name,
                "description": entity.description,
                "status": entity.status,
                "mentor_id": entity.mentor_id,
            }
        )
    elif isinstance(entity, Task):
        data.update(
            {
                "title": entity.title,
                "project_id": entity.project_id,
                "status": entity.status,
                "assigned_to": entity.assigned_to,
            }
        )
    elif isinstance(entity, TaskComment):
        data.update(
            {
                "body": entity.body,
                "task_id": entity.task_id,
                "user_id": entity.user_id,
            }
        )
    elif isinstance(entity, User):
        data.update(
            {
                "name": entity.name,
                "email": entity.email,
                "role": entity.role,
            }
        )
    elif isinstance(entity, Announcement):
        data.update({"title": entity.title, "project_id": entity.project_id})
    elif isinstance(entity, Cohort):
        data.update({"name": entity.name})
    elif isinstance(entity, PerformanceReview):
        data.update(
            {
                "intern_id": entity.intern_id,
                "reviewer_id": entity.reviewer_id,
                "period": entity.period,
                "rating": entity.rating,
            }
        )
    elif isinstance(entity, StandupLog):
        data.update({"user_id": entity.user_id, "date": entity.date.isoformat()})
    elif isinstance(entity, LeaveRequest):
        data.update(
            {
                "user_id": entity.user_id,
                "start_date": entity.start_date.isoformat(),
                "end_date": entity.end_date.isoformat(),
                "status": entity.status,
            }
        )
    return data


def get_entity(db: "Session", entity_type: str, entity_id: int):
    model = ENTITY_MODELS.get(entity_type)
    if not model:
        return None
    return db.get(model, entity_id)


def move_to_bin(
    db: "Session",
    actor,
    entity_type: str,
    entity: Any,
    *,
    title: str | None = None,
) -> BinItem:
    """Soft-delete an entity and record it in the recycle bin."""
    if entity_type not in ENTITY_MODELS:
        raise ValueError(f"Unsupported entity type: {entity_type}")

    deleted_at = _utcnow()
    expires_at = deleted_at + timedelta(days=Config.BIN_RETENTION_DAYS)
    naive_deleted = _naive_utc(deleted_at)

    entity.is_deleted = True
    entity.deleted_at = naive_deleted
    if isinstance(entity, User):
        entity.is_active = False

    snapshot = _snapshot_entity(entity_type, entity)
    bin_item = BinItem(
        entity_type=entity_type,
        entity_id=entity.id,
        title=(title or _default_title(entity_type, entity))[:200],
        deleted_by_id=getattr(actor, "id", None),
        deleted_by_name=getattr(actor, "name", "") or "",
        deleted_at=deleted_at,
        expires_at=expires_at,
        snapshot_json=json.dumps(snapshot, default=str),
    )
    db.add(bin_item)
    return bin_item


def restore_bin_item(db: "Session", bin_item: BinItem) -> Any:
    if bin_item.restored_at is not None:
        raise ValueError("Item has already been restored.")
    if _aware_utc(bin_item.expires_at) < _utcnow():
        raise ValueError("Item has expired and can no longer be restored.")

    entity = get_entity(db, bin_item.entity_type, bin_item.entity_id)
    if not entity:
        raise ValueError("Linked record no longer exists.")

    entity.is_deleted = False
    entity.deleted_at = None
    if isinstance(entity, User):
        entity.is_active = True

    bin_item.restored_at = _utcnow()
    return entity


def permanently_delete_entity(db: "Session", entity_type: str, entity_id: int) -> bool:
    entity = get_entity(db, entity_type, entity_id)
    if not entity:
        return False

    if entity_type == BinEntityType.USER:
        from models import LeaveRequest

        db.query(LeaveRequest).filter(LeaveRequest.reviewed_by == entity.id).update(
            {"reviewed_by": None}, synchronize_session=False
        )

    db.delete(entity)
    return True


def purge_expired_bin_items(db: "Session") -> int:
    """Permanently delete expired, non-restored bin entries and their entities."""
    now = _utcnow()
    items = (
        db.query(BinItem)
        .filter(BinItem.restored_at.is_(None))
        .all()
    )
    purged = 0
    for item in items:
        if _aware_utc(item.expires_at) >= now:
            continue
        permanently_delete_entity(db, item.entity_type, item.entity_id)
        db.delete(item)
        purged += 1
    if purged:
        db.commit()
    return purged


def purge_all_bin_items(db: "Session") -> int:
    """Permanently delete every non-restored bin entry and its entity, regardless of
    expiry — used by the admin "Clear all" action. Caller must commit."""
    items = db.query(BinItem).filter(BinItem.restored_at.is_(None)).all()
    for item in items:
        permanently_delete_entity(db, item.entity_type, item.entity_id)
        db.delete(item)
    return len(items)


def bin_item_dict(item: BinItem) -> dict:
    metadata = None
    if item.snapshot_json:
        try:
            metadata = json.loads(item.snapshot_json)
        except json.JSONDecodeError:
            metadata = {"raw": item.snapshot_json}

    from utils import isoformat_utc

    return {
        "id": item.id,
        "entity_type": item.entity_type,
        "entity_id": item.entity_id,
        "title": item.title,
        "deleted_by_id": item.deleted_by_id,
        "deleted_by_name": item.deleted_by_name,
        "deleted_at": isoformat_utc(item.deleted_at),
        "expires_at": isoformat_utc(item.expires_at),
        "metadata": metadata,
    }
