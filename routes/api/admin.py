"""JSON admin endpoints."""
import secrets
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response
from sqlalchemy import or_
from sqlalchemy.orm import Session

from config import Config
from database import get_db
from dependencies import get_optional_user, generate_token, issue_session_cookies
from models import InternInviteLink, LeaveRequest, Project, ProjectAssignment, User, UserRole, BinItem, _utcnow
from recycle_bin import (
    bin_item_dict,
    move_to_bin,
    permanently_delete_entity,
    purge_all_bin_items,
    purge_expired_bin_items,
    restore_bin_item,
)
from models import BinEntityType
from utils import clear_all_database_data, push_notification, record_audit, isoformat_utc

from routes.api.schemas import (
    AdminCreateUserRequest,
    AdminUpdateUserRequest,
    AdminRoleUpdateRequest,
    AdminInviteLinkCreateRequest,
    AdminInviteLinkActionRequest,
    ClearDataRequest,
    get_payload,
)

router = APIRouter(prefix="/api/admin", tags=["Administration"])
DbSession = Annotated[Session, Depends(get_db)]


def _mentor_names(db: Session) -> dict[int, str]:
    return {
        m.id: m.name
        for m in db.query(User).filter(User.role == UserRole.MENTOR).all()
    }


def _user_dict(u: User, mentor_names: dict[int, str] | None = None) -> dict:
    data = {
        "id": u.id,
        "name": u.name,
        "email": u.email,
        "role": u.role,
        "is_active": u.is_active,
        "bio": u.bio,
        "department": u.department,
        "phone": u.phone,
        "job_title": u.job_title,
        "joining_date": u.joining_date.isoformat() if u.joining_date else None,
        "skills": u.skills_list(),
        "created_at": isoformat_utc(u.created_at),
        "mentor_id": u.mentor_id,
        "mentor_name": mentor_names.get(u.mentor_id) if mentor_names and u.mentor_id else None,
    }
    return data


def _intern_brief(u: User, mentor_names: dict[int, str] | None = None) -> dict:
    return {
        "id": u.id,
        "name": u.name,
        "email": u.email,
        "department": u.department,
        "is_active": u.is_active,
        "mentor_id": u.mentor_id,
        "mentor_name": mentor_names.get(u.mentor_id) if mentor_names and u.mentor_id else None,
    }


