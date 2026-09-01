"""Organization SMTP configuration and email notification endpoints."""
import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_optional_user, _resolve_request_org_id
from models import EmailLog, Organization, TenantSmtpConfig, UserRole, _utcnow
from utils import record_audit, isoformat_utc
from email_service import send_test_email

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/org/smtp", tags=["Tenant SMTP & Email Notifications"])
DbSession = Annotated[Session, Depends(get_db)]


class SmtpConfigUpdateRequest(BaseModel):
    is_enabled: bool | None = None
    host: str | None = None
    port: int | None = None
    username: str | None = None
    password: str | None = None
    sender_email: str | None = None
    sender_name: str | None = None
    encryption: str | None = None  # "tls", "ssl", "none"

    # Triggers
    notify_welcome: bool | None = None
    notify_leave_request: bool | None = None
    notify_leave_decision: bool | None = None
    notify_assignment_new: bool | None = None
    notify_assignment_submit: bool | None = None
    notify_assignment_grade: bool | None = None
    notify_task_assigned: bool | None = None
    notify_attendance_alert: bool | None = None


class SmtpTestRequest(BaseModel):
    target_email: str
    host: str | None = None
    port: int | None = None
    username: str | None = None
    password: str | None = None
    sender_email: str | None = None
    sender_name: str | None = None
    encryption: str | None = None


def _require_admin_and_org(request: Request, db: Session):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Organization Admin privileges required.")

    org_id = _resolve_request_org_id(request, user, db)
    if not org_id:
        org_id = 1
    return user, org_id


@router.get("")
async def get_tenant_smtp_config(request: Request, db: DbSession):
    """Retrieve tenant's current SMTP settings and notification trigger preferences."""
    user, org_id = _require_admin_and_org(request, db)

    cfg = db.query(TenantSmtpConfig).filter_by(organization_id=org_id).first()
    if not cfg:
        # Return clean default configuration object
        return {
            "organization_id": org_id,
            "is_enabled": False,
            "host": "",
            "port": 587,
            "username": "",
            "password": "",
            "has_password": False,
            "sender_email": "",
            "sender_name": "",
            "encryption": "tls",
            "notify_welcome": True,
            "notify_leave_request": True,
            "notify_leave_decision": True,
            "notify_assignment_new": True,
            "notify_assignment_submit": True,
            "notify_assignment_grade": True,
            "notify_task_assigned": True,
            "notify_attendance_alert": True,
            "created_at": None,
            "updated_at": None,
        }

    return cfg.to_dict(mask_password=True)


@router.put("")
async def update_tenant_smtp_config(
    payload: SmtpConfigUpdateRequest,
    request: Request,
    db: DbSession,
):
    """Update tenant's custom SMTP configuration and notification triggers."""
    user, org_id = _require_admin_and_org(request, db)

    cfg = db.query(TenantSmtpConfig).filter_by(organization_id=org_id).first()
    if not cfg:
        cfg = TenantSmtpConfig(organization_id=org_id)
        db.add(cfg)

    if payload.is_enabled is not None:
        cfg.is_enabled = payload.is_enabled
    if payload.host is not None:
        cfg.host = payload.host.strip()
    if payload.port is not None:
        cfg.port = int(payload.port)
    if payload.username is not None:
        cfg.username = payload.username.strip()
    if payload.password is not None and payload.password.strip() and payload.password != "••••••••":
        cfg.password = payload.password.strip()
    if payload.sender_email is not None:
        cfg.sender_email = payload.sender_email.strip()
    if payload.sender_name is not None:
        cfg.sender_name = payload.sender_name.strip()
    if payload.encryption is not None:
        enc = payload.encryption.strip().lower()
        if enc in ("tls", "ssl", "none"):
            cfg.encryption = enc

    # Triggers
    if payload.notify_welcome is not None:
        cfg.notify_welcome = payload.notify_welcome
    if payload.notify_leave_request is not None:
        cfg.notify_leave_request = payload.notify_leave_request
    if payload.notify_leave_decision is not None:
        cfg.notify_leave_decision = payload.notify_leave_decision
    if payload.notify_assignment_new is not None:
        cfg.notify_assignment_new = payload.notify_assignment_new
    if payload.notify_assignment_submit is not None:
        cfg.notify_assignment_submit = payload.notify_assignment_submit
    if payload.notify_assignment_grade is not None:
        cfg.notify_assignment_grade = payload.notify_assignment_grade
    if payload.notify_task_assigned is not None:
        cfg.notify_task_assigned = payload.notify_task_assigned
    if payload.notify_attendance_alert is not None:
        cfg.notify_attendance_alert = payload.notify_attendance_alert

    cfg.updated_at = _utcnow()
    record_audit(db, user, "tenant.smtp_update", "updated SMTP and notification settings", f"Org {org_id}")
    db.commit()
    db.refresh(cfg)

    return {
        "success": True,
        "message": "SMTP settings saved successfully.",
        "config": cfg.to_dict(mask_password=True),
    }


@router.post("/test")
async def test_tenant_smtp_connection(
    payload: SmtpTestRequest,
    request: Request,
    db: DbSession,
):
    """Test SMTP connection and credentials by dispatching a test email."""
    user, org_id = _require_admin_and_org(request, db)

    target_email = str(payload.target_email).strip().lower()
    if not target_email or "@" not in target_email:
        raise HTTPException(status_code=422, detail="A valid target email address is required for testing.")

    smtp_override = None
    if payload.host:
        # Test provided form fields directly
        password = payload.password
        if not password or password == "••••••••":
            saved_cfg = db.query(TenantSmtpConfig).filter_by(organization_id=org_id).first()
            password = saved_cfg.password if saved_cfg else ""

        smtp_override = {
            "source": "tenant_test_form",
            "host": payload.host.strip(),
            "port": int(payload.port or 587),
            "username": (payload.username or "").strip(),
            "password": (password or "").strip(),
            "sender_email": (payload.sender_email or payload.username or "noreply@internhub.com").strip(),
            "sender_name": (payload.sender_name or "InternHub").strip(),
            "encryption": (payload.encryption or "tls").strip().lower(),
        }

    success, error = send_test_email(db, org_id, target_email, smtp_override=smtp_override)
    if not success:
        return {
            "success": False,
            "message": f"SMTP test failed: {error}",
            "error": error,
        }

    return {
        "success": True,
        "message": f"Test email sent successfully to {target_email}.",
    }


@router.get("/logs")
async def list_tenant_email_logs(
    request: Request,
    db: DbSession,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    email_type: str | None = Query(None),
    status: str | None = Query(None),
):
    """List paginated email dispatch history for the tenant."""
    user, org_id = _require_admin_and_org(request, db)

    q = db.query(EmailLog).filter(EmailLog.organization_id == org_id)

    if email_type:
        q = q.filter(EmailLog.email_type == email_type.strip())
    if status:
        q = q.filter(EmailLog.status == status.strip())

    total = q.count()
    logs = q.order_by(EmailLog.sent_at.desc()).offset((page - 1) * page_size).limit(page_size).all()
    total_pages = max(1, (total + page_size - 1) // page_size)

    return {
        "logs": [log.to_dict() for log in logs],
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
    }
