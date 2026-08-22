import json
import unittest

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import Project, ProjectMentorAssignment, User, UserRole
from routes.api.projects import create_project, get_project, list_projects, update_project


def make_request(user: User, method: str, payload: dict | None = None, query_string: bytes = b"") -> Request:
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
            "path": "/api/projects",
            "raw_path": b"/api/projects",
            "query_string": query_string,
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        },
        receive,
    )


class ProjectMultiMentorTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.admin = self._user("Admin", "admin@multi.test", UserRole.ADMIN)
        self.mentor1 = self._user("Mentor 1", "mentor1@multi.test", UserRole.MENTOR)
        self.mentor2 = self._user("Mentor 2", "mentor2@multi.test", UserRole.MENTOR)
        self.mentor3 = self._user("Mentor 3", "mentor3@multi.test", UserRole.MENTOR)
        self.intern = self._user("Intern", "intern@multi.test", UserRole.INTERN)
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

    async def test_create_with_multiple_mentors_returns_all_in_detail(self):
        created = await create_project(
            make_request(
                self.admin,
                "POST",
                {
                    "name": "Multi mentor project",
                    "mentor_ids": [self.mentor1.id, self.mentor2.id, self.mentor3.id],
                },
            ),
            self.db,
        )
        self.assertEqual(created["mentor_id"], self.mentor1.id)
        self.assertEqual(created["mentor_ids"], [self.mentor1.id, self.mentor2.id, self.mentor3.id])
        self.assertEqual(len(created["mentors"]), 3)
        self.assertEqual({m["id"] for m in created["mentors"]}, {
            self.mentor1.id,
            self.mentor2.id,
            self.mentor3.id,
        })

        detail = await get_project(
            created["id"],
            make_request(self.admin, "GET"),
            self.db,
        )
        self.assertEqual(detail["mentor_ids"], created["mentor_ids"])
        self.assertEqual(len(detail["mentors"]), 3)

    async def test_update_adds_and_removes_mentors(self):
        created = await create_project(
            make_request(
                self.admin,
                "POST",
                {
                    "name": "Mutable mentors",
                    "mentor_ids": [self.mentor1.id, self.mentor2.id],
                },
            ),
            self.db,
        )
        updated = await update_project(
            created["id"],
            make_request(
                self.admin,
                "PUT",
                {
                    "name": "Mutable mentors",
                    "mentor_ids": [self.mentor2.id, self.mentor3.id],
                },
            ),
            self.db,
        )
        self.assertEqual(updated["mentor_id"], self.mentor2.id)
        self.assertEqual(updated["mentor_ids"], [self.mentor2.id, self.mentor3.id])
        self.assertEqual({m["id"] for m in updated["mentors"]}, {self.mentor2.id, self.mentor3.id})

        rows = (
            self.db.query(ProjectMentorAssignment.user_id)
            .filter_by(project_id=created["id"])
            .all()
        )
        self.assertEqual({row[0] for row in rows}, {self.mentor2.id, self.mentor3.id})

    async def test_list_filter_by_co_mentor_returns_project(self):
        created = await create_project(
            make_request(
                self.admin,
                "POST",
                {
                    "name": "Filter me",
                    "mentor_ids": [self.mentor1.id, self.mentor2.id],
                },
            ),
            self.db,
        )
        response = await list_projects(
            make_request(
                self.admin,
                "GET",
                query_string=f"mentor_id={self.mentor2.id}".encode(),
            ),
            self.db,
        )
        project_ids = {project["id"] for project in response["projects"]}
        self.assertIn(created["id"], project_ids)

    async def test_legacy_mentor_id_only_still_works(self):
        created = await create_project(
            make_request(
                self.admin,
                "POST",
                {"name": "Legacy mentor", "mentor_id": self.mentor1.id},
            ),
            self.db,
        )
        self.assertEqual(created["mentor_id"], self.mentor1.id)
        self.assertEqual(created["mentor_ids"], [self.mentor1.id])
        self.assertEqual(len(created["mentors"]), 1)

    async def test_mentor_can_assign_self_and_other_mentors_on_create(self):
        created = await create_project(
            make_request(
                self.mentor1,
                "POST",
                {
                    "name": "Mentor created",
                    "mentor_ids": [self.mentor1.id, self.mentor2.id],
                },
            ),
            self.db,
        )
        self.assertEqual(created["mentor_ids"], [self.mentor1.id, self.mentor2.id])

    async def test_admin_sees_all_projects_and_mentor_sees_only_own(self):
        # Create Project 1 assigned to Mentor 1
        p1 = await create_project(
            make_request(
                self.admin,
                "POST",
                {"name": "Mentor1 Project", "mentor_ids": [self.mentor1.id]},
            ),
            self.db,
        )
        # Create Project 2 assigned to Mentor 2
        p2 = await create_project(
            make_request(
                self.admin,
                "POST",
                {"name": "Mentor2 Project", "mentor_ids": [self.mentor2.id]},
            ),
            self.db,
        )

        # 1. Admin must see both projects
        admin_resp = await list_projects(make_request(self.admin, "GET"), self.db)
        admin_pids = {p["id"] for p in admin_resp["projects"]}
        self.assertIn(p1["id"], admin_pids)
        self.assertIn(p2["id"], admin_pids)

        # 2. Mentor 1 must see only Project 1 (not Project 2)
        m1_resp = await list_projects(make_request(self.mentor1, "GET"), self.db)
        m1_pids = {p["id"] for p in m1_resp["projects"]}
        self.assertIn(p1["id"], m1_pids)
        self.assertNotIn(p2["id"], m1_pids)

        # 3. Mentor 2 must see only Project 2 (not Project 1)
        m2_resp = await list_projects(make_request(self.mentor2, "GET"), self.db)
        m2_pids = {p["id"] for p in m2_resp["projects"]}
        self.assertIn(p2["id"], m2_pids)
        self.assertNotIn(p1["id"], m2_pids)


if __name__ == "__main__":
    unittest.main()
