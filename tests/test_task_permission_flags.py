"""Task payloads say what the viewer may do (can_move / can_edit / can_delete), matching what the API enforces."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import Organization, OrganizationMembership, OrganizationType, User, UserRole, _utcnow


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
    db.add(Organization(id=1, slug="alpha", name="Alpha", type=OrganizationType.BUSINESS))
    users = {}
    for key, name, role in [
        ("admin", "Sneha Kulkarni", UserRole.ADMIN),
        ("mentor", "Rohit Pawar", UserRole.MENTOR),
        ("assignee", "Aarav Deshmukh", UserRole.INTERN),
        ("peer", "Isha Joshi", UserRole.INTERN),
    ]:
        u = User(name=name, email=f"{key}@x.test", role=role, is_active=True, activated_at=_utcnow())
        u.set_password("Passw0rd-123")
        db.add(u)
        db.flush()
        db.add(OrganizationMembership(organization_id=1, user_id=u.id, role=role))
        users[key] = u
    db.commit()

    def headers(key):
        u = users[key]
        return {"Authorization": f"Bearer {generate_token(u.id, u.session_version)}", "X-Organization-Id": "1"}

    c = TestClient(app)
    resp = c.post("/api/projects", headers=headers("admin"), json={
        "name": "PMPML Bus Tracker", "mentor_ids": [users["mentor"].id],
        "intern_ids": [users["assignee"].id, users["peer"].id],
    })
    assert resp.status_code in (200, 201), resp.text
    pid = resp.json().get("id") or resp.json()["project"]["id"]
    resp = c.post(f"/api/projects/{pid}/tasks", headers=headers("admin"), json={
        "title": "GTFS feed import", "assigned_to": users["assignee"].id, "priority": "high",
    })
    assert resp.status_code in (200, 201), resp.text
    tid = resp.json().get("id") or resp.json()["task"]["id"]
    yield {"client": c, "headers": headers, "pid": pid, "tid": tid}
    db.close()
    app.dependency_overrides.clear()


def _flags(env, who):
    project = env["client"].get(f"/api/projects/{env['pid']}", headers=env["headers"](who)).json()
    task = next(t for t in project["tasks"] if t["id"] == env["tid"])
    return task["can_move"], task["can_edit"], task["can_delete"]


def test_flags_per_role(env):
    assert _flags(env, "admin") == (True, True, True)
    assert _flags(env, "mentor") == (True, True, True)
    assert _flags(env, "assignee")[:2] == (True, True)
    assert _flags(env, "peer") == (True, False, False)  # another intern on the project: status only


def test_flags_match_what_the_api_allows(env):
    c, h, tid = env["client"], env["headers"], env["tid"]
    assert c.put(f"/api/projects/tasks/{tid}", headers=h("peer"), json={"title": "Renamed"}).status_code == 403
    assert c.put(f"/api/projects/tasks/{tid}", headers=h("peer"), json={"status": "in_progress"}).status_code == 200
    assert c.put(f"/api/projects/tasks/{tid}", headers=h("assignee"), json={"title": "GTFS import v2"}).status_code == 200
    assert c.delete(f"/api/tasks/{tid}", headers=h("peer")).status_code == 403
    assert c.delete(f"/api/tasks/{tid}", headers=h("admin")).status_code == 200
