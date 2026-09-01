"""Add project_status_buckets, internship_duration_masters, assignments, and assignment_submissions tables.

Idempotent Python migration.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

from database import Base


def upgrade(engine: Engine) -> None:
    # Ensure all tables exist
    Base.metadata.create_all(bind=engine)

    insp = inspect(engine)

    # Seed default project statuses and internship duration masters for org 1 if needed
    from sqlalchemy.orm import Session
    from utils import get_or_seed_org_project_statuses, get_or_seed_org_internship_durations

    with Session(engine) as db:
        try:
            get_or_seed_org_project_statuses(db, org_id=1)
            get_or_seed_org_internship_durations(db, org_id=1)
        except Exception:
            pass
