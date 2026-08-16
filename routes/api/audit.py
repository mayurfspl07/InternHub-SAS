"""JSON audit log endpoints."""
from datetime import date as date_cls, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_optional_user
from models import AuditLog
from utils import APP_TZ, isoformat_utc, scoped_audit_query

router = APIRouter(prefix="/api/audit", tags=["Audit Logs"])
DbSession = Annotated[Session, Depends(get_db)]
PAGE_SIZE = 30

# Map UI category filters to action prefixes (e.g. action=announcement → announcement.*).
ACTION_CATEGORY_PREFIXES = {
    "announcement": "announcement.",
}


def _apply_action_filter(query, action_filter: str):
    category = action_filter.strip().lower()
    prefix = ACTION_CATEGORY_PREFIXES.get(category)
    if prefix:
        from models import AuditLog
        return query.filter(AuditLog.action.like(f"{prefix}%"))
    from models import AuditLog
    return query.filter(AuditLog.action.ilike(f"%{action_filter}%"))


def _log_dict(log: AuditLog) -> dict:
    return {
        "id": log.id,
        "actor_id": log.actor_id,
        "actor_name": log.actor_name,
        "action": log.action,
        "verb": log.verb,
        "target": log.target,
        "target_id": log.target_id,
        "project_id": log.project_id,
        "affected_user_id": log.affected_user_id,
        "created_at": isoformat_utc(log.created_at, timespec="milliseconds"),
    }


@router.get("")
async def list_audit_logs(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    try:
        page = max(1, int(request.query_params.get("page", 1)))
    except ValueError:
        page = 1

    # Resolve active organization scope
    header_org = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    org_id: int | None = None
    if header_org and str(header_org).isdigit():
        org_id = int(header_org)
    else:
        from models import OrganizationMembership
        mem = db.query(OrganizationMembership).filter_by(user_id=user.id, is_active=True, is_deleted=False).first()
        org_id = mem.organization_id if mem else None

    q = scoped_audit_query(db, user, org_id=org_id)

    action_filter = request.query_params.get("action")
    if action_filter and action_filter not in ("undefined", "null", "all"):
        q = _apply_action_filter(q, action_filter)

    actor_id = request.query_params.get("actor_id")
    if actor_id:
        try:
            q = q.filter(AuditLog.actor_id == int(actor_id))
        except ValueError:
            pass

    project_id = request.query_params.get("project_id")
    if project_id:
        try:
            q = q.filter(AuditLog.project_id == int(project_id))
        except ValueError:
            pass

    date_filter = request.query_params.get("date")
    if date_filter:
        try:
            day = date_cls.fromisoformat(date_filter)
        except ValueError:
            day = None
        if day:
            # created_at is stored as naive UTC — convert the requested calendar day
            # (interpreted in the app's business timezone) to a naive-UTC [start, end)
            # range rather than comparing calendar dates directly, so a day boundary
            # near midnight lands on the right side consistently.
            start_local = datetime.combine(day, datetime.min.time(), tzinfo=APP_TZ)
            end_local = start_local + timedelta(days=1)
            start_utc = start_local.astimezone(timezone.utc).replace(tzinfo=None)
            end_utc = end_local.astimezone(timezone.utc).replace(tzinfo=None)
            q = q.filter(AuditLog.created_at >= start_utc, AuditLog.created_at < end_utc)

    total = q.count()
    logs = (
        q.order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .offset((page - 1) * PAGE_SIZE)
        .limit(PAGE_SIZE)
        .all()
    )
    total_pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)

    return {
        "logs": [_log_dict(log) for log in logs],
        "page": page,
        "page_size": PAGE_SIZE,
        "total_pages": total_pages,
        "total": total,
    }
