from copy import deepcopy
from typing import Any, Dict
from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

TAG_NAMES_MAP = {
    "api-auth": "Authentication",
    "api-admin": "Administration",
    "api-attendance": "Attendance",
    "api-leave": "Leave Management",
    "api-projects": "Projects",
    "api-tasks": "Tasks",
    "api-audit": "Audit Logs",
    "api-announcements": "Announcements",
    "api-cohorts": "Cohorts",
    "api-dashboard": "Dashboard",
    "api-notifications": "Notifications",
    "api-profile": "Profile",
    "api-reviews": "Performance Reviews",
    "api-search": "Global Search",
    "api-standup": "Daily Standups",
    "api-users": "Users",
    "platform": "Platform Admin",
    "org": "Organization Management",
    "Admin - Student Attendance": "Admin Student Attendance",
    "Admin - Attendance Management": "Admin Attendance Management",
    "Mentor - Student Attendance": "Mentor Student Attendance",
    "Mentor - Attendance Management": "Mentor Attendance Management",
}

TAG_METADATA = [
    {"name": "Authentication", "description": "User login, registration, invite activation, and session management."},
    {"name": "Profile", "description": "User profile viewing, editing, and password management."},
    {"name": "Attendance", "description": "Check-in, check-out with selfies/geocoding, reports, personal export, and manual adjustments."},
    {"name": "Admin Student Attendance", "description": "Admin overview of interns, today live attendance, individual student attendance, and attendance CSV export."},
    {"name": "Mentor Student Attendance", "description": "Mentor overview of assigned interns, today live attendance, mentee attendance history, and mentee attendance CSV export."},
    {"name": "Projects", "description": "Project creation, member staffing, board discussions, resources, and progress tracking."},
    {"name": "Tasks", "description": "Task creation, status pipelines, assignments, and discussions."},
    {"name": "Daily Standups", "description": "Daily work logs, blocker reporting, and standup history."},
    {"name": "Leave Management", "description": "Leave requests, balance tracking, and mentor/admin approvals."},
    {"name": "Performance Reviews", "description": "Intern performance evaluation, feedback, and rating matrix."},
    {"name": "Cohorts", "description": "Intern batch groups, cohort member management, and assignments."},
    {"name": "Announcements", "description": "Organization-wide bulletins, notices, and pinned updates."},
    {"name": "Dashboard", "description": "Aggregated analytics, quick statistics, and recent activity."},
    {"name": "Notifications", "description": "In-app notifications and read status management."},
    {"name": "Administration", "description": "User management, invite links, bin restoration, and admin controls."},
    {"name": "Audit Logs", "description": "Security audit trails, activity logging, and user action tracking."},
    {"name": "Global Search", "description": "Omni-search across users, projects, and tasks."},
    {"name": "Platform Admin", "description": "Multi-tenant platform administration and organization onboarding."},
    {"name": "Organization Management", "description": "Organization tenant settings, profile, and team members."},
]


