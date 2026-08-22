import requests, sys

def assert_resp(label, resp, expected=200):
    ok = resp.status_code == expected
    mark = "[OK]" if ok else "[FAIL]"
    print(f"{mark} {label} -> {resp.status_code}")
    if not ok:
        print("     ", resp.text[:300])
    return ok

def run(base, admin_email="admin@internhub.dev", admin_password="Imp@pune1"):
    s = requests.Session()
    s.headers["Content-Type"] = "application/json"

    print(f"\n{'='*60}")
    print(f"TARGET: {base}")
    print(f"{'='*60}")

    # 1. Health
    r = s.get(f"{base}/api/health", timeout=15)
    if not assert_resp("GET /api/health", r):
        print("Server not reachable — aborting.")
        return False

    # 2. Login
    r = s.post(f"{base}/api/auth/login",
               json={"email": admin_email, "password": admin_password}, timeout=15)
    if not assert_resp("POST /api/auth/login", r):
        return False
    data = r.json()
    token = data.get("token") or data.get("access_token")
    if token:
        s.headers["Authorization"] = f"Bearer {token}"
    print(f"      auth via {'Bearer token' if token else 'session cookie'}")

    # 3. Unauthenticated 403
    r = requests.get(f"{base}/api/admin/students", timeout=10)
    assert_resp("GET /api/admin/students (no auth) -> 403", r, expected=403)

    # 4. Students list
    r = s.get(f"{base}/api/admin/students", timeout=15)
    if not assert_resp("GET /api/admin/students", r):
        return False
    d = r.json()
    total = d.get("total", 0)
    print(f"      total={total}, pages={d.get('total_pages')}, page_size={d.get('page_size')}")
    first_id = d["students"][0]["id"] if d.get("students") else None
    if first_id:
        st = d["students"][0]
        ov = st.get("attendance_overview", {})
        print(f"      first student: {st['name']} | dept={st.get('department')} | active_projects={st.get('active_projects')}")
        print(f"      attendance_overview: present={ov.get('present')} late={ov.get('late')} absent={ov.get('absent')} rate={ov.get('attendance_rate')}%")

    # 5. Search filter
    r = s.get(f"{base}/api/admin/students?search=a&sort=joining_date&window_days=7", timeout=15)
    if assert_resp("GET /api/admin/students?search=a&sort=joining_date", r):
        print(f"      filtered total={r.json().get('total')}")

    # 6. is_active filter
    r = s.get(f"{base}/api/admin/students?is_active=true&page_size=5", timeout=15)
    if assert_resp("GET /api/admin/students?is_active=true", r):
        print(f"      active students={r.json().get('total')}")

    # 7. Student attendance detail
    if first_id:
        r = s.get(f"{base}/api/admin/students/{first_id}/attendance", timeout=15)
        if assert_resp(f"GET /api/admin/students/{first_id}/attendance", r):
            d = r.json()
            totals = d.get("totals", {})
            print(f"      student={d['student']['name']}, records={d.get('total')}, total_days={totals.get('total_days')}, rate={totals.get('attendance_rate')}%")
            print(f"      present={totals.get('present')} late={totals.get('late')} half_day={totals.get('half_day')} absent={totals.get('absent')}")

        # 8. Month filter
        r = s.get(f"{base}/api/admin/students/{first_id}/attendance?month=2026-08", timeout=15)
        if assert_resp(f"GET /{first_id}/attendance?month=2026-08", r):
            d = r.json()
            print(f"      Aug records={d.get('total')}, monthly_summary={d.get('monthly_summary')}")

        # 9. Status filter
        r = s.get(f"{base}/api/admin/students/{first_id}/attendance?status=present", timeout=15)
        if assert_resp(f"GET /{first_id}/attendance?status=present", r):
            print(f"      present-only records={r.json().get('total')}")

        # 10. Date range filter
        r = s.get(f"{base}/api/admin/students/{first_id}/attendance?start=2026-08-01&end=2026-08-21", timeout=15)
        if assert_resp(f"GET /{first_id}/attendance?start=2026-08-01&end=2026-08-21", r):
            print(f"      range records={r.json().get('total')}")

        # 11. Invalid status -> 422
        r = s.get(f"{base}/api/admin/students/{first_id}/attendance?status=wrong", timeout=15)
        assert_resp(f"GET /{first_id}/attendance?status=wrong -> 422", r, expected=422)

        # 12. Invalid date -> 422
        r = s.get(f"{base}/api/admin/students/{first_id}/attendance?start=not-a-date", timeout=15)
        assert_resp(f"GET /{first_id}/attendance?start=not-a-date -> 422", r, expected=422)

        # 13. Non-existent user -> 404
        r = s.get(f"{base}/api/admin/students/999999/attendance", timeout=15)
        assert_resp("GET /api/admin/students/999999/attendance -> 404", r, expected=404)

    # 14. Existing: attendance history as admin sees all
    r = s.get(f"{base}/api/attendance/history?month=2026-08", timeout=15)
    if assert_resp("GET /api/attendance/history (admin, no user_id)", r):
        d = r.json()
        print(f"      total all-intern records={d.get('total')}")

    # 15. Projects List
    r = s.get(f"{base}/api/projects?page=1&page_size=12", timeout=15)
    if assert_resp("GET /api/projects", r):
        d = r.json()
        print(f"      total projects={d.get('total')}, page_size={d.get('page_size')}, returned={len(d.get('projects', []))}")
        for p in d.get("projects", [])[:3]:
            print(f"        -> Project #{p['id']}: {p['name']} (status={p['status']}, mentor={p.get('mentor_name')})")

    # 16. Projects Search
    r = s.get(f"{base}/api/projects/search?q=", timeout=15)
    if assert_resp("GET /api/projects/search", r):
        d = r.json()
        print(f"      search total={d.get('total')}")

    print("\nDone.")
    return True

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3001"
    email = sys.argv[2] if len(sys.argv) > 2 else "admin@internhub.dev"
    password = sys.argv[3] if len(sys.argv) > 3 else "Imp@pune1"
    run(target, admin_email=email, admin_password=password)
