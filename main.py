"""FastAPI application entry point."""
import asyncio
import os
from contextlib import asynccontextmanager

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.gzip import GZipMiddleware
from starlette.middleware.sessions import SessionMiddleware
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from config import Config
from dependencies import SESSION_COOKIE_NAME, csrf_token_valid, get_token_from_header
from log_files import setup_terminal_logging
from routes.api import (
    admin, announcements, attendance, audit, auth,
    cohorts, dashboard, leave, notifications, profile,
    projects, reviews, search, standup, users,
)

BACKEND_DIR = os.path.abspath(os.path.dirname(__file__))
FRONTEND_DIST_DIR = Config.FRONTEND_DIST_DIR
BOOTSTRAP_ADMIN_EMAIL = os.environ.get("BOOTSTRAP_ADMIN_EMAIL", "admin@internhub.dev")
BOOTSTRAP_ADMIN_PASSWORD = os.environ.get("BOOTSTRAP_ADMIN_PASSWORD", "Imp@pune1")
BOOTSTRAP_ADMIN_NAME = os.environ.get("BOOTSTRAP_ADMIN_NAME", "Admin")
_attendance_scheduler = BackgroundScheduler()
_DEFAULT_BOOTSTRAP_PASSWORD = "Imp@pune1"


def _ensure_bootstrap_admin() -> None:
    """Create the local bootstrap admin account if it is missing."""
    from database import SessionLocal
    from models import User, UserRole

    if Config.IS_PRODUCTION and BOOTSTRAP_ADMIN_PASSWORD == _DEFAULT_BOOTSTRAP_PASSWORD:
        print(
            "[WARNING] BOOTSTRAP_ADMIN_PASSWORD is still the insecure default. "
            "Set a strong BOOTSTRAP_ADMIN_PASSWORD (and change it after first login) "
            "before exposing this deployment publicly."
        )

    db = SessionLocal()
    try:
        email = BOOTSTRAP_ADMIN_EMAIL.strip().lower()
        user = db.query(User).filter_by(email=email).first()
        if user:
            changed = False
            if user.role != UserRole.ADMIN:
                user.role = UserRole.ADMIN
                changed = True
            if not user.is_active:
                user.is_active = True
                changed = True
            if changed:
                db.commit()
            return

        admin = User(
            name=BOOTSTRAP_ADMIN_NAME,
            email=email,
            role=UserRole.ADMIN,
            is_active=True,
        )
        admin.set_password(BOOTSTRAP_ADMIN_PASSWORD)
        admin.session_version = 1
        db.add(admin)
        db.commit()
        print(f"[INFO] Bootstrap admin created: {email}")
    except Exception as exc:
        db.rollback()
        print(f"[WARNING] Bootstrap admin setup failed: {exc}")
    finally:
        db.close()


def _run_auto_checkout() -> None:
    """Midnight / startup catch-up — own DB session (outside FastAPI request cycle)."""
    from database import SessionLocal
    from utils import auto_checkout_missed_sessions

    db = SessionLocal()
    try:
        count = auto_checkout_missed_sessions(db)
        if count:
            print(f"[INFO] Auto check-out applied to {count} missed attendance record(s).")
    except Exception as exc:
        print(f"[WARNING] Attendance auto check-out failed: {exc}")
    finally:
        db.close()


def _run_bin_purge() -> None:
    """Daily purge of expired recycle-bin entries."""
    from database import SessionLocal
    from recycle_bin import purge_expired_bin_items

    db = SessionLocal()
    try:
        count = purge_expired_bin_items(db)
        if count:
            print(f"[INFO] Recycle bin purge removed {count} expired item(s).")
    except Exception as exc:
        print(f"[WARNING] Recycle bin purge failed: {exc}")
    finally:
        db.close()


