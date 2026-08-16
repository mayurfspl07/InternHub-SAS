"""Live API Test Script to test and confirm all API groups against the running server."""
import json
import urllib.request
import urllib.error
import uuid
import sys

BASE_URL = "http://127.0.0.1:3001"


def make_req(path, method="GET", data=None, headers=None):
    if headers is None:
        headers = {}
    url = f"{BASE_URL}{path}"
    req_data = None
    if data is not None:
        req_data = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            try:
                return resp.status, json.loads(body)
            except Exception:
                return resp.status, body
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, body


def run_tests():
    print("================================================================")
    print("             INTERNHUB LIVE API TEST SUITE                      ")
    print("================================================================")

    # 1. Health & Docs
    status, res = make_req("/api/health")
    assert status == 200, f"/api/health failed: {status}"
    print(f"[PASS] 1. GET /api/health (status {status}) -> {res.get('status')}")

    status, res = make_req("/docs")
    assert status == 200, f"/docs failed: {status}"
    print(f"[PASS] 2. GET /docs [Scalar UI] (status {status}) -> {len(res)} bytes")

    status, openapi_doc = make_req("/openapi.json")
    assert status == 200, f"/openapi.json failed: {status}"
    total_paths = len(openapi_doc.get("paths", {}))
    print(f"[PASS] 3. GET /openapi.json (status {status}) -> {total_paths} documented paths")

    # 2. Authentication & Login
    status, login_res = make_req(
        "/api/auth/login",
        method="POST",
        data={"email": "admin@internhub.dev", "password": "AdminPass123!"},
    )
    assert status == 200, f"POST /api/auth/login failed: {status} {login_res}"
    token = login_res.get("token")
    assert token, "No token in login response"
    print(f"[PASS] 4. POST /api/auth/login (status {status}) -> token received")

    auth_headers = {"Authorization": f"Bearer {token}"}

    # 3. Auth Me
    status, me_res = make_req("/api/auth/me", headers=auth_headers)
    assert status == 200, f"GET /api/auth/me failed: {status}"
    print(f"[PASS] 5. GET /api/auth/me (status {status}) -> user='{me_res.get('name')}', role='{me_res.get('role')}'")

    # 4. Admin Assignments & Users
    status, admin_ov = make_req("/api/admin/intern-assignments", headers=auth_headers)
    assert status == 200, f"GET /api/admin/intern-assignments failed: {status}"
    print(f"[PASS] 6. GET /api/admin/intern-assignments (status {status}) -> total_interns={admin_ov.get('total_interns')}")

    status, mentors_res = make_req("/api/admin/mentors", headers=auth_headers)
    assert status == 200, f"GET /api/admin/mentors failed: {status}"
    print(f"[PASS] 7. GET /api/admin/mentors (status {status}) -> mentors count={len(mentors_res)}")

    status, users_res = make_req("/api/admin/users", headers=auth_headers)
    assert status == 200, f"GET /api/admin/users failed: {status}"
    user_count = len(users_res.get("users", []))
    print(f"[PASS] 8. GET /api/admin/users (status {status}) -> returned {user_count} users")

    # 5. Create New Mentor & Intern
    unique_mentor_email = f"live_mentor_{uuid.uuid4().hex[:6]}@test.com"
    status, create_mentor_res = make_req(
        "/api/admin/users",
        method="POST",
        headers=auth_headers,
        data={
            "name": "Live Verification Mentor",
            "email": unique_mentor_email,
            "role": "mentor",
            "department": "Engineering",
            "job_title": "Lead Mentor",
            "password": "MentorPassword123!",
        },
    )
    assert status == 200, f"POST /api/admin/users (mentor) failed: {status} {create_mentor_res}"
    mentor_id = create_mentor_res.get("id")
    print(f"[PASS] 8a. POST /api/admin/users (mentor) (status {status}) -> created mentor id={mentor_id}")

    unique_email = f"live_intern_{uuid.uuid4().hex[:6]}@test.com"
    status, create_user_res = make_req(
        "/api/admin/users",
        method="POST",
        headers=auth_headers,
        data={
            "name": "Live Verification Intern",
            "email": unique_email,
            "role": "intern",
            "department": "Engineering",
            "job_title": "Software Intern",
            "mentor_id": mentor_id,
            "password": "InternPassword123!",
        },
    )
    assert status == 200, f"POST /api/admin/users (intern) failed: {status} {create_user_res}"
    new_user_id = create_user_res.get("id")
    print(f"[PASS] 8b. POST /api/admin/users (intern) (status {status}) -> created intern id={new_user_id} ({unique_email})")

    # 6. Projects & Tasks
    status, proj_list = make_req("/api/projects", headers=auth_headers)
    assert status == 200, f"GET /api/projects failed: {status}"
    print(f"[PASS] 9. GET /api/projects (status {status}) -> {len(proj_list.get('projects', []))} project(s)")

    proj_name = f"Live Validation Project {uuid.uuid4().hex[:4]}"
    status, proj_create = make_req(
        "/api/projects",
        method="POST",
        headers=auth_headers,
        data={
            "name": proj_name,
            "description": "Automated test project for confirming live API responsiveness",
            "status": "in_progress",
            "mentor_id": mentor_id,
            "mentor_ids": [mentor_id],
        },
    )
    assert status == 200, f"POST /api/projects failed: {status} {proj_create}"
    proj_id = proj_create.get("id")
    print(f"[PASS] 10. POST /api/projects (status {status}) -> created project id={proj_id} ('{proj_name}')")

    status, task_create = make_req(
        f"/api/projects/{proj_id}/tasks",
        method="POST",
        headers=auth_headers,
        data={
            "title": "Build Integration Pipeline",
            "description": "Ensure end-to-end integration and verification pass",
            "priority": "high",
            "status": "todo",
            "assigned_to": new_user_id,
        },
    )
    assert status == 200, f"POST /api/projects/{proj_id}/tasks failed: {status} {task_create}"
    task_id = task_create.get("id")
    print(f"[PASS] 11. POST /api/projects/{proj_id}/tasks (status {status}) -> created task id={task_id}")

    status, task_patch = make_req(
        f"/api/projects/tasks/{task_id}/status",
        method="PATCH",
        headers=auth_headers,
        data={"status": "in_progress"},
    )
    assert status == 200, f"PATCH /api/projects/tasks/{task_id}/status failed: {status}"
    print(f"[PASS] 12. PATCH /api/projects/tasks/{task_id}/status (status {status}) -> status='{task_patch.get('status')}'")

    status, task_comment = make_req(
        f"/api/projects/tasks/{task_id}/comments",
        method="POST",
        headers=auth_headers,
        data={"body": "Automated verification comment."},
    )
    assert status == 200, f"POST /api/projects/tasks/{task_id}/comments failed: {status}"
    print(f"[PASS] 13. POST /api/projects/tasks/{task_id}/comments (status {status}) -> comment id={task_comment.get('id')}")

    # 7. Attendance & Calendar
    status, att_today = make_req("/api/attendance/today", headers=auth_headers)
    assert status == 200, f"GET /api/attendance/today failed: {status}"
    print(f"[PASS] 14. GET /api/attendance/today (status {status}) -> date='{att_today.get('date')}'")

    status, att_report = make_req("/api/attendance/report", headers=auth_headers)
    assert status == 200, f"GET /api/attendance/report failed: {status}"
    print(f"[PASS] 15. GET /api/attendance/report (status {status}) -> report total={att_report.get('total')}")

    # 8. Leave Management (Admin list)
    status, leave_manage = make_req("/api/leave/manage", headers=auth_headers)
    assert status == 200, f"GET /api/leave/manage failed: {status}"
    print(f"[PASS] 16. GET /api/leave/manage (status {status}) -> total requests={leave_manage.get('total')}")

    # 9. Cohorts
    cohort_name = f"Cohort {uuid.uuid4().hex[:4]}"
    status, cohort_create = make_req(
        "/api/cohorts",
        method="POST",
        headers=auth_headers,
        data={"name": cohort_name, "description": "Automated test cohort"},
    )
    assert status == 200, f"POST /api/cohorts failed: {status}"
    print(f"[PASS] 17. POST /api/cohorts (status {status}) -> cohort id={cohort_create.get('id')}")

    # 10. Announcements
    status, ann_create = make_req(
        "/api/announcements",
        method="POST",
        headers=auth_headers,
        data={
            "title": "System API Verification Notice",
            "body": "All API endpoints are active and verified.",
            "is_pinned": True,
        },
    )
    assert status == 200, f"POST /api/announcements failed: {status}"
    print(f"[PASS] 18. POST /api/announcements (status {status}) -> ann id={ann_create.get('id')}")

    # 11. Standups
    status, standup_list = make_req("/api/standup", headers=auth_headers)
    assert status == 200, f"GET /api/standup failed: {status}"
    print(f"[PASS] 19. GET /api/standup (status {status}) -> total logs={standup_list.get('total')}")

    # 12. Dashboard, Notifications & Audit Logs
    status, dash = make_req("/api/dashboard", headers=auth_headers)
    assert status == 200, f"GET /api/dashboard failed: {status}"
    print(f"[PASS] 20. GET /api/dashboard (status {status}) -> stats present={bool(dash.get('stats'))}")

    status, notifs = make_req("/api/notifications", headers=auth_headers)
    assert status == 200, f"GET /api/notifications failed: {status}"
    print(f"[PASS] 21. GET /api/notifications (status {status}) -> unread_count={notifs.get('unread_count')}")

    status, audit_logs = make_req("/api/audit", headers=auth_headers)
    assert status == 200, f"GET /api/audit failed: {status}"
    print(f"[PASS] 22. GET /api/audit (status {status}) -> total={audit_logs.get('total')}")

    # 13. Search
    status, search_res = make_req("/api/search?q=test", headers=auth_headers)
    assert status == 200, f"GET /api/search failed: {status}"
    print(f"[PASS] 23. GET /api/search (status {status}) -> results returned")

    # 14. Profile
    status, profile_res = make_req("/api/profile", headers=auth_headers)
    assert status == 200, f"GET /api/profile failed: {status}"
    print(f"[PASS] 24. GET /api/profile (status {status}) -> name='{profile_res.get('name')}'")

    print("\n================================================================")
    print("      ALL 24 LIVE API CHECKS PASSED WITH 100% SUCCESS           ")
    print("================================================================")


if __name__ == "__main__":
    run_tests()
