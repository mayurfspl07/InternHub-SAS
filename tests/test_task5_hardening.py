"""Task 5 tests: performance + security backlog.

- GET /api/admin/intern-assignments is org-scoped and paginates by_mentor
- Cohorts are org-scoped (list filter, cross-tenant detail -> 404, create assigns org)
- Upload validation: image magic bytes/extension allowlist (no SVG), blocked attachment types
- URL validation helper blocks javascript:/data: URLs
"""
import json
import unittest

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import (
    Cohort,
    Organization,
    OrganizationMembership,
    Project,
    User,
    UserRole,
)
from routes.api.admin import intern_assignments
from routes.api.cohorts import create_cohort, get_cohort, list_cohorts
from utils import validate_attachment_upload, validate_image_upload
from app.core.sanitize import validate_http_url


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
        "client": ("testclient", 12345),
    }
    return Request(scope, receive)


class TenantTestCase(unittest.IsolatedAsyncioTestCase):
    def _user(self, name: str, email: str, role: str, org: Organization, mentor_id: int | None = None) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            is_active=True,
            mentor_id=mentor_id,
            session_version=1,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        self.db.add(
            OrganizationMembership(
                organization_id=org.id, user_id=user.id, role=role, is_active=True
            )
        )
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

        self.org_a = Organization(name="Org A", slug="org-a")
        self.org_b = Organization(name="Org B", slug="org-b")
        self.db.add_all([self.org_a, self.org_b])
        self.db.commit()

        self.admin_a = self._user("Admin A", "admin@a.com", UserRole.ADMIN, self.org_a)
        self.admin_b = self._user("Admin B", "admin@b.com", UserRole.ADMIN, self.org_b)
        self.mentor_a = self._user("Mentor A", "mentor@a.com", UserRole.MENTOR, self.org_a)
        self.mentor_b = self._user("Mentor B", "mentor@b.com", UserRole.MENTOR, self.org_b)
        self.intern_a1 = self._user("Intern A1", "a1@a.com", UserRole.INTERN, self.org_a, mentor_id=self.mentor_a.id)
        self.intern_a2 = self._user("Intern A2", "a2@a.com", UserRole.INTERN, self.org_a, mentor_id=None)
        self.intern_b1 = self._user("Intern B1", "b1@b.com", UserRole.INTERN, self.org_b, mentor_id=self.mentor_b.id)

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)


class TestInternAssignments(TenantTestCase):
    async def test_org_scoped_and_totals(self):
        req = make_request(self.admin_a, org_id=self.org_a.id)
        res = await intern_assignments(req, self.db)
        self.assertEqual(res["scope"], "admin")
        self.assertEqual(res["total_interns"], 2)  # only org A interns
        self.assertEqual(res["unassigned_count"], 1)
        self.assertEqual(res["assigned_count"], 1)
        self.assertEqual(len(res["by_mentor"]), 1)  # only org A mentors
        self.assertEqual(res["by_mentor"][0]["mentor"]["id"], self.mentor_a.id)
        self.assertEqual(res["organization_id"], self.org_a.id)

    async def test_by_mentor_paginated(self):
        # Seed 3 more org-A mentors with mentees
        for i in range(3):
            m = self._user(f"Mentor X{i}", f"mx{i}@a.com", UserRole.MENTOR, self.org_a)
            self._user(f"Intern X{i}", f"ix{i}@a.com", UserRole.INTERN, self.org_a, mentor_id=m.id)

        req = make_request(self.admin_a, query_params={"page": "1", "page_size": "2"}, org_id=self.org_a.id)
        res = await intern_assignments(req, self.db)
        self.assertEqual(len(res["by_mentor"]), 2)
        self.assertEqual(res["total"], 4)  # mentor A + 3 seeded
        self.assertEqual(res["total_pages"], 2)
        # Totals stay global, not page-local
        self.assertEqual(res["total_interns"], 2 + 3)

    async def test_mentor_search_filter(self):
        req = make_request(self.admin_a, query_params={"search": "Mentor A"}, org_id=self.org_a.id)
        res = await intern_assignments(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["by_mentor"][0]["mentor"]["name"], "Mentor A")


class TestCohortOrgScoping(TenantTestCase):
    async def test_list_scoped_to_viewer_org(self):
        cohort_a = Cohort(name="Cohort A", organization_id=self.org_a.id, created_by_id=self.admin_a.id)
        cohort_b = Cohort(name="Cohort B", organization_id=self.org_b.id, created_by_id=self.admin_b.id)
        cohort_legacy = Cohort(name="Legacy Cohort", organization_id=None)
        self.db.add_all([cohort_a, cohort_b, cohort_legacy])
        self.db.commit()

        req = make_request(self.admin_a, org_id=self.org_a.id)
        res = await list_cohorts(req, self.db)
        names = {c["name"] for c in res["items"]}
        self.assertIn("Cohort A", names)
        self.assertIn("Legacy Cohort", names)  # NULL-org rows stay visible
        self.assertNotIn("Cohort B", names)

    async def test_cross_tenant_detail_hidden(self):
        cohort_b = Cohort(name="Secret B", organization_id=self.org_b.id, created_by_id=self.admin_b.id)
        self.db.add(cohort_b)
        self.db.commit()
        req = make_request(self.admin_a, org_id=self.org_a.id)
        with self.assertRaises(HTTPException) as ctx:
            await get_cohort(cohort_b.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 404)

    async def test_create_assigns_viewer_org(self):
        req = make_request(
            self.admin_a,
            "POST",
            payload={"name": "New Cohort", "description": "d"},
            org_id=self.org_a.id,
        )
        res = await create_cohort(req, self.db)
        self.assertEqual(res["name"], "New Cohort")
        row = self.db.get(Cohort, res["id"])
        self.assertEqual(row.organization_id, self.org_a.id)


class TestUploadValidation(unittest.TestCase):
    def test_image_accepts_real_png(self):
        png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
        self.assertEqual(validate_image_upload("photo.png", png), ".png")

    def test_image_rejects_extension_mismatch(self):
        fake = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
        with self.assertRaises(ValueError):
            validate_image_upload("photo.jpg", fake)  # PNG bytes named .jpg

    def test_image_rejects_garbage_content(self):
        with self.assertRaises(ValueError):
            validate_image_upload("photo.png", b"<script>evil</script>")

    def test_svg_is_not_allowed(self):
        with self.assertRaises(ValueError):
            validate_image_upload("logo.svg", b"<svg></svg>")

    def test_attachment_blocks_dangerous_extensions(self):
        for name in ("payload.html", "payload.htm", "payload.svg", "malware.exe", "script.js", "shell.sh"):
            with self.assertRaises(ValueError):
                validate_attachment_upload(name, b"x" * 50)
        self.assertEqual(validate_attachment_upload("notes.pdf", b"x" * 50), ".pdf")

    def test_attachment_allowlist(self):
        with self.assertRaises(ValueError):
            validate_attachment_upload("data.csv", b"x", allowed_extensions={".pdf"})
        self.assertEqual(
            validate_attachment_upload("doc.pdf", b"x", allowed_extensions={".pdf"}), ".pdf"
        )


class TestUrlValidation(unittest.TestCase):
    def test_blocks_dangerous_schemes(self):
        for bad in ("javascript:alert(1)", "data:text/html,<script>", "file:///etc/passwd", "//evil.com/x"):
            self.assertIsNone(validate_http_url(bad))
        self.assertIsNone(validate_http_url("not a url"))
        self.assertEqual(validate_http_url("https://ok.com/a?b=1"), "https://ok.com/a?b=1")


if __name__ == "__main__":
    unittest.main()
