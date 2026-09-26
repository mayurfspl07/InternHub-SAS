"""Intern paid/unpaid + stipend tests.

- POST /api/admin/users accepts is_paid + stipend_amount for interns
- Paid interns require a non-negative stipend amount
- Unpaid interns never keep a stipend amount
- PUT /api/admin/users/{id} can switch paid <-> unpaid and keeps the
  organization membership row in sync
- Non-intern roles ignore stipend fields
"""
import json
import unittest

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request
from starlette.responses import Response

from database import Base
from dependencies import generate_token
from models import (
    Organization,
    OrganizationMembership,
    User,
    UserRole,
)
from routes.api.admin import create_user, update_user


def make_request(
    user: User,
    method: str = "GET",
    payload: dict | None = None,
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

    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": "/",
        "raw_path": b"/",
        "query_string": b"",
        "headers": headers,
        "client": ("testclient", 12345),
    }
    return Request(scope, receive)


class StipendTestCase(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()

        self.org = Organization(name="Org A", slug="org-a")
        self.db.add(self.org)
        self.db.commit()

        self.admin = User(
            name="Admin A",
            email="admin@a.com",
            password_hash="test-hash",
            role=UserRole.ADMIN,
            is_active=True,
            session_version=1,
        )
        self.db.add(self.admin)
        self.db.commit()
        self.db.refresh(self.admin)
        self.db.add(
            OrganizationMembership(
                organization_id=self.org.id, user_id=self.admin.id, role=UserRole.ADMIN, is_active=True
            )
        )
        self.db.commit()

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    def membership_for(self, user_id: int) -> OrganizationMembership:
        return (
            self.db.query(OrganizationMembership)
            .filter_by(user_id=user_id, is_active=True, is_deleted=False)
            .first()
        )

    async def create_intern(self, **extra) -> dict:
        payload = {
            "name": "New Intern",
            "email": "new.intern@a.com",
            "password": "Password123!",
            "role": UserRole.INTERN,
            **extra,
        }
        req = make_request(self.admin, "POST", payload, org_id=self.org.id)
        return await create_user(req, self.db)

    async def test_create_paid_intern_with_stipend(self):
        res = await self.create_intern(is_paid=True, stipend_amount=5000)
        self.assertIs(res["is_paid"], True)
        self.assertEqual(res["stipend_amount"], 5000)

        user = self.db.query(User).filter_by(email="new.intern@a.com").first()
        self.assertIs(user.is_paid, True)
        self.assertEqual(user.stipend_amount, 5000)
        membership = self.membership_for(user.id)
        self.assertIs(membership.is_paid, True)
        self.assertEqual(membership.stipend_amount, 5000)

    async def test_create_unpaid_intern_clears_stipend(self):
        res = await self.create_intern(is_paid=False, stipend_amount=999)
        self.assertIs(res["is_paid"], False)
        self.assertIsNone(res["stipend_amount"])

    async def test_create_intern_defaults_when_fields_missing(self):
        res = await self.create_intern()
        self.assertIsNone(res["is_paid"])
        self.assertIsNone(res["stipend_amount"])

    async def test_create_paid_intern_requires_stipend(self):
        with self.assertRaises(HTTPException) as ctx:
            await self.create_intern(is_paid=True)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_create_paid_intern_rejects_negative_stipend(self):
        with self.assertRaises(HTTPException) as ctx:
            await self.create_intern(is_paid=True, stipend_amount=-5)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_create_non_intern_ignores_stipend_fields(self):
        payload = {
            "name": "New Mentor",
            "email": "new.mentor@a.com",
            "password": "Password123!",
            "role": UserRole.MENTOR,
            "is_paid": True,
            "stipend_amount": 5000,
        }
        req = make_request(self.admin, "POST", payload, org_id=self.org.id)
        res = await create_user(req, self.db)
        self.assertIsNone(res["is_paid"])
        self.assertIsNone(res["stipend_amount"])

    async def _create_stored_intern(self, **extra) -> User:
        await self.create_intern(email="edit.intern@a.com", **extra)
        return self.db.query(User).filter_by(email="edit.intern@a.com").first()

    async def test_edit_intern_switch_unpaid_to_paid(self):
        intern = await self._create_stored_intern()
        self.db.expire_all()

        req = make_request(
            self.admin, "PUT", {"is_paid": True, "stipend_amount": 7500.5}
        )
        res = await update_user(intern.id, req, Response(), self.db)
        self.assertIs(res["is_paid"], True)
        self.assertEqual(res["stipend_amount"], 7500.5)

        self.db.expire_all()
        intern = self.db.get(User, intern.id)
        self.assertIs(intern.is_paid, True)
        self.assertEqual(intern.stipend_amount, 7500.5)
        membership = self.membership_for(intern.id)
        self.assertIs(membership.is_paid, True)
        self.assertEqual(membership.stipend_amount, 7500.5)

    async def test_edit_intern_switch_paid_to_unpaid(self):
        intern = await self._create_stored_intern(is_paid=True, stipend_amount=5000)
        self.db.expire_all()

        req = make_request(self.admin, "PUT", {"is_paid": False})
        res = await update_user(intern.id, req, Response(), self.db)
        self.assertIs(res["is_paid"], False)
        self.assertIsNone(res["stipend_amount"])

        self.db.expire_all()
        intern = self.db.get(User, intern.id)
        self.assertIs(intern.is_paid, False)
        self.assertIsNone(intern.stipend_amount)
        membership = self.membership_for(intern.id)
        self.assertIs(membership.is_paid, False)
        self.assertIsNone(membership.stipend_amount)

    async def test_edit_paid_intern_requires_stipend_when_amount_missing(self):
        intern = await self._create_stored_intern(is_paid=False)
        self.db.expire_all()

        req = make_request(self.admin, "PUT", {"is_paid": True})
        with self.assertRaises(HTTPException) as ctx:
            await update_user(intern.id, req, Response(), self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_edit_accepts_stipend_sent_as_string(self):
        intern = await self._create_stored_intern()
        self.db.expire_all()

        req = make_request(
            self.admin, "PUT", {"is_paid": "true", "stipend_amount": "4000"}
        )
        res = await update_user(intern.id, req, Response(), self.db)
        self.assertIs(res["is_paid"], True)
        self.assertEqual(res["stipend_amount"], 4000)


if __name__ == "__main__":
    unittest.main()
