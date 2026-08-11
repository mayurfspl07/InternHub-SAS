import json
import unittest
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Announcement, BinEntityType, BinItem, User, UserRole
from recycle_bin import move_to_bin, purge_expired_bin_items
from routes.api.admin import list_recycle_bin, restore_recycle_bin_item
from routes.api.announcements import create_announcement, delete_announcement, list_announcements


def make_request(user: User, method: str, payload: dict | None = None) -> Request:
    body = json.dumps(payload or {}).encode()
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    token = generate_token(user.id, user.session_version)
    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": "/",
        "raw_path": b"/",
        "query_string": b"",
        "headers": [(b"authorization", f"Bearer {token}".encode())],
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }
    return Request(scope, receive)


class RecycleBinTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()

        self.admin = self._user("Admin", "admin@test.local", UserRole.ADMIN)
        self.mentor = self._user("Mentor", "mentor@test.local", UserRole.MENTOR)
        self.intern = self._user("Intern", "intern@test.local", UserRole.INTERN)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(self, name: str, email: str, role: str) -> User:
        user = User(
            name=name,
            email=email,
            role=role,
            is_active=True,
            session_version=1,
        )
        user.set_password("password123")
        self.db.add(user)
        self.db.flush()
        return user

    async def test_delete_restore_announcement_flow(self):
        created = await create_announcement(
            make_request(self.admin, "POST", {"title": "Bin Test", "body": "Hello"}),
            self.db,
        )
        ann_id = created["id"]

        listed = await list_announcements(make_request(self.admin, "GET"), self.db)
        self.assertEqual(len(listed), 1)

        await delete_announcement(ann_id, make_request(self.admin, "DELETE"), self.db)

        listed_after_delete = await list_announcements(
            make_request(self.admin, "GET"), self.db
        )
        self.assertEqual(listed_after_delete, [])

        bin_list = await list_recycle_bin(make_request(self.admin, "GET"), self.db)
        self.assertEqual(bin_list["total"], 1)
        item = bin_list["items"][0]
        self.assertEqual(item["entity_type"], BinEntityType.ANNOUNCEMENT)
        self.assertEqual(item["entity_id"], ann_id)
        self.assertEqual(item["title"], "Bin Test")
        self.assertTrue(item["deleted_at"].endswith("Z"))
        self.assertTrue(item["expires_at"].endswith("Z"))

        restored = await restore_recycle_bin_item(
            item["id"], make_request(self.admin, "POST"), self.db
        )
        self.assertTrue(restored["ok"])

        listed_after_restore = await list_announcements(
            make_request(self.admin, "GET"), self.db
        )
        self.assertEqual(len(listed_after_restore), 1)
        self.assertEqual(listed_after_restore[0]["id"], ann_id)

    async def test_non_admin_cannot_access_bin(self):
        with self.assertRaises(HTTPException) as ctx:
            await list_recycle_bin(make_request(self.mentor, "GET"), self.db)
        self.assertEqual(ctx.exception.status_code, 403)

        with self.assertRaises(HTTPException) as ctx:
            await restore_recycle_bin_item(1, make_request(self.intern, "POST"), self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    def test_expired_bin_items_are_purged(self):
        ann = Announcement(
            author_id=self.admin.id,
            title="Expired",
            body="Gone",
            is_deleted=True,
        )
        self.db.add(ann)
        self.db.flush()

        expired_at = datetime.now(timezone.utc) - timedelta(days=1)
        deleted_at = expired_at - timedelta(days=15)
        bin_item = BinItem(
            entity_type=BinEntityType.ANNOUNCEMENT,
            entity_id=ann.id,
            title=ann.title,
            deleted_by_id=self.admin.id,
            deleted_by_name=self.admin.name,
            deleted_at=deleted_at,
            expires_at=expired_at,
            snapshot_json="{}",
        )
        self.db.add(bin_item)
        self.db.commit()

        purged = purge_expired_bin_items(self.db)
        self.assertEqual(purged, 1)
        self.assertIsNone(self.db.get(Announcement, ann.id))
        self.assertIsNone(self.db.get(BinItem, bin_item.id))

    def test_move_to_bin_sets_expiry(self):
        ann = Announcement(author_id=self.admin.id, title="Soon", body="Body")
        self.db.add(ann)
        self.db.commit()

        item = move_to_bin(
            self.db, self.admin, BinEntityType.ANNOUNCEMENT, ann, title=ann.title
        )
        self.db.commit()

        delta = item.expires_at - item.deleted_at
        self.assertEqual(delta.days, 15)
        self.assertTrue(ann.is_deleted)


if __name__ == "__main__":
    unittest.main()
