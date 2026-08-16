"""Pydantic schemas for the Notifications domain."""
from datetime import datetime
from pydantic import BaseModel


class NotificationResponse(BaseModel):
    id: int
    user_id: int
    title: str
    message: str
    type: str = "info"
    link: str | None = None
    is_read: bool = False
    created_at: datetime | None = None

    class Config:
        from_attributes = True


class NotificationMarkReadRequest(BaseModel):
    notification_ids: list[int] | None = None
