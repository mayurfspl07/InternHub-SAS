"""Authentication, CSRF, and session helpers."""
import secrets
import time
from typing import Annotated

from fastapi import Depends, HTTPException, Request, Response
from sqlalchemy.orm import Session
from itsdangerous import URLSafeTimedSerializer

from config import Config
from database import get_db
from models import User
from templating import flash

DbSession = Annotated[Session, Depends(get_db)]

_serializer = URLSafeTimedSerializer(Config.SECRET_KEY, salt="auth-salt")

# HttpOnly cookie carrying the auth token, plus a JS-readable sibling cookie used only
# for CSRF double-submit validation (its value is never treated as a secret credential).
SESSION_COOKIE_NAME = "ih_session"
CSRF_COOKIE_NAME = "ih_csrf"


def generate_token(user_id: int, session_version: int, remember: bool = False) -> str:
    return _serializer.dumps({
        "user_id": user_id,
        "session_version": session_version,
        "remember": remember
    })


def verify_token(token: str) -> dict | None:
    try:
        # Load once without age verification to find the 'remember' setting
        payload = _serializer.loads(token)
        remember = payload.get("remember", False)
        max_age = Config.SESSION_REMEMBER_AGE if remember else Config.SESSION_DEFAULT_AGE
        # Validate with timed expiration
        return _serializer.loads(token, max_age=max_age)
    except Exception:
        return None


def get_token_from_header(request: Request) -> str | None:
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        return None
    parts = auth_header.split()
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1]
    return None


class LoginRequired(Exception):
    def __init__(self, next_url: str = "/dashboard"):
        self.next_url = next_url


# ---------------------------------------------------------------------------
# Session / auth helpers
# ---------------------------------------------------------------------------

def get_optional_user(request: Request, db: DbSession) -> User | None:
    # Prefer the Authorization header (used by the pytest suite and any future non-browser
    # client); fall back to the HttpOnly session cookie the browser sends automatically.
    token = get_token_from_header(request) or request.cookies.get(SESSION_COOKIE_NAME)
    if not token:
        return None

    payload = verify_token(token)
    if not payload:
        return None

    user_id = payload.get("user_id")
    if not user_id:
        return None

    user = db.get(User, int(user_id))
    if not user or not user.is_active:
        return None

    # Invalidate sessions created before a password change
    stored_version = payload.get("session_version", 1)
    if stored_version != user.session_version:
        return None

    return user


def require_login(request: Request, db: DbSession) -> User:
    user = get_optional_user(request, db)
    if not user:
        raise LoginRequired(request.url.path)
    return user


def require_roles(*roles: str):
    def checker(request: Request, db: DbSession) -> User:
        user = require_login(request, db)
        if user.role not in roles:
            flash(request, "You do not have permission to view that page.", "danger")
            raise HTTPException(status_code=403, detail="Forbidden")
        return user
    return checker


CurrentUser = Annotated[User, Depends(require_login)]
AdminUser = Annotated[User, Depends(require_roles("admin"))]
MentorOrAdmin = Annotated[User, Depends(require_roles("admin", "mentor"))]


def login_user(request: Request, user: User, remember: bool = False) -> str:
    return generate_token(user.id, user.session_version, remember)


def logout_user(request: Request) -> None:
    pass


# ---------------------------------------------------------------------------
# Session cookie issuance (HttpOnly auth cookie + JS-readable CSRF cookie)
# ---------------------------------------------------------------------------

def _is_https_request(request: Request) -> bool:
    """True if the browser's connection was HTTPS, even when TLS terminates at a
    reverse proxy/tunnel in front of this process (e.g. cloudflared / Railway) and
    uvicorn itself only ever sees plain HTTP."""
    forwarded = request.headers.get("x-forwarded-proto")
    if forwarded:
        return forwarded.split(",")[0].strip().lower() == "https"
    return request.url.scheme == "https"


def _cookie_secure(request: Request) -> bool:
    """Secure cookies in production, or whenever the client connection is HTTPS."""
    return Config.COOKIE_SECURE or _is_https_request(request)


def issue_session_cookies(request: Request, response: Response, token: str, remember: bool) -> None:
    """Set the HttpOnly auth cookie and its paired CSRF cookie on a response."""
    max_age = Config.SESSION_REMEMBER_AGE if remember else Config.SESSION_DEFAULT_AGE
    secure = _cookie_secure(request)
    response.set_cookie(
        SESSION_COOKIE_NAME, token,
        max_age=max_age, httponly=True, secure=secure, samesite="lax", path="/",
    )
    # Not a secret — its only job is to prove the request came from a page that could
    # read this origin's cookies (double-submit CSRF defense), not to authenticate.
    response.set_cookie(
        CSRF_COOKIE_NAME, secrets.token_urlsafe(32),
        max_age=max_age, httponly=False, secure=secure, samesite="lax", path="/",
    )


def clear_session_cookies(request: Request, response: Response) -> None:
    secure = _cookie_secure(request)
    response.delete_cookie(SESSION_COOKIE_NAME, path="/", secure=secure, samesite="lax")
    response.delete_cookie(CSRF_COOKIE_NAME, path="/", secure=secure, samesite="lax")


# ---------------------------------------------------------------------------
# CSRF protection (double-submit cookie) — enforced globally for cookie-authenticated,
# state-changing requests by the middleware in main.py. Bearer-token requests are exempt
# since a third-party page cannot make the browser attach an Authorization header.
# ---------------------------------------------------------------------------

def csrf_token_valid(request: Request) -> bool:
    cookie_token = request.cookies.get(CSRF_COOKIE_NAME)
    header_token = request.headers.get("x-csrf-token")
    if not cookie_token or not header_token:
        return False
    return secrets.compare_digest(cookie_token, header_token)
