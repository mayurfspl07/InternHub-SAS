"""JSON cohort endpoints."""
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from sqlalchemy.orm import Session, joinedload
from datetime import date

from database import get_db
from dependencies import get_optional_user
from models import Cohort, CohortMember, User, BinEntityType
from recycle_bin import move_to_bin
from utils import push_notification, record_audit, isoformat_utc
from routes.api.schemas import CohortCreatePayload, CohortUpdatePayload, CohortMemberPayload, get_payload

router = APIRouter(prefix="/api/cohorts", tags=["Cohorts"])
DbSession = Annotated[Session, Depends(get_db)]


def _member_dict(m: CohortMember) -> dict:
    return {
        "user_id": m.user_id,
        "user_name": m.user.name if m.user else None,
        "user_email": m.user.email if m.user else None,
        "role": m.user.role if m.user else None,
        "joined_at": isoformat_utc(m.joined_at),
    }


def _cohort_dict(c: Cohort, include_members: bool = False) -> dict:
    data = {
        "id": c.id,
        "name": c.name,
        "description": c.description,
        "start_date": c.start_date.isoformat() if c.start_date else None,
        "end_date": c.end_date.isoformat() if c.end_date else None,
        "created_at": isoformat_utc(c.created_at),
        "created_by_id": c.created_by_id,
        "member_count": len(c.members),
    }
    if include_members:
        data["members"] = [
            {
                "user_id": m.user_id,
                "name": m.user.name if m.user else None,
                "email": m.user.email if m.user else None,
                "department": m.user.department if m.user else None,
                "joined_at": isoformat_utc(m.joined_at),
            }
            for m in c.members
            if m.user and not m.user.is_deleted
        ]
    return data


@router.get("")
async def list_cohorts(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    q = db.query(Cohort).options(joinedload(Cohort.members).joinedload(CohortMember.user)).filter(
        Cohort.is_deleted == False
    )
    if user.is_intern:
        # Interns only see cohorts they are a member of
        cohort_ids = [m.cohort_id for m in db.query(CohortMember.cohort_id).filter_by(user_id=user.id).all()]
        q = q.filter(Cohort.id.in_(cohort_ids))
    cohorts = q.order_by(Cohort.created_at.desc()).all()
    return [_cohort_dict(c, include_members=True) for c in cohorts]


@router.post("")
async def create_cohort(request: Request, db: DbSession, data: CohortCreatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    payload = await get_payload(request, data)
    name = str(payload.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=422, detail="Name is required.")

    start_date = None
    end_date = None
    if payload.get("start_date"):
        try:
            start_date = date.fromisoformat(str(payload["start_date"]))
        except ValueError:
            pass
    if payload.get("end_date"):
        try:
            end_date = date.fromisoformat(str(payload["end_date"]))
        except ValueError:
            pass

    cohort = Cohort(
        name=name,
        description=str(payload.get("description") or "").strip() or None,
        start_date=start_date,
        end_date=end_date,
        created_by_id=user.id,
    )
    db.add(cohort)
    record_audit(db, user, "cohort.create", "created cohort", name)
    db.commit()
    db.refresh(cohort)
    cohort = db.query(Cohort).options(joinedload(Cohort.members).joinedload(CohortMember.user)).filter_by(id=cohort.id).first()
    return _cohort_dict(cohort, include_members=True)


@router.get("/{cohort_id}")
async def get_cohort(cohort_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    cohort = db.query(Cohort).options(joinedload(Cohort.members).joinedload(CohortMember.user)).filter_by(id=cohort_id).first()
    if not cohort:
        raise HTTPException(status_code=404)
    if user.is_intern:
        is_member = db.query(CohortMember).filter_by(cohort_id=cohort_id, user_id=user.id).first()
        if not is_member:
            raise HTTPException(status_code=404)  # 404 avoids revealing cohort existence
    return _cohort_dict(cohort, include_members=True)


@router.put("/{cohort_id}")
async def update_cohort(cohort_id: int, request: Request, db: DbSession, data: CohortUpdatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    cohort = db.get(Cohort, cohort_id)
    if not cohort or cohort.is_deleted:
        raise HTTPException(status_code=404)
    # Only admins or the cohort creator can update
    if user.is_mentor and cohort.created_by_id != user.id:
        raise HTTPException(status_code=403, detail="Only the cohort creator or an admin can update this cohort.")
    payload = await get_payload(request, data)
    if "name" in payload and payload["name"] is not None:
        cohort.name = str(payload["name"]).strip()
    if "description" in payload:
        cohort.description = str(payload["description"]).strip() or None if payload["description"] is not None else None
    if payload.get("start_date"):
        try:
            cohort.start_date = date.fromisoformat(str(payload["start_date"]))
        except ValueError:
            pass
    if payload.get("end_date"):
        try:
            cohort.end_date = date.fromisoformat(str(payload["end_date"]))
        except ValueError:
            pass
    record_audit(db, user, "cohort.update", "updated cohort", cohort.name)
    db.commit()
    cohort = db.query(Cohort).options(joinedload(Cohort.members).joinedload(CohortMember.user)).filter_by(id=cohort_id).first()
    return _cohort_dict(cohort, include_members=True)


@router.delete("/{cohort_id}")
async def delete_cohort(cohort_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    cohort = db.get(Cohort, cohort_id)
    if not cohort or cohort.is_deleted:
        raise HTTPException(status_code=404)
    # Only admins or the cohort creator can delete
    if user.is_mentor and cohort.created_by_id != user.id:
        raise HTTPException(status_code=403, detail="Only the cohort creator or an admin can delete this cohort.")
    record_audit(db, user, "cohort.delete", "deleted cohort", cohort.name)
    move_to_bin(db, user, BinEntityType.COHORT, cohort, title=cohort.name)
    db.commit()
    return {"ok": True}


@router.post("/{cohort_id}/members")
async def add_member(cohort_id: int, request: Request, db: DbSession, data: CohortMemberPayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    cohort = db.get(Cohort, cohort_id)
    if not cohort or cohort.is_deleted:
        raise HTTPException(status_code=404)
    if user.is_mentor and cohort.created_by_id != user.id:
        raise HTTPException(status_code=403, detail="Only the cohort creator or an admin can add members.")

    payload = await get_payload(request, data)
    try:
        user_id = int(payload.get("user_id", 0))
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Invalid user_id.")
    target_user = db.get(User, user_id)
    if not target_user or target_user.is_deleted:
        raise HTTPException(status_code=404, detail="User not found.")

    existing = db.query(CohortMember).filter_by(cohort_id=cohort_id, user_id=user_id).first()
    if existing:
        return {"ok": True, "already_member": True}

    db.add(CohortMember(cohort_id=cohort_id, user_id=user_id))
    push_notification(db, user_id, f"You were added to the cohort: {cohort.name}", link="/cohorts")
    record_audit(db, user, "cohort.add_member", f"added {target_user.name} to cohort", cohort.name, affected_user_id=user_id)
    db.commit()
    return {"ok": True}


@router.delete("/{cohort_id}/members/{user_id}")
async def remove_member(cohort_id: int, user_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    member = db.query(CohortMember).filter_by(cohort_id=cohort_id, user_id=user_id).first()
    if member:
        cohort = db.get(Cohort, cohort_id)
        target = db.get(User, user_id)
        record_audit(
            db,
            user,
            "cohort.remove_member",
            f"removed {target.name if target else user_id} from cohort",
            cohort.name if cohort else str(cohort_id),
            affected_user_id=user_id,
        )
        db.delete(member)
        db.commit()
    return {"ok": True}
