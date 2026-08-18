"""Tenant and Request Context resolution."""
from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, Header, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.core.constants import OrganizationStatus, UserRole
from app.core.permissions import get_permissions_for_role


@dataclass
class CurrentContext:
    """Encapsulates the fully authenticated and tenant-scoped execution context."""
    user: Any
    organization: Any
    membership: Any
    settings: Any
    permissions: set[str]

    @property
    def role(self) -> str:
        return self.membership.role if self.membership else (self.user.role if self.user else "guest")

    @property
    def is_platform_admin(self) -> bool:
        return bool(getattr(self.user, "is_platform_admin", False)) or self.role == UserRole.SUPERADMIN

    @property
    def is_superadmin(self) -> bool:
        return self.role == UserRole.SUPERADMIN or self.is_platform_admin

    @property
    def is_admin(self) -> bool:
        return self.role in (UserRole.ADMIN, UserRole.SUPERADMIN) or self.is_platform_admin

    @property
    def is_mentor(self) -> bool:
        return self.role == UserRole.MENTOR

    @property
    def is_intern(self) -> bool:
        return self.role == UserRole.INTERN

    def has_permission(self, permission: str) -> bool:
        if self.is_platform_admin or self.role in (UserRole.ADMIN, UserRole.SUPERADMIN):
            return True
        return permission in self.permissions


def get_current_context(
    request: Request,
    x_organization_id: Annotated[str | None, Header()] = None,
    org_id_param: Annotated[int | None, Query(alias="organization_id")] = None,
) -> CurrentContext:
    """Dependency provider that resolves and verifies user identity and tenant membership."""
    from database import get_db
    from dependencies import get_optional_user
    from models import (
        Organization,
        OrganizationMembership,
        OrganizationSettings,
        UserRole,
    )

    db: Session = next(get_db())
    try:
        user = get_optional_user(request, db)
        if not user:
            raise HTTPException(status_code=401, detail="Authentication required.")

        target_org_id: int | None = None
        if x_organization_id and str(x_organization_id).isdigit():
            target_org_id = int(x_organization_id)
        elif org_id_param:
            target_org_id = int(org_id_param)

        membership: OrganizationMembership | None = None
        org: Organization | None = None

        if target_org_id is not None:
            membership = (
                db.query(OrganizationMembership)
                .filter_by(user_id=user.id, organization_id=target_org_id, is_active=True, is_deleted=False)
                .first()
            )
            if not membership and not getattr(user, "is_platform_admin", False):
                raise HTTPException(status_code=403, detail="Access denied to requested organization.")
            org = db.query(Organization).filter_by(id=target_org_id, is_deleted=False).first()
        else:
            membership = (
                db.query(OrganizationMembership)
                .filter_by(user_id=user.id, is_active=True, is_deleted=False)
                .order_by(OrganizationMembership.created_at.asc())
                .first()
            )
            if membership:
                org = db.query(Organization).filter_by(id=membership.organization_id, is_deleted=False).first()

        if not org:
            raise HTTPException(status_code=403, detail="Organization context required - specify X-Organization-Id header or query parameter")

        if org.status == OrganizationStatus.SUSPENDED:
            raise HTTPException(status_code=403, detail="This organization workspace has been suspended.")

        settings = db.query(OrganizationSettings).filter_by(organization_id=org.id).first()
        if not settings:
            settings = OrganizationSettings(organization_id=org.id)
            db.add(settings)
            db.commit()
            db.refresh(settings)

        permissions = get_permissions_for_role(membership.role)
        return CurrentContext(
            user=user,
            organization=org,
            membership=membership,
            settings=settings,
            permissions=permissions,
        )
    finally:
        db.close()


TenantContext = Annotated[CurrentContext, Depends(get_current_context)]
