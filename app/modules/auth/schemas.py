"""Pydantic schemas for the Authentication domain."""
from pydantic import BaseModel, EmailStr


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    organization_name: str | None = None
    organization_slug: str | None = None


class TokenResponse(BaseModel):
    token: str
    token_type: str = "bearer"
    user_id: int
    name: str
    email: str
    role: str
    organization_id: int | None = None
    is_platform_admin: bool = False
