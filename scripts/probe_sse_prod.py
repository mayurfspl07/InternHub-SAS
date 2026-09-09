"""Probe SSE body flow: with/without Accept-Encoding, print bytes as they arrive."""
import requests

BASE = "https://internhub-sas-production-b44c.up.railway.app"
s = requests.Session()
r = s.post(f"{BASE}/api/auth/login", json={"email": "admin@internhub.dev", "password": "AdminSecurePass123!"}, timeout=30)
print("login:", r.status_code, flush=True)

for label, headers in [
    ("identity (no gzip)", {"Accept-Encoding": "identity"}),
    ("default (gzip)", {}),
]:
    print(f"--- {label}", flush=True)
    try:
        r = s.get(
            f"{BASE}/api/notifications/stream",
            headers=headers,
            timeout=(10, 20),
            stream=True,
        )
        print("  status:", r.status_code, "content-type:", r.headers.get("content-type"),
              "content-encoding:", r.headers.get("content-encoding"), flush=True)
        got = []
        try:
            for chunk in r.iter_content(chunk_size=1, decode_unicode=True):
                if chunk:
                    got.append(chunk)
                    print("  byte:", repr(chunk), flush=True)
                text = "".join(got)
                if "unread_count" in text:
                    print("  GOT EVENT, total bytes:", len(got), flush=True)
                    break
        except Exception as exc:
            print("  read stopped:", type(exc).__name__, flush=True)
        r.close()
    except requests.RequestException as exc:
        print("  request error:", exc, flush=True)
