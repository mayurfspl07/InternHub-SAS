import json
import unittest
from datetime import date

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import (
    Organization,
    OrganizationMembership,
    Project,
    ProjectStatusBucket,
    User,
    UserRole,
)
from routes.api.admin import (
    create_project_status,
    delete_project_status,
    list_project_statuses,
    reorder_project_statuses,
    update_project_status,
)
from routes.api.projects import (
    create_project,
    get_project_statuses_dropdown,
    update_project,
)
from utils import get_or_seed_org_project_statuses


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
    }
    return Request(scope, receive)


class TestProjectStatusMaster(unittest.IsolatedAsyncioTestCase):
    def _user(self, name: str, email: str, role: str, org_id: int) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            is_active=True,
            session_version=1,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)

        membership = OrganizationMembership(
            organization_id=org_id,
            user_id=user.id,
            role=role,
            is_active=True,
        )
        self.db.add(membership)
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

        self.org = Organization(name="TechCorp", slug="techcorp")
        self.db.add(self.org)
        self.db.commit()

        self.admin = self._user("Admin User", "admin@techcorp.com", UserRole.ADMIN, self.org.id)
        self.mentor = self._user("Mentor User", "mentor@techcorp.com", UserRole.MENTOR, self.org.id)
        self.intern = self._user("Intern User", "intern@techcorp.com", UserRole.INTERN, self.org.id)

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def test_auto_seed_default_project_statuses(self):
        statuses = get_or_seed_org_project_statuses(self.db, self.org.id)
        self.assertEqual(len(statuses), 4)
        slugs = [s.slug for s in statuses]
        self.assertIn("planning", slugs)
        self.assertIn("active", slugs)
        self.assertIn("on_hold", slugs)
        self.assertIn("completed", slugs)

    async def test_admin_list_and_create_project_status(self):
        req = make_request(self.admin, "GET", org_id=self.org.id)
        res = await list_project_statuses(req, self.db)
        self.assertEqual(len(res["statuses"]), 4)

        # Create new custom status
        create_req = make_request(
            self.admin,
            "POST",
            payload={"name": "In Review", "color": "#6366F1", "is_default": False},
            org_id=self.org.id,
        )
        created = await create_project_status(create_req, self.db)
        self.assertEqual(created["name"], "In Review")
        self.assertEqual(created["slug"], "in_review")
        self.assertEqual(created["color"], "#6366F1")

        # Verify in list
        res2 = await list_project_statuses(req, self.db)
        self.assertEqual(len(res2["statuses"]), 5)

    async def test_project_statuses_dropdown(self):
        req = make_request(self.mentor, "GET", org_id=self.org.id)
        res = await get_project_statuses_dropdown(req, self.db)
        self.assertIn("statuses", res)
        self.assertEqual(len(res["statuses"]), 4)

    async def test_project_create_and_update_with_valid_and_invalid_status(self):
        # Create with default/valid status
        create_req = make_request(
            self.admin,
            "POST",
            payload={
                "name": "Apollo Project",
                "mentor_id": self.mentor.id,
                "status": "active",
            },
            org_id=self.org.id,
        )
        proj = await create_project(create_req, self.db)
        self.assertEqual(proj["status"], "active")

        # Update to completed
        update_req = make_request(
            self.admin,
            "PUT",
            payload={"name": "Apollo Project", "status": "completed"},
            org_id=self.org.id,
        )
        updated = await update_project(proj["id"], update_req, self.db)
        self.assertEqual(updated["status"], "completed")

        # Update with invalid status should raise 422
        invalid_req = make_request(
            self.admin,
            "PUT",
            payload={"name": "Apollo Project", "status": "non_existent_status_xyz"},
            org_id=self.org.id,
        )
        with self.assertRaises(HTTPException) as ctx:
            await update_project(proj["id"], invalid_req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_delete_project_status_blocked_if_used(self):
        get_or_seed_org_project_statuses(self.db, self.org.id)
        bucket = self.db.query(ProjectStatusBucket).filter_by(organization_id=self.org.id, slug="active").first()

        # Create active project
        proj = Project(
            organization_id=self.org.id,
            name="Test Active Project",
            mentor_id=self.mentor.id,
            status="active",
        )
        self.db.add(proj)
        self.db.commit()

        # Try to delete active status
        del_req = make_request(self.admin, "DELETE", org_id=self.org.id)
        with self.assertRaises(HTTPException) as ctx:
            await delete_project_status(bucket.id, del_req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)
        self.assertIn("active project", ctx.exception.detail)
