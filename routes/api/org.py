from datetime import date, datetime, timezone
from pydantic import BaseModel
from fastapi import APIRouter, HTTPException, Query
from sqlalchemy.orm import Session

from dependencies import DbSession, TenantContext
from models import (
    Organization,
    OrganizationMembership,
    OrganizationSettings,
    User,
    UserRole,
    _utcnow,
)

router = APIRouter(prefix="/api/org", tags=["Organization Management"])


class OrganizationProfileUpdateRequest(BaseModel):
    name: str | None = None
    timezone: str | None = None
    logo_url: str | None = None


class OrganizationSettingsUpdateRequest(BaseModel):
    shift_start: str | None = None
    shift_end: str | None = None
    late_cutoff: str | None = None
    noon_cutoff: str | None = None
    checkin_block: str | None = None
    full_day_hours: float | None = None
    half_day_hours: float | None = None
    leave_quota_days: int | None = None
    advance_leave_days: int | None = None
    require_attendance_selfie: bool | None = None
    require_attendance_gps: bool | None = None
    auto_checkout_enabled: bool | None = None


class AddMemberRequest(BaseModel):
    name: str
    email: str
    password: str | None = None
    role: str = UserRole.INTERN
    department: str | None = None
    job_title: str | None = None
    joining_date: date | None = None
    mentor_id: int | None = None


class UpdateMemberRequest(BaseModel):
    role: str | None = None
    department: str | None = None
    job_title: str | None = None
    joining_date: date | None = None
    mentor_membership_id: int | None = None
    is_active: bool | None = None


@router.get("/current")
def get_current_organization(ctx: TenantContext):
    """Retrieve active organization profile and its settings."""
    return {
        "organization": ctx.organization.to_dict(),
        "settings": ctx.settings.to_dict(),
        "membership": ctx.membership.to_dict(),
        "role": ctx.role,
    }


@router.put("/profile")
def update_organization_profile(
    req: OrganizationProfileUpdateRequest,
    ctx: TenantContext,
    db: DbSession,
):
    """Update organization profile name, timezone, or logo (Org Admin only)."""
    if not ctx.is_admin:
        raise HTTPException(status_code=403, detail="Organization Admin access required")

    org = ctx.organization
    if req.name is not None:
        org.name = req.name.strip()
    if req.timezone is not None:
        org.timezone = req.timezone.strip()
    if req.logo_url is not None:
        org.logo_url = req.logo_url.strip()

    db.commit()
    return {"ok": True, "organization": org.to_dict()}


@router.put("/settings")
def update_organization_settings(
    req: OrganizationSettingsUpdateRequest,
    ctx: TenantContext,
    db: DbSession,
):
    """Update tenant shift, leave, and verification policies (Org Admin only)."""
    if not ctx.is_admin:
        raise HTTPException(status_code=403, detail="Organization Admin access required")

    settings = ctx.settings
    if req.shift_start is not None:
        settings.shift_start = req.shift_start
    if req.shift_end is not None:
        settings.shift_end = req.shift_end
    if req.late_cutoff is not None:
        settings.late_cutoff = req.late_cutoff
    if req.noon_cutoff is not None:
        settings.noon_cutoff = req.noon_cutoff
    if req.checkin_block is not None:
        settings.checkin_block = req.checkin_block
    if req.full_day_hours is not None:
        settings.full_day_hours = req.full_day_hours
    if req.half_day_hours is not None:
        settings.half_day_hours = req.half_day_hours
    if req.leave_quota_days is not None:
        settings.leave_quota_days = req.leave_quota_days
    if req.advance_leave_days is not None:
        settings.advance_leave_days = req.advance_leave_days
    if req.require_attendance_selfie is not None:
        settings.require_attendance_selfie = req.require_attendance_selfie
    if req.require_attendance_gps is not None:
        settings.require_attendance_gps = req.require_attendance_gps
    if req.auto_checkout_enabled is not None:
        settings.auto_checkout_enabled = req.auto_checkout_enabled

    settings.updated_at = _utcnow()
    db.commit()
    return {"ok": True, "settings": settings.to_dict()}


@router.get("/members")
def list_organization_members(
    ctx: TenantContext,
    db: DbSession,
    role: str | None = None,
    search: str | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=100),
):
    """List all members within the active organization."""
    query = (
        db.query(OrganizationMembership, User)
        .join(User, OrganizationMembership.user_id == User.id)
        .filter(
            OrganizationMembership.organization_id == ctx.organization.id,
            OrganizationMembership.is_deleted == False,
        )
    )

    if role:
        query = query.filter(OrganizationMembership.role == role)
    if search:
        query = query.filter(
            User.name.ilike(f"%{search}%") | User.email.ilike(f"%{search}%")
        )

    total = query.count()
    rows = (
        query.order_by(OrganizationMembership.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    members = []
    for membership, user in rows:
        data = membership.to_dict()
        data["user_name"] = user.name
        data["user_email"] = user.email
        data["user_phone"] = user.phone
        members.append(data)

    return {
        "members": members,
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.post("/members")
def add_organization_member(
    req: AddMemberRequest,
    ctx: TenantContext,
    db: DbSession,
):
    """Add a new or existing user to the active organization (Org Admin & Mentor)."""
    if not (ctx.is_admin or ctx.is_mentor):
        raise HTTPException(status_code=403, detail="Admin or Mentor access required")

    # Mentors can only create interns
    if ctx.is_mentor and req.role != UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentors can only create intern accounts")

    user = db.query(User).filter_by(email=req.email).first()
    if not user:
        if not req.password:
            raise HTTPException(status_code=400, detail="Password is required for new users")
        user = User(
            name=req.name.strip(),
            email=req.email,
            role=req.role,
            is_active=True,
            activated_at=_utcnow(),
        )
        user.set_password(req.password)
        db.add(user)
        db.flush()

    existing_membership = (
        db.query(OrganizationMembership)
        .filter_by(organization_id=ctx.organization.id, user_id=user.id)
        .first()
    )
    if existing_membership and not existing_membership.is_deleted:
        raise HTTPException(status_code=400, detail="User is already a member of this organization")

    if existing_membership and existing_membership.is_deleted:
        existing_membership.is_deleted = False
        existing_membership.is_active = True
        existing_membership.role = req.role
        existing_membership.department = req.department
        existing_membership.job_title = req.job_title
        existing_membership.joining_date = req.joining_date
        db.commit()
        return {"ok": True, "membership": existing_membership.to_dict()}

    membership = OrganizationMembership(
        organization_id=ctx.organization.id,
        user_id=user.id,
        role=req.role,
        department=req.department,
        job_title=req.job_title,
        joining_date=req.joining_date,
        is_active=True,
        activated_at=_utcnow(),
    )
    db.add(membership)
    db.commit()
    db.refresh(membership)

    return {"ok": True, "membership": membership.to_dict()}
