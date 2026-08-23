"""Lead capture API tests — public POST with honeypot/rate-limit + superadmin read-only list."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import Organization, OrganizationStatus, OrganizationType, User, UserRole
from services.redis_service import RedisService


@pytest.fixture()
def client():
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
    org = Organization(
        id=1,
        slug="techcorp",
        name="TechCorp Global",
        type=OrganizationType.BUSINESS,
        status=OrganizationStatus.ACTIVE,
    )
    db.add(org)

    super_admin = User(
        name="Super Admin",
        email="superadmin@test.local",
        role=UserRole.ADMIN,
        is_platform_admin=True,
        is_active=True,
        session_version=1,
    )
    super_admin.set_password("SuperPass123!")
    org_admin = User(
        name="Org Admin",
        email="admin@test.local",
        role=UserRole.ADMIN,
        is_active=True,
        session_version=1,
    )
    org_admin.set_password("AdminPass123!")
    intern = User(
        name="Intern Bob",
        email="intern@test.local",
        role=UserRole.INTERN,
        is_active=True,
        session_version=1,
    )
    intern.set_password("InternPass123!")
    db.add_all([super_admin, org_admin, intern])
    db.commit()

    tokens = {
        "super_admin": generate_token(super_admin.id, super_admin.session_version),
        "org_admin": generate_token(org_admin.id, org_admin.session_version),
        "intern": generate_token(intern.id, intern.session_version),
    }
    yield TestClient(app), TestingSessionLocal, tokens
    app.dependency_overrides.pop(get_db, None)
    # Reset the per-IP lead bucket so tests stay isolated.
    RedisService.delete("rate_limit:leads:testclient")
    db.close()
    engine.dispose()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _lead_payload(**overrides) -> dict:
    payload = {
        "name": "Alex Morgan",
        "email": "Alex@AcmeCorp.com",
        "company": "Acme Corp",
        "role": "Engineering Lead",
        "cohort_size": "16-50 interns",
        "message": "We want a demo for our summer cohort.",
    }
    payload.update(overrides)
    return payload


def test_create_lead_publicly_and_list_as_superadmin(client):
    tc, SessionLocal, tokens = client

    res = tc.post("/api/leads", json=_lead_payload())
    assert res.status_code == 200
    assert res.json() == {"ok": True}

    data = tc.get("/api/platform/leads", headers=_auth(tokens["super_admin"])).json()
    assert data["total"] == 1
    lead = data["items"][0]
    assert lead["name"] == "Alex Morgan"
    assert lead["email"] == "alex@acmecorp.com"  # normalized to lowercase
    assert lead["status"] == "new"
    assert lead["source"] == "marketing_site"
    assert lead["company"] == "Acme Corp"


def test_missing_or_invalid_fields_rejected(client):
    tc, _, _ = client

    missing_email = {k: v for k, v in _lead_payload().items() if k != "email"}
    assert tc.post("/api/leads", json=missing_email).status_code == 422

    bad_email = _lead_payload(email="not-an-email")
    assert tc.post("/api/leads", json=bad_email).status_code == 422

    empty_body = tc.post("/api/leads")
    assert empty_body.status_code == 422


def test_honeypot_silently_discards_bot_submissions(client):
    tc, SessionLocal, tokens = client

    res = tc.post("/api/leads", json=_lead_payload(website="http://spam.example"))
    assert res.status_code == 200
    assert res.json() == {"ok": True}

    data = tc.get("/api/platform/leads", headers=_auth(tokens["super_admin"])).json()
    assert data["total"] == 0


def test_rate_limit_blocks_flood(client):
    tc, _, tokens = client

    for i in range(5):
        res = tc.post("/api/leads", json=_lead_payload(name=f"Lead {i}", email=f"lead{i}@acme.com"))
        assert res.status_code == 200

    flooded = tc.post("/api/leads", json=_lead_payload(name="Overflow", email="overflow@acme.com"))
    assert flooded.status_code == 429

    # Superadmin still sees exactly the five accepted leads.
    data = tc.get("/api/platform/leads", headers=_auth(tokens["super_admin"])).json()
    assert data["total"] == 5


def test_platform_list_requires_platform_admin(client):
    tc, _, tokens = client

    assert tc.get("/api/platform/leads").status_code == 401
    assert tc.get("/api/platform/leads", headers=_auth(tokens["intern"])).status_code == 403
    # Org-level admins are not platform admins.
    assert tc.get("/api/platform/leads", headers=_auth(tokens["org_admin"])).status_code == 403


def test_search_status_and_pagination_filters(client):
    tc, SessionLocal, tokens = client

    leads = [
        _lead_payload(name="Dana Tech", email="dana@zeta.com"),
        _lead_payload(name="Evan Corp", email="evan@acme.com", company="Zeta Labs"),
        _lead_payload(name="Fiona Flow", email="fiona@flow.com"),
    ]
    for lead in leads:
        assert tc.post("/api/leads", json=lead).status_code == 200

    assert tc.get("/api/platform/leads", params={"search": "zeta"}, headers=_auth(tokens["super_admin"])).json()["total"] == 2
    assert tc.get("/api/platform/leads", params={"search": "fiona@flow.com"}, headers=_auth(tokens["super_admin"])).json()["total"] == 1
    assert tc.get("/api/platform/leads", params={"status": "new"}, headers=_auth(tokens["super_admin"])).json()["total"] == 3

    paged = tc.get(
        "/api/platform/leads",
        params={"page": 2, "page_size": 2},
        headers=_auth(tokens["super_admin"]),
    ).json()
    assert paged["total"] == 3
    assert len(paged["items"]) == 1

    # Newest first ordering.
    first_page = tc.get(
        "/api/platform/leads",
        params={"page_size": 3},
        headers=_auth(tokens["super_admin"]),
    ).json()
    assert [i["email"] for i in first_page["items"]] == ["fiona@flow.com", "evan@acme.com", "dana@zeta.com"]
