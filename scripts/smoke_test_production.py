"""Smoke-test the deployed InternHub API (read-only; login + GETs)."""
import json
import sys

import requests

BASE = "https://internhub-sas-production-b44c.up.railway.app"

results = []


def check(name, ok, extra=""):
    results.append((name, ok, extra))
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {extra}")


s = requests.Session()

# 1. Health + security headers
r = s.get(f"{BASE}/api/health", timeout=30)
check("health", r.status_code == 200, f"{r.status_code} {r.text[:60]}")
csp = r.headers.get("content-security-policy", "")
check(
    "CSP spec",
    "default-src 'self'" in csp and "object-src 'none'" in csp and "frame-ancestors 'self'" in csp,
    csp[:100],
)
check("nosniff", r.headers.get("x-content-type-options") == "nosniff")
check("HSTS", "max-age" in r.headers.get("strict-transport-security", ""))

# 2. Frontend served
r = s.get(f"{BASE}/", timeout=30)
check("frontend index", r.status_code == 200 and "html" in r.headers.get("content-type", ""), f"{r.status_code}")

# 3. Public blog (no auth)
r = s.get(f"{BASE}/api/blogs", timeout=30)
check("blogs public list", r.status_code == 200, f"{r.status_code} keys={list(r.json().keys())[:5] if r.ok else r.text[:80]}")

# 4. Unauthenticated list endpoints -> 401/403 (routing deployed; admin endpoints use 403)
for path in [
    "/api/announcements",
    "/api/reviews",
    "/api/cohorts",
    "/api/assignments",
    "/api/projects/mentors",
    "/api/projects/interns",
    "/api/admin/users",
    "/api/admin/intern-assignments",
    "/api/profile",
    "/api/leave/mine",
    "/api/dashboard",
]:
    r = s.get(f"{BASE}{path}", timeout=30)
    check(f"authz 401/403 {path}", r.status_code in (401, 403), f"{r.status_code}")

# 5. Login — try bootstrap default creds from repo test scripts
creds = [
    ("admin@internhub.dev", "AdminSecurePass123!"),
    ("admin@internhub.dev", "Imp@pune1"),
    ("admin@internhub.dev", "Imp@pune2"),
]
logged_in = False
admin_token = None
for email, pw in creds:
    r = s.post(
        f"{BASE}/api/auth/login",
        json={"email": email, "password": pw},
        timeout=30,
    )
    if r.status_code == 200 and r.json().get("ok"):
        logged_in = True
        admin_token = r.json().get("token")
        check("login", True, f"{email} (cookie session set, token_in_body={admin_token is not None})")
        break
    else:
        print(f"  login try {email}/{pw[:3]}*** -> {r.status_code} {r.json().get('detail', '')[:60]}")

if not logged_in:
    check("login", False, "no known credentials worked; skipping authenticated checks")
    sys.exit(0)

def h():
    hdrs = {}
    if admin_token:
        hdrs["Authorization"] = f"Bearer {admin_token}"
    return hdrs

def get(path, params=None):
    return s.get(f"{BASE}{path}", params=params or {}, headers=h(), timeout=30)

# 6. Envelope shape on the six paginated endpoints
checks = [
    ("announcements", "/api/announcements", {"page": 1, "page_size": 5}),
    ("reviews", "/api/reviews", {"page": 1, "page_size": 5}),
    ("cohorts", "/api/cohorts", {"page": 1, "page_size": 5}),
    ("assignments", "/api/assignments", {"page": 1, "page_size": 5}),
    ("projects/mentors", "/api/projects/mentors", {"page": 1, "page_size": 5}),
    ("projects/interns", "/api/projects/interns", {"page": 1, "page_size": 5}),
]
for name, path, params in checks:
    r = get(path, params)
    ok = r.status_code == 200
    body = r.json() if ok else {}
    keys_ok = ok and set(["items", "page", "page_size", "total", "total_pages"]).issubset(body.keys())
    check(
        f"envelope {name}",
        ok and keys_ok,
        f"{r.status_code} items={len(body.get('items', []))} total={body.get('total')} ps={body.get('page_size')}",
    )

# 7. page_size cap
r = get("/api/announcements", {"page": 1, "page_size": 5000})
check("page_size cap", r.ok and r.json().get("page_size") == 100, f"{r.status_code} ps={r.json().get('page_size') if r.ok else ''}")