def _run_overdue_task_notifications() -> None:
    """Daily / startup catch-up — reminds an intern and their mentor once per task
    that's gone past its deadline without being marked done."""
    from database import SessionLocal
    from utils import notify_overdue_tasks

    db = SessionLocal()
    try:
        count = notify_overdue_tasks(db)
        if count:
            print(f"[INFO] Sent overdue-task reminders for {count} task(s).")
    except Exception as exc:
        print(f"[WARNING] Overdue-task notification sweep failed: {exc}")
    finally:
        db.close()


def _start_attendance_scheduler() -> None:
    if _attendance_scheduler.get_job("auto_checkout"):
        _attendance_scheduler.remove_job("auto_checkout")
    if _attendance_scheduler.get_job("bin_purge"):
        _attendance_scheduler.remove_job("bin_purge")
    if _attendance_scheduler.get_job("overdue_tasks"):
        _attendance_scheduler.remove_job("overdue_tasks")

    # Explicit timezone: without it, APScheduler fires at midnight in the *host OS's*
    # timezone, which can differ between local dev and the production server and would
    # make "midnight" auto-checkout/purge run at the wrong wall-clock hour in Config.TIMEZONE.
    _attendance_scheduler.add_job(
        func=_run_auto_checkout,
        trigger=CronTrigger(hour=0, minute=0, timezone=Config.TIMEZONE),
        id="auto_checkout",
    )
    _attendance_scheduler.add_job(
        func=_run_bin_purge,
        trigger=CronTrigger(hour=0, minute=5, timezone=Config.TIMEZONE),
        id="bin_purge",
    )
    _attendance_scheduler.add_job(
        func=_run_overdue_task_notifications,
        trigger=CronTrigger(hour=0, minute=10, timezone=Config.TIMEZONE),
        id="overdue_tasks",
    )
    _attendance_scheduler.start()


def _stop_attendance_scheduler() -> None:
    if _attendance_scheduler.running:
        _attendance_scheduler.shutdown(wait=False)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app_logger = setup_terminal_logging()

    from database import SessionLocal
    from models import User
    from migrate_db import sync_schema

    # Idempotent schema sync: creates missing tables and adds missing columns
    try:
        await asyncio.to_thread(sync_schema)
    except Exception as exc:
        app_logger.warning(f"Schema sync failed (run migrate_db.py manually): {exc}")

    await asyncio.to_thread(_ensure_bootstrap_admin)

    db = SessionLocal()
    try:
        if db.query(User).count() == 0:
            app_logger.warning("No users in DB. Run: .venv\\Scripts\\python.exe seed.py")
    finally:
        db.close()

    await asyncio.to_thread(_run_auto_checkout)
    await asyncio.to_thread(_run_bin_purge)
    await asyncio.to_thread(_run_overdue_task_notifications)
    await asyncio.to_thread(_start_attendance_scheduler)

    try:
        yield
    finally:
        await asyncio.to_thread(_stop_attendance_scheduler)


app = FastAPI(title="InternHub", docs_url="/api/docs", redoc_url=None, lifespan=lifespan)

# Railway (and most PaaS) terminate TLS at the edge and forward X-Forwarded-Proto.
# Without this, request.url.scheme stays "http" and Secure cookies / redirects break.
app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")
app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(
    SessionMiddleware,
    secret_key=Config.SECRET_KEY,
    max_age=Config.SESSION_REMEMBER_AGE,
    same_site="lax",
    https_only=Config.COOKIE_SECURE,
)

# Cookie-authenticated, state-changing requests must prove they came from a page that
# could read this origin's cookies (double-submit CSRF token) — Bearer-token requests are
# exempt, since a third-party page can't make the browser attach an Authorization header.
_CSRF_EXEMPT_PATHS = ("/api/auth/login", "/api/auth/register", "/api/auth/invite/")


