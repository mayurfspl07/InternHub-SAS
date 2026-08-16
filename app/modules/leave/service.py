"""Domain service for applying, calculating, and reviewing leave requests."""
from datetime import date, datetime, timezone
from sqlalchemy.orm import Session

from app.modules.leave.calculator import count_business_days, calculate_leave_balance
from app.modules.leave.repository import LeaveRepository
from app.modules.leave.schemas import LeaveCreateRequest, LeaveReviewRequest
from models import LeaveRequest, OrganizationSettings, User


class LeaveService:
    def __init__(self, db: Session, org_id: int, settings: OrganizationSettings):
        self.db = db
        self.org_id = org_id
        self.settings = settings
        self.repo = LeaveRepository(db, org_id)

    def apply_leave(self, user: User, request: LeaveCreateRequest) -> LeaveRequest:
        days = count_business_days(request.start_date, request.end_date)
        if days <= 0:
            raise ValueError("Leave start date must be before or equal to end date.")

        lr = LeaveRequest(
            user_id=user.id,
            organization_id=self.org_id,
            start_date=request.start_date,
            end_date=request.end_date,
            days_count=days,
            reason=request.reason,
            leave_type=request.leave_type,
            status="pending",
        )
        return self.repo.create(lr)

    def review_leave(self, leave_id: int, reviewer: User, request: LeaveReviewRequest) -> LeaveRequest:
        lr = self.repo.get_by_id(leave_id)
        if not lr:
            raise ValueError("Leave request not found.")

        lr.status = request.decision
        lr.reviewed_by = reviewer.id
        lr.reviewed_at = datetime.now(timezone.utc).replace(tzinfo=None)
        return self.repo.update(lr)
