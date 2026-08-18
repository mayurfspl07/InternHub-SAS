"""Unified Role-Based Access Control (RBAC) permission registry."""
from app.core.constants import UserRole

# Standard Permission Grants by Role
ROLE_PERMISSIONS: dict[str, set[str]] = {
    UserRole.SUPERADMIN: {
        "org.manage",
        "members.manage",
        "attendance.view_all",
        "attendance.manage_all",
        "leave.view_all",
        "leave.review",
        "projects.manage_all",
        "tasks.manage_all",
        "cohorts.manage",
        "reviews.manage",
        "announcements.manage",
        "audit.view",
        "bin.manage",
        "platform.manage",
    },
    UserRole.ADMIN: {
        "org.manage",
        "members.manage",
        "attendance.view_all",
        "attendance.manage_all",
        "leave.view_all",
        "leave.review",
        "projects.manage_all",
        "tasks.manage_all",
        "cohorts.manage",
        "reviews.manage",
        "announcements.manage",
        "audit.view",
        "bin.manage",
    },
    UserRole.MENTOR: {
        "attendance.view_assigned",
        "attendance.manage_assigned",
        "leave.view_assigned",
        "leave.review_assigned",
        "projects.create",
        "projects.manage_assigned",
        "tasks.manage_assigned",
        "reviews.create",
        "announcements.create",
        "standups.view_assigned",
    },
    UserRole.INTERN: {
        "attendance.self_checkin",
        "attendance.view_own",
        "leave.request_own",
        "leave.view_own",
        "projects.view_assigned",
        "tasks.view_assigned",
        "tasks.update_assigned_status",
        "standups.create_own",
        "reviews.view_own",
        "announcements.view",
    },
}


def get_permissions_for_role(role: str) -> set[str]:
    """Retrieve the permission set granted to a workspace role."""
    return ROLE_PERMISSIONS.get(role, set()).copy()
