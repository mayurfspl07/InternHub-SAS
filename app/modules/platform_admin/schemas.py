"""Pydantic schemas for the Platform Admin domain."""
from datetime import datetime
from pydantic import BaseModel


class PlatformStatsResponse(BaseModel):
    total_organizations: int = 0
    active_organizations: int = 0
    total_users: int = 0
    platform_admins: int = 0
    total_attendances: int = 0
    total_projects: int = 0
    total_tasks: int = 0


class TenantProvisionRequest(BaseModel):
    name: str
    slug: str
    admin_name: str
    admin_email: str
    admin_password: str
    type: str = "business"
    timezone: str = "Asia/Kolkata"
