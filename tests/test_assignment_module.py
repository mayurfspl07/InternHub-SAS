import json
import unittest
from datetime import date, timedelta

from fastapi import HTTPException, UploadFile
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request
from io import BytesIO

from database import Base
from dependencies import generate_token
from models import (
    Organization,
    OrganizationMembership,
    Project,
    ProjectAssignment,
    Cohort,
    Assignment,
    AssignmentSubmission,
    User,
    UserRole,
)
from routes.api.assignments import (
    create_assignment,
    delete_assignment,
    get_assignment,
    list_assignment_submissions,
    list_assignments,
    review_submission,
    submit_assignment,
    update_assignment,
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


class TestAssignmentModule(unittest.IsolatedAsyncioTestCase):
    def _user(self, name: str, email: str, role: str, org_id: int) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
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

        self.org = Organization(name="CodeLab", slug="codelab")
        self.db.add(self.org)
        self.db.commit()

        self.mentor = self._user("Mentor Mark", "mark@codelab.com", UserRole.MENTOR, self.org.id)
        self.intern = self._user("Intern Ivy", "ivy@codelab.com", UserRole.INTERN, self.org.id)

        self.project = Project(
            organization_id=self.org.id,
            name="Fullstack App",
            mentor_id=self.mentor.id,
            status="active",
        )
        self.db.add(self.project)
        self.db.flush()
        self.db.add(ProjectAssignment(project_id=self.project.id, user_id=self.intern.id))
        self.db.commit()

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def test_mentor_creates_assignment_and_intern_lists(self):
        create_req = make_request(
            self.mentor,
            "POST",
            payload={
                "title": "Build Authentication API",
                "description": "Implement JWT auth and refresh endpoints.",
                "project_id": self.project.id,
                "due_date": (date.today() + timedelta(days=7)).isoformat(),
                "max_score": 100,
            },
            org_id=self.org.id,
        )
        assignment_data = await create_assignment(create_req, self.db)
        self.assertEqual(assignment_data["title"], "Build Authentication API")
        self.assertEqual(assignment_data["max_score"], 100)

        # Intern views assignment list
        intern_list_req = make_request(self.intern, "GET", org_id=self.org.id)
        intern_res = await list_assignments(intern_list_req, self.db)
        self.assertEqual(len(intern_res["assignments"]), 1)
        self.assertEqual(intern_res["assignments"][0]["title"], "Build Authentication API")
        self.assertFalse(intern_res["assignments"][0]["is_submitted"])

    async def test_assignment_submission_and_mentor_review_flow(self):
        # 1. Create assignment
        assignment = Assignment(
            organization_id=self.org.id,
            title="FastAPI Middleware Task",
            description="Write a custom rate limit middleware.",
            created_by_id=self.mentor.id,
            project_id=self.project.id,
            max_score=50,
            status="active",
        )
        self.db.add(assignment)
        self.db.commit()

        # 2. Intern submits response
        submit_req = make_request(
            self.intern,
            "POST",
            payload={
                "submission_text": "Implemented leaky bucket rate limiter in Python.",
                "github_url": "https://github.com/internivy/rate-limiter",
            },
            org_id=self.org.id,
        )
        submit_res = await submit_assignment(
            assignment.id,
            submit_req,
            self.db,
            submission_text="Implemented leaky bucket rate limiter in Python.",
            github_url="https://github.com/internivy/rate-limiter",
            file=None,
        )
        self.assertTrue(submit_res["success"])
        submission_id = submit_res["submission"]["id"]
        self.assertEqual(submit_res["submission"]["status"], "submitted")

        # 3. Mentor lists submissions
        subs_req = make_request(self.mentor, "GET", org_id=self.org.id)
        subs_list = await list_assignment_submissions(assignment.id, subs_req, self.db)
        self.assertEqual(len(subs_list["submissions"]), 1)

        # 4. Mentor reviews and grades
        review_req = make_request(
            self.mentor,
            "POST",
            payload={
                "score": 48.5,
                "feedback": "Excellent design and comprehensive unit test coverage.",
                "status": "approved",
            },
            org_id=self.org.id,
        )
        review_res = await review_submission(submission_id, review_req, self.db)
        self.assertTrue(review_res["success"])
        self.assertEqual(review_res["submission"]["score"], 48.5)
        self.assertEqual(review_res["submission"]["status"], "approved")

        # 5. Intern checks detail and sees updated score
        get_req = make_request(self.intern, "GET", org_id=self.org.id)
        detail = await get_assignment(assignment.id, get_req, self.db)
        self.assertTrue(detail["is_submitted"])
        self.assertEqual(detail["my_score"], 48.5)
        self.assertEqual(detail["submission_status"], "approved")
