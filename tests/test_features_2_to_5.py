import io
import json
import unittest
from datetime import date, datetime, timezone

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.datastructures import Headers, UploadFile
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import (
    Attendance,
    LeaveRequest,
    LeaveStatus,
    Organization,
    OrganizationMembership,
    Project,
    ProjectAssignment,
    Task,
    TaskAttachment,
    User,
    UserRole,
)
from routes.api.attendance import history as list_attendance
from routes.api.leave import apply as apply_leave, get_leave_attachment, my_requests
from routes.api.profile import get_profile
from routes.api.projects import (
    create_task,
    delete_task_attachment,
    download_task_attachment,
    list_task_attachments,
    post_task_comment,
    upload_task_attachment,
)
from utils import fmt_time_ist, get_internship_summary, to_ist


def make_request(
    user: User,
    method: str = "GET",
    payload: dict | None = None,
    query_params: dict | None = None,
    org_id: int | None = None,
) -> Request:
    body = json.dumps(payload or {}).encode() if payload is not None else b""
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    token = generate_token(user.id, user.session_version)
    headers = [
        (b"authorization", f"Bearer {token}".encode()),
        (b"content-type", b"application/json"),
    ]
    if org_id:
        headers.append((b"x-organization-id", str(org_id).encode()))

    query_str = ""
    if query_params:
        query_str = "&".join(f"{k}={v}" for k, v in query_params.items())

    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": "/",
        "raw_path": b"/",
        "query_string": query_str.encode(),
        "headers": headers,
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }
    return Request(scope, receive)


