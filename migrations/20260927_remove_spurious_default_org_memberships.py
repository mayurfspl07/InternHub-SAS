"""Undo default-organization memberships that the start-up backfill added by mistake.

20260815_multi_tenant_saas re-ran on every boot and inserted an organization-1
membership for *every* user, so each deploy made every tenant's users (admins
included) members of the default organization. That backfill is now limited to
users without any membership; this migration retires the rows it wrongly created.

A row is treated as spurious when all of these hold:
  * it is an organization-1 membership that is not already deleted,
  * the user's first membership (lowest id) is in another organization, and
  * its created_at equals the user's own created_at (the backfill copied it).
Such rows are soft-deleted (is_active = false, is_deleted = true), so the change
is reversible. Idempotent Python migration.
"""
from sqlalchemy import func, inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

import models  # noqa: F401


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not (inspector.has_table("users") and inspector.has_table("organization_memberships")):
        return

    from models import OrganizationMembership, User

    with Session(bind=engine) as db:
        first_ids = dict(
            db.query(OrganizationMembership.user_id, func.min(OrganizationMembership.id))
            .group_by(OrganizationMembership.user_id)
            .all()
        )
        first_org = {
            m.user_id: m.organization_id
            for m in db.query(OrganizationMembership).filter(OrganizationMembership.id.in_(list(first_ids.values())))
        }
        candidates = (
            db.query(OrganizationMembership, User)
            .join(User, User.id == OrganizationMembership.user_id)
            .filter(
                OrganizationMembership.organization_id == 1,
                OrganizationMembership.is_deleted == False,  # noqa: E712
                User.is_platform_admin == False,  # noqa: E712
            )
            .all()
        )
        retired = 0
        for membership, user in candidates:
            if first_org.get(user.id, 1) == 1:
                continue  # the user genuinely started in the default organization
            if membership.id == first_ids.get(user.id):
                continue
            if membership.created_at != user.created_at:
                continue  # not the backfill's signature: created on purpose later
            membership.is_active = False
            membership.is_deleted = True
            retired += 1
        if retired:
            db.commit()
            print(f"[OK] Retired {retired} default-organization membership(s) added by the start-up backfill")
