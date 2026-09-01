"""Test suite for pagination across masters, admin, and assignment endpoints."""
import unittest
from datetime import date

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Assignment,
    AssignmentSubmission,
    InternshipDurationMaster,
    Organization,
    OrganizationMembership,
    ProjectStatusBucket,
    TaskStatusBucket,
    User,
    UserRole,
)


class TestPaginationEnhancements(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)
        self.db = self.Session()

        self.org = Organization(name="Acme Corp", slug="acme")
        self.db.add(self.org)
        self.db.commit()
        self.db.refresh(self.org)

        self.admin = User(name="Admin", email="admin@acme.com", role=UserRole.ADMIN, password_hash="test", is_active=True)
        self.mentor = User(name="Mentor", email="mentor@acme.com", role=UserRole.MENTOR, password_hash="test", is_active=True)
        self.intern1 = User(name="Intern 1", email="i1@acme.com", role=UserRole.INTERN, password_hash="test", is_active=True)
        self.intern2 = User(name="Intern 2", email="i2@acme.com", role=UserRole.INTERN, password_hash="test", is_active=True)
        self.db.add_all([self.admin, self.mentor, self.intern1, self.intern2])
        self.db.commit()

        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.admin.id, role=UserRole.ADMIN, is_active=True))
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.mentor.id, role=UserRole.MENTOR, is_active=True))
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.intern1.id, role=UserRole.INTERN, is_active=True))
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.intern2.id, role=UserRole.INTERN, is_active=True))
        self.db.commit()

        app.dependency_overrides[get_db] = lambda: self.db
        self.client = TestClient(app)
        self.admin_headers = {
            "Authorization": f"Bearer {generate_token(self.admin.id, self.admin.session_version)}",
            "X-Organization-Id": str(self.org.id),
        }
        self.mentor_headers = {
            "Authorization": f"Bearer {generate_token(self.mentor.id, self.mentor.session_version)}",
            "X-Organization-Id": str(self.org.id),
        }

    def tearDown(self):
        self.db.close()
        app.dependency_overrides.clear()

    def test_project_statuses_pagination_and_filtering(self):
        # Seed 5 project status buckets
        for i in range(1, 6):
            b = ProjectStatusBucket(
                organization_id=self.org.id,
                name=f"Status {i}",
                slug=f"status-{i}",
                order_index=i,
            )
            self.db.add(b)
        self.db.commit()

        # Page 1, page_size 2
        resp = self.client.get("/api/admin/project-statuses?page=1&page_size=2", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["page"], 1)
        self.assertEqual(data["page_size"], 2)
        self.assertGreaterEqual(data["total"], 5)
        self.assertEqual(len(data["statuses"]), 2)
        self.assertEqual(len(data["items"]), 2)

        # Search filter
        resp_search = self.client.get("/api/admin/project-statuses?search=Status 3", headers=self.admin_headers)
        self.assertEqual(resp_search.status_code, 200)
        search_data = resp_search.json()
        self.assertEqual(search_data["total"], 1)
        self.assertEqual(search_data["statuses"][0]["slug"], "status-3")

    def test_task_statuses_pagination(self):
        # Seed task statuses
        for i in range(1, 6):
            b = TaskStatusBucket(
                organization_id=self.org.id,
                name=f"Task Status {i}",
                slug=f"task-status-{i}",
                status_category="in_progress",
                order_index=i,
            )
            self.db.add(b)
        self.db.commit()

        resp = self.client.get("/api/admin/task-statuses?page=2&page_size=2", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["page"], 2)
        self.assertEqual(data["page_size"], 2)
        self.assertGreaterEqual(data["total"], 5)
        self.assertEqual(len(data["statuses"]), 2)

    def test_internship_durations_pagination(self):
        for i in [1, 2, 3, 6, 12]:
            d = InternshipDurationMaster(
                organization_id=self.org.id,
                duration_months=i,
                title=f"{i} Month Plan",
                leaves=i * 2,
                is_active=True,
            )
            self.db.add(d)
        self.db.commit()

        resp = self.client.get("/api/admin/internship-durations?page=1&page_size=3", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["page"], 1)
        self.assertEqual(data["page_size"], 3)
        self.assertGreaterEqual(data["total"], 5)
        self.assertEqual(len(data["durations"]), 3)

    def test_assignments_list_and_submissions_pagination(self):
        # Create 3 assignments
        for i in range(1, 4):
            a = Assignment(
                organization_id=self.org.id,
                title=f"Assignment {i}",
                created_by_id=self.mentor.id,
                due_date=date(2026, 9, 30),
            )
            self.db.add(a)
        self.db.commit()

        resp = self.client.get("/api/assignments?page=1&page_size=2", headers=self.admin_headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["page"], 1)
        self.assertEqual(data["page_size"], 2)
        self.assertEqual(data["total"], 3)
        self.assertEqual(len(data["assignments"]), 2)

        # Check submissions pagination
        first_a = self.db.query(Assignment).first()
        sub1 = AssignmentSubmission(assignment_id=first_a.id, user_id=self.intern1.id, submission_text="Work 1")
        sub2 = AssignmentSubmission(assignment_id=first_a.id, user_id=self.intern2.id, submission_text="Work 2")
        self.db.add_all([sub1, sub2])
        self.db.commit()

        resp_sub = self.client.get(f"/api/assignments/{first_a.id}/submissions?page=1&page_size=1", headers=self.mentor_headers)
        self.assertEqual(resp_sub.status_code, 200)
        sub_data = resp_sub.json()
        self.assertEqual(sub_data["total"], 2)
        self.assertEqual(sub_data["page"], 1)
        self.assertEqual(sub_data["page_size"], 1)
        self.assertEqual(len(sub_data["submissions"]), 1)
