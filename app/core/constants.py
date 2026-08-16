"""Application-wide constants, enums, and default configuration values."""


class UserRole:
    ADMIN = "admin"
    MENTOR = "mentor"
    INTERN = "intern"
    ALL = (ADMIN, MENTOR, INTERN)


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
    HALF_DAY = "half_day"
    LATE = "late"
    ABSENT = "absent"
    ON_LEAVE = "on_leave"
    ALL = (PRESENT, HALF_DAY, LATE, ABSENT, ON_LEAVE)


class LeaveStatus:
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    ALL = (PENDING, APPROVED, REJECTED)


class LeaveType:
    CASUAL = "casual"
    SICK = "sick"
    EXAM = "exam"
    OTHER = "other"
    ALL = (CASUAL, SICK, EXAM, OTHER)


class ProjectStatus:
    PLANNING = "planning"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    ON_HOLD = "on_hold"
    CANCELLED = "cancelled"
    ALL = (PLANNING, IN_PROGRESS, COMPLETED, ON_HOLD, CANCELLED)


class TaskStatus:
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    IN_REVIEW = "in_review"
    COMPLETED = "completed"
    DONE = "done"
    ALL = (TODO, IN_PROGRESS, IN_REVIEW, COMPLETED, DONE)


class TaskPriority:
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    URGENT = "urgent"
    ALL = (LOW, MEDIUM, HIGH, URGENT)


PAGE_SIZE_DEFAULT = 20
PAGE_SIZE_MAX = 100
RECYCLE_BIN_RETENTION_DAYS = 30
