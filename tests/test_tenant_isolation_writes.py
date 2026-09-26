"""Cross-tenant write isolation (IDOR) regression suite.

An admin of Organization A — sending their own, honest X-Organization-Id — must not
be able to modify, delete, or reference records that belong to Organization B, and
org-wide admin actions (invite regenerate/deactivate, recycle bin) must only touch
their own organization.
"""
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Assignment,
    Attendance,
    AttendanceStatus,
    BlogPost,
    Cohort,
    CohortMember,
    InternInviteLink,
    Organization,
    OrganizationMembership,
    OrganizationSettings,
    OrganizationType,
    Project,
    ProjectAssignment,
    Task,
    TaskStatus,
    User,
    UserRole,
    _utcnow,
)


@pytest.fixture()
def env():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    db = Session()

    db.add_all([
        Organization(id=1, slug="alpha", name="Alpha", type=OrganizationType.BUSINESS),
        Organization(id=2, slug="beta", name="Beta", type=OrganizationType.BUSINESS),
    ])
    db.flush()
    db.add_all([OrganizationSettings(organization_id=1), OrganizationSettings(organization_id=2)])

    def mk(name, role, org):
        u = User(name=name, email=f"{name.lower().replace(' ', '.')}@x.test", role=role, is_active=True,
                 activated_at=_utcnow())
        u.set_password("Password123!")
        db.add(u)
        db.flush()
        db.add(OrganizationMembership(organization_id=org, user_id=u.id, role=role))
        return u

    admin_a = mk("Admin A", UserRole.ADMIN, 1)
    intern_a = mk("Intern A", UserRole.INTERN, 1)
    admin_b = mk("Admin B", UserRole.ADMIN, 2)
    mentor_b = mk("Mentor B", UserRole.MENTOR, 2)
    intern_b = mk("Intern B", UserRole.INTERN, 2)
    db.flush()

    project_a = Project(organization_id=1, name="Alpha Project", mentor_id=None, status=TaskStatus.TODO)
    project_b = Project(organization_id=2, name="Beta Project", mentor_id=mentor_b.id, status=TaskStatus.TODO)
    db.add_all([project_a, project_b])
    db.flush()
    db.add(ProjectAssignment(project_id=project_b.id, user_id=intern_b.id))
    task_b = Task(organization_id=2, project_id=project_b.id, created_by_id=mentor_b.id, assigned_to=intern_b.id,
                  title="Beta Task", status=TaskStatus.TODO)
    cohort_b = Cohort(organization_id=2, name="Beta Cohort")
    assignment_b = Assignment(organization_id=2, title="Beta Assignment", created_by_id=mentor_b.id)
    blog_b = BlogPost(organization_id=2, title="Beta Draft", slug="beta-draft", content="secret", status="draft")
    link_b = InternInviteLink(organization_id=2, token="beta-invite-token", created_by_id=admin_b.id, is_active=True)
    db.add_all([task_b, cohort_b, assignment_b, blog_b, link_b])
    db.flush()
    db.add(CohortMember(cohort_id=cohort_b.id, user_id=intern_b.id))
    db.add(Attendance(organization_id=2, user_id=intern_b.id, date=date.today(), check_in=_utcnow(),
                      status=AttendanceStatus.PRESENT))
    db.commit()

    ids = {
        "admin_a": admin_a.id, "intern_a": intern_a.id, "intern_b": intern_b.id, "mentor_b": mentor_b.id,
        "project_a": project_a.id, "project_b": project_b.id, "task_b": task_b.id, "cohort_b": cohort_b.id,
        "assignment_b": assignment_b.id, "blog_b": blog_b.id, "link_b": link_b.id,
    }
    tokens = {
        "admin_a": generate_token(admin_a.id, admin_a.session_version),
        "intern_a": generate_token(intern_a.id, intern_a.session_version),
        "admin_b": generate_token(admin_b.id, admin_b.session_version),
    }
    yield {"client": TestClient(app), "db": db, "ids": ids, "tokens": tokens}
    db.close()
    app.dependency_overrides.clear()


def _as(env, who="admin_a"):
    org = "2" if who.endswith("_b") else "1"
    return {"Authorization": f"Bearer {env['tokens'][who]}", "X-Organization-Id": org}


def _denied(resp):
    assert resp.status_code in (403, 404, 422), (resp.status_code, resp.text[:200])


def test_cannot_delete_or_edit_other_tenant_project_and_task(env):
    c, i, h = env["client"], env["ids"], _as(env)
    _denied(c.delete(f"/api/projects/{i['project_b']}", headers=h))
    _denied(c.put(f"/api/projects/tasks/{i['task_b']}", json={"title": "pwned"}, headers=h))
    _denied(c.patch(f"/api/projects/tasks/{i['task_b']}/status", json={"status": "done"}, headers=h))
    _denied(c.delete(f"/api/tasks/{i['task_b']}", headers=h))
    _denied(c.post(f"/api/projects/{i['project_b']}/tasks", json={"title": "x"}, headers=h))
    _denied(c.delete(f"/api/projects/{i['project_b']}/assign/{i['intern_b']}", headers=h))

    db = env["db"]
    db.expire_all()
    project = db.get(Project, i["project_b"])
    task = db.get(Task, i["task_b"])
    assert not project.is_deleted
    assert task.title == "Beta Task" and task.status == TaskStatus.TODO and not task.is_deleted