def build_custom_openapi(app: FastAPI) -> Dict[str, Any]:
    """Generates an enhanced OpenAPI 3.1.0 schema with complete request/response definitions and examples."""
    if app.openapi_schema:
        return app.openapi_schema

    schema = get_openapi(
        title=app.title,
        version="1.0.0",
        description="Comprehensive REST API documentation for InternHub Platform with live payloads and responses.",
        routes=app.routes,
        tags=TAG_METADATA,
    )

    # Standard Common Payloads & Responses
    user_sample = {
        "id": 1,
        "name": "Jane Doe",
        "email": "jane@techcorp.com",
        "role": "intern",
        "is_active": True,
        "bio": "Full-stack software engineering intern",
        "department": "Engineering",
        "skills": ["Python", "FastAPI", "React", "TypeScript"],
        "phone": "+91 9876543210",
        "job_title": "Software Intern",
        "joining_date": "2026-06-01",
        "created_at": "2026-06-01T09:00:00Z",
        "session_version": 1,
    }

    mentor_sample = {
        "id": 2,
        "name": "Dr. Sarah Connor",
        "email": "sarah@techcorp.com",
        "role": "mentor",
        "is_active": True,
        "bio": "Senior Engineering Lead & Mentor",
        "department": "Engineering",
        "skills": ["System Architecture", "Leadership", "Python"],
        "phone": "+91 9123456789",
        "job_title": "Staff Engineer",
        "joining_date": "2024-01-15",
        "created_at": "2024-01-15T09:00:00Z",
        "session_version": 1,
    }

    project_sample = {
        "id": 1,
        "name": "AI Search Engine",
        "description": "Semantic search engine using vector embeddings",
        "start_date": "2026-06-01",
        "end_date": "2026-08-31",
        "status": "in_progress",
        "mentor_id": 2,
        "mentor_name": "Dr. Sarah Connor",
        "mentor_ids": [2],
        "mentors": [{"id": 2, "name": "Dr. Sarah Connor", "email": "sarah@techcorp.com", "role": "mentor"}],
        "task_done": 8,
        "task_total": 12,
        "progress_percent": 67,
        "created_at": "2026-06-01T10:00:00Z",
    }

    task_sample = {
        "id": 101,
        "project_id": 1,
        "project_name": "AI Search Engine",
        "title": "Implement Vector Search Pipeline",
        "description": "Construct high performance indexing using Faiss",
        "status": "in_progress",
        "priority": "high",
        "assigned_to": 1,
        "assignee_name": "Jane Doe",
        "created_by_id": 2,
        "creator_name": "Dr. Sarah Connor",
        "deadline": "2026-08-20",
        "is_overdue": False,
        "created_at": "2026-08-01T10:00:00Z",
        "can_edit": True,
        "can_move": True,
        "can_delete": True,
    }

    attendance_sample = {
        "id": 501,
        "user_id": 1,
        "user_name": "Jane Doe",
        "date": "2026-08-16",
        "check_in": "09:00",
        "check_out": "17:30",
        "hours_worked": 8.5,
        "status": "present",
        "checkin_photo_path": "/api/attendance/photo/checkin_501.jpg",
        "checkout_photo_path": "/api/attendance/photo/checkout_501.jpg",
        "checkin_location": "Tech Hub Tower, Bengaluru",
        "checkout_location": "Tech Hub Tower, Bengaluru",
        "checkout_missed": False,
        "checkout_source": "user",
        "status_override": None,
        "created_at": "2026-08-16T09:00:00Z",
    }

    leave_sample = {
        "id": 201,
        "user_id": 1,
        "user_name": "Jane Doe",
        "start_date": "2026-09-01",
        "end_date": "2026-09-03",
        "days": 3,
        "leave_type": "casual",
        "reason": "Family function",
        "status": "pending",
        "reviewed_by": None,
        "reviewer_name": None,
        "reviewed_at": None,
        "created_at": "2026-08-16T12:00:00Z",
    }

    standup_sample = {
        "id": 301,
        "user_id": 1,
        "user_name": "Jane Doe",
        "date": "2026-08-16",
        "did": "Completed unit tests for authentication module",
        "plan": "Integrate Scalar interactive documentation and verify OpenAPI schemas",
        "blockers": "None",
        "mood": "great",
        "created_at": "2026-08-16T09:15:00Z",
    }

    cohort_sample = {
        "id": 1,
        "name": "Summer Engineering Cohort 2026",
        "description": "Undergraduate and graduate software engineering intern batch",
        "start_date": "2026-06-01",
        "end_date": "2026-08-31",
        "member_count": 15,
        "created_by_id": 2,
        "created_at": "2026-05-15T10:00:00Z",
        "members": [
            {
                "user_id": 1,
                "name": "Jane Doe",
                "email": "jane@techcorp.com",
                "department": "Engineering",
                "joined_at": "2026-06-01T09:00:00Z",
            }
        ],
    }

    announcement_sample = {
        "id": 401,
        "title": "Mid-Term Project Demonstrations Schedule",
        "body": "Presentations will begin next Monday at 10:00 AM IST. All interns please submit demo links.",
        "is_pinned": True,
        "author_id": 2,
        "author_name": "Dr. Sarah Connor",
        "author_role": "mentor",
        "project_id": None,
        "project_name": None,
        "created_at": "2026-08-15T14:30:00Z",
    }

    review_sample = {
        "id": 101,
        "intern_id": 1,
        "intern_name": "Jane Doe",
        "reviewer_id": 2,
        "reviewer_name": "Dr. Sarah Connor",
        "project_id": 1,
        "project_name": "AI Search Engine",
        "period": "Mid-Term Q3 2026",
        "rating": 5,
        "technical_rating": 5,
        "communication_rating": 4,
        "initiative_rating": 5,
        "feedback": "Outstanding technical delivery and independent problem solving abilities.",
        "strengths": "Fast learner, excellent code quality, proactive collaboration.",
        "improvements": "Continue expanding end-to-end integration test coverage.",
        "created_at": "2026-08-15T16:00:00Z",
    }

    notification_sample = {
        "id": 801,
        "user_id": 1,
        "message": "New task assigned: Implement Vector Search Pipeline",
        "link": "/projects/1",
        "is_read": False,
        "created_at": "2026-08-16T10:00:00Z",
    }

    audit_sample = {
        "id": 901,
        "user_id": 1,
        "user_name": "Jane Doe",
        "action": "task.create",
        "detail": "created task: Implement Vector Search Pipeline",
        "target": "AI Search Engine",
        "ip_address": "127.0.0.1",
        "created_at": "2026-08-16T10:00:00Z",
    }

    student_overview_sample = {
        "id": 1,
        "name": "Jane Doe",
        "email": "jane@techcorp.com",
        "department": "Engineering",
        "phone": "+91 9876543210",
        "job_title": "Software Intern",
        "is_active": True,
        "joining_date": "2026-06-01",
        "mentor_id": 2,
        "mentor_name": "Dr. Sarah Connor",
        "created_at": "2026-06-01T09:00:00Z",
        "active_projects": 2,
        "attendance_overview": {
            "window_days": 30,
            "start_date": "2026-07-22",
            "end_date": "2026-08-21",
            "total_records": 22,
            "present": 18,
            "late": 2,
            "half_day": 1,
            "absent": 1,
            "on_leave": 0,
            "excused": 0,
            "attended": 21,
            "attendance_rate": 95.5,
            "total_hours": 164.5,
            "last_check_in": "2026-08-21T09:15:00",
        },
    }

    today_student_item_sample = {
        "student": {
            "id": 1,
            "name": "Jane Doe",
            "email": "jane@techcorp.com",
            "department": "Engineering",
            "phone": "+91 9876543210",
            "job_title": "Software Intern",
            "is_active": True,
            "mentor_id": 2,
        },
        "today_status": "present",
        "is_checked_in": True,
        "is_checked_out": False,
        "attendance": attendance_sample,
    }

    monthly_summary_sample = {
        "year_month": "2026-08",
        "present": 15,
        "late": 2,
        "half_day": 0,
        "absent": 0,
        "on_leave": 1,
        "attended": 17,
        "total_days": 18,
        "total_hours": 136.5,
        "attendance_rate": 94.4,
    }

    # Map endpoint patterns to rich response definitions & examples
    custom_responses: Dict[str, Dict[str, Any]] = {
        # Auth
        ("GET", "/api/auth/me"): {
            "example": user_sample,
            "description": "Authenticated user profile data",
        },
        ("POST", "/api/auth/login"): {
            "example": {
                "ok": True,
                "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIiwiaXNzIjoiaW50ZXJuaHViIn0...",
                "user": user_sample,
            },
            "description": "Login successful — session token issued",
        },
        ("POST", "/api/auth/logout"): {
            "example": {"ok": True},
            "description": "Logged out successfully",
        },
        ("POST", "/api/auth/register"): {
            "example": {
                "ok": True,
                "message": "Registration successful — you can now log in.",
                "user": user_sample,
            },
            "description": "User account created successfully",
        },
        ("GET", "/api/auth/invite/{token}"): {
            "example": {
                "valid": True,
                "label": "Summer 2026 Interns",
                "mentor_name": "Dr. Sarah Connor",
            },
            "description": "Invite link validity and metadata",
        },
        ("POST", "/api/auth/invite/{token}/register"): {
            "example": {
                "ok": True,
                "message": "Account created successfully.",
                "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                "user": user_sample,
            },
            "description": "Account created and activated via invite link",
        },

        # Admin
        ("GET", "/api/admin/overview"): {
            "example": {
                "total_users": 48,
                "total_interns": 35,
                "total_mentors": 10,
                "total_admins": 3,
                "active_interns": 32,
                "today_present": 28,
                "pending_leaves": 4,
                "active_projects": 8,
            },
            "description": "System-wide administrative dashboard statistics",
        },
        ("GET", "/api/admin/users"): {
            "example": {
                "users": [user_sample, mentor_sample],
                "page": 1,
                "page_size": 20,
                "total": 48,
                "total_pages": 3,
            },
            "description": "Paginated list of all organization users",
        },
        ("POST", "/api/admin/users"): {
            "example": user_sample,
            "description": "User created successfully by administrator",
        },
        ("GET", "/api/admin/users/{user_id}"): {
            "example": user_sample,
            "description": "User details",
        },
        ("PUT", "/api/admin/users/{user_id}"): {
            "example": user_sample,
            "description": "User updated successfully",
        },
        ("POST", "/api/admin/users/{user_id}/toggle"): {
            "example": user_sample,
            "description": "User activation status toggled",
        },
        ("POST", "/api/admin/users/{user_id}/role"): {
            "example": user_sample,
            "description": "User role changed successfully",
        },
        ("DELETE", "/api/admin/users/{user_id}"): {
            "example": {"ok": True},
            "description": "User moved to recycle bin",
        },
        ("GET", "/api/admin/invite-link"): {
            "example": {
                "link": {
                    "id": 1,
                    "token": "inv_sec89283471029384",
                    "label": "Summer Batch 2026",
                    "mentor_id": 2,
                    "mentor_name": "Dr. Sarah Connor",
                    "is_active": True,
                    "usage_count": 12,
                    "url": "http://127.0.0.1:3000/join/inv_sec89283471029384",
                    "created_at": "2026-05-01T09:00:00Z",
                },
                "links": [],
            },
            "description": "Active invite links",
        },
        ("POST", "/api/admin/invite-link"): {
            "example": {
                "link": {
                    "id": 2,
                    "token": "inv_new90218390213",
                    "label": "Engineering Q3 Batch",
                    "url": "http://127.0.0.1:3000/join/inv_new90218390213",
                    "is_active": True,
                }
            },
            "description": "Created new invite link",
        },
        ("GET", "/api/admin/bin"): {
            "example": {
                "items": [
                    {
                        "id": 10,
                        "entity_type": "project",
                        "entity_id": 99,
                        "title": "Archived Legacy Project",
                        "deleted_at": "2026-08-10T12:00:00Z",
                        "deleted_by_name": "Admin User",
                    }
                ],
                "total": 1,
                "page": 1,
                "total_pages": 1,
            },
            "description": "Recycle bin items",
        },
        ("POST", "/api/admin/bin/{bin_id}/restore"): {
            "example": {"ok": True, "message": "Item restored successfully."},
            "description": "Item restored from recycle bin",
        },
        ("DELETE", "/api/admin/bin"): {
            "example": {"ok": True, "message": "Permanently deleted 5 item(s).", "deleted_count": 5},
            "description": "Purged all recycle bin items",
        },
        ("POST", "/api/admin/clear-database"): {
            "example": {"ok": True, "message": "All database data has been cleared.", "deleted_rows": 142},
            "description": "Database cleared (dev mode)",
        },

        # Attendance
        ("GET", "/api/attendance/today"): {
            "example": attendance_sample,
            "description": "Today's attendance check-in status",
        },
        ("POST", "/api/attendance/check-in"): {
            "example": {
                "ok": True,
                "message": "Checked in successfully at 09:00.",
                "record": attendance_sample,
            },
            "description": "Check-in recorded with selfie & geocoding",
        },
        ("POST", "/api/attendance/check-out"): {
            "example": {
                "ok": True,
                "message": "Checked out successfully at 17:30.",
                "record": attendance_sample,
            },
            "description": "Check-out recorded",
        },
        ("GET", "/api/attendance/overview"): {
            "example": {
                "records": [attendance_sample],
                "total_hours": 160.0,
                "days_present": 20,
                "days_late": 1,
                "days_absent": 0,
                "days_on_leave": 2,
            },
            "description": "30-day attendance overview & KPIs",
        },
        ("GET", "/api/attendance/calendar"): {
            "example": {
                "days": [
                    {"date": "2026-08-16", "status": "present", "hours": 8.5},
                    {"date": "2026-08-15", "status": "present", "hours": 8.0},
                    {"date": "2026-08-14", "status": "excused", "hours": 0.0},
                ]
            },
            "description": "Calendar monthly attendance status view",
        },
        ("GET", "/api/attendance/report"): {
            "example": {
                "report": [attendance_sample],
                "page": 1,
                "page_size": 30,
                "total": 150,
                "total_pages": 5,
            },
            "description": "Paginated attendance report",
        },
        ("PUT", "/api/attendance/{record_id}"): {
            "example": attendance_sample,
            "description": "Attendance record updated by mentor/admin",
        },
        ("POST", "/api/attendance/manual"): {
            "example": attendance_sample,
            "description": "Manual attendance record created",
        },
        ("POST", "/api/attendance/auto-checkout"): {
            "example": {"count": 2, "message": "Auto check-out applied to 2 missed record(s)."},
            "description": "Auto checkout sweep executed",
        },
        ("GET", "/api/attendance/my/export"): {
            "example": {"exported_at": "2026-08-21T12:00:00Z", "format": "csv", "filename": "my_attendance_JaneDoe_all_to_latest.csv"},
            "description": "Personal attendance CSV export for logged-in intern/user",
        },

        # Admin - Student Attendance
        ("GET", "/api/admin/students"): {
            "example": {
                "students": [student_overview_sample],
                "page": 1,
                "page_size": 20,
                "total": 35,
                "total_pages": 2,
                "filters": {"search": None, "department": None, "is_active": "true", "sort": "name", "window_days": 30},
            },
            "description": "Admin paginated intern list with 30-day attendance overview stats",
        },
        ("GET", "/api/admin/students/today"): {
            "example": {
                "today": "2026-08-21",
                "summary": {
                    "total_interns": 35,
                    "checked_in": 30,
                    "not_checked_in": 5,
                    "checked_out": 12,
                    "present": 25,
                    "late": 5,
                    "half_day": 0,
                    "absent": 0,
                    "on_leave": 2,
                    "excused": 0,
                    "attended": 30,
                    "attendance_rate": 85.7,
                },
                "students": [today_student_item_sample],
                "page": 1,
                "page_size": 20,
                "total": 35,
                "total_pages": 2,
                "filters": {"search": None, "department": None, "status": None, "is_active": "true"},
            },
            "description": "Admin today's live attendance breakdown and intern check-in status",
        },
        ("GET", "/api/admin/students/search"): {
            "example": {
                "students": [student_overview_sample],
                "date_range": {"start": "2026-07-22", "end": "2026-08-21"},
                "page": 1,
                "page_size": 20,
                "total": 1,
                "total_pages": 1,
                "filters": {"search": "Jane", "department": "Engineering", "is_active": "true", "sort": "name", "start": "2026-07-22", "end": "2026-08-21"},
            },
            "description": "Admin search students with custom date range attendance overview",
        },
        ("GET", "/api/admin/students/{user_id}/attendance"): {
            "example": {
                "student": {
                    "id": 1,
                    "name": "Jane Doe",
                    "email": "jane@techcorp.com",
                    "department": "Engineering",
                    "phone": "+91 9876543210",
                    "job_title": "Software Intern",
                    "is_active": True,
                    "joining_date": "2026-06-01",
                    "mentor_id": 2,
                    "mentor_name": "Dr. Sarah Connor",
                },
                "records": [attendance_sample],
                "monthly_summary": [monthly_summary_sample],
                "totals": {
                    "present": 15,
                    "late": 2,
                    "half_day": 0,
                    "absent": 0,
                    "on_leave": 1,
                    "excused": 0,
                    "total_hours": 136.5,
                    "total_days": 18,
                    "attended": 17,
                    "attendance_rate": 94.4,
                },
                "page": 1,
                "page_size": 31,
                "total": 18,
                "total_pages": 1,
                "filters": {"start": "2026-08-01", "end": "2026-08-21", "month": "2026-08", "status": None},
            },
            "description": "Admin full attendance records and monthly breakdown for specific intern",
        },
        ("GET", "/api/admin/students/export"): {
            "example": {"exported_at": "2026-08-21T12:00:00Z", "format": "csv", "filename": "attendance_export_2026-07-22_to_2026-08-21.csv"},
            "description": "Admin export attendance records as CSV with date filters",
        },

        # Mentor - Student Attendance
        ("GET", "/api/mentor/students"): {
            "example": {
                "students": [student_overview_sample],
                "page": 1,
                "page_size": 20,
                "total": 6,
                "total_pages": 1,
                "filters": {"search": None, "department": None, "is_active": "true", "sort": "name", "window_days": 30},
            },
            "description": "Mentor paginated assigned mentees with 30-day attendance overview stats",
        },
        ("GET", "/api/mentor/students/today"): {
            "example": {
                "today": "2026-08-21",
                "summary": {
                    "total_interns": 6,
                    "checked_in": 5,
                    "not_checked_in": 1,
                    "checked_out": 2,
                    "present": 4,
                    "late": 1,
                    "half_day": 0,
                    "absent": 0,
                    "on_leave": 0,
                    "excused": 0,
                    "attended": 5,
                    "attendance_rate": 83.3,
                },
                "students": [today_student_item_sample],
                "page": 1,
                "page_size": 20,
                "total": 6,
                "total_pages": 1,
                "filters": {"search": None, "department": None, "status": None, "is_active": "true"},
            },
            "description": "Mentor today's live attendance for assigned mentees",
        },
        ("GET", "/api/mentor/students/search"): {
            "example": {
                "students": [student_overview_sample],
                "date_range": {"start": "2026-07-22", "end": "2026-08-21"},
                "page": 1,
                "page_size": 20,
                "total": 1,
                "total_pages": 1,
                "filters": {"search": "Jane", "department": None, "is_active": "true", "sort": "name", "start": "2026-07-22", "end": "2026-08-21"},
            },
            "description": "Mentor search across assigned mentees with date range attendance overview",
        },
        ("GET", "/api/mentor/students/{user_id}/attendance"): {
            "example": {
                "student": {
                    "id": 1,
                    "name": "Jane Doe",
                    "email": "jane@techcorp.com",
                    "department": "Engineering",
                    "phone": "+91 9876543210",
                    "job_title": "Software Intern",
                    "is_active": True,
                    "joining_date": "2026-06-01",
                    "mentor_id": 2,
                    "mentor_name": "Dr. Sarah Connor",
                },
                "records": [attendance_sample],
                "monthly_summary": [monthly_summary_sample],
                "totals": {
                    "present": 15,
                    "late": 2,
                    "half_day": 0,
                    "absent": 0,
                    "on_leave": 1,
                    "excused": 0,
                    "total_hours": 136.5,
                    "total_days": 18,
                    "attended": 17,
                    "attendance_rate": 94.4,
                },
                "page": 1,
                "page_size": 31,
                "total": 18,
                "total_pages": 1,
                "filters": {"start": "2026-08-01", "end": "2026-08-21", "month": "2026-08", "status": None},
            },
            "description": "Mentor full attendance records for assigned mentee (403 if unassigned)",
        },
        ("GET", "/api/mentor/students/export"): {
            "example": {"exported_at": "2026-08-21T12:00:00Z", "format": "csv", "filename": "attendance_export_2026-07-22_to_2026-08-21.csv"},
            "description": "Mentor export attendance records for assigned mentees as CSV",
        },

        # Leave
        ("GET", "/api/leave/mine"): {
            "example": {
                "requests": [leave_sample],
                "balance": {"total": 12, "used": 3, "remaining": 9},
            },
            "description": "Current user's leave requests & balance",
        },
        ("POST", "/api/leave"): {
            "example": leave_sample,
            "description": "Leave request submitted",
        },
        ("GET", "/api/leave/all"): {
            "example": {
                "requests": [leave_sample],
                "page": 1,
                "page_size": 20,
                "total": 12,
                "total_pages": 1,
            },
            "description": "All submitted leave requests for review",
        },
        ("POST", "/api/leave/{leave_id}/review"): {
            "example": {**leave_sample, "status": "approved", "reviewer_name": "Dr. Sarah Connor"},
            "description": "Leave request reviewed (approved/rejected)",
        },
        ("GET", "/api/leave/balance"): {
            "example": {
                "total": 12,
                "used": 3,
                "remaining": 9,
                "leave_types": {"casual": 6, "sick": 4, "earned": 2},
            },
            "description": "Detailed leave balance summary",
        },

        # Projects & Tasks
        ("GET", "/api/projects"): {
            "example": {
                "projects": [project_sample],
                "page": 1,
                "total": 8,
                "total_pages": 1,
            },
            "description": "List of accessible projects",
        },
        ("POST", "/api/projects"): {
            "example": project_sample,
            "description": "Project created successfully",
        },
        ("GET", "/api/projects/{project_id}"): {
            "example": {
                **project_sample,
                "tasks": [task_sample],
                "can_edit": True,
            },
            "description": "Project details with task backlog and members",
        },
        ("PUT", "/api/projects/{project_id}"): {
            "example": project_sample,
            "description": "Project details updated",
        },
        ("DELETE", "/api/projects/{project_id}"): {
            "example": {"ok": True},
            "description": "Project moved to recycle bin",
        },
        ("POST", "/api/projects/{project_id}/assign"): {
            "example": {"ok": True},
            "description": "Intern assigned to project",
        },
        ("GET", "/api/projects/{project_id}/export"): {
            "example": {
                "project": project_sample,
                "members": [user_sample, mentor_sample],
                "tasks": [task_sample],
                "exported_at": "2026-08-16T12:00:00Z",
            },
            "description": "Project full export bundle",
        },
        ("POST", "/api/projects/{project_id}/tasks"): {
            "example": task_sample,
            "description": "Task created under project",
        },
        ("PUT", "/api/projects/tasks/{task_id}"): {
            "example": task_sample,
            "description": "Task updated",
        },
        ("PATCH", "/api/projects/tasks/{task_id}/status"): {
            "example": {**task_sample, "status": "done"},
            "description": "Task status changed",
        },
        ("DELETE", "/api/projects/tasks/{task_id}"): {
            "example": {"ok": True},
            "description": "Task deleted",
        },
        ("GET", "/api/projects/tasks/{task_id}/comments"): {
            "example": [
                {
                    "id": 1,
                    "task_id": 101,
                    "author_name": "Dr. Sarah Connor",
                    "author_role": "mentor",
                    "body": "Ensure similarity metrics use cosine distance.",
                    "created_at": "2026-08-16T11:00:00Z",
                }
            ],
            "description": "Task discussion comments",
        },
        ("POST", "/api/projects/tasks/{task_id}/comments"): {
            "example": {
                "id": 2,
                "task_id": 101,
                "author_name": "Jane Doe",
                "author_role": "intern",
                "body": "Added cosine similarity and benchmarked with 10k items.",
                "created_at": "2026-08-16T11:30:00Z",
            },
            "description": "Comment posted to task",
        },
        ("GET", "/api/projects/{project_id}/comments-board"): {
            "example": [
                {
                    "id": 1,
                    "project_id": 1,
                    "user_name": "Dr. Sarah Connor",
                    "user_role": "mentor",
                    "body": "Sprint goal: Finish vector pipeline by Friday.",
                    "created_at": "2026-08-16T09:00:00Z",
                }
            ],
            "description": "Project board discussion thread",
        },
        ("POST", "/api/projects/{project_id}/comments-board"): {
            "example": {
                "id": 2,
                "project_id": 1,
                "user_name": "Jane Doe",
                "user_role": "intern",
                "body": "On track for Friday delivery.",
                "created_at": "2026-08-16T09:45:00Z",
            },
            "description": "Project board message posted",
        },
        ("GET", "/api/projects/{project_id}/links"): {
            "example": [
                {
                    "id": 1,
                    "project_id": 1,
                    "link": "https://github.com/techcorp/vector-engine",
                    "remark": "Primary repository link",
                    "user_name": "Jane Doe",
                    "created_at": "2026-08-01T10:00:00Z",
                }
            ],
            "description": "Shared project links and resources",
        },
        ("POST", "/api/projects/{project_id}/links"): {
            "example": {
                "id": 2,
                "project_id": 1,
                "link": "https://docs.faiss.ai",
                "remark": "Faiss documentation and API reference",
                "user_name": "Jane Doe",
                "created_at": "2026-08-16T12:00:00Z",
            },
            "description": "Shared link added to project",
        },

        # Standup
        ("GET", "/api/standup"): {
            "example": {
                "logs": [standup_sample],
                "page": 1,
                "total": 24,
                "total_pages": 2,
            },
            "description": "Standup history log",
        },
        ("GET", "/api/standup/today"): {
            "example": standup_sample,
            "description": "Today's submitted standup",
        },
        ("POST", "/api/standup"): {
            "example": standup_sample,
            "description": "Daily standup submitted",
        },
        ("PUT", "/api/standup/{log_id}"): {
            "example": standup_sample,
            "description": "Standup entry updated",
        },
        ("DELETE", "/api/standup/{log_id}"): {
            "example": {"ok": True},
            "description": "Standup moved to recycle bin",
        },

        # Cohorts
        ("GET", "/api/cohorts"): {
            "example": [cohort_sample],
            "description": "Active cohorts",
        },
        ("POST", "/api/cohorts"): {
            "example": cohort_sample,
            "description": "Cohort created",
        },
        ("GET", "/api/cohorts/{cohort_id}"): {
            "example": cohort_sample,
            "description": "Cohort details with member list",
        },
        ("PUT", "/api/cohorts/{cohort_id}"): {
            "example": cohort_sample,
            "description": "Cohort details updated",
        },
        ("DELETE", "/api/cohorts/{cohort_id}"): {
            "example": {"ok": True},
            "description": "Cohort deleted",
        },
        ("POST", "/api/cohorts/{cohort_id}/members"): {
            "example": {"ok": True},
            "description": "Intern added to cohort",
        },

        # Announcements
        ("GET", "/api/announcements"): {
            "example": [announcement_sample],
            "description": "Announcements bulletin",
        },
        ("POST", "/api/announcements"): {
            "example": announcement_sample,
            "description": "Announcement published",
        },
        ("PUT", "/api/announcements/{ann_id}"): {
            "example": announcement_sample,
            "description": "Announcement updated",
        },
        ("DELETE", "/api/announcements/{ann_id}"): {
            "example": {"ok": True},
            "description": "Announcement moved to recycle bin",
        },

        # Profile & Reviews
        ("GET", "/api/profile"): {
            "example": user_sample,
            "description": "Current user profile",
        },
        ("PUT", "/api/profile"): {
            "example": user_sample,
            "description": "Profile updated",
        },
        ("POST", "/api/profile/change-password"): {
            "example": {
                "ok": True,
                "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                "message": "Password changed successfully.",
            },
            "description": "Password updated and new session token returned",
        },
        ("GET", "/api/reviews"): {
            "example": [review_sample],
            "description": "Performance reviews list",
        },
        ("POST", "/api/reviews"): {
            "example": review_sample,
            "description": "Performance review submitted",
        },
        ("GET", "/api/reviews/{review_id}"): {
            "example": review_sample,
            "description": "Performance review details",
        },
        ("PUT", "/api/reviews/{review_id}"): {
            "example": review_sample,
            "description": "Performance review updated",
        },
        ("DELETE", "/api/reviews/{review_id}"): {
            "example": {"ok": True},
            "description": "Performance review deleted",
        },

        # Dashboard, Notifications, Audit & Search
        ("GET", "/api/dashboard"): {
            "example": {
                "stats": {
                    "active_projects": 3,
                    "pending_tasks": 4,
                    "attendance_rate": "95%",
                    "unread_notifications": 2,
                },
                "recent_tasks": [task_sample],
                "announcements": [announcement_sample],
            },
            "description": "Personalized user role dashboard",
        },
        ("GET", "/api/notifications"): {
            "example": {
                "notifications": [notification_sample],
                "unread_count": 1,
            },
            "description": "User notification inbox",
        },
        ("POST", "/api/notifications/mark-read"): {
            "example": {"ok": True},
            "description": "Notifications marked as read",
        },
        ("GET", "/api/audit-logs"): {
            "example": {
                "logs": [audit_sample],
                "page": 1,
                "total": 240,
                "total_pages": 12,
            },
            "description": "System security & operation audit logs",
        },
        ("GET", "/api/search"): {
            "example": {
                "users": [user_sample],
                "projects": [project_sample],
                "tasks": [task_sample],
            },
            "description": "Global multi-entity search results",
        },

        # Multi-Tenant & Platform
        ("POST", "/api/platform/organizations"): {
            "example": {
                "ok": True,
                "organization": {
                    "id": 1,
                    "name": "Acme Technologies",
                    "slug": "acme",
                    "status": "active",
                },
            },
            "description": "Organization tenant created",
        },
        ("GET", "/api/platform/organizations"): {
            "example": [
                {
                    "id": 1,
                    "name": "Acme Technologies",
                    "slug": "acme",
                    "status": "active",
                    "created_at": "2026-01-01T00:00:00Z",
                }
            ],
            "description": "List all organization tenants",
        },
        ("PUT", "/api/platform/organizations/{org_id}/status"): {
            "example": {"ok": True, "status": "active"},
            "description": "Tenant status updated",
        },
        ("GET", "/api/org/profile"): {
            "example": {
                "id": 1,
                "name": "Acme Technologies",
                "slug": "acme",
                "industry": "Software & Internet",
                "website": "https://acme.example.com",
            },
            "description": "Organization tenant profile",
        },
        ("PUT", "/api/org/profile"): {
            "example": {"ok": True, "message": "Organization profile updated."},
            "description": "Organization profile saved",
        },
        ("GET", "/api/org/settings"): {
            "example": {
                "allow_intern_invites": True,
                "require_selfie_attendance": True,
                "geofencing_enabled": False,
            },
            "description": "Organization tenant settings",
        },
        ("PUT", "/api/org/settings"): {
            "example": {"ok": True, "message": "Settings updated."},
            "description": "Organization settings saved",
        },
        ("GET", "/api/org/members"): {
            "example": [
                {"user_id": 1, "name": "Jane Doe", "role": "intern"},
                {"user_id": 2, "name": "Dr. Sarah Connor", "role": "mentor"},
            ],
            "description": "Organization membership list",
        },
        ("POST", "/api/org/members"): {
            "example": {"ok": True, "message": "Member added to organization."},
            "description": "Member added to organization",
        },
    }

    # Enhance OpenAPI Paths
    for path, methods in schema.get("paths", {}).items():
        for method, operation in methods.items():
            method_upper = method.upper()
            lookup_key = (method_upper, path)

            # 0. Clean & Normalize Tags (e.g. 'api-auth' -> 'Authentication')
            if "tags" in operation:
                operation["tags"] = [TAG_NAMES_MAP.get(t, t.replace("api-", "").title()) for t in operation["tags"]]

            # 1. Clean up Request Body
            req_body = operation.get("requestBody")
            if req_body and "content" in req_body:
                json_content = req_body["content"].get("application/json")
                if json_content and "schema" in json_content:
                    s = json_content["schema"]
                    if "anyOf" in s:
                        # Extract the main component $ref or object schema
                        real_schemas = [item for item in s["anyOf"] if item.get("type") != "null"]
                        if real_schemas:
                            json_content["schema"] = real_schemas[0]

            # 2. Enrich Responses
            responses = operation.setdefault("responses", {})
            res_200 = responses.setdefault("200", {"description": "Successful Response"})
            content = res_200.setdefault("content", {})
            json_response = content.setdefault("application/json", {})

            # Match custom detailed response example & schema
            matched_custom = custom_responses.get(lookup_key)
            if not matched_custom:
                # Try prefix/generic matching
                if method_upper == "DELETE":
                    matched_custom = {"example": {"ok": True}, "description": "Operation successful"}
                elif "export" in path:
                    matched_custom = {"example": {"exported_at": "2026-08-16T12:00:00Z"}, "description": "Exported data payload"}
                else:
                    matched_custom = {"example": {"ok": True}, "description": "Successful Response"}

            if matched_custom:
                json_response["example"] = matched_custom.get("example", {"ok": True})
                res_200["description"] = matched_custom.get("description", "Successful Response")

                # Auto-generate or refine schema properties from example so Scalar renders the Model Tab too
                example_val = matched_custom.get("example")
                if isinstance(example_val, dict):
                    properties = {}
                    for k, v in example_val.items():
                        if isinstance(v, bool):
                            prop_type = "boolean"
                        elif isinstance(v, int):
                            prop_type = "integer"
                        elif isinstance(v, float):
                            prop_type = "number"
                        elif isinstance(v, list):
                            prop_type = "array"
                        elif isinstance(v, dict):
                            prop_type = "object"
                        else:
                            prop_type = "string"
                        properties[k] = {"type": prop_type, "example": v}

                    json_response["schema"] = {
                        "type": "object",
                        "title": f"{operation.get('summary', 'Response').replace(' ', '')}Response",
                        "properties": properties,
                    }
                elif isinstance(example_val, list):
                    json_response["schema"] = {
                        "type": "array",
                        "title": f"{operation.get('summary', 'Response').replace(' ', '')}ListResponse",
                        "items": {"type": "object"},
                    }

    app.openapi_schema = schema
    return app.openapi_schema
