"""Pydantic schemas for the Projects domain."""
from datetime import date, datetime
from pydantic import BaseModel


class ProjectCreateRequest(BaseModel):
    name: str
    description: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    status: str = "planning"
    mentor_id: int | None = None
    mentor_ids: list[int] | None = None
    intern_ids: list[int] | None = None


class ProjectUpdateRequest(BaseModel):
    name: str | None = None
    description: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    status: str | None = None
    mentor_ids: list[int] | None = None
    intern_ids: list[int] | None = None


class ProjectResponse(BaseModel):
    id: int
    name: str
    description: str | None = None
    status: str
    start_date: date | None = None
    end_date: date | None = None
    mentor_id: int | None = None
    mentor_ids: list[int] = []
    created_at: datetime | None = None

    class Config:
        from_attributes = True
