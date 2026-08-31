"""Add task_attachments table and attachment/internship period columns.

Idempotent Python migration.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from database import Base


def upgrade(engine: Engine) -> None:
    # Ensure all tables (including task_attachments) exist
    Base.metadata.create_all(bind=engine)

    insp = inspect(engine)

    # 1. users: internship_end_date, internship_duration_months
    user_cols = {c["name"] for c in insp.get_columns("users")}
    with engine.begin() as conn:
        if "internship_end_date" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN internship_end_date DATE NULL"))
        if "internship_duration_months" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN internship_duration_months INT NULL DEFAULT 3"))

    # 2. organization_memberships: internship_end_date, internship_duration_months
    if insp.has_table("organization_memberships"):
        member_cols = {c["name"] for c in insp.get_columns("organization_memberships")}
        with engine.begin() as conn:
            if "internship_end_date" not in member_cols:
                conn.execute(text("ALTER TABLE organization_memberships ADD COLUMN internship_end_date DATE NULL"))
            if "internship_duration_months" not in member_cols:
                conn.execute(text("ALTER TABLE organization_memberships ADD COLUMN internship_duration_months INT NULL DEFAULT 3"))

    # 3. leave_requests: attachment_path, attachment_name
    if insp.has_table("leave_requests"):
        leave_cols = {c["name"] for c in insp.get_columns("leave_requests")}
        with engine.begin() as conn:
            if "attachment_path" not in leave_cols:
                conn.execute(text("ALTER TABLE leave_requests ADD COLUMN attachment_path VARCHAR(500) NULL"))
            if "attachment_name" not in leave_cols:
                conn.execute(text("ALTER TABLE leave_requests ADD COLUMN attachment_name VARCHAR(255) NULL"))
