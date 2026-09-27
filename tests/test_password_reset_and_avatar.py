"""Password reset by e-mailed code, and avatar persistence."""
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import email_service
from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Organization,
    OrganizationMembership,
    OrganizationType,
    PasswordResetCode,
    User,
    UserRole,
    _utcnow,
)

PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4"
       b"\x89\x00\x00\x00\rIDATx\x9cc\xf8\xcf\xc0\xf0\x1f\x00\x05\x00\x01\xff\x89\x99=\x1d\x00\x00\x00\x00IEND"
       b"\xaeB`\x82")


@pytest.fixture()
def env(monkeypatch):
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
    user = User(name="Omkar Jadhav", email="omkar@x.test", role=UserRole.INTERN, is_active=True, activated_at=_utcnow())
    user.set_password("OldPass123")
    db.add(user)
    db.flush()
    db.add(OrganizationMembership(organization_id=1, user_id=user.id, role=UserRole.INTERN))
    db.commit()

    from utils import reset_login_attempts

    for key in ("reset-request:testclient", "reset-verify:testclient", "testclient"):
        reset_login_attempts(key)  # the limiter is process-wide; start each test with a clean count
    sent = []
    monkeypatch.setattr(email_service, "send_password_reset_email",
                        lambda _db, org_id, u, code, minutes: sent.append({"org": org_id, "email": u.email,
                                                                           "code": code, "minutes": minutes}))
    yield {"client": TestClient(app), "db": db, "user": user, "sent": sent}
    db.close()
    app.dependency_overrides.clear()


def _forgot(c, email):
    return c.post("/api/auth/password/forgot", json={"email": email})


def _reset(c, email, code, pw="NewPass2026"):
    return c.post("/api/auth/password/reset",
                  json={"email": email, "code": code, "new_password": pw, "confirm_password": pw})


def test_reset_with_emailed_code_changes_password_and_revokes_sessions(env):
    c, db, user, sent = env["client"], env["db"], env["user"], env["sent"]
    old_token = generate_token(user.id, user.session_version)

    resp = _forgot(c, "Omkar@X.test")
    assert resp.status_code == 200
    assert sent and sent[0]["email"] == "omkar@x.test" and sent[0]["org"] == 1 and len(sent[0]["code"]) == 6

    resp = _reset(c, "omkar@x.test", sent[0]["code"])
    assert resp.status_code == 200, resp.text
    assert c.post("/api/auth/login", json={"email": "omkar@x.test", "password": "NewPass2026"}).status_code == 200
    assert c.post("/api/auth/login", json={"email": "omkar@x.test", "password": "OldPass123"}).status_code == 401
    assert c.get("/api/auth/me", headers={"Authorization": f"Bearer {old_token}"}).status_code == 401
    # The code is single-use.
    assert _reset(c, "omkar@x.test", sent[0]["code"], pw="Another2026").status_code == 422


def test_unknown_email_gets_the_same_answer_and_no_mail(env):
    c, sent = env["client"], env["sent"]
    known = _forgot(c, "omkar@x.test")
    unknown = _forgot(c, "nobody@x.test")
    assert known.status_code == unknown.status_code == 200
    assert known.json() == unknown.json()
    assert len(sent) == 1


def test_wrong_code_is_refused_and_attempts_are_capped(env):
    c, db, sent = env["client"], env["db"], env["sent"]
    _forgot(c, "omkar@x.test")
    real = sent[0]["code"]
    wrong = "000000" if real != "000000" else "111111"
    for _ in range(PasswordResetCode.MAX_ATTEMPTS):
        assert _reset(c, "omkar@x.test", wrong).status_code == 422
    # Even the right code no longer works once the attempts are used up.
    assert _reset(c, "omkar@x.test", real).status_code == 422


def test_expired_code_is_refused(env):
    c, db, sent = env["client"], env["db"], env["sent"]
    _forgot(c, "omkar@x.test")
    reset = db.query(PasswordResetCode).one()
    reset.expires_at = _utcnow() - timedelta(minutes=1)
    db.commit()
    assert _reset(c, "omkar@x.test", sent[0]["code"]).status_code == 422


def test_a_new_request_invalidates_the_previous_code(env):
    c, sent = env["client"], env["sent"]
    _forgot(c, "omkar@x.test")
    _forgot(c, "omkar@x.test")
    first, second = sent[0]["code"], sent[1]["code"]
    if first != second:
        assert _reset(c, "omkar@x.test", first).status_code == 422
    assert _reset(c, "omkar@x.test", second).status_code == 200


def test_weak_new_password_is_refused(env):
    c, sent = env["client"], env["sent"]
    _forgot(c, "omkar@x.test")
    assert _reset(c, "omkar@x.test", sent[0]["code"], pw="short").status_code == 422


def test_avatar_upload_is_saved_on_the_user(env):
    c, db, user = env["client"], env["db"], env["user"]
    h = {"Authorization": f"Bearer {generate_token(user.id, user.session_version)}"}
    resp = c.post("/api/upload/avatar", headers=h, files={"file": ("me.png", PNG, "image/png")})
    assert resp.status_code == 200, resp.text
    url = resp.json()["avatar_url"]
    assert url
    assert c.get("/api/auth/me", headers=h).json()["avatar_url"] == url
    assert c.get("/api/profile", headers=h).json()["avatar_url"] == url


def test_null_and_unsent_fields_keep_real_values(env):
    """A JSON null is never saved as the text "None", and fields left out of a PUT keep their values."""
    c, db = env["client"], env["db"]
    admin = User(name="Sneha Kulkarni", email="sneha@x.test", role=UserRole.ADMIN, is_active=True, activated_at=_utcnow())
    admin.set_password("AdminPass123")
    db.add(admin)
    db.flush()
    db.add(OrganizationMembership(organization_id=1, user_id=admin.id, role=UserRole.ADMIN))
    db.commit()
    h = {"Authorization": f"Bearer {generate_token(admin.id, admin.session_version)}", "X-Organization-Id": "1"}

    resp = c.post("/api/admin/users", headers=h, json={
        "name": "Rohit Pawar", "email": "rohit@x.test", "password": "Intern2026x", "role": "mentor",
        "phone": "9876543210", "job_title": None, "department": None,
    })
    assert resp.status_code in (200, 201), resp.text
    created = db.query(User).filter_by(email="rohit@x.test").one()
    assert created.job_title is None and created.department is None

    resp = c.post("/api/projects", headers=h, json={"name": None, "description": None})
    assert resp.status_code in (400, 422)  # a null name is missing, not a project called "None"

    mentor_id = created.id
    resp = c.post("/api/projects", headers=h, json={"name": "Krishi Mitra", "description": "Crop price alerts",
                                                   "mentor_ids": [mentor_id], "end_date": "2026-12-31"})
    assert resp.status_code in (200, 201), resp.text
    pid = resp.json().get("id") or resp.json()["project"]["id"]
    resp = c.put(f"/api/projects/{pid}", headers=h, json={"status": "on_hold"})  # a partial update
    assert resp.status_code == 200, resp.text
    detail = c.get(f"/api/projects/{pid}", headers=h).json()
    project = detail.get("project", detail)
    assert project["name"] == "Krishi Mitra" and project["description"] == "Crop price alerts"
    assert project["end_date"] == "2026-12-31"
