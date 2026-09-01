"""Migration to create tenant_smtp_configs and email_logs tables."""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

from database import Base
import models  # noqa: F401


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)

    # Ensure tables are created if not present
    Base.metadata.create_all(bind=engine)

    with engine.begin() as conn:
        dialect = engine.dialect.name
        if dialect == "sqlite":
            return

        # Add index if missing
        if inspector.has_table("tenant_smtp_configs"):
            existing_indexes = {idx["name"] for idx in inspector.get_indexes("tenant_smtp_configs")}
            if "ix_tenant_smtp_org" not in existing_indexes:
                try:
                    conn.execute(text("CREATE INDEX ix_tenant_smtp_org ON tenant_smtp_configs (organization_id)"))
                except Exception:
                    pass

        if inspector.has_table("email_logs"):
            existing_indexes = {idx["name"] for idx in inspector.get_indexes("email_logs")}
            if "ix_email_logs_org_sent" not in existing_indexes:
                try:
                    conn.execute(text("CREATE INDEX ix_email_logs_org_sent ON email_logs (organization_id, sent_at)"))
                except Exception:
                    pass
