"""SQLAlchemy models for the intern management system."""
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from werkzeug.security import check_password_hash, generate_password_hash

from database import Base


# ---------------------------------------------------------------------------
# Status constants — use these instead of raw strings throughout the codebase
# ---------------------------------------------------------------------------
class UserRole:
    SUPERADMIN = "superadmin"
    ADMIN = "admin"
    MENTOR = "mentor"
    INTERN = "intern"
    ALL = (SUPERADMIN, ADMIN, MENTOR, INTERN)


class OrganizationType:
    BUSINESS = "business"
    EDUCATIONAL_INSTITUTE = "educational_institute"
    ALL = (BUSINESS, EDUCATIONAL_INSTITUTE)


class OrganizationStatus:
    ACTIVE = "active"
    SUSPENDED = "suspended"
    TRIAL = "trial"
    CANCELLED = "cancelled"
    ALL = (ACTIVE, SUSPENDED, TRIAL, CANCELLED)


class AttendanceStatus:
    PRESENT = "present"
    LATE = "late"
    HALF_DAY = "half_day"
    ABSENT = "absent"
    ON_LEAVE = "on_leave"
    EXCUSED = "excused"


class ProjectStatus:
    PLANNING = "planning"
    ACTIVE = "active"
    COMPLETED = "completed"
    ON_HOLD = "on_hold"
    ALL = (PLANNING, ACTIVE, COMPLETED, ON_HOLD)


class TaskStatusCategory:
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    DONE = "done"
    ALL = (TODO, IN_PROGRESS, DONE)


class TaskStatus:
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    TESTING = "testing"
    DONE = "done"
    ALL = (TODO, IN_PROGRESS, TESTING, DONE)


class TaskPriority:
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class LeaveStatus:
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class LeaveType:
    CASUAL = "casual"
    SICK = "sick"
    EARNED = "earned"
    COMP = "comp"
    ALL = (CASUAL, SICK, EARNED, COMP)


# ---------------------------------------------------------------------------
# Helper functions for datetime handling
# ---------------------------------------------------------------------------

