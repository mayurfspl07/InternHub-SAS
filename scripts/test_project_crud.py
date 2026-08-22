"""Comprehensive Project & Task CRUD verification test runner with full response formatting."""
import json
import os
import sys

# Ensure root backend dir is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from datetime import date, timedelta
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base, get_db
from dependencies import generate_token
from main import app
from models import (
    Organization,
    OrganizationMembership,
    OrganizationSettings,
    OrganizationStatus,
    OrganizationType,
    User,
    UserRole,
    _utcnow,
)


def pretty(data) -> str:
    return json.dumps(data, indent=2, default=str)


def run_project_crud_tests():
    print("=" * 80)
    print("       INTERNHUB - PROJECT & TASK CRUD TEST SUITE (WITH RESPONSES)")
    print("=" * 80)

    # 1. Setup in-memory SQLite DB
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    db = TestingSession()

    def override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db

    # 2. Seed Tenant, Admin, Mentor, Intern
    org = Organization(
        name="TechCorp Global",
        slug="techcorp",
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
    )
    db.add(settings)

    admin = User(
        name="Admin Alex",
        email="admin@techcorp.com",
        role=UserRole.ADMIN,
        is_active=True,
        activated_at=_utcnow(),
    )
    admin.set_password("AdminPass123!")

    mentor = User(
        name="Mentor Sarah",
        email="mentor.sarah@techcorp.com",
        role=UserRole.MENTOR,
        is_active=True,
        activated_at=_utcnow(),
    )
    mentor.set_password("MentorPass123!")

    intern1 = User(
        name="Intern Bob",
        email="bob@techcorp.com",
        role=UserRole.INTERN,
        is_active=True,
        activated_at=_utcnow(),
    )
    intern1.set_password("InternPass123!")

    intern2 = User(
        name="Intern Alice",
        email="alice@techcorp.com",
        role=UserRole.INTERN,
        is_active=True,
        activated_at=_utcnow(),
    )
    intern2.set_password("InternPass123!")

    db.add_all([admin, mentor, intern1, intern2])
    db.flush()

    for u in [admin, mentor, intern1, intern2]:
        db.add(
            OrganizationMembership(
                user_id=u.id,
                organization_id=org.id,
                role=u.role,
                is_active=True,
            )
        )
    db.commit()

    client = TestClient(app)

    def auth_headers(user: User):
        token = generate_token(user.id, user.session_version)
        return {
            "Authorization": f"Bearer {token}",
            "X-Organization-Id": str(org.id),
        }

    admin_hdr = auth_headers(admin)
    mentor_hdr = auth_headers(mentor)
    intern_hdr = auth_headers(intern1)

    print(f"[SETUP] Created Org (id={org.id}), Admin (id={admin.id}), Mentor (id={mentor.id}), Intern1 (id={intern1.id}), Intern2 (id={intern2.id})\n")

    # --------------------------------------------------------------------------
    # 1. CREATE PROJECT (POST /api/projects)
    # --------------------------------------------------------------------------
    print(">>> 1. CREATE PROJECT (POST /api/projects)")
    create_payload = {
        "name": "Cloud Migration Platform",
        "description": "Migrate core infrastructure to microservices on AWS/Kubernetes.",
        "mentor_ids": [mentor.id],
        "intern_ids": [intern1.id],
        "start_date": (date.today() - timedelta(days=5)).isoformat(),
        "end_date": (date.today() + timedelta(days=45)).isoformat(),
        "status": "active",
    }
    resp = client.post("/api/projects", json=create_payload, headers=admin_hdr)
    assert resp.status_code == 200, f"Failed create project: {resp.status_code} {resp.text}"
    project_data = resp.json()
    project_id = project_data["id"]
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(project_data)}\n")

    # --------------------------------------------------------------------------
    # 2. READ SINGLE PROJECT (GET /api/projects/{id})
    # --------------------------------------------------------------------------
    print(f">>> 2. READ SINGLE PROJECT (GET /api/projects/{project_id})")
    resp = client.get(f"/api/projects/{project_id}", headers=admin_hdr)
    assert resp.status_code == 200, f"Failed get project: {resp.status_code}"
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 3. LIST & SEARCH PROJECTS (GET /api/projects, GET /api/projects/search)
    # --------------------------------------------------------------------------
    print(">>> 3. LIST PROJECTS WITH FILTERS (GET /api/projects?status=active)")
    resp = client.get("/api/projects?status=active", headers=admin_hdr)
    assert resp.status_code == 200
    list_data = resp.json()
    print(f"Status Code: {resp.status_code}, Total: {list_data.get('total')}")
    print(f"Response:\n{pretty(list_data)}\n")

    print(">>> 3b. SEARCH PROJECTS (GET /api/projects/search?q=Migration)")
    resp = client.get("/api/projects/search?q=Migration", headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}, Results:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 4. UPDATE PROJECT (PUT /api/projects/{id})
    # --------------------------------------------------------------------------
    print(f">>> 4. UPDATE PROJECT (PUT /api/projects/{project_id})")
    update_payload = {
        "name": "Cloud Migration Platform v2",
        "description": "Updated scope with automated CI/CD pipeline deployment.",
        "status": "in_progress",
        "mentor_ids": [mentor.id],
    }
    resp = client.put(f"/api/projects/{project_id}", json=update_payload, headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 5. ASSIGN ADDITIONAL INTERN (POST /api/projects/{id}/assign)
    # --------------------------------------------------------------------------
    print(f">>> 5. ASSIGN INTERN 2 TO PROJECT (POST /api/projects/{project_id}/assign)")
    resp = client.post(f"/api/projects/{project_id}/assign", json={"user_id": intern2.id}, headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 6. CREATE TASK (POST /api/projects/{id}/tasks)
    # --------------------------------------------------------------------------
    print(f">>> 6. CREATE TASK (POST /api/projects/{project_id}/tasks)")
    task_payload = {
        "title": "Setup Docker Compose & Terraform",
        "description": "Define declarative infra for staging and production clusters.",
        "assigned_to": intern1.id,
        "deadline": (date.today() + timedelta(days=7)).isoformat(),
        "priority": "high",
        "status": "todo",
    }
    resp = client.post(f"/api/projects/{project_id}/tasks", json=task_payload, headers=mentor_hdr)
    assert resp.status_code == 200
    task_data = resp.json()
    task_id = task_data["id"]
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(task_data)}\n")

    # --------------------------------------------------------------------------
    # 7. UPDATE TASK DETAILS & STATUS (PUT & PATCH)
    # --------------------------------------------------------------------------
    print(f">>> 7a. UPDATE TASK DETAILS (PUT /api/projects/tasks/{task_id})")
    task_update = {
        "title": "Setup Docker Compose, Helm & Terraform",
        "priority": "critical",
    }
    resp = client.put(f"/api/projects/tasks/{task_id}", json=task_update, headers=mentor_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    print(f">>> 7b. MOVE TASK TO IN_PROGRESS (PATCH /api/projects/tasks/{task_id}/status)")
    resp = client.patch(f"/api/projects/tasks/{task_id}/status", json={"status": "in_progress"}, headers=intern_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 8. TASK COMMENTS (POST, GET, DELETE)
    # --------------------------------------------------------------------------
    print(f">>> 8a. POST TASK COMMENT (POST /api/projects/tasks/{task_id}/comments)")
    resp = client.post(
        f"/api/projects/tasks/{task_id}/comments",
        json={"body": "Initial Terraform scripts tested in staging VPC."},
        headers=intern_hdr,
    )
    assert resp.status_code == 200
    comment_data = resp.json()
    comment_id = comment_data["id"]
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(comment_data)}\n")

    print(f">>> 8b. GET TASK COMMENTS (GET /api/projects/tasks/{task_id}/comments)")
    resp = client.get(f"/api/projects/tasks/{task_id}/comments", headers=mentor_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    print(f">>> 8c. DELETE TASK COMMENT (DELETE /api/projects/tasks/comments/{comment_id})")
    resp = client.delete(f"/api/projects/tasks/comments/{comment_id}", headers=intern_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 9. PROJECT DISCUSSION BOARD (POST, GET, DELETE)
    # --------------------------------------------------------------------------
    print(f">>> 9a. POST TO PROJECT BOARD (POST /api/projects/{project_id}/comments-board)")
    resp = client.post(
        f"/api/projects/{project_id}/comments-board",
        json={"body": "Welcome team! Please review architecture docs before sprint planning."},
        headers=mentor_hdr,
    )
    assert resp.status_code == 200
    board_comment = resp.json()
    board_id = board_comment["id"]
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(board_comment)}\n")

    print(f">>> 9b. GET PROJECT BOARD COMMENTS (GET /api/projects/{project_id}/comments-board)")
    resp = client.get(f"/api/projects/{project_id}/comments-board", headers=intern_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    print(f">>> 9c. DELETE BOARD COMMENT (DELETE /api/projects/comments-board/{board_id})")
    resp = client.delete(f"/api/projects/comments-board/{board_id}", headers=mentor_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 10. PROJECT ASSETS / LINKS (POST, GET, DELETE)
    # --------------------------------------------------------------------------
    print(f">>> 10a. ADD PROJECT RESOURCE LINK (POST /api/projects/{project_id}/links)")
    resp = client.post(
        f"/api/projects/{project_id}/links",
        json={"link": "https://aws.amazon.com/architecture", "remark": "AWS Architecture Diagram"},
        headers=mentor_hdr,
    )
    assert resp.status_code == 200, f"Failed add link: {resp.status_code} {resp.text}"
    link_data = resp.json()
    link_id = link_data["id"]
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(link_data)}\n")

    print(f">>> 10b. GET PROJECT LINKS (GET /api/projects/{project_id}/links)")
    resp = client.get(f"/api/projects/{project_id}/links", headers=intern_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    print(f">>> 10c. DELETE PROJECT LINK (DELETE /api/projects/links/{link_id})")
    resp = client.delete(f"/api/projects/links/{link_id}", headers=mentor_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 11. REMOVE ASSIGNED INTERN (DELETE /api/projects/{id}/assign/{uid})
    # --------------------------------------------------------------------------
    print(f">>> 11. REMOVE INTERN 2 FROM PROJECT (DELETE /api/projects/{project_id}/assign/{intern2.id})")
    resp = client.delete(f"/api/projects/{project_id}/assign/{intern2.id}", headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    # --------------------------------------------------------------------------
    # 12. EXPORT PROJECT DETAILS (GET /api/projects/{id}/export)
    # --------------------------------------------------------------------------
    print(f">>> 12. EXPORT PROJECT AS CSV (GET /api/projects/{project_id}/export)")
    resp = client.get(f"/api/projects/{project_id}/export", headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}, Content-Type: {resp.headers.get('content-type')}")
    print(f"CSV Snippet:\n{resp.text[:200]}...\n")

    # --------------------------------------------------------------------------
    # 13. DELETE PROJECT -> RECYCLE BIN (DELETE /api/projects/{id})
    # --------------------------------------------------------------------------
    print(f">>> 13. SOFT-DELETE PROJECT TO RECYCLE BIN (DELETE /api/projects/{project_id})")
    resp = client.delete(f"/api/projects/{project_id}", headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    print(f">>> 13b. VERIFY 404 ON DELETED PROJECT (GET /api/projects/{project_id})")
    resp = client.get(f"/api/projects/{project_id}", headers=admin_hdr)
    assert resp.status_code == 404, f"Expected 404, got {resp.status_code}"
    print(f"Status Code: {resp.status_code} (Verified Not Found / In Bin)\n")

    # --------------------------------------------------------------------------
    # 14. RECYCLE BIN INSPECTION & RESTORATION
    # --------------------------------------------------------------------------
    print(">>> 14a. INSPECT RECYCLE BIN (GET /api/admin/bin)")
    resp = client.get("/api/admin/bin", headers=admin_hdr)
    assert resp.status_code == 200
    bin_data = resp.json()
    bin_items = bin_data.get("items", [])
    project_bin_item = next((b for b in bin_items if b["entity_type"] == "project" and b["entity_id"] == project_id), None)
    assert project_bin_item is not None, "Project not found in recycle bin"
    bin_id = project_bin_item["id"]
    print(f"Found Project in Bin: ID={bin_id}, Title='{project_bin_item['title']}'\n")

    print(f">>> 14b. RESTORE PROJECT FROM BIN (POST /api/admin/bin/{bin_id}/restore)")
    resp = client.post(f"/api/admin/bin/{bin_id}/restore", headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Response:\n{pretty(resp.json())}\n")

    print(f">>> 14c. VERIFY RESTORED PROJECT ACCESS (GET /api/projects/{project_id})")
    resp = client.get(f"/api/projects/{project_id}", headers=admin_hdr)
    assert resp.status_code == 200
    print(f"Status Code: {resp.status_code}")
    print(f"Project Restored Successfully: Name='{resp.json().get('name')}', Status='{resp.json().get('status')}'\n")

    print("=" * 80)
    print("       ALL PROJECT & TASK CRUD TESTS PASSED SUCCESSFULLY!")
    print("=" * 80)


if __name__ == "__main__":
    run_project_crud_tests()
