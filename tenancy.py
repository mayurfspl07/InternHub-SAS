"""Tenant isolation guards.

Every handler that loads a record by id (or accepts ids in its body) must make
sure the record belongs to the caller's organization. These helpers centralize
that check so routes cannot forget a piece of it:

* ``viewer_org_id``     – the caller's active org, validated against memberships
                          (a spoofed ``X-Organization-Id`` falls back to the
                          caller's real membership, never to the target org).
* ``ensure_in_org``     – 404 unless an org-owned record is in the caller's org.
* ``ensure_user_in_org``/``ensure_project_in_org``/``ensure_cohort_in_org``
                        – validate ids referenced in request bodies / paths.

Rows created before multi-tenancy have ``organization_id = NULL``; they belong
to the default organization (id 1), matching the existing org-1 fallbacks.
Platform admins (``is_platform_admin`` / ``is_superadmin``) are not restricted.
"""
from __future__ import annotations

from typing import Iterable

from fastapi import HTTPException, Request
from sqlalchemy.orm import Session

from models import Cohort, OrganizationMembership, Project, Task, User

DEFAULT_ORG_ID = 1
NO_ORG_ID = -1  # matches no organization


def is_platform_admin(user: User | None) -> bool:
    return bool(user and (getattr(user, "is_platform_admin", False) or getattr(user, "is_superadmin", False)))


def _norm(org_id: int | None) -> int:
    return DEFAULT_ORG_ID if org_id is None else int(org_id)


def viewer_org_id(request: Request, user: User, db: Session) -> int:
    """Caller's organization for this request (membership-validated).

    Users with no membership rows at all are legacy single-tenant accounts and belong to
    the default organization, matching ``user_org_ids`` and the routes' org-1 fallbacks.
    Users whose memberships are all inactive (e.g. suspended) match no organization."""
    from dependencies import _resolve_request_org_id

    resolved = _resolve_request_org_id(request, user, db)
    if resolved is not None:
        return resolved
    has_memberships = (
        db.query(OrganizationMembership.id)
        .filter(OrganizationMembership.user_id == user.id, OrganizationMembership.is_deleted == False)  # noqa: E712
        .first()
    )
    return NO_ORG_ID if has_memberships else DEFAULT_ORG_ID


def _deny(detail: str = "Not found.") -> HTTPException:
    # 404 rather than 403 so ids from other tenants are indistinguishable from missing ones.
    return HTTPException(status_code=404, detail=detail)


def ensure_in_org(request: Request, user: User, db: Session, record_org_id: int | None, detail: str = "Not found.") -> None:
    """404 unless ``record_org_id`` is the caller's organization."""
    if is_platform_admin(user):
        return
    viewer = viewer_org_id(request, user, db)
    if _norm(record_org_id) != _norm(viewer):
        raise _deny(detail)


def user_org_ids(db: Session, user_id: int) -> set[int]:
    """Organizations a user belongs to (active or pending, not deleted)."""
    rows = (
        db.query(OrganizationMembership.organization_id)
        .filter(
            OrganizationMembership.user_id == user_id,
            OrganizationMembership.is_deleted == False,  # noqa: E712
        )
        .all()
    )
    orgs = {r[0] for r in rows}
    return orgs or {DEFAULT_ORG_ID}


def ensure_user_in_org(request: Request, user: User, db: Session, target_user_id: int | None,
                       detail: str = "User not found.") -> None:
    """404 unless ``target_user_id`` is a member of the caller's organization."""
    if target_user_id is None or is_platform_admin(user):
        return
    viewer = viewer_org_id(request, user, db)
    if _norm(viewer) not in {_norm(o) for o in user_org_ids(db, int(target_user_id))}:
        raise _deny(detail)


def ensure_users_in_org(request: Request, user: User, db: Session, user_ids: Iterable[int | None],
                        detail: str = "User not found.") -> None:
    for uid in user_ids or []:
        ensure_user_in_org(request, user, db, uid, detail)


def ensure_project_in_org(request: Request, user: User, db: Session, project_id: int | None,
                          detail: str = "Project not found.") -> Project | None:
    if project_id is None:
        return None
    project = db.get(Project, int(project_id))
    if not project:
        raise _deny(detail)
    ensure_in_org(request, user, db, project.organization_id, detail)
    return project


def ensure_task_in_org(request: Request, user: User, db: Session, task: Task | None,
                       detail: str = "Task not found.") -> None:
    if task is None:
        return
    org_id = task.organization_id
    if org_id is None and task.project_id:
        project = db.get(Project, task.project_id)
        org_id = project.organization_id if project else None
    ensure_in_org(request, user, db, org_id, detail)


def ensure_cohort_in_org(request: Request, user: User, db: Session, cohort_id: int | None,
                         detail: str = "Cohort not found.") -> Cohort | None:
    if cohort_id is None:
        return None
    cohort = db.get(Cohort, int(cohort_id))
    if not cohort:
        raise _deny(detail)
    ensure_in_org(request, user, db, cohort.organization_id, detail)
    return cohort


def org_member_user_ids(db: Session, org_id: int | None, roles: Iterable[str] | None = None) -> list[int]:
    """Active users of an organization, optionally filtered by membership role."""
    q = db.query(OrganizationMembership.user_id).filter(
        OrganizationMembership.organization_id == _norm(org_id),
        OrganizationMembership.is_active == True,  # noqa: E712
        OrganizationMembership.is_deleted == False,  # noqa: E712
    )
    if roles:
        q = q.filter(OrganizationMembership.role.in_(list(roles)))
    return [r[0] for r in q.all()]


def org_filter(column, org_id: int | None):
    """SQL filter placing ``column`` (an ``organization_id``) in ``org_id``; legacy NULL rows count as org 1."""
    from sqlalchemy import or_

    org_id = _norm(org_id)
    if org_id == DEFAULT_ORG_ID:
        return or_(column == DEFAULT_ORG_ID, column.is_(None))
    return column == org_id
