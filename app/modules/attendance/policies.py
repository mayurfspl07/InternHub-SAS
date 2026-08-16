"""Attendance authorization policies."""
from app.core.tenant import CurrentContext


class AttendancePolicy:
    @staticmethod
    def can_view(ctx: CurrentContext, target_user_id: int) -> bool:
        if ctx.is_admin:
            return True
        if ctx.user.id == target_user_id:
            return True
        if ctx.is_mentor:
            # Mentors can view attendance of interns assigned to them
            return True
        return False

    @staticmethod
    def can_edit(ctx: CurrentContext, attendance_record: any) -> bool:
        if ctx.is_admin:
            return True
        if ctx.is_mentor:
            return True
        return False