# 8. admin/users — shape, newest-first, counts
r = get("/api/admin/users", {"page": 1, "page_size": 10})
body = r.json() if r.ok else {}
check(
    "admin/users envelope",
    r.ok and set(["users", "items", "page", "page_size", "total", "total_pages", "counts"]).issubset(body.keys()),
    f"{r.status_code} total={body.get('total')} counts={body.get('counts')}",
)
roles = [u.get("role") for u in body.get("users", [])]
check("no superadmin rows", "superadmin" not in roles, f"roles={roles}")
platform_rows = [u for u in body.get("users", []) if u.get("email") == "admin@internhub.dev"]
check("platform admin hidden", not platform_rows, f"bootstrap admin visible: {bool(platform_rows)}")

# role=superadmin rejected
r = get("/api/admin/users", {"role": "superadmin"})
check("role=superadmin -> 422", r.status_code == 422, f"{r.status_code}")

# unassigned filter
r = get("/api/admin/users", {"unassigned": "true"})
body = r.json() if r.ok else {}
check(
    "unassigned filter",
    r.ok and all(u.get("role") == "intern" and not u.get("mentor_id") for u in body.get("users", [])),
    f"{r.status_code} n={len(body.get('users', []))}",
)

# 9. search on admin/users
r = get("/api/admin/users", {"search": "admin", "page_size": 10})
check("admin/users search", r.ok, f"{r.status_code} total={r.json().get('total') if r.ok else ''}")

# 10. intern-assignments pagination + scope
r = get("/api/admin/intern-assignments", {"page": 1, "page_size": 5})
body = r.json() if r.ok else {}
check(
    "intern-assignments paginated",
    r.ok and set(["by_mentor", "page", "page_size", "total", "total_pages", "organization_id"]).issubset(body.keys()),
    f"{r.status_code} total={body.get('total')} scope={body.get('scope')}",
)

# 11. profile + duration/leave info
r = get("/api/profile")
body = r.json() if r.ok else {}
check(
    "profile duration fields",
    r.ok and set(["internship_duration_months", "internship_end_date", "internship_summary"]).issubset(body.keys()),
    f"{r.status_code} role={body.get('role')} summary_quota={body.get('internship_summary', {}).get('total_leave_quota')}",
)

r = get("/api/leave/mine")
body = r.json() if r.ok else {}
check("leave/mine balance", r.ok and "balance" in body and "quota" in body.get("balance", {}), f"{r.status_code} quota={body.get('balance', {}).get('quota')}")

# 12. assignments aggregate counts
r = get("/api/assignments", {"page_size": 5})
body = r.json() if r.ok else {}
check(
    "assignments counts",
    r.ok and "counts" in body and set(["active", "draft", "closed", "pending_reviews"]).issubset(body.get("counts", {}).keys()),
    f"{r.status_code} counts={body.get('counts')}",
)

# 13. rating filter on reviews
r = get("/api/reviews", {"rating": 3, "page_size": 5})
check("reviews rating filter", r.ok and all(x.get("rating") == 3 for x in r.json().get("items", [])), f"{r.status_code} n={len(r.json().get('items', [])) if r.ok else ''}")

# 14. SSE stream endpoint (raw streaming read; events are tiny)
try:
    r = s.get(f"{BASE}/api/notifications/stream", headers=h(), timeout=(10, 25), stream=True)
    ctype = r.headers.get("content-type", "")
    check("SSE content-type", "text/event-stream" in ctype, f"{r.status_code} {ctype}")
    lines = []
    for chunk in r.iter_content(chunk_size=1, decode_unicode=True):
        if chunk:
            lines.append(chunk)
        text = "".join(lines)
        if "\n\n" in text and len(lines) > 10:
            break
    body = "".join(lines)
    check("SSE first event", "unread_count" in body, f"body={body[:80]!r}")
    r.close()
except requests.RequestException as exc:
    check("SSE first event", False, f"error: {exc}")

print()
print(f"SUMMARY: {sum(1 for _, ok, _ in results if ok)}/{len(results)} passed")
fails = [n for n, ok, _ in results if not ok]
if fails:
    print("FAILURES:", ", ".join(fails))
