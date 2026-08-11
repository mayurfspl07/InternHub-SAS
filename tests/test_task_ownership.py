import json
import unittest

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Project, ProjectAssignment, Task, User, UserRole
from routes.api.projects import create_task, delete_task, get_project, task_router


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


class TaskOwnershipTests(unittest.IsolatedAsyncioTestCase):
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
        self.other_mentor = self._user(
            "Other Mentor", "other-mentor@test.local", UserRole.MENTOR
        )
        self.intern = self._user("Intern One", "intern1@test.local", UserRole.INTERN)
        self.other_intern = self._user(
            "Intern Two", "intern2@test.local", UserRole.INTERN
        )
        self.project = Project(name="Ownership Project", mentor_id=self.mentor.id)
        self.db.add(self.project)
        self.db.flush()
        self.db.add_all(
            [
                ProjectAssignment(project_id=self.project.id, user_id=self.intern.id),
                ProjectAssignment(
                    project_id=self.project.id, user_id=self.other_intern.id
                ),
            ]
        )
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _user(self, name: str, email: str, role: str) -> User:
        user = User(name=name, email=email, role=role, is_active=True)
        user.set_password("test-password-1")
        self.db.add(user)
        self.db.flush()
        return user

    def _task(
        self,
        *,
        creator: User | None,
        assignee: User | None = None,
        title: str = "Test task",
    ) -> Task:
        task = Task(
            project_id=self.project.id,
            created_by_id=creator.id if creator else None,
            assigned_to=assignee.id if assignee else None,
            title=title,
        )
        self.db.add(task)
        self.db.commit()
        return task

    async def _assert_forbidden(self, user: User, task: Task):
        with self.assertRaises(HTTPException) as raised:
            await delete_task(
                task.id, make_request(user, "DELETE"), self.db
            )
        self.assertEqual(raised.exception.status_code, 403)
        self.db.refresh(task)
        self.assertFalse(task.is_deleted)

    async def test_intern_creates_and_deletes_own_task(self):
        response = await create_task(
            self.project.id,
            make_request(self.intern, "POST", {"title": "My task"}),
            self.db,
        )
        self.assertEqual(response["created_by_id"], self.intern.id)
        self.assertEqual(response["created_by_name"], self.intern.name)
        self.assertTrue(response["can_delete"])

        result = await delete_task(
            response["id"], make_request(self.intern, "DELETE"), self.db
        )

        self.assertEqual(result, {"ok": True})
        task = self.db.get(Task, response["id"])
        self.assertTrue(task.is_deleted)

    async def test_intern_cannot_delete_another_interns_task(self):
        task = self._task(creator=self.other_intern)
        await self._assert_forbidden(self.intern, task)

    async def test_assignment_does_not_grant_intern_delete_access(self):
        task = self._task(creator=self.other_intern, assignee=self.intern)
        project_response = await get_project(
            self.project.id, make_request(self.intern, "GET"), self.db
        )
        returned_task = next(
            item for item in project_response["tasks"] if item["id"] == task.id
        )
        self.assertFalse(returned_task["can_delete"])
        await self._assert_forbidden(self.intern, task)

    async def test_intern_cannot_spoof_creator_and_responses_include_creator(self):
        response = await create_task(
            self.project.id,
            make_request(
                self.intern,
                "POST",
                {
                    "title": "Spoof attempt",
                    "created_by_id": self.other_intern.id,
                },
            ),
            self.db,
        )
        self.assertEqual(response["created_by_id"], self.intern.id)
        self.assertEqual(response["created_by_name"], self.intern.name)
        self.assertTrue(response["can_delete"])

        project_response = await get_project(
            self.project.id, make_request(self.intern, "GET"), self.db
        )
        returned_task = next(
            task for task in project_response["tasks"] if task["id"] == response["id"]
        )
        self.assertEqual(returned_task["created_by_id"], self.intern.id)
        self.assertEqual(returned_task["created_by_name"], self.intern.name)
        self.assertTrue(returned_task["can_delete"])

        other_intern_response = await get_project(
            self.project.id, make_request(self.other_intern, "GET"), self.db
        )
        other_intern_task = next(
            task
            for task in other_intern_response["tasks"]
            if task["id"] == response["id"]
        )
        self.assertFalse(other_intern_task["can_delete"])

    async def test_admin_and_authorized_mentor_can_delete(self):
        admin_task = self._task(creator=self.other_intern, title="Admin delete")
        mentor_task = self._task(creator=self.other_intern, title="Mentor delete")

        self.assertEqual(
            await delete_task(
                admin_task.id, make_request(self.admin, "DELETE"), self.db
            ),
            {"ok": True},
        )
        self.assertEqual(
            await delete_task(
                mentor_task.id, make_request(self.mentor, "DELETE"), self.db
            ),
            {"ok": True},
        )

    async def test_unauthorized_mentor_receives_403(self):
        task = self._task(creator=self.intern)
        await self._assert_forbidden(self.other_mentor, task)

    async def test_missing_task_returns_404(self):
        with self.assertRaises(HTTPException) as raised:
            await delete_task(
                999999, make_request(self.admin, "DELETE"), self.db
            )
        self.assertEqual(raised.exception.status_code, 404)

    def test_canonical_delete_route_is_registered(self):
        self.assertTrue(
            any(
                route.path == "/api/tasks/{task_id}"
                and "DELETE" in route.methods
                for route in task_router.routes
            )
        )


if __name__ == "__main__":
    unittest.main()
