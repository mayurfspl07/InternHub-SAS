"""
Systematic Role-Based Access Control (RBAC) Test Suite.
Tests each and every role in InternHub:
1. Platform Super Admin (is_platform_admin=True / role='superadmin')
2. Organization Admin (role='admin')
3. Mentor / Faculty (role='mentor')
4. Intern / Student (role='intern')
5. Anonymous / Unauthenticated User
"""
from datetime import date, datetime, timedelta
import io
import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Announcement,
    Assignment,
    AssignmentSubmission,
    Attendance,
    AttendanceStatus,
    Cohort,
    LeaveRequest,
    LeaveStatus,
    LeaveType,
    Organization,
    OrganizationMembership,
    OrganizationSettings,
    OrganizationStatus,
    OrganizationType,
    PerformanceReview,
    Project,
    ProjectAssignment,
    StandupLog,
    Task,
    TaskPriority,
    TaskStatus,
    User,
    UserRole,
    _utcnow,
)


@pytest.fixture(scope="module")
def rbac_env():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    db = TestingSessionLocal()

    # 1. Organization & Settings
    org = Organization(
        id=1,
        slug="globalcorp",
        name="Global Corp",
        type=OrganizationType.BUSINESS,
        status=OrganizationStatus.ACTIVE,
    )
    db.add(org)
    db.flush()

    settings = OrganizationSettings(
        organization_id=org.id,
        shift_start="09:00",
        shift_end="18:00",
        late_cutoff="09:30",
        leave_quota_days=15,
        full_day_hours=8.0,
        half_day_hours=4.0,
        auto_checkout_enabled=True,
    )
    db.add(settings)

    # 2. Roles: Super Admin, Org Admin, Mentor, Intern
    super_admin = User(
        name="Super Admin User",
        email="superadmin@globalcorp.com",
        role=UserRole.SUPERADMIN,
        is_platform_admin=True,
        is_active=True,
        activated_at=_utcnow(),
    )
    super_admin.set_password("SuperSecret123!")

    org_admin = User(
        name="Org Admin User",
        email="admin@globalcorp.com",
        role=UserRole.ADMIN,
        is_active=True,
        activated_at=_utcnow(),
    )
    org_admin.set_password("AdminPass123!")

    mentor = User(
        name="Mentor User",
        email="mentor@globalcorp.com",
        role=UserRole.MENTOR,
        is_active=True,
        activated_at=_utcnow(),
    )
    mentor.set_password("MentorPass123!")

    intern = User(
        name="Intern User",
        email="intern@globalcorp.com",
        role=UserRole.INTERN,
        is_active=True,
        mentor_id=mentor.id,
        activated_at=_utcnow(),
    )
    intern.set_password("InternPass123!")

    db.add_all([super_admin, org_admin, mentor, intern])
    db.flush()

    # 3. Memberships
    mem_admin = OrganizationMembership(organization_id=org.id, user_id=org_admin.id, role=UserRole.ADMIN)
    mem_mentor = OrganizationMembership(organization_id=org.id, user_id=mentor.id, role=UserRole.MENTOR)
    mem_intern = OrganizationMembership(
        organization_id=org.id,
        user_id=intern.id,
        role=UserRole.INTERN,
        mentor_membership_id=mem_mentor.id,
    )
    db.add_all([mem_admin, mem_mentor, mem_intern])
    db.flush()

    # 4. Project & Task
    project = Project(
        organization_id=org.id,
        name="Fintech Platform",
        description="Core banking integration",
        mentor_id=mentor.id,
        status="active",
    )
    db.add(project)
    db.flush()

    assignment_proj = ProjectAssignment(project_id=project.id, user_id=intern.id)
    db.add(assignment_proj)
    db.flush()

    task = Task(
        organization_id=org.id,
        project_id=project.id,
        created_by_id=mentor.id,
        assigned_to=intern.id,
        title="Setup Stripe Webhooks",
        description="Verify webhook signatures",
        status=TaskStatus.TODO,
        priority=TaskPriority.HIGH,
    )
    db.add(task)

    # 5. Leave Request for review testing
    leave_req = LeaveRequest(
        organization_id=org.id,
        user_id=intern.id,
        start_date=date.today() + timedelta(days=10),
        end_date=date.today() + timedelta(days=11),
        leave_type=LeaveType.CASUAL,
        reason="Semester Examination",
        status=LeaveStatus.PENDING,
    )
    db.add(leave_req)

    # 6. Assignment module assignment
    asgn = Assignment(
        organization_id=org.id,
        created_by_id=mentor.id,
        title="Python Async Programming",
        description="Implement async workers",
        due_date=date.today() + timedelta(days=5),
        max_score=100,
    )
    db.add(asgn)
    db.commit()

    client = TestClient(app)

    def auth_headers(user: User, with_org: bool = True) -> dict:
        token = generate_token(user.id, user.session_version)
        headers = {"Authorization": f"Bearer {token}"}
        if with_org:
            headers["X-Organization-Id"] = str(org.id)
        return headers

    return {
        "db": db,
        "client": client,
        "org": org,
        "super_admin": super_admin,
        "org_admin": org_admin,
        "mentor": mentor,
        "intern": intern,
        "project": project,
        "task": task,
        "leave_req": leave_req,
        "asgn": asgn,
        "auth_headers": auth_headers,
    }


