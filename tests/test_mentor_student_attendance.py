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
from routes.api.student_attendance import (
    export_admin_attendance,
    list_students,
    search_student_overview,
    student_attendance,
    today_attendance,
)


def make_request(
    user: User | None,
    path: str = "/api/admin/students",
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

    headers = []
    if user is not None:
        token = generate_token(user.id, user.session_version)
        headers.append((b"authorization", f"Bearer {token}".encode()))

    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": path,
            "raw_path": path.encode(),
            "query_string": query_string,
            "headers": headers,
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class MentorStudentAttendanceTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.admin = self._user("Admin User", "admin@test.local", UserRole.ADMIN)
        self.mentor_a = self._user("Mentor A", "mentor_a@test.local", UserRole.MENTOR)
        self.mentor_b = self._user("Mentor B", "mentor_b@test.local", UserRole.MENTOR)

        self.intern_a = self._user(
            "Intern Alpha",
            "intern_a@test.local",
            UserRole.INTERN,
            mentor_id=self.mentor_a.id,
            department="Engineering",
        )
        self.intern_b = self._user(
            "Intern Beta",
            "intern_b@test.local",
            UserRole.INTERN,
            mentor_id=self.mentor_b.id,
            department="Design",
        )
        self.db.commit()

        # Add attendance records
        today = date.today()
        yesterday = today - timedelta(days=1)
        self._attendance(self.intern_a, today, AttendanceStatus.PRESENT, check_in_h=9, check_out_h=17)
        self._attendance(self.intern_a, yesterday, AttendanceStatus.LATE, check_in_h=10, check_out_h=18)
        self._attendance(self.intern_b, today, AttendanceStatus.HALF_DAY, check_in_h=9, check_out_h=13)
        self._attendance(self.intern_b, yesterday, AttendanceStatus.PRESENT, check_in_h=9, check_out_h=17)

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
        user.set_password("Secret123!")
        self.db.add(user)
        self.db.flush()
        return user

    def _attendance(
        self,
        user: User,
        att_date: date,
        status: str,
        check_in_h: int = 9,
        check_out_h: int = 17,
    ) -> Attendance:
        check_in = datetime(att_date.year, att_date.month, att_date.day, check_in_h, 0)
        check_out = datetime(att_date.year, att_date.month, att_date.day, check_out_h, 0)
        hours = check_out_h - check_in_h
        record = Attendance(
            user_id=user.id,
            date=att_date,
            check_in=check_in,
            check_out=check_out,
            status=status,
            hours_worked=float(hours),
        )
        self.db.add(record)
        self.db.commit()
        return record

    # -----------------------------------------------------------------------
    # 1. GET /api/admin/students (List)
    # -----------------------------------------------------------------------
    async def test_list_students_mentor_scoped(self):
        req = make_request(self.mentor_a)
        res = await list_students(req, self.db)
        student_ids = [s["id"] for s in res["students"]]
        self.assertEqual(student_ids, [self.intern_a.id])
        self.assertEqual(res["total"], 1)

    async def test_list_students_admin_sees_all(self):
        req = make_request(self.admin)
        res = await list_students(req, self.db)
        student_ids = [s["id"] for s in res["students"]]
        self.assertIn(self.intern_a.id, student_ids)
        self.assertIn(self.intern_b.id, student_ids)
        self.assertEqual(res["total"], 2)

    async def test_list_students_intern_forbidden(self):
        req = make_request(self.intern_a)
        with self.assertRaises(HTTPException) as ctx:
            await list_students(req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    # -----------------------------------------------------------------------
    # 2. GET /api/admin/students/search
    # -----------------------------------------------------------------------
    async def test_search_student_overview_mentor_scoped(self):
        req = make_request(self.mentor_a, query_string=b"search=Intern")
        res = await search_student_overview(req, self.db)
        student_ids = [s["id"] for s in res["students"]]
        self.assertEqual(student_ids, [self.intern_a.id])

        req_b = make_request(self.mentor_b, query_string=b"search=Intern")
        res_b = await search_student_overview(req_b, self.db)
        student_ids_b = [s["id"] for s in res_b["students"]]
        self.assertEqual(student_ids_b, [self.intern_b.id])

    async def test_search_student_overview_admin_sees_all(self):
        req = make_request(self.admin, query_string=b"search=Intern")
        res = await search_student_overview(req, self.db)
        student_ids = [s["id"] for s in res["students"]]
        self.assertEqual(len(student_ids), 2)
        self.assertIn(self.intern_a.id, student_ids)
        self.assertIn(self.intern_b.id, student_ids)

    # -----------------------------------------------------------------------
    # 3. GET /api/admin/students/today
    # -----------------------------------------------------------------------
    async def test_today_attendance_mentor_scoped(self):
        req = make_request(self.mentor_a)
        res = await today_attendance(req, self.db)
        self.assertEqual(res["summary"]["total_interns"], 1)
        self.assertEqual(res["summary"]["present"], 1)
        self.assertEqual(len(res["students"]), 1)
        self.assertEqual(res["students"][0]["student"]["id"], self.intern_a.id)

        req_b = make_request(self.mentor_b)
        res_b = await today_attendance(req_b, self.db)
        self.assertEqual(res_b["summary"]["total_interns"], 1)
        self.assertEqual(res_b["summary"]["half_day"], 1)
        self.assertEqual(len(res_b["students"]), 1)
        self.assertEqual(res_b["students"][0]["student"]["id"], self.intern_b.id)

    async def test_today_attendance_admin_sees_all(self):
        req = make_request(self.admin)
        res = await today_attendance(req, self.db)
        self.assertEqual(res["summary"]["total_interns"], 2)
        self.assertEqual(len(res["students"]), 2)

    # -----------------------------------------------------------------------
    # 4. GET /api/admin/students/{user_id}/attendance
    # -----------------------------------------------------------------------
    async def test_student_attendance_mentor_own_intern(self):
        req = make_request(self.mentor_a)
        res = await student_attendance(self.intern_a.id, req, self.db)
        self.assertEqual(res["student"]["id"], self.intern_a.id)
        self.assertEqual(res["totals"]["total_days"], 2)

    async def test_student_attendance_mentor_other_intern_forbidden(self):
        req = make_request(self.mentor_a)
        with self.assertRaises(HTTPException) as ctx:
            await student_attendance(self.intern_b.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("own interns", ctx.exception.detail)

    async def test_student_attendance_admin_can_view_any(self):
        req = make_request(self.admin)
        res_a = await student_attendance(self.intern_a.id, req, self.db)
        self.assertEqual(res_a["student"]["id"], self.intern_a.id)
        res_b = await student_attendance(self.intern_b.id, req, self.db)
        self.assertEqual(res_b["student"]["id"], self.intern_b.id)

    # -----------------------------------------------------------------------
    # 5. GET /api/admin/students/export
    # -----------------------------------------------------------------------
    async def test_export_admin_attendance_mentor_scoped(self):
        req = make_request(self.mentor_a)
        res = await export_admin_attendance(req, self.db)
        csv_content = res.body.decode("utf-8")
        self.assertIn("Intern Alpha", csv_content)
        self.assertNotIn("Intern Beta", csv_content)

    async def test_export_admin_attendance_mentor_other_intern_id_forbidden(self):
        req = make_request(self.mentor_a, query_string=f"user_id={self.intern_b.id}".encode())
        with self.assertRaises(HTTPException) as ctx:
            await export_admin_attendance(req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("own interns", ctx.exception.detail)

    async def test_export_admin_attendance_admin_exports_all(self):
        req = make_request(self.admin)
        res = await export_admin_attendance(req, self.db)
        csv_content = res.body.decode("utf-8")
        self.assertIn("Intern Alpha", csv_content)
        self.assertIn("Intern Beta", csv_content)

    # -----------------------------------------------------------------------
    # 6. GET /api/attendance/my/export (Intern My Attendance Export)
    # -----------------------------------------------------------------------
    async def test_export_my_attendance_intern(self):
        from routes.api.attendance import export_my_attendance
        req = make_request(self.intern_a, path="/api/attendance/my/export")
        res = await export_my_attendance(req, self.db)
        csv_content = res.body.decode("utf-8")
        self.assertIn("Intern Alpha", csv_content)
        self.assertNotIn("Intern Beta", csv_content)
        self.assertIn("Content-Disposition", res.headers)
        self.assertIn("my_attendance_InternAlpha", res.headers["Content-Disposition"])


if __name__ == "__main__":
    unittest.main()
