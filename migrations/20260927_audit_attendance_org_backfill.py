"""File audit-log and attendance rows under the organization they belong to.

record_audit never set audit_logs.organization_id, and check-in, manual attendance
and leave-synced attendance never set attendance.organization_id, so every tenant's
rows defaulted to organization 1: org-1 admins saw every tenant's audit trail and
other organizations saw none of theirs.

Rows currently filed under organization 1 (or NULL) are re-tagged:
  * audit_logs: the project's organization when project_id is set, else the actor's,
    else the affected user's earliest active non-default membership;
  * attendance: the user's earliest active non-default membership.
Rows of genuine default-organization users (no other membership) are unchanged.
Idempotent Python migration.
"""
from sqlalchemy import inspect, or_
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

import models  # noqa: F401


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not all(inspector.has_table(t) for t in ("audit_logs", "attendance", "organization_memberships", "projects")):
        return

    from models import Attendance, AuditLog, OrganizationMembership, Project

    with Session(bind=engine) as db:
        tenant_of: dict[int, int | None] = {}

        def user_tenant(uid):
            if not uid:
                return None
            if uid not in tenant_of:
                m = (
                    db.query(OrganizationMembership)
                    .filter(
                        OrganizationMembership.user_id == uid,
                        OrganizationMembership.organization_id != 1,
                        OrganizationMembership.is_active == True,  # noqa: E712
                        OrganizationMembership.is_deleted == False,  # noqa: E712
                    )
                    .order_by(OrganizationMembership.id.asc())
                    .first()
                )
                tenant_of[uid] = m.organization_id if m else None
            return tenant_of[uid]

        project_org = {pid: org for pid, org in db.query(Project.id, Project.organization_id)}

        audit_moved = 0
        for log in db.query(AuditLog).filter(or_(AuditLog.organization_id == 1, AuditLog.organization_id.is_(None))):
            target = None
            if log.project_id and project_org.get(log.project_id) not in (None, 1):
                target = project_org[log.project_id]
            elif not log.project_id or project_org.get(log.project_id) is None:
                target = user_tenant(log.actor_id) or user_tenant(log.affected_user_id)
            if target:
                log.organization_id = target
                audit_moved += 1

        attendance_moved = 0
        for rec in db.query(Attendance).filter(or_(Attendance.organization_id == 1,
                                                   Attendance.organization_id.is_(None))):
            target = user_tenant(rec.user_id)
            if target:
                rec.organization_id = target
                attendance_moved += 1

        if audit_moved or attendance_moved:
            db.commit()
            print(f"[OK] Re-filed {audit_moved} audit log and {attendance_moved} attendance row(s) "
                  "under their organization")
