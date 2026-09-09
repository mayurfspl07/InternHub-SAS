"""Cloudinary image service for cloud asset uploads and management."""
import logging
import os
from io import BytesIO
from typing import Any

from config import Config

logger = logging.getLogger(__name__)

_cloudinary_initialized = False


def _init_cloudinary():
    global _cloudinary_initialized

    try:
        import cloudinary
        import cloudinary.uploader
        import cloudinary.api

        if Config.CLOUDINARY_URL:
            os.environ["CLOUDINARY_URL"] = Config.CLOUDINARY_URL
            cloudinary.reset_config()
            cloudinary.config(cloudinary_url=Config.CLOUDINARY_URL, secure=True)
            _cloudinary_initialized = True
        elif Config.CLOUDINARY_CLOUD_NAME and Config.CLOUDINARY_API_KEY and Config.CLOUDINARY_API_SECRET:
            cloudinary.config(
                cloud_name=Config.CLOUDINARY_CLOUD_NAME,
                api_key=Config.CLOUDINARY_API_KEY,
                api_secret=Config.CLOUDINARY_API_SECRET,
                secure=True,
            )
            _cloudinary_initialized = True
    except Exception as e:
        logger.warning("Failed to initialize Cloudinary configuration: %s", e)


def is_cloudinary_configured() -> bool:
    """Check if Cloudinary environment credentials are configured."""
    if bool(Config.CLOUDINARY_URL):
        return True
    if bool(Config.CLOUDINARY_CLOUD_NAME and Config.CLOUDINARY_API_KEY and Config.CLOUDINARY_API_SECRET):
        return True
    return False


def upload_image(
    content: bytes | str | BytesIO,
    folder: str | None = None,
    public_id: str | None = None,
    tags: list[str] | None = None,
    transformation: dict | list | None = None,
    resource_type: str = "image",
) -> dict[str, Any]:
    """Upload an image to Cloudinary.

    Returns dictionary with secure_url, public_id, format, width, height, bytes.
    Raises ValueError on invalid input or RuntimeError on failure.
    """
    if not is_cloudinary_configured():
        raise RuntimeError("Cloudinary is not configured. Please set CLOUDINARY_URL or CLOUDINARY_CLOUD_NAME/API_KEY/API_SECRET.")

    _init_cloudinary()
    import cloudinary.uploader

    target_folder = folder or Config.CLOUDINARY_FOLDER
    upload_options: dict[str, Any] = {
        "folder": target_folder,
        "resource_type": resource_type,
        "secure": True,
        "overwrite": True,
    }

    if public_id:
        upload_options["public_id"] = public_id
    if tags:
        upload_options["tags"] = tags
    if transformation:
        upload_options["transformation"] = transformation

    # Default image optimization delivery
    if resource_type == "image" and not transformation:
        upload_options["quality"] = "auto"
        upload_options["fetch_format"] = "auto"

    try:
        if isinstance(content, bytes):
            result = cloudinary.uploader.upload(BytesIO(content), **upload_options)
        else:
            result = cloudinary.uploader.upload(content, **upload_options)

        return {
            "secure_url": result.get("secure_url") or result.get("url"),
            "url": result.get("secure_url") or result.get("url"),
            "public_id": result.get("public_id"),
            "format": result.get("format"),
            "width": result.get("width"),
            "height": result.get("height"),
            "bytes": result.get("bytes"),
            "created_at": result.get("created_at"),
            "resource_type": result.get("resource_type"),
        }
    except Exception as e:
        logger.error("Cloudinary upload failed: %s", e)
        raise RuntimeError(f"Cloudinary upload failed: {e}") from e


def delete_image(public_id: str) -> bool:
    """Delete an image asset from Cloudinary by public ID."""
    if not is_cloudinary_configured() or not public_id:
        return False

    _init_cloudinary()
    import cloudinary.uploader

    try:
        res = cloudinary.uploader.destroy(public_id)
        return res.get("result") in ("ok", "not found")
    except Exception as e:
        logger.warning("Cloudinary delete failed for %s: %s", public_id, e)
        return False


def signed_delivery_url(url: str | None) -> str | None:
    """Return a signed Cloudinary CDN delivery URL for a stored Cloudinary asset.

    Lets the frontend render attendance photos with a plain <img src> even when
    unsigned delivery is restricted on the cloud. Non-Cloudinary URLs (local
    file paths, third-party hosts) pass through unchanged, as does anything
    when Cloudinary is not configured.
    """
    if not url:
        return url
    raw = str(url).strip()
    if not raw.startswith(("http://", "https://")) or "/upload/" not in raw:
        return raw
    if not is_cloudinary_configured():
        return raw

    try:
        import cloudinary

        _init_cloudinary()
        public_id = raw.split("/upload/", 1)[1]
        # Drop the version segment (v1234567890/) if present.
        if public_id.startswith("v") and "/" in public_id and public_id.split("/", 1)[0][1:].isdigit():
            public_id = public_id.split("/", 1)[1]
        # Drop any transformation segments and the file extension.
        if "." in public_id.rsplit("/", 1)[-1]:
            public_id = public_id.rsplit(".", 1)[0]
        return cloudinary.CloudinaryImage(public_id).build_url(sign_url=True, secure=True)
    except Exception as e:
        logger.warning("Could not sign Cloudinary URL (%s): %s", raw, e)
        return raw
