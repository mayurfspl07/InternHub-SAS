"""Pydantic schemas for the Attendance domain."""
from datetime import date, datetime, time
from pydantic import BaseModel


class CheckInRequest(BaseModel):
    latitude: float | None = None
    longitude: float | None = None
    selfie_url: str | None = None
    selfie_key: str | None = None
    notes: str | None = None


class CheckOutRequest(BaseModel):
    latitude: float | None = None
    longitude: float | None = None
    notes: str | None = None


class ManualAttendanceCreateRequest(BaseModel):
    user_id: int
    date: date
    status: str
    check_in: time | None = None
    check_out: time | None = None
    reason: str


class AttendanceResponse(BaseModel):
    id: int
    user_id: int
    user_name: str | None = None
    date: date
    check_in: datetime | None = None
    check_out: datetime | None = None
    status: str
    hours_worked: float | None = None
    address: str | None = None
    selfie_url: str | None = None

    class Config:
        from_attributes = True
