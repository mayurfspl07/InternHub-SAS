"""JSON auth endpoints for the React frontend."""
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from config import Config
from database import get_db
from dependencies import (
    clear_session_cookies,
    get_optional_user,
    issue_session_cookies,
    login_user,
    logout_user,
)
from models import InternInviteLink, User, UserRole, _utcnow
from utils import check_login_rate_limit, reset_login_attempts, record_audit, push_notification, isoformat_utc

from routes.api.schemas import (
    LoginRequest,
    RegisterRequest,
    InviteRegisterRequest,
    UserProfileResponse,
    get_payload,
)

router = APIRouter(prefix="/api/auth", tags=["Authentication"])

DbSession = Annotated[Session, Depends(get_db)]


def _user_dict(user: User) -> dict:
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "role": user.role,
        "is_platform_admin": user.is_platform_admin,
        "is_superadmin": user.is_superadmin,
        "is_active": user.is_active,
        "bio": user.bio,
        "department": user.department,
        "skills": user.skills_list(),
        "phone": user.phone,
        "job_title": user.job_title,
        "joining_date": user.joining_date.isoformat() if user.joining_date else None,
        "created_at": isoformat_utc(user.created_at),
        "session_version": user.session_version,
    }


@router.get("/me")
async def me(request: Request, db: DbSession):
    """Return the currently authenticated user or 401."""
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return _user_dict(user)


@router.post("/login")
async def login(request: Request, response: Response, db: DbSession, data: LoginRequest | None = Body(None)):
    payload = await get_payload(request, data)
    email = str(payload.get("email", "")).strip().lower()
    password = str(payload.get("password", ""))
    remember = bool(payload.get("remember", False))

    client_ip = request.client.host if request.client else "unknown"
    if not check_login_rate_limit(client_ip, Config.LOGIN_MAX_ATTEMPTS, Config.LOGIN_WINDOW_SECONDS):
        raise HTTPException(
            status_code=429,
            detail="Too many login attempts. Please wait 5 minutes.",
            headers={"Retry-After": str(Config.LOGIN_WINDOW_SECONDS)},
        )

    # Soft-deleted accounts must look exactly like "no such account" — an admin deleting
    # someone shouldn't leak account state (active/pending/deactivated) to that person.
    found = db.query(User).filter_by(email=email).first()
    if not found or found.is_deleted or not found.check_password(password):
        raise HTTPException(status_code=401, detail="Invalid email or password.")
    if not found.is_active:
        # activated_at is set the first time an account is ever activated and never
        # cleared again — None means it's never been approved yet; set means it was
        # active before and has since been deactivated by an admin/mentor.
        pending = found.activated_at is None
        if found.role == UserRole.MENTOR:
            detail = (
                "Your mentor account is pending admin approval."
                if pending
                else "Your account is deactivated. Please contact the admin."
            )
        elif found.role == UserRole.INTERN:
            detail = (
                "Your account is pending mentor approval."
                if pending
                else "Your account is deactivated. Please contact your mentor."
            )
        else:
            detail = "Your account is deactivated. Please contact an admin."
        raise HTTPException(status_code=403, detail=detail)

    reset_login_attempts(client_ip)
    token = login_user(request, found, remember=remember)
    issue_session_cookies(request, response, token, remember)
    # Also returned in the body for cross-origin frontend deployments (VITE_API_BASE
    # set), where the HttpOnly session cookie can't be relied on — SameSite=Lax cookies
    # aren't sent on the next cross-site request. Those clients send this back as
    # `Authorization: Bearer <token>`, which get_optional_user already prefers over the
    # cookie and which the CSRF guard in main.py already exempts.
    return {"user": _user_dict(found), "ok": True, "token": token}


@router.post("/logout")
async def logout(request: Request, response: Response):
    logout_user(request)
    clear_session_cookies(request, response)
    return {"ok": True}


@router.post("/register")
async def register(request: Request, db: DbSession, data: RegisterRequest | None = Body(None)):
    client_ip = request.client.host if request.client else "unknown"
    if not check_login_rate_limit(client_ip, Config.LOGIN_MAX_ATTEMPTS, Config.LOGIN_WINDOW_SECONDS):
        raise HTTPException(
            status_code=429,
            detail="Too many requests. Please wait 5 minutes.",
            headers={"Retry-After": str(Config.LOGIN_WINDOW_SECONDS)},
        )

    payload = await get_payload(request, data)
    name = str(payload.get("name", "")).strip()
    email = str(payload.get("email", "")).strip().lower()
    password = str(payload.get("password", ""))
    confirm = str(payload.get("confirm_password", payload.get("confirm", "")))
    role = str(payload.get("role", UserRole.INTERN)).strip().lower()

    errors = []
    if not (name and email and password):
        errors.append("All fields are required.")
    if role not in (UserRole.MENTOR, UserRole.INTERN):
        errors.append("Invalid role selection.")
    if password != confirm:
        errors.append("Passwords do not match.")
    if len(password) < 8:
        errors.append("Password must be at least 8 characters.")
    if not any(c.isdigit() for c in password):
        errors.append("Password must contain at least one number.")
    if errors:
        raise HTTPException(status_code=422, detail="; ".join(errors))

    if db.query(User).filter_by(email=email).first():
        # Generic message to prevent email enumeration
        raise HTTPException(status_code=409, detail="An account with that email already exists.")

    is_mentor_signup = role == UserRole.MENTOR
    # Mentor signups require admin activation before first login.
    new_user = User(
        name=name,
        email=email,
        role=role,
        is_active=not is_mentor_signup,
        activated_at=None if is_mentor_signup else _utcnow(),
    )
    new_user.set_password(password)
    new_user.session_version = 1
    db.add(new_user)
    db.flush()  # assign new_user.id for the audit row
    audit_action = "user.register_mentor_pending" if is_mentor_signup else "user.register"
    audit_verb = "registered mentor account (pending approval)" if is_mentor_signup else "registered account"
    record_audit(db, new_user, audit_action, audit_verb, new_user.name)
    db.commit()
    db.refresh(new_user)
    message = (
        "Mentor account created and sent for admin approval. You can sign in after approval."
        if is_mentor_signup
        else "Registration successful — you can now log in."
    )
    return {"ok": True, "message": message, "user": _user_dict(new_user)}


