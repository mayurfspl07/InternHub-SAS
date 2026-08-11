import json
import unittest
from datetime import date, datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Attendance, AttendanceStatus, LeaveRequest, LeaveStatus, LeaveType, User, UserRole
from routes.api.leave import review
from routes.api.users import user_overview
from utils import iter_weekdays


def make_request(user: User, method: str, payload: dict | None = None) -> Request:
    body = json.dumps(payload or {}).encode()
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    token = generate_token(user.id, user.session_version)
    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": "/",
            "raw_path": b"/",
            "query_string": b"",
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class LeaveAttendanceSyncTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.admin = self._user("Admin", "admin@leave-att.test", UserRole.ADMIN)
        self.mentor = self._user("Mentor", "mentor@leave-att.test", UserRole.MENTOR)
        self.intern = self._user("Intern", "intern@leave-att.test", UserRole.INTERN)
        self.intern.mentor_id = self.mentor.id
        self.db.commit()

        self.leave_start, self.leave_end = self._recent_weekday_pair()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(self, name: str, email: str, role: str) -> User:
        user = User(name=name, email=email, role=role, is_active=True, session_version=1)
        user.set_password("test-password-1")
        self.db.add(user)
        self.db.flush()
        return user

    def _recent_weekday_pair(self) -> tuple[date, date]:
        day = date.today() - timedelta(days=10)
        while day.weekday() != 0:
            day -= timedelta(days=1)
        return day, day + timedelta(days=1)

    def _pending_leave(self) -> LeaveRequest:
        lr = LeaveRequest(
            user_id=self.intern.id,
            start_date=self.leave_start,
            end_date=self.leave_end,
            reason="Family trip",
            leave_type=LeaveType.CASUAL,
            status=LeaveStatus.PENDING,
        )
        self.db.add(lr)
        self.db.commit()
        return lr

    async def test_approve_leave_creates_on_leave_attendance_rows(self):
        lr = self._pending_leave()

        await review(
            lr.id,
            make_request(self.admin, "POST", {"decision": LeaveStatus.APPROVED}),
            self.db,
        )

        expected_days = list(iter_weekdays(self.leave_start, self.leave_end))
        records = (
            self.db.query(Attendance)
            .filter_by(user_id=self.intern.id)
            .order_by(Attendance.date)
            .all()
        )
        self.assertEqual(len(records), len(expected_days))
        for record, day in zip(records, expected_days):
            self.assertEqual(record.date, day)
            self.assertEqual(record.status, AttendanceStatus.ON_LEAVE)
            self.assertEqual(record.hours_worked, 0.0)

    async def test_approve_leave_updates_existing_attendance(self):
        lr = self._pending_leave()
        existing = Attendance(
            user_id=self.intern.id,
            date=self.leave_start,
            check_in=datetime.combine(self.leave_start, datetime.min.time().replace(hour=10)),
            check_out=datetime.combine(self.leave_start, datetime.min.time().replace(hour=17)),
            status=AttendanceStatus.ABSENT,
            hours_worked=0.0,
            checkout_missed=False,
        )
        self.db.add(existing)
        self.db.commit()

        await review(
            lr.id,
            make_request(self.admin, "POST", {"decision": LeaveStatus.APPROVED}),
            self.db,
        )

        self.db.refresh(existing)
        self.assertEqual(existing.status, AttendanceStatus.ON_LEAVE)
        self.assertIsNone(existing.check_out)
        self.assertEqual(existing.hours_worked, 0.0)

    async def test_reject_leave_does_not_create_attendance(self):
        lr = self._pending_leave()

        await review(
            lr.id,
            make_request(self.admin, "POST", {"decision": LeaveStatus.REJECTED}),
            self.db,
        )

        count = self.db.query(Attendance).filter_by(user_id=self.intern.id).count()
        self.assertEqual(count, 0)

    async def test_overview_includes_on_leave_30d(self):
        lr = self._pending_leave()
        await review(
            lr.id,
            make_request(self.admin, "POST", {"decision": LeaveStatus.APPROVED}),
            self.db,
        )

        response = await user_overview(
            self.intern.id,
            make_request(self.admin, f"/api/users/{self.intern.id}/overview"),
            self.db,
        )
        expected = len(list(iter_weekdays(self.leave_start, self.leave_end)))
        self.assertEqual(response["stats"]["on_leave_30d"], expected)
        self.assertEqual(response["stats"]["on_leave_14d"], expected)


if __name__ == "__main__":
    unittest.main()
