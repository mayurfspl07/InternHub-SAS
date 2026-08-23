"""Public lead capture (marketing site forms) + superadmin read-only listing."""
import re
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from sqlalchemy import or_
from sqlalchemy.orm import Session

from database import get_db
from dependencies import DbSession, PlatformAdminUser
from models import Lead
from routes.api.schemas import LeadCreatePayload, get_payload
from services.redis_service import RedisService
from utils import isoformat_utc

router = APIRouter(prefix="/api/leads", tags=["Leads"])
platform_router = APIRouter(prefix="/api/platform/leads", tags=["Platform Admin"])

DbSession = Annotated[Session, Depends(get_db)]

LEAD_RATE_LIMIT = 5
LEAD_RATE_WINDOW_SECONDS = 3600  # per IP, rolling window

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _clean(value, limit: int) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return text[:limit]


def _lead_dict(lead: Lead) -> dict:
    return {
        "id": lead.id,
        "name": lead.name,
        "email": lead.email,
        "phone": lead.phone,
        "company": lead.company,
        "role": lead.role,
        "cohort_size": lead.cohort_size,
        "message": lead.message,
        "source": lead.source,
        "status": lead.status,
        "ip_address": lead.ip_address,
        "created_at": isoformat_utc(lead.created_at),
    }


@router.post("")
async def create_lead(request: Request, db: DbSession, data: LeadCreatePayload | None = Body(None)):
    """Public endpoint — captures a marketing-site lead. Honeypot + per-IP rate limited."""
    payload = await get_payload(request, data)

    # Hidden "website" field: humans never fill it; bots do. Pretend success, store nothing.
    honeypot = str(payload.get("website") or "").strip()
    if honeypot:
        return {"ok": True}

    ip = _client_ip(request)
    if RedisService.is_rate_limited(
        f"rate_limit:leads:{ip}", limit=LEAD_RATE_LIMIT, window_seconds=LEAD_RATE_WINDOW_SECONDS
    ):
        raise HTTPException(status_code=429, detail="Too many submissions from this network. Please try again later.")

    name = _clean(payload.get("name"), 120)
    email = (_clean(payload.get("email"), 200) or "").lower()
    if not name or not email or not _EMAIL_RE.match(email):
        raise HTTPException(status_code=422, detail="Valid name and email are required.")

    lead = Lead(
        name=name,
        email=email,
        phone=_clean(payload.get("phone"), 40),
        company=_clean(payload.get("company"), 200),
        role=_clean(payload.get("role"), 100),
        cohort_size=_clean(payload.get("cohort_size"), 50),
        message=_clean(payload.get("message"), 5000),
        source=_clean(payload.get("source"), 50) or "marketing_site",
        ip_address=ip[:64],
    )
    db.add(lead)
    db.commit()
    return {"ok": True}


@platform_router.get("")
def list_leads(
    current_user: PlatformAdminUser,
    db: DbSession,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: str | None = Query(None, description="Search name/email/company"),
    status: str | None = Query(None, description="Filter by status (e.g. new)"),
):
    """Read-only lead inbox for Platform Super Admins."""
    q = db.query(Lead)
    if search:
        term = f"%{search.strip()}%"
        q = q.filter(or_(Lead.name.ilike(term), Lead.email.ilike(term), Lead.company.ilike(term)))
    if status:
        q = q.filter(Lead.status == status.strip().lower())

    total = q.count()
    leads = (
        q.order_by(Lead.created_at.desc(), Lead.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return {"items": [_lead_dict(l) for l in leads], "total": total, "page": page, "page_size": page_size}
