"""Data access repository for Tasks and Task Comments."""
from sqlalchemy import desc
from sqlalchemy.orm import Session, joinedload

from models import Task, TaskComment


class TaskRepository:
    def __init__(self, db: Session, org_id: int = 1):
        self.db = db
        self.org_id = org_id

    def get_by_id(self, task_id: int) -> Task | None:
        return (
            self.db.query(Task)
            .options(
                joinedload(Task.assignee),
                joinedload(Task.creator),
                joinedload(Task.comments).joinedload(TaskComment.author),
            )
            .filter(
                Task.id == task_id,
                Task.organization_id == self.org_id,
                Task.is_deleted == False,
            )
            .first()
        )

    def list_for_project(self, project_id: int) -> list[Task]:
        return (
            self.db.query(Task)
            .options(joinedload(Task.assignee), joinedload(Task.creator))
            .filter(
                Task.project_id == project_id,
                Task.organization_id == self.org_id,
                Task.is_deleted == False,
            )
            .order_by(desc(Task.created_at))
            .all()
        )

    def create(self, task: Task) -> Task:
        task.organization_id = self.org_id
        self.db.add(task)
        self.db.commit()
        self.db.refresh(task)
        return task

    def update(self, task: Task) -> Task:
        self.db.commit()
        self.db.refresh(task)
        return task
