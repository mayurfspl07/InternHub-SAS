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
    ADMIN = "admin"
    MENTOR = "mentor"
    INTERN = "intern"
    ALL = (ADMIN, MENTOR, INTERN)


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


class TaskStatus:
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    TESTING = "testing"
    DONE = "done"
    COMPLETED = "completed"  # alias used by seeded data
    ALL = (TODO, IN_PROGRESS, TESTING, DONE, COMPLETED)


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
# ORM models
# ---------------------------------------------------------------------------

def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _utcnow_aware() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(180), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False, default=UserRole.INTERN)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # Set the first time this account is ever activated (at creation if created active, or
    # on admin/mentor approval otherwise) and never cleared afterward — this is what lets
    # login distinguish "never approved yet" (activated_at is None) from "was approved,
    # since deactivated" (activated_at is set) when is_active is False.
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
    session_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    mentor_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=True, index=True
    )
    signup_invite_link_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("intern_invite_links.id", ondelete="SET NULL"), nullable=True, index=True
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

    def check_password(self, raw: str) -> bool:
        return check_password_hash(self.password_hash, raw)

    def skills_list(self) -> list[str]:
        if not self.skills:
            return []
        return [s.strip() for s in self.skills.split(",") if s.strip()]

    @property
    def is_admin(self) -> bool:
        return self.role == UserRole.ADMIN

    @property
    def is_mentor(self) -> bool:
        return self.role == UserRole.MENTOR

    @property
    def is_intern(self) -> bool:
        return self.role == UserRole.INTERN

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


class Attendance(Base):
    __tablename__ = "attendance"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_user_date"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
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

    # GPS coordinates and a selfie captured client-side at the moment of check-in/out —
    # photo is a path relative to attendance_photos.PHOTOS_DIR, not the raw image.
    # address is a best-effort reverse-geocoded place name — may be null if the geocoding
    # lookup failed/timed out, in which case callers fall back to showing lat/lng.
    check_in_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_in_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_in_address: Mapped[str | None] = mapped_column(String(300), nullable=True)
    check_in_photo: Mapped[str | None] = mapped_column(String(300), nullable=True)
    check_out_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_out_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    check_out_address: Mapped[str | None] = mapped_column(String(300), nullable=True)
    check_out_photo: Mapped[str | None] = mapped_column(String(300), nullable=True)

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


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_date: Mapped[date] = mapped_column(Date, nullable=False, default=date.today)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default=ProjectStatus.PLANNING)
    mentor_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

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
        done = sum(1 for t in active if t.status in (TaskStatus.DONE, TaskStatus.COMPLETED))
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
    # Set once an overdue reminder has been sent for this task, so the daily sweep
    # doesn't re-notify the same missed deadline every day. Cleared if the deadline
    # changes, so a rescheduled task can be flagged again if it goes overdue anew.
    overdue_notified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    project = relationship("Project", back_populates="tasks")
    creator = relationship("User", back_populates="tasks_created", foreign_keys=[created_by_id])
    assignee = relationship("User", back_populates="tasks_assigned", foreign_keys=[assigned_to])
    comments = relationship("TaskComment", back_populates="task", cascade="all, delete-orphan", order_by="TaskComment.created_at")

    @property
    def is_overdue(self) -> bool:
        return (
            self.deadline is not None
            and self.status not in (TaskStatus.DONE, TaskStatus.COMPLETED)
            and self.deadline < date.today()
        )


class LeaveRequest(Base):
    __tablename__ = "leave_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
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
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

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
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    message: Mapped[str] = mapped_column(String(500), nullable=False)
    link: Mapped[str | None] = mapped_column(String(300), nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)

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


class StandupLog(Base):
    __tablename__ = "standup_logs"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_standup_user_date"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
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

    user = relationship("User", foreign_keys=[user_id])


class BinEntityType:
    PROJECT = "project"
    TASK = "task"
    TASK_COMMENT = "task_comment"
    USER = "user"
    ANNOUNCEMENT = "announcement"
    COHORT = "cohort"
    REVIEW = "review"
    STANDUP = "standup"
    LEAVE_REQUEST = "leave_request"


class BinItem(Base):
    """Recycle-bin entry for soft-deleted entities (admin restore / auto-purge)."""

    __tablename__ = "bin_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
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

    deleted_by = relationship("User", foreign_keys=[deleted_by_id])


class Announcement(Base):
    __tablename__ = "announcements"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    project_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("projects.id", ondelete="SET NULL"), nullable=True)
    author_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    project = relationship("Project", foreign_keys=[project_id])
    author = relationship("User", foreign_keys=[author_id])


class PerformanceReview(Base):
    __tablename__ = "performance_reviews"
    __table_args__ = (
        UniqueConstraint("intern_id", "reviewer_id", "period", name="uq_review_intern_reviewer_period"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
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

    intern = relationship("User", foreign_keys=[intern_id])
    reviewer = relationship("User", foreign_keys=[reviewer_id])
    project = relationship("Project", foreign_keys=[project_id])


class Cohort(Base):
    __tablename__ = "cohorts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
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
