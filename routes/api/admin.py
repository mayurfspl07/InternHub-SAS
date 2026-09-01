"""JSON admin endpoints."""
import secrets
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, Response
from sqlalchemy import or_
from sqlalchemy.orm import Session

from config import Config
from database import get_db
from dependencies import get_optional_user, generate_token, issue_session_cookies
from models import (
    InternInviteLink,
    LeaveRequest,
    Project,
    ProjectAssignment,
    ProjectStatusBucket,
    InternshipDurationMaster,
    Task,
    TaskStatusBucket,
    TaskStatusCategory,
    User,
    UserRole,
    BinItem,
    _utcnow,
)
from recycle_bin import (
    bin_item_dict,
    move_to_bin,
    permanently_delete_entity,
    purge_all_bin_items,
    purge_expired_bin_items,
    restore_bin_item,
)
from models import BinEntityType
from utils import (
    clear_all_database_data,
    get_or_seed_org_task_statuses,
    get_or_seed_org_project_statuses,
    get_or_seed_org_internship_durations,
    push_notification,
    record_audit,
    isoformat_utc,
    slugify_status_name,
)

from routes.api.schemas import (
    AdminCreateUserRequest,
    AdminUpdateUserRequest,
    AdminRoleUpdateRequest,
    AdminInviteLinkCreateRequest,
    AdminInviteLinkActionRequest,
    ClearDataRequest,
    TaskStatusBucketCreatePayload,
    TaskStatusBucketUpdatePayload,
    TaskStatusBucketReorderPayload,
    ProjectStatusBucketCreatePayload,
    ProjectStatusBucketUpdatePayload,
    ProjectStatusBucketReorderPayload,
    InternshipDurationCreatePayload,
    InternshipDurationUpdatePayload,
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
async def list_intern_signup_requests(
    request: Request,
    db: DbSession,
    page: int = 1,
    page_size: int = 20,
    search: str | None = None,
):
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
    )

    p = _clean_param_int(page, 1)
    ps = _clean_param_int(page_size, 20)
    s = _clean_param_str(search)

    if user.is_mentor:
        link_ids = _mentor_link_ids_for_user(db, user)
        if not link_ids:
            return {
                "requests": [],
                "items": [],
                "total": 0,
                "page": p,
                "page_size": ps,
                "total_pages": 1,
            }
        query = query.filter(User.signup_invite_link_id.in_(link_ids))

    if s:
        search_pattern = f"%{s}%"
        query = query.filter(or_(User.name.ilike(search_pattern), User.email.ilike(search_pattern)))

    total = query.count()
    total_pages = max(1, (total + ps - 1) // ps) if total else 1
    interns = (
        query.order_by(User.created_at.desc())
        .offset((p - 1) * ps)
        .limit(ps)
        .all()
    )
    items = [_intern_signup_request_dict(i, db) for i in interns]
    return {
        "requests": items,
        "items": items,
        "total": total,
        "page": p,
        "page_size": ps,
        "total_pages": total_pages,
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


def _resolve_admin_org_id(request: Request, user: User, db: Session) -> int:
    org_header = request.headers.get("X-Organization-Id") or request.query_params.get("organization_id")
    if org_header and str(org_header).isdigit():
        return int(org_header)
    from models import OrganizationMembership
    mem = db.query(OrganizationMembership).filter_by(user_id=user.id, is_active=True, is_deleted=False).first()
    if mem and mem.organization_id:
        return mem.organization_id
    return 1


def _clean_param_int(val, default: int = 1) -> int:
    if hasattr(val, "default"):
        val = val.default
    try:
        return max(1, int(val))
    except (TypeError, ValueError):
        return default


def _clean_param_str(val) -> str | None:
    if hasattr(val, "default"):
        val = val.default
    if val is None:
        return None
    s = str(val).strip()
    return s if s else None


@router.get("/task-statuses")
async def list_task_statuses(
    request: Request,
    db: DbSession,
    page: int = 1,
    page_size: int = 20,
    search: str | None = None,
    category: str | None = None,
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")
    
    org_id = _resolve_admin_org_id(request, user, db)
    buckets = get_or_seed_org_task_statuses(db, org_id)

    from sqlalchemy import func
    task_counts_rows = (
        db.query(Task.status, func.count(Task.id))
        .filter(Task.organization_id == org_id, Task.is_deleted == False)
        .group_by(Task.status)
        .all()
    )
    task_counts = {status: count for status, count in task_counts_rows}

    p = _clean_param_int(page, 1)
    ps = _clean_param_int(page_size, 20)
    s = _clean_param_str(search)
    cat = _clean_param_str(category)

    filtered_buckets = buckets
    if cat:
        cat_lower = cat.lower()
        filtered_buckets = [b for b in filtered_buckets if b.status_category.lower() == cat_lower]
    if s:
        s_lower = s.lower()
        filtered_buckets = [
            b for b in filtered_buckets
            if s_lower in b.name.lower() or s_lower in b.slug.lower() or (getattr(b, "description", None) and s_lower in b.description.lower())
        ]

    total = len(filtered_buckets)
    total_pages = max(1, (total + ps - 1) // ps) if total else 1
    paginated_items = [
        b.to_dict(task_count=task_counts.get(b.slug, 0))
        for b in filtered_buckets[(p - 1) * ps : p * ps]
    ]

    return {
        "statuses": paginated_items,
        "items": paginated_items,
        "total": total,
        "page": p,
        "page_size": ps,
        "total_pages": total_pages,
    }


@router.post("/task-statuses")
async def create_task_status(
    request: Request,
    db: DbSession,
    data: TaskStatusBucketCreatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    payload = await get_payload(request, data)

    name = str(payload.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=422, detail="Status bucket name is required.")

    slug_raw = payload.get("slug")
    slug = str(slug_raw).strip() if slug_raw else slugify_status_name(name)
    if not slug:
        slug = slugify_status_name(name)

    existing_slug = (
        db.query(TaskStatusBucket)
        .filter_by(organization_id=org_id, slug=slug)
        .first()
    )
    if existing_slug:
        raise HTTPException(
            status_code=422,
            detail=f"A status bucket with key '{slug}' already exists in this organization.",
        )

    existing_name = (
        db.query(TaskStatusBucket)
        .filter_by(organization_id=org_id, name=name)
        .first()
    )
    if existing_name:
        raise HTTPException(
            status_code=422,
            detail=f"A status bucket named '{name}' already exists in this organization.",
        )

    category = str(payload.get("status_category", TaskStatusCategory.IN_PROGRESS)).strip().lower()
    if category not in TaskStatusCategory.ALL:
        category = TaskStatusCategory.IN_PROGRESS

    is_default = bool(payload.get("is_default", False))
    if is_default:
        db.query(TaskStatusBucket).filter_by(organization_id=org_id).update(
            {TaskStatusBucket.is_default: False}
        )

    from sqlalchemy import func
    order_index = payload.get("order_index")
    if order_index is None:
        max_order = (
            db.query(func.max(TaskStatusBucket.order_index))
            .filter_by(organization_id=org_id)
            .scalar()
        )
        order_index = (max_order + 1) if max_order is not None else 0
    else:
        try:
            order_index = int(order_index)
        except (TypeError, ValueError):
            order_index = 0

    color = str(payload.get("color", "#6366F1")).strip() or "#6366F1"

    bucket = TaskStatusBucket(
        organization_id=org_id,
        name=name,
        slug=slug,
        color=color,
        order_index=order_index,
        status_category=category,
        is_default=is_default,
        is_system=False,
    )
    db.add(bucket)
    db.commit()
    db.refresh(bucket)

    record_audit(
        db,
        user,
        "task_status.create",
        "created task status bucket",
        name,
        target_id=bucket.id,
    )

    return bucket.to_dict(task_count=0)


@router.put("/task-statuses/reorder")
async def reorder_task_statuses(
    request: Request,
    db: DbSession,
    data: TaskStatusBucketReorderPayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    payload = await get_payload(request, data)
    status_ids = payload.get("status_ids")
    if not isinstance(status_ids, list):
        raise HTTPException(status_code=422, detail="status_ids list is required.")

    for index, sid in enumerate(status_ids):
        try:
            s_id = int(sid)
        except (TypeError, ValueError):
            continue
        db.query(TaskStatusBucket).filter_by(id=s_id, organization_id=org_id).update(
            {TaskStatusBucket.order_index: index}
        )
    db.commit()

    buckets = (
        db.query(TaskStatusBucket)
        .filter_by(organization_id=org_id)
        .order_by(TaskStatusBucket.order_index.asc(), TaskStatusBucket.id.asc())
        .all()
    )
    return {"statuses": [b.to_dict() for b in buckets]}


@router.put("/task-statuses/{status_id}")
async def update_task_status(
    status_id: int,
    request: Request,
    db: DbSession,
    data: TaskStatusBucketUpdatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    bucket = db.query(TaskStatusBucket).filter_by(id=status_id, organization_id=org_id).first()
    if not bucket:
        raise HTTPException(status_code=404, detail="Status bucket not found.")

    payload = await get_payload(request, data)

    if "name" in payload and payload["name"] is not None:
        name = str(payload["name"]).strip()
        if not name:
            raise HTTPException(status_code=422, detail="Name cannot be empty.")
        existing_name = (
            db.query(TaskStatusBucket)
            .filter(
                TaskStatusBucket.organization_id == org_id,
                TaskStatusBucket.name == name,
                TaskStatusBucket.id != status_id,
            )
            .first()
        )
        if existing_name:
            raise HTTPException(status_code=422, detail=f"A status bucket named '{name}' already exists.")
        bucket.name = name

    if "color" in payload and payload["color"] is not None:
        bucket.color = str(payload["color"]).strip()

    if "status_category" in payload and payload["status_category"] is not None:
        category = str(payload["status_category"]).strip().lower()
        if category in TaskStatusCategory.ALL:
            bucket.status_category = category

    if "is_default" in payload and payload["is_default"] is not None:
        is_def = bool(payload["is_default"])
        if is_def:
            db.query(TaskStatusBucket).filter(
                TaskStatusBucket.organization_id == org_id,
                TaskStatusBucket.id != status_id,
            ).update({TaskStatusBucket.is_default: False})
            bucket.is_default = True
        else:
            bucket.is_default = False

    if "order_index" in payload and payload["order_index"] is not None:
        try:
            bucket.order_index = int(payload["order_index"])
        except (TypeError, ValueError):
            pass

    db.commit()
    db.refresh(bucket)

    record_audit(
        db,
        user,
        "task_status.update",
        "updated task status bucket",
        bucket.name,
        target_id=bucket.id,
    )
    return bucket.to_dict()


@router.delete("/task-statuses/{status_id}")
async def delete_task_status(status_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    bucket = db.query(TaskStatusBucket).filter_by(id=status_id, organization_id=org_id).first()
    if not bucket:
        raise HTTPException(status_code=404, detail="Status bucket not found.")

    active_tasks_count = (
        db.query(Task)
        .filter(
            Task.organization_id == org_id,
            Task.is_deleted == False,
            Task.status == bucket.slug,
        )
        .count()
    )
    if active_tasks_count > 0:
        raise HTTPException(
            status_code=422,
            detail=f"Cannot delete status bucket '{bucket.name}' because {active_tasks_count} active task(s) are currently assigned to it. Please reassign or move these tasks before deleting.",
        )

    if bucket.is_default:
        other_bucket = (
            db.query(TaskStatusBucket)
            .filter(TaskStatusBucket.organization_id == org_id, TaskStatusBucket.id != bucket.id)
            .first()
        )
        if other_bucket:
            other_bucket.is_default = True
        else:
            raise HTTPException(
                status_code=422,
                detail="Cannot delete the organization's only remaining status bucket.",
            )

    bucket_name = bucket.name
    db.delete(bucket)
    db.commit()

    record_audit(
        db,
        user,
        "task_status.delete",
        "deleted task status bucket",
        bucket_name,
        target_id=status_id,
    )
    return {"success": True, "message": f"Status bucket '{bucket_name}' deleted."}


# ==============================================================================
# Project Status Masters Endpoints
# ==============================================================================
@router.get("/project-statuses")
async def list_project_statuses(
    request: Request,
    db: DbSession,
    page: int = 1,
    page_size: int = 20,
    search: str | None = None,
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    buckets = get_or_seed_org_project_statuses(db, org_id)

    from sqlalchemy import func
    proj_counts_rows = (
        db.query(Project.status, func.count(Project.id))
        .filter(Project.organization_id == org_id, Project.is_deleted == False)
        .group_by(Project.status)
        .all()
    )
    project_counts = {status: count for status, count in proj_counts_rows}

    p = _clean_param_int(page, 1)
    ps = _clean_param_int(page_size, 20)
    s = _clean_param_str(search)

    filtered_buckets = buckets
    if s:
        s_lower = s.lower()
        filtered_buckets = [
            b for b in filtered_buckets
            if s_lower in b.name.lower() or s_lower in b.slug.lower() or (getattr(b, "description", None) and s_lower in b.description.lower())
        ]

    total = len(filtered_buckets)
    total_pages = max(1, (total + ps - 1) // ps) if total else 1
    paginated_items = [
        b.to_dict(project_count=project_counts.get(b.slug, 0))
        for b in filtered_buckets[(p - 1) * ps : p * ps]
    ]

    return {
        "statuses": paginated_items,
        "items": paginated_items,
        "total": total,
        "page": p,
        "page_size": ps,
        "total_pages": total_pages,
    }


@router.post("/project-statuses")
async def create_project_status(
    request: Request,
    db: DbSession,
    data: ProjectStatusBucketCreatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    payload = await get_payload(request, data)

    name = str(payload.get("name", "")).strip()
    if not name:
        raise HTTPException(status_code=422, detail="Project status bucket name is required.")

    slug_raw = payload.get("slug")
    slug = str(slug_raw).strip() if slug_raw else slugify_status_name(name)
    if not slug:
        slug = slugify_status_name(name)

    existing_slug = (
        db.query(ProjectStatusBucket)
        .filter_by(organization_id=org_id, slug=slug)
        .first()
    )
    if existing_slug:
        raise HTTPException(
            status_code=422,
            detail=f"A project status with key '{slug}' already exists in this organization.",
        )

    existing_name = (
        db.query(ProjectStatusBucket)
        .filter_by(organization_id=org_id, name=name)
        .first()
    )
    if existing_name:
        raise HTTPException(
            status_code=422,
            detail=f"A project status named '{name}' already exists in this organization.",
        )

    is_default = bool(payload.get("is_default", False))
    if is_default:
        db.query(ProjectStatusBucket).filter_by(organization_id=org_id).update(
            {ProjectStatusBucket.is_default: False}
        )

    from sqlalchemy import func
    order_index = payload.get("order_index")
    if order_index is None:
        max_order = (
            db.query(func.max(ProjectStatusBucket.order_index))
            .filter_by(organization_id=org_id)
            .scalar()
        )
        order_index = (max_order + 1) if max_order is not None else 0
    else:
        try:
            order_index = int(order_index)
        except (TypeError, ValueError):
            order_index = 0

    color = str(payload.get("color", "#3B82F6")).strip() or "#3B82F6"

    bucket = ProjectStatusBucket(
        organization_id=org_id,
        name=name,
        slug=slug,
        color=color,
        order_index=order_index,
        is_default=is_default,
        is_system=False,
    )
    db.add(bucket)
    db.commit()
    db.refresh(bucket)

    record_audit(
        db,
        user,
        "project_status.create",
        "created project status bucket",
        name,
        target_id=bucket.id,
    )

    return bucket.to_dict(project_count=0)


@router.put("/project-statuses/reorder")
async def reorder_project_statuses(
    request: Request,
    db: DbSession,
    data: ProjectStatusBucketReorderPayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    payload = await get_payload(request, data)
    status_ids = payload.get("status_ids")
    if not isinstance(status_ids, list):
        raise HTTPException(status_code=422, detail="status_ids list is required.")

    for index, sid in enumerate(status_ids):
        try:
            s_id = int(sid)
        except (TypeError, ValueError):
            continue
        db.query(ProjectStatusBucket).filter_by(id=s_id, organization_id=org_id).update(
            {ProjectStatusBucket.order_index: index}
        )
    db.commit()

    buckets = (
        db.query(ProjectStatusBucket)
        .filter_by(organization_id=org_id)
        .order_by(ProjectStatusBucket.order_index.asc(), ProjectStatusBucket.id.asc())
        .all()
    )
    return {"statuses": [b.to_dict() for b in buckets]}


@router.put("/project-statuses/{status_id}")
async def update_project_status(
    status_id: int,
    request: Request,
    db: DbSession,
    data: ProjectStatusBucketUpdatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    bucket = db.query(ProjectStatusBucket).filter_by(id=status_id, organization_id=org_id).first()
    if not bucket:
        raise HTTPException(status_code=404, detail="Project status bucket not found.")

    payload = await get_payload(request, data)

    if "name" in payload and payload["name"] is not None:
        name = str(payload["name"]).strip()
        if not name:
            raise HTTPException(status_code=422, detail="Name cannot be empty.")
        existing_name = (
            db.query(ProjectStatusBucket)
            .filter(
                ProjectStatusBucket.organization_id == org_id,
                ProjectStatusBucket.name == name,
                ProjectStatusBucket.id != status_id,
            )
            .first()
        )
        if existing_name:
            raise HTTPException(status_code=422, detail=f"A project status named '{name}' already exists.")
        bucket.name = name

    if "color" in payload and payload["color"] is not None:
        bucket.color = str(payload["color"]).strip()

    if "is_default" in payload and payload["is_default"] is not None:
        is_def = bool(payload["is_default"])
        if is_def:
            db.query(ProjectStatusBucket).filter(
                ProjectStatusBucket.organization_id == org_id,
                ProjectStatusBucket.id != status_id,
            ).update({ProjectStatusBucket.is_default: False})
            bucket.is_default = True
        else:
            bucket.is_default = False

    if "order_index" in payload and payload["order_index"] is not None:
        try:
            bucket.order_index = int(payload["order_index"])
        except (TypeError, ValueError):
            pass

    db.commit()
    db.refresh(bucket)

    record_audit(
        db,
        user,
        "project_status.update",
        "updated project status bucket",
        bucket.name,
        target_id=bucket.id,
    )
    return bucket.to_dict()


@router.delete("/project-statuses/{status_id}")
async def delete_project_status(status_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    bucket = db.query(ProjectStatusBucket).filter_by(id=status_id, organization_id=org_id).first()
    if not bucket:
        raise HTTPException(status_code=404, detail="Project status bucket not found.")

    active_projects_count = (
        db.query(Project)
        .filter(
            Project.organization_id == org_id,
            Project.is_deleted == False,
            Project.status == bucket.slug,
        )
        .count()
    )
    if active_projects_count > 0:
        raise HTTPException(
            status_code=422,
            detail=f"Cannot delete project status '{bucket.name}' because {active_projects_count} active project(s) are currently in this status. Please update them first.",
        )

    if bucket.is_default:
        other_bucket = (
            db.query(ProjectStatusBucket)
            .filter(ProjectStatusBucket.organization_id == org_id, ProjectStatusBucket.id != bucket.id)
            .first()
        )
        if other_bucket:
            other_bucket.is_default = True
        else:
            raise HTTPException(
                status_code=422,
                detail="Cannot delete the organization's only remaining project status bucket.",
            )

    bucket_name = bucket.name
    db.delete(bucket)
    db.commit()

    record_audit(
        db,
        user,
        "project_status.delete",
        "deleted project status bucket",
        bucket_name,
        target_id=status_id,
    )
    return {"success": True, "message": f"Project status bucket '{bucket_name}' deleted."}


# ==============================================================================
# Internship Duration Masters Endpoints
# ==============================================================================
@router.get("/internship-durations")
@router.get("/internship-durations/dropdown")
async def list_internship_durations(
    request: Request,
    db: DbSession,
    page: int = 1,
    page_size: int = 20,
    search: str | None = None,
    is_active: bool | None = None,
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    org_id = _resolve_admin_org_id(request, user, db) if user.is_admin else 1
    durations = get_or_seed_org_internship_durations(db, org_id)

    from sqlalchemy import func
    intern_counts_rows = (
        db.query(User.internship_duration_months, func.count(User.id))
        .filter(User.role == UserRole.INTERN, User.is_deleted == False)
        .group_by(User.internship_duration_months)
        .all()
    )
    intern_counts = {dur: count for dur, count in intern_counts_rows if dur is not None}

    filtered_durations = [d for d in durations if d.is_active or user.is_admin]
    if is_active is not None and not hasattr(is_active, "default"):
        filtered_durations = [d for d in filtered_durations if d.is_active == bool(is_active)]

    s = _clean_param_str(search)
    if s:
        s_lower = s.lower()
        filtered_durations = [
            d for d in filtered_durations
            if s_lower in d.title.lower() or s_lower in str(d.duration_months) or (getattr(d, "description", None) and s_lower in d.description.lower())
        ]

    # For dropdown endpoint, return unpaginated active list
    if request.url.path.endswith("/dropdown"):
        items = [
            d.to_dict(intern_count=intern_counts.get(d.duration_months, 0))
            for d in filtered_durations if d.is_active
        ]
        return {
            "durations": items,
            "items": items,
            "total": len(items),
        }

    p = _clean_param_int(page, 1)
    ps = _clean_param_int(page_size, 20)
    total = len(filtered_durations)
    total_pages = max(1, (total + ps - 1) // ps) if total else 1
    paginated_items = [
        d.to_dict(intern_count=intern_counts.get(d.duration_months, 0))
        for d in filtered_durations[(p - 1) * ps : p * ps]
    ]

    return {
        "durations": paginated_items,
        "items": paginated_items,
        "total": total,
        "page": p,
        "page_size": ps,
        "total_pages": total_pages,
    }


@router.post("/internship-durations")
async def create_internship_duration(
    request: Request,
    db: DbSession,
    data: InternshipDurationCreatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    payload = await get_payload(request, data)

    title = str(payload.get("title", "")).strip()
    if not title:
        raise HTTPException(status_code=422, detail="Duration title is required.")

    duration_val = payload.get("duration_months") or payload.get("internship_duration")
    if duration_val is None:
        raise HTTPException(status_code=422, detail="internship_duration / duration_months is required.")
    try:
        duration_months = int(duration_val)
        if duration_months <= 0:
            raise ValueError()
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Duration in months must be a positive integer.")

    leaves_val = payload.get("leaves")
    if leaves_val is None:
        raise HTTPException(status_code=422, detail="leaves quota is required.")
    try:
        leaves = int(leaves_val)
        if leaves < 0:
            raise ValueError()
    except (TypeError, ValueError):
        raise HTTPException(status_code=422, detail="Leaves quota must be a non-negative integer.")

    existing_months = (
        db.query(InternshipDurationMaster)
        .filter_by(organization_id=org_id, duration_months=duration_months)
        .first()
    )
    if existing_months:
        raise HTTPException(
            status_code=422,
            detail=f"A duration tier for {duration_months} month(s) already exists in this organization.",
        )

    existing_title = (
        db.query(InternshipDurationMaster)
        .filter_by(organization_id=org_id, title=title)
        .first()
    )
    if existing_title:
        raise HTTPException(
            status_code=422,
            detail=f"A duration tier titled '{title}' already exists in this organization.",
        )

    is_default = bool(payload.get("is_default", False))
    if is_default:
        db.query(InternshipDurationMaster).filter_by(organization_id=org_id).update(
            {InternshipDurationMaster.is_default: False}
        )

    from sqlalchemy import func
    order_index = payload.get("order_index")
    if order_index is None:
        max_order = (
            db.query(func.max(InternshipDurationMaster.order_index))
            .filter_by(organization_id=org_id)
            .scalar()
        )
        order_index = (max_order + 1) if max_order is not None else 0
    else:
        try:
            order_index = int(order_index)
        except (TypeError, ValueError):
            order_index = 0

    duration_days = payload.get("duration_days")
    if duration_days is not None:
        try:
            duration_days = int(duration_days)
        except (TypeError, ValueError):
            duration_days = None

    master = InternshipDurationMaster(
        organization_id=org_id,
        title=title,
        duration_months=duration_months,
        duration_days=duration_days,
        leaves=leaves,
        is_default=is_default,
        order_index=order_index,
        is_active=True,
    )
    db.add(master)
    db.commit()
    db.refresh(master)

    record_audit(
        db,
        user,
        "internship_duration.create",
        "created internship duration tier",
        f"{title} ({duration_months} mos, {leaves} leaves)",
        target_id=master.id,
    )

    return master.to_dict(intern_count=0)


@router.put("/internship-durations/{duration_id}")
async def update_internship_duration(
    duration_id: int,
    request: Request,
    db: DbSession,
    data: InternshipDurationUpdatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    master = db.query(InternshipDurationMaster).filter_by(id=duration_id, organization_id=org_id).first()
    if not master:
        raise HTTPException(status_code=404, detail="Internship duration tier not found.")

    payload = await get_payload(request, data)

    if "title" in payload and payload["title"] is not None:
        title = str(payload["title"]).strip()
        if not title:
            raise HTTPException(status_code=422, detail="Title cannot be empty.")
        existing_title = (
            db.query(InternshipDurationMaster)
            .filter(
                InternshipDurationMaster.organization_id == org_id,
                InternshipDurationMaster.title == title,
                InternshipDurationMaster.id != duration_id,
            )
            .first()
        )
        if existing_title:
            raise HTTPException(status_code=422, detail=f"A duration tier titled '{title}' already exists.")
        master.title = title

    duration_val = payload.get("duration_months") or payload.get("internship_duration")
    if duration_val is not None:
        try:
            dur = int(duration_val)
            if dur <= 0:
                raise ValueError()
            existing_months = (
                db.query(InternshipDurationMaster)
                .filter(
                    InternshipDurationMaster.organization_id == org_id,
                    InternshipDurationMaster.duration_months == dur,
                    InternshipDurationMaster.id != duration_id,
                )
                .first()
            )
            if existing_months:
                raise HTTPException(status_code=422, detail=f"A duration tier for {dur} months already exists.")
            master.duration_months = dur
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="duration_months must be a positive integer.")

    if "leaves" in payload and payload["leaves"] is not None:
        try:
            l_val = int(payload["leaves"])
            if l_val < 0:
                raise ValueError()
            master.leaves = l_val
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="leaves must be a non-negative integer.")

    if "is_default" in payload and payload["is_default"] is not None:
        is_def = bool(payload["is_default"])
        if is_def:
            db.query(InternshipDurationMaster).filter(
                InternshipDurationMaster.organization_id == org_id,
                InternshipDurationMaster.id != duration_id,
            ).update({InternshipDurationMaster.is_default: False})
            master.is_default = True
        else:
            master.is_default = False

    if "is_active" in payload and payload["is_active"] is not None:
        master.is_active = bool(payload["is_active"])

    if "order_index" in payload and payload["order_index"] is not None:
        try:
            master.order_index = int(payload["order_index"])
        except (TypeError, ValueError):
            pass

    db.commit()
    db.refresh(master)

    record_audit(
        db,
        user,
        "internship_duration.update",
        "updated internship duration tier",
        master.title,
        target_id=master.id,
    )
    return master.to_dict()


@router.delete("/internship-durations/{duration_id}")
async def delete_internship_duration(duration_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required.")

    org_id = _resolve_admin_org_id(request, user, db)
    master = db.query(InternshipDurationMaster).filter_by(id=duration_id, organization_id=org_id).first()
    if not master:
        raise HTTPException(status_code=404, detail="Internship duration tier not found.")

    title = master.title
    db.delete(master)
    db.commit()

    record_audit(
        db,
        user,
        "internship_duration.delete",
        "deleted internship duration tier",
        title,
        target_id=duration_id,
    )
    return {"success": True, "message": f"Internship duration tier '{title}' deleted."}
