"""Add task_status_buckets table and backfill default buckets for existing organizations.

Idempotent Python migration.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from database import Base


def upgrade(engine: Engine) -> None:
    # Ensure task_status_buckets table is created
    Base.metadata.create_all(bind=engine)

    # Seed default buckets for any existing organizations that don't have them
    with Session(bind=engine) as db:
        from models import Organization, TaskStatusBucket
        from utils import get_or_seed_org_task_statuses

        orgs = db.query(Organization).filter_by(is_deleted=False).all()
        for org in orgs:
            get_or_seed_org_task_statuses(db, org.id)
