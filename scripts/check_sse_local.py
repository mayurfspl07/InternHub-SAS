"""Bisect where check_sse_local hangs."""
import os

os.environ.setdefault("BOOTSTRAP_ADMIN_PASSWORD", "test-bootstrap-pw")

print("1: starting imports", flush=True)
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from models import Notification, Organization, User, UserRole

engine = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
Base.metadata.create_all(bind=engine)
TestSession = sessionmaker(bind=engine)
db = TestSession()

org = Organization(name="SSE Org", slug="sseorg")
db.add(org)
db.commit()
user = User(
    name="SSE User",
    email="sse@test.com",
    password_hash="x",
    role=UserRole.INTERN,
    is_active=True,
    session_version=1,
)
db.add(user)
db.commit()
db.add(Notification(user_id=user.id, message="hello", is_read=False))
db.add(Notification(user_id=user.id, message="world", is_read=False))
db.commit()
print("2: db seeded", flush=True)

from main import app

print("3: main imported", flush=True)

import database
import routes.api.notifications as notif

app.dependency_overrides[get_db] = lambda: db
database.SessionLocal = TestSession
notif.SessionLocal = TestSession
print("4: overrides set", flush=True)

client = TestClient(app)
token = generate_token(user.id, user.session_version)
print("5: client ready, opening stream", flush=True)

with client.stream(
    "GET", "/api/notifications/stream", headers={"Authorization": f"Bearer {token}"},
    timeout=20.0,
) as resp:
    print("6: response:", resp.status_code, resp.headers.get("content-type"), flush=True)
    got = []
    for line in resp.iter_lines():
        print("  line:", line, flush=True)
        if line:
            got.append(line)
        if len(got) >= 2:
            break
    print("7: SSE OK, lines:", got, flush=True)
