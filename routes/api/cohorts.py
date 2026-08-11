"""JSON cohort endpoints."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import Cohort, CohortMember, User, BinEntityType
from recycle_bin import move_to_bin
from utils import record_audit, isoformat_utc

router = APIRouter(prefix="/api/cohorts", tags=["api-cohorts"])
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
    d = {
        "id": c.id,
        "name": c.name,
        "description": c.description,
        "start_date": c.start_date.isoformat() if c.start_date else None,
        "end_date": c.end_date.isoformat() if c.end_date else None,
        "created_at": isoformat_utc(c.created_at),
        "created_by_id": c.created_by_id,
        "member_count": len(c.members) if c.members is not None else 0,
    }
    if include_members:
        d["members"] = [_member_dict(m) for m in c.members]
    return d


@router.get("")
async def list_cohorts(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    q = db.query(Cohort).options(joinedload(Cohort.members).joinedload(CohortMember.user)).filter(
        Cohort.is_deleted == False
    )
    if user.is_intern:
        member_cohort_ids = [r[0] for r in db.query(CohortMember.cohort_id).filter_by(user_id=user.id).all()]
        q = q.filter(Cohort.id.in_(member_cohort_ids))
    cohorts = q.order_by(Cohort.created_at.desc()).all()
    return [_cohort_dict(c) for c in cohorts]


@router.post("")
async def create_cohort(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    data = await request.json()
    name = str(data.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=422, detail="Name is required.")

    from datetime import date
    start_date = None
    end_date = None
    if data.get("start_date"):
        try:
            start_date = date.fromisoformat(str(data["start_date"]))
        except ValueError:
            pass
    if data.get("end_date"):
        try:
            end_date = date.fromisoformat(str(data["end_date"]))
        except ValueError:
            pass

    cohort = Cohort(
        name=name,
        description=str(data.get("description", "")).strip() or None,
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
async def update_cohort(cohort_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    cohort = db.get(Cohort, cohort_id)
    if not cohort or cohort.is_deleted:
        raise HTTPException(status_code=404)
    # Only admins or the cohort creator can update
    if user.is_mentor and cohort.created_by_id != user.id:
        raise HTTPException(status_code=403, detail="Only the cohort creator or an admin can update this cohort.")
    data = await request.json()
    if "name" in data:
        cohort.name = str(data["name"]).strip()
    if "description" in data:
        cohort.description = str(data["description"]).strip() or None
    from datetime import date
    if "start_date" in data and data["start_date"]:
        try:
            cohort.start_date = date.fromisoformat(str(data["start_date"]))
        except ValueError:
            pass
    if "end_date" in data and data["end_date"]:
        try:
            cohort.end_date = date.fromisoformat(str(data["end_date"]))
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
async def add_member(cohort_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    cohort = db.get(Cohort, cohort_id)
    if not cohort or cohort.is_deleted:
        raise HTTPException(status_code=404)
    data = await request.json()
    user_id = data.get("user_id")
    if not user_id:
        raise HTTPException(status_code=422, detail="user_id is required.")
    try:
        user_id = int(user_id)
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Invalid user_id.")
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found.")
    existing = db.query(CohortMember).filter_by(cohort_id=cohort_id, user_id=target.id).first()
    if existing:
        return {"ok": True, "message": "Already a member."}
    member = CohortMember(cohort_id=cohort_id, user_id=target.id)
    db.add(member)
    record_audit(db, user, "cohort.add_member", f"added {target.name} to cohort", cohort.name)
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
