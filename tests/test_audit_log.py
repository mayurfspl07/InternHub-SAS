import json
import re
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import AuditLog, Project, ProjectAssignment, User, UserRole
from routes.api.announcements import create_announcement, delete_announcement, update_announcement
from routes.api.audit import list_audit_logs
from routes.api.projects import create_task
from utils import record_audit


def make_request(
    user: User,
    method: str = "GET",
    payload: dict | None = None,
    query_string: bytes = b"",
) -> Request:
    body = json.dumps(payload or {}).encode()
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    token = generate_token(user.id, user.session_version)
    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": "/api/audit",
            "raw_path": b"/api/audit",
            "query_string": query_string,
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class AuditLogTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()
        self.log_patch = patch("log_files.write_activity_log")
        self.log_patch.start()

        self.admin = self._user("Admin", "admin@audit.test", UserRole.ADMIN)
        self.intern = self._user("Intern One", "intern1@audit.test", UserRole.INTERN)
        self.other_intern = self._user(
            "Intern Two", "intern2@audit.test", UserRole.INTERN
        )
        self.project = Project(name="Visible Project")
        self.other_project = Project(name="Hidden Project")
        self.db.add_all([self.project, self.other_project])
        self.db.flush()
        self.db.add_all(
            [
                ProjectAssignment(
                    project_id=self.project.id, user_id=self.intern.id
                ),
                ProjectAssignment(
                    project_id=self.other_project.id,
                    user_id=self.other_intern.id,
                ),
            ]
        )
        self.db.commit()

    def tearDown(self):
        self.log_patch.stop()
        self.db.close()
        self.engine.dispose()

    def _user(self, name: str, email: str, role: str) -> User:
        user = User(name=name, email=email, role=role, is_active=True)
        user.set_password("test-password-1")
        self.db.add(user)
        self.db.flush()
        return user

    async def test_task_activity_uses_current_server_utc_and_appears_immediately(self):
        before = datetime.now(timezone.utc)
        await create_task(
            self.project.id,
            make_request(
                self.intern,
                "POST",
                {
                    "title": "Fresh activity",
                    "created_at": "2000-01-01T00:00:00Z",
                },
            ),
            self.db,
        )
        after = datetime.now(timezone.utc)

        audit = (
            self.db.query(AuditLog)
            .filter_by(action="task.create")
            .order_by(AuditLog.id.desc())
            .first()
        )
        stored = audit.created_at
        if stored.tzinfo is None:
            stored = stored.replace(tzinfo=timezone.utc)
        self.assertGreaterEqual(stored, before)
        self.assertLessEqual(stored, after)

        response = await list_audit_logs(
            make_request(self.admin), self.db
        )
        fresh = next(log for log in response["logs"] if log["id"] == audit.id)
        self.assertRegex(
            fresh["created_at"],
            re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"),
        )
        self.assertNotEqual(fresh["created_at"], "2000-01-01T00:00:00.000Z")

    async def test_audit_results_are_newest_first(self):
        record_audit(
            self.db,
            self.intern,
            "test.first",
            "created",
            "first",
            project_id=self.project.id,
        )
        self.db.commit()
        record_audit(
            self.db,
            self.intern,
            "test.second",
            "created",
            "second",
            project_id=self.project.id,
        )
        self.db.commit()

        response = await list_audit_logs(make_request(self.admin), self.db)
        actions = [log["action"] for log in response["logs"]]
        self.assertLess(actions.index("test.second"), actions.index("test.first"))
        timestamps = [log["created_at"] for log in response["logs"]]
        self.assertEqual(timestamps, sorted(timestamps, reverse=True))

    async def test_project_visibility_is_preserved(self):
        record_audit(
            self.db,
            self.intern,
            "visible.action",
            "changed",
            "visible",
            project_id=self.project.id,
        )
        record_audit(
            self.db,
            self.other_intern,
            "hidden.action",
            "changed",
            "hidden",
            project_id=self.other_project.id,
        )
        self.db.commit()

        intern_response = await list_audit_logs(
            make_request(self.intern), self.db
        )
        intern_actions = {log["action"] for log in intern_response["logs"]}
        self.assertIn("visible.action", intern_actions)
        self.assertNotIn("hidden.action", intern_actions)

        admin_response = await list_audit_logs(
            make_request(self.admin), self.db
        )
        admin_actions = {log["action"] for log in admin_response["logs"]}
        self.assertIn("visible.action", admin_actions)
        self.assertIn("hidden.action", admin_actions)

    async def test_announcement_filter_returns_only_announcement_actions(self):
        await create_announcement(
            make_request(
                self.admin,
                "POST",
                {"title": "Team update", "body": "All hands Friday"},
            ),
            self.db,
        )
        created = (
            self.db.query(AuditLog)
            .filter(AuditLog.action == "announcement.create")
            .one()
        )
        ann_id = created.target_id

        await update_announcement(
            ann_id,
            make_request(
                self.admin,
                "PUT",
                {"is_pinned": True},
            ),
            self.db,
        )
        await delete_announcement(
            ann_id,
            make_request(self.admin, "DELETE"),
            self.db,
        )

        record_audit(
            self.db,
            self.admin,
            "task.create",
            "created task",
            "Noise",
            project_id=self.project.id,
        )
        self.db.commit()

        response = await list_audit_logs(
            make_request(self.admin, query_string=b"action=announcement"),
            self.db,
        )
        actions = {log["action"] for log in response["logs"]}
        self.assertIn("announcement.create", actions)
        self.assertIn("announcement.pin", actions)
        self.assertIn("announcement.delete", actions)
        self.assertNotIn("task.create", actions)
        self.assertTrue(all(action.startswith("announcement.") for action in actions))


if __name__ == "__main__":
    unittest.main()
