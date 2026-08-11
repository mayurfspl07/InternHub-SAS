import unittest
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Attendance, AttendanceStatus, User, UserRole
from routes.api.attendance import report


def make_request(
    user: User,
    method: str = "GET",
    query_string: bytes = b"",
) -> Request:
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
            "method": method,
            "scheme": "http",
            "path": "/api/attendance/report",
            "raw_path": b"/api/attendance/report",
            "query_string": query_string,
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class AttendanceReportTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.admin = self._user("Admin", "admin@report.test", UserRole.ADMIN)
        self.mentor = self._user("Mentor", "mentor@report.test", UserRole.MENTOR)
        self.other_mentor = self._user(
            "Other Mentor", "other-mentor@report.test", UserRole.MENTOR
        )
        self.intern = self._user(
            "Intern One",
            "intern1@report.test",
            UserRole.INTERN,
            mentor_id=self.mentor.id,
            department="Engineering",
        )
        self.other_intern = self._user(
            "Intern Two",
            "intern2@report.test",
            UserRole.INTERN,
            mentor_id=self.other_mentor.id,
            department="Design",
        )
        self.db.commit()

        # Records spanning well beyond any last-14-days window.
        self.old_date = date.today() - timedelta(days=60)
        self.mid_date = date.today() - timedelta(days=40)
        self.recent_date = date.today() - timedelta(days=2)
        self._attendance(self.intern, self.old_date, AttendanceStatus.PRESENT)
        self._attendance(self.intern, self.mid_date, AttendanceStatus.LATE)
        self._attendance(self.intern, self.recent_date, AttendanceStatus.HALF_DAY)
        self._attendance(self.other_intern, self.old_date, AttendanceStatus.ABSENT)
        self._attendance(self.other_intern, self.recent_date, AttendanceStatus.PRESENT)

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(
        self,
        name: str,
        email: str,
        role: str,
        *,
        mentor_id: int | None = None,
        department: str | None = None,
    ) -> User:
        user = User(
            name=name,
            email=email,
            role=role,
            is_active=True,
            mentor_id=mentor_id,
            department=department,
        )
        user.set_password("test-password-1")
        self.db.add(user)
        self.db.flush()
        return user

    def _attendance(self, user: User, day: date, status: str) -> Attendance:
        record = Attendance(
            user_id=user.id,
            date=day,
            check_in=datetime.combine(day, datetime.min.time().replace(hour=10)),
            check_out=datetime.combine(day, datetime.min.time().replace(hour=18)),
            status=status,
            hours_worked=7.0 if status != AttendanceStatus.ABSENT else 0.0,
            checkout_missed=False,
            checkout_source="manual",
        )
        self.db.add(record)
        self.db.commit()
        return record

    async def test_omitting_dates_returns_all_time_not_last_14_days(self):
        response = await report(
            make_request(self.admin, query_string=b"page=1&page_size=5000"),
            self.db,
        )

        self.assertEqual(response["filters"], {"intern_id": None, "start": None, "end": None})
        self.assertEqual(response["total"], 5)
        self.assertEqual(len(response["records"]), 5)
        dates = {row["date"] for row in response["records"]}
        self.assertIn(self.old_date.isoformat(), dates)
        self.assertIn(self.mid_date.isoformat(), dates)
        self.assertIn(self.recent_date.isoformat(), dates)
        self.assertTrue(any(item["year_month"] == self.old_date.strftime("%Y-%m") for item in response["monthly_summary"]))

    async def test_empty_start_end_treated_as_all_time(self):
        response = await report(
            make_request(
                self.admin,
                query_string=b"page=1&page_size=5000&start=&end=null",
            ),
            self.db,
        )
        self.assertIsNone(response["filters"]["start"])
        self.assertIsNone(response["filters"]["end"])
        self.assertEqual(response["total"], 5)

    async def test_start_end_filter_inclusively(self):
        start = self.mid_date.isoformat()
        end = self.recent_date.isoformat()
        response = await report(
            make_request(
                self.admin,
                query_string=f"start={start}&end={end}&page_size=5000".encode(),
            ),
            self.db,
        )
        dates = sorted(row["date"] for row in response["records"])
        self.assertEqual(
            dates,
            [
                self.mid_date.isoformat(),
                self.recent_date.isoformat(),
                self.recent_date.isoformat(),
            ],
        )
        self.assertEqual(response["filters"]["start"], start)
        self.assertEqual(response["filters"]["end"], end)
        self.assertNotIn(self.old_date.isoformat(), dates)
        self.assertEqual(response["total"], 3)

    async def test_mentor_scoping_enforced(self):
        response = await report(
            make_request(self.mentor, query_string=b"page_size=5000"),
            self.db,
        )
        user_ids = {row["user_id"] for row in response["records"]}
        intern_ids = {row["id"] for row in response["interns"]}
        self.assertEqual(user_ids, {self.intern.id})
        self.assertEqual(intern_ids, {self.intern.id})
        self.assertEqual(response["total"], 3)
        self.assertTrue(all(item["user_id"] == self.intern.id for item in response["monthly_summary"]))

        with self.assertRaises(HTTPException) as raised:
            await report(
                make_request(
                    self.mentor,
                    query_string=f"intern_id={self.other_intern.id}".encode(),
                ),
                self.db,
            )
        self.assertEqual(raised.exception.status_code, 403)

    async def test_intern_cannot_access_report(self):
        with self.assertRaises(HTTPException) as raised:
            await report(make_request(self.intern), self.db)
        self.assertEqual(raised.exception.status_code, 403)

    async def test_empty_attendance_returns_interns_with_empty_records(self):
        self.db.query(Attendance).delete()
        self.db.commit()

        response = await report(
            make_request(self.admin, query_string=b"page_size=5000"),
            self.db,
        )
        self.assertEqual(response["records"], [])
        self.assertEqual(response["monthly_summary"], [])
        self.assertEqual(response["total"], 0)
        self.assertEqual(response["total_pages"], 1)
        self.assertEqual(
            {row["id"] for row in response["interns"]},
            {self.intern.id, self.other_intern.id},
        )

    async def test_large_history_paginates_with_complete_monthly_summary(self):
        # Add enough older rows that a small page cannot hold everything.
        for offset in range(1, 21):
            day = self.old_date - timedelta(days=offset)
            if day.weekday() >= 5:
                continue
            self._attendance(self.intern, day, AttendanceStatus.PRESENT)

        response = await report(
            make_request(self.admin, query_string=b"page=1&page_size=5"),
            self.db,
        )
        self.assertEqual(len(response["records"]), 5)
        self.assertGreater(response["total"], 5)
        self.assertGreater(response["total_pages"], 1)
        # Month aggregates cover the full filtered set, not just the page.
        total_from_summary = sum(item["total_days"] for item in response["monthly_summary"])
        self.assertEqual(total_from_summary, response["total"])


if __name__ == "__main__":
    unittest.main()
