import unittest
from datetime import date, datetime

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base
from models import (
    Attendance,
    AttendanceStatus,
    LeaveRequest,
    LeaveStatus,
    Organization,
    OrganizationMembership,
    User,
    UserRole,
)
from utils import (
    get_leave_balance,
    reconcile_past_approved_leaves,
)


class TestLeaveAutoDeductionSync(unittest.TestCase):
    def _user(self, name: str, email: str, role: str, org_id: int, duration_months: int | None = None) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            internship_duration_months=duration_months,
            is_active=True,
            session_version=1,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)

        membership = OrganizationMembership(
            organization_id=org_id,
            user_id=user.id,
            role=role,
            is_active=True,
        )
        self.db.add(membership)
        self.db.commit()
        return user

    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()

        self.org = Organization(name="AutoCorp", slug="autocorp")
        self.db.add(self.org)
        self.db.commit()

        self.intern = self._user("Dev Intern", "dev@autocorp.com", UserRole.INTERN, self.org.id, duration_months=3)

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    def test_approved_leave_auto_deducted_when_no_attendance(self):
        # Intern has approved leave on Monday 2026-08-24
        leave_day = date(2026, 8, 24)
        lr = LeaveRequest(
            organization_id=self.org.id,
            user_id=self.intern.id,
            start_date=leave_day,
            end_date=leave_day,
            reason="Family function",
            status=LeaveStatus.APPROVED,
        )
        self.db.add(lr)
        self.db.commit()

        # Run reconciliation for target date 2026-08-25
        stats = reconcile_past_approved_leaves(self.db, target_date=date(2026, 8, 25))
        self.assertEqual(stats["reconciled_requests"], 1)
        self.assertEqual(stats["leave_days_settled"], 1)

        # Check attendance was created as ON_LEAVE
        att = self.db.query(Attendance).filter_by(user_id=self.intern.id, date=leave_day).first()
        self.assertIsNotNone(att)
        self.assertEqual(att.status, AttendanceStatus.ON_LEAVE)

        # Check leave balance counts it as deducted used
        balance = get_leave_balance(self.db, self.intern.id, self.org.id)
        self.assertEqual(balance["deducted_used"], 1)
        self.assertEqual(balance["attended_saved"], 0)

    def test_approved_leave_not_deducted_if_intern_actually_attended(self):
        # Intern had approved leave on Tuesday 2026-08-25
        leave_day = date(2026, 8, 25)
        lr = LeaveRequest(
            organization_id=self.org.id,
            user_id=self.intern.id,
            start_date=leave_day,
            end_date=leave_day,
            reason="Dentist appointment",
            status=LeaveStatus.APPROVED,
        )
        self.db.add(lr)

        # But intern actually checked in and worked 8 hours!
        att = Attendance(
            organization_id=self.org.id,
            user_id=self.intern.id,
            date=leave_day,
            check_in=datetime(2026, 8, 25, 9, 0),
            check_out=datetime(2026, 8, 25, 17, 0),
            hours_worked=8.0,
            status=AttendanceStatus.PRESENT,
        )
        self.db.add(att)
        self.db.commit()

        # Run reconciliation
        stats = reconcile_past_approved_leaves(self.db, target_date=date(2026, 8, 26))
        self.assertEqual(stats["attended_days"], 1)

        # Attendance record remains PRESENT
        att_db = self.db.query(Attendance).filter_by(user_id=self.intern.id, date=leave_day).first()
        self.assertEqual(att_db.status, AttendanceStatus.PRESENT)

        # In balance check, day was saved (not deducted)
        balance = get_leave_balance(self.db, self.intern.id, self.org.id)
        self.assertEqual(balance["attended_saved"], 1)
        self.assertEqual(balance["deducted_used"], 0)
