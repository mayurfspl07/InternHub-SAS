import unittest
from datetime import date, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database import Base
from models import Notification, Project, Task, TaskStatus, User, UserRole
from utils import notify_overdue_tasks


class OverdueTaskNotificationTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.db = sessionmaker(bind=self.engine)()

        self.mentor = User(name="Mentor", email="mentor@overdue.test", role=UserRole.MENTOR, is_active=True)
        self.mentor.set_password("test-password-1")
        self.db.add(self.mentor)
        self.db.flush()

        self.intern = User(
            name="Intern",
            email="intern@overdue.test",
            role=UserRole.INTERN,
            is_active=True,
            mentor_id=self.mentor.id,
        )
        self.intern.set_password("test-password-1")
        self.db.add(self.intern)
        self.db.flush()

        self.project = Project(name="Test Project", mentor_id=self.mentor.id, status="active")
        self.db.add(self.project)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.engine.dispose()

    def _task(self, **kwargs) -> Task:
        defaults = dict(
            project_id=self.project.id,
            title="Ship the thing",
            assigned_to=self.intern.id,
            status=TaskStatus.TODO,
            deadline=date.today() - timedelta(days=1),
        )
        defaults.update(kwargs)
        task = Task(**defaults)
        self.db.add(task)
        self.db.commit()
        return task

    def _notifications_for(self, user_id: int) -> list[Notification]:
        return self.db.query(Notification).filter_by(user_id=user_id).all()

    def test_overdue_unassigned_status_notifies_intern_and_mentor(self):
        task = self._task()
        count = notify_overdue_tasks(self.db)
        self.assertEqual(count, 1)

        intern_notes = self._notifications_for(self.intern.id)
        mentor_notes = self._notifications_for(self.mentor.id)
        self.assertEqual(len(intern_notes), 1)
        self.assertEqual(len(mentor_notes), 1)
        self.assertIn(task.title, intern_notes[0].message)
        self.assertIn(self.project.name, intern_notes[0].message)
        self.assertIn(self.intern.name, mentor_notes[0].message)

        self.db.refresh(task)
        self.assertIsNotNone(task.overdue_notified_at)

    def test_does_not_renotify_the_same_task(self):
        self._task()
        notify_overdue_tasks(self.db)
        second_pass_count = notify_overdue_tasks(self.db)
        self.assertEqual(second_pass_count, 0)
        self.assertEqual(len(self._notifications_for(self.intern.id)), 1)

    def test_future_deadline_not_notified(self):
        self._task(deadline=date.today() + timedelta(days=3))
        count = notify_overdue_tasks(self.db)
        self.assertEqual(count, 0)
        self.assertEqual(self._notifications_for(self.intern.id), [])

    def test_completed_task_not_notified(self):
        self._task(status=TaskStatus.DONE)
        count = notify_overdue_tasks(self.db)
        self.assertEqual(count, 0)

    def test_unassigned_task_not_notified(self):
        self._task(assigned_to=None)
        count = notify_overdue_tasks(self.db)
        self.assertEqual(count, 0)

    def test_intern_without_mentor_only_notifies_intern(self):
        self.intern.mentor_id = None
        self.db.commit()
        self._task()
        notify_overdue_tasks(self.db)
        self.assertEqual(len(self._notifications_for(self.intern.id)), 1)
        self.assertEqual(len(self._notifications_for(self.mentor.id)), 0)


if __name__ == "__main__":
    unittest.main()
