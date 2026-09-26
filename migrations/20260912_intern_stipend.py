"""Add intern paid/unpaid + monthly stipend columns to users and organization_memberships.

Idempotent Python migration.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

from database import Base
import models  # noqa: F401


_COLUMN_SPECS = {
    "users": [
        ("is_paid", "BOOLEAN NULL"),
        ("stipend_amount", "FLOAT NULL"),
    ],
    "organization_memberships": [
        ("is_paid", "BOOLEAN NULL"),
        ("stipend_amount", "FLOAT NULL"),
    ],
}


def upgrade(engine: Engine) -> None:
    # Fresh databases already get the columns via create_all from current models.
    Base.metadata.create_all(bind=engine)

    inspector = inspect(engine)
    for table_name, columns in _COLUMN_SPECS.items():
        if not inspector.has_table(table_name):
            continue
        existing = {column["name"] for column in inspector.get_columns(table_name)}
        with engine.begin() as connection:
            for column_name, column_sql in columns:
                if column_name in existing:
                    continue
                connection.execute(
                    text(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_sql}")
                )