@app.middleware("http")
async def csrf_guard(request: Request, call_next):
    if (
        request.method in ("POST", "PUT", "DELETE", "PATCH")
        and request.url.path.startswith("/api/")
        and not request.url.path.startswith(_CSRF_EXEMPT_PATHS)
        and not get_token_from_header(request)
        # Only enforce when a session cookie is actually present — an unauthenticated
        # request should fall through to the route's normal 401, not a confusing 403.
        and request.cookies.get(SESSION_COOKIE_NAME)
        and not csrf_token_valid(request)
    ):
        return JSONResponse({"detail": "CSRF validation failed."}, status_code=403)
    return await call_next(request)


# Security response headers (defense in depth — not a substitute for output escaping,
# server-side authorization, etc., which remain the primary controls).
_CSP = (
    "default-src 'self'; "
    "script-src 'self'; "
    # 'unsafe-inline' is required for Radix UI's inline positioning styles on
    # dialogs/popovers/tooltips; there is no inline <script> usage in this app.
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
    "font-src 'self' https://fonts.gstatic.com; "
    "img-src 'self' data:; "
    "connect-src 'self'; "
    "base-uri 'self'; "
    "form-action 'self'; "
    "frame-ancestors 'none'"
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # Camera + geolocation are used for the attendance check-in/out selfie flow (same
    # origin only); microphone stays locked down since nothing in the app uses it.
    response.headers["Permissions-Policy"] = "camera=(self), microphone=(), geolocation=(self)"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Content-Security-Policy"] = _CSP
    # Harmless (ignored) on a plain-HTTP response; protects real users who reach this
    # app over HTTPS (e.g. via the cloudflared tunnel), where TLS terminates upstream of
    # this process.
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


# Added last so it runs first and handles OPTIONS preflight before other middleware.
app.add_middleware(
    CORSMiddleware,
    allow_origins=Config.cors_origins(),
    allow_origin_regex=Config.CORS_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

for _router in (
    auth.router, admin.router, attendance.router, audit.router,
    announcements.router, cohorts.router, dashboard.router,
    leave.router, notifications.router, profile.router,
    projects.router, projects.task_router, reviews.router, search.router, standup.router,
    users.router,
):
    app.include_router(_router)


@app.get("/api/health", include_in_schema=False)
async def health():
    """Liveness probe for Railway / load balancers (no DB dependency)."""
    return {"status": "ok", "service": "internhub"}


assets_dir = os.path.join(FRONTEND_DIST_DIR, "assets")
if os.path.exists(assets_dir):
    app.mount("/assets", StaticFiles(directory=assets_dir), name="static_assets")


@app.api_route("/{path:path}", methods=["GET", "HEAD"], include_in_schema=False)
async def serve_frontend(path: str):
    """Serve Vite assets and fall back to index.html for client-side routes."""
    if path.startswith("api/"):
        return HTMLResponse("Not Found", status_code=404)

    requested_file = os.path.abspath(os.path.join(FRONTEND_DIST_DIR, path))
    try:
        is_frontend_file = (
            os.path.commonpath([FRONTEND_DIST_DIR, requested_file]) == FRONTEND_DIST_DIR
            and os.path.isfile(requested_file)
        )
    except ValueError:
        is_frontend_file = False
    if is_frontend_file:
        return FileResponse(requested_file)

    index_file = os.path.join(FRONTEND_DIST_DIR, "index.html")
    if os.path.isfile(index_file):
        return FileResponse(
            index_file,
            headers={
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Expires": "0",
            },
        )

    return HTMLResponse(
        "<html><body><h2>InternHub API is running.</h2>"
        "<p>The React UI build was not found at this deployment. "
        "API docs: <a href=\"/api/docs\">/api/docs</a></p></body></html>",
        status_code=200,
    )


if __name__ == "__main__":
    import uvicorn

    print(f"[INFO] Starting InternHub on http://{Config.APP_HOST}:{Config.APP_PORT}")
    uvicorn.run("main:app", host=Config.APP_HOST, port=Config.APP_PORT, reload=False)
