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
    Organization,
    OrganizationMembership,
    InternshipDurationMaster,
    User,
    UserRole,
)
from routes.api.admin import (
    create_internship_duration,
    delete_internship_duration,
    list_internship_durations,
    update_internship_duration,
)
from utils import (
    get_or_seed_org_internship_durations,
    get_leave_balance,
    resolve_user_leave_quota,
)


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


class TestInternshipDurationMaster(unittest.IsolatedAsyncioTestCase):
    def _user(self, name: str, email: str, role: str, org_id: int, duration_months: int | None = None) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            internship_duration_months=duration_months,
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

        self.org = Organization(name="InnovateTech", slug="innovatetech")
        self.db.add(self.org)
        self.db.commit()

        self.admin = self._user("Admin Leader", "admin@innovatetech.com", UserRole.ADMIN, self.org.id)
        self.intern = self._user("Alice Intern", "alice@innovatetech.com", UserRole.INTERN, self.org.id, duration_months=6)

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def test_auto_seed_and_list_durations(self):
        durations = get_or_seed_org_internship_durations(self.db, self.org.id)
        self.assertEqual(len(durations), 3)

        req = make_request(self.admin, "GET", org_id=self.org.id)
        res = await list_internship_durations(req, self.db)
        self.assertEqual(len(res["durations"]), 3)
        titles = [d["title"] for d in res["durations"]]
        self.assertIn("1 Month", titles)
        self.assertIn("3 Months", titles)
        self.assertIn("6 Months", titles)

    async def test_create_update_delete_duration_master(self):
        # Create 12 Months tier
        create_req = make_request(
            self.admin,
            "POST",
            payload={
                "title": "12 Months (Full Year)",
                "internship_duration": 12,
                "leaves": 20,
                "is_default": False,
            },
            org_id=self.org.id,
        )
        created = await create_internship_duration(create_req, self.db)
        self.assertEqual(created["duration_months"], 12)
        self.assertEqual(created["leaves"], 20)

        # Update leaves to 24
        update_req = make_request(
            self.admin,
            "PUT",
            payload={"leaves": 24},
            org_id=self.org.id,
        )
        updated = await update_internship_duration(created["id"], update_req, self.db)
        self.assertEqual(updated["leaves"], 24)

        # Delete duration
        del_req = make_request(self.admin, "DELETE", org_id=self.org.id)
        del_res = await delete_internship_duration(created["id"], del_req, self.db)
        self.assertTrue(del_res["success"])

    async def test_dynamic_leave_quota_resolution(self):
        get_or_seed_org_internship_durations(self.db, self.org.id)
        # Alice is configured with 6 months -> 6 Months tier in seed has 10 leaves
        quota = resolve_user_leave_quota(self.db, self.intern.id, self.org.id)
        self.assertEqual(quota, 10)

        balance = get_leave_balance(self.db, self.intern.id, self.org.id)
        self.assertEqual(balance["quota"], 10)
        self.assertEqual(balance["remaining"], 10)
