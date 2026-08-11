"""Backfill users.activated_at for accounts that predate this column — without this,
the generic column-sync leaves it NULL for every existing user, which would make login
treat any of them as "still pending approval" on their next deactivation instead of
"was active, now deactivated".

Two cases:
1. Currently active users obviously have been activated.
2. Currently *inactive* users who were nonetheless active at some point in the past (then
   later deactivated by an admin/mentor) — inferred from the audit trail, since
   activated_at didn't exist yet to record this directly when it happened.

This project uses idempotent Python migrations rather than Alembic revisions.
"""
from sqlalchemy import bindparam, inspect, text
from sqlalchemy.engine import Engine


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not inspector.has_table("users"):
        return
    columns = {column["name"] for column in inspector.get_columns("users")}
    if "activated_at" not in columns:
        return

    with engine.begin() as connection:
        connection.execute(
            text(
                "UPDATE `users` SET `activated_at` = `created_at` "
                "WHERE `is_active` = 1 AND `activated_at` IS NULL"
            )
        )

        if inspector.has_table("audit_logs"):
            rows = connection.execute(
                text(
                    "SELECT DISTINCT affected_user_id FROM `audit_logs` "
                    "WHERE action IN ('user.activated', 'user.signup_approve') "
                    "AND affected_user_id IS NOT NULL"
                )
            ).fetchall()
            ever_activated_ids = [r[0] for r in rows]
            if ever_activated_ids:
                stmt = text(
                    "UPDATE `users` SET `activated_at` = `created_at` "
                    "WHERE `is_active` = 0 AND `activated_at` IS NULL AND `id` IN :ids"
                ).bindparams(bindparam("ids", expanding=True))
                connection.execute(stmt, {"ids": ever_activated_ids})
