"""Pydantic schemas for the Users domain."""
from datetime import date, datetime
from pydantic import BaseModel, EmailStr


class UserCreateRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: str = "intern"
    department: str | None = None
    job_title: str | None = None
    joining_date: date | None = None


class UserUpdateRequest(BaseModel):
    name: str | None = None
    department: str | None = None
    job_title: str | None = None
    role: str | None = None
    is_active: bool | None = None


class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    role: str
    department: str | None = None
    job_title: str | None = None
    is_active: bool
    is_platform_admin: bool = False
    joining_date: date | None = None
    created_at: datetime | None = None

    class Config:
        from_attributes = True
