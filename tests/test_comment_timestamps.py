import json
import re
import unittest
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Project, Task, TaskComment, User, UserRole
from routes.api.projects import add_comment, get_comments
from utils import isoformat_utc

UTC_SUFFIX = re.compile(r"(Z|\+00:00)$")


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
    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": "/api/projects/tasks/1/comments",
            "raw_path": b"/api/projects/tasks/1/comments",
            "query_string": b"",
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class TimestampSerializationTests(unittest.TestCase):
    def test_isoformat_utc_appends_z_suffix(self):
        naive = datetime(2026, 7, 22, 7, 37, 21, 123456)
        self.assertTrue(UTC_SUFFIX.search(isoformat_utc(naive)))
        self.assertEqual(
            isoformat_utc(datetime(2026, 7, 22, 7, 37, 21, tzinfo=timezone.utc)),
            "2026-07-22T07:37:21.000000Z",
        )

    def test_isoformat_utc_can_emit_offset(self):
        value = isoformat_utc(
            datetime(2026, 7, 22, 7, 37, 21, tzinfo=timezone.utc),
            use_z_suffix=False,
        )
        self.assertTrue(value.endswith("+00:00"))


class TaskCommentTimestampTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.mentor = User(
            name="Mentor",
            email="mentor@comments.test",
            role=UserRole.MENTOR,
            is_active=True,
        )
        self.mentor.set_password("test-password-1")
        self.db.add(self.mentor)
        self.db.flush()

        self.project = Project(name="Comment project", mentor_id=self.mentor.id)
        self.db.add(self.project)
        self.db.flush()
        self.task = Task(project_id=self.project.id, title="Comment task")
        self.db.add(self.task)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    async def test_get_comments_returns_timezone_aware_created_at(self):
        created = await add_comment(
            self.task.id,
            make_request(self.mentor, "POST", {"body": "Looks good"}),
            self.db,
        )
        self.assertRegex(created["created_at"], UTC_SUFFIX)

        comments = await get_comments(
            self.task.id,
            make_request(self.mentor, "GET"),
            self.db,
        )
        self.assertEqual(len(comments), 1)
        self.assertRegex(comments[0]["created_at"], UTC_SUFFIX)

        stored = self.db.get(TaskComment, comments[0]["id"])
        self.assertIsNotNone(stored.created_at)


if __name__ == "__main__":
    unittest.main()
