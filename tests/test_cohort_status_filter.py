"""GET /api/cohorts?status= filters by the cohort's dates across all pages, not per page in the app."""
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import Cohort, Organization, OrganizationMembership, OrganizationType, User, UserRole, _utcnow
from utils import local_today


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
    admin = User(name="Sneha Kulkarni", email="admin@x.test", role=UserRole.ADMIN, is_active=True, activated_at=_utcnow())
    admin.set_password("Passw0rd-123")
    db.add(admin)
    db.flush()
    db.add(OrganizationMembership(organization_id=1, user_id=admin.id, role=UserRole.ADMIN))

    today = local_today()
    for name, start, end in [
        ("Past batch", today - timedelta(days=90), today - timedelta(days=1)),
        ("Current batch", today - timedelta(days=10), today + timedelta(days=30)),
        ("Open-ended batch", None, None),
        ("Next batch", today + timedelta(days=5), today + timedelta(days=60)),
    ]:
        db.add(Cohort(name=name, organization_id=1, start_date=start, end_date=end, created_by_id=admin.id))
    db.commit()
    headers = {"Authorization": f"Bearer {generate_token(admin.id, admin.session_version)}", "X-Organization-Id": "1"}
    yield TestClient(app), headers
    db.close()
    app.dependency_overrides.clear()


def _names(client, headers, status):
    res = client.get("/api/cohorts", headers=headers, params={"status": status} if status else None)
    assert res.status_code == 200, res.text
    body = res.json()
    return sorted(c["name"] for c in body["items"]), body["total"]


def test_status_filter(env):
    client, headers = env
    assert _names(client, headers, "completed") == (["Past batch"], 1)
    assert _names(client, headers, "active") == (["Current batch", "Open-ended batch"], 2)
    assert _names(client, headers, "upcoming") == (["Next batch"], 1)
    assert _names(client, headers, None)[1] == 4


def test_unknown_status_rejected(env):
    client, headers = env
    assert client.get("/api/cohorts", headers=headers, params={"status": "bogus"}).status_code == 422
