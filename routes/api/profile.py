"""JSON profile endpoints."""
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response
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
from utils import record_audit, isoformat_utc, get_internship_summary
from routes.api.schemas import ProfileUpdatePayload, ChangePasswordPayload, get_payload

router = APIRouter(prefix="/api/profile", tags=["Profile"])
DbSession = Annotated[Session, Depends(get_db)]


def _user_dict(u: User, db: Session | None = None) -> dict:
    data = {
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
        "internship_end_date": u.internship_end_date.isoformat() if u.internship_end_date else None,
        "internship_duration_months": u.internship_duration_months,
        "created_at": isoformat_utc(u.created_at),
    }
    if db is not None:
        data["internship_summary"] = get_internship_summary(db, u)
    return data


@router.get("")
async def get_profile(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)
    return _user_dict(user, db=db)


@router.put("")
async def update_profile(request: Request, db: DbSession, data: ProfileUpdatePayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    payload = await get_payload(request, data)
    if "name" in payload and payload["name"] is not None:
        name = str(payload["name"]).strip()
        if not name:
            raise HTTPException(status_code=422, detail="Name is required.")
        user.name = name

    if "email" in payload and payload["email"] is not None:
        email = str(payload["email"]).strip().lower()
        if not email:
            raise HTTPException(status_code=422, detail="Email is required.")
        existing = db.query(User).filter(User.email == email, User.id != user.id).first()
        if existing:
            raise HTTPException(status_code=409, detail="That email is already in use.")
        user.email = email

    if "bio" in payload:
        user.bio = str(payload["bio"]).strip() or None if payload["bio"] is not None else None
    if "department" in payload:
        user.department = str(payload["department"]).strip() or None if payload["department"] is not None else None
    if "phone" in payload:
        user.phone = str(payload["phone"]).strip() or None if payload["phone"] is not None else None
    if "job_title" in payload:
        user.job_title = str(payload["job_title"]).strip() or None if payload["job_title"] is not None else None
    if "skills" in payload and payload["skills"] is not None:
        skills = payload["skills"]
        if isinstance(skills, list):
            user.skills = ", ".join(str(s).strip() for s in skills if str(s).strip())
        else:
            user.skills = str(skills).strip() or None

    record_audit(db, user, "profile.update", "updated their profile", user.name)
    db.commit()
    return _user_dict(user)


@router.post("/change-password")
async def change_password(request: Request, response: Response, db: DbSession, data: ChangePasswordPayload | None = Body(None)):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    payload = await get_payload(request, data)
    current_pw = str(payload.get("current_password", ""))
    new_pw = str(payload.get("new_password", ""))
    confirm_pw = str(payload.get("confirm_password", ""))

    if not current_pw or not new_pw:
        raise HTTPException(status_code=422, detail="Both current and new password are required.")
    if not user.check_password(current_pw):
        raise HTTPException(status_code=422, detail="Current password is incorrect.")
    if new_pw != confirm_pw:
        raise HTTPException(status_code=422, detail="New passwords do not match.")
    if len(new_pw) < 8:
        raise HTTPException(status_code=422, detail="New password must be at least 8 characters.")
    if not any(c.isdigit() for c in new_pw):
        raise HTTPException(status_code=422, detail="New password must contain at least one number.")

    user.set_password(new_pw)
    user.session_version += 1
    record_audit(db, user, "user.change_password", "changed their password", user.name)
    db.commit()

    token_str = get_token_from_header(request) or request.cookies.get(SESSION_COOKIE_NAME)
    token_data = verify_token(token_str) if token_str else None
    remember = token_data.get("remember", False) if token_data else False
    new_token = generate_token(user.id, user.session_version, remember=remember)
    issue_session_cookies(request, response, new_token, remember=remember)
    return {"ok": True, "token": new_token, "message": "Password changed successfully."}
