"""Data access repository for User entities."""
from sqlalchemy import desc
from sqlalchemy.orm import Session, joinedload

from models import OrganizationMembership, User


class UserRepository:
    def __init__(self, db: Session, org_id: int | None = None):
        self.db = db
        self.org_id = org_id

    def get_by_id(self, user_id: int) -> User | None:
        return (
            self.db.query(User)
            .options(joinedload(User.memberships))
            .filter(User.id == user_id, User.is_deleted == False)
            .first()
        )

    def get_by_email(self, email: str) -> User | None:
        return (
            self.db.query(User)
            .filter(User.email == email.strip().lower(), User.is_deleted == False)
            .first()
        )

    def list_org_users(self, role: str | None = None) -> list[User]:
        if not self.org_id:
            return []
        q = (
            self.db.query(User)
            .join(OrganizationMembership, OrganizationMembership.user_id == User.id)
            .filter(
                OrganizationMembership.organization_id == self.org_id,
                OrganizationMembership.is_active == True,
                OrganizationMembership.is_deleted == False,
                User.is_deleted == False,
            )
        )
        if role:
            q = q.filter(OrganizationMembership.role == role)
        return q.order_by(User.name.asc()).all()

    def create(self, user: User) -> User:
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user

    def update(self, user: User) -> User:
        self.db.commit()
        self.db.refresh(user)
        return user