def _utcnow() -> datetime:
    """Return naive UTC now - use for timezone-naive DateTime columns."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _utcnow_aware() -> datetime:
    """Return aware UTC now - use for DateTime(timezone=True) columns."""
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Core SaaS & Tenancy Models
# ---------------------------------------------------------------------------

class Organization(Base):
    __tablename__ = "organizations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    type: Mapped[str] = mapped_column(String(40), nullable=False, default=OrganizationType.BUSINESS)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=OrganizationStatus.ACTIVE)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Kolkata")
    logo_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    settings = relationship(
        "OrganizationSettings",
        back_populates="organization",
        uselist=False,
        cascade="all, delete-orphan",
    )
    memberships = relationship(
        "OrganizationMembership",
        back_populates="organization",
        cascade="all, delete-orphan",
    )
    task_status_buckets = relationship(
        "TaskStatusBucket",
        back_populates="organization",
        cascade="all, delete-orphan",
        order_by="TaskStatusBucket.order_index",
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "slug": self.slug,
            "name": self.name,
            "type": self.type,
            "status": self.status,
            "timezone": self.timezone,
            "logo_url": self.logo_url,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }

    def __repr__(self) -> str:
        return f"<Organization {self.id} {self.slug} ({self.name})>"


class OrganizationSettings(Base):
    __tablename__ = "organization_settings"

    organization_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), primary_key=True
    )
    shift_start: Mapped[str] = mapped_column(String(10), nullable=False, default="10:00:00")
    shift_end: Mapped[str] = mapped_column(String(10), nullable=False, default="19:00:00")
    late_cutoff: Mapped[str] = mapped_column(String(10), nullable=False, default="10:30:00")
    noon_cutoff: Mapped[str] = mapped_column(String(10), nullable=False, default="12:00:00")
    checkin_block: Mapped[str] = mapped_column(String(10), nullable=False, default="20:00:00")
    full_day_hours: Mapped[float] = mapped_column(Float, nullable=False, default=7.00)
    half_day_hours: Mapped[float] = mapped_column(Float, nullable=False, default=5.00)
    leave_quota_days: Mapped[int] = mapped_column(Integer, nullable=False, default=15)
    advance_leave_days: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    require_attendance_selfie: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    require_attendance_gps: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    auto_checkout_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    organization = relationship("Organization", back_populates="settings")

    def to_dict(self) -> dict:
        return {
            "organization_id": self.organization_id,
            "shift_start": self.shift_start,
            "shift_end": self.shift_end,
            "late_cutoff": self.late_cutoff,
            "noon_cutoff": self.noon_cutoff,
            "checkin_block": self.checkin_block,
            "full_day_hours": float(self.full_day_hours),
            "half_day_hours": float(self.half_day_hours),
            "leave_quota_days": self.leave_quota_days,
            "advance_leave_days": self.advance_leave_days,
            "require_attendance_selfie": self.require_attendance_selfie,
            "require_attendance_gps": self.require_attendance_gps,
            "auto_checkout_enabled": self.auto_checkout_enabled,
        }


class OrganizationMembership(Base):
    __tablename__ = "organization_memberships"
    __table_args__ = (UniqueConstraint("organization_id", "user_id", name="uq_org_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role: Mapped[str] = mapped_column(String(40), nullable=False, default=UserRole.INTERN)
    department: Mapped[str | None] = mapped_column(String(120), nullable=True)
    job_title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    joining_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    internship_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    internship_duration_months: Mapped[int | None] = mapped_column(Integer, nullable=True, default=3)
    mentor_membership_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organization_memberships.id", ondelete="SET NULL"), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    activated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", back_populates="memberships")
    user = relationship("User", back_populates="memberships")
    mentor = relationship(
        "OrganizationMembership",
        remote_side="OrganizationMembership.id",
        foreign_keys=[mentor_membership_id],
        back_populates="mentees",
    )
    mentees = relationship(
        "OrganizationMembership",
        foreign_keys="OrganizationMembership.mentor_membership_id",
        back_populates="mentor",
    )

    @property
    def is_superadmin(self) -> bool:
        return self.role in (UserRole.SUPERADMIN, "superadmin")

    @property
    def is_admin(self) -> bool:
        return self.role in (UserRole.ADMIN, UserRole.SUPERADMIN, "admin", "superadmin", "org_admin")

    @property
    def is_mentor(self) -> bool:
        return self.role in (UserRole.MENTOR, "mentor")

    @property
    def is_intern(self) -> bool:
        return self.role in (UserRole.INTERN, "intern")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "organization_id": self.organization_id,
            "user_id": self.user_id,
            "role": self.role,
            "department": self.department,
            "job_title": self.job_title,
            "joining_date": self.joining_date.isoformat() if self.joining_date else None,
            "mentor_membership_id": self.mentor_membership_id,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


# ---------------------------------------------------------------------------
# Core User Model
# ---------------------------------------------------------------------------

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(180), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False, default=UserRole.INTERN)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_platform_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    activated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    department: Mapped[str | None] = mapped_column(String(120), nullable=True)
    skills: Mapped[str | None] = mapped_column(Text, nullable=True)
    phone: Mapped[str | None] = mapped_column(String(30), nullable=True)
    job_title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    joining_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    internship_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    internship_duration_months: Mapped[int | None] = mapped_column(Integer, nullable=True, default=3)
    session_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    token_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    mentor_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=True, index=True
    )
    signup_invite_link_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("intern_invite_links.id", ondelete="SET NULL"), nullable=True, index=True
    )

    memberships = relationship(
        "OrganizationMembership", back_populates="user", cascade="all, delete-orphan"
    )
    attendance_records = relationship(
        "Attendance", back_populates="user", cascade="all, delete-orphan"
    )
    projects_as_mentor = relationship(
        "Project", back_populates="mentor", foreign_keys="Project.mentor_id"
    )
    project_mentor_assignments = relationship(
        "ProjectMentorAssignment",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    project_assignments = relationship(
        "ProjectAssignment", back_populates="user", cascade="all, delete-orphan"
    )
    tasks_assigned = relationship(
        "Task", back_populates="assignee", foreign_keys="Task.assigned_to"
    )
    tasks_created = relationship(
        "Task", back_populates="creator", foreign_keys="Task.created_by_id"
    )
    leave_requests = relationship(
        "LeaveRequest",
        back_populates="user",
        cascade="all, delete-orphan",
        foreign_keys="LeaveRequest.user_id",
    )
    notifications = relationship(
        "Notification",
        back_populates="user",
        cascade="all, delete-orphan",
        order_by="Notification.created_at.desc()",
    )
    mentor = relationship(
        "User",
        remote_side="User.id",
        foreign_keys=[mentor_id],
        back_populates="mentees",
    )
    mentees = relationship(
        "User",
        back_populates="mentor",
        foreign_keys="User.mentor_id",
    )

    is_authenticated = True

    def set_password(self, raw: str) -> None:
        self.password_hash = generate_password_hash(raw)
        self.session_version = (self.session_version or 1) + 1
        self.token_version = (self.token_version or 1) + 1

    def check_password(self, raw: str) -> bool:
        return check_password_hash(self.password_hash, raw)

    def skills_list(self) -> list[str]:
        if not self.skills:
            return []
        return [s.strip() for s in self.skills.split(",") if s.strip()]

    @property
    def is_superadmin(self) -> bool:
        return self.role in (UserRole.SUPERADMIN, "superadmin") or self.is_platform_admin

    @property
    def is_admin(self) -> bool:
        return (
            self.role in (UserRole.ADMIN, UserRole.SUPERADMIN, "admin", "superadmin", "org_admin")
            or self.is_platform_admin
        )

    @property
    def is_mentor(self) -> bool:
        return self.role in (UserRole.MENTOR, "mentor")

    @property
    def is_intern(self) -> bool:
        return self.role in (UserRole.INTERN, "intern")

    def __repr__(self) -> str:
        return f"<User {self.id} {self.email} ({self.role})>"


class GuestUser:
    """Placeholder for unauthenticated template context."""

    is_authenticated = False
    role = ""
    name = ""
    email = ""
    is_admin = False
    is_mentor = False
    is_intern = False
    is_platform_admin = False


# ---------------------------------------------------------------------------
# Attendance Models
# ---------------------------------------------------------------------------

class Attendance(Base):
    __tablename__ = "attendance"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_user_date"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    date: Mapped[date] = mapped_column(Date, nullable=False, default=date.today, index=True)
    check_in: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    check_out: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=AttendanceStatus.PRESENT)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    checkout_source: Mapped[str | None] = mapped_column(String(10), nullable=True)
    checkout_missed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    hours_worked: Mapped[float | None] = mapped_column(Float, nullable=True)

    check_in_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_in_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_in_address: Mapped[str | None] = mapped_column(String(300), nullable=True)
    check_in_photo: Mapped[str | None] = mapped_column(String(300), nullable=True)
    check_out_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_out_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_out_address: Mapped[str | None] = mapped_column(String(300), nullable=True)
    check_out_photo: Mapped[str | None] = mapped_column(String(300), nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    user = relationship("User", back_populates="attendance_records")
    audit_entries = relationship(
        "AttendanceAuditLog",
        back_populates="attendance",
        cascade="all, delete-orphan",
        order_by="AttendanceAuditLog.created_at.desc()",
    )

    @property
    def duration_hours(self) -> float:
        if self.checkout_missed:
            return 0.0
        if self.hours_worked is not None:
            return round(float(self.hours_worked), 2)
        if not self.check_out:
            return 0.0
        delta = self.check_out - self.check_in
        return round(delta.total_seconds() / 3600, 2)


class AttendanceAuditLog(Base):
    """Immutable log of mentor/admin attendance corrections."""

    __tablename__ = "attendance_audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    attendance_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("attendance.id", ondelete="CASCADE"), nullable=False, index=True
    )
    editor_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    editor_name: Mapped[str] = mapped_column(String(120), nullable=False, default="")
    field_name: Mapped[str] = mapped_column(String(40), nullable=False)
    old_value: Mapped[str | None] = mapped_column(String(120), nullable=True)
    new_value: Mapped[str | None] = mapped_column(String(120), nullable=True)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False, index=True)

    attendance = relationship("Attendance", back_populates="audit_entries")
    editor = relationship("User", foreign_keys=[editor_id])


# ---------------------------------------------------------------------------
# Project & Task Models
# ---------------------------------------------------------------------------

class Project(Base):
    __tablename__ = "projects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_date: Mapped[date] = mapped_column(Date, nullable=False, default=date.today)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=ProjectStatus.PLANNING)
    mentor_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    mentor = relationship("User", back_populates="projects_as_mentor", foreign_keys=[mentor_id])
    tasks = relationship("Task", back_populates="project", cascade="all, delete-orphan")
    assignments = relationship(
        "ProjectAssignment", back_populates="project", cascade="all, delete-orphan"
    )
    mentor_assignments = relationship(
        "ProjectMentorAssignment", back_populates="project", cascade="all, delete-orphan"
    )
    comments = relationship(
        "ProjectComment", back_populates="project", cascade="all, delete-orphan", order_by="ProjectComment.created_at"
    )
    links = relationship(
        "ProjectLink", back_populates="project", cascade="all, delete-orphan", order_by="ProjectLink.created_at"
    )

    @property
    def active_tasks(self):
        return [t for t in self.tasks if not t.is_deleted]

    @property
    def progress_pct(self) -> int:
        active = self.active_tasks
        if not active:
            return 0
        done = sum(1 for t in active if t.status in (TaskStatus.DONE,))
        return int(done * 100 / len(active))

    @property
    def task_count(self) -> int:
        return len(self.active_tasks)


class ProjectAssignment(Base):
    __tablename__ = "project_assignments"
    __table_args__ = (UniqueConstraint("project_id", "user_id", name="uq_project_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assigned_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    project = relationship("Project", back_populates="assignments")
    user = relationship("User", back_populates="project_assignments")


class ProjectMentorAssignment(Base):
    __tablename__ = "project_mentor_assignments"
    __table_args__ = (UniqueConstraint("project_id", "user_id", name="uq_project_mentor_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assigned_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    project = relationship("Project", back_populates="mentor_assignments")
    user = relationship("User", back_populates="project_mentor_assignments")


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    assigned_to: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id"), nullable=True)
    deadline: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=TaskStatus.TODO)
    priority: Mapped[str] = mapped_column(String(10), nullable=False, default=TaskPriority.MEDIUM)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    overdue_notified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    project = relationship("Project", back_populates="tasks")
    creator = relationship("User", back_populates="tasks_created", foreign_keys=[created_by_id])
    assignee = relationship("User", back_populates="tasks_assigned", foreign_keys=[assigned_to])
    comments = relationship("TaskComment", back_populates="task", cascade="all, delete-orphan", order_by="TaskComment.created_at")
    attachments = relationship("TaskAttachment", back_populates="task", cascade="all, delete-orphan", order_by="TaskAttachment.created_at.desc()")

    @property
    def is_overdue(self) -> bool:
        return (
            self.deadline is not None
            and self.status not in (TaskStatus.DONE, "done", "completed")
            and self.deadline < date.today()
        )


class TaskAttachment(Base):
    __tablename__ = "task_attachments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    task_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    comment_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("task_comments.id", ondelete="SET NULL"), nullable=True, index=True
    )
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    file_path: Mapped[str] = mapped_column(String(500), nullable=False)
    file_size: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    file_type: Mapped[str] = mapped_column(String(100), nullable=False, default="application/octet-stream")
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    task = relationship("Task", back_populates="attachments")
    user = relationship("User")
    comment = relationship("TaskComment")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "task_id": self.task_id,
            "user_id": self.user_id,
            "user_name": self.user.name if self.user else None,
            "comment_id": self.comment_id,
            "file_name": self.file_name,
            "file_size": self.file_size,
            "file_type": self.file_type,
            "description": self.description,
            "download_url": f"/api/projects/tasks/attachments/{self.id}/download",
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class TaskStatusBucket(Base):
    __tablename__ = "task_status_buckets"
    __table_args__ = (
        UniqueConstraint("organization_id", "slug", name="uq_org_status_slug"),
        UniqueConstraint("organization_id", "name", name="uq_org_status_name"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(60), nullable=False)
    slug: Mapped[str] = mapped_column(String(60), nullable=False)
    color: Mapped[str] = mapped_column(String(20), nullable=False, default="#6366F1")
    order_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status_category: Mapped[str] = mapped_column(
        String(20), nullable=False, default=TaskStatusCategory.IN_PROGRESS
    )
    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_system: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_utcnow, onupdate=_utcnow, nullable=False
    )

    organization = relationship("Organization", back_populates="task_status_buckets")

    def to_dict(self, task_count: int | None = None) -> dict:
        data = {
            "id": self.id,
            "organization_id": self.organization_id,
            "name": self.name,
            "slug": self.slug,
            "color": self.color,
            "order_index": self.order_index,
            "status_category": self.status_category,
            "is_default": self.is_default,
            "is_system": self.is_system,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
        if task_count is not None:
            data["task_count"] = task_count
        return data


class LeaveRequest(Base):
    __tablename__ = "leave_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    leave_type: Mapped[str] = mapped_column(String(20), nullable=False, default="casual")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=LeaveStatus.PENDING)
    reviewed_by: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    attachment_path: Mapped[str | None] = mapped_column(String(500), nullable=True)
    attachment_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    user = relationship("User", back_populates="leave_requests", foreign_keys=[user_id])
    reviewer = relationship("User", foreign_keys=[reviewed_by])

    @property
    def days(self) -> int:
        """Business days (Mon–Fri) — matches leave-balance accounting."""
        count = 0
        current = self.start_date
        while current <= self.end_date:
            if current.weekday() < 5:
                count += 1
            current += timedelta(days=1)
        return count


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    message: Mapped[str] = mapped_column(String(500), nullable=False)
    link: Mapped[str | None] = mapped_column(String(300), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    organization = relationship("Organization", foreign_keys=[organization_id])
    user = relationship("User", back_populates="notifications")


class TaskComment(Base):
    __tablename__ = "task_comments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    task_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    task = relationship("Task", back_populates="comments")
    author = relationship("User", foreign_keys=[user_id])
    deleted_by = relationship("User", foreign_keys=[deleted_by_id])


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="SET NULL"), nullable=True, index=True, default=1
    )
    actor_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    actor_name: Mapped[str] = mapped_column(String(120), nullable=False, default="")
    action: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    verb: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    target: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    target_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    project_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
    affected_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=_utcnow_aware,
        nullable=False,
        index=True,
    )

    organization = relationship("Organization", foreign_keys=[organization_id])


class StandupLog(Base):
    __tablename__ = "standup_logs"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_standup_user_date"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    date: Mapped[date] = mapped_column(Date, nullable=False, default=date.today, index=True)
    did: Mapped[str] = mapped_column(Text, nullable=False, default="")
    plan: Mapped[str] = mapped_column(Text, nullable=False, default="")
    blockers: Mapped[str | None] = mapped_column(Text, nullable=True)
    mood: Mapped[str | None] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    user = relationship("User", foreign_keys=[user_id])


class BinEntityType:
    PROJECT = "project"
    TASK = "task"
    TASK_COMMENT = "task_comment"
    USER = "user"
    ANNOUNCEMENT = "announcement"
    BLOG_POST = "blog_post"
    COHORT = "cohort"
    REVIEW = "review"
    STANDUP = "standup"
    LEAVE_REQUEST = "leave_request"


class BinItem(Base):
    """Recycle-bin entry for soft-deleted entities (admin restore / auto-purge)."""

    __tablename__ = "bin_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    entity_type: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    deleted_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    deleted_by_name: Mapped[str] = mapped_column(String(120), nullable=False, default="")
    deleted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow_aware, nullable=False, index=True
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    restored_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    snapshot_json: Mapped[str | None] = mapped_column(Text, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    deleted_by = relationship("User", foreign_keys=[deleted_by_id])


class Announcement(Base):
    __tablename__ = "announcements"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    project_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
    author_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    project = relationship("Project", foreign_keys=[project_id])
    author = relationship("User", foreign_keys=[author_id])


class PerformanceReview(Base):
    __tablename__ = "performance_reviews"
    __table_args__ = (
        UniqueConstraint("intern_id", "reviewer_id", "period", name="uq_review_intern_reviewer_period"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    intern_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    reviewer_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    project_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
    period: Mapped[str | None] = mapped_column(String(50), nullable=True)
    rating: Mapped[int] = mapped_column(Integer, nullable=False)
    technical_rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    communication_rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    initiative_rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    strengths: Mapped[str | None] = mapped_column(Text, nullable=True)
    improvements: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    intern = relationship("User", foreign_keys=[intern_id])
    reviewer = relationship("User", foreign_keys=[reviewer_id])
    project = relationship("Project", foreign_keys=[project_id])


class Cohort(Base):
    __tablename__ = "cohorts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    organization = relationship("Organization", foreign_keys=[organization_id])
    members = relationship("CohortMember", back_populates="cohort", cascade="all, delete-orphan")
    created_by = relationship("User", foreign_keys=[created_by_id])


class CohortMember(Base):
    __tablename__ = "cohort_members"
    __table_args__ = (UniqueConstraint("cohort_id", "user_id", name="uq_cohort_user"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    cohort_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("cohorts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    cohort = relationship("Cohort", back_populates="members")
    user = relationship("User", foreign_keys=[user_id])


class InternInviteLink(Base):
    """Shareable link for interns to self-register into the workspace."""

    __tablename__ = "intern_invite_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    label: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    mentor_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    usage_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    organization = relationship("Organization", foreign_keys=[organization_id])
    created_by = relationship("User", foreign_keys=[created_by_id])
    mentor = relationship("User", foreign_keys=[mentor_id])


class ProjectComment(Base):
    __tablename__ = "project_comments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    project = relationship("Project", back_populates="comments")
    user = relationship("User", foreign_keys=[user_id])
    deleted_by = relationship("User", foreign_keys=[deleted_by_id])


class ProjectLink(Base):
    __tablename__ = "project_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    link: Mapped[str] = mapped_column(Text, nullable=False)
    remark: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_by_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    project = relationship("Project", back_populates="links")
    user = relationship("User", foreign_keys=[user_id])
    deleted_by = relationship("User", foreign_keys=[deleted_by_id])


class BlogPost(Base):
    """Marketing blog post — publicly readable when published, admin-managed."""

    __tablename__ = "blog_posts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    organization_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("organizations.id", ondelete="CASCADE"), nullable=True, index=True, default=1
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    slug: Mapped[str] = mapped_column(String(220), nullable=False, unique=True, index=True)
    excerpt: Mapped[str | None] = mapped_column(Text, nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    cover_image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    tags: Mapped[str | None] = mapped_column(String(500), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="draft", nullable=False, index=True)
    author_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    published_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, onupdate=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    organization = relationship("Organization", foreign_keys=[organization_id])
    author = relationship("User", foreign_keys=[author_id])


class LeadStatus:
    NEW = "new"
    CONTACTED = "contacted"
    CONVERTED = "converted"
    CLOSED = "closed"
    ALL = (NEW, CONTACTED, CONVERTED, CLOSED)


class Lead(Base):
    """Marketing-site lead captured from public forms (demo requests, contact)."""

    __tablename__ = "leads"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    phone: Mapped[str | None] = mapped_column(String(40), nullable=True)
    company: Mapped[str | None] = mapped_column(String(200), nullable=True)
    role: Mapped[str | None] = mapped_column(String(100), nullable=True)
    cohort_size: Mapped[str | None] = mapped_column(String(50), nullable=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(String(50), default="marketing_site", nullable=False)
    status: Mapped[str] = mapped_column(String(20), default=LeadStatus.NEW, nullable=False, index=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False, index=True)
