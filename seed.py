"""Seed script to populate database with realistic demo data for 10 mentors and 100 interns."""
import random
import os
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from sqlalchemy.orm import Session

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from database import SessionLocal, Base, engine
from models import (
    User, UserRole, Project, ProjectStatus, ProjectAssignment,
    ProjectMentorAssignment, Task, TaskStatus, TaskPriority,
    TaskComment, Attendance, AttendanceStatus, LeaveRequest,
    LeaveStatus, LeaveType, StandupLog, Announcement, PerformanceReview,
    Cohort, CohortMember, InternInviteLink, ProjectComment, ProjectLink
)
from utils import clear_all_database_data, determine_status

# Define standard seed password
PASSWORD = "demo-password-123"

DEPARTMENTS = ["Engineering", "Product Management", "Quality Assurance", "Design", "DevOps"]
SKILLS_POOL = ["Python", "React", "SQL", "Docker", "FastAPI", "Tailwind", "Git", "TypeScript", "Node.js", "GraphQL"]
MOODS = ["Happy", "Productive", "Good", "Tired", "Stressed", "Motivated"]
LEAVE_REASONS = ["Fever and cold", "Family wedding", "College exams", "Personal work", "Doctor appointment"]
STANDUP_DIDS = [
    "Fixed styling issues in the responsive navbar and wrote unit tests.",
    "Integrated the dashboard charts with the live backend analytics API.",
    "Setup Docker container orchestration config and optimized queries.",
    "Drafted user flows for task assignments and resolved review feedback.",
    "Investigated memory leaks in WebSocket connections and optimized memory usage."
]
STANDUP_PLANS = [
    "Implement task status drag-and-drop board on the frontend.",
    "Conduct code review for the auth endpoints and merge pull requests.",
    "Write documentation for the database schema migrations.",
    "Design performance dashboard visual assets.",
    "Optimize page load performance and run end-to-end tests."
]
STANDUP_BLOCKERS = [
    None, None, None, None,
    "Waiting for the UI mockups to be finalized.",
    "API backend endpoints are returning intermittent 500 errors.",
    "Blocked by local network proxy issues."
]

def get_weekdays(start: date, count: int) -> list[date]:
    """Get list of past weekdays starting from `start` backwards."""
    days = []
    curr = start
    while len(days) < count:
        if curr.weekday() < 5:  # Monday to Friday
            days.append(curr)
        curr -= timedelta(days=1)
    return days

