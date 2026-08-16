"""Pydantic schemas for the Organizations domain."""
from datetime import datetime
from pydantic import BaseModel


class OrganizationCreateRequest(BaseModel):
    name: str
    slug: str
    type: str = "business"
    timezone: str = "Asia/Kolkata"
    logo_url: str | None = None


class OrganizationUpdateRequest(BaseModel):
    name: str | None = None
    type: str | None = None
    timezone: str | None = None
    logo_url: str | None = None


class OrganizationSettingsUpdateRequest(BaseModel):
    shift_start: str | None = None
    shift_end: str | None = None
    late_cutoff: str | None = None
    noon_cutoff: str | None = None
    checkin_block: str | None = None
    full_day_hours: float | None = None
    half_day_hours: float | None = None
    leave_quota_days: int | None = None
    advance_leave_days: int | None = None
    require_attendance_selfie: bool | None = None
    require_attendance_gps: bool | None = None
    auto_checkout_enabled: bool | None = None


class OrganizationResponse(BaseModel):
    id: int
    name: str
    slug: str
    type: str
    status: str
    timezone: str
    logo_url: str | None = None
    created_at: datetime | None = None

    class Config:
        from_attributes = True
