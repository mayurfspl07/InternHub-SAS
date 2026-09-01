"""Image upload endpoints supporting Cloudinary and local disk fallback."""
import logging
import os
import re
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from sqlalchemy.orm import Session

from config import Config
from database import get_db
from dependencies import get_optional_user
from models import Organization, User, _utcnow
from utils import record_audit
from cloudinary_service import is_cloudinary_configured, upload_image

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/upload", tags=["Image Uploads"])
DbSession = Annotated[Session, Depends(get_db)]

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg"}
MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10 MB


def _validate_image_file(file: UploadFile, content: bytes) -> str:
    if not content:
        raise HTTPException(status_code=422, detail="Uploaded file is empty.")
    if len(content) > MAX_IMAGE_SIZE:
        raise HTTPException(status_code=422, detail="Image size exceeds 10 MB limit.")

    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=422,
            detail=f"Unsupported file format '{ext}'. Allowed: {', '.join(sorted(ALLOWED_IMAGE_EXTENSIONS))}",
        )
    return ext


def _save_local_fallback(content: bytes, subfolder: str, filename: str) -> str:
    """Save image to local UPLOADS_DIR fallback if Cloudinary is not configured."""
    clean_subfolder = re.sub(r"[^\w/-]", "", subfolder).strip("/") or "general"
    folder_path = os.path.join(Config.UPLOADS_DIR, clean_subfolder)
    os.makedirs(folder_path, exist_ok=True)

    safe_name = f"{_utcnow().strftime('%Y%m%d_%H%M%S')}_{os.path.basename(filename)}"
    abs_path = os.path.join(folder_path, safe_name)
    with open(abs_path, "wb") as f:
        f.write(content)

    rel_path = os.path.join("uploads", clean_subfolder, safe_name).replace("\\", "/")
    return f"/{rel_path}"


@router.get("/status")
async def get_upload_status(request: Request, db: DbSession):
    """Check image upload provider status and configuration."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    configured = is_cloudinary_configured()
    return {
        "provider": "cloudinary" if configured else "local_disk",
        "cloudinary_configured": configured,
        "cloud_name": Config.CLOUDINARY_CLOUD_NAME if configured and user.is_admin else None,
        "folder": Config.CLOUDINARY_FOLDER,
        "max_size_mb": 10,
        "allowed_formats": list(ALLOWED_IMAGE_EXTENSIONS),
    }


@router.post("/image")
async def upload_generic_image(
    request: Request,
    db: DbSession,
    file: UploadFile = File(...),
    folder: str = Form("general"),
):
    """Upload any image to Cloudinary (with local fallback if unconfigured)."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    content = await file.read()
    _validate_image_file(file, content)

    target_folder = f"{Config.CLOUDINARY_FOLDER}/{folder.strip('/')}"

    if is_cloudinary_configured():
        try:
            result = upload_image(
                content=content,
                folder=target_folder,
                tags=[folder, f"user_{user.id}"],
            )
            return {
                "success": True,
                "provider": "cloudinary",
                "url": result.get("secure_url") or result.get("url"),
                "secure_url": result.get("secure_url") or result.get("url"),
                "public_id": result.get("public_id"),
                "format": result.get("format"),
                "width": result.get("width"),
                "height": result.get("height"),
                "bytes": result.get("bytes"),
            }
        except Exception as e:
            logger.warning("Cloudinary upload failed, falling back to disk: %s", e)

    # Local fallback
    local_url = _save_local_fallback(content, folder, file.filename or "image.jpg")
    return {
        "success": True,
        "provider": "local_disk",
        "url": local_url,
        "secure_url": local_url,
        "bytes": len(content),
    }


@router.post("/avatar")
async def upload_user_avatar(
    request: Request,
    db: DbSession,
    file: UploadFile = File(...),
):
    """Upload user avatar to Cloudinary and update profile."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    content = await file.read()
    _validate_image_file(file, content)

    target_folder = f"{Config.CLOUDINARY_FOLDER}/avatars"
    public_id = f"user_{user.id}_avatar"

    url = None
    if is_cloudinary_configured():
        try:
            result = upload_image(
                content=content,
                folder=target_folder,
                public_id=public_id,
                tags=["avatar", f"user_{user.id}"],
                transformation={"width": 400, "height": 400, "crop": "fill", "gravity": "face"},
            )
            url = result.get("secure_url") or result.get("url")
        except Exception as e:
            logger.warning("Avatar Cloudinary upload failed: %s", e)

    if not url:
        url = _save_local_fallback(content, "avatars", file.filename or "avatar.jpg")

    record_audit(db, user, "user.avatar_upload", "uploaded new avatar image", user.name)
    return {
        "success": True,
        "message": "Avatar uploaded successfully.",
        "avatar_url": url,
        "url": url,
    }


@router.post("/org-logo")
async def upload_org_logo(
    request: Request,
    db: DbSession,
    file: UploadFile = File(...),
):
    """Upload organization logo to Cloudinary and update organization."""
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    content = await file.read()
    _validate_image_file(file, content)

    org_id = 1
    from dependencies import _resolve_request_org_id
    resolved_org = _resolve_request_org_id(request, user, db)
    if resolved_org:
        org_id = resolved_org

    target_folder = f"{Config.CLOUDINARY_FOLDER}/logos"
    public_id = f"org_{org_id}_logo"

    url = None
    if is_cloudinary_configured():
        try:
            result = upload_image(
                content=content,
                folder=target_folder,
                public_id=public_id,
                tags=["logo", f"org_{org_id}"],
            )
            url = result.get("secure_url") or result.get("url")
        except Exception as e:
            logger.warning("Logo Cloudinary upload failed: %s", e)

    if not url:
        url = _save_local_fallback(content, "logos", file.filename or "logo.png")

    org = db.get(Organization, org_id)
    if org:
        org.logo_url = url
        db.commit()

    record_audit(db, user, "org.logo_upload", "uploaded organization logo", org.name if org else "Org")
    return {
        "success": True,
        "message": "Organization logo uploaded successfully.",
        "logo_url": url,
        "url": url,
    }
