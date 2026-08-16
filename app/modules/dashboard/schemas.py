"""Pydantic schemas and domain service for Dashboard Analytics."""
from pydantic import BaseModel


class DashboardStats(BaseModel):
    present_today: int = 0
    active_projects: int = 0
    total_projects: int = 0
    pending_leave: int = 0
    open_tasks: int = 0
    overdue_tasks: int = 0
    total_hours: float = 0.0
    days_logged: int = 0
    total_interns: int = 0


class DashboardResponse(BaseModel):
    stats: DashboardStats
    recent_activity: list[dict] = []
    projects: list[dict] = []
    attendance_overview: list[dict] = []
