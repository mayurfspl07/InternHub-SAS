"""Task 4 tests: internship duration assignment flow.

- POST /api/admin/users accepts internship_duration_months and validates it
  tenant-wise against the org's InternshipDurationMaster tiers
- joining_date is applied and internship_end_date is computed
- an OrganizationMembership is created so duration→leaves mapping works
- GET /api/profile returns duration info + tier leaves
- leave balance quota follows the assigned duration tier
- PUT /users/{id} can change duration and re-maps quota
"""
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
    User,
    UserRole,
)
from routes.api.admin import create_user, update_user
from routes.api.profile import get_profile
from routes.api.leave import my_requests
from utils import get_leave_balance, get_or_seed_org_internship_durations


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


class TestDurationFlow(unittest.IsolatedAsyncioTestCase):
    def _user(self, name: str, email: str, role: str, org: Organization, duration_months: int | None = None) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            is_active=True,
            session_version=1,
            internship_duration_months=duration_months,
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

        self.org = Organization(name="DurationOrg", slug="durationorg")
        self.db.add(self.org)
        self.db.commit()

        self.admin = self._user("Admin D", "admin@durationorg.com", UserRole.ADMIN, self.org)

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def test_create_user_with_valid_duration(self):
        get_or_seed_org_internship_durations(self.db, self.org.id)
        req = make_request(
            self.admin,
            "POST",
            payload={
                "name": "Six Month Sam",
                "email": "sam@durationorg.com",
                "password": "Password123!",
                "role": UserRole.INTERN,
                "internship_duration_months": 6,
                "joining_date": "2026-09-01",
            },
            org_id=self.org.id,
        )
        res = await create_user(req, self.db)
        self.assertEqual(res["internship_duration_months"], 6)
        # 6 months from 2026-09-01 -> 2027-03-01
        self.assertEqual(res["joining_date"], "2026-09-01")
        self.assertEqual(res["internship_end_date"], "2027-03-01")
        self.assertEqual(res["internship_duration"]["title"], "6 Months")
        self.assertEqual(res["internship_duration"]["leaves"], 10)

        membership = (
            self.db.query(OrganizationMembership).filter_by(user_id=res["id"]).first()
        )
        self.assertIsNotNone(membership)
        self.assertEqual(membership.duration_months() if False else membership.internship_duration_months, 6)

    async def test_create_user_rejects_invalid_tenant_duration(self):
        get_or_seed_org_internship_durations(self.db, self.org.id)
        req = make_request(
            self.admin,
            "POST",
            payload={
                "name": "Bad Duration",
                "email": "bad@durationorg.com",
                "password": "Password123!",
                "role": UserRole.INTERN,
                "internship_duration_months": 7,
            },
            org_id=self.org.id,
        )
        with self.assertRaises(HTTPException) as ctx:
            await create_user(req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)
        self.assertIn("Allowed durations", ctx.exception.detail)

    async def test_leaves_follow_assigned_duration(self):
        get_or_seed_org_internship_durations(self.db, self.org.id)
        req = make_request(
            self.admin,
            "POST",
            payload={
                "name": "Leavy McLeave",
                "email": "leavy@durationorg.com",
                "password": "Password123!",
                "role": UserRole.INTERN,
                "internship_duration_months": 6,
            },
            org_id=self.org.id,
        )
        created = await create_user(req, self.db)
        intern = self.db.get(User, created["id"])

        balance = get_leave_balance(self.db, intern.id, self.org.id)
        self.assertEqual(balance["quota"], 10)  # 6-month tier grants 10 leaves

        # Profile shows duration tier info
        profile_req = make_request(intern, org_id=self.org.id)
        profile = await get_profile(profile_req, self.db)
        self.assertEqual(profile["internship_duration_months"], 6)
        self.assertEqual(profile["internship_duration"]["leaves"], 10)
        self.assertEqual(profile["internship_summary"]["total_leave_quota"], 10)

    async def test_mine_endpoint_balance_uses_tier(self):
        get_or_seed_org_internship_durations(self.db, self.org.id)
        req = make_request(
            self.admin,
            "POST",
            payload={
                "name": "Mine Intern",
                "email": "mine@durationorg.com",
                "password": "Password123!",
                "role": UserRole.INTERN,
                "internship_duration_months": 3,
            },
            org_id=self.org.id,
        )
        created = await create_user(req, self.db)
        intern = self.db.get(User, created["id"])

        mine_req = make_request(intern, org_id=self.org.id)
        mine = await my_requests(mine_req, self.db)
        self.assertEqual(mine["balance"]["quota"], 5)  # 3-month tier grants 5 leaves

    async def test_update_user_duration_remaps_quota(self):
        get_or_seed_org_internship_durations(self.db, self.org.id)
        req = make_request(
            self.admin,
            "POST",
            payload={
                "name": "Switch Intern",
                "email": "switch@durationorg.com",
                "password": "Password123!",
                "role": UserRole.INTERN,
                "internship_duration_months": 3,
            },
            org_id=self.org.id,
        )
        created = await create_user(req, self.db)
        intern = self.db.get(User, created["id"])
        self.assertEqual(get_leave_balance(self.db, intern.id, self.org.id)["quota"], 5)

        upd_req = make_request(
            self.admin,
            "PUT",
            payload={"internship_duration_months": 6},
            org_id=self.org.id,
        )
        from starlette.responses import Response
        updated = await update_user(intern.id, upd_req, Response(), self.db)
        self.assertEqual(updated["internship_duration_months"], 6)
        self.assertEqual(get_leave_balance(self.db, intern.id, self.org.id)["quota"], 10)

        membership = (
            self.db.query(OrganizationMembership).filter_by(user_id=intern.id).first()
        )
        self.assertEqual(membership.internship_duration_months, 6)

    async def test_update_user_rejects_invalid_duration(self):
        req = make_request(
            self.admin,
            "PUT",
            payload={"internship_duration_months": 99},
            org_id=self.org.id,
        )
        from starlette.responses import Response
        with self.assertRaises(HTTPException) as ctx:
            await update_user(self.admin.id, req, Response(), self.db)
        self.assertEqual(ctx.exception.status_code, 422)


if __name__ == "__main__":
    unittest.main()
