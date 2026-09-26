"""Backfill recycle-bin rows with the organization that owns the binned record.

Before this fix move_to_bin never set ``bin_items.organization_id``, so every
tenant's deleted records landed in the default organization's bin. Rows are
re-tagged from their linked entity; rows whose entity is gone keep their value.

Idempotent Python migration.
"""
from sqlalchemy import inspect, or_
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

import models  # noqa: F401


def upgrade(engine: Engine) -> None:
    if not inspect(engine).has_table("bin_items"):
        return

    from models import BinItem
    from recycle_bin import entity_org_id, get_entity

    with Session(bind=engine) as db:
        rows = (
            db.query(BinItem)
            .filter(BinItem.restored_at.is_(None))
            .filter(or_(BinItem.organization_id.is_(None), BinItem.organization_id == 1))
            .all()
        )
        changed = 0
        for item in rows:
            entity = get_entity(db, item.entity_type, item.entity_id)
            if entity is None:
                continue
            org_id = entity_org_id(db, item.entity_type, entity)
            if org_id is not None and org_id != item.organization_id:
                item.organization_id = org_id
                changed += 1
        if changed:
            db.commit()
            print(f"[OK] Re-tagged {changed} recycle bin item(s) with their organization")
