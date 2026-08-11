"""Application configuration."""
import os
from datetime import time
from decimal import Decimal
from urllib.parse import quote_plus, urlparse, urlunparse, parse_qsl, urlencode

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

try:
    from dotenv import load_dotenv
    load_dotenv(os.path.join(BASE_DIR, ".env"))
except ImportError:
    pass


def _env(*names: str, default: str = "") -> str:
    """Return the first non-empty environment variable among *names*."""
    for name in names:
        value = os.environ.get(name)
        if value is not None and value.strip() != "":
            return value
    return default


class Config:
    # Railway sets RAILWAY_ENVIRONMENT; also honor a generic ENVIRONMENT flag.
    ENVIRONMENT: str = (
        os.environ.get("ENVIRONMENT")
        or os.environ.get("RAILWAY_ENVIRONMENT")
        or "development"
    ).strip().lower()
    IS_PRODUCTION: bool = ENVIRONMENT in ("production", "prod") or bool(
        os.environ.get("RAILWAY_ENVIRONMENT")
    )

    _secret = os.environ.get("SECRET_KEY", "")
    if not _secret:
        import warnings
        warnings.warn(
            "SECRET_KEY env var is not set. Using an insecure default — set SECRET_KEY in production.",
            stacklevel=2,
        )
        _secret = "dev-secret-change-me-in-prod"
    SECRET_KEY: str = _secret
    del _secret

    # Local .env names + Railway MySQL plugin aliases (MYSQLHOST, etc.)
    MYSQL_HOST = _env("MYSQL_HOST", "MYSQLHOST", default="localhost")
    MYSQL_PORT = int(_env("MYSQL_PORT", "MYSQLPORT", default="3306"))
    MYSQL_USER = _env("MYSQL_USER", "MYSQLUSER", default="root")
    MYSQL_PASSWORD = _env("MYSQL_PASSWORD", "MYSQLPASSWORD", default="")
    MYSQL_DATABASE = _env("MYSQL_DATABASE", "MYSQLDATABASE", default="internhub")

    @staticmethod
    def _normalize_database_url(url: str) -> str:
        """Make platform-provided MySQL URLs work with SQLAlchemy + PyMySQL.

        Railway often injects ``mysql://…`` or ``MYSQL_URL`` without the
        ``+pymysql`` driver suffix and sometimes without ``charset=utf8mb4``.
        """
        url = url.strip().strip('"').strip("'")
        if url.startswith("mysql://"):
            url = "mysql+pymysql://" + url[len("mysql://"):]
        elif url.startswith("mariadb://"):
            url = "mysql+pymysql://" + url[len("mariadb://"):]

        parsed = urlparse(url)
        query = dict(parse_qsl(parsed.query, keep_blank_values=True))
        query.setdefault("charset", "utf8mb4")
        return urlunparse(parsed._replace(query=urlencode(query)))

    @classmethod
    def database_url(cls) -> str:
        if url := _env("DATABASE_URL", "MYSQL_URL", "MYSQL_PRIVATE_URL"):
            return cls._normalize_database_url(url)
        pwd = quote_plus(cls.MYSQL_PASSWORD) if cls.MYSQL_PASSWORD else ""
        auth = f"{quote_plus(cls.MYSQL_USER)}:{pwd}" if pwd else quote_plus(cls.MYSQL_USER)
        return (
            f"mysql+pymysql://{auth}@{cls.MYSQL_HOST}:{cls.MYSQL_PORT}"
            f"/{cls.MYSQL_DATABASE}?charset=utf8mb4"
        )

    @classmethod
    def server_url(cls) -> str:
        pwd = quote_plus(cls.MYSQL_PASSWORD) if cls.MYSQL_PASSWORD else ""
        auth = f"{quote_plus(cls.MYSQL_USER)}:{pwd}" if pwd else quote_plus(cls.MYSQL_USER)
        return f"mysql+pymysql://{auth}@{cls.MYSQL_HOST}:{cls.MYSQL_PORT}/?charset=utf8mb4"

    # Intern shift: 10:00 AM – 7:00 PM
    SHIFT_START: time = time(10, 0)
    LATE_CUTOFF: time = time(10, 30)  # provisional "late" at check-in; final status uses NOON_CUTOFF
    NOON_CUTOFF: time = time(12, 0)
    CHECKIN_BLOCK: time = time(20, 0)
    FULL_DAY_HOURS: Decimal = Decimal("7.0")
    HALF_DAY_HOURS: Decimal = Decimal("5.0")
    SHIFT_END_HOUR: int = 19  # used as auto-checkout fallback time

    LEAVE_QUOTA_DAYS: int = 15

    # Recycle bin retention (days) before permanent purge
    BIN_RETENTION_DAYS: int = int(os.environ.get("BIN_RETENTION_DAYS", "15"))

    # Login rate limiting: max attempts per window
    LOGIN_MAX_ATTEMPTS: int = 10
    LOGIN_WINDOW_SECONDS: int = 300

    # Password reset token TTL (seconds)
    RESET_TOKEN_MAX_AGE: int = 3600

    # Session max age for "remember me" (30 days)
    SESSION_REMEMBER_AGE: int = 30 * 24 * 3600
    # Session max age without "remember me" (8 hours)
    SESSION_DEFAULT_AGE: int = 8 * 3600

    # Password required to wipe all application data from the admin panel.
    # Must be set via DB_CLEAR_PASSWORD env var — no default is provided.
    DB_CLEAR_PASSWORD: str | None = os.environ.get("DB_CLEAR_PASSWORD") or None

    # FastAPI bind address — use 0.0.0.0 to accept public/external connections.
    # Railway injects PORT dynamically; prefer it over APP_PORT.
    APP_HOST: str = os.environ.get("APP_HOST", "0.0.0.0")
    APP_PORT: int = int(_env("PORT", "APP_PORT", default="3001"))

    # Business timezone for "today"/shift-boundary logic (attendance, standup, leave).
    # Explicit on purpose — the host OS's timezone differs between local dev machines
    # and production servers, which previously caused "today" and shift cutoffs (10:00
    # AM, noon, 8:00 PM) to silently shift by the OS's UTC offset depending on where the
    # app happened to be running.
    TIMEZONE: str = os.environ.get("APP_TIMEZONE", "Asia/Kolkata")

    # Optional regex for allowed browser origins, only needed for cross-origin dev setups
    # not covered by CORS_ORIGINS below. Left unset by default: combined with
    # allow_credentials=True (required for cookie-based auth), a wildcard regex here would
    # let any origin make credentialed requests using a visitor's session cookie.
    # Example: r"http://(localhost|127\.0\.0\.1):\d+"
    CORS_ORIGIN_REGEX: str | None = os.environ.get("CORS_ORIGIN_REGEX") or None

    # Optional public site URL for generating full invite links (e.g. https://xyz.trycloudflare.com)
    # Must be the https URL users actually open. Keep VITE_API_BASE empty when the SPA is
    # served from this same backend so /api stays same-origin (avoids mixed-content failures).
    # On Railway, set this to your public HTTPS domain (custom domain or *.up.railway.app).
    PUBLIC_SITE_URL: str = os.environ.get("PUBLIC_SITE_URL", "").strip().rstrip("/")

    # Persist attendance selfies on a Railway Volume by pointing this at the mount path
    # (e.g. /data/attendance_photos). Defaults to ./attendance_photos next to the app.
    ATTENDANCE_PHOTOS_DIR: str = os.path.abspath(
        _env(
            "ATTENDANCE_PHOTOS_DIR",
            default=os.path.join(BASE_DIR, "attendance_photos"),
        )
    )

    # Optional override when the Vite build is not in the sibling frontend folder
    # (common when deploying the backend folder alone on Railway).
    FRONTEND_DIST_DIR: str = os.path.abspath(
        _env(
            "FRONTEND_DIST_DIR",
            default=os.path.join(BASE_DIR, "..", "internhub frontend", "dist"),
        )
    )

    # Force Secure cookies (defaults to on in production / Railway).
    _cookie_secure = os.environ.get("COOKIE_SECURE", "").strip().lower()
    COOKIE_SECURE: bool = (
        True if _cookie_secure in ("1", "true", "yes")
        else False if _cookie_secure in ("0", "false", "no")
        else IS_PRODUCTION
    )
    del _cookie_secure

    @classmethod
    def cors_origins(cls) -> list[str]:
        raw = os.environ.get(
            "CORS_ORIGINS",
            "http://localhost:5173,http://127.0.0.1:5173,"
            "http://localhost:3001,http://127.0.0.1:3001",
        )
        origins = [origin.strip().rstrip("/") for origin in raw.split(",") if origin.strip()]
        if cls.PUBLIC_SITE_URL and cls.PUBLIC_SITE_URL not in origins:
            origins.append(cls.PUBLIC_SITE_URL)
        return origins
