"""JSON standup log endpoints."""
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import StandupLog, User, BinEntityType
from recycle_bin import move_to_bin
from utils import get_mentor_intern_ids, record_audit, isoformat_utc, local_today

router = APIRouter(prefix="/api/standup", tags=["api-standup"])
DbSession = Annotated[Session, Depends(get_db)]

MOOD_OPTIONS = ["great", "good", "okay", "tired", "stressed"]


def _log_dict(log: StandupLog) -> dict:
    return {
        "id": log.id,
        "user_id": log.user_id,
        "user_name": log.user.name if log.user else None,
        "date": log.date.isoformat(),
        "did": log.did,
        "plan": log.plan,
        "blockers": log.blockers,
        "mood": log.mood,
        "created_at": isoformat_utc(log.created_at),
    }


@router.get("")
async def list_standups(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    q = db.query(StandupLog).options(joinedload(StandupLog.user)).filter(
        StandupLog.is_deleted == False
    )

    if user.is_intern:
        q = q.filter(StandupLog.user_id == user.id)
    elif user.is_mentor:
        intern_ids = get_mentor_intern_ids(db, user.id) or [-1]
        q = q.filter(StandupLog.user_id.in_(intern_ids))

    # Optional date range filter
    from_date = request.query_params.get("from")
    to_date = request.query_params.get("to")
    if from_date:
        try:
            q = q.filter(StandupLog.date >= date.fromisoformat(from_date))
        except ValueError:
            pass
    if to_date:
        try:
            q = q.filter(StandupLog.date <= date.fromisoformat(to_date))
        except ValueError:
            pass

    # Optional user_id filter for mentor/admin
    uid = request.query_params.get("user_id")
    if uid and not user.is_intern:
        try:
            q = q.filter(StandupLog.user_id == int(uid))
        except ValueError:
            pass

    params = request.query_params
    try:
        page = max(1, int(params.get("page", 1)))
        page_size = max(1, min(100, int(params.get("page_size", 20))))
    except ValueError:
        page, page_size = 1, 20

    total = q.count()
    logs = q.order_by(StandupLog.date.desc()).offset((page - 1) * page_size).limit(page_size).all()
    return {
        "logs": [_log_dict(log) for log in logs],
        "page": page,
        "total": total,
        "total_pages": max(1, (total + page_size - 1) // page_size),
    }


@router.get("/today")
async def today_standup(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    today = local_today()
    log = db.query(StandupLog).filter_by(user_id=user.id, date=today).first()
    return _log_dict(log) if log else None


@router.post("")
async def submit_standup(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    data = await request.json()

    did = str(data.get("did", "")).strip()
    plan = str(data.get("plan", "")).strip()
    blockers = str(data.get("blockers", "")).strip() or None
    mood = str(data.get("mood", "")).strip()
    if mood not in MOOD_OPTIONS:
        mood = None

    if not did or not plan:
        raise HTTPException(status_code=422, detail="Both 'did' and 'plan' are required.")

    try:
        log_date = date.fromisoformat(str(data.get("date", local_today().isoformat())))
    except ValueError:
        log_date = local_today()

    # Interns can only submit standups for today
    if user.is_intern and log_date != local_today():
        raise HTTPException(status_code=422, detail="Interns can only submit a standup for today.")

    existing = db.query(StandupLog).filter_by(user_id=user.id, date=log_date).first()
    if existing:
        existing.did = did
        existing.plan = plan
        existing.blockers = blockers
        existing.mood = mood
        record_audit(db, user, "standup.update", "updated standup", log_date.isoformat())
        db.commit()
        return _log_dict(existing)

    log = StandupLog(user_id=user.id, date=log_date, did=did, plan=plan, blockers=blockers, mood=mood)
    db.add(log)
    record_audit(db, user, "standup.submit", "submitted standup", log_date.isoformat())
    db.commit()
    db.refresh(log)
    log = db.query(StandupLog).options(joinedload(StandupLog.user)).filter_by(id=log.id).first()
    return _log_dict(log)


@router.put("/{log_id}")
async def update_standup(log_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    log = db.get(StandupLog, log_id)
    if not log or log.is_deleted:
        raise HTTPException(status_code=404)
    # Users can edit their own standups; admins can edit anyone's
    if log.user_id != user.id and not user.is_admin:
        raise HTTPException(status_code=403)

    data = await request.json()
    if "did" in data:
        log.did = str(data["did"]).strip()
    if "plan" in data:
        log.plan = str(data["plan"]).strip()
    if "blockers" in data:
        log.blockers = str(data["blockers"]).strip() or None
    if "mood" in data:
        mood = str(data["mood"]).strip()
        log.mood = mood if mood in MOOD_OPTIONS else None
    record_audit(db, user, "standup.update", "updated standup", log.date.isoformat())
    db.commit()
    log = db.query(StandupLog).options(joinedload(StandupLog.user)).filter_by(id=log_id).first()
    return _log_dict(log)


@router.delete("/{log_id}")
async def delete_standup(log_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    log = db.get(StandupLog, log_id)
    if not log or log.is_deleted:
        raise HTTPException(status_code=404)
    if log.user_id != user.id and not user.is_admin:
        raise HTTPException(status_code=403)
    record_audit(
        db,
        user,
        "standup.delete",
        "deleted standup",
        log.date.isoformat(),
        affected_user_id=log.user_id,
    )
    move_to_bin(
        db,
        user,
        BinEntityType.STANDUP,
        log,
        title=f"Standup {log.date.isoformat()}",
    )
    db.commit()
    return {"ok": True}