def seed():
    print("[INFO] Wiping all existing tables...")
    db = SessionLocal()
    try:
        from sqlalchemy import text
        db.execute(text("SET FOREIGN_KEY_CHECKS = 0"))
        clear_all_database_data(db, preserve_admin_users=False)
        db.execute(text("SET FOREIGN_KEY_CHECKS = 1"))
        db.commit()
        print("[OK] All data cleared.")

        print("\n[INFO] Seeding System Admin...")
        admin_email = os.environ.get("BOOTSTRAP_ADMIN_EMAIL", "admin@internhub.dev").strip().lower()
        admin_password = os.environ.get("BOOTSTRAP_ADMIN_PASSWORD", "Imp@pune1")
        admin_name = os.environ.get("BOOTSTRAP_ADMIN_NAME", "Admin")

        admin = User(
            name=admin_name,
            email=admin_email,
            role=UserRole.ADMIN,
            is_active=True,
            department="Operations",
            job_title="Operations Lead"
        )
        admin.set_password(admin_password)
        db.add(admin)
        db.flush()

        print("[INFO] Seeding 10 Mentors...")
        mentors = []
        for i in range(1, 11):
            mentor = User(
                name=f"Mentor {i}",
                email=f"mentor{i}@demo.com",
                role=UserRole.MENTOR,
                is_active=True,
                department=DEPARTMENTS[(i - 1) % len(DEPARTMENTS)],
                job_title=f"Senior {DEPARTMENTS[(i - 1) % len(DEPARTMENTS)]} Engineer",
                joining_date=date.today() - timedelta(days=random.randint(200, 500))
            )
            mentor.set_password(PASSWORD)
            db.add(mentor)
            mentors.append(mentor)
        db.flush()

        print("[INFO] Seeding 100 Interns (distributed among mentors)...")
        interns = []
        for i in range(1, 101):
            assigned_mentor = mentors[(i - 1) % len(mentors)]
            skills = ", ".join(random.sample(SKILLS_POOL, random.randint(2, 4)))
            joining_days_ago = random.randint(15, 60)
            intern = User(
                name=f"Intern {i}",
                email=f"intern{i}@demo.com",
                role=UserRole.INTERN,
                is_active=True,
                mentor_id=assigned_mentor.id,
                department=assigned_mentor.department,
                skills=skills,
                job_title=f"Intern - {assigned_mentor.department}",
                joining_date=date.today() - timedelta(days=joining_days_ago)
            )
            intern.set_password(PASSWORD)
            db.add(intern)
            interns.append(intern)
        db.flush()

        print("[INFO] Seeding Projects...")
        projects = []
        proj_names = [
            ("Mobile App Revamp", ProjectStatus.ACTIVE, 30),
            ("Data Analytics Dashboard", ProjectStatus.ACTIVE, 45),
            ("Cloud Infrastructure Migration", ProjectStatus.PLANNING, 10),
            ("Security Audit & Hardening", ProjectStatus.COMPLETED, 90),
            ("Internal Portal UX Design", ProjectStatus.ON_HOLD, 60)
        ]
        for name, status, start_days_ago in proj_names:
            proj = Project(
                name=name,
                description=f"A crucial project to deliver {name.lower()} features.",
                status=status,
                start_date=date.today() - timedelta(days=start_days_ago),
                end_date=date.today() + timedelta(days=60) if status != ProjectStatus.COMPLETED else date.today()
            )
            db.add(proj)
            projects.append(proj)
        db.flush()

        print("[INFO] Assigning Mentors and Interns to Projects...")
        # Mobile app gets mentors 1-2, Dashboard gets 3-4, etc.
        for idx, proj in enumerate(projects):
            # Assign mentors
            m1 = mentors[(idx * 2) % len(mentors)]
            m2 = mentors[(idx * 2 + 1) % len(mentors)]
            db.add(ProjectMentorAssignment(project_id=proj.id, user_id=m1.id))
            db.add(ProjectMentorAssignment(project_id=proj.id, user_id=m2.id))
            
            # Assign interns (each project gets ~25 interns)
            raw_interns = interns[idx*20 : (idx+1)*20] + interns[(idx+5)*10 : (idx+5)*10+5]
            assigned_interns = list({intern.id: intern for intern in raw_interns}.values())
            for intern in assigned_interns:
                db.add(ProjectAssignment(project_id=proj.id, user_id=intern.id))
        db.flush()

        print("[INFO] Seeding Cohorts...")
        cohort1 = Cohort(name="Summer Cohort 2026", description="First batch of 2026 interns", start_date=date.today() - timedelta(days=30), is_active=True, created_by_id=admin.id)
        cohort2 = Cohort(name="Autumn Cohort 2026", description="Fall batch of 2026 interns", start_date=date.today() + timedelta(days=60), is_active=True, created_by_id=admin.id)
        db.add(cohort1)
        db.add(cohort2)
        db.flush()

        # Assign interns to Cohorts
        for idx, intern in enumerate(interns):
            if idx < 50:
                db.add(CohortMember(cohort_id=cohort1.id, user_id=intern.id))
            else:
                db.add(CohortMember(cohort_id=cohort2.id, user_id=intern.id))
        db.flush()

        print("[INFO] Seeding Tasks & Comments...")
        for proj in projects:
            assigned_intern_ids = [r[0] for r in db.query(ProjectAssignment.user_id).filter_by(project_id=proj.id).all()]
            if not assigned_intern_ids:
                continue
                
            for j in range(1, 11):
                assignee_id = random.choice(assigned_intern_ids)
                task_status = random.choice([TaskStatus.TODO, TaskStatus.IN_PROGRESS, TaskStatus.TESTING, TaskStatus.DONE])
                task = Task(
                    project_id=proj.id,
                    title=f"Task {j} - Configure {proj.name}",
                    description=f"Detailed specifications for executing task {j} on project {proj.name}.",
                    assigned_to=assignee_id,
                    deadline=date.today() + timedelta(days=random.randint(-5, 10)),
                    status=task_status,
                    priority=random.choice([TaskPriority.LOW, TaskPriority.MEDIUM, TaskPriority.HIGH])
                )
                db.add(task)
                db.flush()

                # Add some comments on random tasks
                if random.random() < 0.4:
                    commenter_id = random.choice([assignee_id, admin.id])
                    db.add(TaskComment(
                        task_id=task.id,
                        user_id=commenter_id,
                        body=f"Progress check: Working on fixing tests. Will update soon."
                    ))
        db.commit()

        print("[INFO] Seeding Project Collaboration Comments & Links...")
        for proj in projects:
            assigned_intern_ids = [r[0] for r in db.query(ProjectAssignment.user_id).filter_by(project_id=proj.id).all()]
            if not assigned_intern_ids:
                continue
            
            # Seed 2 comments per project
            intern_commenter_id = random.choice(assigned_intern_ids)
            db.add(ProjectComment(
                project_id=proj.id,
                user_id=intern_commenter_id,
                body=f"Hi everyone, let's keep all project task requirements updated on this board!"
            ))
            db.add(ProjectComment(
                project_id=proj.id,
                user_id=proj.mentor_id or admin.id,
                body=f"Acknowledged. Let's use this board for announcements and checking links."
            ))

            # Seed 2 document links per project
            db.add(ProjectLink(
                project_id=proj.id,
                user_id=intern_commenter_id,
                link="https://github.com/project-alpha/docs",
                remark="Project Documentation Wiki"
            ))
            db.add(ProjectLink(
                project_id=proj.id,
                user_id=proj.mentor_id or admin.id,
                link="https://figma.com/file/project-alpha-design",
                remark="Design Mockups"
            ))
        db.commit()

        print("[INFO] Seeding 14 Days Attendance Records for all 100 interns...")
        # Get past 14 weekdays starting from yesterday
        past_weekdays = get_weekdays(date.today() - timedelta(days=1), 14)
        
        for intern in interns:
            # Let's seed attendance for each weekday since they joined
            joining_date = intern.joining_date or (date.today() - timedelta(days=30))
            valid_days = [d for d in past_weekdays if d >= joining_date]
            
            for d in valid_days:
                rand = random.random()
                
                # 80% Present, 10% Late, 5% Half-day, 3% Absent, 2% leave
                if rand < 0.80:
                    status = AttendanceStatus.PRESENT
                    check_in_h, check_in_m = random.randint(9, 10), random.randint(0, 25)
                    check_out_h, check_out_m = random.randint(18, 19), random.randint(0, 59)
                elif rand < 0.90:
                    status = AttendanceStatus.LATE
                    check_in_h, check_in_m = random.randint(10, 12), random.randint(31, 59)
                    check_out_h, check_out_m = random.randint(18, 20), random.randint(0, 30)
                elif rand < 0.95:
                    status = AttendanceStatus.HALF_DAY
                    check_in_h, check_in_m = 10, 0
                    check_out_h, check_out_m = 15, 30  # 5.5 hours worked
                elif rand < 0.98:
                    status = AttendanceStatus.ABSENT
                    # missed check-out
                    check_in_h, check_in_m = 10, 0
                    check_out_h, check_out_m = 19, 0
                else:
                    status = AttendanceStatus.ON_LEAVE
                    check_in_h, check_in_m = 0, 0
                    check_out_h, check_out_m = 0, 0

                check_in_dt = datetime.combine(d, time(check_in_h, check_in_m))
                check_out_dt = datetime.combine(d, time(check_out_h, check_out_m)) if check_out_h > 0 else None
                
                if status == AttendanceStatus.ON_LEAVE:
                    att = Attendance(
                        user_id=intern.id,
                        date=d,
                        check_in=datetime.combine(d, time(10, 0)),
                        check_out=datetime.combine(d, time(19, 0)),
                        status=AttendanceStatus.ON_LEAVE,
                        notes="Approved Casual Leave",
                        hours_worked=0.0
                    )
                elif status == AttendanceStatus.ABSENT:
                    # simulate missed checkout
                    att = Attendance(
                        user_id=intern.id,
                        date=d,
                        check_in=check_in_dt,
                        check_out=check_out_dt,
                        checkout_source="auto",
                        checkout_missed=True,
                        status=AttendanceStatus.ABSENT,
                        hours_worked=0.0
                    )
                else:
                    hours = round((check_out_dt - check_in_dt).total_seconds() / 3600.0, 2)
                    resolved_status = determine_status(check_in_dt.time(), Decimal(str(hours)), False)
                    att = Attendance(
                        user_id=intern.id,
                        date=d,
                        check_in=check_in_dt,
                        check_out=check_out_dt,
                        status=resolved_status,
                        hours_worked=hours
                    )
                db.add(att)
        db.commit()

        print("[INFO] Seeding Leave Requests...")
        for intern in interns[:30]:  # Only seed leaves for first 30 interns
            # 1 past leave, 1 future leave
            past_start = date.today() - timedelta(days=random.randint(5, 12))
            past_end = past_start + timedelta(days=random.randint(0, 2))
            
            db.add(LeaveRequest(
                user_id=intern.id,
                start_date=past_start,
                end_date=past_end,
                reason=random.choice(LEAVE_REASONS),
                leave_type=random.choice([LeaveType.CASUAL, LeaveType.SICK]),
                status=random.choice([LeaveStatus.APPROVED, LeaveStatus.REJECTED]),
                reviewed_by=mentors[0].id,
                reviewed_at=datetime.now()
            ))

            future_start = date.today() + timedelta(days=random.randint(2, 10))
            future_end = future_start + timedelta(days=random.randint(0, 2))
            db.add(LeaveRequest(
                user_id=intern.id,
                start_date=future_start,
                end_date=future_end,
                reason=random.choice(LEAVE_REASONS),
                leave_type=random.choice([LeaveType.CASUAL, LeaveType.SICK]),
                status=LeaveStatus.PENDING
            ))
        db.commit()

        print("[INFO] Seeding Standup Logs for all 100 interns (last 5 weekdays)...")
        past_5_weekdays = get_weekdays(date.today() - timedelta(days=1), 5)
        for intern in interns:
            joining_date = intern.joining_date or (date.today() - timedelta(days=30))
            valid_days = [d for d in past_5_weekdays if d >= joining_date]
            
            for d in valid_days:
                db.add(StandupLog(
                    user_id=intern.id,
                    date=d,
                    did=random.choice(STANDUP_DIDS),
                    plan=random.choice(STANDUP_PLANS),
                    blockers=random.choice(STANDUP_BLOCKERS),
                    mood=random.choice(MOODS),
                    created_at=datetime.combine(d, time(18, random.randint(0, 59)))
                ))
        db.commit()

        print("[INFO] Seeding Announcements...")
        db.add(Announcement(title="Welcome to InternHub Workspace!", body="Welcome cohorts! Please review the wiki pages and ensure you check-in daily.", is_pinned=True, author_id=admin.id))
        db.add(Announcement(title="Daily Standups Reminder", body="Reminder to fill in your standup logs on the dashboard daily before 6 PM.", is_pinned=False, author_id=admin.id))
        db.add(Announcement(title="Project Launch Meeting", body="Mandatory meeting for all interns working on Mobile App Revamp at 3 PM today.", is_pinned=False, project_id=projects[0].id, author_id=mentors[0].id))
        db.commit()

        print("[INFO] Seeding Performance Reviews...")
        for intern in interns[:20]:  # Seed reviews for first 20 interns
            db.add(PerformanceReview(
                intern_id=intern.id,
                reviewer_id=intern.mentor_id,
                project_id=projects[0].id,
                period="Q3 2026 Evaluation",
                rating=random.randint(3, 5),
                technical_rating=random.randint(3, 5),
                communication_rating=random.randint(3, 5),
                initiative_rating=random.randint(3, 5),
                feedback="Excellent execution of tasks. Always communicative and cooperative in standups.",
                strengths="Technically sound and proactive coder.",
                improvements="Work on documentation standards."
            ))
        db.commit()

        print("[INFO] Seeding Intern Invite Links...")
        db.add(InternInviteLink(token="summer-batch-invite-token", label="Summer Batch Link", created_by_id=admin.id, mentor_id=mentors[0].id, is_active=True))
        db.add(InternInviteLink(token="qa-department-invite-token", label="QA Team Link", created_by_id=admin.id, mentor_id=mentors[1].id, is_active=True))
        db.commit()

        print("\n" + "="*50)
        print("[OK] Seeding complete! Database successfully populated.")
        print("="*50)
        print("Login accounts summary:")
        print(f"  System Admin : {admin_email} / {admin_password}")
        print("  10 Mentors   : mentor1@demo.com  to  mentor10@demo.com  / demo-password-123")
        print("  100 Interns  : intern1@demo.com  to  intern100@demo.com  / demo-password-123")
        print("="*50)

    except Exception as exc:
        db.rollback()
        print(f"[ERROR] Seeding failed: {exc}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed()