def _get_active_invite(db: Session, token: str) -> InternInviteLink | None:
    return (
        db.query(InternInviteLink)
        .filter_by(token=token.strip(), is_active=True)
        .first()
    )


@router.get("/invite/{token}")
async def get_invite_info(token: str, db: DbSession):
    link = _get_active_invite(db, token)
    if not link:
        raise HTTPException(status_code=404, detail="This invite link is invalid or has expired.")
    mentor_name = None
    if link.mentor_id:
        mentor = db.get(User, link.mentor_id)
        mentor_name = mentor.name if mentor else None
    return {
        "valid": True,
        "label": link.label,
        "mentor_name": mentor_name,
    }


@router.post("/invite/{token}/register")
async def register_via_invite(token: str, request: Request, db: DbSession, data: InviteRegisterRequest | None = Body(None)):
    link = _get_active_invite(db, token)
    if not link:
        raise HTTPException(status_code=404, detail="This invite link is invalid or has expired.")

    payload = await get_payload(request, data)
    name = str(payload.get("name", "")).strip()
    email = str(payload.get("email", "")).strip().lower()
    password = str(payload.get("password", ""))
    confirm = str(payload.get("confirm_password", payload.get("confirm", "")))
    phone = str(payload.get("phone", "")).strip()
    department = str(payload.get("department", "")).strip()
    job_title = str(payload.get("job_title", "")).strip()
    joining_date_str = str(payload.get("joining_date", "")).strip().strip()

    errors = []
    if not (name and email and password and phone and department and job_title and joining_date_str):
        errors.append(
            "Full name, email, department, job title, phone number, joining date, and password are required."
        )
    if password != confirm:
        errors.append("Passwords do not match.")
    if len(password) < 8:
        errors.append("Password must be at least 8 characters.")
    if not any(c.isdigit() for c in password):
        errors.append("Password must contain at least one number.")
    joining_date_value = None
    if joining_date_str:
        try:
            joining_date_value = date.fromisoformat(joining_date_str)
        except ValueError:
            errors.append("Invalid joining date format. Use YYYY-MM-DD.")
    if errors:
        raise HTTPException(status_code=422, detail="; ".join(errors))

    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=409, detail="Email is already registered.")

    mentor_id = link.mentor_id
    if mentor_id:
        mentor = db.get(User, mentor_id)
        if not mentor or mentor.role != UserRole.MENTOR or not mentor.is_active:
            mentor_id = None

    new_user = User(
        name=name,
        email=email,
        role=UserRole.INTERN,
        is_active=False,
        phone=phone or None,
        department=department or None,
        job_title=job_title or None,
        joining_date=joining_date_value,
        mentor_id=mentor_id,
        signup_invite_link_id=link.id,
    )
    new_user.set_password(password)
    new_user.session_version = 1
    db.add(new_user)
    link.usage_count = (link.usage_count or 0) + 1
    db.commit()
    db.refresh(new_user)

    creator = db.get(User, link.created_by_id) if link.created_by_id else None
    record_audit(
        db,
        creator or new_user,
        "user.register_invite_pending",
        "submitted intern signup via invite link (pending approval)",
        new_user.name,
        affected_user_id=new_user.id,
    )

    notify_ids: set[int] = set()
    if link.created_by_id:
        creator_user = db.get(User, link.created_by_id)
        if creator_user and creator_user.role == UserRole.MENTOR and creator_user.is_active:
            notify_ids.add(creator_user.id)
    if mentor_id and mentor_id not in notify_ids:
        notify_ids.add(mentor_id)

    for reviewer_id in notify_ids:
        push_notification(
            db,
            reviewer_id,
            f"{new_user.name} requested an intern account via your invite link. Review and approve or reject.",
            link="/invite-links",
        )

    assigned_mentor = db.get(User, mentor_id) if mentor_id else None
    mentor_label = assigned_mentor.name if assigned_mentor else "Unassigned"

    for admin in db.query(User).filter(User.role.in_([UserRole.ADMIN, UserRole.SUPERADMIN]), User.is_active.is_(True)).all():
        push_notification(
            db,
            admin.id,
            f"New intern signup request from {new_user.name} (mentor: {mentor_label}).",
            link="/invite-links",
        )

    db.commit()

    return {
        "ok": True,
        "pending_approval": True,
        "message": "Your account request was submitted. You can sign in after your mentor approves it.",
    }
