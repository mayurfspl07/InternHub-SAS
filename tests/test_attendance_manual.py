import unittest
import json
from datetime import date, datetime, timedelta, time

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Attendance, AttendanceStatus, User, UserRole, AttendanceAuditLog, AuditLog
from routes.api.attendance import create_attendance_manual


def make_request(
    user: User | None,
    method: str = "POST",
    body: dict | None = None,
    query_string: bytes = b"",
) -> Request:
    sent = False
    body_bytes = json.dumps(body).encode("utf-8") if body is not None else b""

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body_bytes, "more_body": False}

    headers = []
    if user:
        token = generate_token(user.id, user.session_version)
        headers.append((b"authorization", f"Bearer {token}".encode()))

    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": "/api/attendance/manual",
            "raw_path": b"/api/attendance/manual",
            "query_string": query_string,
            "headers": headers,
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class AttendanceManualTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        # Users setup
        self.admin = self._user("Admin User", "admin@manual.test", UserRole.ADMIN)
        self.mentor = self._user("Mentor User", "mentor@manual.test", UserRole.MENTOR)
        self.other_mentor = self._user("Other Mentor", "othermentor@manual.test", UserRole.MENTOR)
        self.intern = self._user(
            "Intern One",
            "intern1@manual.test",
            UserRole.INTERN,
            mentor_id=self.mentor.id,
        )
        self.other_intern = self._user(
            "Intern Two",
            "intern2@manual.test",
            UserRole.INTERN,
            mentor_id=self.other_mentor.id,
        )
        self.db.commit()

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
    ) -> User:
        user = User(
            name=name,
            email=email,
            role=role,
            is_active=True,
            mentor_id=mentor_id,
        )
        user.set_password("password123")
        self.db.add(user)
        self.db.flush()
        return user

    async def test_unauthenticated_request_raises_401(self):
        req = make_request(None, body={
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "reason": "Forgot check-in",
        })
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 401)

    async def test_intern_request_raises_403(self):
        req = make_request(self.intern, body={
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "reason": "Self logging",
        })
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_mentor_request_for_unassigned_intern_raises_403(self):
        req = make_request(self.mentor, body={
            "user_id": self.other_intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "reason": "Logging for other intern",
        })
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_mentor_request_for_assigned_intern_succeeds(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "check_out": "18:00",
            "reason": "Mentor manual logging",
        }
        req = make_request(self.mentor, body=body)
        res = await create_attendance_manual(req, self.db)
        self.assertEqual(res["user_id"], self.intern.id)
        self.assertEqual(res["date"], "2026-07-27")
        self.assertEqual(res["check_in"], "10:00")
        self.assertEqual(res["check_out"], "18:00")

    async def test_admin_request_succeeds(self):
        body = {
            "user_id": self.other_intern.id,
            "date": "2026-07-27",
            "check_in": "09:55",
            "check_out": "17:55",
            "reason": "Admin logging",
        }
        req = make_request(self.admin, body=body)
        res = await create_attendance_manual(req, self.db)
        self.assertEqual(res["user_id"], self.other_intern.id)
        self.assertEqual(res["check_in"], "09:55")

    async def test_invalid_intern_role_raises_400(self):
        body = {
            "user_id": self.mentor.id,  # Target user is a mentor, not an intern
            "date": "2026-07-27",
            "check_in": "10:00",
            "reason": "Logging for mentor",
        }
        req = make_request(self.admin, body=body)
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 400)

    async def test_user_not_found_raises_404(self):
        body = {
            "user_id": 99999,
            "date": "2026-07-27",
            "check_in": "10:00",
            "reason": "Non-existent intern",
        }
        req = make_request(self.admin, body=body)
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 404)

    async def test_duplicate_record_raises_409(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "reason": "First log",
        }
        req = make_request(self.admin, body=body)
        await create_attendance_manual(req, self.db)

        # Duplicate call
        req2 = make_request(self.admin, body=body)
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req2, self.db)
        self.assertEqual(ctx.exception.status_code, 409)

    async def test_checkout_before_checkin_raises_422(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "check_out": "09:00",  # Check-out before check-in
            "reason": "Time travel",
        }
        req = make_request(self.admin, body=body)
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_invalid_time_format_raises_422(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "invalid_time",
            "reason": "Invalid time format",
        }
        req = make_request(self.admin, body=body)
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_status_override_by_admin_succeeds(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "check_out": "18:00",
            "status_override": "excused",
            "reason": "Excused by admin",
        }
        req = make_request(self.admin, body=body)
        res = await create_attendance_manual(req, self.db)
        self.assertEqual(res["status"], "excused")

    async def test_status_override_by_mentor_raises_403(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "10:00",
            "check_out": "18:00",
            "status_override": "excused",
            "reason": "Mentor override try",
        }
        req = make_request(self.mentor, body=body)
        with self.assertRaises(HTTPException) as ctx:
            await create_attendance_manual(req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_auditing_logs_are_written(self):
        body = {
            "user_id": self.intern.id,
            "date": "2026-07-27",
            "check_in": "09:30",
            "check_out": "18:30",
            "reason": "Auditing log verification",
        }
        req = make_request(self.admin, body=body)
        res = await create_attendance_manual(req, self.db)
        record_id = res["id"]

        # 1. Verify AttendanceAuditLog entries
        audit_logs = self.db.query(AttendanceAuditLog).filter_by(attendance_id=record_id).all()
        # Expecting three fields audited: check_in, check_out, status
        self.assertEqual(len(audit_logs), 3)
        fields = {log.field_name for log in audit_logs}
        self.assertIn("check_in", fields)
        self.assertIn("check_out", fields)
        self.assertIn("status", fields)

        # 2. Verify system-wide AuditLog entry
        system_audit = self.db.query(AuditLog).filter_by(
            action="attendance.create",
            affected_user_id=self.intern.id,
        ).first()
        self.assertIsNotNone(system_audit)
        self.assertEqual(system_audit.actor_name, self.admin.name)
        self.assertEqual(system_audit.verb, f"created attendance for {self.intern.name}")
        self.assertEqual(system_audit.target, "Auditing log verification")
