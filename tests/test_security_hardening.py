"""Task 3 tests: security hardening.

- Blog HTML is sanitized on write (script/iframe/event handlers/javascript:
  URLs stripped; p/h2/ul/a/img kept)
- cover_image_url must be an absolute http(s) URL
- CSP header emitted per spec (object-src 'none', frame-ancestors 'self')
- login does NOT return a Bearer token by default; when AUTH_RETURN_BEARER_TOKEN
  is enabled the body token is short-lived (remember ignored for tokens)
- session cookie is HttpOnly
"""
import json
import os
import unittest

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request
from starlette.responses import Response

# main.py imports must not fail without a bootstrap password env var.
os.environ.setdefault("BOOTSTRAP_ADMIN_PASSWORD", "test-bootstrap-pw")

from app.core.sanitize import sanitize_html, validate_http_url  # noqa: E402
from config import Config  # noqa: E402
from database import Base  # noqa: E402
from dependencies import verify_token, SESSION_COOKIE_NAME  # noqa: E402
from models import User, UserRole, Organization, OrganizationMembership  # noqa: E402
from routes.api.auth import login  # noqa: E402
from routes.api.blogs import create_blog  # noqa: E402


def make_request(
    user: User | None,
    method: str = "GET",
    payload: dict | None = None,
    org_id: int | None = None,
) -> Request:
    body = json.dumps(payload or {}).encode() if payload is not None else b""
    sent = False

    async def receive():
        nonlocal sent
        if sent:
            return {"type": "http.disconnect"}
        sent = True
        return {"type": "http.request", "body": body, "more_body": False}

    headers = [(b"content-type", b"application/json")]
    if user is not None:
        from dependencies import generate_token

        headers.append(
            (b"authorization", f"Bearer {generate_token(user.id, user.session_version)}".encode())
        )
    if org_id:
        headers.append((b"x-organization-id", str(org_id).encode()))

    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": "/",
        "raw_path": b"/",
        "query_string": b"",
        "headers": headers,
        "client": ("testclient", 12345),
    }
    return Request(scope, receive)


