"""Pydantic schemas for the Leave domain."""
from datetime import date, datetime
from pydantic import BaseModel


class LeaveCreateRequest(BaseModel):
    start_date: date
    end_date: date
    reason: str
    leave_type: str = "casual"


class LeaveReviewRequest(BaseModel):
    decision: str  # 'approved' or 'rejected'
    notes: str | None = None


class LeaveResponse(BaseModel):
    id: int
    user_id: int
    user_name: str | None = None
    start_date: date
    end_date: date
    days_count: int | None = None
    reason: str
    leave_type: str
    status: str
    reviewed_by: int | None = None
    reviewed_at: datetime | None = None

    class Config:
        from_attributes = True
