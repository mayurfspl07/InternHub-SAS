"""Data access repository for Leave entities."""
from datetime import date
from sqlalchemy import desc
from sqlalchemy.orm import Session, joinedload

from models import LeaveRequest


class LeaveRepository:
    def __init__(self, db: Session, org_id: int = 1):
        self.db = db
        self.org_id = org_id

    def get_by_id(self, leave_id: int) -> LeaveRequest | None:
        return (
            self.db.query(LeaveRequest)
            .options(
                joinedload(LeaveRequest.user),
                joinedload(LeaveRequest.reviewer),
            )
            .filter(
                LeaveRequest.id == leave_id,
                LeaveRequest.organization_id == self.org_id,
                LeaveRequest.is_deleted == False,
            )
            .first()
        )

    def list_for_user(self, user_id: int) -> list[LeaveRequest]:
        return (
            self.db.query(LeaveRequest)
            .filter(
                LeaveRequest.user_id == user_id,
                LeaveRequest.organization_id == self.org_id,
                LeaveRequest.is_deleted == False,
            )
            .order_by(desc(LeaveRequest.created_at))
            .all()
        )

    def list_pending(self, intern_ids: list[int] | None = None) -> list[LeaveRequest]:
        q = (
            self.db.query(LeaveRequest)
            .options(joinedload(LeaveRequest.user))
            .filter(
                LeaveRequest.organization_id == self.org_id,
                LeaveRequest.status == "pending",
                LeaveRequest.is_deleted == False,
            )
        )
        if intern_ids is not None:
            q = q.filter(LeaveRequest.user_id.in_(intern_ids))
        return q.order_by(desc(LeaveRequest.created_at)).all()

    def create(self, leave: LeaveRequest) -> LeaveRequest:
        leave.organization_id = self.org_id
        self.db.add(leave)
        self.db.commit()
        self.db.refresh(leave)
        return leave

    def update(self, leave: LeaveRequest) -> LeaveRequest:
        self.db.commit()
        self.db.refresh(leave)
        return leave
