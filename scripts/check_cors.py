import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from config import Config

origins = Config.cors_origins()
print("allowlist:", origins)

from fastapi.testclient import TestClient
from main import app

c = TestClient(app)
for origin in ("https://app.nowinternhub.com", "https://nowinternhub.com"):
    r = c.options(
        "/api/auth/login",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    print(origin, "->", r.status_code, "| allow-origin:", r.headers.get("access-control-allow-origin"))
