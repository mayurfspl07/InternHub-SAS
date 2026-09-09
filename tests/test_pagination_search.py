"""Task 2 tests: pagination + search on list endpoints.

Covers:
- response envelope shape {items, page, page_size, total, total_pages}
- pagination bounds (page<1 -> 1, page_size>100 -> 100)
- search filtering
- empty pages (page beyond range -> [])
- unbounded dumps are no longer returned when page_size is set
- announcements pinned filter, reviews rating/project filters, cohort member trimming
- assignments aggregate counts
"""
import json
import unittest
from datetime import datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from database import Base
from dependencies import generate_token
from models import (
    Announcement,
    Assignment,
    AssignmentStatus,
    AssignmentSubmission,
    AssignmentSubmissionStatus,
    Cohort,
    CohortMember,
    Organization,
    OrganizationMembership,
    PerformanceReview,
    Project,
    User,
    UserRole,
    _utcnow,
)
from routes.api.announcements import list_announcements
from routes.api.assignments import list_assignments
from routes.api.cohorts import list_cohorts
from routes.api.projects import get_project_interns, get_project_mentors
from routes.api.reviews import list_reviews


def make_request(
    user: User,
    method: str = "GET",
    payload: dict | None = None,
    query_params: dict | None = None,
    path: str = "/",
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
        "path": path,
        "raw_path": path.encode(),
        "query_string": query_str.encode(),
        "headers": headers,
    }
    return Request(scope, receive)


