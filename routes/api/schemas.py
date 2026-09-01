"""Pydantic schemas for FastAPI request and response validation, generating full OpenAPI/Scalar documentation."""
from datetime import date, datetime
from typing import Any, List, Optional
from pydantic import BaseModel, ConfigDict, Field
from fastapi import Request


async def get_payload(request: Request, data: Any = None) -> dict:
    """Safely extracts dictionary payload from either parsed Pydantic model or request.json()."""
    if isinstance(data, BaseModel):
        return data.model_dump(exclude_unset=False)
    try:
        raw = await request.json()
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}



# ==============================================================================
# Auth Schemas
# ==============================================================================
class LoginRequest(BaseModel):
    email: str = Field(..., description="User account email address", json_schema_extra={"example": "intern@techcorp.com"})
    password: str = Field(..., min_length=1, description="Account password", json_schema_extra={"example": "InternPass123!"})
    remember: bool = Field(False, description="Whether to remember the login session", json_schema_extra={"example": False})


class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, description="Full name of user", json_schema_extra={"example": "Bob Johnson"})
    email: str = Field(..., description="Email address", json_schema_extra={"example": "bob@techcorp.com"})
    password: str = Field(..., min_length=8, description="Password (min 8 chars, at least 1 digit)", json_schema_extra={"example": "InternPass123!"})
    confirm_password: str = Field(..., description="Password confirmation matching password", json_schema_extra={"example": "InternPass123!"})
    role: Optional[str] = Field("intern", description="Account role: admin, mentor, or intern", json_schema_extra={"example": "intern"})
    phone: Optional[str] = Field(None, description="Phone number", json_schema_extra={"example": "+91 9876543210"})
    department: Optional[str] = Field(None, description="Department name", json_schema_extra={"example": "Engineering"})
    job_title: Optional[str] = Field(None, description="Job title / role", json_schema_extra={"example": "Backend Engineering Intern"})
    joining_date: Optional[str] = Field(None, description="Joining date in YYYY-MM-DD format", json_schema_extra={"example": "2026-06-01"})
    organization_name: Optional[str] = Field(None, description="Tenant organization name (optional)", json_schema_extra={"example": "TechCorp Global"})
    organization_slug: Optional[str] = Field(None, description="Tenant organization slug (optional)", json_schema_extra={"example": "techcorp"})


class InviteRegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, description="Full name of invited intern", json_schema_extra={"example": "Bob Johnson"})
    email: str = Field(..., description="Email address", json_schema_extra={"example": "bob@techcorp.com"})
    password: str = Field(..., min_length=8, description="Password (min 8 chars, at least 1 digit)", json_schema_extra={"example": "InternPass123!"})
    confirm_password: str = Field(..., description="Password confirmation", json_schema_extra={"example": "InternPass123!"})
    phone: str = Field(..., description="Phone number", json_schema_extra={"example": "+91 9876543210"})
    department: str = Field(..., description="Department name", json_schema_extra={"example": "Engineering"})
    job_title: str = Field(..., description="Job title / designation", json_schema_extra={"example": "Software Intern"})
    joining_date: str = Field(..., description="Joining date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})


class UserProfileResponse(BaseModel):
    id: int
    name: str
    email: str
    role: str
    is_active: bool
    bio: Optional[str] = None
    department: Optional[str] = None
    skills: List[str] = []
    phone: Optional[str] = None
    job_title: Optional[str] = None
    joining_date: Optional[str] = None
    created_at: Optional[str] = None
    session_version: int = 1


# ==============================================================================
# Admin Schemas
# ==============================================================================
class AdminCreateUserRequest(BaseModel):
    name: str = Field(..., description="Full name", json_schema_extra={"example": "Jane Doe"})
    email: str = Field(..., description="Email", json_schema_extra={"example": "jane@techcorp.com"})
    password: str = Field(..., min_length=8, description="Password", json_schema_extra={"example": "Password123!"})
    role: str = Field("intern", description="Role: admin, mentor, or intern", json_schema_extra={"example": "intern"})
    phone: Optional[str] = Field(None, description="Phone number", json_schema_extra={"example": "+91 9876543210"})
    department: Optional[str] = Field(None, description="Department", json_schema_extra={"example": "Engineering"})
    job_title: Optional[str] = Field(None, description="Job title", json_schema_extra={"example": "Frontend Intern"})
    joining_date: Optional[str] = Field(None, description="Joining date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})
    mentor_id: Optional[int] = Field(None, description="Assigned mentor ID for intern", json_schema_extra={"example": 2})


class AdminUpdateUserRequest(BaseModel):
    name: Optional[str] = Field(None, description="Full name", json_schema_extra={"example": "Jane Doe Updated"})
    email: Optional[str] = Field(None, description="Email", json_schema_extra={"example": "jane.updated@techcorp.com"})
    phone: Optional[str] = Field(None, description="Phone", json_schema_extra={"example": "+91 9876543210"})
    department: Optional[str] = Field(None, description="Department", json_schema_extra={"example": "QA"})
    job_title: Optional[str] = Field(None, description="Job title", json_schema_extra={"example": "QA Engineer"})
    joining_date: Optional[str] = Field(None, description="Joining date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})
    mentor_id: Optional[int] = Field(None, description="Assigned mentor ID", json_schema_extra={"example": 2})


class AdminRoleUpdateRequest(BaseModel):
    role: str = Field(..., description="New role: admin, mentor, or intern", json_schema_extra={"example": "mentor"})


class AdminInviteLinkCreateRequest(BaseModel):
    label: str = Field(..., description="Invite link label or batch name", json_schema_extra={"example": "Batch Summer 2026"})
    mentor_id: Optional[int] = Field(None, description="Mentor ID associated with this link", json_schema_extra={"example": 2})


class AdminInviteLinkActionRequest(BaseModel):
    link_id: int = Field(..., description="Invite link ID", json_schema_extra={"example": 1})


class ClearDataRequest(BaseModel):
    password: str = Field(..., description="DB clear confirmation password", json_schema_extra={"example": "Imp@pune2"})


# ==============================================================================
# Attendance Schemas
# ==============================================================================
class AttendanceEditRequest(BaseModel):
    check_in: Optional[str] = Field(None, description="Check-in time (HH:MM)", json_schema_extra={"example": "09:30"})
    check_out: Optional[str] = Field(None, description="Check-out time (HH:MM)", json_schema_extra={"example": "18:30"})
    status_override: Optional[str] = Field(None, description="Status override: on_leave, excused, or null to clear", json_schema_extra={"example": "excused"})
    reason: str = Field(..., description="Reason for the manual adjustment", json_schema_extra={"example": "Approved by HR"})


class ManualAttendanceRequest(BaseModel):
    user_id: int = Field(..., description="Intern user ID", json_schema_extra={"example": 3})
    date: str = Field(..., description="Attendance date (YYYY-MM-DD)", json_schema_extra={"example": "2026-08-15"})
    check_in: Optional[str] = Field("09:00", description="Check-in time (HH:MM)", json_schema_extra={"example": "09:00"})
    check_out: Optional[str] = Field(None, description="Check-out time (HH:MM). Omit to leave checkout open.", json_schema_extra={"example": "17:00"})
    # NOTE: `status` is intentionally absent — it is computed from check_in/check_out times.
    # Use `status_override` (admin-only) to force on_leave or excused on a record.
    status_override: Optional[str] = Field(None, description="Admin-only status override: on_leave or excused", json_schema_extra={"example": "excused"})
    reason: str = Field(..., description="Reason for creating manual record", json_schema_extra={"example": "Retroactive entry approved by Mentor"})



# ==============================================================================
# Leave Schemas
# ==============================================================================
class LeaveApplyRequest(BaseModel):
    start_date: str = Field(..., description="Leave start date (YYYY-MM-DD)", json_schema_extra={"example": "2026-09-01"})
    end_date: str = Field(..., description="Leave end date (YYYY-MM-DD)", json_schema_extra={"example": "2026-09-03"})
    leave_type: str = Field("casual", description="Leave type: casual, sick, earned, comp", json_schema_extra={"example": "casual"})
    reason: str = Field(..., description="Reason for requesting leave", json_schema_extra={"example": "Family function and travel"})


class LeaveReviewRequest(BaseModel):
    decision: str = Field(..., description="Review decision: approved or rejected", json_schema_extra={"example": "approved"})
    comment: Optional[str] = Field(None, description="Optional reviewer remarks", json_schema_extra={"example": "Approved. Enjoy your time off."})


# ==============================================================================
# Projects & Tasks Schemas
# ==============================================================================
class ProjectCreatePayload(BaseModel):
    name: str = Field(..., description="Project name", json_schema_extra={"example": "Mobile App V2"})
    description: Optional[str] = Field("", description="Project description", json_schema_extra={"example": "Cross-platform mobile client"})
    mentor_id: Optional[int] = Field(None, description="Primary mentor ID", json_schema_extra={"example": 2})
    mentor_ids: Optional[List[int]] = Field(None, description="List of co-mentor IDs", json_schema_extra={"example": [2]})
    intern_ids: Optional[List[int]] = Field(None, description="List of assigned intern IDs", json_schema_extra={"example": [3, 4]})
    start_date: Optional[str] = Field(None, description="Start date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})
    end_date: Optional[str] = Field(None, description="End date (YYYY-MM-DD)", json_schema_extra={"example": "2026-09-30"})
    status: Optional[str] = Field("active", description="Project status: active, completed, on_hold", json_schema_extra={"example": "active"})


class ProjectUpdatePayload(BaseModel):
    name: Optional[str] = Field(None, description="Project name", json_schema_extra={"example": "Mobile App V2 Updated"})
    description: Optional[str] = Field(None, description="Project description", json_schema_extra={"example": "Updated specifications"})
    mentor_id: Optional[int] = Field(None, description="Primary mentor ID", json_schema_extra={"example": 2})
    mentor_ids: Optional[List[int]] = Field(None, description="List of co-mentor IDs", json_schema_extra={"example": [2]})
    intern_ids: Optional[List[int]] = Field(None, description="List of assigned intern IDs", json_schema_extra={"example": [3]})
    start_date: Optional[str] = Field(None, description="Start date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})
    end_date: Optional[str] = Field(None, description="End date (YYYY-MM-DD)", json_schema_extra={"example": "2026-09-30"})
    status: Optional[str] = Field(None, description="Project status: active, completed, on_hold", json_schema_extra={"example": "active"})


class ProjectAssignPayload(BaseModel):
    user_id: int = Field(..., description="Intern user ID to assign", json_schema_extra={"example": 3})


class TaskCreatePayload(BaseModel):
    title: str = Field(..., description="Task title", json_schema_extra={"example": "Implement OAuth2 Login"})
    description: Optional[str] = Field("", description="Task description and acceptance criteria", json_schema_extra={"example": "Support Google and GitHub OAuth"})
    assigned_to: Optional[int] = Field(None, description="Assigned intern user ID", json_schema_extra={"example": 3})
    due_date: Optional[str] = Field(None, description="Due date / deadline (YYYY-MM-DD)", json_schema_extra={"example": "2026-08-30"})
    priority: Optional[str] = Field("medium", description="Priority: low, medium, high", json_schema_extra={"example": "high"})
    status: Optional[str] = Field(None, description="Initial status slug (defaults to org default status if omitted)", json_schema_extra={"example": "todo"})


class TaskUpdatePayload(BaseModel):
    title: Optional[str] = Field(None, description="Task title", json_schema_extra={"example": "Implement OAuth2 & JWT"})
    description: Optional[str] = Field(None, description="Task description", json_schema_extra={"example": "Updated OAuth details"})
    assigned_to: Optional[int] = Field(None, description="Assigned intern ID", json_schema_extra={"example": 3})
    due_date: Optional[str] = Field(None, description="Deadline (YYYY-MM-DD)", json_schema_extra={"example": "2026-08-30"})
    priority: Optional[str] = Field(None, description="Priority: low, medium, high", json_schema_extra={"example": "high"})
    status: Optional[str] = Field(None, description="Status slug", json_schema_extra={"example": "done"})


class TaskStatusPayload(BaseModel):
    status: str = Field(..., description="New task status slug", json_schema_extra={"example": "done"})


class TaskStatusBucketCreatePayload(BaseModel):
    name: str = Field(..., description="Status bucket name", json_schema_extra={"example": "QA / Testing"})
    slug: Optional[str] = Field(None, description="Optional custom slug (auto-generated if omitted)", json_schema_extra={"example": "qa_testing"})
    color: Optional[str] = Field("#6366F1", description="Hex color code", json_schema_extra={"example": "#8B5CF6"})
    status_category: Optional[str] = Field("in_progress", description="Category: todo, in_progress, done", json_schema_extra={"example": "in_progress"})
    is_default: Optional[bool] = Field(False, description="Whether this is the default status for new tasks")
    order_index: Optional[int] = Field(None, description="Sequence order for display")


class TaskStatusBucketUpdatePayload(BaseModel):
    name: Optional[str] = Field(None, description="Status bucket name")
    color: Optional[str] = Field(None, description="Hex color code")
    status_category: Optional[str] = Field(None, description="Category: todo, in_progress, done")
    is_default: Optional[bool] = Field(None, description="Whether this is default status")
    order_index: Optional[int] = Field(None, description="Sequence order for display")


class TaskStatusBucketReorderPayload(BaseModel):
    status_ids: list[int] = Field(..., description="List of status IDs in desired order", json_schema_extra={"example": [1, 3, 2, 4]})


# ==============================================================================
# Project Status Master Schemas
# ==============================================================================
class ProjectStatusBucketCreatePayload(BaseModel):
    name: str = Field(..., description="Project status name", json_schema_extra={"example": "In Review"})
    slug: Optional[str] = Field(None, description="Optional custom slug (auto-generated if omitted)", json_schema_extra={"example": "in_review"})
    color: Optional[str] = Field("#3B82F6", description="Hex color code", json_schema_extra={"example": "#6366F1"})
    is_default: Optional[bool] = Field(False, description="Whether this is default status for new projects")
    order_index: Optional[int] = Field(None, description="Sequence order for display")


class ProjectStatusBucketUpdatePayload(BaseModel):
    name: Optional[str] = Field(None, description="Project status name")
    color: Optional[str] = Field(None, description="Hex color code")
    is_default: Optional[bool] = Field(None, description="Whether this is default status")
    order_index: Optional[int] = Field(None, description="Sequence order for display")


class ProjectStatusBucketReorderPayload(BaseModel):
    status_ids: list[int] = Field(..., description="List of status IDs in desired order", json_schema_extra={"example": [1, 2, 3, 4]})


# ==============================================================================
# Internship Duration Master Schemas
# ==============================================================================
class InternshipDurationCreatePayload(BaseModel):
    title: str = Field(..., description="Duration tier title", json_schema_extra={"example": "3 Months Standard"})
    internship_duration: Optional[int] = Field(None, description="Duration in months (or use duration_months)", json_schema_extra={"example": 3})
    duration_months: Optional[int] = Field(None, description="Duration in months", json_schema_extra={"example": 3})
    duration_days: Optional[int] = Field(None, description="Optional duration in days")
    leaves: int = Field(..., description="Allowed leave days quota", json_schema_extra={"example": 5})
    is_default: Optional[bool] = Field(False, description="Whether this is the default duration for new interns")
    order_index: Optional[int] = Field(None, description="Sequence order for display")


class InternshipDurationUpdatePayload(BaseModel):
    title: Optional[str] = Field(None, description="Duration tier title")
    internship_duration: Optional[int] = Field(None, description="Duration in months")
    duration_months: Optional[int] = Field(None, description="Duration in months")
    duration_days: Optional[int] = Field(None, description="Optional duration in days")
    leaves: Optional[int] = Field(None, description="Allowed leave days quota")
    is_default: Optional[bool] = Field(None, description="Whether this is default duration")
    is_active: Optional[bool] = Field(None, description="Whether this duration option is active")
    order_index: Optional[int] = Field(None, description="Sequence order for display")


# ==============================================================================
# Assignment Module Schemas
# ==============================================================================
class AssignmentCreatePayload(BaseModel):
    title: str = Field(..., description="Assignment title", json_schema_extra={"example": "Build REST API Module"})
    description: Optional[str] = Field("", description="Assignment requirements and guidelines", json_schema_extra={"example": "Create endpoints with proper authentication."})
    project_id: Optional[int] = Field(None, description="Project ID to assign to", json_schema_extra={"example": 1})
    cohort_id: Optional[int] = Field(None, description="Cohort ID to assign to", json_schema_extra={"example": 1})
    assigned_to_user_id: Optional[int] = Field(None, description="Specific intern ID", json_schema_extra={"example": 4})
    due_date: Optional[str] = Field(None, description="Due date (YYYY-MM-DD)", json_schema_extra={"example": "2026-09-15"})
    max_score: Optional[int] = Field(100, description="Maximum points/score", json_schema_extra={"example": 100})
    status: Optional[str] = Field("active", description="Status: draft, active, closed, archived")


class AssignmentUpdatePayload(BaseModel):
    title: Optional[str] = Field(None, description="Assignment title")
    description: Optional[str] = Field(None, description="Assignment requirements")
    project_id: Optional[int] = Field(None, description="Project ID")
    cohort_id: Optional[int] = Field(None, description="Cohort ID")
    assigned_to_user_id: Optional[int] = Field(None, description="Specific intern ID")
    due_date: Optional[str] = Field(None, description="Due date (YYYY-MM-DD)")
    max_score: Optional[int] = Field(None, description="Maximum points/score")
    status: Optional[str] = Field(None, description="Status: draft, active, closed, archived")


class AssignmentSubmitPayload(BaseModel):
    submission_text: Optional[str] = Field(None, description="Written submission notes / response", json_schema_extra={"example": "Completed all backend tasks."})
    github_url: Optional[str] = Field(None, description="GitHub repository or commit link", json_schema_extra={"example": "https://github.com/intern/project"})


class AssignmentReviewPayload(BaseModel):
    score: Optional[float] = Field(None, ge=0, description="Awarded score / marks", json_schema_extra={"example": 95.0})
    feedback: Optional[str] = Field(None, description="Mentor review feedback", json_schema_extra={"example": "Great structure and clean test coverage!"})
    status: Optional[str] = Field("approved", description="Review status: approved, rejected, resubmitted, under_review", json_schema_extra={"example": "approved"})


class TaskCommentPayload(BaseModel):
    body: str = Field(..., description="Comment content", json_schema_extra={"example": "Completed the integration test suite."})


class ProjectBoardCommentPayload(BaseModel):
    body: str = Field(..., max_length=100, description="Project message (max 100 chars)", json_schema_extra={"example": "Sprint review on Friday at 3 PM!"})


class ProjectLinkPayload(BaseModel):
    link: str = Field(..., description="Valid HTTP/HTTPS URL", json_schema_extra={"example": "https://figma.com/file/xyz"})
    remark: str = Field(..., description="Description / label for the link", json_schema_extra={"example": "Figma Design Mockups"})


# ==============================================================================
# Cohort Schemas
# ==============================================================================
class CohortCreatePayload(BaseModel):
    name: str = Field(..., description="Cohort batch name", json_schema_extra={"example": "Summer 2026 Batch"})
    description: Optional[str] = Field("", description="Cohort description", json_schema_extra={"example": "Full-stack development internship cohort"})
    start_date: Optional[str] = Field(None, description="Start date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})
    end_date: Optional[str] = Field(None, description="End date (YYYY-MM-DD)", json_schema_extra={"example": "2026-08-31"})


class CohortUpdatePayload(BaseModel):
    name: Optional[str] = Field(None, description="Cohort name", json_schema_extra={"example": "Summer 2026 Batch Updated"})
    description: Optional[str] = Field(None, description="Cohort description", json_schema_extra={"example": "Updated description"})
    start_date: Optional[str] = Field(None, description="Start date (YYYY-MM-DD)", json_schema_extra={"example": "2026-06-01"})
    end_date: Optional[str] = Field(None, description="End date (YYYY-MM-DD)", json_schema_extra={"example": "2026-08-31"})


class CohortMemberPayload(BaseModel):
    user_id: int = Field(..., description="User ID to add to cohort", json_schema_extra={"example": 3})


# ==============================================================================
# Announcement Schemas
# ==============================================================================
class AnnouncementCreatePayload(BaseModel):
    title: str = Field(..., description="Announcement title", json_schema_extra={"example": "Town Hall Meeting on Monday"})
    body: str = Field(..., description="Announcement markdown body", json_schema_extra={"example": "Please join the company-wide town hall via Google Meet."})
    is_pinned: Optional[bool] = Field(False, description="Pin announcement to top of feed", json_schema_extra={"example": True})
    project_id: Optional[int] = Field(None, description="Optional project ID for project-specific announcement", json_schema_extra={"example": None})


class AnnouncementUpdatePayload(BaseModel):
    title: Optional[str] = Field(None, description="Announcement title", json_schema_extra={"example": "Town Hall Meeting (Updated)"})
    body: Optional[str] = Field(None, description="Announcement body", json_schema_extra={"example": "Meeting postponed to 11 AM."})
    is_pinned: Optional[bool] = Field(None, description="Pin/unpin", json_schema_extra={"example": True})


# ==============================================================================
# Blog Schemas
# ==============================================================================
class BlogCreatePayload(BaseModel):
    title: str = Field(..., min_length=1, description="Blog post title", json_schema_extra={"example": "How InternHub Simplifies Intern Management"})
    content: str = Field(..., min_length=1, description="Blog post body (HTML or markdown)", json_schema_extra={"example": "<p>Managing interns has never been easier...</p>"})
    excerpt: Optional[str] = Field(None, description="Short summary shown in blog listings", json_schema_extra={"example": "A deep dive into InternHub's intern management workflow."})
    cover_image_url: Optional[str] = Field(None, description="Cover image URL", json_schema_extra={"example": "https://cdn.example.com/cover.png"})
    tags: Optional[List[str]] = Field(None, description="Tag list; stored comma-separated", json_schema_extra={"example": ["product", "internship"]})
    status: Optional[str] = Field("draft", description="Publication status: draft or published", json_schema_extra={"example": "draft"})
    slug: Optional[str] = Field(None, description="Optional custom URL slug (auto-generated from title when omitted)", json_schema_extra={"example": "how-internhub-simplifies-intern-management"})


class BlogUpdatePayload(BaseModel):
    title: Optional[str] = Field(None, description="Blog post title", json_schema_extra={"example": "How InternHub Simplifies Intern Management (2026)"})
    content: Optional[str] = Field(None, description="Blog post body (HTML or markdown)", json_schema_extra={"example": "<p>Updated content...</p>"})
    excerpt: Optional[str] = Field(None, description="Short summary shown in blog listings", json_schema_extra={"example": "An updated look at InternHub's workflow."})
    cover_image_url: Optional[str] = Field(None, description="Cover image URL", json_schema_extra={"example": "https://cdn.example.com/cover-v2.png"})
    tags: Optional[List[str]] = Field(None, description="Tag list; stored comma-separated", json_schema_extra={"example": ["product"]})
    status: Optional[str] = Field(None, description="Publication status: draft or published", json_schema_extra={"example": "published"})
    slug: Optional[str] = Field(None, description="Custom URL slug", json_schema_extra={"example": "internhub-intern-management-2026"})


# ==============================================================================
# Lead Schemas
# ==============================================================================
class LeadCreatePayload(BaseModel):
    name: str = Field(..., min_length=1, description="Full name of the prospective customer", json_schema_extra={"example": "Alex Morgan"})
    email: str = Field(..., min_length=1, description="Work email address", json_schema_extra={"example": "alex@acmecorp.com"})
    phone: Optional[str] = Field(None, description="Contact phone number", json_schema_extra={"example": "+91 9876543210"})
    company: Optional[str] = Field(None, description="Company / organization name", json_schema_extra={"example": "Acme Corp"})
    role: Optional[str] = Field(None, description="Job title of the contact", json_schema_extra={"example": "Engineering Lead"})
    cohort_size: Optional[str] = Field(None, description="Intern cohort size band", json_schema_extra={"example": "16-50 interns"})
    message: Optional[str] = Field(None, description="Free-text message from the contact", json_schema_extra={"example": "We would like a demo for our summer cohort."})
    source: Optional[str] = Field("marketing_site", description="Where the lead came from (e.g. marketing_site)", json_schema_extra={"example": "marketing_site"})
    website: Optional[str] = Field(None, description="Honeypot anti-spam field — must remain empty", json_schema_extra={"example": None})


# ==============================================================================
# Profile & Standup & Reviews Schemas
# ==============================================================================
class ProfileUpdatePayload(BaseModel):
    bio: Optional[str] = Field(None, description="User bio/summary", json_schema_extra={"example": "Software engineering intern passionate about cloud & AI"})
    phone: Optional[str] = Field(None, description="Phone number", json_schema_extra={"example": "+91 9876543210"})
    skills: Optional[str] = Field(None, description="Comma-separated skills", json_schema_extra={"example": "Python, FastAPI, TypeScript, React"})


class ChangePasswordPayload(BaseModel):
    current_password: str = Field(..., description="Current password", json_schema_extra={"example": "InternPass123!"})
    new_password: str = Field(..., min_length=8, description="New password (min 8 chars, at least 1 digit)", json_schema_extra={"example": "NewInternPass123!"})
    confirm_password: str = Field(..., description="Confirm new password", json_schema_extra={"example": "NewInternPass123!"})


class ReviewCreatePayload(BaseModel):
    intern_id: int = Field(..., description="Intern user ID being reviewed", json_schema_extra={"example": 3})
    project_id: Optional[int] = Field(None, description="Project ID", json_schema_extra={"example": 1})
    period: str = Field(..., description="Evaluation period", json_schema_extra={"example": "Q3 2026"})
    rating: int = Field(..., ge=1, le=5, description="Overall rating (1-5)", json_schema_extra={"example": 5})
    technical_rating: Optional[int] = Field(None, ge=1, le=5, description="Technical rating (1-5)", json_schema_extra={"example": 5})
    communication_rating: Optional[int] = Field(None, ge=1, le=5, description="Communication rating (1-5)", json_schema_extra={"example": 4})
    initiative_rating: Optional[int] = Field(None, ge=1, le=5, description="Initiative rating (1-5)", json_schema_extra={"example": 5})
    feedback: Optional[str] = Field("", description="Detailed review feedback", json_schema_extra={"example": "Outstanding problem-solving and rapid learning!"})
    strengths: Optional[str] = Field("", description="Key strengths", json_schema_extra={"example": "Python, FastAPI, Architecture"})
    improvements: Optional[str] = Field("", description="Areas for growth", json_schema_extra={"example": "System design documentation"})


class ReviewUpdatePayload(BaseModel):
    rating: Optional[int] = Field(None, ge=1, le=5, description="Overall rating (1-5)", json_schema_extra={"example": 5})
    technical_rating: Optional[int] = Field(None, ge=1, le=5, description="Technical rating (1-5)", json_schema_extra={"example": 5})
    communication_rating: Optional[int] = Field(None, ge=1, le=5, description="Communication rating (1-5)", json_schema_extra={"example": 5})
    initiative_rating: Optional[int] = Field(None, ge=1, le=5, description="Initiative rating (1-5)", json_schema_extra={"example": 5})
    feedback: Optional[str] = Field(None, description="Detailed feedback", json_schema_extra={"example": "Updated review comments."})
    strengths: Optional[str] = Field(None, description="Strengths", json_schema_extra={"example": "Python, Architecture"})
    improvements: Optional[str] = Field(None, description="Areas for improvement", json_schema_extra={"example": "Writing tests"})


class StandupCreatePayload(BaseModel):
    date: str = Field(..., description="Standup date (YYYY-MM-DD)", json_schema_extra={"example": "2026-08-16"})
    did: str = Field(..., description="What was accomplished yesterday", json_schema_extra={"example": "Implemented backend API authentication"})
    plan: str = Field(..., description="What is planned for today", json_schema_extra={"example": "Add Scalar OpenAPI documentation and verify schemas"})
    blockers: Optional[str] = Field("None", description="Any blockers or challenges", json_schema_extra={"example": "None"})
    mood: Optional[str] = Field("great", description="Mood / status: great, good, okay, bad", json_schema_extra={"example": "great"})


class StandupUpdatePayload(BaseModel):
    did: Optional[str] = Field(None, description="Accomplishments", json_schema_extra={"example": "Completed all unit tests"})
    plan: Optional[str] = Field(None, description="Plans", json_schema_extra={"example": "Deploy to staging"})
    blockers: Optional[str] = Field(None, description="Blockers", json_schema_extra={"example": "None"})
    mood: Optional[str] = Field(None, description="Mood", json_schema_extra={"example": "great"})
