from pydantic import BaseModel
from fastapi import APIRouter, HTTPException, Query
from sqlalchemy.orm import Session

from dependencies import DbSession, PlatformAdminUser
from models import (
    Attendance,
    Organization,
    OrganizationMembership,
    OrganizationSettings,
    OrganizationStatus,
    OrganizationType,
    Project,
    User,
    UserRole,
    _utcnow,
)

router = APIRouter(prefix="/api/platform", tags=["Platform Admin"])


class OrganizationCreateRequest(BaseModel):
    name: str
    slug: str
    type: str = OrganizationType.BUSINESS
    timezone: str = "Asia/Kolkata"
    admin_name: str
    admin_email: str
    admin_password: str


class OrganizationStatusUpdateRequest(BaseModel):
    status: str


@router.get("/metrics")
def get_platform_metrics(current_user: PlatformAdminUser, db: DbSession):
    """Aggregate metrics across all SaaS organizations for Platform Super Admins."""
    total_orgs = db.query(Organization).filter_by(is_deleted=False).count()
    active_orgs = (
        db.query(Organization)
        .filter_by(is_deleted=False, status=OrganizationStatus.ACTIVE)
        .count()
    )
    total_users = db.query(User).filter_by(is_deleted=False).count()
    total_projects = db.query(Project).filter_by(is_deleted=False).count()

    return {
        "total_organizations": total_orgs,
        "active_organizations": active_orgs,
        "total_users": total_users,
        "total_projects": total_projects,
    }


@router.get("/organizations")
def list_organizations(
    current_user: PlatformAdminUser,
    db: DbSession,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: str | None = None,
):
    """List all tenant organizations with pagination and metrics."""
    query = db.query(Organization).filter_by(is_deleted=False)
    if search:
        query = query.filter(
            Organization.name.ilike(f"%{search}%") | Organization.slug.ilike(f"%{search}%")
        )

    total = query.count()
    orgs = (
        query.order_by(Organization.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    items = []
    for org in orgs:
        member_count = (
            db.query(OrganizationMembership)
            .filter_by(organization_id=org.id, is_active=True, is_deleted=False)
            .count()
        )
        project_count = (
            db.query(Project)
            .filter_by(organization_id=org.id, is_deleted=False)
            .count()
        )
        data = org.to_dict()
        data["member_count"] = member_count
        data["project_count"] = project_count
        items.append(data)

    return {
        "organizations": items,
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.post("/organizations")
def create_organization(
    req: OrganizationCreateRequest,
    current_user: PlatformAdminUser,
    db: DbSession,
):
    """Onboard a new SaaS tenant with an initial Organization Admin account."""
    existing_slug = db.query(Organization).filter_by(slug=req.slug).first()
    if existing_slug:
        raise HTTPException(status_code=400, detail=f"Organization slug '{req.slug}' is already taken.")

    org = Organization(
        slug=req.slug.strip().lower(),
        name=req.name.strip(),
        type=req.type if req.type in OrganizationType.ALL else OrganizationType.BUSINESS,
        status=OrganizationStatus.ACTIVE,
        timezone=req.timezone,
    )
    db.add(org)
    db.flush()

    # Create default settings
    settings = OrganizationSettings(organization_id=org.id)
    db.add(settings)

    # Check if admin user already exists or create new
    admin_user = db.query(User).filter_by(email=req.admin_email).first()
    if not admin_user:
        admin_user = User(
            name=req.admin_name.strip(),
            email=req.admin_email,
            role=UserRole.ADMIN,
            is_active=True,
            activated_at=_utcnow(),
        )
        admin_user.set_password(req.admin_password)
        db.add(admin_user)
        db.flush()

    # Create Organization Admin membership
    membership = OrganizationMembership(
        organization_id=org.id,
        user_id=admin_user.id,
        role=UserRole.ADMIN,
        job_title="Administrator",
        is_active=True,
        activated_at=_utcnow(),
    )
    db.add(membership)
    db.commit()
    db.refresh(org)

    return {
        "ok": True,
        "organization": org.to_dict(),
        "admin_user_id": admin_user.id,
    }


@router.get("/organizations/{org_id}")
def get_organization_detail(
    org_id: int,
    current_user: PlatformAdminUser,
    db: DbSession,
):
    """Get complete details for a single organization."""
    org = db.get(Organization, org_id)
    if not org or org.is_deleted:
        raise HTTPException(status_code=404, detail="Organization not found")

    settings = db.get(OrganizationSettings, org.id)
    settings_dict = settings.to_dict() if settings else {}

    members = (
        db.query(OrganizationMembership)
        .filter_by(organization_id=org.id, is_deleted=False)
        .all()
    )

    return {
        "organization": org.to_dict(),
        "settings": settings_dict,
        "members": [m.to_dict() for m in members],
    }


@router.put("/organizations/{org_id}/status")
def update_organization_status(
    org_id: int,
    req: OrganizationStatusUpdateRequest,
    current_user: PlatformAdminUser,
    db: DbSession,
):
    """Update organization subscription status (active, suspended, trial, cancelled)."""
    org = db.get(Organization, org_id)
    if not org or org.is_deleted:
        raise HTTPException(status_code=404, detail="Organization not found")

    if req.status not in OrganizationStatus.ALL:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of {OrganizationStatus.ALL}")

    org.status = req.status
    db.commit()
    return {"ok": True, "organization": org.to_dict()}
