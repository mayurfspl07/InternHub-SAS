"""JSON profile endpoints."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.orm import Session

from database import get_db
from dependencies import (
    SESSION_COOKIE_NAME,
    generate_token,
    get_optional_user,
    get_token_from_header,
    issue_session_cookies,
    verify_token,
)
from models import User
from utils import record_audit, isoformat_utc

router = APIRouter(prefix="/api/profile", tags=["api-profile"])
DbSession = Annotated[Session, Depends(get_db)]


def _user_dict(u: User) -> dict:
    return {
        "id": u.id,
        "name": u.name,
        "email": u.email,
        "role": u.role,
        "is_active": u.is_active,
        "bio": u.bio,
        "department": u.department,
        "skills": u.skills_list(),
        "phone": u.phone,
        "job_title": u.job_title,
        "joining_date": u.joining_date.isoformat() if u.joining_date else None,
        "created_at": isoformat_utc(u.created_at),
    }


@router.get("")
async def get_profile(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    return _user_dict(user)


@router.put("")
async def update_profile(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    data = await request.json()

    if "name" in data:
        name = str(data["name"]).strip()
        if not name:
            raise HTTPException(status_code=422, detail="Name is required.")
        user.name = name

    if "email" in data:
        email = str(data["email"]).strip().lower()
        if not email:
            raise HTTPException(status_code=422, detail="Email is required.")
        existing = db.query(User).filter(User.email == email, User.id != user.id).first()
        if existing:
            raise HTTPException(status_code=409, detail="That email is already in use.")
        user.email = email

    if "bio" in data:
        user.bio = str(data["bio"]).strip() or None
    if "department" in data:
        user.department = str(data["department"]).strip() or None
    if "phone" in data:
        user.phone = str(data["phone"]).strip() or None
    if "job_title" in data:
        user.job_title = str(data["job_title"]).strip() or None
    if "skills" in data:
        skills = data["skills"]
        if isinstance(skills, list):
            user.skills = ", ".join(str(s).strip() for s in skills if str(s).strip())
        else:
            user.skills = str(skills).strip() or None
    # joining_date is intentionally not editable here — only admins/mentors can set it,
    # via PUT /api/admin/users/{id}. This endpoint only ever edits the caller's own record.

    record_audit(db, user, "profile.update", "updated their profile", user.name)
    db.commit()
    return _user_dict(user)


@router.post("/change-password")
async def change_password(request: Request, response: Response, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    data = await request.json()
    current_pw = str(data.get("current_password", ""))
    new_pw = str(data.get("new_password", ""))
    confirm_pw = str(data.get("confirm_password", ""))

    if not user.check_password(current_pw):
        raise HTTPException(status_code=400, detail="Current password is incorrect.")
    if len(new_pw) < 8 or not any(c.isdigit() for c in new_pw):
        raise HTTPException(status_code=422, detail="New password must be at least 8 characters and include a number.")
    if new_pw != confirm_pw:
        raise HTTPException(status_code=422, detail="New passwords do not match.")

    current_token = get_token_from_header(request) or request.cookies.get(SESSION_COOKIE_NAME)
    current_payload = verify_token(current_token) if current_token else None
    remember = bool(current_payload and current_payload.get("remember"))

    user.set_password(new_pw)  # increments session_version
    record_audit(
        db,
        user,
        "user.password_change",
        "changed their password",
        user.name,
        affected_user_id=user.id,
    )
    db.commit()
    token = generate_token(user.id, user.session_version, remember=remember)
    issue_session_cookies(request, response, token, remember)
    return {"ok": True, "message": "Password changed successfully."}
