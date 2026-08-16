"""Tenant-aware repository base and entity repositories.

Guarantees that all queries and mutations are automatically scoped by organization_id.
"""
from typing import Any, Generic, Type, TypeVar
from sqlalchemy.orm import Session
from models import (
    Announcement,
    Attendance,
    AuditLog,
    BinItem,
    Cohort,
    CohortMember,
    InternInviteLink,
    LeaveRequest,
    Notification,
    PerformanceReview,
    Project,
    ProjectAssignment,
    ProjectComment,
    ProjectLink,
    ProjectMentorAssignment,
    StandupLog,
    Task,
    TaskComment,
    User,
)

T = TypeVar("T")


class TenantRepository:
    """Base repository that automatically enforces organization_id boundaries."""

    def __init__(self, db: Session, org_id: int):
        self.db = db
        self.org_id = org_id

    # -----------------------------------------------------------------------
    # Generic Helpers
    # -----------------------------------------------------------------------
    def get_scoped(self, model: Type[T], entity_id: int) -> T | None:
        """Fetch a single record by primary key, verifying it belongs to this tenant."""
        query = self.db.query(model).filter(getattr(model, "id") == entity_id)
        if hasattr(model, "organization_id"):
            query = query.filter(getattr(model, "organization_id") == self.org_id)
        if hasattr(model, "is_deleted"):
            query = query.filter(getattr(model, "is_deleted") == False)
        return query.first()

    def query_scoped(self, model: Type[T]):
        """Return a base query filtered to this organization and active (non-deleted) rows."""
        query = self.db.query(model)
        if hasattr(model, "organization_id"):
            query = query.filter(getattr(model, "organization_id") == self.org_id)
        if hasattr(model, "is_deleted"):
            query = query.filter(getattr(model, "is_deleted") == False)
        return query

    # -----------------------------------------------------------------------
    # Projects & Tasks
    # -----------------------------------------------------------------------
    def get_project(self, project_id: int) -> Project | None:
        return self.get_scoped(Project, project_id)

    def list_projects(self, status: str | None = None, mentor_id: int | None = None):
        q = self.query_scoped(Project)
        if status:
            q = q.filter(Project.status == status)
        if mentor_id:
            q = q.filter(Project.mentor_id == mentor_id)
        return q.order_by(Project.created_at.desc()).all()

    def get_task(self, task_id: int) -> Task | None:
        return self.get_scoped(Task, task_id)

    def list_tasks_for_project(self, project_id: int):
        # Validate project belongs to org
        proj = self.get_project(project_id)
        if not proj:
            return []
        return (
            self.query_scoped(Task)
            .filter(Task.project_id == project_id)
            .order_by(Task.created_at.asc())
            .all()
        )

    # -----------------------------------------------------------------------
    # Attendance
    # -----------------------------------------------------------------------
    def get_attendance(self, record_id: int) -> Attendance | None:
        return self.get_scoped(Attendance, record_id)

    def get_attendance_for_user_and_date(self, user_id: int, target_date):
        return (
            self.db.query(Attendance)
            .filter(
                Attendance.organization_id == self.org_id,
                Attendance.user_id == user_id,
                Attendance.date == target_date,
            )
            .first()
        )

    # -----------------------------------------------------------------------
    # Leave Requests
    # -----------------------------------------------------------------------
    def get_leave_request(self, leave_id: int) -> LeaveRequest | None:
        return self.get_scoped(LeaveRequest, leave_id)

    # -----------------------------------------------------------------------
    # Standups, Cohorts, Reviews, Announcements
    # -----------------------------------------------------------------------
    def get_standup(self, log_id: int) -> StandupLog | None:
        return self.get_scoped(StandupLog, log_id)

    def get_cohort(self, cohort_id: int) -> Cohort | None:
        return self.get_scoped(Cohort, cohort_id)

    def get_review(self, review_id: int) -> PerformanceReview | None:
        return self.get_scoped(PerformanceReview, review_id)

    def get_announcement(self, ann_id: int) -> Announcement | None:
        return self.get_scoped(Announcement, ann_id)

    def get_invite_link(self, token: str) -> InternInviteLink | None:
        return (
            self.db.query(InternInviteLink)
            .filter(
                InternInviteLink.organization_id == self.org_id,
                InternInviteLink.token == token,
                InternInviteLink.is_active == True,
            )
            .first()
        )
