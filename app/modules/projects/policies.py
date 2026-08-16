"""Project authorization policies."""
from app.core.tenant import CurrentContext


class ProjectPolicy:
    @staticmethod
    def can_view(ctx: CurrentContext, project: any) -> bool:
        if project.organization_id != ctx.organization.id:
            return False
        if ctx.is_admin:
            return True
        if ctx.is_mentor and (project.mentor_id == ctx.user.id or any(ma.user_id == ctx.user.id for ma in getattr(project, "mentor_assignments", []))):
            return True
        if ctx.is_intern and any(a.user_id == ctx.user.id for a in getattr(project, "assignments", [])):
            return True
        return False

    @staticmethod
    def can_edit(ctx: CurrentContext, project: any) -> bool:
        if project.organization_id != ctx.organization.id:
            return False
        if ctx.is_admin:
            return True
        if ctx.is_mentor and (project.mentor_id == ctx.user.id or any(ma.user_id == ctx.user.id for ma in getattr(project, "mentor_assignments", []))):
            return True
        return False
