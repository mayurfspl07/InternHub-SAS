"""Unified API router aggregating all domain sub-routers under /api."""
from fastapi import APIRouter

from routes.api import (
    admin,
    announcements,
    attendance,
    audit,
    auth,
    cohorts,
    dashboard,
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
api_router.include_router(cohorts.router)
api_router.include_router(dashboard.router)
api_router.include_router(notifications.router)
api_router.include_router(profile.router)
api_router.include_router(reviews.router)
api_router.include_router(search.router)
api_router.include_router(standup.router)
api_router.include_router(student_attendance.router)
api_router.include_router(users.router)
