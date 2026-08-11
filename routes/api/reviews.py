"""JSON performance review endpoints."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import PerformanceReview, Project, User, BinEntityType
from recycle_bin import move_to_bin
from utils import push_notification, record_audit, isoformat_utc

router = APIRouter(prefix="/api/reviews", tags=["api-reviews"])
DbSession = Annotated[Session, Depends(get_db)]


def _review_dict(r: PerformanceReview) -> dict:
    return {
        "id": r.id,
        "intern_id": r.intern_id,
        "intern_name": r.intern.name if r.intern else None,
        "reviewer_id": r.reviewer_id,
        "reviewer_name": r.reviewer.name if r.reviewer else None,
        "project_id": r.project_id,
        "project_name": r.project.name if r.project else None,
        "period": r.period,
        "rating": r.rating,
        "technical_rating": r.technical_rating,
        "communication_rating": r.communication_rating,
        "initiative_rating": r.initiative_rating,
        "feedback": r.feedback,
        "strengths": r.strengths,
        "improvements": r.improvements,
        "created_at": isoformat_utc(r.created_at),
    }


@router.get("")
async def list_reviews(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    q = db.query(PerformanceReview).options(
        joinedload(PerformanceReview.intern),
        joinedload(PerformanceReview.reviewer),
        joinedload(PerformanceReview.project),
    ).filter(PerformanceReview.is_deleted == False)
    if user.is_intern:
        q = q.filter(PerformanceReview.intern_id == user.id)
    elif user.is_mentor:
        q = q.filter(PerformanceReview.reviewer_id == user.id)
    reviews = q.order_by(PerformanceReview.created_at.desc()).all()
    return [_review_dict(r) for r in reviews]


@router.post("")
async def create_review(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    data = await request.json()

    intern_id = data.get("intern_id")
    if not intern_id:
        raise HTTPException(status_code=422, detail="intern_id is required.")
    try:
        intern_id = int(intern_id)
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Invalid intern_id.")
    intern = db.get(User, intern_id)
    if not intern or not intern.is_intern:
        raise HTTPException(status_code=404, detail="Intern not found.")

    try:
        rating = int(data.get("rating", 0))
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Rating must be a number.")
    if rating < 1 or rating > 5:
        raise HTTPException(status_code=422, detail="Overall rating must be 1–5.")

    def _rating(key: str) -> int | None:
        val = data.get(key)
        if val is None:
            return None
        try:
            v = int(val)
        except (TypeError, ValueError):
            return None
        return v if 1 <= v <= 5 else None

    project_id = data.get("project_id")
    if project_id:
        try:
            project_id = int(project_id)
        except (TypeError, ValueError):
            project_id = None
        if project_id and not db.get(Project, project_id):
            project_id = None

    period = str(data.get("period", "")).strip() or None
    # One review per intern/reviewer/period (mirrors the DB unique constraint)
    if period:
        duplicate = db.query(PerformanceReview).filter_by(
            intern_id=intern.id, reviewer_id=user.id, period=period
        ).first()
        if duplicate:
            raise HTTPException(
                status_code=409,
                detail=f"You already submitted a review for this intern for period '{period}'.",
            )

    review = PerformanceReview(
        intern_id=intern.id,
        reviewer_id=user.id,
        project_id=project_id,
        period=period,
        rating=rating,
        technical_rating=_rating("technical_rating"),
        communication_rating=_rating("communication_rating"),
        initiative_rating=_rating("initiative_rating"),
        feedback=str(data.get("feedback", "")).strip() or None,
        strengths=str(data.get("strengths", "")).strip() or None,
        improvements=str(data.get("improvements", "")).strip() or None,
    )
    db.add(review)
    push_notification(db, intern.id, f"You received a performance review from {user.name}.", link="/reviews")
    record_audit(db, user, "review.create", "submitted performance review for", intern.name, affected_user_id=intern.id)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="A review for this intern and period already exists.",
        )
    db.refresh(review)
    review = db.query(PerformanceReview).options(
        joinedload(PerformanceReview.intern),
        joinedload(PerformanceReview.reviewer),
        joinedload(PerformanceReview.project),
    ).filter_by(id=review.id).first()
    return _review_dict(review)


@router.get("/{review_id}")
async def get_review(review_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    review = db.query(PerformanceReview).options(
        joinedload(PerformanceReview.intern),
        joinedload(PerformanceReview.reviewer),
        joinedload(PerformanceReview.project),
    ).filter_by(id=review_id).first()
    if not review:
        raise HTTPException(status_code=404)
    if user.is_intern and review.intern_id != user.id:
        raise HTTPException(status_code=403)
    return _review_dict(review)


@router.put("/{review_id}")
async def update_review(review_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    review = db.get(PerformanceReview, review_id)
    if not review or review.is_deleted:
        raise HTTPException(status_code=404)
    if not user.is_admin and review.reviewer_id != user.id:
        raise HTTPException(status_code=403)

    data = await request.json()
    if "rating" in data:
        try:
            r = int(data["rating"])
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="Rating must be a number.")
        if r < 1 or r > 5:
            raise HTTPException(status_code=422, detail="Rating must be 1–5.")
        review.rating = r
    for key in ("technical_rating", "communication_rating", "initiative_rating"):
        if key in data and data[key] is not None:
            try:
                v = int(data[key])
            except (TypeError, ValueError):
                continue
            setattr(review, key, v if 1 <= v <= 5 else None)
    for key in ("period", "feedback", "strengths", "improvements"):
        if key in data:
            setattr(review, key, str(data[key]).strip() or None)

    intern = db.get(User, review.intern_id)
    record_audit(db, user, "review.update", "updated performance review for", intern.name if intern else str(review.intern_id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="A review for this intern and period already exists.",
        )
    review = db.query(PerformanceReview).options(
        joinedload(PerformanceReview.intern),
        joinedload(PerformanceReview.reviewer),
        joinedload(PerformanceReview.project),
    ).filter_by(id=review_id).first()
    return _review_dict(review)


@router.delete("/{review_id}")
async def delete_review(review_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.is_intern:
        raise HTTPException(status_code=403)
    review = db.get(PerformanceReview, review_id)
    if not review or review.is_deleted:
        raise HTTPException(status_code=404)
    if not user.is_admin and review.reviewer_id != user.id:
        raise HTTPException(status_code=403)
    intern = db.get(User, review.intern_id)
    record_audit(
        db,
        user,
        "review.delete",
        "deleted performance review for",
        intern.name if intern else str(review.intern_id),
        project_id=review.project_id,
        affected_user_id=review.intern_id,
    )
    move_to_bin(
        db,
        user,
        BinEntityType.REVIEW,
        review,
        title=f"Review for {intern.name if intern else review.intern_id}",
    )
    db.commit()
    return {"ok": True}
