"""Publish SEO blog posts to a running InternHub backend via its HTTP API (idempotent by slug)."""
import os
import sys

import httpx

import config  # noqa: F401 — loads .env before we read env vars
from seed_blogs import BLOG_POSTS

BASE_URL = (os.environ.get("TARGET_BASE_URL") or "https://internhub-sas-production.up.railway.app").rstrip("/")


def main() -> None:
    email = os.environ.get("BOOTSTRAP_ADMIN_EMAIL", "admin@internhub.dev").strip().lower()
    password = os.environ.get("BOOTSTRAP_ADMIN_PASSWORD")
    if not password:
        sys.exit("BOOTSTRAP_ADMIN_PASSWORD not set — cannot authenticate.")

    client = httpx.Client(base_url=BASE_URL, timeout=30)

    res = client.post("/api/auth/login", json={"email": email, "password": password})
    if res.status_code != 200:
        sys.exit(f"Login failed ({res.status_code}). Check BOOTSTRAP_ADMIN_EMAIL/PASSWORD for this deployment.")
    token = res.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    print(f"[OK] Authenticated as {email}")

    res = client.get("/api/blogs", params={"per_page": 50})
    res.raise_for_status()
    existing = {item["slug"] for item in res.json()["items"]}
    print(f"[OK] Backend has {len(existing)} published post(s) already.")

    created, skipped = [], []
    for spec in BLOG_POSTS:
        if spec["slug"] in existing:
            skipped.append(spec["slug"])
            continue
        payload = {
            "title": spec["title"],
            "slug": spec["slug"],
            "excerpt": spec["excerpt"],
            "content": spec["content"].strip(),
            "cover_image_url": spec["cover_image_url"],
            "tags": spec["tags"],
            "status": "published",
        }
        res = client.post("/api/blogs", json=payload, headers=headers)
        if res.status_code == 200:
            created.append(spec["slug"])
            print(f"     + published {spec['slug']}")
        else:
            print(f"     ! FAILED {spec['slug']}: {res.status_code} {res.text[:200]}")

    print(f"\n[DONE] Created {len(created)}, skipped {len(skipped)} (already exist).")
    for slug in skipped:
        print(f"       = {slug}")

    # Final verification against the public list endpoint.
    res = client.get("/api/blogs", params={"per_page": 50})
    total = res.json()["total"]
    print(f"[VERIFY] Public blog list now reports {total} published post(s):")
    for item in res.json()["items"]:
        print(f"         - {item['slug']}  ({item['published_at'][:10]})")


if __name__ == "__main__":
    main()
