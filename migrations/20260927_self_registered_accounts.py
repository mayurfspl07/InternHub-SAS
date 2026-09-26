"""Flag public self-registrations made since multi-tenancy and detach them from org 1.

Accounts created through /api/auth/register after the multi-tenant cut-over belong
to no organization, but the old start-up backfill quietly made them members of the
default organization. They are identified by their own "registered account" audit
entry (actor is the new user) and a creation time after organization 1 was created.
Each is flagged ``self_registered`` and, when its only memberships are the
default-organization rows the backfill wrote (created_at copied from the user),
those rows are soft-deleted. Accounts an admin later added to an organization keep
that membership. Idempotent Python migration.
"""
from sqlalchemy import inspect
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

import models  # noqa: F401

REGISTER_ACTIONS = ("user.register", "user.register_mentor_pending")


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    needed = ("users", "organization_memberships", "audit_logs", "organizations")
    if not all(inspector.has_table(t) for t in needed):
        return
    if "self_registered" not in {c["name"] for c in inspector.get_columns("users")}:
        return

    from models import AuditLog, Organization, OrganizationMembership, User

    with Session(bind=engine) as db:
        default_org = db.get(Organization, 1)
        if default_org is None or default_org.created_at is None:
            return
        registered_ids = {
            actor_id for (actor_id,) in db.query(AuditLog.actor_id)
            .filter(AuditLog.action.in_(REGISTER_ACTIONS), AuditLog.actor_id.isnot(None))
            .distinct()
        }
        if not registered_ids:
            return
        users = (
            db.query(User)
            .filter(
                User.id.in_(registered_ids),
                User.is_platform_admin == False,  # noqa: E712
                User.created_at > default_org.created_at,
            )
            .all()
        )
        flagged = detached = 0
        for user in users:
            if not user.self_registered:
                user.self_registered = True
                flagged += 1
            rows = db.query(OrganizationMembership).filter_by(user_id=user.id, is_deleted=False).all()
            backfilled = [r for r in rows if r.organization_id == 1 and r.created_at == user.created_at]
            if rows and len(backfilled) == len(rows):
                for row in backfilled:
                    row.is_active = False
                    row.is_deleted = True
                detached += 1
        if flagged or detached:
            db.commit()
            print(f"[OK] Flagged {flagged} self-registered account(s); detached {detached} from the default organization")