class TestBlogSanitization(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()
        self.org = Organization(name="SecOrg", slug="secorg")
        self.db.add(self.org)
        self.db.commit()
        self.admin = User(
            name="Admin S",
            email="admin@secorg.com",
            password_hash="x",
            role=UserRole.ADMIN,
            is_active=True,
            session_version=1,
        )
        self.db.add(self.admin)
        self.db.commit()
        self.db.refresh(self.admin)
        self.db.add(
            OrganizationMembership(
                organization_id=self.org.id, user_id=self.admin.id, role=UserRole.ADMIN, is_active=True
            )
        )
        self.db.commit()

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def _create(self, payload: dict) -> dict:
        req = make_request(self.admin, "POST", payload, org_id=self.org.id)
        return await create_blog(req, self.db)

    async def test_xss_payloads_stripped_safe_tags_kept(self):
        res = await self._create(
            {
                "title": "Sanitize Test",
                "content": (
                    "<script>alert(1)</script>"
                    "<p>Safe paragraph</p>"
                    "<h2>Heading</h2>"
                    "<ul><li>item</li></ul>"
                    "<iframe src='https://evil.example'></iframe>"
                    "<img src='https://cdn.example/a.png' onerror='alert(1)'>"
                    "<a href='javascript:alert(1)'>click</a>"
                    "<a href='https://ok.example' target='_blank'>ok link</a>"
                    "<object data='evil'></object>"
                ),
            }
        )
        content = res["content"]
        self.assertNotIn("<script", content)
        self.assertNotIn("alert(1)", content)
        self.assertNotIn("iframe", content)
        self.assertNotIn("object", content)
        self.assertNotIn("onerror", content)
        self.assertNotIn("javascript:", content)
        self.assertIn("<p>Safe paragraph</p>", content)
        self.assertIn("<h2>Heading</h2>", content)
        self.assertIn("<ul><li>item</li></ul>", content)
        self.assertIn("<img", content)
        self.assertIn("<a", content)

    async def test_excerpt_sanitized(self):
        res = await self._create(
            {
                "title": "Excerpt Test",
                "content": "<p>body</p>",
                "excerpt": "<b>Bold teaser</b><script>evil()</script>",
            }
        )
        self.assertIn("<b>Bold teaser</b>", res["excerpt"])
        self.assertNotIn("<script", res["excerpt"])

    async def test_cover_image_url_rejects_non_http_schemes(self):
        with self.assertRaises(Exception):
            await self._create(
                {
                    "title": "Cover Test",
                    "content": "<p>body</p>",
                    "cover_image_url": "javascript:alert(1)",
                }
            )
        res = await self._create(
            {
                "title": "Cover Test 2",
                "content": "<p>body</p>",
                "cover_image_url": "https://cdn.example/cover.png",
            }
        )
        self.assertEqual(res["cover_image_url"], "https://cdn.example/cover.png")

    def test_sanitize_unit(self):
        self.assertEqual(sanitize_html("<p>hi</p>"), "<p>hi</p>")
        self.assertEqual(sanitize_html(None), "")
        cleaned = sanitize_html("<p onclick='x()'>t</p>")
        self.assertNotIn("onclick", cleaned)

    def test_validate_http_url(self):
        self.assertIsNone(validate_http_url("javascript:alert(1)"))
        self.assertIsNone(validate_http_url("data:text/html,evil"))
        self.assertIsNone(validate_http_url("//host/path"))
        self.assertEqual(validate_http_url("https://a.com/b"), "https://a.com/b")
        self.assertEqual(validate_http_url("http://a.com/b"), "http://a.com/b")


class TestSecurityHeaders(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import main

        cls.app = app = main.app
        cls.client = TestClient(app)

    def test_csp_header_spec(self):
        resp = self.client.get("/api/health")
        csp = resp.headers["content-security-policy"]
        self.assertIn("default-src 'self'", csp)
        self.assertIn("object-src 'none'", csp)
        self.assertIn("frame-ancestors 'self'", csp)
        self.assertIn("img-src 'self' data: blob: https:", csp)
        self.assertIn("connect-src 'self'", csp)
        self.assertIn("script-src 'self'", csp)

    def test_other_security_headers(self):
        resp = self.client.get("/api/health")
        self.assertEqual(resp.headers["x-content-type-options"], "nosniff")
        self.assertEqual(resp.headers["x-frame-options"], "DENY")
        self.assertIn("Strict-Transport-Security", resp.headers)


class TestBearerGating(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()
        self.user = User(
            name="Login User",
            email="login@secorg.com",
            password_hash="x",
            role=UserRole.INTERN,
            is_active=True,
            session_version=1,
        )
        self.user.set_password("Password123!")
        self.db.add(self.user)
        self.db.commit()
        self.db.refresh(self.user)
        self._orig_flag = Config.AUTH_RETURN_BEARER_TOKEN

    def tearDown(self):
        Config.AUTH_RETURN_BEARER_TOKEN = self._orig_flag
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    async def _login(self, remember: bool = True) -> tuple[dict, Response]:
        req = make_request(None, "POST", {"email": self.user.email, "password": "Password123!", "remember": remember})
        response = Response()
        result = await login(req, response, self.db, None)
        return result, response

    async def test_login_returns_no_token_by_default(self):
        Config.AUTH_RETURN_BEARER_TOKEN = False
        result, response = await self._login()
        self.assertNotIn("token", result)
        self.assertIn("user", result)
        all_cookies = "; ".join(response.headers.getlist("set-cookie"))
        self.assertIn(SESSION_COOKIE_NAME, all_cookies)
        self.assertIn("HttpOnly", all_cookies)
        self.assertIn("ih_csrf", all_cookies)

    async def test_body_token_is_short_lived_when_enabled(self):
        Config.AUTH_RETURN_BEARER_TOKEN = True
        result, response = await self._login(remember=True)
        self.assertIn("token", result)
        # The body token must NOT carry the remember flag → 8h TTL, not 30 days.
        data = verify_token(result["token"])
        self.assertIsNotNone(data)
        self.assertFalse(data["remember"])
        # Session cookie still honors remember (long Max-Age)
        self.assertIn(SESSION_COOKIE_NAME, response.headers.get("set-cookie", ""))


if __name__ == "__main__":
    unittest.main()