def test_cannot_reference_other_tenant_users_in_own_records(env):
    c, i, h = env["client"], env["ids"], _as(env)
    _denied(c.post(f"/api/projects/{i['project_a']}/assign", json={"intern_id": i["intern_b"]}, headers=h))
    _denied(c.post(f"/api/projects/{i['project_a']}/tasks",
                   json={"title": "x", "assigned_to": i["intern_b"]}, headers=h))
    _denied(c.post("/api/assignments", json={"title": "x", "project_id": i["project_b"]}, headers=h))
    _denied(c.post("/api/assignments", json={"title": "x", "assigned_to_user_id": i["intern_b"]}, headers=h))
    _denied(c.post("/api/announcements", json={"title": "x", "body": "y", "project_id": i["project_b"]}, headers=h))


def test_cannot_manage_other_tenant_users(env):
    c, i, h = env["client"], env["ids"], _as(env)
    _denied(c.put(f"/api/admin/users/{i['intern_b']}", json={"name": "pwned"}, headers=h))
    _denied(c.post(f"/api/admin/users/{i['intern_b']}/toggle", headers=h))
    _denied(c.post(f"/api/admin/users/{i['intern_b']}/role", json={"role": "mentor"}, headers=h))
    _denied(c.delete(f"/api/admin/users/{i['intern_b']}", headers=h))
    _denied(c.put(f"/api/admin/users/{i['intern_a']}", json={"mentor_id": i["mentor_b"]}, headers=h))

    db = env["db"]
    db.expire_all()
    victim = db.get(User, i["intern_b"])
    assert victim.name == "Intern B" and victim.is_active and not victim.is_deleted
    assert db.get(User, i["intern_a"]).mentor_id is None


def test_cannot_touch_other_tenant_assignment_blog_cohort(env):
    c, i, h = env["client"], env["ids"], _as(env)
    _denied(c.put(f"/api/assignments/{i['assignment_b']}", json={"title": "pwned"}, headers=h))
    _denied(c.delete(f"/api/assignments/{i['assignment_b']}", headers=h))
    _denied(c.delete(f"/api/blogs/{i['blog_b']}", headers=h))
    _denied(c.delete(f"/api/cohorts/{i['cohort_b']}/members/{i['intern_b']}", headers=h))

    db = env["db"]
    db.expire_all()
    assert not db.get(Assignment, i["assignment_b"]).is_deleted
    assert not db.get(BlogPost, i["blog_b"]).is_deleted
    assert db.query(CohortMember).filter_by(cohort_id=i["cohort_b"]).count() == 1

    listed = c.get("/api/blogs/admin/all", headers=h).json()["items"]
    assert all(p["id"] != i["blog_b"] for p in listed)


def test_org_wide_invite_actions_stay_in_own_org(env):
    c, i, h = env["client"], env["ids"], _as(env)
    _denied(c.delete(f"/api/admin/invite-link/{i['link_b']}", headers=h))
    assert c.post("/api/admin/invite-link/regenerate", headers=h).status_code == 200
    assert c.post("/api/admin/invite-link/deactivate", headers=h).status_code == 200

    db = env["db"]
    db.expire_all()
    link = db.get(InternInviteLink, i["link_b"])
    assert link is not None and link.is_active


def test_admin_dashboard_lists_only_own_org_interns(env):
    c, h = env["client"], _as(env)
    body = c.get("/api/dashboard/present-today", headers=h).text
    assert "Intern B" not in body
    body = c.get("/api/dashboard/open-tasks", headers=h).text
    assert "Beta Task" not in body


def test_leave_request_notifies_only_own_org_admins(env):
    from models import Notification

    c, i = env["client"], env["ids"]
    start = (date.today() + timedelta(days=10)).isoformat()
    resp = c.post("/api/leave", data={"start_date": start, "end_date": start, "reason": "trip", "leave_type": "casual"},
                  headers=_as(env, "intern_a"))
    assert resp.status_code in (200, 201), resp.text[:300]
    db = env["db"]
    db.expire_all()
    beta_ids = {i["mentor_b"], i["intern_b"]} | {
        u.id for u in db.query(User).filter(User.email == "admin.b@x.test")
    }
    assert db.query(Notification).filter(Notification.user_id.in_(beta_ids)).count() == 0


def test_manual_auto_checkout_only_touches_own_org(env):
    c, i, db = env["client"], env["ids"], env["db"]
    yesterday = date.today() - timedelta(days=1)
    open_b = Attendance(organization_id=2, user_id=i["intern_b"], date=yesterday, check_in=_utcnow(),
                        status=AttendanceStatus.PRESENT)
    db.add(open_b)
    db.commit()
    resp = c.post("/api/attendance/auto-checkout", headers=_as(env))
    assert resp.status_code == 200, resp.text[:200]
    db.expire_all()
    record = db.get(Attendance, open_b.id)
    assert record.check_out is None and record.status == AttendanceStatus.PRESENT


def test_recycle_bin_items_belong_to_the_deleting_org(env):
    c, i = env["client"], env["ids"]
    assert c.delete(f"/api/projects/{i['project_b']}", headers=_as(env, "admin_b")).status_code == 200

    def bin_titles(who):
        return [b["title"] for b in c.get("/api/admin/bin", headers=_as(env, who)).json()["items"]]

    assert "Beta Project" in bin_titles("admin_b")
    assert "Beta Project" not in bin_titles("admin_a")
    item = next(b for b in c.get("/api/admin/bin", headers=_as(env, "admin_b")).json()["items"]
                if b["title"] == "Beta Project")
    _denied(c.post(f"/api/admin/bin/{item['id']}/restore", headers=_as(env)))
    assert c.post(f"/api/admin/bin/{item['id']}/restore", headers=_as(env, "admin_b")).status_code == 200
