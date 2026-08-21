"""Comprehensive test suite covering each and every API endpoint in InternHub backend."""
from datetime import date, datetime, timedelta
import io
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Announcement,
    Attendance,
    AttendanceStatus,
    BinEntityType,
    Cohort,
    CohortMember,
    InternInviteLink,
    LeaveRequest,
    LeaveStatus,
    LeaveType,
    Notification,
    Organization,
    OrganizationMembership,
    OrganizationSettings,
    OrganizationStatus,
    OrganizationType,
    PerformanceReview,
    Project,
    ProjectAssignment,
    ProjectComment,
    ProjectLink,
    ProjectStatus,
    StandupLog,
    Task,
    TaskComment,
    TaskPriority,
    TaskStatus,
    User,
    UserRole,
    _utcnow,
)


@pytest.fixture(scope="module")
def api_env():
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
        slug="techcorp",
        name="TechCorp Global",
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
        noon_cutoff="13:00",
        checkin_block="23:59",
        full_day_hours=8.0,
        half_day_hours=4.0,
        leave_quota_days=12,
        advance_leave_days=3,
        require_attendance_selfie=False,
        require_attendance_gps=False,
        auto_checkout_enabled=True,
    )
    db.add(settings)

    # 2. Users
    super_admin = User(
        name="Super Admin",
        email="superadmin@techcorp.com",
        role=UserRole.ADMIN,
        is_platform_admin=True,
        is_active=True,
        activated_at=_utcnow(),
    )
    super_admin.set_password("SuperSecret123!")

    org_admin = User(
        name="Org Admin",
        email="admin@techcorp.com",
        role=UserRole.ADMIN,
        is_active=True,
        activated_at=_utcnow(),
    )
    org_admin.set_password("AdminPass123!")

    mentor = User(
        name="Mentor Jane",
        email="mentor@techcorp.com",
        role=UserRole.MENTOR,
        is_active=True,
        activated_at=_utcnow(),
    )
    mentor.set_password("MentorPass123!")

    intern = User(
        name="Intern Bob",
        email="intern@techcorp.com",
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
        name="Core Web App",
        description="Main client portal",
        mentor_id=mentor.id,
        status=ProjectStatus.ACTIVE,
    )
    db.add(project)
    db.flush()

    assignment = ProjectAssignment(
        project_id=project.id,
        user_id=intern.id,
    )
    db.add(assignment)
    db.flush()

    task = Task(
        organization_id=org.id,
        project_id=project.id,
        created_by_id=mentor.id,
        assigned_to=intern.id,
        title="Implement Login Flow",
        description="Add OAuth & Bearer JWT login",
        status=TaskStatus.TODO,
        priority=TaskPriority.HIGH,
    )
    db.add(task)
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
        "auth_headers": auth_headers,
    }


