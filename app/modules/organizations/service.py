"""Domain service for managing tenant organizations and settings."""
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from app.modules.organizations.repository import OrganizationRepository
from app.modules.organizations.schemas import (
    OrganizationCreateRequest,
    OrganizationSettingsUpdateRequest,
    OrganizationUpdateRequest,
)
from models import Organization, OrganizationMembership, OrganizationSettings, UserRole


class OrganizationService:
    def __init__(self, db: Session):
        self.db = db
        self.repo = OrganizationRepository(db)

    def create_organization(self, user_id: int, request: OrganizationCreateRequest) -> Organization:
        org = Organization(
            name=request.name,
            slug=request.slug,
            type=request.type,
            timezone=request.timezone,
            logo_url=request.logo_url,
        )
        settings = OrganizationSettings()
        org = self.repo.create(org, settings)

        membership = OrganizationMembership(
            organization_id=org.id,
            user_id=user_id,
            role=UserRole.ADMIN,
            is_active=True,
        )
        self.db.add(membership)
        self.db.commit()
        return org

    def update_settings(self, org_id: int, request: OrganizationSettingsUpdateRequest) -> OrganizationSettings:
        org = self.repo.get_by_id(org_id)
        if not org or not org.settings:
            raise ValueError("Organization settings not found.")

        settings = org.settings
        update_data = request.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(settings, key, value)
        settings.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        self.db.commit()
        self.db.refresh(settings)
        return settings
