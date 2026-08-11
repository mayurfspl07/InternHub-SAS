"""On-disk storage for attendance check-in/check-out selfies.

Layout: attendance_photos/<date>/<user_id>_<name-slug>/<checkin|checkout>/<HHMMSS>.jpg
Photos are resized/compressed client-side before upload, so this module just persists
whatever bytes it's given (capped at MAX_PHOTO_BYTES as a sanity limit) — it does not
re-encode images, to avoid adding an image-processing dependency for a file that's
already a small JPEG by the time it reaches here.
"""
import os
import re
import time as _time
from datetime import date

from config import Config

# Overridable via ATTENDANCE_PHOTOS_DIR (mount a Railway Volume here in production).
PHOTOS_DIR = Config.ATTENDANCE_PHOTOS_DIR

# Real captures (resized to a few hundred px wide, JPEG quality ~0.7) are tens of KB —
# this just guards against a client sending something unexpectedly large.
MAX_PHOTO_BYTES = 2 * 1024 * 1024


def _slug(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "user"


def save_attendance_photo(user_id: int, user_name: str, day: date, kind: str, content: bytes) -> str:
    """Save a selfie to disk and return its path relative to PHOTOS_DIR (stored in the DB)."""
    if not content:
        raise ValueError("Empty photo upload.")
    if len(content) > MAX_PHOTO_BYTES:
        raise ValueError("Photo is too large.")
    if kind not in ("checkin", "checkout"):
        raise ValueError("Invalid photo kind.")

    folder = os.path.join(PHOTOS_DIR, day.isoformat(), f"{user_id}_{_slug(user_name)}", kind)
    os.makedirs(folder, exist_ok=True)
    filename = f"{_time.strftime('%H%M%S')}.jpg"
    abs_path = os.path.join(folder, filename)
    with open(abs_path, "wb") as f:
        f.write(content)
    return os.path.relpath(abs_path, PHOTOS_DIR).replace("\\", "/")


def photo_abs_path(rel_path: str) -> str | None:
    """Resolve a DB-stored relative photo path to an absolute path.

    Returns None if the resolved path would escape PHOTOS_DIR (defense in depth — the
    path is always one this module generated itself, never taken from a request) or if
    the file no longer exists on disk.
    """
    abs_path = os.path.abspath(os.path.join(PHOTOS_DIR, rel_path))
    if os.path.commonpath([PHOTOS_DIR, abs_path]) != PHOTOS_DIR:
        return None
    if not os.path.isfile(abs_path):
        return None
    return abs_path
