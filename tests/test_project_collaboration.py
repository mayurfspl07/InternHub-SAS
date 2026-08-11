import unittest
import json
from datetime import date, datetime, timedelta, time

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, joinedload
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import (
    Project,
    ProjectAssignment,
    ProjectMentorAssignment,
    ProjectComment,
    ProjectLink,
    User,
    UserRole,
    AuditLog,
)
from routes.api.projects import (
    get_project_comments,
    create_project_comment,
    delete_project_comment,
    get_project_links,
    create_project_link,
    delete_project_link,
)


def make_request(
    user: User | None,
    method: str = "GET",
    body: dict | None = None,
    query_string: bytes = b"",
) -> Request:
    sent = False
    body_bytes = json.dumps(body).encode("utf-8") if body is not None else b""

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body_bytes, "more_body": False}

    headers = []
    if user:
        token = generate_token(user.id, user.session_version)
        headers.append((b"authorization", f"Bearer {token}".encode()))

    return Request(
        {
            "type": "http",
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": "/api/projects/stub",
            "raw_path": b"/api/projects/stub",
            "query_string": query_string,
            "headers": headers,
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class ProjectCollaborationTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        # Setup Users
        self.admin = self._user("Admin User", "admin@collab.test", UserRole.ADMIN)
        self.mentor = self._user("Mentor User", "mentor@collab.test", UserRole.MENTOR)
        self.co_mentor = self._user("Co-Mentor User", "comentor@collab.test", UserRole.MENTOR)
        self.other_mentor = self._user("Other Mentor", "othermentor@collab.test", UserRole.MENTOR)
        self.intern = self._user("Intern One", "intern1@collab.test", UserRole.INTERN)
        self.other_intern = self._user("Intern Two", "intern2@collab.test", UserRole.INTERN)

        # Setup Project
        self.project = Project(
            name="Alpha Project",
            description="Project Alpha Description",
            mentor_id=self.mentor.id,
            status="active"
        )
        self.db.add(self.project)
        self.db.flush()

        # Assignments
        self.db.add(ProjectMentorAssignment(project_id=self.project.id, user_id=self.co_mentor.id))
        self.db.add(ProjectAssignment(project_id=self.project.id, user_id=self.intern.id))
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
        )
        user.set_password("password123")
        self.db.add(user)
        self.db.flush()
        return user

    # ---------------------------------------------------------------------------
    # Comments Board Tests
    # ---------------------------------------------------------------------------

    async def test_get_comments_unauthenticated_raises_401(self):
        req = make_request(None)
        with self.assertRaises(HTTPException) as ctx:
            await get_project_comments(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 401)

    async def test_get_comments_project_not_found_raises_404(self):
        req = make_request(self.admin)
        with self.assertRaises(HTTPException) as ctx:
            await get_project_comments(9999, req, self.db)
        self.assertEqual(ctx.exception.status_code, 404)

    async def test_get_comments_unauthorized_intern_raises_403(self):
        req = make_request(self.other_intern)
        with self.assertRaises(HTTPException) as ctx:
            await get_project_comments(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_get_comments_authorized_roles_succeed(self):
        # Seed a comment first
        c = ProjectComment(project_id=self.project.id, user_id=self.intern.id, body="Hello World")
        self.db.add(c)
        self.db.commit()

        for user in [self.admin, self.mentor, self.co_mentor, self.other_mentor, self.intern]:
            req = make_request(user)
            res = await get_project_comments(self.project.id, req, self.db)
            self.assertEqual(len(res), 1)
            self.assertEqual(res[0]["body"], "Hello World")
            self.assertEqual(res[0]["user_name"], self.intern.name)

    async def test_post_comment_empty_body_raises_422(self):
        req = make_request(self.intern, method="POST", body={"body": ""})
        with self.assertRaises(HTTPException) as ctx:
            await create_project_comment(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_post_comment_intern_unauthorized_raises_403(self):
        req = make_request(self.other_intern, method="POST", body={"body": "Hello"})
        with self.assertRaises(HTTPException) as ctx:
            await create_project_comment(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_post_comment_authorized_succeeds(self):
        body = {"body": "My alpha comment"}
        req = make_request(self.intern, method="POST", body=body)
        res = await create_project_comment(self.project.id, req, self.db)
        self.assertEqual(res["body"], "My alpha comment")
        self.assertEqual(res["user_name"], self.intern.name)
        self.assertEqual(res["user_role"], UserRole.INTERN)

        # Verify audit log
        audit = self.db.query(AuditLog).filter_by(action="project.comment", project_id=self.project.id).first()
        self.assertIsNotNone(audit)
        self.assertEqual(audit.actor_name, self.intern.name)
        self.assertEqual(audit.target, self.project.name)

    async def test_delete_comment_author_succeeds(self):
        c = ProjectComment(project_id=self.project.id, user_id=self.intern.id, body="Hello World")
        self.db.add(c)
        self.db.commit()

        req = make_request(self.intern, method="DELETE")
        res = await delete_project_comment(c.id, req, self.db)
        self.assertEqual(res, {"ok": True})

    async def test_delete_comment_mentor_succeeds(self):
        c = ProjectComment(project_id=self.project.id, user_id=self.intern.id, body="Hello World")
        self.db.add(c)
        self.db.commit()

        # Project Mentor
        req = make_request(self.mentor, method="DELETE")
        res = await delete_project_comment(c.id, req, self.db)
        self.assertEqual(res, {"ok": True})

    async def test_delete_comment_co_mentor_succeeds(self):
        c = ProjectComment(project_id=self.project.id, user_id=self.intern.id, body="Hello World")
        self.db.add(c)
        self.db.commit()

        # Co-Mentor
        req = make_request(self.co_mentor, method="DELETE")
        res = await delete_project_comment(c.id, req, self.db)
        self.assertEqual(res, {"ok": True})

    async def test_delete_comment_other_mentor_raises_403(self):
        c = ProjectComment(project_id=self.project.id, user_id=self.intern.id, body="Hello World")
        self.db.add(c)
        self.db.commit()

        # Unassigned Mentor
        req = make_request(self.other_mentor, method="DELETE")
        with self.assertRaises(HTTPException) as ctx:
            await delete_project_comment(c.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    # ---------------------------------------------------------------------------
    # Project Links Tests
    # ---------------------------------------------------------------------------

    async def test_get_links_unauthorized_intern_raises_403(self):
        req = make_request(self.other_intern)
        with self.assertRaises(HTTPException) as ctx:
            await get_project_links(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_get_links_authorized_succeeds(self):
        link = ProjectLink(project_id=self.project.id, user_id=self.intern.id, link="https://google.com", remark="Doc")
        self.db.add(link)
        self.db.commit()

        req = make_request(self.intern)
        res = await get_project_links(self.project.id, req, self.db)
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["link"], "https://google.com")
        self.assertEqual(res[0]["remark"], "Doc")

    async def test_post_link_invalid_url_raises_422(self):
        req = make_request(self.intern, method="POST", body={"link": "not-a-url", "remark": "Test"})
        with self.assertRaises(HTTPException) as ctx:
            await create_project_link(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_post_link_empty_remark_raises_422(self):
        req = make_request(self.intern, method="POST", body={"link": "https://google.com", "remark": ""})
        with self.assertRaises(HTTPException) as ctx:
            await create_project_link(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_post_link_unassigned_raises_403(self):
        req = make_request(self.other_intern, method="POST", body={"link": "https://google.com", "remark": "Test"})
        with self.assertRaises(HTTPException) as ctx:
            await create_project_link(self.project.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_post_link_succeeds(self):
        body = {"link": "https://github.com", "remark": "Repo link"}
        req = make_request(self.intern, method="POST", body=body)
        res = await create_project_link(self.project.id, req, self.db)
        self.assertEqual(res["link"], "https://github.com")
        self.assertEqual(res["remark"], "Repo link")

        # Verify audit log
        audit = self.db.query(AuditLog).filter_by(action="project.link_added", project_id=self.project.id).first()
        self.assertIsNotNone(audit)
        self.assertEqual(audit.actor_name, self.intern.name)
        self.assertEqual(audit.target, "https://github.com")

    async def test_delete_link_submitter_succeeds(self):
        link = ProjectLink(project_id=self.project.id, user_id=self.intern.id, link="https://google.com", remark="Doc")
        self.db.add(link)
        self.db.commit()

        req = make_request(self.intern, method="DELETE")
        res = await delete_project_link(link.id, req, self.db)
        self.assertEqual(res, {"ok": True})

    async def test_delete_link_non_submitter_intern_raises_403(self):
        link = ProjectLink(project_id=self.project.id, user_id=self.intern.id, link="https://google.com", remark="Doc")
        self.db.add(link)
        self.db.commit()

        req = make_request(self.other_intern, method="DELETE")
        with self.assertRaises(HTTPException) as ctx:
            await delete_project_link(link.id, req, self.db)
        self.assertEqual(ctx.exception.status_code, 403)

    async def test_delete_link_mentor_succeeds(self):
        link = ProjectLink(project_id=self.project.id, user_id=self.intern.id, link="https://google.com", remark="Doc")
        self.db.add(link)
        self.db.commit()

        # Mentor can delete
        req = make_request(self.mentor, method="DELETE")
        res = await delete_project_link(link.id, req, self.db)
        self.assertEqual(res, {"ok": True})
