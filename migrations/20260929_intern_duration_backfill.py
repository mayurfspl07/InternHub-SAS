"""Give every intern a duration tier of their organization.

Interns created before duration became required (add-existing, invite approval,
role change) got no duration or the column default of 3 months, which may match
none of their organization's tiers, so their leave quota silently fell back to the
organization setting. Each such intern gets their organization's default active
tier (or its first active tier). Interns whose months already match an active
tier, or who belong to no organization, are left alone.

Idempotent Python migration.
"""
from sqlalchemy import inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

import models  # noqa: F401


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not (inspector.has_table("users") and inspector.has_table("organization_memberships")):
        return

    from models import OrganizationMembership, User, UserRole
    from utils import compute_internship_end_date, get_org_duration_tier, resolve_intern_duration

    with Session(bind=engine) as db:
        rows = (
            db.query(User, OrganizationMembership)
            .join(OrganizationMembership, OrganizationMembership.user_id == User.id)
            .filter(
                User.role == UserRole.INTERN,
                User.is_deleted == False,  # noqa: E712
                OrganizationMembership.is_deleted == False,  # noqa: E712
            )
            .all()
        )
        fixed = 0
        for user, membership in rows:
            org_id = membership.organization_id
            if user.internship_duration_months and get_org_duration_tier(db, org_id, user.internship_duration_months):
                continue
            months, error = resolve_intern_duration(db, org_id, None)
            if error or months is None:
                continue
            user.internship_duration_months = months
            user.internship_end_date = compute_internship_end_date(user.joining_date, months)
            membership.internship_duration_months = months
            membership.internship_end_date = user.internship_end_date
            fixed += 1
        db.commit()
        if fixed:
            print(f"[OK] Gave {fixed} intern(s) their organization's default internship duration.")
