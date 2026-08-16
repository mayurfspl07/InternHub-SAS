"""Task authorization policies."""
from app.core.tenant import CurrentContext
from app.modules.projects.policies import ProjectPolicy


class TaskPolicy:
    @staticmethod
    def can_view(ctx: CurrentContext, task: any, project: any) -> bool:
        return ProjectPolicy.can_view(ctx, project)

    @staticmethod
    def can_update(ctx: CurrentContext, task: any, project: any) -> bool:
        if ProjectPolicy.can_edit(ctx, project):
            return True
        return task.assigned_to == ctx.user.id

    @staticmethod
    def can_move_status(ctx: CurrentContext, task: any, project: any) -> bool:
        if TaskPolicy.can_update(ctx, task, project):
            return True
        return ctx.is_intern and ProjectPolicy.can_view(ctx, project)

    @staticmethod
    def can_delete(ctx: CurrentContext, task: any, project: any) -> bool:
        if ProjectPolicy.can_edit(ctx, project):
            return True
        return ctx.is_intern and task.created_by_id == ctx.user.id and ProjectPolicy.can_view(ctx, project)
