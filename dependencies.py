"""Authentication, CSRF, session, and tenant context helpers."""
from dataclasses import dataclass, field
import secrets
import time
from typing import Annotated

from fastapi import Depends, HTTPException, Request, Response
from sqlalchemy.orm import Session
from itsdangerous import URLSafeTimedSerializer

from config import Config
from database import get_db
from models import Organization, OrganizationMembership, OrganizationSettings, User, UserRole
from repositories.tenant_repository import TenantRepository
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
        payload = _serializer.loads(token)
        remember = payload.get("remember", False)
        max_age = Config.SESSION_REMEMBER_AGE if remember else Config.SESSION_DEFAULT_AGE
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
    if not user or not user.is_active or user.is_deleted:
        return None

    stored_version = payload.get("session_version", 1)
    if stored_version != user.session_version:
        return None

    return user


def require_login(request: Request, db: DbSession) -> User:
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user


def require_roles(*roles: str):
    def checker(request: Request, db: DbSession) -> User:
        user = require_login(request, db)
        if user.role not in roles:
            flash(request, "You do not have permission to view that page.", "danger")
            raise HTTPException(status_code=403, detail="Forbidden")
        return user
    return checker


def require_platform_admin(request: Request, db: DbSession) -> User:
    user = require_login(request, db)
    if not user.is_platform_admin:
        raise HTTPException(status_code=403, detail="Platform Super Admin access required")
    return user


require_admin = require_roles("admin", "superadmin")
require_mentor = require_roles("admin", "superadmin", "mentor")
require_intern = require_roles("intern")

CurrentUser = Annotated[User, Depends(require_login)]
AdminUser = Annotated[User, Depends(require_admin)]
MentorOrAdmin = Annotated[User, Depends(require_mentor)]
InternUser = Annotated[User, Depends(require_intern)]
PlatformAdminUser = Annotated[User, Depends(require_platform_admin)]


# ---------------------------------------------------------------------------
# Tenant Request Context
# ---------------------------------------------------------------------------

@dataclass
class RequestContext:
    user: User
    organization: Organization
    membership: OrganizationMembership
    role: str
    settings: OrganizationSettings
    repo: TenantRepository
    permissions: set[str] = field(default_factory=set)

    @property
    def is_platform_admin(self) -> bool:
        return self.user.is_platform_admin or self.role == UserRole.SUPERADMIN

    @property
    def is_superadmin(self) -> bool:
        return self.role == UserRole.SUPERADMIN or self.user.is_platform_admin

    @property
    def is_admin(self) -> bool:
        return self.role in (UserRole.ADMIN, UserRole.SUPERADMIN, "org_admin") or self.user.is_platform_admin

    @property
    def is_mentor(self) -> bool:
        return self.role == UserRole.MENTOR

    @property
    def is_intern(self) -> bool:
        return self.role == UserRole.INTERN


def get_request_context(request: Request, db: DbSession) -> RequestContext:
    user = require_login(request, db)

    org_header = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    target_org_id = int(org_header) if org_header and str(org_header).isdigit() else None

    membership = None
    if target_org_id:
        membership = (
            db.query(OrganizationMembership)
            .filter(
                OrganizationMembership.user_id == user.id,
                OrganizationMembership.organization_id == target_org_id,
                OrganizationMembership.is_active == True,
                OrganizationMembership.is_deleted == False,
            )
            .first()
        )
        if not membership and not user.is_platform_admin:
            raise HTTPException(status_code=403, detail="Not a member of the specified organization")

    if not membership:
        membership = (
            db.query(OrganizationMembership)
            .filter(
                OrganizationMembership.user_id == user.id,
                OrganizationMembership.is_active == True,
                OrganizationMembership.is_deleted == False,
            )
            .order_by(OrganizationMembership.id.asc())
            .first()
        )

    if not membership:
        if user.is_platform_admin:
            # Platform admins can access any organization; get first active org
            membership = (
                db.query(OrganizationMembership)
                .filter(OrganizationMembership.user_id == user.id, OrganizationMembership.is_active == True)
                .order_by(OrganizationMembership.id.asc())
                .first()
            )
            if not membership:
                raise HTTPException(status_code=403, detail="No organization membership found for platform admin")
        else:
            # Regular users must have an explicit organization context
            raise HTTPException(status_code=403, detail="Organization context required - specify X-Organization-Id header")

    org = db.get(Organization, membership.organization_id)
    if not org or org.is_deleted or org.status != "active":
        raise HTTPException(status_code=403, detail="Organization is inactive or suspended")

    settings = db.get(OrganizationSettings, org.id)
    if not settings:
        settings = OrganizationSettings(organization_id=org.id)
        db.add(settings)
        db.commit()
        db.refresh(settings)

    repo = TenantRepository(db, org.id)
    return RequestContext(
        user=user,
        organization=org,
        membership=membership,
        role=membership.role,
        settings=settings,
        repo=repo,
    )


TenantContext = Annotated[RequestContext, Depends(get_request_context)]


def login_user(request: Request, user: User, remember: bool = False) -> str:
    return generate_token(user.id, user.session_version, remember)


def logout_user(request: Request) -> None:
    pass


# ---------------------------------------------------------------------------
# Session cookie issuance
# ---------------------------------------------------------------------------

def _is_https_request(request: Request) -> bool:
    forwarded = request.headers.get("x-forwarded-proto")
    if forwarded:
        return forwarded.split(",")[0].strip().lower() == "https"
    return request.url.scheme == "https"


def _cookie_secure(request: Request) -> bool:
    return Config.COOKIE_SECURE or _is_https_request(request)


def issue_session_cookies(request: Request, response: Response, token: str, remember: bool) -> None:
    max_age = Config.SESSION_REMEMBER_AGE if remember else Config.SESSION_DEFAULT_AGE
    secure = _cookie_secure(request)
    response.set_cookie(
        SESSION_COOKIE_NAME, token,
        max_age=max_age, httponly=True, secure=secure, samesite="lax", path="/",
    )
    response.set_cookie(
        CSRF_COOKIE_NAME, secrets.token_urlsafe(32),
        max_age=max_age, httponly=False, secure=secure, samesite="lax", path="/",
    )


def clear_session_cookies(request: Request, response: Response) -> None:
    secure = _cookie_secure(request)
    response.delete_cookie(SESSION_COOKIE_NAME, path="/", secure=secure, samesite="lax")
    response.delete_cookie(CSRF_COOKIE_NAME, path="/", secure=secure, samesite="lax")


def csrf_token_valid(request: Request) -> bool:
    cookie_token = request.cookies.get(CSRF_COOKIE_NAME)
    header_token = request.headers.get("x-csrf-token")
    if not cookie_token or not header_token:
        return False
    return secrets.compare_digest(cookie_token, header_token)


def _resolve_request_org_id(request: Request, user: User | None = None, db: DbSession | None = None) -> int | None:
    """Helper to resolve active organization ID from headers, query params, or user membership."""
    org_header = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if org_header and str(org_header).isdigit():
        return int(org_header)

    if user and db:
        m = (
            db.query(OrganizationMembership)
            .filter(
                OrganizationMembership.user_id == user.id,
                OrganizationMembership.is_active == True,
                OrganizationMembership.is_deleted == False,
            )
            .order_by(OrganizationMembership.id.asc())
            .first()
        )
        if m:
            return m.organization_id

    return None

