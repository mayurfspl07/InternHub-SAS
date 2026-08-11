import unittest
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from config import Config
from database import Base
from dependencies import generate_token
from models import LeaveRequest, LeaveStatus, LeaveType, User, UserRole
from routes.api.users import user_overview


def make_request(user: User, path: str = "/") -> Request:
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": b"", "more_body": False}

    token = generate_token(user.id, user.session_version)
    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": "GET",
            "scheme": "http",
            "path": path,
            "raw_path": path.encode(),
            "query_string": b"",
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class ProfileLeaveOverviewTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.admin = self._user("Admin", "admin@leave.test", UserRole.ADMIN)
        self.mentor = self._user("Mentor", "mentor@leave.test", UserRole.MENTOR)
        self.intern = self._user("Intern", "intern@leave.test", UserRole.INTERN)
        self.intern.mentor_id = None
        self.db.flush()
        self.intern.mentor_id = self.mentor.id
        self.db.commit()

        self.approved = self._leave(
            self.intern,
            date(2026, 8, 3),
            date(2026, 8, 5),
            LeaveStatus.APPROVED,
            reviewed_by=self.mentor,
        )
        self.rejected = self._leave(
            self.intern,
            date(2026, 8, 10),
            date(2026, 8, 10),
            LeaveStatus.REJECTED,
            reviewed_by=self.admin,
        )
        self.pending = self._leave(
            self.intern,
            date(2026, 8, 17),
            date(2026, 8, 18),
            LeaveStatus.PENDING,
        )

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(self, name: str, email: str, role: str) -> User:
        user = User(name=name, email=email, role=role, is_active=True, session_version=1)
        user.set_password("test-password-1")
        self.db.add(user)
        self.db.flush()
        return user

    def _leave(
        self,
        user: User,
        start: date,
        end: date,
        status: str,
        *,
        reviewed_by: User | None = None,
    ) -> LeaveRequest:
        lr = LeaveRequest(
            user_id=user.id,
            start_date=start,
            end_date=end,
            reason="Family event",
            leave_type=LeaveType.CASUAL,
            status=status,
            reviewed_by=reviewed_by.id if reviewed_by else None,
            reviewed_at=datetime.now(timezone.utc).replace(tzinfo=None) if reviewed_by else None,
        )
        self.db.add(lr)
        self.db.commit()
        return lr

    async def test_admin_sees_leave_requests_summary_and_balance(self):
        response = await user_overview(
            self.intern.id,
            make_request(self.admin, f"/api/users/{self.intern.id}/overview"),
            self.db,
        )

        self.assertEqual(len(response["leave_requests"]), 3)
        self.assertEqual(response["leave_summary"]["total"], 3)
        self.assertEqual(response["leave_summary"]["approved"], 1)
        self.assertEqual(response["leave_summary"]["rejected"], 1)
        self.assertEqual(response["leave_summary"]["pending"], 1)
        self.assertEqual(response["leave_summary"]["days_taken"], self.approved.days)

        self.assertEqual(response["leave_balance"]["quota"], Config.LEAVE_QUOTA_DAYS)
        self.assertEqual(response["leave_balance"]["used"], self.approved.days)
        self.assertEqual(
            response["leave_balance"]["remaining"],
            Config.LEAVE_QUOTA_DAYS - self.approved.days,
        )

        self.assertEqual(response["stats"]["leave_total"], 3)
        self.assertEqual(response["stats"]["leave_approved"], 1)
        self.assertEqual(response["stats"]["leave_rejected"], 1)
        self.assertEqual(response["stats"]["leave_pending"], 1)
        self.assertEqual(response["stats"]["leave_days_taken"], self.approved.days)

        by_id = {item["id"]: item for item in response["leave_requests"]}
        approved_row = by_id[self.approved.id]
        self.assertEqual(approved_row["status"], LeaveStatus.APPROVED)
        self.assertEqual(approved_row["reviewer_name"], self.mentor.name)
        self.assertTrue(approved_row["created_at"].endswith("Z"))

    async def test_intern_can_view_own_leave_data(self):
        response = await user_overview(
            self.intern.id,
            make_request(self.intern, f"/api/users/{self.intern.id}/overview"),
            self.db,
        )
        self.assertEqual(response["leave_summary"]["pending"], 1)
        self.assertEqual(len(response["leave_requests"]), 3)

    async def test_mentor_can_view_intern_leave_data(self):
        response = await user_overview(
            self.intern.id,
            make_request(self.mentor, f"/api/users/{self.intern.id}/overview"),
            self.db,
        )
        self.assertEqual(response["leave_summary"]["approved"], 1)
        self.assertEqual(len(response["leave_requests"]), 3)

    async def test_mentor_profile_does_not_include_leave_fields(self):
        response = await user_overview(
            self.mentor.id,
            make_request(self.admin, f"/api/users/{self.mentor.id}/overview"),
            self.db,
        )
        self.assertNotIn("leave_requests", response)
        self.assertNotIn("leave_summary", response)
        self.assertNotIn("leave_balance", response)


if __name__ == "__main__":
    unittest.main()
