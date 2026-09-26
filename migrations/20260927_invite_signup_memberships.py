"""Give invite-approved interns the organization membership approval never created.

Approving an invite-link signup used to activate the user without adding an
organization membership. Such users were then either left with no membership, or
(via the old start-up backfill) given only a default-organization membership.

For each non-platform user with a mentor whose memberships are empty, or consist
only of default-organization rows written by that backfill (created_at copied from
the user), the user joins the organization of the mentor's earliest non-default
membership, and the backfilled default-organization rows are retired. Users whose
mentor belongs only to the default organization are genuine default-org users and
are left alone.

Idempotent Python migration.
"""
from datetime import datetime, timezone

from sqlalchemy import inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

import models  # noqa: F401


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not (inspector.has_table("users") and inspector.has_table("organization_memberships")):
        return

    from models import OrganizationMembership, User

    with Session(bind=engine) as db:
        users = (
            db.query(User)
            .filter(
                User.is_deleted == False,  # noqa: E712
                User.is_platform_admin == False,  # noqa: E712
                User.mentor_id.isnot(None),
            )
            .all()
        )
        moved = 0
        for user in users:
            rows = (
                db.query(OrganizationMembership)
                .filter_by(user_id=user.id, is_deleted=False)
                .all()
            )
            backfilled = [r for r in rows if r.organization_id == 1 and r.created_at == user.created_at]
            if rows and len(backfilled) != len(rows):
                continue  # the user has a real membership already
            mentor_membership = (
                db.query(OrganizationMembership)
                .filter(
                    OrganizationMembership.user_id == user.mentor_id,
                    OrganizationMembership.organization_id != 1,
                    OrganizationMembership.is_deleted == False,  # noqa: E712
                )
                .order_by(OrganizationMembership.id.asc())
                .first()
            )
            if mentor_membership is None:
                continue  # mentor lives in the default organization: nothing to fix
            target = mentor_membership.organization_id
            existing = db.query(OrganizationMembership).filter_by(organization_id=target, user_id=user.id).first()
            if existing is None:
                db.add(OrganizationMembership(
                    organization_id=target,
                    user_id=user.id,
                    role=user.role,
                    mentor_membership_id=mentor_membership.id,
                    is_active=bool(user.is_active),
                    activated_at=user.activated_at or datetime.now(timezone.utc).replace(tzinfo=None),
                ))
            else:
                existing.is_deleted = False
                existing.is_active = bool(user.is_active)
            for row in backfilled:
                row.is_active = False
                row.is_deleted = True
            moved += 1
        if moved:
            db.commit()
            print(f"[OK] Placed {moved} invite-approved user(s) in their mentor's organization")