# ==============================================================================
# ROLE 1: PLATFORM SUPER ADMIN
# ==============================================================================
class TestSuperAdminRole:
    """Super Admin has global visibility across all tenants and platform administration."""

    def test_super_admin_can_access_platform_metrics(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["super_admin"], with_org=False)
        resp = client.get("/api/platform/metrics", headers=headers)
        assert resp.status_code == 200
        assert "total_organizations" in resp.json()

    def test_super_admin_can_list_and_create_organizations(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["super_admin"], with_org=False)
        resp = client.get("/api/platform/organizations", headers=headers)
        assert resp.status_code == 200

        slug = f"superorg-{int(datetime.now().timestamp())}"
        resp_create = client.post(
            "/api/platform/organizations",
            json={
                "name": "Super Admin Created Org",
                "slug": slug,
                "type": OrganizationType.BUSINESS,
                "admin_name": "Admin Test",
                "admin_email": f"admin@{slug}.com",
                "admin_password": "OrgPassword123!",
            },
            headers=headers,
        )
        assert resp_create.status_code == 200
        assert resp_create.json()["organization"]["slug"] == slug

    def test_super_admin_can_view_platform_leads(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["super_admin"], with_org=False)
        resp = client.get("/api/platform/leads", headers=headers)
        assert resp.status_code == 200
        assert "items" in resp.json()

    def test_super_admin_can_access_superadmin_dashboard(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["super_admin"], with_org=False)
        resp = client.get("/api/superadmin/dashboard", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["role"] == "superadmin"

    def test_super_admin_can_manage_tenant_with_org_context(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["super_admin"], with_org=True)
        resp = client.get("/api/admin/users", headers=headers)
        assert resp.status_code == 200
        assert "users" in resp.json()


# ==============================================================================
# ROLE 2: ORGANIZATION ADMIN
# ==============================================================================
class TestOrgAdminRole:
    """Organization Admin has full control over their tenant, but NO platform-level access."""

    def test_admin_can_manage_org_settings_and_profile(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"])
        resp = client.put("/api/org/settings", json={"leave_quota_days": 18}, headers=headers)
        assert resp.status_code == 200
        assert resp.json()["settings"]["leave_quota_days"] == 18

        resp_prof = client.put("/api/org/profile", json={"name": "Global Corp Updated"}, headers=headers)
        assert resp_prof.status_code == 200

    def test_admin_can_manage_users(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"])
        resp = client.get("/api/admin/users", headers=headers)
        assert resp.status_code == 200

        # Create user
        new_email = f"newintern_{int(datetime.now().timestamp())}@globalcorp.com"
        resp_create = client.post(
            "/api/admin/users",
            json={"name": "New Intern", "email": new_email, "password": "Password123!", "role": "intern"},
            headers=headers,
        )
        assert resp_create.status_code == 200
        uid = resp_create.json()["id"]

        # Toggle & Role change
        resp_toggle = client.post(f"/api/admin/users/{uid}/toggle", headers=headers)
        assert resp_toggle.status_code == 200

        resp_role = client.post(f"/api/admin/users/{uid}/role", json={"role": "mentor"}, headers=headers)
        assert resp_role.status_code == 200

        resp_del = client.delete(f"/api/admin/users/{uid}", headers=headers)
        assert resp_del.status_code == 200

    def test_admin_can_view_full_attendance_report(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"])
        resp = client.get("/api/attendance/report", headers=headers)
        assert resp.status_code == 200

        resp_export = client.get("/api/attendance/export.csv", headers=headers)
        assert resp_export.status_code == 200
        assert "text/csv" in resp_export.headers["content-type"]

    def test_admin_can_review_leave_requests(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"])
        leave_id = rbac_env["leave_req"].id
        resp = client.post(
            f"/api/leave/{leave_id}/review",
            json={"decision": "approved", "comment": "Approved by Org Admin"},
            headers=headers,
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == LeaveStatus.APPROVED

    def test_admin_can_access_admin_dashboard(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"])
        resp = client.get("/api/admin/dashboard", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["role"] == "admin"

    def test_admin_can_manage_recycle_bin(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"])
        resp = client.get("/api/admin/bin", headers=headers)
        assert resp.status_code == 200

    def test_admin_cannot_access_platform_endpoints(self, rbac_env):
        """Org admin is forbidden from SaaS platform management."""
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["org_admin"], with_org=False)
        assert client.get("/api/platform/metrics", headers=headers).status_code == 403
        assert client.get("/api/platform/organizations", headers=headers).status_code == 403
        assert client.get("/api/platform/leads", headers=headers).status_code == 403


# ==============================================================================
# ROLE 3: MENTOR / FACULTY
# ==============================================================================
class TestMentorRole:
    """Mentor manages assigned interns, projects, tasks, and reviews; cannot administer tenant."""

    def test_mentor_can_access_mentor_dashboard(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["mentor"])
        resp = client.get("/api/mentor/dashboard", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["role"] == "mentor"

    def test_mentor_can_view_assigned_students_and_attendance(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["mentor"])
        intern_id = rbac_env["intern"].id

        resp = client.get("/api/mentor/students", headers=headers)
        assert resp.status_code == 200

        resp_today = client.get("/api/mentor/students/today", headers=headers)
        assert resp_today.status_code == 200

        resp_att = client.get("/api/mentor/attendance/today", headers=headers)
        assert resp_att.status_code == 200

        resp_detail = client.get(f"/api/mentor/students/{intern_id}/attendance", headers=headers)
        assert resp_detail.status_code == 200

        resp_csv = client.get("/api/mentor/students/export.csv", headers=headers)
        assert resp_csv.status_code == 200

    def test_mentor_can_manage_projects_and_tasks(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["mentor"])
        proj_id = rbac_env["project"].id

        resp = client.get("/api/projects", headers=headers)
        assert resp.status_code == 200

        # Create task
        resp_task = client.post(
            f"/api/projects/{proj_id}/tasks",
            json={
                "title": "Mentor Created Task",
                "description": "Implement feature X",
                "assigned_to": rbac_env["intern"].id,
                "priority": TaskPriority.MEDIUM,
            },
            headers=headers,
        )
        assert resp_task.status_code == 200
        task_id = resp_task.json()["id"]

        # Delete task
        resp_del = client.delete(f"/api/projects/tasks/{task_id}", headers=headers)
        assert resp_del.status_code == 200

    def test_mentor_can_create_assignments_and_review_submissions(self, rbac_env):
        client = rbac_env["client"]
        mentor_headers = rbac_env["auth_headers"](rbac_env["mentor"])
        intern_headers = rbac_env["auth_headers"](rbac_env["intern"])

        resp_asgn = client.post(
            "/api/assignments",
            json={
                "title": "Docker Containerization",
                "description": "Create multistage Dockerfile",
                "due_date": (date.today() + timedelta(days=7)).isoformat(),
                "max_score": 100,
            },
            headers=mentor_headers,
        )
        assert resp_asgn.status_code == 200
        asgn_id = resp_asgn.json()["id"]

        # Intern submits
        resp_sub = client.post(
            f"/api/assignments/{asgn_id}/submit",
            json={"submission_link": "https://github.com/intern/docker", "notes": "Done"},
            headers=intern_headers,
        )
        assert resp_sub.status_code == 200
        sub_id = resp_sub.json()["submission"]["id"]

        # Mentor reviews
        resp_rev = client.post(
            f"/api/assignments/submissions/{sub_id}/review",
            json={"score": 92, "feedback": "Well optimized container!"},
            headers=mentor_headers,
        )
        assert resp_rev.status_code == 200

        client.delete(f"/api/assignments/{asgn_id}", headers=mentor_headers)

    def test_mentor_can_create_and_manage_performance_reviews(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["mentor"])
        resp = client.post(
            "/api/reviews",
            json={
                "intern_id": rbac_env["intern"].id,
                "project_id": rbac_env["project"].id,
                "period": "Sprint 3",
                "rating": 5,
                "feedback": "Consistent high quality output",
            },
            headers=headers,
        )
        assert resp.status_code == 200
        rev_id = resp.json()["id"]

        resp_del = client.delete(f"/api/reviews/{rev_id}", headers=headers)
        assert resp_del.status_code == 200

    def test_mentor_cannot_access_admin_or_org_settings(self, rbac_env):
        """Mentor is forbidden from admin user management mutations, settings, bin, and SMTP."""
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["mentor"])
        # Mentors cannot create admin accounts
        assert client.post(
            "/api/admin/users",
            json={"name": "Attacker", "email": "attacker@test.com", "password": "Password123!", "role": "admin"},
            headers=headers,
        ).status_code == 403
        # Mentors cannot change roles, toggle, or delete users
        assert client.post("/api/admin/users/1/role", json={"role": "admin"}, headers=headers).status_code == 403
        assert client.post("/api/admin/users/1/toggle", headers=headers).status_code == 403
        assert client.delete("/api/admin/users/1", headers=headers).status_code == 403
        # Mentors cannot access bin, mutate duration settings, org settings, SMTP, or platform metrics
        assert client.get("/api/admin/bin", headers=headers).status_code == 403
        assert client.post(
            "/api/admin/internship-durations",
            json={"title": "Hacked", "internship_duration": 12, "leaves": 12},
            headers=headers,
        ).status_code == 403
        assert client.delete("/api/admin/internship-durations/1", headers=headers).status_code == 403
        assert client.put("/api/org/settings", json={"leave_quota_days": 20}, headers=headers).status_code == 403
        assert client.put("/api/org/profile", json={"name": "Hacked"}, headers=headers).status_code == 403
        assert client.get("/api/org/smtp", headers=headers).status_code == 403
        assert client.get("/api/platform/metrics", headers=headers).status_code == 403


# ==============================================================================
# ROLE 4: INTERN / STUDENT
# ==============================================================================
class TestInternRole:
    """Intern has access only to their own attendance, tasks, leaves, submissions, and profile."""

    def test_intern_can_access_intern_dashboard(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])
        resp = client.get("/api/intern/dashboard", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["role"] == "intern"

    def test_intern_can_checkin_checkout_and_view_history(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])
        photo_file = ("selfie.jpg", b"\xff\xd8\xff\xe0" + b"intern_photo", "image/jpeg")

        with patch("routes.api.attendance.is_checkin_blocked", return_value=False):
            resp_in = client.post(
                "/api/attendance/check-in",
                files={"photo": photo_file},
                data={"lat": 18.52, "lng": 73.85},
                headers=headers,
            )
            assert resp_in.status_code == 200

            resp_out = client.post(
                "/api/attendance/check-out",
                files={"photo": photo_file},
                data={"lat": 18.52, "lng": 73.85},
                headers=headers,
            )
            assert resp_out.status_code == 200

        resp_hist = client.get("/api/attendance/history", headers=headers)
        assert resp_hist.status_code == 200

        resp_exp = client.get("/api/attendance/my/export.csv", headers=headers)
        assert resp_exp.status_code == 200

    def test_intern_can_check_leave_balance_and_apply(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])

        resp_bal = client.get("/api/leave/balance", headers=headers)
        assert resp_bal.status_code == 200
        assert "remaining" in resp_bal.json()

        d_start = date.today() + timedelta(days=20)
        while d_start.weekday() >= 5:
            d_start += timedelta(days=1)
        d_end = d_start + timedelta(days=1)
        while d_end.weekday() >= 5:
            d_end += timedelta(days=1)

        resp_apply = client.post(
            "/api/leave",
            json={
                "start_date": d_start.isoformat(),
                "end_date": d_end.isoformat(),
                "leave_type": "sick",
                "reason": "Doctor consultation",
            },
            headers=headers,
        )
        assert resp_apply.status_code == 200

        resp_mine = client.get("/api/leave/mine", headers=headers)
        assert resp_mine.status_code == 200

    def test_intern_can_update_assigned_task_status_and_comment(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])
        task_id = rbac_env["task"].id

        resp_status = client.patch(
            f"/api/projects/tasks/{task_id}/status",
            json={"status": TaskStatus.IN_PROGRESS},
            headers=headers,
        )
        assert resp_status.status_code == 200

        resp_comm = client.post(
            f"/api/projects/tasks/{task_id}/comments",
            json={"body": "Working on webhook endpoint"},
            headers=headers,
        )
        assert resp_comm.status_code == 200

    def test_intern_can_log_daily_standup(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])
        resp = client.post(
            "/api/standup",
            json={
                "date": date.today().isoformat(),
                "did": "Connected Stripe webhook listener",
                "plan": "Write test cases",
                "blockers": "None",
                "mood": "happy",
            },
            headers=headers,
        )
        assert resp.status_code == 200

        resp_today = client.get("/api/standup/today", headers=headers)
        assert resp_today.status_code == 200

    def test_intern_can_manage_own_profile(self, rbac_env):
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])
        resp = client.get("/api/profile", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["email"] == rbac_env["intern"].email

        resp_update = client.put("/api/profile", json={"bio": "Junior Full Stack Dev"}, headers=headers)
        assert resp_update.status_code == 200

    def test_intern_cannot_access_restricted_endpoints(self, rbac_env):
        """Intern is strictly forbidden from admin, mentor, review, and platform operations."""
        client = rbac_env["client"]
        headers = rbac_env["auth_headers"](rbac_env["intern"])
        proj_id = rbac_env["project"].id
        leave_id = rbac_env["leave_req"].id

        # Admin prohibitions
        assert client.get("/api/admin/users", headers=headers).status_code == 403
        assert client.post(
            "/api/admin/users",
            json={"name": "Hacked", "email": "hacked@test.com", "password": "Password123!", "role": "intern"},
            headers=headers,
        ).status_code == 403
        assert client.get("/api/admin/bin", headers=headers).status_code == 403
        assert client.get("/api/attendance/report", headers=headers).status_code == 403
        assert client.post(
            "/api/attendance/manual",
            json={"user_id": 1, "date": "2026-09-01", "check_in": "09:00", "check_out": "17:00", "status": "present", "reason": "Test"},
            headers=headers,
        ).status_code == 403

        # Mentor prohibitions
        assert client.get("/api/mentor/dashboard", headers=headers).status_code == 403
        assert client.get("/api/mentor/students", headers=headers).status_code == 403
        assert client.post(
            "/api/assignments",
            json={"title": "Hacked Assignment", "description": "Desc", "due_date": "2026-09-20", "max_score": 100},
            headers=headers,
        ).status_code == 403
        assert client.post(
            "/api/reviews",
            json={"intern_id": 1, "project_id": proj_id, "period": "Q1", "rating": 5, "feedback": "Nice"},
            headers=headers,
        ).status_code == 403
        assert client.post(f"/api/leave/{leave_id}/review", json={"decision": "approved"}, headers=headers).status_code == 403

        # Project creation prohibition
        assert client.post("/api/projects", json={"name": "Hacked"}, headers=headers).status_code == 403

        # Cohort & Announcement creation prohibition
        assert client.post("/api/cohorts", json={"name": "Hacked"}, headers=headers).status_code == 403
        assert client.post("/api/announcements", json={"title": "Hacked", "body": "Body content"}, headers=headers).status_code == 403

        # Platform prohibitions
        assert client.get("/api/platform/metrics", headers=headers).status_code == 403


# ==============================================================================
# ROLE 5: ANONYMOUS / UNAUTHENTICATED PUBLIC USER
# ==============================================================================
class TestAnonymousRole:
    """Anonymous visitors can access public landing/docs/blogs/leads, but are blocked (401/403) on private APIs."""

    def test_anonymous_can_access_public_endpoints(self, rbac_env):
        client = rbac_env["client"]
        assert client.get("/api/health").status_code == 200
        assert client.get("/docs").status_code == 200
        assert client.get("/api/docs").status_code == 200
        assert client.get("/openapi.json").status_code == 200
        assert client.get("/api/blogs").status_code == 200
        assert client.get("/sitemap.xml").status_code == 200
        assert client.post("/api/leads", json={"name": "Lead", "email": "lead@test.com"}).status_code == 200

    def test_anonymous_blocked_from_authenticated_endpoints(self, rbac_env):
        client = rbac_env["client"]
        assert client.get("/api/auth/me").status_code == 401
        assert client.get("/api/dashboard").status_code == 401
        assert client.get("/api/attendance/today").status_code == 401
        assert client.get("/api/leave/mine").status_code == 401
        assert client.get("/api/projects").status_code == 401
        assert client.get("/api/admin/users").status_code in (401, 403)
        assert client.get("/api/org/current").status_code == 401
        assert client.get("/api/platform/metrics").status_code == 401
