"""JSON leave request endpoints."""
from datetime import date, datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import LeaveRequest, LeaveStatus, LeaveType, User
from utils import get_leave_balance, get_mentor_intern_ids, push_notification, record_audit, _business_days, isoformat_utc, sync_attendance_for_approved_leave, local_today

from routes.api.schemas import LeaveApplyRequest, LeaveReviewRequest, get_payload

router = APIRouter(prefix="/api/leave", tags=["Leave Management"])
DbSession = Annotated[Session, Depends(get_db)]


def _leave_dict(lr: LeaveRequest) -> dict:
    return {
        "id": lr.id,
        "user_id": lr.user_id,
        "user_name": lr.user.name if lr.user else None,
        "start_date": lr.start_date.isoformat(),
        "end_date": lr.end_date.isoformat(),
        "days": lr.days,
        "reason": lr.reason,
        "leave_type": lr.leave_type,
        "status": lr.status,
        "reviewed_by": lr.reviewed_by,
        "reviewer_name": lr.reviewer.name if lr.reviewer else None,
        "reviewed_at": isoformat_utc(lr.reviewed_at),
        "created_at": isoformat_utc(lr.created_at),
    }


def _has_overlap(db, user_id: int, start: date, end: date, exclude_id: int | None = None) -> bool:
    """Check if user already has a pending/approved leave overlapping the given dates."""
    q = db.query(LeaveRequest).filter(
        LeaveRequest.user_id == user_id,
        LeaveRequest.status.in_([LeaveStatus.PENDING, LeaveStatus.APPROVED]),
        LeaveRequest.start_date <= end,
        LeaveRequest.end_date >= start,
    )
    if exclude_id:
        q = q.filter(LeaveRequest.id != exclude_id)
    return q.first() is not None


