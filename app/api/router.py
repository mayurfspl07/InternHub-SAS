"""Unified API router aggregating all domain sub-routers under /api."""
from fastapi import APIRouter

from routes.api import (
    admin,
    announcements,
    attendance,
    audit,
    auth,
    blogs,
    cohorts,
    dashboard,
    leads,
    leave,
    notifications,
    org,
    platform,
    profile,
    projects,
    reviews,
    search,
    standup,
    student_attendance,
    users,
)

api_router = APIRouter()

# Register all domain routers
api_router.include_router(auth.router)
api_router.include_router(platform.router)
api_router.include_router(org.router)
api_router.include_router(admin.router)
api_router.include_router(attendance.router)
api_router.include_router(leave.router)
api_router.include_router(projects.router)
api_router.include_router(projects.task_router)
api_router.include_router(audit.router)
api_router.include_router(announcements.router)
api_router.include_router(blogs.router)
api_router.include_router(blogs.sitemap_router)
api_router.include_router(leads.router)
api_router.include_router(leads.platform_router)
api_router.include_router(cohorts.router)
api_router.include_router(dashboard.router)
api_router.include_router(dashboard.admin_dashboard_router)
api_router.include_router(dashboard.mentor_dashboard_router)
api_router.include_router(dashboard.intern_dashboard_router)
api_router.include_router(dashboard.superadmin_dashboard_router)
api_router.include_router(dashboard.root_admin_dashboard_router)
api_router.include_router(dashboard.root_mentor_dashboard_router)
api_router.include_router(dashboard.root_intern_dashboard_router)
api_router.include_router(dashboard.root_superadmin_dashboard_router)
api_router.include_router(notifications.router)
api_router.include_router(profile.router)
api_router.include_router(reviews.router)
api_router.include_router(search.router)
api_router.include_router(standup.router)
api_router.include_router(student_attendance.router)
api_router.include_router(student_attendance.admin_attendance_router)
api_router.include_router(student_attendance.mentor_router)
api_router.include_router(student_attendance.mentor_attendance_router)
api_router.include_router(users.router)
