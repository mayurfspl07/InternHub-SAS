"""Pydantic schemas for the Tasks domain."""
from datetime import date, datetime
from pydantic import BaseModel


class TaskCreateRequest(BaseModel):
    title: str
    description: str | None = None
    project_id: int
    assigned_to: int | None = None
    priority: str = "medium"
    status: str = "todo"
    deadline: date | None = None


class TaskUpdateRequest(BaseModel):
    title: str | None = None
    description: str | None = None
    assigned_to: int | None = None
    priority: str | None = None
    status: str | None = None
    deadline: date | None = None


class TaskStatusMoveRequest(BaseModel):
    status: str


class TaskResponse(BaseModel):
    id: int
    title: str
    description: str | None = None
    project_id: int
    assigned_to: int | None = None
    created_by_id: int | None = None
    priority: str
    status: str
    deadline: date | None = None
    created_at: datetime | None = None

    class Config:
        from_attributes = True
