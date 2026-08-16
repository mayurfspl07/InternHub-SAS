"""Data access repository for Organizations, Memberships, and Settings."""
from sqlalchemy.orm import Session, joinedload

from models import Organization, OrganizationMembership, OrganizationSettings


class OrganizationRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, org_id: int) -> Organization | None:
        return (
            self.db.query(Organization)
            .options(
                joinedload(Organization.settings),
                joinedload(Organization.memberships),
            )
            .filter(
                Organization.id == org_id,
                Organization.is_deleted == False,
            )
            .first()
        )

    def get_by_slug(self, slug: str) -> Organization | None:
        return (
            self.db.query(Organization)
            .options(joinedload(Organization.settings))
            .filter(
                Organization.slug == slug,
                Organization.is_deleted == False,
            )
            .first()
        )

    def list_user_organizations(self, user_id: int) -> list[OrganizationMembership]:
        return (
            self.db.query(OrganizationMembership)
            .options(joinedload(OrganizationMembership.organization))
            .filter(
                OrganizationMembership.user_id == user_id,
                OrganizationMembership.is_active == True,
                OrganizationMembership.is_deleted == False,
            )
            .all()
        )

    def create(self, org: Organization, settings: OrganizationSettings | None = None) -> Organization:
        self.db.add(org)
        self.db.commit()
        self.db.refresh(org)
        if settings:
            settings.organization_id = org.id
            self.db.add(settings)
            self.db.commit()
            self.db.refresh(settings)
        return org
