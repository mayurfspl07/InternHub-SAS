"""Data access repository for Projects and Project Assignments."""
from sqlalchemy import desc
from sqlalchemy.orm import Session, joinedload

from models import Project, ProjectAssignment, ProjectMentorAssignment


class ProjectRepository:
    def __init__(self, db: Session, org_id: int = 1):
        self.db = db
        self.org_id = org_id

    def get_by_id(self, project_id: int) -> Project | None:
        return (
            self.db.query(Project)
            .options(
                joinedload(Project.mentor),
                joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
                joinedload(Project.tasks),
                joinedload(Project.assignments).joinedload(ProjectAssignment.user),
            )
            .filter(
                Project.id == project_id,
                Project.organization_id == self.org_id,
                Project.is_deleted == False,
            )
            .first()
        )

    def list_all(self) -> list[Project]:
        return (
            self.db.query(Project)
            .options(
                joinedload(Project.mentor),
                joinedload(Project.mentor_assignments).joinedload(ProjectMentorAssignment.user),
                joinedload(Project.assignments).joinedload(ProjectAssignment.user),
            )
            .filter(
                Project.organization_id == self.org_id,
                Project.is_deleted == False,
            )
            .order_by(desc(Project.created_at))
            .all()
        )

    def create(self, project: Project) -> Project:
        project.organization_id = self.org_id
        self.db.add(project)
        self.db.commit()
        self.db.refresh(project)
        return project

    def update(self, project: Project) -> Project:
        self.db.commit()
        self.db.refresh(project)
        return project
