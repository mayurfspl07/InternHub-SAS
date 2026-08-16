"""Disk-based attendance selfie persistence and safe path resolver."""
import os
import re
from datetime import date, datetime
from config import Config


def _slugify(name: str) -> str:
    s = re.sub(r"[^\w\s-]", "", name).strip().lower()
    return re.sub(r"[-\s]+", "_", s) or "user"


def save_attendance_photo(
    user_id: int,
    user_name: str,
    day: date,
    kind: str,
    content: bytes,
) -> str:
    """Validate and persist selfie photo to ATTENDANCE_PHOTOS_DIR.

    Returns the relative path to be stored in the database.
    """
    if not content:
        raise ValueError("Photo content cannot be empty.")
    if len(content) > 10 * 1024 * 1024:  # 10 MB max
        raise ValueError("Photo file size exceeds 10 MB limit.")

    # Allowed kinds
    if kind not in ("checkin", "checkout"):
        raise ValueError(f"Invalid photo kind: {kind}")

    # Build relative directory: <YYYY-MM-DD>/<user_id>_<slug>/<kind>/
    day_str = day.isoformat()
    slug = _slugify(user_name)
    user_dir = f"{user_id}_{slug}"
    timestamp_name = datetime.now().strftime("%H%M%S") + ".jpg"

    rel_path = os.path.join(day_str, user_dir, kind, timestamp_name)
    base_dir = os.path.abspath(Config.ATTENDANCE_PHOTOS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))

    # Path traversal prevention
    if not abs_path.startswith(base_dir):
        raise ValueError("Invalid target path.")

    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "wb") as f:
        f.write(content)

    return rel_path.replace("\\", "/")


def photo_abs_path(rel_path: str) -> str | None:
    """Safely resolve a relative photo path to an absolute path on disk."""
    if not rel_path:
        return None
    base_dir = os.path.abspath(Config.ATTENDANCE_PHOTOS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))
    if not abs_path.startswith(base_dir):
        return None
    if os.path.isfile(abs_path):
        return abs_path
    return None
