import json
import unittest
from datetime import date

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
    Project,
    ProjectAssignment,
    Task,
    User,
    UserRole,
)
from routes.api.admin import (
    create_task_status,
    delete_task_status,
    list_task_statuses,
    reorder_task_statuses,
    update_task_status as admin_update_task_status,
)
from routes.api.projects import (
    create_task,
    get_project,
    get_project_task_statuses,
    update_task,
    update_task_status,
)
from utils import get_or_seed_org_task_statuses, get_org_done_statuses


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
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }
    return Request(scope, receive)


class TaskStatusMasterTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()

        # Create Organizations
        self.org1 = Organization(name="TechCorp", slug="techcorp")
        self.org2 = Organization(name="InnovateInc", slug="innovateinc")
        self.db.add_all([self.org1, self.org2])
        self.db.commit()

        # Users
        self.admin = self._user("Admin User", "admin@techcorp.com", UserRole.ADMIN, self.org1.id)
        self.mentor = self._user("Mentor User", "mentor@techcorp.com", UserRole.MENTOR, self.org1.id)
        self.intern = self._user("Intern User", "intern@techcorp.com", UserRole.INTERN, self.org1.id)
        
        self.org2_admin = self._user("Org2 Admin", "admin@innovateinc.com", UserRole.ADMIN, self.org2.id)

        # Project in org1
        self.project = Project(
            organization_id=self.org1.id,
            name="Alpha Project",
            description="Test Project",
            mentor_id=self.mentor.id,
        )
        self.db.add(self.project)
        self.db.commit()
        self.db.add(ProjectAssignment(project_id=self.project.id, user_id=self.intern.id))
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

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

    async def test_default_status_seeding(self):
        """Verify default status buckets are auto-seeded for an organization."""
        buckets = get_or_seed_org_task_statuses(self.db, self.org1.id)
        self.assertEqual(len(buckets), 4)
        slugs = [b.slug for b in buckets]
        self.assertIn("todo", slugs)
        self.assertIn("in_progress", slugs)
        self.assertIn("review", slugs)
        self.assertIn("done", slugs)

        default_bucket = next((b for b in buckets if b.is_default), None)
        self.assertIsNotNone(default_bucket)
        self.assertEqual(default_bucket.slug, "todo")

        done_statuses = get_org_done_statuses(self.db, self.org1.id)
        self.assertIn("done", done_statuses)

    async def test_admin_list_and_create_custom_status(self):
        """Admin can list and create custom status buckets."""
        req_list = make_request(self.admin, method="GET", org_id=self.org1.id)
        res_list = await list_task_statuses(request=req_list, db=self.db)
        self.assertTrue(len(res_list["statuses"]) >= 4)

        # Create new custom status bucket "QA / Testing"
        req_create = make_request(
            self.admin,
            method="POST",
            payload={
                "name": "QA / Testing",
                "color": "#8B5CF6",
                "status_category": "in_progress",
            },
            org_id=self.org1.id,
        )
        new_status = await create_task_status(request=req_create, db=self.db)
        self.assertEqual(new_status["name"], "QA / Testing")
        self.assertEqual(new_status["slug"], "qa_testing")
        self.assertEqual(new_status["color"], "#8B5CF6")
        self.assertEqual(new_status["status_category"], "in_progress")

    async def test_admin_update_and_reorder_statuses(self):
        """Admin can update status properties and reorder buckets."""
        buckets = get_or_seed_org_task_statuses(self.db, self.org1.id)
        review_bucket = next(b for b in buckets if b.slug == "review")

        # Update Review bucket to "Code Review"
        req_update = make_request(
            self.admin,
            method="PUT",
            payload={"name": "Code Review", "color": "#EAB308"},
            org_id=self.org1.id,
        )
        updated = await admin_update_task_status(
            status_id=review_bucket.id, request=req_update, db=self.db
        )
        self.assertEqual(updated["name"], "Code Review")
        self.assertEqual(updated["color"], "#EAB308")

        # Reorder buckets
        all_ids = [b.id for b in buckets]
        reversed_ids = list(reversed(all_ids))
        req_reorder = make_request(
            self.admin,
            method="PUT",
            payload={"status_ids": reversed_ids},
            org_id=self.org1.id,
        )
        reordered = await reorder_task_statuses(request=req_reorder, db=self.db)
        returned_ids = [s["id"] for s in reordered["statuses"]]
        self.assertEqual(returned_ids, reversed_ids)

    async def test_admin_delete_status_safety_guard(self):
        """Deleting a bucket with active tasks fails with 422; unused succeeds."""
        buckets = get_or_seed_org_task_statuses(self.db, self.org1.id)
        in_prog_bucket = next(b for b in buckets if b.slug == "in_progress")

        # Assign a task with status 'in_progress'
        task = Task(
            project_id=self.project.id,
            organization_id=self.org1.id,
            created_by_id=self.admin.id,
            title="Active Task in Progress",
            status="in_progress",
        )
        self.db.add(task)
        self.db.commit()

        # Attempt to delete 'in_progress' bucket
        req_del = make_request(self.admin, method="DELETE", org_id=self.org1.id)
        with self.assertRaises(HTTPException) as ctx:
            await delete_task_status(
                status_id=in_prog_bucket.id, request=req_del, db=self.db
            )
        self.assertEqual(ctx.exception.status_code, 422)
        self.assertIn("active task(s)", ctx.exception.detail)

        # Create an unused bucket and delete it successfully
        req_create = make_request(
            self.admin,
            method="POST",
            payload={"name": "Temporary Bucket", "status_category": "in_progress"},
            org_id=self.org1.id,
        )
        temp_status = await create_task_status(request=req_create, db=self.db)
        temp_id = temp_status["id"]

        req_del_temp = make_request(self.admin, method="DELETE", org_id=self.org1.id)
        del_res = await delete_task_status(
            status_id=temp_id, request=req_del_temp, db=self.db
        )
        self.assertTrue(del_res["success"])

    async def test_task_workflow_and_dynamic_validation(self):
        """Tasks default to default bucket, and transitions validate against org buckets."""
        # 1. Create task without status -> defaults to default bucket ("todo")
        req_create = make_request(
            self.mentor,
            method="POST",
            payload={"title": "New Workflow Task", "assigned_to": self.intern.id},
            org_id=self.org1.id,
        )
        task_data = await create_task(
            project_id=self.project.id, request=req_create, db=self.db
        )
        self.assertEqual(task_data["status"], "todo")
        task_id = task_data["id"]

        # 2. Update status to "review"
        req_patch = make_request(
            self.intern,
            method="PATCH",
            payload={"status": "review"},
            org_id=self.org1.id,
        )
        patched = await update_task_status(
            task_id=task_id, request=req_patch, db=self.db
        )
        self.assertEqual(patched["status"], "review")

        # 3. Invalid status rejected with 422
        req_invalid = make_request(
            self.intern,
            method="PATCH",
            payload={"status": "non_existent_status"},
            org_id=self.org1.id,
        )
        with self.assertRaises(HTTPException) as ctx:
            await update_task_status(
                task_id=task_id, request=req_invalid, db=self.db
            )
        self.assertEqual(ctx.exception.status_code, 422)

    async def test_project_metrics_with_custom_done_status(self):
        """Project task_done count dynamically includes all buckets with category 'done'."""
        # Create custom status bucket "Shipped" with category 'done'
        req_create = make_request(
            self.admin,
            method="POST",
            payload={"name": "Shipped", "status_category": "done"},
            org_id=self.org1.id,
        )
        shipped_status = await create_task_status(request=req_create, db=self.db)
        shipped_slug = shipped_status["slug"]

        # Create 1 task with 'todo' and 1 task with 'shipped'
        t1 = Task(
            project_id=self.project.id,
            organization_id=self.org1.id,
            created_by_id=self.mentor.id,
            title="Task 1",
            status="todo",
        )
        t2 = Task(
            project_id=self.project.id,
            organization_id=self.org1.id,
            created_by_id=self.mentor.id,
            title="Task 2",
            status=shipped_slug,
        )
        self.db.add_all([t1, t2])
        self.db.commit()

        # Check project details
        req_proj = make_request(self.mentor, method="GET", org_id=self.org1.id)
        proj_data = await get_project(
            project_id=self.project.id, request=req_proj, db=self.db
        )
        self.assertEqual(proj_data["task_total"], 2)
        self.assertEqual(proj_data["task_done"], 1)

    async def test_tenant_isolation_of_status_buckets(self):
        """Organization 1 and Organization 2 maintain completely independent status buckets."""
        # Org 1 custom bucket
        req_create_1 = make_request(
            self.admin,
            method="POST",
            payload={"name": "Org 1 Specific", "status_category": "in_progress"},
            org_id=self.org1.id,
        )
        await create_task_status(request=req_create_1, db=self.db)

        # Org 2 list
        req_list_2 = make_request(self.org2_admin, method="GET", org_id=self.org2.id)
        res_2 = await list_task_statuses(request=req_list_2, db=self.db)
        slugs_2 = [s["slug"] for s in res_2["statuses"]]
        self.assertNotIn("org_1_specific", slugs_2)
