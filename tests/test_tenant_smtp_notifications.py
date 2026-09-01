"""Test suite for tenant-wise SMTP configuration and email notifications."""
import unittest
from datetime import date
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from config import Config
from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Assignment,
    AssignmentSubmission,
    EmailLog,
    LeaveRequest,
    LeaveStatus,
    Organization,
    OrganizationMembership,
    Task,
    TenantSmtpConfig,
    User,
    UserRole,
    _utcnow,
)
from email_service import (
    send_assignment_created_email,
    send_assignment_graded_email,
    send_assignment_submitted_email,
    send_leave_request_email,
    send_leave_status_email,
    send_task_assigned_email,
    send_test_email,
    send_welcome_email,
)


class TestTenantSmtpAndNotifications(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)
        self.db = self.Session()

        # Organization
        self.org = Organization(name="Acme Tech", slug="acme")
        self.db.add(self.org)
        self.db.commit()
        self.db.refresh(self.org)

        # Admin
        self.admin = User(
            name="Admin User",
            email="admin@acme.com",
            role=UserRole.ADMIN,
            password_hash="test-hash",
            is_active=True,
        )
        self.db.add(self.admin)
        self.db.commit()
        self.db.refresh(self.admin)
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.admin.id, role=UserRole.ADMIN, is_active=True))

        # Mentor
        self.mentor = User(
            name="Mentor John",
            email="john@acme.com",
            role=UserRole.MENTOR,
            password_hash="test-hash",
            is_active=True,
        )
        self.db.add(self.mentor)
        self.db.commit()
        self.db.refresh(self.mentor)
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.mentor.id, role=UserRole.MENTOR, is_active=True))

        # Intern
        self.intern = User(
            name="Intern Alice",
            email="alice@acme.com",
            role=UserRole.INTERN,
            password_hash="test-hash",
            mentor_id=self.mentor.id,
            is_active=True,
        )
        self.db.add(self.intern)
        self.db.commit()
        self.db.refresh(self.intern)
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.intern.id, role=UserRole.INTERN, is_active=True))
        self.db.commit()

        app.dependency_overrides[get_db] = lambda: self.db
        self.client = TestClient(app)
        self.admin_headers = {
            "Authorization": f"Bearer {generate_token(self.admin.id, self.admin.session_version)}",
            "X-Organization-Id": str(self.org.id),
        }
        self.intern_headers = {
            "Authorization": f"Bearer {generate_token(self.intern.id, self.intern.session_version)}",
            "X-Organization-Id": str(self.org.id),
        }

    def tearDown(self):
        self.db.close()
        app.dependency_overrides.clear()

    def test_get_smtp_config_defaults(self):
        resp = self.client.get("/api/org/smtp", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertFalse(data["is_enabled"])
        self.assertEqual(data["port"], 587)
        self.assertTrue(data["notify_welcome"])

    def test_update_smtp_config_and_mask_password(self):
        payload = {
            "is_enabled": True,
            "host": "smtp.sendgrid.net",
            "port": 587,
            "username": "apikey",
            "password": "SG.secret_api_key_12345",
            "sender_email": "alerts@acme.com",
            "sender_name": "Acme Notifications",
            "encryption": "tls",
            "notify_welcome": True,
            "notify_leave_request": False,
        }
        resp = self.client.put("/api/org/smtp", json=payload, headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()["config"]
        self.assertTrue(data["is_enabled"])
        self.assertEqual(data["host"], "smtp.sendgrid.net")
        self.assertEqual(data["sender_email"], "alerts@acme.com")
        self.assertEqual(data["password"], "••••••••")
        self.assertTrue(data["has_password"])
        self.assertFalse(data["notify_leave_request"])

        # Check DB raw password
        cfg = self.db.query(TenantSmtpConfig).filter_by(organization_id=self.org.id).first()
        self.assertIsNotNone(cfg)
        self.assertEqual(cfg.password, "SG.secret_api_key_12345")

    def test_intern_forbidden_to_access_or_update_smtp(self):
        resp_get = self.client.get("/api/org/smtp", headers=self.intern_headers)
        self.assertEqual(resp_get.status_code, 403)

        resp_put = self.client.put("/api/org/smtp", json={"host": "bad.com"}, headers=self.intern_headers)
        self.assertEqual(resp_put.status_code, 403)

    @patch("smtplib.SMTP")
    def test_smtp_test_connection_endpoint(self, mock_smtp):
        mock_server = MagicMock()
        mock_smtp.return_value = mock_server

        payload = {
            "target_email": "verify@acme.com",
            "host": "smtp.testserver.com",
            "port": 587,
            "username": "tester",
            "password": "pwd",
            "sender_email": "no-reply@acme.com",
            "sender_name": "Acme Test",
        }
        resp = self.client.post("/api/org/smtp/test", json=payload, headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertTrue(data["success"])

        # Verify EmailLog was recorded
        log = self.db.query(EmailLog).filter_by(organization_id=self.org.id, email_type="test").first()
        self.assertIsNotNone(log)
        self.assertEqual(log.recipient_email, "verify@acme.com")

    def test_email_logs_endpoint(self):
        log1 = EmailLog(organization_id=self.org.id, recipient_email="user1@acme.com", subject="Sub 1", email_type="welcome", status="sent")
        log2 = EmailLog(organization_id=self.org.id, recipient_email="user2@acme.com", subject="Sub 2", email_type="leave_request", status="sent")
        self.db.add_all([log1, log2])
        self.db.commit()

        resp = self.client.get("/api/org/smtp/logs", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["total"], 2)
        self.assertEqual(len(data["logs"]), 2)

    @patch("smtplib.SMTP")
    def test_leave_request_and_decision_email_triggers(self, mock_smtp):
        mock_smtp.return_value = MagicMock()
        cfg = TenantSmtpConfig(organization_id=self.org.id, is_enabled=True, host="smtp.fake.org", notify_leave_request=True, notify_leave_decision=True)
        self.db.add(cfg)
        self.db.commit()

        lr = LeaveRequest(
            user_id=self.intern.id,
            start_date=date(2026, 9, 10),
            end_date=date(2026, 9, 12),
            leave_type="sick",
            reason="Flu",
            status=LeaveStatus.PENDING,
        )
        self.db.add(lr)
        self.db.commit()

        send_leave_request_email(self.db, self.org.id, lr, self.intern, [self.mentor, self.admin])
        send_leave_status_email(self.db, self.org.id, lr, self.intern, self.mentor)

        # Give threads a tiny fraction to write logs
        import time
        time.sleep(0.2)

        logs = self.db.query(EmailLog).filter_by(organization_id=self.org.id).all()
        types = [l.email_type for l in logs]
        self.assertIn("leave_request", types)
        self.assertIn("leave_decision", types)

    @patch("smtplib.SMTP")
    def test_assignment_lifecycle_email_triggers(self, mock_smtp):
        mock_smtp.return_value = MagicMock()
        cfg = TenantSmtpConfig(organization_id=self.org.id, is_enabled=True, host="smtp.fake.org")
        self.db.add(cfg)
        self.db.commit()

        assignment = Assignment(
            organization_id=self.org.id,
            title="FastAPI Microservice",
            description="Build endpoints with tests",
            created_by_id=self.mentor.id,
            due_date=date(2026, 9, 20),
            max_score=100,
        )
        self.db.add(assignment)
        self.db.commit()

        submission = AssignmentSubmission(
            assignment_id=assignment.id,
            user_id=self.intern.id,
            github_url="https://github.com/intern/solution",
            submission_text="Finished all CRUD endpoints",
            score=95.0,
            feedback="Great code structure",
        )
        self.db.add(submission)
        self.db.commit()

        send_assignment_created_email(self.db, self.org.id, assignment, [self.intern])
        send_assignment_submitted_email(self.db, self.org.id, assignment, submission, self.intern, [self.mentor])
        send_assignment_graded_email(self.db, self.org.id, assignment, submission, self.intern, self.mentor)

        import time
        time.sleep(0.2)

        logs = self.db.query(EmailLog).filter_by(organization_id=self.org.id).all()
        types = [l.email_type for l in logs]
        self.assertIn("assignment_new", types)
        self.assertIn("assignment_submit", types)
        self.assertIn("assignment_grade", types)
