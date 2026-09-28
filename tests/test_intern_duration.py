"""Every intern gets one of their organization's duration tiers, and that tier's leaves drive the leave quota."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    InternInviteLink,
    InternshipDurationMaster,
    Organization,
    OrganizationMembership,
    OrganizationType,
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
    # Beta's own tiers: 2 months / 4 leaves (default) and 4 months / 9 leaves.
    db.add_all([
        InternshipDurationMaster(organization_id=2, title="Short", duration_months=2, leaves=4, is_default=True, order_index=0),
        InternshipDurationMaster(organization_id=2, title="Long", duration_months=4, leaves=9, order_index=1),
    ])
    users = {}
    for key, role, org in [("admin", UserRole.ADMIN, 2), ("mentor", UserRole.MENTOR, 2), ("alpha_admin", UserRole.ADMIN, 1)]:
        u = User(name=key.title(), email=f"{key}@x.test", role=role, is_active=True, activated_at=_utcnow())
        u.set_password("Passw0rd-123")
        db.add(u)
        db.flush()
        db.add(OrganizationMembership(organization_id=org, user_id=u.id, role=role))
        users[key] = u
    db.commit()

    def headers(key, org=2):
        u = users[key]
        return {"Authorization": f"Bearer {generate_token(u.id, u.session_version)}", "X-Organization-Id": str(org)}

    yield TestClient(app), headers, Session, users
    db.close()
    app.dependency_overrides.clear()


def _new_intern(client, headers, key="admin", **extra):
    body = {"name": "Priya Sharma", "email": "priya@x.test", "password": "Passw0rd-123", "role": "intern",
            "phone": "9876543210", "department": "Eng", "job_title": "Intern", **extra}
    return client.post("/api/admin/users", headers=headers(key), json=body)


def test_mentor_dropdown_shows_own_org_tiers(env):
    client, headers, *_ = env
    res = client.get("/api/admin/internship-durations/dropdown", headers=headers("mentor"))
    assert res.status_code == 200, res.text
    months = sorted(d["duration_months"] for d in res.json()["durations"])
    assert months == [2, 4]


def test_intern_without_duration_gets_default_tier(env):
    client, headers, Session, _ = env
    res = _new_intern(client, headers)
    assert res.status_code in (200, 201), res.text
    db = Session()
    u = db.query(User).filter_by(email="priya@x.test").one()
    assert u.internship_duration_months == 2
    m = db.query(OrganizationMembership).filter_by(user_id=u.id).one()
    assert m.internship_duration_months == 2


def test_invalid_duration_is_rejected(env):
    client, headers, *_ = env
    res = _new_intern(client, headers, internship_duration_months=6)
    assert res.status_code == 422
    assert "2, 4" in res.json()["detail"]


def test_leave_quota_follows_the_tier(env):
    client, headers, Session, _ = env
    assert _new_intern(client, headers, internship_duration_months=4).status_code in (200, 201)
    db = Session()
    u = db.query(User).filter_by(email="priya@x.test").one()
    token = {"Authorization": f"Bearer {generate_token(u.id, u.session_version)}", "X-Organization-Id": "2"}
    res = client.get("/api/leave/balance", headers=token)
    assert res.status_code == 200, res.text
    assert res.json()["quota"] == 9


def test_intern_duration_cannot_be_cleared(env):
    client, headers, Session, _ = env
    _new_intern(client, headers, internship_duration_months=4)
    uid = Session().query(User).filter_by(email="priya@x.test").one().id
    res = client.put(f"/api/admin/users/{uid}", headers=headers("admin"), json={"internship_duration_months": None})
    assert res.status_code == 422


def test_add_existing_account_as_intern_sets_duration(env):
    client, headers, Session, _ = env
    db = Session()
    u = User(name="Old Account", email="old@x.test", role=UserRole.INTERN, is_active=True, activated_at=_utcnow())
    u.set_password("Passw0rd-123")
    db.add(u)
    db.commit()
    res = client.post("/api/org/members", headers=headers("admin"),
                      json={"name": "", "email": "old@x.test", "role": "intern", "internship_duration_months": 4})
    assert res.status_code == 200, res.text
    db = Session()
    assert db.query(User).filter_by(email="old@x.test").one().internship_duration_months == 4


def test_signup_approval_sets_reviewers_duration(env):
    client, headers, Session, users = env
    db = Session()
    link = InternInviteLink(organization_id=2, token="tok-123", label="Drive", created_by_id=users["admin"].id)
    db.add(link)
    db.flush()
    intern = User(name="Joiner", email="join@x.test", role=UserRole.INTERN, is_active=False, signup_invite_link_id=link.id)
    intern.set_password("Passw0rd-123")
    db.add(intern)
    db.commit()
    res = client.post(f"/api/admin/intern-signup-requests/{intern.id}/review", headers=headers("admin"),
                      json={"decision": "approved", "internship_duration_months": 4})
    assert res.status_code == 200, res.text
    db = Session()
    approved = db.query(User).filter_by(email="join@x.test").one()
    assert approved.is_active and approved.internship_duration_months == 4
    assert db.query(OrganizationMembership).filter_by(user_id=approved.id, organization_id=2).one().internship_duration_months == 4


def test_intern_counts_are_per_organization(env):
    client, headers, Session, _ = env
    _new_intern(client, headers, internship_duration_months=4)
    # An Alpha intern with the same months must not count for Beta.
    db = Session()
    other = User(name="Alpha Intern", email="a@x.test", role=UserRole.INTERN, is_active=True, internship_duration_months=4)
    other.set_password("Passw0rd-123")
    db.add(other)
    db.flush()
    db.add(OrganizationMembership(organization_id=1, user_id=other.id, role=UserRole.INTERN))
    db.commit()
    res = client.get("/api/admin/internship-durations/dropdown", headers=headers("admin"))
    long = next(d for d in res.json()["durations"] if d["duration_months"] == 4)
    assert long["intern_count"] == 1


def _tier_id(Session, months):
    return Session().query(InternshipDurationMaster).filter_by(organization_id=2, duration_months=months).one().id


def test_changing_a_tiers_months_moves_its_interns(env):
    client, headers, Session, _ = env
    _new_intern(client, headers, internship_duration_months=4)
    res = client.put(f"/api/admin/internship-durations/{_tier_id(Session, 4)}", headers=headers("admin"),
                     json={"title": "Long", "duration_months": 5, "duration_days": 150, "leaves": 9})
    assert res.status_code == 200, res.text
    db = Session()
    u = db.query(User).filter_by(email="priya@x.test").one()
    assert u.internship_duration_months == 5
    assert db.query(OrganizationMembership).filter_by(user_id=u.id).one().internship_duration_months == 5


def test_tier_in_use_cannot_be_turned_off_or_deleted(env):
    client, headers, Session, _ = env
    _new_intern(client, headers, internship_duration_months=4)
    tid = _tier_id(Session, 4)
    off = client.put(f"/api/admin/internship-durations/{tid}", headers=headers("admin"),
                     json={"title": "Long", "duration_months": 4, "duration_days": 120, "leaves": 9, "is_active": False})
    assert off.status_code == 422 and "1 intern" in off.json()["detail"]
    gone = client.delete(f"/api/admin/internship-durations/{tid}", headers=headers("admin"))
    assert gone.status_code == 422
    # An unused tier can still be turned off.
    unused = client.put(f"/api/admin/internship-durations/{_tier_id(Session, 2)}", headers=headers("admin"),
                        json={"title": "Short", "duration_months": 2, "duration_days": 60, "leaves": 4, "is_active": False})
    assert unused.status_code == 200, unused.text


def test_role_change_to_intern_gets_default_duration(env):
    client, headers, Session, users = env
    res = client.post(f"/api/admin/users/{users['mentor'].id}/role", headers=headers("admin"), json={"role": "intern"})
    assert res.status_code == 200, res.text
    assert Session().get(User, users["mentor"].id).internship_duration_months == 2


def test_backfill_migration_gives_interns_the_default(env):
    import importlib
    _client, _headers, Session, _ = env
    db = Session()
    # Legacy interns: the column default of 3 months (no such tier in Beta), and one already on a real tier.
    u = User(name="Legacy", email="legacy@x.test", role=UserRole.INTERN, is_active=True)
    ok = User(name="Fine", email="fine@x.test", role=UserRole.INTERN, is_active=True, internship_duration_months=4)
    for x in (u, ok):
        x.set_password("Passw0rd-123")
        db.add(x)
    db.flush()
    assert u.internship_duration_months == 3
    db.add_all([
        OrganizationMembership(organization_id=2, user_id=u.id, role=UserRole.INTERN),
        OrganizationMembership(organization_id=2, user_id=ok.id, role=UserRole.INTERN),
    ])
    db.commit()
    migration = importlib.import_module("migrations.20260929_intern_duration_backfill")
    migration.upgrade(db.get_bind())
    migration.upgrade(db.get_bind())  # idempotent
    db = Session()
    assert db.query(User).filter_by(email="legacy@x.test").one().internship_duration_months == 2
    assert db.query(User).filter_by(email="fine@x.test").one().internship_duration_months == 4