class PaginationTestCase(unittest.IsolatedAsyncioTestCase):
    def _user(self, name: str, email: str, role: str, mentor_id: int | None = None) -> User:
        user = User(
            name=name,
            email=email,
            password_hash="test-hash",
            role=role,
            is_active=True,
            mentor_id=mentor_id,
            session_version=1,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        self.db.add(
            OrganizationMembership(
                organization_id=self.org.id, user_id=user.id, role=role, is_active=True
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

        self.org = Organization(name="PageTest Org", slug="pagetest")
        self.db.add(self.org)
        self.db.commit()

        self.admin = self._user("Admin P", "admin@pagetest.com", UserRole.ADMIN)
        self.mentor = self._user("Mentor P", "mentor@pagetest.com", UserRole.MENTOR)
        self.intern = self._user("Intern P", "intern@pagetest.com", UserRole.INTERN, mentor_id=self.mentor.id)

        self.project = Project(
            name="Page Project", description="", organization_id=self.org.id, mentor_id=self.mentor.id
        )
        self.db.add(self.project)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)


class TestAnnouncementsPagination(PaginationTestCase):
    def _seed(self, n=5, pinned_first=False):
        for i in range(n):
            self.db.add(
                Announcement(
                    organization_id=self.org.id,
                    title=f"Ann {i}",
                    body=f"Body {i}",
                    is_pinned=pinned_first and i == 0,
                    author_id=self.admin.id,
                    project_id=None if i % 2 else self.project.id,
                )
            )
        self.db.commit()

    async def test_envelope_and_page_size_cap(self):
        self._seed(5)
        req = make_request(self.admin, query_params={"page": "1", "page_size": "3"})
        res = await list_announcements(req, self.db)
        self.assertEqual(set(res.keys()), {"items", "page", "page_size", "total", "total_pages"})
        self.assertEqual(len(res["items"]), 3)
        self.assertEqual(res["total"], 5)
        self.assertEqual(res["page"], 1)
        self.assertEqual(res["page_size"], 3)
        self.assertEqual(res["total_pages"], 2)

    async def test_unbounded_dump_no_longer_returned(self):
        self._seed(5)
        req = make_request(self.admin, query_params={"page": "1", "page_size": "5000"})
        res = await list_announcements(req, self.db)
        self.assertEqual(res["page_size"], 100)
        self.assertLessEqual(len(res["items"]), 100)
        self.assertEqual(res["total"], 5)

    async def test_page_bounds(self):
        self._seed(3)
        req = make_request(self.admin, query_params={"page": "0", "page_size": "2"})
        res = await list_announcements(req, self.db)
        self.assertEqual(res["page"], 1)
        self.assertEqual(len(res["items"]), 2)

    async def test_empty_page_beyond_range(self):
        self._seed(3)
        req = make_request(self.admin, query_params={"page": "10", "page_size": "2"})
        res = await list_announcements(req, self.db)
        self.assertEqual(res["items"], [])
        self.assertEqual(res["total"], 3)

    async def test_search(self):
        self._seed(3)
        req = make_request(self.admin, query_params={"search": "Ann 1"})
        res = await list_announcements(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["items"][0]["title"], "Ann 1")

    async def test_pinned_filter(self):
        self._seed(3, pinned_first=True)
        req_true = make_request(self.admin, query_params={"pinned": "true"})
        res_true = await list_announcements(req_true, self.db)
        self.assertEqual(res_true["total"], 1)
        self.assertTrue(res_true["items"][0]["is_pinned"])

        req_false = make_request(self.admin, query_params={"pinned": "false"})
        res_false = await list_announcements(req_false, self.db)
        self.assertEqual(res_false["total"], 2)

    async def test_project_id_filter(self):
        self._seed(4)
        req = make_request(self.admin, query_params={"project_id": str(self.project.id)})
        res = await list_announcements(req, self.db)
        self.assertEqual(res["total"], 2)
        for item in res["items"]:
            self.assertEqual(item["project_id"], self.project.id)


class TestReviewsPagination(PaginationTestCase):
    def _seed(self, n=5):
        for i in range(n):
            self.db.add(
                PerformanceReview(
                    organization_id=self.org.id,
                    intern_id=self.intern.id,
                    reviewer_id=self.mentor.id,
                    project_id=self.project.id,
                    period=f"2026-{i + 1:02d}",
                    rating=(i % 5) + 1,
                    feedback=f"Feedback {i}",
                )
            )
        self.db.commit()

    async def test_envelope(self):
        self._seed(5)
        req = make_request(self.admin, query_params={"page": "1", "page_size": "2"})
        res = await list_reviews(req, self.db)
        self.assertEqual(set(res.keys()), {"items", "page", "page_size", "total", "total_pages"})
        self.assertEqual(len(res["items"]), 2)
        self.assertEqual(res["total"], 5)

    async def test_rating_filter(self):
        self._seed(5)
        req = make_request(self.admin, query_params={"rating": "3"})
        res = await list_reviews(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["items"][0]["rating"], 3)

    async def test_search_matches_feedback(self):
        self._seed(5)
        req = make_request(self.admin, query_params={"search": "Feedback 2"})
        res = await list_reviews(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["items"][0]["feedback"], "Feedback 2")

    async def test_search_matches_intern_name(self):
        self._seed(2)
        req = make_request(self.admin, query_params={"search": "Intern P"})
        res = await list_reviews(req, self.db)
        self.assertEqual(res["total"], 2)

    async def test_project_filter(self):
        self._seed(3)
        req = make_request(self.admin, query_params={"project_id": str(self.project.id)})
        res = await list_reviews(req, self.db)
        self.assertEqual(res["total"], 3)

    async def test_empty_result(self):
        req = make_request(self.admin, query_params={"search": "nothing-matches"})
        res = await list_reviews(req, self.db)
        self.assertEqual(res["items"], [])
        self.assertEqual(res["total"], 0)
        self.assertEqual(res["total_pages"], 1)


class TestCohortsPagination(PaginationTestCase):
    async def test_envelope_and_no_nested_members(self):
        for i in range(3):
            cohort = Cohort(
                organization_id=self.org.id,
                name=f"Cohort {i}",
                description=f"Desc {i}",
                created_by_id=self.admin.id,
            )
            self.db.add(cohort)
            self.db.commit()
            self.db.add(CohortMember(cohort_id=cohort.id, user_id=self.intern.id))
            self.db.commit()

        req = make_request(self.admin, query_params={"page": "1", "page_size": "2"})
        res = await list_cohorts(req, self.db)
        self.assertEqual(set(res.keys()), {"items", "page", "page_size", "total", "total_pages"})
        self.assertEqual(len(res["items"]), 2)
        self.assertEqual(res["total"], 3)
        # List items are lightweight: member_count kept, members array dropped
        self.assertNotIn("members", res["items"][0])
        self.assertEqual(res["items"][0]["member_count"], 1)

    async def test_search(self):
        self.db.add(Cohort(organization_id=self.org.id, name="Alpha Team", created_by_id=self.admin.id))
        self.db.add(Cohort(organization_id=self.org.id, name="Beta Team", created_by_id=self.admin.id))
        self.db.commit()
        req = make_request(self.admin, query_params={"search": "beta"})
        res = await list_cohorts(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["items"][0]["name"], "Beta Team")

    async def test_intern_sees_only_member_cohorts(self):
        c1 = Cohort(organization_id=self.org.id, name="Mine", created_by_id=self.admin.id)
        c2 = Cohort(organization_id=self.org.id, name="Not Mine", created_by_id=self.admin.id)
        self.db.add_all([c1, c2])
        self.db.commit()
        self.db.add(CohortMember(cohort_id=c1.id, user_id=self.intern.id))
        self.db.commit()
        req = make_request(self.intern, query_params={"page_size": "50"})
        res = await list_cohorts(req, self.db)
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["items"][0]["name"], "Mine")


class TestAssignmentsPagination(PaginationTestCase):
    def _seed(self):
        for i in range(6):
            self.db.add(
                Assignment(
                    organization_id=self.org.id,
                    title=f"Assignment {i}",
                    description=f"Desc {i}",
                    created_by_id=self.admin.id,
                    status=AssignmentStatus.ACTIVE if i < 4 else AssignmentStatus.CLOSED,
                )
            )
        self.db.add(
            AssignmentSubmission(
                assignment_id=1,
                user_id=self.intern.id,
                status=AssignmentSubmissionStatus.SUBMITTED,
            )
        )
        self.db.commit()

    async def test_envelope_and_counts(self):
        self._seed()
        req = make_request(self.admin, query_params={"page": "1", "page_size": "4"})
        res = await list_assignments(req, self.db, None, None, None, None, None)
        self.assertEqual(res["total"], 6)
        self.assertEqual(len(res["items"]), 4)
        self.assertEqual(res["page_size"], 4)
        counts = res["counts"]
        self.assertEqual(counts["active"], 4)
        self.assertEqual(counts["closed"], 2)
        self.assertEqual(counts["all"], 6)
        self.assertEqual(counts["pending_reviews"], 1)

    async def test_search_and_status_filter(self):
        self._seed()
        req = make_request(self.admin, query_params={"search": "Assignment 5"})
        res = await list_assignments(req, self.db, None, None, None, None, "Assignment 5")
        self.assertEqual(res["total"], 1)
        self.assertEqual(res["items"][0]["status"], "closed")

        req2 = make_request(self.admin, query_params={"status": "active", "page_size": "10"})
        res2 = await list_assignments(req2, self.db, "active", None, None, None, None)
        self.assertEqual(res2["total"], 4)

    async def test_page_size_cap(self):
        self._seed()
        req = make_request(self.admin, query_params={"page_size": "9999"})
        res = await list_assignments(req, self.db, None, None, None, None, None)
        self.assertEqual(res["page_size"], 100)


class TestProjectPeoplePagination(PaginationTestCase):
    def _seed(self):
        for i in range(4):
            self._user(f"Extra Intern {i}", f"extra_intern{i}@pagetest.com", UserRole.INTERN)
        for i in range(2):
            self._user(f"Extra Mentor {i}", f"extra_mentor{i}@pagetest.com", UserRole.MENTOR)

    async def test_interns_envelope_and_search(self):
        self._seed()
        req = make_request(self.admin, query_params={"page": "1", "page_size": "2"})
        res = await get_project_interns(req, self.db)
        self.assertEqual(set(res.keys()), {"items", "page", "page_size", "total", "total_pages", "interns", "total"})
        self.assertEqual(len(res["items"]), 2)
        self.assertEqual(res["total"], 5)  # intern P + 4 extras
        self.assertEqual(res["interns"], res["items"])

        req_search = make_request(self.admin, query_params={"search": "Extra Intern 1"})
        res_search = await get_project_interns(req_search, self.db)
        self.assertEqual(res_search["total"], 1)
        self.assertEqual(res_search["items"][0]["name"], "Extra Intern 1")

    async def test_mentors_envelope_and_search(self):
        self._seed()
        req = make_request(self.admin, query_params={"page_size": "10"})
        res = await get_project_mentors(req, self.db)
        self.assertEqual(res["total"], 3)  # mentor P + 2 extras
        self.assertEqual(len(res["items"]), 3)
        self.assertEqual(res["mentors"], res["items"])

        req_search = make_request(self.admin, query_params={"search": "Mentor P"})
        res_search = await get_project_mentors(req_search, self.db)
        self.assertEqual(res_search["total"], 1)
        self.assertEqual(res_search["items"][0]["name"], "Mentor P")

    async def test_page_size_capped(self):
        self._seed()
        req = make_request(self.admin, query_params={"page_size": "10000"})
        res = await get_project_interns(req, self.db)
        self.assertEqual(res["page_size"], 100)


if __name__ == "__main__":
    unittest.main()
