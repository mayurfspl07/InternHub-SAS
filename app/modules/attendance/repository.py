"""Data access repository for Attendance entities."""
from datetime import date, datetime
from sqlalchemy import desc, func
from sqlalchemy.orm import Session, joinedload

from models import Attendance, AttendanceAuditLog


class AttendanceRepository:
    def __init__(self, db: Session, org_id: int = 1):
        self.db = db
        self.org_id = org_id

    def get_by_id(self, attendance_id: int) -> Attendance | None:
        return (
            self.db.query(Attendance)
            .options(
                joinedload(Attendance.user),
                joinedload(Attendance.audit_entries),
            )
            .filter(
                Attendance.id == attendance_id,
                Attendance.organization_id == self.org_id,
            )
            .first()
        )

    def get_for_user_date(self, user_id: int, target_date: date) -> Attendance | None:
        return (
            self.db.query(Attendance)
            .filter(
                Attendance.user_id == user_id,
                Attendance.date == target_date,
                Attendance.organization_id == self.org_id,
            )
            .first()
        )

    def list_for_user(self, user_id: int, start_date: date | None = None, end_date: date | None = None) -> list[Attendance]:
        q = (
            self.db.query(Attendance)
            .filter(
                Attendance.user_id == user_id,
                Attendance.organization_id == self.org_id,
            )
        )
        if start_date:
            q = q.filter(Attendance.date >= start_date)
        if end_date:
            q = q.filter(Attendance.date <= end_date)
        return q.order_by(desc(Attendance.date)).all()

    def list_org_attendance(self, target_date: date) -> list[Attendance]:
        return (
            self.db.query(Attendance)
            .options(joinedload(Attendance.user))
            .filter(
                Attendance.organization_id == self.org_id,
                Attendance.date == target_date,
            )
            .order_by(Attendance.check_in.asc())
            .all()
        )

    def create(self, attendance: Attendance) -> Attendance:
        attendance.organization_id = self.org_id
        self.db.add(attendance)
        self.db.commit()
        self.db.refresh(attendance)
        return attendance

    def update(self, attendance: Attendance) -> Attendance:
        self.db.commit()
        self.db.refresh(attendance)
        return attendance