# ==============================================================================
# 1. Health Endpoint (/api/health)
# ==============================================================================
def test_health_api(api_env):
    client = api_env["client"]
    resp = client.get("/api/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["service"] == "internhub"


def test_scalar_docs_endpoint(api_env):
    client = api_env["client"]
    resp = client.get("/docs")
    assert resp.status_code == 200
    assert "Scalar API Reference" in resp.text
    assert "@scalar/api-reference" in resp.text

    resp_api = client.get("/api/docs")
    assert resp_api.status_code == 200
    assert "Scalar API Reference" in resp_api.text


# ==============================================================================
# 2. Auth APIs (/api/auth/*)
# ==============================================================================
def test_auth_me_authenticated(api_env):
    client, intern = api_env["client"], api_env["intern"]
    headers = api_env["auth_headers"](intern)
    resp = client.get("/api/auth/me", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["email"] == intern.email


def test_auth_me_unauthenticated(api_env):
    client = api_env["client"]
    resp = client.get("/api/auth/me")
    assert resp.status_code == 401


def test_auth_login_and_logout(api_env):
    client, intern = api_env["client"], api_env["intern"]
    headers = api_env["auth_headers"](intern)
    # Valid login
    resp = client.post("/api/auth/login", json={"email": intern.email, "password": "InternPass123!"})
    assert resp.status_code == 200
    assert resp.json()["ok"] is True
    assert "token" in resp.json()

    # Invalid password
    resp = client.post("/api/auth/login", json={"email": intern.email, "password": "WrongPassword123!"})
    assert resp.status_code == 401

    # Logout (with auth header)
    resp = client.post("/api/auth/logout", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


def test_auth_register_and_invite_flow(api_env):
    client, db, mentor = api_env["client"], api_env["db"], api_env["mentor"]
    # Register new intern
    new_email = f"newintern_{int(datetime.now().timestamp())}@techcorp.com"
    resp = client.post(
        "/api/auth/register",
        json={
            "name": "New Intern Candidate",
            "email": new_email,
            "password": "Password123!",
            "confirm_password": "Password123!",
            "role": "intern",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["ok"] is True

    # Create invite link
    invite = InternInviteLink(
        label="Spring Internship 2026",
        token=f"tok_{int(datetime.now().timestamp())}",
        mentor_id=mentor.id,
        is_active=True,
    )
    db.add(invite)
    db.commit()

    # Get invite info
    resp = client.get(f"/api/auth/invite/{invite.token}")
    assert resp.status_code == 200
    assert resp.json()["valid"] is True
    assert resp.json()["mentor_name"] == mentor.name

    # Register via invite
    invited_email = f"invited_{int(datetime.now().timestamp())}@techcorp.com"
    resp = client.post(
        f"/api/auth/invite/{invite.token}/register",
        json={
            "name": "Invited Intern",
            "email": invited_email,
            "password": "Password123!",
            "confirm_password": "Password123!",
            "phone": "9876543210",
            "department": "Engineering",
            "job_title": "Software Intern",
            "joining_date": "2026-06-01",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


# ==============================================================================
# 3. Platform APIs (Super Admin) (/api/platform/*)
# ==============================================================================
def test_platform_apis(api_env):
    client, super_admin, intern = api_env["client"], api_env["super_admin"], api_env["intern"]
    super_headers = api_env["auth_headers"](super_admin, with_org=False)
    intern_headers = api_env["auth_headers"](intern, with_org=False)

    # 1. Non-super admin access rejected
    resp = client.get("/api/platform/metrics", headers=intern_headers)
    assert resp.status_code == 403

    # 2. Get Platform Metrics
    resp = client.get("/api/platform/metrics", headers=super_headers)
    assert resp.status_code == 200
    assert "total_organizations" in resp.json()

    # 3. List Organizations
    resp = client.get("/api/platform/organizations", headers=super_headers)
    assert resp.status_code == 200
    assert "organizations" in resp.json()

    # 4. Create Organization
    slug = f"neworg-{int(datetime.now().timestamp())}"
    resp = client.post(
        "/api/platform/organizations",
        json={
            "name": "New Alpha Org",
            "slug": slug,
            "type": OrganizationType.BUSINESS,
            "timezone": "Asia/Kolkata",
            "admin_name": "Alpha Admin",
            "admin_email": f"admin@{slug}.com",
            "admin_password": "AlphaAdminPass123!",
        },
        headers=super_headers,
    )
    assert resp.status_code == 200
    created_org = resp.json()["organization"]
    created_org_id = created_org["id"]

    # 5. Get Organization Details
    resp = client.get(f"/api/platform/organizations/{created_org_id}", headers=super_headers)
    assert resp.status_code == 200
    assert resp.json()["organization"]["slug"] == slug

    # 6. Update Organization Status
    resp = client.put(
        f"/api/platform/organizations/{created_org_id}/status",
        json={"status": OrganizationStatus.SUSPENDED},
        headers=super_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["organization"]["status"] == OrganizationStatus.SUSPENDED


# ==============================================================================
# 4. Org APIs (Current Tenant Settings & Profile) (/api/org/*)
# ==============================================================================
def test_org_apis(api_env):
    client, org_admin = api_env["client"], api_env["org_admin"]
    headers = api_env["auth_headers"](org_admin)

    # 1. Get current organization
    resp = client.get("/api/org/current", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert "organization" in data
    assert "settings" in data

    # 2. Update org profile
    resp = client.put(
        "/api/org/profile",
        json={"name": "TechCorp Global Updated", "timezone": "Asia/Kolkata"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["organization"]["name"] == "TechCorp Global Updated"

    # 3. Update org settings
    resp = client.put(
        "/api/org/settings",
        json={"leave_quota_days": 15, "full_day_hours": 8.5},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["settings"]["leave_quota_days"] == 15

    # 4. List members
    resp = client.get("/api/org/members", headers=headers)
    assert resp.status_code == 200
    assert len(resp.json()) >= 3

    # 5. Add member
    new_email = f"orgmember_{int(datetime.now().timestamp())}@techcorp.com"
    resp = client.post(
        "/api/org/members",
        json={
            "name": "Direct Added Member",
            "email": new_email,
            "password": "MemberPass123!",
            "role": UserRole.INTERN,
            "department": "Engineering",
        },
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["ok"] is True
    assert "membership" in resp.json()


# ==============================================================================
# 5. Admin APIs (/api/admin/*)
# ==============================================================================
def test_admin_apis(api_env):
    client, org_admin, db = api_env["client"], api_env["org_admin"], api_env["db"]
    headers = api_env["auth_headers"](org_admin)

    # 1. List users
    resp = client.get("/api/admin/users", headers=headers)
    assert resp.status_code == 200
    assert "users" in resp.json()

    # 2. List mentors
    resp = client.get("/api/admin/mentors", headers=headers)
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)

    # 3. List intern assignments
    resp = client.get("/api/admin/intern-assignments", headers=headers)
    assert resp.status_code == 200
    assert "total_interns" in resp.json()

    # 4. Create user via admin
    user_email = f"admincreated_{int(datetime.now().timestamp())}@techcorp.com"
    resp = client.post(
        "/api/admin/users",
        json={
            "name": "Admin Created User",
            "email": user_email,
            "password": "UserPass123!",
            "role": UserRole.INTERN,
        },
        headers=headers,
    )
    assert resp.status_code == 200
    new_user_id = resp.json()["id"]

    # 5. Update user
    resp = client.put(
        f"/api/admin/users/{new_user_id}",
        json={"name": "Admin Updated User", "department": "QA"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["department"] == "QA"

    # 6. Toggle user active state
    resp = client.post(f"/api/admin/users/{new_user_id}/toggle", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_active"] is False

    # 7. Update user role
    resp = client.post(
        f"/api/admin/users/{new_user_id}/role",
        json={"role": UserRole.MENTOR},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["role"] == UserRole.MENTOR

    # 8. Delete user (moves to bin)
    resp = client.delete(f"/api/admin/users/{new_user_id}", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["ok"] is True

    # 9. Admin invite links management
    resp = client.get("/api/admin/invite-link", headers=headers)
    assert resp.status_code == 200

    resp = client.post(
        "/api/admin/invite-link",
        json={"label": "Batch 2026 Admin Link"},
        headers=headers,
    )
    assert resp.status_code == 200
    link_id = resp.json()["link"]["id"]

    resp = client.post("/api/admin/invite-link/regenerate", json={"link_id": link_id}, headers=headers)
    assert resp.status_code == 200

    resp = client.post("/api/admin/invite-link/deactivate", json={"link_id": link_id}, headers=headers)
    assert resp.status_code == 200

    resp = client.delete(f"/api/admin/invite-link/{link_id}", headers=headers)
    assert resp.status_code == 200

    # 10. Intern signup requests review
    resp = client.get("/api/admin/intern-signup-requests", headers=headers)
    assert resp.status_code == 200

    # 11. Recycle bin operations
    resp = client.get("/api/admin/bin", headers=headers)
    assert resp.status_code == 200
    bin_items = resp.json()["items"]
    assert isinstance(bin_items, list)
    if bin_items:
        first_bin_id = bin_items[0]["id"]
        # Test restore
        resp = client.post(f"/api/admin/bin/{first_bin_id}/restore", headers=headers)
        assert resp.status_code == 200


# ==============================================================================
# 6. Attendance APIs (/api/attendance/*)
# ==============================================================================
def test_attendance_apis(api_env):
    client, intern, org_admin, org = (
        api_env["client"],
        api_env["intern"],
        api_env["org_admin"],
        api_env["org"],
    )
    intern_headers = api_env["auth_headers"](intern)
    admin_headers = api_env["auth_headers"](org_admin)

    # 1. Attendance today status
    resp = client.get("/api/attendance/today", headers=intern_headers)
    assert resp.status_code == 200

    # 2. Check-in (multipart form-data with selfie and GPS)
    photo_file = ("selfie.jpg", b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"fake_jpeg_content", "image/jpeg")
    resp = client.post(
        "/api/attendance/check-in",
        files={"photo": photo_file},
        data={"lat": 19.076, "lng": 72.877},
        headers=intern_headers,
    )
    assert resp.status_code == 200
    record_id = resp.json()["id"]

    # 3. Check-out
    resp = client.post(
        "/api/attendance/check-out",
        files={"photo": photo_file},
        data={"lat": 19.076, "lng": 72.877},
        headers=intern_headers,
    )
    assert resp.status_code == 200

    # 4. Get photo
    resp = client.get(f"/api/attendance/{record_id}/photo/checkin", headers=intern_headers)
    assert resp.status_code == 200

    # 5. History
    resp = client.get("/api/attendance/history", headers=intern_headers)
    assert resp.status_code == 200
    assert "records" in resp.json()

    # 6. Report
    resp = client.get("/api/attendance/report", headers=admin_headers)
    assert resp.status_code == 200

    # 7. Export CSV
    resp = client.get("/api/attendance/export.csv", headers=admin_headers)
    assert resp.status_code == 200
    assert "text/csv" in resp.headers.get("content-type", "")

    # 8. Audit of record
    resp = client.get(f"/api/attendance/{record_id}/audit", headers=admin_headers)
    assert resp.status_code == 200

    # 9. Edit attendance record
    resp = client.put(
        f"/api/attendance/{record_id}",
        json={"check_in": "09:15", "reason": "Admin adjustment"},
        headers=admin_headers,
    )
    assert resp.status_code == 200

    # 10. Manual attendance creation by Admin
    resp = client.post(
        "/api/attendance/manual",
        json={
            "user_id": intern.id,
            "date": (date.today() - timedelta(days=2)).isoformat(),
            "check_in": "09:00",
            "check_out": "17:00",
            "status": AttendanceStatus.PRESENT,
            "reason": "Approved retroactive entry",
        },
        headers=admin_headers,
    )
    assert resp.status_code == 200

    # 11. Auto checkout sweep trigger
    resp = client.post("/api/attendance/auto-checkout", headers=admin_headers)
    assert resp.status_code == 200


# ==============================================================================
# 7. Leave APIs (/api/leave/*)
# ==============================================================================
def test_leave_apis(api_env):
    client, intern, org_admin = api_env["client"], api_env["intern"], api_env["org_admin"]
    intern_headers = api_env["auth_headers"](intern)
    admin_headers = api_env["auth_headers"](org_admin)

    # 1. Balance
    resp = client.get("/api/leave/balance", headers=intern_headers)
    assert resp.status_code == 200
    assert "remaining" in resp.json()

    # 2. Apply for leave
    leave_start = date.today() + timedelta(days=5)
    leave_end = date.today() + timedelta(days=6)
    resp = client.post(
        "/api/leave",
        json={
            "start_date": leave_start.isoformat(),
            "end_date": leave_end.isoformat(),
            "leave_type": LeaveType.CASUAL,
            "reason": "Personal errands and exams",
        },
        headers=intern_headers,
    )
    assert resp.status_code == 200
    leave_id = resp.json()["id"]

    # 3. View my requests
    resp = client.get("/api/leave/mine", headers=intern_headers)
    assert resp.status_code == 200
    assert len(resp.json()["requests"]) >= 1

    # 4. Admin / Mentor manage view
    resp = client.get("/api/leave/manage", headers=admin_headers)
    assert resp.status_code == 200

    # 5. Review leave request
    resp = client.post(
        f"/api/leave/{leave_id}/review",
        json={"decision": "approved", "comment": "Approved by Admin"},
        headers=admin_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == LeaveStatus.APPROVED


# ==============================================================================
# 8. Projects & Tasks APIs (/api/projects/* & /api/tasks/*)
# ==============================================================================
def test_projects_and_tasks_apis(api_env):
    client, org_admin, mentor, intern = (
        api_env["client"],
        api_env["org_admin"],
        api_env["mentor"],
        api_env["intern"],
    )
    mentor_headers = api_env["auth_headers"](mentor)
    admin_headers = api_env["auth_headers"](org_admin)
    intern_headers = api_env["auth_headers"](intern)

    # 1. List projects
    resp = client.get("/api/projects", headers=mentor_headers)
    assert resp.status_code == 200
    assert "projects" in resp.json()

    # 2. Create project
    resp = client.post(
        "/api/projects",
        json={
            "name": "Mobile App V2",
            "description": "Cross-platform client",
            "mentor_id": mentor.id,
        },
        headers=admin_headers,
    )
    assert resp.status_code == 200
    project_id = resp.json()["id"]

    # 3. Get project details
    resp = client.get(f"/api/projects/{project_id}", headers=mentor_headers)
    assert resp.status_code == 200
    assert resp.json()["name"] == "Mobile App V2"

    # 4. Export project
    resp = client.get(f"/api/projects/{project_id}/export", headers=mentor_headers)
    assert resp.status_code == 200

    # 5. Update project
    resp = client.put(
        f"/api/projects/{project_id}",
        json={"name": "Mobile App V2 Updated", "status": ProjectStatus.ACTIVE},
        headers=mentor_headers,
    )
    assert resp.status_code == 200

    # 6. Assign intern
    resp = client.post(
        f"/api/projects/{project_id}/assign",
        json={"user_id": intern.id},
        headers=mentor_headers,
    )
    assert resp.status_code == 200

    # 7. Create task
    resp = client.post(
        f"/api/projects/{project_id}/tasks",
        json={
            "title": "Build Flutter UI",
            "description": "Design main screens",
            "assigned_to": intern.id,
            "priority": TaskPriority.HIGH,
        },
        headers=mentor_headers,
    )
    assert resp.status_code == 200
    task_id = resp.json()["id"]

    # 8. Update task
    resp = client.put(
        f"/api/projects/tasks/{task_id}",
        json={"title": "Build Flutter UI screens", "priority": TaskPriority.MEDIUM},
        headers=mentor_headers,
    )
    assert resp.status_code == 200

    # 9. Patch task status
    resp = client.patch(
        f"/api/projects/tasks/{task_id}/status",
        json={"status": TaskStatus.DONE},
        headers=intern_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == TaskStatus.DONE

    # 10. Task comments
    resp = client.post(
        f"/api/projects/tasks/{task_id}/comments",
        json={"body": "Completed the initial layout"},
        headers=intern_headers,
    )
    assert resp.status_code == 200
    comment_id = resp.json()["id"]

    resp = client.get(f"/api/projects/tasks/{task_id}/comments", headers=intern_headers)
    assert resp.status_code == 200
    assert len(resp.json()) >= 1

    resp = client.delete(f"/api/projects/tasks/comments/{comment_id}", headers=intern_headers)
    assert resp.status_code == 200

    # 11. Project comments board
    resp = client.post(
        f"/api/projects/{project_id}/comments-board",
        json={"body": "Great progress team!"},
        headers=mentor_headers,
    )
    assert resp.status_code == 200
    board_comm_id = resp.json()["id"]

    resp = client.get(f"/api/projects/{project_id}/comments-board", headers=mentor_headers)
    assert resp.status_code == 200

    resp = client.delete(f"/api/projects/comments-board/{board_comm_id}", headers=mentor_headers)
    assert resp.status_code == 200

    # 12. Project links
    resp = client.post(
        f"/api/projects/{project_id}/links",
        json={"remark": "Figma Designs", "link": "https://figma.com/file/example"},
        headers=mentor_headers,
    )
    assert resp.status_code == 200
    link_id = resp.json()["id"]

    resp = client.get(f"/api/projects/{project_id}/links", headers=mentor_headers)
    assert resp.status_code == 200

    resp = client.delete(f"/api/projects/links/{link_id}", headers=mentor_headers)
    assert resp.status_code == 200

    # 13. Unassign intern
    resp = client.delete(f"/api/projects/{project_id}/assign/{intern.id}", headers=mentor_headers)
    assert resp.status_code == 200

    # 14. Delete task
    resp = client.delete(f"/api/projects/tasks/{task_id}", headers=mentor_headers)
    assert resp.status_code == 200

    # 15. Delete project
    resp = client.delete(f"/api/projects/{project_id}", headers=admin_headers)
    assert resp.status_code == 200


# ==============================================================================
# 9. Cohorts, Announcements & Audit APIs (/api/cohorts/*, /api/announcements/*, /api/audit)
# ==============================================================================
def test_cohorts_announcements_audit_apis(api_env):
    client, org_admin, mentor, intern = (
        api_env["client"],
        api_env["org_admin"],
        api_env["mentor"],
        api_env["intern"],
    )
    admin_headers = api_env["auth_headers"](org_admin)
    intern_headers = api_env["auth_headers"](intern)

    # 1. Create Cohort
    resp = client.post(
        "/api/cohorts",
        json={
            "name": "Summer 2026 Batch",
            "description": "Full-stack development interns",
            "start_date": "2026-06-01",
            "end_date": "2026-08-31",
        },
        headers=admin_headers,
    )
    assert resp.status_code == 200
    cohort_id = resp.json()["id"]

    # 2. List cohorts
    resp = client.get("/api/cohorts", headers=admin_headers)
    assert resp.status_code == 200

    # 3. Get cohort details
    resp = client.get(f"/api/cohorts/{cohort_id}", headers=admin_headers)
    assert resp.status_code == 200

    # 4. Add member to cohort
    resp = client.post(
        f"/api/cohorts/{cohort_id}/members",
        json={"user_id": intern.id},
        headers=admin_headers,
    )
    assert resp.status_code == 200

    # 5. Remove member from cohort
    resp = client.delete(f"/api/cohorts/{cohort_id}/members/{intern.id}", headers=admin_headers)
    assert resp.status_code == 200

    # 6. Update cohort
    resp = client.put(
        f"/api/cohorts/{cohort_id}",
        json={"name": "Summer 2026 Batch Updated"},
        headers=admin_headers,
    )
    assert resp.status_code == 200

    # 7. Delete cohort
    resp = client.delete(f"/api/cohorts/{cohort_id}", headers=admin_headers)
    assert resp.status_code == 200

    # 8. Create announcement
    resp = client.post(
        "/api/announcements",
        json={
            "title": "Welcome All New Interns",
            "body": "Orientation takes place at 10 AM on Monday.",
            "is_pinned": True,
        },
        headers=admin_headers,
    )
    assert resp.status_code == 200
    ann_id = resp.json()["id"]

    # 9. List announcements
    resp = client.get("/api/announcements", headers=intern_headers)
    assert resp.status_code == 200

    # 10. Update announcement
    resp = client.put(
        f"/api/announcements/{ann_id}",
        json={"title": "Welcome All New Interns (Updated)"},
        headers=admin_headers,
    )
    assert resp.status_code == 200

    # 11. Delete announcement
    resp = client.delete(f"/api/announcements/{ann_id}", headers=admin_headers)
    assert resp.status_code == 200

    # 12. Audit Logs API
    resp = client.get("/api/audit", headers=admin_headers)
    assert resp.status_code == 200
    assert "logs" in resp.json()


# ==============================================================================
# 10. Dashboard, Notifications, Profile, Reviews, Search, Standup, Users APIs
# ==============================================================================
def test_dashboard_notifications_profile_reviews_search_standup_users_apis(api_env):
    client, org_admin, mentor, intern, project = (
        api_env["client"],
        api_env["org_admin"],
        api_env["mentor"],
        api_env["intern"],
        api_env["project"],
    )
    admin_headers = api_env["auth_headers"](org_admin)
    mentor_headers = api_env["auth_headers"](mentor)
    intern_headers = api_env["auth_headers"](intern)

    # 1. Dashboard APIs
    resp = client.get("/api/dashboard", headers=intern_headers)
    assert resp.status_code == 200
    assert "stats" in resp.json()

    # Role-specific Single-Response Dashboard APIs
    resp = client.get("/api/admin/dashboard", headers=admin_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["role"] == "admin"
    assert "present_today_list" in data
    assert "open_tasks" in data
    assert "active_projects" in data
    assert "pending_leave_requests" in data

    resp = client.get("/admin/dashboard", headers=admin_headers)
    assert resp.status_code == 200

    resp = client.get("/api/mentor/dashboard", headers=mentor_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["role"] == "mentor"
    assert "assigned_interns" in data
    assert "projects" in data
    assert "open_tasks" in data

    resp = client.get("/mentor/dashboard", headers=mentor_headers)
    assert resp.status_code == 200

    resp = client.get("/api/intern/dashboard", headers=intern_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["role"] == "intern"
    assert "today_attendance" in data
    assert "assigned_projects" in data
    assert "assigned_tasks" in data

    resp = client.get("/intern/dashboard", headers=intern_headers)
    assert resp.status_code == 200

    resp = client.get("/api/superadmin/dashboard", headers=admin_headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["role"] == "superadmin"
    assert "organizations" in data
    assert "system_health" in data

    resp = client.get("/superadmin/dashboard", headers=admin_headers)
    assert resp.status_code == 200

    resp = client.get("/api/dashboard/present-today", headers=admin_headers)
    assert resp.status_code == 200

    resp = client.get("/api/dashboard/open-tasks", headers=intern_headers)
    assert resp.status_code == 200

    resp = client.get("/api/dashboard/attendance-chart", headers=intern_headers)
    assert resp.status_code == 200

    # 2. Notifications APIs
    resp = client.get("/api/notifications", headers=intern_headers)
    assert resp.status_code == 200

    resp = client.get("/api/notifications/unread-count", headers=intern_headers)
    assert resp.status_code == 200

    resp = client.post("/api/notifications/mark-read", headers=intern_headers)
    assert resp.status_code == 200

    # 3. Profile APIs
    resp = client.get("/api/profile", headers=intern_headers)
    assert resp.status_code == 200
    assert resp.json()["email"] == intern.email

    resp = client.put(
        "/api/profile",
        json={"bio": "Software engineering intern passionate about cloud & AI"},
        headers=intern_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["bio"] == "Software engineering intern passionate about cloud & AI"

    resp = client.post(
        "/api/profile/change-password",
        json={
            "current_password": "InternPass123!",
            "new_password": "NewInternPass123!",
            "confirm_password": "NewInternPass123!",
        },
        headers=intern_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["ok"] is True

    # Refresh intern headers since password change increments session_version
    api_env["db"].refresh(intern)
    intern_headers = api_env["auth_headers"](intern)

    # 4. Performance Reviews APIs
    resp = client.post(
        "/api/reviews",
        json={
            "intern_id": intern.id,
            "project_id": project.id,
            "period": "Q3 2026",
            "rating": 5,
            "technical_rating": 5,
            "communication_rating": 4,
            "initiative_rating": 5,
            "feedback": "Outstanding problem-solving and rapid learning!",
            "strengths": "Python, FastAPI, Architecture",
            "improvements": "System design documentation",
        },
        headers=mentor_headers,
    )
    assert resp.status_code == 200
    review_id = resp.json()["id"]

    resp = client.get("/api/reviews", headers=intern_headers)
    assert resp.status_code == 200
    assert len(resp.json()) >= 1

    resp = client.get(f"/api/reviews/{review_id}", headers=intern_headers)
    assert resp.status_code == 200
    assert resp.json()["rating"] == 5

    resp = client.put(
        f"/api/reviews/{review_id}",
        json={"rating": 5, "feedback": "Updated review feedback"},
        headers=mentor_headers,
    )
    assert resp.status_code == 200

    resp = client.delete(f"/api/reviews/{review_id}", headers=mentor_headers)
    assert resp.status_code == 200

    # 5. Search APIs (Global & Project Search)
    resp = client.get("/api/search?q=TechCorp", headers=admin_headers)
    assert resp.status_code == 200
    assert "results" in resp.json()

    resp = client.get("/api/projects?search=Platform", headers=admin_headers)
    assert resp.status_code == 200
    assert "projects" in resp.json()

    resp = client.get("/api/projects/search?q=Platform", headers=admin_headers)
    assert resp.status_code == 200
    assert "projects" in resp.json()

    # 6. Standup Log APIs
    resp = client.post(
        "/api/standup",
        json={
            "date": date.today().isoformat(),
            "did": "Worked on backend API unit and integration tests",
            "plan": "Complete all domain router coverage",
            "blockers": "None",
            "mood": "great",
        },
        headers=intern_headers,
    )
    assert resp.status_code == 200
    standup_id = resp.json()["id"]

    resp = client.get("/api/standup", headers=intern_headers)
    assert resp.status_code == 200

    resp = client.get("/api/standup/today", headers=intern_headers)
    assert resp.status_code == 200

    resp = client.put(
        f"/api/standup/{standup_id}",
        json={"plan": "Deploy and test end-to-end"},
        headers=intern_headers,
    )
    assert resp.status_code == 200

    resp = client.delete(f"/api/standup/{standup_id}", headers=intern_headers)
    assert resp.status_code == 200

    # 7. Users Overview & Leave APIs
    resp = client.get(f"/api/users/{intern.id}/overview", headers=admin_headers)
    assert resp.status_code == 200
    assert "user" in resp.json()
    assert "stats" in resp.json()

    resp = client.get(f"/api/users/{intern.id}/leave", headers=admin_headers)
    assert resp.status_code == 200
    assert "summary" in resp.json()
