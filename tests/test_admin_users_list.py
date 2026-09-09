"""Task 1 regression tests: /api/admin/users list fixes.

- superadmin / platform-admin rows must never leak into the list (or counts)
- ?role=superadmin must be rejected
- list must be newest-first (a newly created user appears first)
- creating or role-changing into 'superadmin' via the admin API must be blocked
- ?unassigned=true returns only interns without a mentor
- page_size is capped at 100
"""
import json
import unittest
from datetime import timedelta

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
    _utcnow,
)
from routes.api.admin import (
    change_role,
    create_user,
    list_users,
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


class TestAdminUsersList(unittest.IsolatedAsyncioTestCase):
    def _user(
        self,
        name: str,
        email: str,
        role: str,
        *,
        is_platform_admin: bool = False,
        mentor_id: int | None = None,
        created_offset_minutes: int = 0,
    ) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            is_active=True,
            is_platform_admin=is_platform_admin,
            mentor_id=mentor_id,
            session_version=1,
            created_at=_utcnow() + timedelta(minutes=created_offset_minutes),
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        self.db.add(
            OrganizationMembership(
                organization_id=self.org.id,
                user_id=user.id,
                role=role,
                is_active=True,
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

        self.org = Organization(name="InnovateTech", slug="innovatetech")
        self.db.add(self.org)
        self.db.commit()

        self.platform_admin = self._user(
            "Super Admin", "bootstrap@internhub.dev", UserRole.ADMIN, is_platform_admin=True
        )
        self.superadmin = self._user("Root Super", "root@internhub.dev", UserRole.SUPERADMIN)
        self.org_admin = self._user("Org Admin", "admin@innovatetech.com", UserRole.ADMIN)
        self.mentor = self._user("Mentor Mary", "mentor@innovatetech.com", UserRole.MENTOR)
        self.intern1 = self._user("Alice Intern", "alice@innovatetech.com", UserRole.INTERN, mentor_id=None)
        self.intern2 = self._user(
            "Bob Intern", "bob@innovatetech.com", UserRole.INTERN, mentor_id=self.mentor.id
        )

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def test_superadmin_and_platform_admin_hidden_from_org_admin(self):
        req = make_request(self.org_admin, org_id=self.org.id)
        res = await list_users(req, self.db)

        listed_ids = {u["id"] for u in res["users"]}
        self.assertNotIn(self.superadmin.id, listed_ids)
        self.assertNotIn(self.platform_admin.id, listed_ids)
        self.assertIn(self.org_admin.id, listed_ids)
        self.assertEqual(res["counts"]["all"], 4)  # admin + mentor + 2 interns
        self.assertEqual(res["counts"]["intern"], 2)
        self.assertEqual(res["counts"]["mentor"], 1)

    async def test_platform_admin_caller_sees_platform_admin_rows_but_not_superadmin(self):
        req = make_request(self.platform_admin, org_id=self.org.id)
        res = await list_users(req, self.db)
        listed_ids = {u["id"] for u in res["users"]}
        self.assertIn(self.platform_admin.id, listed_ids)
        self.assertNotIn(self.superadmin.id, listed_ids)

    async def test_superadmin_caller_can_list_users(self):
        # Superadmin accounts are the most privileged operators — the user
        # management surface must not 403 them (regression: raw role-string gate).
        self.superadmin.is_platform_admin = True
        self.db.commit()
        req = make_request(self.superadmin, org_id=self.org.id)
        res = await list_users(req, self.db)
        self.assertEqual(res["counts"]["all"], 5)  # everyone except the superadmin row itself
        listed_ids = {u["id"] for u in res["users"]}
        self.assertIn(self.org_admin.id, listed_ids)
        self.assertIn(self.mentor.id, listed_ids)

    async def test_superadmin_caller_can_create_user(self):
        req = make_request(
            self.superadmin,
            "POST",
            payload={
                "name": "Created By Root",
                "email": "byroot@innovatetech.com",
                "password": "Password123!",
                "role": UserRole.INTERN,
            },
            org_id=self.org.id,
        )
        res = await create_user(req, self.db)
        self.assertEqual(res["role"], UserRole.INTERN)

    async def test_role_filter_superadmin_rejected(self):
        req = make_request(
            self.org_admin, query_params={"role": "superadmin"}, org_id=self.org.id
        )
        with self.assertRaises(HTTPException) as ctx:
            await list_users(req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_newest_first_ordering(self):
        newest = self._user(
            "New Kid", "newkid@innovatetech.com", UserRole.INTERN, created_offset_minutes=5
        )
        req = make_request(self.org_admin, org_id=self.org.id)
        res = await list_users(req, self.db)
        self.assertEqual(res["users"][0]["id"], newest.id)
        self.assertEqual(res["users"][0]["email"], "newkid@innovatetech.com")

    async def test_ordering_descending_by_created_at(self):
        req = make_request(self.org_admin, org_id=self.org.id)
        res = await list_users(req, self.db)
        created_order = [u["id"] for u in res["users"]]
        # intern2 was created last among the original seed rows
        self.assertEqual(created_order[0], self.intern2.id)
        # org_admin is the oldest row visible to an org-admin caller
        self.assertEqual(created_order[-1], self.org_admin.id)

    async def test_create_user_rejects_superadmin_role(self):
        req = make_request(
            self.org_admin,
            "POST",
            payload={
                "name": "Evil Sudo",
                "email": "evil@innovatetech.com",
                "password": "Password123!",
                "role": UserRole.SUPERADMIN,
            },
            org_id=self.org.id,
        )
        with self.assertRaises(HTTPException) as ctx:
            await create_user(req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_change_role_rejects_superadmin_role(self):
        req = make_request(
            self.org_admin,
            "POST",
            payload={"role": UserRole.SUPERADMIN},
            org_id=self.org.id,
        )
        with self.assertRaises(HTTPException) as ctx:
            await change_role(self.intern1.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_unassigned_filter_returns_only_mentorless_interns(self):
        req = make_request(
            self.org_admin,
            query_params={"unassigned": "true"},
            org_id=self.org.id,
        )
        res = await list_users(req, self.db)
        listed_ids = {u["id"] for u in res["users"]}
        self.assertIn(self.intern1.id, listed_ids)  # no mentor
        self.assertNotIn(self.intern2.id, listed_ids)  # has a mentor
        self.assertNotIn(self.mentor.id, listed_ids)  # not an intern
        self.assertEqual(res["total"], 1)

    async def test_mentor_id_null_filter(self):
        req = make_request(
            self.org_admin,
            query_params={"mentor_id": "null"},
            org_id=self.org.id,
        )
        res = await list_users(req, self.db)
        for u in res["users"]:
            self.assertEqual(u["role"], UserRole.INTERN)
            self.assertIsNone(u["mentor_id"])

    async def test_page_size_capped_at_100(self):
        # Seed 120 interns + admin/mentor rows
        for i in range(120):
            self._user(f"Bulk {i}", f"bulk{i}@innovatetech.com", UserRole.INTERN)
        req = make_request(
            self.org_admin,
            query_params={"page": "1", "page_size": "5000"},
            org_id=self.org.id,
        )
        res = await list_users(req, self.db)
        self.assertEqual(res["page_size"], 100)
        self.assertLessEqual(len(res["users"]), 100)

    async def test_pagination_bounds(self):
        req = make_request(
            self.org_admin,
            query_params={"page": "0", "page_size": "0"},
            org_id=self.org.id,
        )
        res = await list_users(req, self.db)
        self.assertEqual(res["page"], 1)
        self.assertGreaterEqual(res["page_size"], 1)

    async def test_empty_page_beyond_range(self):
        req = make_request(
            self.org_admin,
            query_params={"page": "99", "page_size": "2"},
            org_id=self.org.id,
        )
        res = await list_users(req, self.db)
        self.assertEqual(res["users"], [])
        self.assertGreater(res["total_pages"], 1)

    async def test_search_matches_name_and_email(self):
        req = make_request(
            self.org_admin, query_params={"search": "alice"}, org_id=self.org.id
        )
        res = await list_users(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["users"][0]["email"], "alice@innovatetech.com")

    async def test_response_shape_includes_items_alias(self):
        req = make_request(self.org_admin, org_id=self.org.id)
        res = await list_users(req, self.db)
        for key in ("users", "items", "page", "page_size", "total", "total_pages", "counts"):
            self.assertIn(key, res)
        self.assertEqual(res["users"], res["items"])


if __name__ == "__main__":
    unittest.main()
