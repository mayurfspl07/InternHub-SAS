"""Security infrastructure: hashing, session tokens, and CSRF protection."""
import base64
import hashlib
import hmac
import os
import secrets
import time
from typing import Any

from config import Config

SECRET_KEY = Config.SECRET_KEY


def hash_password(plain: str) -> str:
    """Hash a plaintext password using salted PBKDF2-HMAC-SHA256."""
    salt = secrets.token_hex(16)
    dk = hashlib.pbkdf2_hmac("sha256", plain.encode("utf-8"), salt.encode("utf-8"), 260_000)
    return f"{salt}${dk.hex()}"


def verify_password(plain: str, hashed: str) -> bool:
    """Verify a plaintext password against a stored PBKDF2 hash."""
    try:
        salt, dk_hex = hashed.split("$", 1)
        dk = hashlib.pbkdf2_hmac("sha256", plain.encode("utf-8"), salt.encode("utf-8"), 260_000)
        return hmac.compare_digest(dk.hex(), dk_hex)
    except Exception:
        return False


def generate_token(user_id: int, session_version: int) -> str:
    """Generate a tamper-evident signed authentication token."""
    payload = f"{user_id}:{session_version}:{int(time.time())}"
    sig = hmac.new(SECRET_KEY.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
    raw = f"{payload}:{sig}"
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("utf-8")


def decode_token(token: str) -> tuple[int, int] | None:
    """Decode and verify a signed authentication token, returning (user_id, session_version)."""
    try:
        raw = base64.urlsafe_b64decode(token.encode("utf-8")).decode("utf-8")
        parts = raw.split(":")
        if len(parts) != 4:
            return None
        user_id_str, ver_str, ts_str, sig = parts
        payload = f"{user_id_str}:{ver_str}:{ts_str}"
        expected_sig = hmac.new(SECRET_KEY.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig, expected_sig):
            return None
        return int(user_id_str), int(ver_str)
    except Exception:
        return None


def generate_csrf_token() -> str:
    return secrets.token_hex(32)


def validate_csrf_token(stored_token: str, submitted_token: str) -> bool:
    if not stored_token or not submitted_token:
        return False
    return hmac.compare_digest(str(stored_token), str(submitted_token))