@router.get("/users")
async def list_users(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    role_filter = request.query_params.get("role")
    search_query = request.query_params.get("search", "").strip()

    try:
        page = int(request.query_params.get("page", 1))
        page_size = int(request.query_params.get("page_size", 15))
        if page < 1:
            page = 1
        if page_size < 1:
            page_size = 15
    except ValueError:
        page = 1
        page_size = 15

    is_mentor = user.role == "mentor"

    base_q = db.query(User).filter(User.is_deleted == False)
    if is_mentor:
        base_q = base_q.filter(User.role == UserRole.INTERN, User.mentor_id == user.id)

    # Calculate count summaries
    total_all = base_q.count()
    total_interns = base_q.filter(User.role == UserRole.INTERN).count()
    total_mentors = base_q.filter(User.role == UserRole.MENTOR).count()

    q = base_q
    if role_filter and role_filter != "all":
        q = q.filter(User.role == role_filter)

    if search_query:
        search_pattern = f"%{search_query}%"
        q = q.filter(
            or_(
                User.name.like(search_pattern),
                User.email.like(search_pattern)
            )
        )

    total = q.count()
    import math
    total_pages = math.ceil(total / page_size) if total > 0 else 1

    paginated_users = (
        q.order_by(User.role, User.name)
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    mentor_names = _mentor_names(db)

    return {
        "users": [_user_dict(u, mentor_names) for u in paginated_users],
        "page": page,
        "total_pages": total_pages,
        "total": total,
        "counts": {
            "all": total_all,
            "intern": total_interns,
            "mentor": total_mentors
        }
    }


@router.get("/mentors")
async def list_mentors(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    mentors = db.query(User).filter(User.role == UserRole.MENTOR, User.is_deleted == False).order_by(User.name).all()
    mentor_names = _mentor_names(db)
    return [_user_dict(m, mentor_names) for m in mentors]


@router.get("/intern-assignments")
async def intern_assignments(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    mentor_names = _mentor_names(db)
    interns = (
        db.query(User)
        .filter(User.role == UserRole.INTERN)
        .order_by(User.name)
        .all()
    )
    mentors = (
        db.query(User)
        .filter(User.role == UserRole.MENTOR)
        .order_by(User.name)
        .all()
    )

    # Interns on board but not staffed on any (non-deleted) project — a separate signal
    # from mentor assignment above: an intern can have a mentor and still have zero
    # project work, which is what this is meant to surface.
    interns_with_a_project = {
        r[0]
        for r in db.query(ProjectAssignment.user_id)
        .join(Project, ProjectAssignment.project_id == Project.id)
        .filter(Project.is_deleted == False)
        .distinct()
        .all()
    }

    if user.role == "mentor":
        my_interns = [i for i in interns if i.mentor_id == user.id]
        my_no_project = [i for i in my_interns if i.id not in interns_with_a_project]
        return {
            "total_interns": len(my_interns),
            "assigned_count": len(my_interns),
            "unassigned_count": 0,
            "unassigned": [],
            "no_project_count": len(my_no_project),
            "no_project": [_intern_brief(i, mentor_names) for i in my_no_project],
            "by_mentor": [
                {
                    "mentor": _user_dict(user, mentor_names),
                    "interns": [_intern_brief(i, mentor_names) for i in my_interns],
                    "count": len(my_interns),
                }
            ],
            "scope": "mentor",
        }

    unassigned = [i for i in interns if not i.mentor_id]
    no_project = [i for i in interns if i.id not in interns_with_a_project]
    by_mentor = []
    for mentor in mentors:
        mentees = [i for i in interns if i.mentor_id == mentor.id]
        by_mentor.append(
            {
                "mentor": _user_dict(mentor, mentor_names),
                "interns": [_intern_brief(i, mentor_names) for i in mentees],
                "count": len(mentees),
            }
        )

    return {
        "total_interns": len(interns),
        "assigned_count": len(interns) - len(unassigned),
        "unassigned_count": len(unassigned),
        "unassigned": [_intern_brief(i, mentor_names) for i in unassigned],
        "no_project_count": len(no_project),
        "no_project": [_intern_brief(i, mentor_names) for i in no_project],
        "by_mentor": by_mentor,
        "scope": "admin",
    }


@router.post("/users")
async def create_user(request: Request, db: DbSession, data: AdminCreateUserRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    payload = await get_payload(request, data)
    name = str(payload.get("name", "")).strip()
    email = str(payload.get("email", "")).strip().lower()
    password = str(payload.get("password", ""))
    role = str(payload.get("role", "intern"))
    phone = str(payload.get("phone", "")).strip()
    job_title = str(payload.get("job_title", "")).strip()
    department = str(payload.get("department", "")).strip()

    if not name or not email or not password:
        raise HTTPException(status_code=422, detail="Name, email, and password are required.")
    if len(password) < 8:
        raise HTTPException(status_code=422, detail="Password must be at least 8 characters.")
    if role not in UserRole.ALL:
        raise HTTPException(status_code=422, detail="Invalid role.")
    # Mentors can only create interns
    if user.is_mentor and role != UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentors can only create intern accounts.")
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=409, detail="Email already registered.")

    mentor_id = payload.get("mentor_id")
    resolved_mentor_id: int | None = None
    if role == UserRole.INTERN and mentor_id not in (None, "", 0, "0"):
        resolved_mentor_id = int(mentor_id)
        # Mentors can only assign interns to themselves
        if user.is_mentor and resolved_mentor_id != user.id:
            raise HTTPException(status_code=403, detail="Mentors can only assign interns to themselves.")
        mentor_user = db.get(User, resolved_mentor_id)
        if not mentor_user or mentor_user.role != UserRole.MENTOR:
            raise HTTPException(status_code=422, detail="Invalid mentor selected.")
    elif role == UserRole.INTERN and user.is_mentor:
        resolved_mentor_id = user.id

    new_user = User(
        name=name,
        email=email,
        role=role,
        is_active=True,
        activated_at=_utcnow(),
        phone=phone or None,
        job_title=job_title or None,
        department=department or None,
        mentor_id=resolved_mentor_id,
    )
    new_user.set_password(password)
    new_user.session_version = 1
    db.add(new_user)
    db.flush()  # assign new_user.id so the audit row references it
    record_audit(db, user, "user.create", f"created {role} account for", name, affected_user_id=new_user.id)
    db.commit()
    db.refresh(new_user)
    mentor_names = _mentor_names(db)
    return _user_dict(new_user, mentor_names)


@router.put("/users/{user_id}")
async def update_user(user_id: int, request: Request, response: Response, db: DbSession, data: AdminUpdateUserRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404)
    # Mentors can only edit their own directly assigned interns
    if user.is_mentor and (target.role != UserRole.INTERN or target.mentor_id != user.id):
        raise HTTPException(status_code=403, detail="Mentors can only edit their own assigned interns.")

    payload = await get_payload(request, data)
    if "name" in payload and payload["name"] is not None:
        target.name = str(payload["name"]).strip()
    if "email" in payload and payload["email"] is not None:
        new_email = str(payload["email"]).strip().lower()
        existing = db.query(User).filter(User.email == new_email, User.id != user_id).first()
        if existing:
            raise HTTPException(status_code=409, detail="Email already in use.")
        target.email = new_email
    if "phone" in payload:
        target.phone = str(payload["phone"]).strip() or None if payload["phone"] is not None else None
    if "job_title" in payload:
        target.job_title = str(payload["job_title"]).strip() or None if payload["job_title"] is not None else None
    if "department" in payload:
        target.department = str(payload["department"]).strip() or None if payload["department"] is not None else None
    if "joining_date" in payload and payload["joining_date"] is not None:
        raw_joining_date = payload["joining_date"]
        if raw_joining_date:
            try:
                target.joining_date = date.fromisoformat(str(raw_joining_date).strip())
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid joining date format. Use YYYY-MM-DD.")
        else:
            target.joining_date = None
    if user.role in ("admin", "mentor") and "mentor_id" in payload and payload["mentor_id"] is not None and target.role == UserRole.INTERN:
        raw_mentor = payload["mentor_id"]
        if raw_mentor in (None, "", 0, "0"):
            target.mentor_id = None
        else:
            mentor_id = int(raw_mentor)
            mentor_user = db.get(User, mentor_id)
            if not mentor_user or mentor_user.role != UserRole.MENTOR:
                raise HTTPException(status_code=422, detail="Invalid mentor selected.")
            if user.is_mentor and mentor_id != user.id:
                raise HTTPException(status_code=403, detail="Mentors can only assign interns to themselves.")
            target.mentor_id = mentor_id

    record_audit(db, user, "user.update", "updated account for", target.name, affected_user_id=target.id)
    db.commit()
    mentor_names = _mentor_names(db)
    return _user_dict(target, mentor_names)


@router.post("/users/{user_id}/toggle")
async def toggle_active(user_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404)
    if target.id == user.id:
        raise HTTPException(status_code=400, detail="Cannot deactivate yourself.")
    # Mentors can only toggle their own directly assigned interns
    if user.is_mentor and (target.role != UserRole.INTERN or target.mentor_id != user.id):
        raise HTTPException(status_code=403, detail="Mentors can only activate/deactivate their own assigned interns.")
    target.is_active = not target.is_active
    if target.is_active:
        if target.activated_at is None:
            target.activated_at = _utcnow()
        push_notification(db, target.id, "Your account has been activated.")
    action = "activated" if target.is_active else "deactivated"
    record_audit(db, user, f"user.{action}", f"{action} account", target.name, affected_user_id=target.id)
    db.commit()
    mentor_names = _mentor_names(db)
    return _user_dict(target, mentor_names)


@router.post("/users/{user_id}/role")
async def change_role(user_id: int, request: Request, db: DbSession, data: AdminRoleUpdateRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404)
    if target.id == user.id:
        raise HTTPException(status_code=400, detail="Cannot change your own role.")
    payload = await get_payload(request, data)
    new_role = str(payload.get("role", ""))
    if new_role not in UserRole.ALL:
        raise HTTPException(status_code=422, detail="Invalid role.")
    old_role = target.role
    target.role = new_role
    push_notification(db, target.id, f"Your role was changed from {old_role} to {new_role} by an admin.")
    record_audit(db, user, "user.role_change", f"changed role of {target.name}", f"{old_role} → {new_role}", affected_user_id=target.id)
    db.commit()
    mentor_names = _mentor_names(db)
    return _user_dict(target, mentor_names)


@router.delete("/users/{user_id}")
async def delete_user(user_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)
    target = db.get(User, user_id)
    if not target or target.is_deleted:
        raise HTTPException(status_code=404)
    if target.id == user.id:
        raise HTTPException(status_code=400, detail="Cannot delete yourself.")
    name = target.name
    record_audit(db, user, "user.delete", "deleted account", name, affected_user_id=user_id)
    move_to_bin(db, user, BinEntityType.USER, target, title=name)
    db.commit()
    return {"ok": True}


def _invite_link_dict(link: InternInviteLink, db: Session, request: Request | None = None) -> dict:
    mentor_name = None
    if link.mentor_id:
        mentor = db.get(User, link.mentor_id)
        mentor_name = mentor.name if mentor else None
    creator_name = None
    if link.created_by_id:
        creator = db.get(User, link.created_by_id)
        creator_name = creator.name if creator else None

    base_url = Config.PUBLIC_SITE_URL
    if not base_url and request:
        proto = request.headers.get("x-forwarded-proto", request.url.scheme)
        host = request.headers.get("x-forwarded-host", request.headers.get("host", ""))
        if host:
            base_url = f"{proto}://{host}".rstrip("/")
        else:
            base_url = str(request.base_url).rstrip("/")

    join_url = f"{base_url}/join/{link.token}" if base_url else f"/join/{link.token}"

    return {
        "id": link.id,
        "token": link.token,
        "label": link.label,
        "mentor_id": link.mentor_id,
        "mentor_name": mentor_name,
        "is_active": link.is_active,
        "usage_count": link.usage_count,
        "created_by_id": link.created_by_id,
        "created_by_name": creator_name,
        "created_at": isoformat_utc(link.created_at),
        "url": join_url,
    }


@router.get("/invite-link")
async def get_invite_link(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)
    query = db.query(InternInviteLink)
    if user.is_mentor:
        query = query.filter(InternInviteLink.created_by_id == user.id)
    links = query.order_by(InternInviteLink.created_at.desc()).all()
    if not links:
        return {"link": None, "links": []}
    return {
        "link": _invite_link_dict(links[0], db, request),
        "links": [_invite_link_dict(link, db, request) for link in links],
    }


@router.post("/invite-link")
async def create_invite_link(request: Request, db: DbSession, data: AdminInviteLinkCreateRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    payload = await get_payload(request, data)
    label = str(payload.get("label", "")).strip() or "Intern onboarding link"
    mentor_id = payload.get("mentor_id")
    resolved_mentor_id: int | None = None
    if user.is_mentor:
        resolved_mentor_id = user.id
    elif mentor_id not in (None, "", 0, "0", "none"):
        try:
            resolved_mentor_id = int(mentor_id)
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="Invalid mentor selected.")
        mentor_user = db.get(User, resolved_mentor_id)
        if not mentor_user or mentor_user.role != UserRole.MENTOR:
            raise HTTPException(status_code=422, detail="Invalid mentor selected.")

    link = InternInviteLink(
        token=secrets.token_urlsafe(32),
        label=label,
        created_by_id=user.id,
        mentor_id=resolved_mentor_id,
        is_active=True,
    )
    db.add(link)
    record_audit(db, user, "invite.create", "created intern invite link", label)
    db.commit()
    db.refresh(link)
    return {"link": _invite_link_dict(link, db, request)}


@router.delete("/invite-link/{link_id}")
async def delete_invite_link(link_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    link = db.get(InternInviteLink, link_id)
    if not link:
        raise HTTPException(status_code=404, detail="Invite link not found.")
    if user.is_mentor and link.created_by_id != user.id:
        raise HTTPException(status_code=403, detail="You can only delete links created by you.")

    label = link.label or link.token
    record_audit(db, user, "invite.delete", "deleted intern invite link", label)
    db.delete(link)
    db.commit()
    return {"ok": True}


def _mentor_link_ids_for_user(db: Session, user: User) -> list[int]:
    """Links a mentor can manage: created by them or assigned to them."""
    rows = (
        db.query(InternInviteLink.id)
        .filter(
            or_(
                InternInviteLink.created_by_id == user.id,
                InternInviteLink.mentor_id == user.id,
            )
        )
        .all()
    )
    return [row[0] for row in rows]


def _can_review_intern_signup(db: Session, reviewer: User, intern: User, org_id: int | None = None) -> bool:
    if not intern.signup_invite_link_id:
        return False
    link = db.get(InternInviteLink, intern.signup_invite_link_id)
    if not link:
        return False
    if reviewer.is_admin:
        if org_id is not None and link.organization_id != org_id:
            return False
        return True
    if reviewer.is_mentor:
        if org_id is not None and link.organization_id != org_id:
            return False
        return link.created_by_id == reviewer.id or link.mentor_id == reviewer.id
    return False


def _intern_signup_request_dict(intern: User, db: Session) -> dict:
    link = db.get(InternInviteLink, intern.signup_invite_link_id) if intern.signup_invite_link_id else None
    mentor_name = None
    if intern.mentor_id:
        mentor = db.get(User, intern.mentor_id)
        mentor_name = mentor.name if mentor else None
    creator_name = None
    if link and link.created_by_id:
        creator = db.get(User, link.created_by_id)
        creator_name = creator.name if creator else None
    return {
        "id": intern.id,
        "name": intern.name,
        "email": intern.email,
        "department": intern.department,
        "phone": intern.phone,
        "job_title": intern.job_title,
        "mentor_id": intern.mentor_id,
        "mentor_name": mentor_name,
        "invite_link_id": intern.signup_invite_link_id,
        "invite_label": link.label if link else None,
        "link_creator_id": link.created_by_id if link else None,
        "link_creator_name": creator_name,
        "created_at": isoformat_utc(intern.created_at),
    }


@router.get("/intern-signup-requests")
async def list_intern_signup_requests(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    query = (
        db.query(User)
        .filter(
            User.role == UserRole.INTERN,
            User.is_active.is_(False),
            User.signup_invite_link_id.isnot(None),
        )
        .order_by(User.created_at.desc())
    )

    if user.is_mentor:
        link_ids = _mentor_link_ids_for_user(db, user)
        if not link_ids:
            return {"requests": [], "total": 0}
        query = query.filter(User.signup_invite_link_id.in_(link_ids))

    interns = query.all()
    return {
        "requests": [_intern_signup_request_dict(i, db) for i in interns],
        "total": len(interns),
    }


@router.post("/intern-signup-requests/{user_id}/review")
async def review_intern_signup_request(user_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role not in ("admin", "mentor"):
        raise HTTPException(status_code=403)

    # Resolve organization context
    org_header = request.headers.get("X-Organization-Id")
    org_id = int(org_header) if org_header and str(org_header).isdigit() else None
    if org_id is None:
        from models import OrganizationMembership
        mem = db.query(OrganizationMembership).filter_by(user_id=user.id, is_active=True, is_deleted=False).first()
        org_id = mem.organization_id if mem else None

    intern = db.get(User, user_id)
    if not intern or intern.role != UserRole.INTERN or intern.is_active:
        raise HTTPException(status_code=404, detail="Signup request not found.")
    if not intern.signup_invite_link_id:
        raise HTTPException(status_code=404, detail="Signup request not found.")
    if not _can_review_intern_signup(db, user, intern, org_id):
        raise HTTPException(status_code=403, detail="You cannot review this signup request.")

    data = await request.json()
    decision = str(data.get("decision", "")).strip().lower()
    if decision not in ("approved", "rejected"):
        raise HTTPException(status_code=422, detail="Decision must be approved or rejected.")

    intern_name = intern.name
    if decision == "approved":
        intern.is_active = True
        if intern.activated_at is None:
            intern.activated_at = _utcnow()
        intern.signup_invite_link_id = None
        push_notification(
            db,
            intern.id,
            "Your intern account was approved. You can now sign in.",
            link="/",
        )
        record_audit(
            db,
            user,
            "user.signup_approve",
            "approved intern signup request",
            intern_name,
            affected_user_id=intern.id,
        )
        db.commit()
        mentor_names = _mentor_names(db)
        return _user_dict(intern, mentor_names)

    record_audit(
        db,
        user,
        "user.signup_reject",
        "rejected intern signup request",
        intern_name,
        affected_user_id=user_id,
    )
    db.delete(intern)
    db.commit()
    return {"ok": True}


@router.post("/invite-link/regenerate")
async def regenerate_invite_link(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)

    current = (
        db.query(InternInviteLink)
        .filter_by(is_active=True)
        .order_by(InternInviteLink.created_at.desc())
        .first()
    )
    label = current.label if current else "Intern onboarding link"
    mentor_id = current.mentor_id if current else None

    # Regenerating invalidates all previously active links
    for old_link in db.query(InternInviteLink).filter_by(is_active=True).all():
        old_link.is_active = False

    link = InternInviteLink(
        token=secrets.token_urlsafe(32),
        label=label,
        created_by_id=user.id,
        mentor_id=mentor_id,
        is_active=True,
    )
    db.add(link)
    record_audit(db, user, "invite.regenerate", "regenerated intern invite link", label)
    db.commit()
    db.refresh(link)
    return {"link": _invite_link_dict(link, db, request)}


@router.post("/invite-link/deactivate")
async def deactivate_invite_link(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)
    updated = 0
    for link in db.query(InternInviteLink).filter_by(is_active=True).all():
        link.is_active = False
        updated += 1
    if updated:
        record_audit(db, user, "invite.deactivate", "deactivated intern invite link", f"{updated} link(s)")
    db.commit()
    return {"ok": True}


@router.get("/bin")
async def list_recycle_bin(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)

    params = request.query_params
    entity_type = params.get("entity_type")
    if entity_type in ("", "null", "undefined", "all"):
        entity_type = None

    try:
        page = max(1, int(params.get("page", 1)))
    except ValueError:
        page = 1
    try:
        page_size = max(1, min(100, int(params.get("page_size", 10))))
    except ValueError:
        page_size = 10

    q = db.query(BinItem).filter(BinItem.restored_at.is_(None))
    if entity_type:
        q = q.filter(BinItem.entity_type == entity_type)

    total = q.count()
    items = (
        q.order_by(BinItem.deleted_at.desc(), BinItem.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    total_pages = max(1, (total + page_size - 1) // page_size) if total else 1
    return {
        "items": [bin_item_dict(item) for item in items],
        "page": page,
        "total_pages": total_pages,
        "total": total,
    }


@router.post("/bin/{bin_id}/restore")
async def restore_recycle_bin_item(bin_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)

    item = db.get(BinItem, bin_id)
    if not item or item.restored_at is not None:
        raise HTTPException(status_code=404, detail="Recycle bin item not found.")

    try:
        entity = restore_bin_item(db, item)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    record_audit(
        db,
        user,
        "bin.restore",
        f"restored {item.entity_type}",
        item.title,
        target_id=item.entity_id,
    )
    db.commit()
    return {
        "ok": True,
        "message": f"Restored {item.entity_type.replace('_', ' ')} '{item.title}'.",
        "entity_type": item.entity_type,
        "entity_id": entity.id,
    }


@router.delete("/bin/{bin_id}")
async def purge_recycle_bin_item(bin_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)

    item = db.get(BinItem, bin_id)
    if not item or item.restored_at is not None:
        raise HTTPException(status_code=404, detail="Recycle bin item not found.")

    permanently_delete_entity(db, item.entity_type, item.entity_id)
    record_audit(
        db,
        user,
        "bin.purge",
        f"permanently deleted {item.entity_type}",
        item.title,
        target_id=item.entity_id,
    )
    db.delete(item)
    db.commit()
    return {"ok": True, "message": f"Permanently deleted '{item.title}'."}


@router.delete("/bin")
async def clear_recycle_bin(request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)

    count = purge_all_bin_items(db)
    if count:
        record_audit(
            db,
            user,
            "bin.clear_all",
            f"permanently deleted all {count} bin item(s)",
            "Recycle Bin",
        )
    db.commit()
    return {"ok": True, "message": f"Permanently deleted {count} item(s).", "deleted_count": count}


@router.post("/clear-database")
async def clear_database(request: Request, db: DbSession, data: ClearDataRequest | None = Body(None)):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Only admins can clear the database.")

    if not getattr(user, "is_platform_admin", False) and not Config.IS_LOCAL:
        raise HTTPException(
            status_code=403,
            detail="Only Platform Super Admins can execute a global database wipe in development.",
        )

    payload = await get_payload(request, data)

    if not Config.DB_CLEAR_PASSWORD:
        raise HTTPException(status_code=503, detail="Database clear is not configured on this server.")
    password = str(payload.get("password", ""))
    if not secrets.compare_digest(password, Config.DB_CLEAR_PASSWORD):
        raise HTTPException(status_code=403, detail="Incorrect database clear password.")

    counts = clear_all_database_data(db)
    total = sum(v for k, v in counts.items() if k != "admins_preserved")
    preserved = counts.get("admins_preserved", 0)
    record_audit(
        db,
        user,
        "database.clear",
        "cleared application data",
        f"{total} row(s)",
        affected_user_id=user.id,
    )
    db.commit()
    return {
        "ok": True,
        "message": (
            f"All database data has been cleared. {preserved} admin account(s) preserved."
            if preserved
            else "All database data has been cleared."
        ),
        "deleted_rows": total,
        "admins_preserved": preserved,
        "tables": counts,
    }
