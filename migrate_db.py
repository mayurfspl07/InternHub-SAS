"""Sync database schema with SQLAlchemy models (add missing tables/columns)."""
import importlib
import sys

from sqlalchemy import inspect, text
from sqlalchemy.schema import CreateColumn

from database import Base, engine

import models  # noqa: F401 — register all models on Base.metadata


def sync_schema() -> None:
    inspector = inspect(engine)

    with engine.begin() as conn:
        for table_name, table in sorted(Base.metadata.tables.items()):
            if not inspector.has_table(table_name):
                continue
            existing = {c["name"] for c in inspector.get_columns(table_name)}
            for column in table.columns:
                if column.name in existing:
                    continue
                fragment = str(CreateColumn(column).compile(dialect=engine.dialect))
                conn.execute(text(f"ALTER TABLE `{table_name}` ADD {fragment}"))
                print(f"[OK] Added column {table_name}.{column.name}")

    Base.metadata.create_all(bind=engine)

    task_creator_migration = importlib.import_module(
        "migrations.20260721_add_task_created_by"
    )
    task_creator_migration.upgrade(engine)
    audit_timestamp_migration = importlib.import_module(
        "migrations.20260721_audit_created_at_utc"
    )
    audit_timestamp_migration.upgrade(engine)
    recycle_bin_migration = importlib.import_module(
        "migrations.20260722_recycle_bin"
    )
    recycle_bin_migration.upgrade(engine)
    activated_at_migration = importlib.import_module(
        "migrations.20260805_backfill_user_activated_at"
    )
    activated_at_migration.upgrade(engine)
    multi_tenant_migration = importlib.import_module(
        "migrations.20260815_multi_tenant_saas"
    )
    multi_tenant_migration.upgrade(engine)
    task_status_migration = importlib.import_module(
        "migrations.20260831_add_task_status_buckets"
    )
    task_status_migration.upgrade(engine)
    features_2_to_5_migration = importlib.import_module(
        "migrations.20260831_features_2_to_5"
    )
    features_2_to_5_migration.upgrade(engine)
    print("[OK] Schema sync complete.")


if __name__ == "__main__":
    try:
        sync_schema()
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        sys.exit(1)
