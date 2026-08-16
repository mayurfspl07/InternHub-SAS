"""Cross-tenant isolation & IDOR security test suite.

Verifies that users in Organization A can NEVER view, mutate, search,
or delete resources belonging to Organization B.
"""
from datetime import date, datetime, timedelta, timezone
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
    Cohort,
    CohortMember,
    LeaveRequest,
    LeaveStatus,
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
def test_setup():
    test_engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)
    Base.metadata.create_all(bind=test_engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db

    db = TestingSessionLocal()

    # Create Org Alpha and Org Beta
    org_alpha = Organization(id=1, slug="alpha-corp", name="Alpha Corp", type=OrganizationType.BUSINESS)
    org_beta = Organization(id=2, slug="beta-univ", name="Beta University", type=OrganizationType.EDUCATIONAL_INSTITUTE)
    db.add_all([org_alpha, org_beta])
    db.flush()

    settings_alpha = OrganizationSettings(organization_id=org_alpha.id)
    settings_beta = OrganizationSettings(organization_id=org_beta.id)
    db.add_all([settings_alpha, settings_beta])

    # Platform Super Admin
    super_admin = User(
        name="Platform Super Admin",
        email="superadmin@internhub.saas",
        role=UserRole.ADMIN,
        is_platform_admin=True,
        is_active=True,
        activated_at=_utcnow(),
    )
    super_admin.set_password("SuperSecret123!")

    # Org Alpha Users
    admin_a = User(name="Admin Alpha", email="admin@alpha.com", role=UserRole.ADMIN, is_active=True, activated_at=_utcnow())
    admin_a.set_password("PassAlpha123!")
    mentor_a = User(name="Mentor Alpha", email="mentor@alpha.com", role=UserRole.MENTOR, is_active=True, activated_at=_utcnow())
    mentor_a.set_password("PassAlpha123!")
    intern_a = User(name="Intern Alpha", email="intern@alpha.com", role=UserRole.INTERN, is_active=True, activated_at=_utcnow())
    intern_a.set_password("PassAlpha123!")

    # Org Beta Users
    admin_b = User(name="Admin Beta", email="admin@beta.com", role=UserRole.ADMIN, is_active=True, activated_at=_utcnow())
    admin_b.set_password("PassBeta123!")
    mentor_b = User(name="Mentor Beta", email="mentor@beta.com", role=UserRole.MENTOR, is_active=True, activated_at=_utcnow())
    mentor_b.set_password("PassBeta123!")
    intern_b = User(name="Intern Beta", email="intern@beta.com", role=UserRole.INTERN, is_active=True, activated_at=_utcnow())
    intern_b.set_password("PassBeta123!")

    db.add_all([super_admin, admin_a, mentor_a, intern_a, admin_b, mentor_b, intern_b])
    db.flush()

    # Memberships
    mem_admin_a = OrganizationMembership(organization_id=org_alpha.id, user_id=admin_a.id, role=UserRole.ADMIN)
    mem_mentor_a = OrganizationMembership(organization_id=org_alpha.id, user_id=mentor_a.id, role=UserRole.MENTOR)
    mem_intern_a = OrganizationMembership(organization_id=org_alpha.id, user_id=intern_a.id, role=UserRole.INTERN, mentor_membership_id=mem_mentor_a.id)

    mem_admin_b = OrganizationMembership(organization_id=org_beta.id, user_id=admin_b.id, role=UserRole.ADMIN)
    mem_mentor_b = OrganizationMembership(organization_id=org_beta.id, user_id=mentor_b.id, role=UserRole.MENTOR)
    mem_intern_b = OrganizationMembership(organization_id=org_beta.id, user_id=intern_b.id, role=UserRole.INTERN, mentor_membership_id=mem_mentor_b.id)

    db.add_all([mem_admin_a, mem_mentor_a, mem_intern_a, mem_admin_b, mem_mentor_b, mem_intern_b])
    db.flush()

    # Org Beta Resources
    project_b = Project(
        organization_id=org_beta.id,
        name="Beta Secret AI Project",
        description="Top Secret Research at Beta Univ",
        mentor_id=mentor_b.id,
        status=TaskStatus.TODO,
    )
    db.add(project_b)
    db.flush()

    task_b = Task(
        organization_id=org_beta.id,
        project_id=project_b.id,
        created_by_id=mentor_b.id,
        assigned_to=intern_b.id,
        title="Beta Confidential Task",
        status=TaskStatus.TODO,
    )
    db.add(task_b)

    att_b = Attendance(
        organization_id=org_beta.id,
        user_id=intern_b.id,
        date=date.today(),
        check_in=datetime.now(),
        status=AttendanceStatus.PRESENT,
        hours_worked=8.0,
    )
    db.add(att_b)

    leave_b = LeaveRequest(
        organization_id=org_beta.id,
        user_id=intern_b.id,
        start_date=date.today() + timedelta(days=2),
        end_date=date.today() + timedelta(days=3),
        reason="Beta conference",
        status=LeaveStatus.PENDING,
    )
    db.add(leave_b)

    db.commit()

    tokens = {
        "super_admin": generate_token(super_admin.id, super_admin.session_version),
        "admin_a": generate_token(admin_a.id, admin_a.session_version),
        "mentor_a": generate_token(mentor_a.id, mentor_a.session_version),
        "intern_a": generate_token(intern_a.id, intern_a.session_version),
        "admin_b": generate_token(admin_b.id, admin_b.session_version),
        "mentor_b": generate_token(mentor_b.id, mentor_b.session_version),
        "intern_b": generate_token(intern_b.id, intern_b.session_version),
    }

    client = TestClient(app)

    yield {
        "client": client,
        "tokens": tokens,
        "org_alpha": org_alpha,
        "org_beta": org_beta,
        "project_b": project_b,
        "task_b": task_b,
        "att_b": att_b,
        "leave_b": leave_b,
    }

    app.dependency_overrides.clear()


def test_cross_tenant_project_access_denied(test_setup):
    """Org A Admin attempting to read Org B Project returns 404 or 403."""
    client = test_setup["client"]
    token_a = test_setup["tokens"]["admin_a"]
    project_b_id = test_setup["project_b"].id

    resp = client.get(
        f"/api/projects/{project_b_id}",
        headers={"Authorization": f"Bearer {token_a}", "X-Organization-Id": "1"},
    )
    assert resp.status_code in (403, 404)


def test_cross_tenant_task_mutation_denied(test_setup):
    """Org A Intern attempting to move Org B Task status returns 403 or 404."""
    client = test_setup["client"]
    token_a = test_setup["tokens"]["intern_a"]
    task_b_id = test_setup["task_b"].id

    resp = client.patch(
        f"/api/projects/tasks/{task_b_id}/status",
        json={"status": "in_progress"},
        headers={"Authorization": f"Bearer {token_a}", "X-Organization-Id": "1"},
    )
    assert resp.status_code in (403, 404)


def test_cross_tenant_attendance_edit_denied(test_setup):
    """Org A Mentor attempting to edit Org B Intern Attendance returns 403 or 404."""
    client = test_setup["client"]
    token_a = test_setup["tokens"]["mentor_a"]
    att_b_id = test_setup["att_b"].id

    resp = client.put(
        f"/api/attendance/{att_b_id}",
        json={"reason": "Auditing", "check_in": "10:00:00", "check_out": "19:00:00"},
        headers={"Authorization": f"Bearer {token_a}", "X-Organization-Id": "1"},
    )
    assert resp.status_code in (403, 404)


def test_cross_tenant_leave_review_denied(test_setup):
    """Org A Admin attempting to review Org B Leave Request returns 403 or 404."""
    client = test_setup["client"]
    token_a = test_setup["tokens"]["admin_a"]
    leave_b_id = test_setup["leave_b"].id

    resp = client.post(
        f"/api/leave/{leave_b_id}/review",
        json={"decision": "approved"},
        headers={"Authorization": f"Bearer {token_a}", "X-Organization-Id": "1"},
    )
    assert resp.status_code in (403, 404)


def test_cross_tenant_search_does_not_leak_data(test_setup):
    """Org A Intern searching for Beta confidential keyword gets 0 results from Org B."""
    client = test_setup["client"]
    token_a = test_setup["tokens"]["intern_a"]

    resp = client.get(
        "/api/search?q=Secret",
        headers={"Authorization": f"Bearer {token_a}", "X-Organization-Id": "1"},
    )
    assert resp.status_code == 200
    data = resp.json()
    projects = data.get("projects", [])
    assert not any(p["name"] == "Beta Secret AI Project" for p in projects)


def test_platform_super_admin_vs_org_admin(test_setup):
    """Platform Super Admin can access /api/platform/organizations; Org Admin gets 403."""
    client = test_setup["client"]
    super_token = test_setup["tokens"]["super_admin"]
    admin_a_token = test_setup["tokens"]["admin_a"]

    # Super Admin succeeds
    resp_super = client.get(
        "/api/platform/organizations",
        headers={"Authorization": f"Bearer {super_token}"},
    )
    assert resp_super.status_code == 200
    data = resp_super.json()
    assert data["total"] >= 2

    # Org Admin fails with 403 Forbidden
    resp_org_admin = client.get(
        "/api/platform/organizations",
        headers={"Authorization": f"Bearer {admin_a_token}"},
    )
    assert resp_org_admin.status_code == 403


def test_organization_settings_lifecycle(test_setup):
    """Org Admin can retrieve and update their own organization settings."""
    client = test_setup["client"]
    admin_a_token = test_setup["tokens"]["admin_a"]

    # Get current org
    resp = client.get(
        "/api/org/current",
        headers={"Authorization": f"Bearer {admin_a_token}", "X-Organization-Id": "1"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["organization"]["slug"] == "alpha-corp"
    assert data["settings"]["leave_quota_days"] == 15

    # Update shift start time to 09:30:00
    resp_update = client.put(
        "/api/org/settings",
        json={"shift_start": "09:30:00", "leave_quota_days": 18},
        headers={"Authorization": f"Bearer {admin_a_token}", "X-Organization-Id": "1"},
    )
    assert resp_update.status_code == 200
    assert resp_update.json()["settings"]["shift_start"] == "09:30:00"
    assert resp_update.json()["settings"]["leave_quota_days"] == 18