@router.get("/mine")
async def my_requests(request: Request, db: DbSession):
    """Retrieve logged-in user's leave requests with pending status breakdown and quota balance."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    mine = (
        db.query(LeaveRequest)
        .options(joinedload(LeaveRequest.user), joinedload(LeaveRequest.reviewer))
        .filter(LeaveRequest.user_id == user.id, LeaveRequest.is_deleted == False)
        .order_by(LeaveRequest.created_at.desc())
        .all()
    )
    request_dicts = [_leave_dict(lr) for lr in mine]
    pending = [r for r in request_dicts if r["status"] == LeaveStatus.PENDING]
    approved = [r for r in request_dicts if r["status"] == LeaveStatus.APPROVED]
    rejected = [r for r in request_dicts if r["status"] == LeaveStatus.REJECTED]
    balance = get_leave_balance(db, user.id)

    return {
        "requests": request_dicts,
        "pending_requests": pending,
        "approved_requests": approved,
        "rejected_requests": rejected,
        "summary": {
            "total": len(request_dicts),
            "pending": len(pending),
            "approved": len(approved),
            "rejected": len(rejected),
            "days_taken": sum(r["days"] for r in approved),
            "days_pending": sum(r["days"] for r in pending),
        },
        "balance": balance,
    }


@router.post("")
async def apply(request: Request, db: DbSession, data: LeaveApplyRequest | None = Body(None)):
    """
    Submit a leave request with strict date, overlap, notice, and balance validations.
    """
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    if not user.is_intern:
        raise HTTPException(status_code=403, detail="Only interns can request leave.")

    payload = await get_payload(request, data)
    raw_start = str(payload.get("start_date") or payload.get("start") or "").strip()
    raw_end = str(payload.get("end_date") or payload.get("end") or "").strip()
    if not raw_start or not raw_end:
        raise HTTPException(status_code=422, detail="Both start_date and end_date are required.")

    try:
        start = date.fromisoformat(raw_start)
        end = date.fromisoformat(raw_end)
    except (ValueError, TypeError):
        raise HTTPException(status_code=422, detail="Invalid date format. Use YYYY-MM-DD.")

    if start > end:
        raise HTTPException(status_code=422, detail="End date must be on or after start date.")

    today = local_today()
    if start <= today:
        raise HTTPException(status_code=422, detail="Leave must be requested at least one day in advance.")

    reason = str(payload.get("reason", "")).strip()
    if not reason or len(reason) < 3:
        raise HTTPException(status_code=422, detail="Please provide a valid reason (at least 3 characters).")

    leave_type = str(payload.get("leave_type", LeaveType.CASUAL)).strip().lower()
    if leave_type not in LeaveType.ALL:
        leave_type = LeaveType.CASUAL

    days_requested = _business_days(start, end)
    if days_requested <= 0:
        raise HTTPException(status_code=422, detail="Requested leave period contains 0 working days.")

    # Overlap check against existing pending or approved requests
    if _has_overlap(db, user.id, start, end):
        raise HTTPException(
            status_code=409,
            detail="You already have a pending or approved leave overlapping these dates."
        )

    balance = get_leave_balance(db, user.id)
    if days_requested > balance["remaining"]:
        raise HTTPException(
            status_code=422,
            detail=f"Insufficient leave balance. You have {balance['remaining']} day(s) remaining, but requested {days_requested} working day(s)."
        )

    from routes.api.projects import _resolve_request_org_id
    org_id = _resolve_request_org_id(request, user, db)

    lr = LeaveRequest(
        organization_id=org_id,
        user_id=user.id,
        start_date=start,
        end_date=end,
        reason=reason,
        leave_type=leave_type,
        status=LeaveStatus.PENDING,
    )
    db.add(lr)
    record_audit(db, user, "leave.request", "requested leave", f"{start} → {end}")

    # Notify intern's mentor and organization admins
    notify_ids: set[int] = set()
    if user.mentor_id:
        notify_ids.add(user.mentor_id)
    for admin_user in db.query(User).filter(User.role.in_(("admin", "superadmin", "org_admin")), User.is_active == True).all():
        notify_ids.add(admin_user.id)
    for uid in notify_ids:
        push_notification(
            db, uid,
            f"{user.name} requested {leave_type} leave for {start.isoformat()} → {end.isoformat()} "
            f"({days_requested} day{'s' if days_requested != 1 else ''}).",
            link="/leave",
        )

    db.commit()
    db.refresh(lr)
    return _leave_dict(lr)


@router.get("/manage")
async def manage(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    status_filter = request.query_params.get("status", "pending")
    
    try:
        page = int(request.query_params.get("page", 1))
        page_size = int(request.query_params.get("page_size", 10))
        if page < 1:
            page = 1
        if page_size < 1:
            page_size = 10
    except ValueError:
        page = 1
        page_size = 10

    q = db.query(LeaveRequest).options(joinedload(LeaveRequest.user), joinedload(LeaveRequest.reviewer))
    if user.is_mentor and not user.is_admin:
        ids = get_mentor_intern_ids(db, user.id) or [-1]
        q = q.filter(LeaveRequest.user_id.in_(ids))
    if status_filter in (LeaveStatus.PENDING, LeaveStatus.APPROVED, LeaveStatus.REJECTED):
        q = q.filter(LeaveRequest.status == status_filter)
        
    total = q.count()
    import math
    total_pages = math.ceil(total / page_size) if total > 0 else 1
    
    requests_ = (
        q.order_by(LeaveRequest.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    
    return {
        "requests": [_leave_dict(lr) for lr in requests_],
        "page": page,
        "page_size": page_size,
        "total_pages": total_pages,
        "total": total
    }


@router.post("/{leave_id}/review")
@router.put("/{leave_id}/review")
@router.post("/review/{leave_id}")
@router.put("/review/{leave_id}")
async def review(leave_id: int, request: Request, db: DbSession, data: LeaveReviewRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor", "superadmin", "org_admin"):
        raise HTTPException(status_code=403)
    lr = db.query(LeaveRequest).options(joinedload(LeaveRequest.user)).filter_by(id=leave_id).first()
    if not lr:
        raise HTTPException(status_code=404)
    
    # Check tenant isolation when explicit header is passed
    target_org_id = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if target_org_id and str(target_org_id).isdigit():
        req_org_id = int(target_org_id)
        if lr.organization_id is not None and lr.organization_id != req_org_id:
            raise HTTPException(status_code=404, detail="Leave request not found.")

    # Mentors can only review leave for their own interns
    if user.is_mentor and not user.is_admin:
        allowed_ids = get_mentor_intern_ids(db, user.id)
        if lr.user_id not in allowed_ids:
            raise HTTPException(status_code=403, detail="You can only review leave requests for your own interns.")

    payload = await get_payload(request, data)
    raw_decision = str(payload.get("decision") or payload.get("status") or payload.get("action") or "").strip().lower()
    if raw_decision in ("approve", "approved"):
        decision = LeaveStatus.APPROVED
    elif raw_decision in ("reject", "rejected", "deny", "denied"):
        decision = LeaveStatus.REJECTED
    else:
        raise HTTPException(status_code=422, detail="Decision must be 'approved' or 'rejected'.")

    lr.status = str(decision)
    lr.reviewed_by = user.id
    lr.reviewed_at = datetime.now(timezone.utc).replace(tzinfo=None)
    if decision == LeaveStatus.APPROVED:
        sync_attendance_for_approved_leave(db, lr)
    push_notification(
        db, lr.user_id,
        f"Your leave request ({lr.start_date} → {lr.end_date}) was {decision} by {user.name}.",
        link="/leave"
    )
    record_audit(db, user, f"leave.{decision}", f"{decision} leave for", lr.user.name if lr.user else str(lr.user_id))
    db.commit()
    return _leave_dict(lr)


@router.get("/balance")
async def balance(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    return get_leave_balance(db, user.id)
