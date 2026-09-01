"""Attendance selfie persistence (Cloudinary-enabled with disk fallback) and safe path resolver."""
import logging
import os
import re
from datetime import date, datetime
from config import Config
from cloudinary_service import is_cloudinary_configured, upload_image

logger = logging.getLogger(__name__)


def _slugify(name: str) -> str:
    s = re.sub(r"[^\w\s-]", "", name).strip().lower()
    return re.sub(r"[-\s]+", "_", s) or "user"


def save_attendance_photo(
    user_id: int,
    user_name: str,
    day: date,
    kind: str,
    content: bytes | str,
) -> str:
    """Validate and persist selfie photo to Cloudinary or local storage.

    Accepts raw bytes, base64 strings (including data:image/... URIs), or file bytes.
    When Cloudinary is configured, uploads directly to Cloudinary and returns
    the HTTPS Cloudinary URL. Otherwise, saves to ATTENDANCE_PHOTOS_DIR.
    """
    import base64

    if not content:
        raise ValueError("Photo content cannot be empty.")

    if isinstance(content, str):
        content_str = content.strip()
        if content_str.startswith(("http://", "https://")):
            return content_str
        if "," in content_str and "base64" in content_str:
            content_str = content_str.split(",", 1)[1]
        try:
            content_bytes = base64.b64decode(content_str)
        except Exception as e:
            raise ValueError(f"Invalid base64 photo data: {e}")
    elif isinstance(content, (bytes, bytearray)):
        content_bytes = bytes(content)
    else:
        raise ValueError("Unsupported photo content format.")

    if not content_bytes:
        raise ValueError("Photo content cannot be empty.")
    if len(content_bytes) > 10 * 1024 * 1024:  # 10 MB max
        raise ValueError("Photo file size exceeds 10 MB limit.")

    # Allowed kinds
    if kind not in ("checkin", "checkout"):
        raise ValueError(f"Invalid photo kind: {kind}")

    day_str = day.isoformat()
    slug = _slugify(user_name)
    user_dir = f"{user_id}_{slug}"
    time_str = datetime.now().strftime("%H%M%S")

    # 1. Cloudinary upload if configured
    if is_cloudinary_configured():
        try:
            folder = f"{Config.CLOUDINARY_FOLDER}/attendance/{day_str}/{user_dir}"
            public_id = f"{kind}_{time_str}"
            result = upload_image(
                content=content_bytes,
                folder=folder,
                public_id=public_id,
                tags=["attendance", kind, f"user_{user_id}", day_str],
            )
            secure_url = result.get("secure_url") or result.get("url")
            if secure_url:
                return secure_url
        except Exception as e:
            logger.warning("Cloudinary attendance upload failed, falling back to local disk: %s", e)

    # 2. Local disk fallback
    timestamp_name = f"{time_str}.jpg"
    rel_path = os.path.join(day_str, user_dir, kind, timestamp_name)
    base_dir = os.path.abspath(Config.ATTENDANCE_PHOTOS_DIR)
    abs_path = os.path.abspath(os.path.join(base_dir, rel_path))

    # Path traversal prevention
    if not abs_path.startswith(base_dir):
        raise ValueError("Invalid target path.")

    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "wb") as f:
        f.write(content_bytes)

    return rel_path.replace("\\", "/")


def photo_abs_path(rel_path: str) -> str | None:
    """Safely resolve a relative photo path to an absolute path on disk."""
    if not rel_path:
        return None

    # Handle string cleanup
    clean_path = str(rel_path).strip().lstrip("/\\")
    if not clean_path:
        return None

    candidate_bases = [
        os.path.abspath(Config.ATTENDANCE_PHOTOS_DIR),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "attendance_photos")),
        os.path.abspath("attendance_photos"),
    ]

    for base_dir in candidate_bases:
        if not os.path.exists(base_dir):
            continue
        abs_path = os.path.abspath(os.path.join(base_dir, clean_path))
        if abs_path.startswith(base_dir) and os.path.isfile(abs_path):
            return abs_path

    # Fallback search if username slug changed or separators differed
    parts = clean_path.replace("\\", "/").split("/")
    if len(parts) >= 3:
        # e.g. [2026-08-31, 4_intern_bob, checkin, 234014.jpg]
        day_str = parts[0]
        user_dir = parts[1]
        kind = parts[2]
        filename = parts[3] if len(parts) >= 4 else None

        user_id_prefix = user_dir.split("_")[0] if "_" in user_dir else user_dir
        for base_dir in candidate_bases:
            day_dir = os.path.join(base_dir, day_str)
            if not os.path.isdir(day_dir):
                continue
            for entry in os.listdir(day_dir):
                if entry == user_dir or entry.startswith(f"{user_id_prefix}_"):
                    target_kind_dir = os.path.join(day_dir, entry, kind)
                    if os.path.isdir(target_kind_dir):
                        if filename:
                            candidate_file = os.path.join(target_kind_dir, filename)
                            if os.path.isfile(candidate_file):
                                return candidate_file
                        # If filename changed or not found, return newest photo in kind directory
                        kind_files = [
                            os.path.join(target_kind_dir, f)
                            for f in os.listdir(target_kind_dir)
                            if f.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))
                        ]
                        if kind_files:
                            kind_files.sort(key=os.path.getmtime, reverse=True)
                            return kind_files[0]

    return None
