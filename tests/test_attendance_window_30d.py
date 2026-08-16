import unittest
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Attendance, AttendanceStatus, User, UserRole, Organization, OrganizationMembership, OrganizationType
from routes.api.dashboard import dashboard
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
            "headers": [(b"authorization", f"Bearer {token}".encode()), (b"x-organization-id", b"1")],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class AttendanceWindow30DayTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.org = Organization(id=1, slug="window-test-org", name="Window Test Org", type=OrganizationType.BUSINESS)
        self.db.add(self.org)
        self.db.flush()

        self.admin = self._user("Admin", "admin@window.test", UserRole.ADMIN)
        self.intern = self._user("Intern", "intern@window.test", UserRole.INTERN)
        self.other = self._user("Other", "other@window.test", UserRole.INTERN)

        self.db.add_all([
            OrganizationMembership(organization_id=self.org.id, user_id=self.admin.id, role=UserRole.ADMIN),
            OrganizationMembership(organization_id=self.org.id, user_id=self.intern.id, role=UserRole.INTERN),
            OrganizationMembership(organization_id=self.org.id, user_id=self.other.id, role=UserRole.INTERN),
        ])
        self.db.commit()

        self.today = date.today()
        self.in_window_edge = self.today - timedelta(days=29)
        self.outside_window = self.today - timedelta(days=30)
        self.mid_window = self.today - timedelta(days=20)

        self._attendance(self.intern, self.outside_window, AttendanceStatus.PRESENT, hours=8.0)
        self._attendance(self.intern, self.in_window_edge, AttendanceStatus.PRESENT, hours=7.0)
        self._attendance(self.intern, self.mid_window, AttendanceStatus.LATE, hours=6.5)
        self._attendance(self.intern, self.today, AttendanceStatus.HALF_DAY, hours=4.0)
        self._attendance(self.intern, self.today - timedelta(days=5), AttendanceStatus.ABSENT, hours=0.0)
        self._attendance(self.other, self.today, AttendanceStatus.PRESENT, hours=7.0)

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(self, name: str, email: str, role: str) -> User:
        user = User(name=name, email=email, role=role, is_active=True)
        user.set_password("test-password-1")
        self.db.add(user)
        self.db.flush()
        return user

    def _attendance(
        self,
        user: User,
        day: date,
        status: str,
        *,
        hours: float,
    ) -> Attendance:
        record = Attendance(
            user_id=user.id,
            date=day,
            check_in=datetime.combine(day, datetime.min.time().replace(hour=10)),
            check_out=datetime.combine(day, datetime.min.time().replace(hour=17)),
            status=status,
            hours_worked=hours,
            checkout_missed=False,
            checkout_source="manual",
        )
        self.db.add(record)
        self.db.commit()
        return record

    async def test_dashboard_chart_uses_last_30_days(self):
        response = await dashboard(make_request(self.intern, "/api/dashboard"), self.db)
        dates = [point["date"] for point in response["attendance_chart"]]

        self.assertIn(self.in_window_edge.isoformat(), dates)
        self.assertIn(self.mid_window.isoformat(), dates)
        self.assertIn(self.today.isoformat(), dates)
        self.assertNotIn(self.outside_window.isoformat(), dates)
        self.assertLessEqual(len(response["attendance_chart"]), 30)
        self.assertEqual(response["stats"]["days_logged"], 4)
        self.assertEqual(response["stats"]["total_hours"], 17.5)

    async def test_dashboard_empty_window_returns_empty_chart(self):
        self.db.query(Attendance).delete()
        self.db.commit()

        response = await dashboard(make_request(self.intern, "/api/dashboard"), self.db)
        self.assertEqual(response["attendance_chart"], [])
        self.assertEqual(response["stats"]["days_logged"], 0)
        self.assertEqual(response["stats"]["total_hours"], 0)

    async def test_profile_overview_stats_use_30_day_window(self):
        response = await user_overview(
            self.intern.id,
            make_request(self.admin, f"/api/users/{self.intern.id}/overview"),
            self.db,
        )
        stats = response["stats"]
        attendance_dates = {row["date"] for row in response["attendance"]}

        self.assertEqual(stats["present_30d"], 1)
        self.assertEqual(stats["late_30d"], 1)
        self.assertEqual(stats["half_day_30d"], 1)
        self.assertEqual(stats["absent_30d"], 1)
        # Backward-compatible aliases mirror the 30-day values.
        self.assertEqual(stats["present_14d"], stats["present_30d"])
        self.assertEqual(stats["late_14d"], stats["late_30d"])
        self.assertEqual(stats["half_day_14d"], stats["half_day_30d"])
        self.assertEqual(stats["absent_14d"], stats["absent_30d"])

        self.assertIn(self.in_window_edge.isoformat(), attendance_dates)
        # `attendance` is intentionally full history (used by the profile/export Excel sheet),
        # not windowed — only the *_30d stats above are limited to the trailing 30 days.
        self.assertIn(self.outside_window.isoformat(), attendance_dates)

    async def test_profile_empty_window_returns_zeros(self):
        self.db.query(Attendance).delete()
        self.db.commit()

        response = await user_overview(
            self.intern.id,
            make_request(self.admin, f"/api/users/{self.intern.id}/overview"),
            self.db,
        )
        stats = response["stats"]
        self.assertEqual(response["attendance"], [])
        self.assertEqual(stats["present_30d"], 0)
        self.assertEqual(stats["late_30d"], 0)
        self.assertEqual(stats["half_day_30d"], 0)
        self.assertEqual(stats["absent_30d"], 0)
        self.assertEqual(stats["present_14d"], 0)

    async def test_profile_authorization_unchanged(self):
        with self.assertRaises(HTTPException) as raised:
            await user_overview(
                self.intern.id,
                make_request(self.other, f"/api/users/{self.intern.id}/overview"),
                self.db,
            )
        self.assertEqual(raised.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