class Features2To5Tests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()

        # Organization
        self.org = Organization(name="Innovate Tech", slug="innovate-tech")
        self.db.add(self.org)
        self.db.commit()

        # Users
        self.admin = self._user("Admin User", "admin@test.local", UserRole.ADMIN)
        self.mentor = self._user("Mentor User", "mentor@test.local", UserRole.MENTOR)
        self.intern = self._user(
            "Intern User",
            "intern@test.local",
            UserRole.INTERN,
            joining_date=date(2026, 6, 1),
            internship_end_date=date(2026, 8, 31),
            internship_duration_months=3,
        )

        # Project
        self.project = Project(
            organization_id=self.org.id,
            name="Platform Upgrade",
            mentor_id=self.mentor.id,
        )
        self.db.add(self.project)
        self.db.commit()
        self.db.add(ProjectAssignment(project_id=self.project.id, user_id=self.intern.id))
        self.db.commit()

        # Task
        self.task = Task(
            project_id=self.project.id,
            organization_id=self.org.id,
            created_by_id=self.mentor.id,
            assigned_to=self.intern.id,
            title="Implement Core API",
            status="in_progress",
        )
        self.db.add(self.task)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(
        self,
        name: str,
        email: str,
        role: str,
        joining_date: date | None = None,
        internship_end_date: date | None = None,
        internship_duration_months: int | None = None,
    ) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            is_active=True,
            session_version=1,
            joining_date=joining_date,
            internship_end_date=internship_end_date,
            internship_duration_months=internship_duration_months,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)

        membership = OrganizationMembership(
            organization_id=self.org.id,
            user_id=user.id,
            role=role,
            joining_date=joining_date,
            is_active=True,
        )
        self.db.add(membership)
        self.db.commit()
        return user

    async def test_checkin_checkout_time_in_ist(self):
        """Verify check-in/out timestamps are converted to IST (Asia/Kolkata +05:30)."""
        # UTC 04:30:00 corresponds to 10:00 AM IST
        utc_dt = datetime(2026, 8, 31, 4, 30, 0, tzinfo=timezone.utc)
        ist_dt = to_ist(utc_dt)
        self.assertEqual(ist_dt.hour, 10)
        self.assertEqual(ist_dt.minute, 0)
        self.assertEqual(fmt_time_ist(utc_dt), "10:00 AM")

        # Create attendance record
        att = Attendance(
            organization_id=self.org.id,
            user_id=self.intern.id,
            date=date(2026, 8, 31),
            check_in=datetime(2026, 8, 31, 10, 0, 0),
            check_out=datetime(2026, 8, 31, 19, 0, 0),
            status="present",
        )
        self.db.add(att)
        self.db.commit()

        req = make_request(self.admin, query_params={"month": "2026-08"})
        res = await list_attendance(request=req, db=self.db)
        rec = next((r for r in res["records"] if r["user_id"] == self.intern.id), None)
        self.assertIsNotNone(rec)
        self.assertEqual(rec["check_in"], "10:00")
        self.assertEqual(rec["check_out"], "19:00")

    async def test_task_attachment_upload_and_download(self):
        """Upload file against a task and verify download and list endpoints."""
        dummy_content = b"PDF Document Content for Task"
        file_obj = UploadFile(
            file=io.BytesIO(dummy_content),
            filename="sprint_report.pdf",
            headers=Headers({"content-type": "application/pdf"}),
        )

        req_upload = make_request(self.intern, method="POST")
        attachment = await upload_task_attachment(
            task_id=self.task.id,
            request=req_upload,
            db=self.db,
            file=file_obj,
            description="Sprint final report",
        )
        self.assertEqual(attachment["file_name"], "sprint_report.pdf")
        self.assertEqual(attachment["task_id"], self.task.id)
        attachment_id = attachment["id"]

        # List task attachments
        req_list = make_request(self.mentor, method="GET")
        att_list = await list_task_attachments(
            task_id=self.task.id, request=req_list, db=self.db
        )
        self.assertEqual(len(att_list["attachments"]), 1)
        self.assertEqual(att_list["attachments"][0]["id"], attachment_id)

        # Download attachment
        req_dl = make_request(self.mentor, method="GET")
        dl_response = await download_task_attachment(
            attachment_id=attachment_id, request=req_dl, db=self.db
        )
        self.assertEqual(dl_response.headers.get("content-disposition"), 'attachment; filename="sprint_report.pdf"')

        # Delete attachment
        req_del = make_request(self.intern, method="DELETE")
        del_res = await delete_task_attachment(
            attachment_id=attachment_id, request=req_del, db=self.db
        )
        self.assertTrue(del_res["success"])

    async def test_task_comment_with_attachment(self):
        """Adding a comment with an attachment links the attachment to the comment and task."""
        file_obj = UploadFile(
            file=io.BytesIO(b"Screenshot of bug"),
            filename="error_screenshot.png",
            headers=Headers({"content-type": "image/png"}),
        )

        req = make_request(self.intern, method="POST")
        comment_res = await post_task_comment(
            task_id=self.task.id,
            request=req,
            db=self.db,
            body="Attached screenshot for mentor review",
            file=file_obj,
        )
        self.assertIsNotNone(comment_res.get("attachment"))
        self.assertEqual(comment_res["attachment"]["file_name"], "error_screenshot.png")

    async def test_internship_period_visibility(self):
        """Profile and leave responses return complete internship period and leave quota breakdown."""
        # Add 1 approved leave of 2 days
        leave = LeaveRequest(
            organization_id=self.org.id,
            user_id=self.intern.id,
            start_date=date(2026, 7, 6),
            end_date=date(2026, 7, 7),
            reason="Medical",
            leave_type="sick",
            status=LeaveStatus.APPROVED,
            reviewed_by=self.mentor.id,
        )
        self.db.add(leave)
        self.db.commit()

        # Check get_profile
        req_prof = make_request(self.intern)
        prof = await get_profile(request=req_prof, db=self.db)
        summary = prof.get("internship_summary")
        self.assertIsNotNone(summary)
        self.assertEqual(summary["start_date"], "2026-06-01")
        self.assertEqual(summary["end_date"], "2026-08-31")
        self.assertEqual(summary["duration_months"], 3)
        self.assertEqual(summary["duration_label"], "3 Months")
        self.assertEqual(summary["approved_leaves"], 2)
        self.assertEqual(summary["remaining_leave_balance"], 13)

        # Check /api/leave/mine
        req_leave = make_request(self.intern)
        leave_mine = await my_requests(request=req_leave, db=self.db)
        self.assertIn("internship_summary", leave_mine)
        self.assertEqual(leave_mine["internship_summary"]["approved_leaves"], 2)

    async def test_leave_application_with_and_without_attachment(self):
        """Leave application supports optional attachment upload and download."""
        # 1. Apply WITH attachment
        file_obj = UploadFile(
            file=io.BytesIO(b"Medical Certificate Document"),
            filename="medical_cert.pdf",
            headers=Headers({"content-type": "application/pdf"}),
        )

        req_apply_with = make_request(self.intern, method="POST")
        leave_res = await apply_leave(
            request=req_apply_with,
            db=self.db,
            start_date="2026-09-10",
            end_date="2026-09-11",
            reason="Doctor advised rest",
            leave_type="sick",
            attachment=file_obj,
        )
        self.assertEqual(leave_res["attachment_name"], "medical_cert.pdf")
        leave_id = leave_res["id"]

        # Download attachment
        req_dl = make_request(self.mentor)
        dl_resp = await get_leave_attachment(
            leave_id=leave_id, request=req_dl, db=self.db
        )
        self.assertEqual(dl_resp.headers.get("content-disposition"), 'attachment; filename="medical_cert.pdf"')

        # 2. Apply WITHOUT attachment (optional)
        req_apply_without = make_request(self.intern, method="POST")
        leave_res2 = await apply_leave(
            request=req_apply_without,
            db=self.db,
            start_date="2026-09-18",
            end_date="2026-09-18",
            reason="Family event",
            leave_type="casual",
            attachment=None,
        )
        self.assertIsNone(leave_res2["attachment_name"])
