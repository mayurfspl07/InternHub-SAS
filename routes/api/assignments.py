"""JSON assignment and submission endpoints for mentors and interns."""
from datetime import date, datetime, timezone
import os
from typing import Annotated

from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_, and_, func

from config import Config
from database import get_db
from dependencies import get_optional_user
from models import (
    Assignment,
    AssignmentStatus,
    AssignmentSubmission,
    AssignmentSubmissionStatus,
    Cohort,
    CohortMember,
    Project,
    ProjectAssignment,
    User,
    UserRole,
    _utcnow,
)
from utils import (
    attachment_abs_path,
    isoformat_utc,
    push_notification,
    record_audit,
    save_assignment_attachment,
    save_submission_file,
)
from app.core.pagination import get_page_params
from app.core.sanitize import validate_http_url
from routes.api.schemas import (
    AssignmentCreatePayload,
    AssignmentUpdatePayload,
    AssignmentSubmitPayload,
    AssignmentReviewPayload,
    get_payload,
)
from tenancy import ensure_cohort_in_org, ensure_in_org, ensure_project_in_org, ensure_user_in_org

router = APIRouter(prefix="/api/assignments", tags=["Assignments"])
DbSession = Annotated[Session, Depends(get_db)]


def _resolve_org_id(request: Request, user: User, db: Session) -> int:
    from dependencies import _resolve_request_org_id
    return _resolve_request_org_id(request, user, db) or 1


def _assignment_to_dict(a: Assignment, user: User | None = None, db: Session | None = None) -> dict:
    data = a.to_dict()
    # If requesting user is intern, attach their submission status if exists
    if user and user.role == UserRole.INTERN and db:
        sub = (
            db.query(AssignmentSubmission)
            .filter_by(assignment_id=a.id, user_id=user.id)
            .order_by(AssignmentSubmission.id.desc())
            .first()
        )
        data["my_submission"] = sub.to_dict() if sub else None
        data["has_submitted"] = sub is not None
        data["is_submitted"] = sub is not None
        data["submission_status"] = sub.status if sub else "not_submitted"
        data["my_score"] = sub.score if sub else None
    elif db:
        # Total submissions count for mentors/admins
        sub_count = db.query(AssignmentSubmission).filter_by(assignment_id=a.id).count()
        reviewed_count = (
            db.query(AssignmentSubmission)
            .filter(
                AssignmentSubmission.assignment_id == a.id,
                AssignmentSubmission.status.in_([AssignmentSubmissionStatus.APPROVED, AssignmentSubmissionStatus.REJECTED]),
            )
            .count()
        )
        data["submissions_count"] = sub_count
        data["submission_count"] = sub_count
        data["graded_count"] = reviewed_count
        data["reviewed_count"] = reviewed_count
        data["pending_review_count"] = sub_count - reviewed_count
    return data


def _clean_param_int(val, default: int = 1) -> int:
    if hasattr(val, "default"):
        val = val.default
    try:
        return max(1, int(val))
    except (TypeError, ValueError):
        return default


def _clean_param_str(val) -> str | None:
    if hasattr(val, "default"):
        val = val.default
    if val is None:
        return None
    s = str(val).strip()
    return s if s else None


# ==============================================================================
# Assignments List & Create
# ==============================================================================
@router.get("")
@router.get("/")
async def list_assignments(
    request: Request,
    db: DbSession,
    status: str | None = None,
    project_id: int | None = None,
    cohort_id: int | None = None,
    assigned_to_user_id: int | None = None,
    search: str | None = None,
    page: int = 1,
    page_size: int = 20,
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    org_id = _resolve_org_id(request, user, db)
    query = (
        db.query(Assignment)
        .options(
            joinedload(Assignment.created_by),
            joinedload(Assignment.project),
            joinedload(Assignment.cohort),
            joinedload(Assignment.assigned_to_user),
        )
        .filter(
            ((Assignment.organization_id == 1) | (Assignment.organization_id.is_(None))) if org_id == 1 else (Assignment.organization_id == org_id),
            Assignment.is_deleted == False,
        )
    )
    st = _clean_param_str(status)
    if st:
        query = query.filter(Assignment.status == st.lower())

    if project_id and not hasattr(project_id, "default"):
        query = query.filter(Assignment.project_id == int(project_id))

    if cohort_id and not hasattr(cohort_id, "default"):
        query = query.filter(Assignment.cohort_id == int(cohort_id))

    if assigned_to_user_id and not hasattr(assigned_to_user_id, "default"):
        query = query.filter(Assignment.assigned_to_user_id == int(assigned_to_user_id))

    s = _clean_param_str(search)
    if s:
        search_pattern = f"%{s}%"
        query = query.filter(or_(Assignment.title.ilike(search_pattern), Assignment.description.ilike(search_pattern)))

    if user.role == UserRole.INTERN:
        user_proj_ids = [
            pa.project_id
            for pa in db.query(ProjectAssignment).filter_by(user_id=user.id).all()
        ]
        user_cohort_ids = [
            cm.cohort_id
            for cm in db.query(CohortMember).filter_by(user_id=user.id).all()
        ]
        intern_filters = [
            Assignment.assigned_to_user_id == user.id,
            and_(
                Assignment.project_id == None,
                Assignment.cohort_id == None,
                Assignment.assigned_to_user_id == None,
            ),
        ]
        if user_proj_ids:
            intern_filters.append(
                and_(Assignment.project_id.in_(user_proj_ids), Assignment.assigned_to_user_id == None)
            )
        if user_cohort_ids:
            intern_filters.append(
                and_(Assignment.cohort_id.in_(user_cohort_ids), Assignment.assigned_to_user_id == None)
            )
        query = query.filter(
            or_(*intern_filters),
            Assignment.status != AssignmentStatus.DRAFT,
        )

    p, ps = get_page_params(request, default_page_size=20)
    total = query.count()
    assignments = query.order_by(Assignment.created_at.desc()).offset((p - 1) * ps).limit(ps).all()
    paginated_items = [
        _assignment_to_dict(a, user=user, db=db) for a in assignments
    ]

    # Aggregate status counts (same visibility scope as the list, before the
    # status/project/search filters) for dashboard metric cards.
    counts_q = (
        db.query(Assignment)
        .filter(
            Assignment.organization_id == org_id,
            Assignment.is_deleted == False,
        )
    )
    if user.role == UserRole.INTERN:
        counts_q = counts_q.filter(or_(*intern_filters), Assignment.status != AssignmentStatus.DRAFT)
    status_counts = dict(
        counts_q.with_entities(Assignment.status, func.count(Assignment.id)).group_by(Assignment.status).all()
    )
    pending_reviews = (
        db.query(func.count(AssignmentSubmission.id))
        .join(Assignment, AssignmentSubmission.assignment_id == Assignment.id)
        .filter(
            Assignment.organization_id == org_id,
            Assignment.is_deleted == False,
            AssignmentSubmission.status.in_(
                [
                    AssignmentSubmissionStatus.SUBMITTED,
                    AssignmentSubmissionStatus.UNDER_REVIEW,
                    AssignmentSubmissionStatus.RESUBMITTED,
                ]
            ),
        )
        .scalar()
        or 0
    )

    return {
        "assignments": paginated_items,
        "items": paginated_items,
        "total": total,
        "page": p,
        "page_size": ps,
        "total_pages": max(1, (total + ps - 1) // ps) if total else 1,
        "counts": {
            "all": sum(status_counts.values()),
            "draft": status_counts.get(AssignmentStatus.DRAFT, 0),
            "active": status_counts.get(AssignmentStatus.ACTIVE, 0),
            "closed": status_counts.get(AssignmentStatus.CLOSED, 0),
            "archived": status_counts.get(AssignmentStatus.ARCHIVED, 0),
            "pending_reviews": pending_reviews,
        },
    }


@router.post("")
@router.post("/")
async def create_assignment(
    request: Request,
    db: DbSession,
    data: AssignmentCreatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or user.role == UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentor or Admin privileges required.")

    org_id = _resolve_org_id(request, user, db)
    payload = await get_payload(request, data)

    title = str(payload.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=422, detail="Assignment title is required.")

    description = str(payload.get("description") or "").strip()
    project_id = payload.get("project_id")
    cohort_id = payload.get("cohort_id")
    assigned_to_user_id = payload.get("assigned_to_user_id")
    ensure_project_in_org(request, user, db, project_id)
    ensure_cohort_in_org(request, user, db, cohort_id)
    ensure_user_in_org(request, user, db, assigned_to_user_id)

    due_date = None
    if payload.get("due_date"):
        try:
            due_date = date.fromisoformat(str(payload["due_date"]))
        except ValueError:
            raise HTTPException(status_code=422, detail="Invalid due_date format. Use YYYY-MM-DD.")

    max_score = int(payload.get("max_score", 100))
    status = str(payload.get("status") or AssignmentStatus.ACTIVE).strip()
    if status not in (
        AssignmentStatus.DRAFT,
        AssignmentStatus.ACTIVE,
        AssignmentStatus.CLOSED,
        AssignmentStatus.ARCHIVED,
    ):
        status = AssignmentStatus.ACTIVE

    assignment = Assignment(
        organization_id=org_id,
        title=title,
        description=description,
        created_by_id=user.id,
        project_id=project_id,
        cohort_id=cohort_id,
        assigned_to_user_id=assigned_to_user_id,
        due_date=due_date,
        max_score=max_score,
        status=status,
    )
    db.add(assignment)
    db.commit()
    db.refresh(assignment)

    record_audit(
        db,
        user,
        "assignment.create",
        "created assignment",
        title,
        target_id=assignment.id,
    )

    # Notify assignee if specific intern was assigned
    from email_service import send_assignment_created_email
    recipient_users = []
    if assigned_to_user_id:
        push_notification(
            db,
            user_id=assigned_to_user_id,
            message=f"You have been assigned a new assignment: '{title}'",
            link=f"/assignments/{assignment.id}",
        )
        assigned_user = db.get(User, assigned_to_user_id)
        if assigned_user:
            recipient_users.append(assigned_user)
    elif cohort_id:
        from models import CohortMember
        members = db.query(CohortMember).filter_by(cohort_id=cohort_id).all()
        for m in members:
            u = db.get(User, m.user_id)
            if u:
                recipient_users.append(u)
    else:
        from models import OrganizationMembership
        members = db.query(OrganizationMembership).filter_by(organization_id=org_id, role="intern", is_active=True).all()
        for m in members:
            u = db.get(User, m.user_id)
            if u:
                recipient_users.append(u)

    if recipient_users:
        send_assignment_created_email(db, org_id, assignment, recipient_users)

    return _assignment_to_dict(assignment, user=user, db=db)


# ==============================================================================
# Single Assignment Detail, Update, Delete & Attachments
# ==============================================================================
@router.get("/{assignment_id}")
async def get_assignment(assignment_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    assignment = (
        db.query(Assignment)
        .options(
            joinedload(Assignment.created_by),
            joinedload(Assignment.project),
            joinedload(Assignment.cohort),
            joinedload(Assignment.assigned_to_user),
        )
        .filter_by(id=assignment_id, is_deleted=False)
        .first()
    )
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    return _assignment_to_dict(assignment, user=user, db=db)


@router.put("/{assignment_id}")
async def update_assignment(
    assignment_id: int,
    request: Request,
    db: DbSession,
    data: AssignmentUpdatePayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or user.role == UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentor or Admin privileges required.")

    assignment = db.query(Assignment).filter_by(id=assignment_id, is_deleted=False).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    payload = await get_payload(request, data)

    if "title" in payload and payload["title"] is not None:
        title = str(payload["title"]).strip()
        if not title:
            raise HTTPException(status_code=422, detail="Title cannot be empty.")
        assignment.title = title

    if "description" in payload and payload["description"] is not None:
        assignment.description = str(payload["description"]).strip()

    if payload.get("project_id") is not None:
        ensure_project_in_org(request, user, db, payload["project_id"])
    if payload.get("cohort_id") is not None:
        ensure_cohort_in_org(request, user, db, payload["cohort_id"])
    if payload.get("assigned_to_user_id") is not None:
        ensure_user_in_org(request, user, db, payload["assigned_to_user_id"])

    if "project_id" in payload:
        assignment.project_id = payload["project_id"]

    if "cohort_id" in payload:
        assignment.cohort_id = payload["cohort_id"]

    if "assigned_to_user_id" in payload:
        assignment.assigned_to_user_id = payload["assigned_to_user_id"]

    if "due_date" in payload:
        if payload["due_date"]:
            try:
                assignment.due_date = date.fromisoformat(str(payload["due_date"]))
            except ValueError:
                raise HTTPException(status_code=422, detail="Invalid due_date format.")
        else:
            assignment.due_date = None

    if "max_score" in payload and payload["max_score"] is not None:
        try:
            assignment.max_score = int(payload["max_score"])
        except (TypeError, ValueError):
            pass

    if "status" in payload and payload["status"] is not None:
        assignment.status = str(payload["status"]).strip()

    db.commit()
    db.refresh(assignment)

    record_audit(
        db,
        user,
        "assignment.update",
        "updated assignment",
        assignment.title,
        target_id=assignment.id,
    )
    return _assignment_to_dict(assignment, user=user, db=db)


@router.delete("/{assignment_id}")
async def delete_assignment(assignment_id: int, request: Request, db: DbSession):
    user = get_optional_user(request, db)
    if not user or user.role == UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentor or Admin privileges required.")

    assignment = db.query(Assignment).filter_by(id=assignment_id, is_deleted=False).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    assignment.is_deleted = True
    db.commit()

    record_audit(
        db,
        user,
        "assignment.delete",
        "deleted assignment",
        assignment.title,
        target_id=assignment.id,
    )
    return {"success": True, "message": f"Assignment '{assignment.title}' deleted."}


@router.post("/{assignment_id}/attachment")
async def upload_assignment_attachment(
    assignment_id: int,
    request: Request,
    db: DbSession,
    file: UploadFile = File(...),
):
    user = get_optional_user(request, db)
    if not user or user.role == UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentor or Admin privileges required.")

    assignment = db.query(Assignment).filter_by(id=assignment_id, is_deleted=False).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=422, detail="Uploaded file is empty.")

    try:
        rel_path, safe_name, size = save_assignment_attachment(
            assignment_id=assignment.id,
            user_id=user.id,
            file_name=file.filename or "attachment",
            content=content,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    assignment.attachment_path = rel_path
    assignment.attachment_name = safe_name
    db.commit()
    db.refresh(assignment)

    return _assignment_to_dict(assignment, user=user, db=db)


@router.get("/{assignment_id}/attachment")
async def download_assignment_attachment(
    assignment_id: int,
    request: Request,
    db: DbSession,
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    assignment = db.query(Assignment).filter_by(id=assignment_id, is_deleted=False).first()
    if not assignment or not assignment.attachment_path:
        raise HTTPException(status_code=404, detail="No attachment found for this assignment.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    abs_path = attachment_abs_path(assignment.attachment_path)
    if not abs_path:
        raise HTTPException(status_code=404, detail="Attachment file not found on server.")

    return FileResponse(
        path=abs_path,
        filename=assignment.attachment_name or os.path.basename(abs_path),
        media_type="application/octet-stream",
    )


# ==============================================================================
# Submission Endpoints (Intern Work & Solutions)
# ==============================================================================
@router.post("/{assignment_id}/submit")
async def submit_assignment(
    assignment_id: int,
    request: Request,
    db: DbSession,
    submission_text: str = Form(None),
    github_url: str = Form(None),
    file: UploadFile = File(None),
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    assignment = db.query(Assignment).filter_by(id=assignment_id, is_deleted=False).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    if assignment.status == AssignmentStatus.CLOSED:
        raise HTTPException(status_code=422, detail="This assignment is closed for submissions.")

    text_content = submission_text
    gh_url = github_url
    if text_content is None and gh_url is None and file is None:
        try:
            body = await request.json()
            text_content = body.get("submission_text")
            gh_url = body.get("github_url")
        except Exception:
            pass

    submission = (
        db.query(AssignmentSubmission)
        .filter_by(assignment_id=assignment.id, user_id=user.id)
        .first()
    )

    if not submission:
        submission = AssignmentSubmission(
            assignment_id=assignment.id,
            user_id=user.id,
            status=AssignmentSubmissionStatus.SUBMITTED,
        )
        db.add(submission)
        db.flush()

    if text_content is not None:
        submission.submission_text = str(text_content).strip()
    if gh_url is not None:
        cleaned_url = validate_http_url(str(gh_url).strip())
        if cleaned_url is None and str(gh_url).strip():
            raise HTTPException(status_code=422, detail="github_url must be an absolute http(s) URL.")
        submission.github_url = cleaned_url

    if file and file.filename:
        file_bytes = await file.read()
        if file_bytes:
            try:
                rel_path, safe_name, size = save_submission_file(
                    submission_id=submission.id,
                    user_id=user.id,
                    file_name=file.filename,
                    content=file_bytes,
                )
            except ValueError as exc:
                raise HTTPException(status_code=422, detail=str(exc))
            submission.file_path = rel_path
            submission.file_name = safe_name
            submission.file_size = size

    submission.status = (
        AssignmentSubmissionStatus.RESUBMITTED
        if submission.reviewed_at is not None
        else AssignmentSubmissionStatus.SUBMITTED
    )
    submission.submitted_at = _utcnow()
    db.commit()
    db.refresh(submission)

    record_audit(
        db,
        user,
        "assignment.submit",
        "submitted assignment response",
        assignment.title,
        target_id=assignment.id,
    )

    # Notify creator / mentor
    if assignment.created_by_id:
        push_notification(
            db,
            user_id=assignment.created_by_id,
            message=f"{user.name} submitted their response for '{assignment.title}'",
            link=f"/assignments/{assignment.id}",
        )
        creator_user = db.get(User, assignment.created_by_id)
        if creator_user:
            from email_service import send_assignment_submitted_email
            send_assignment_submitted_email(db, assignment.organization_id, assignment, submission, user, [creator_user])

    return {
        "success": True,
        "message": "Assignment submitted successfully.",
        "submission": submission.to_dict(),
    }


@router.get("/{assignment_id}/submissions")
async def list_assignment_submissions(
    assignment_id: int,
    request: Request,
    db: DbSession,
    status: str | None = None,
    page: int = 1,
    page_size: int = 20,
):
    user = get_optional_user(request, db)
    if not user or user.role == UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentor or Admin privileges required.")

    assignment = db.query(Assignment).filter_by(id=assignment_id, is_deleted=False).first()
    if not assignment:
        raise HTTPException(status_code=404, detail="Assignment not found.")
    ensure_in_org(request, user, db, assignment.organization_id, "Assignment not found.")

    query = (
        db.query(AssignmentSubmission)
        .options(
            joinedload(AssignmentSubmission.user),
            joinedload(AssignmentSubmission.reviewed_by),
        )
        .filter_by(assignment_id=assignment.id)
    )

    st = _clean_param_str(status)
    if st:
        query = query.filter(AssignmentSubmission.status == st.lower())

    p = _clean_param_int(page, 1)
    ps = _clean_param_int(page_size, 20)
    total = query.count()
    total_pages = max(1, (total + ps - 1) // ps) if total else 1
    submissions = (
        query.order_by(AssignmentSubmission.submitted_at.desc())
        .offset((p - 1) * ps)
        .limit(ps)
        .all()
    )

    paginated_items = [s.to_dict() for s in submissions]
    return {
        "assignment": assignment.to_dict(),
        "submissions": paginated_items,
        "items": paginated_items,
        "total": total,
        "page": p,
        "page_size": ps,
        "total_pages": total_pages,
    }


@router.get("/submissions/{submission_id}/file")
async def download_submission_file(
    submission_id: int,
    request: Request,
    db: DbSession,
):
    user = get_optional_user(request, db)
    if not user:
        raise HTTPException(status_code=401)

    sub = db.query(AssignmentSubmission).filter_by(id=submission_id).first()
    if not sub or not sub.file_path:
        raise HTTPException(status_code=404, detail="No submission file found.")
    ensure_in_org(request, user, db, sub.assignment.organization_id if sub.assignment else None, "Submission not found.")

    if user.role == UserRole.INTERN and sub.user_id != user.id:
        raise HTTPException(status_code=403, detail="Access denied.")

    abs_path = attachment_abs_path(sub.file_path)
    if not abs_path:
        raise HTTPException(status_code=404, detail="File not found on server.")

    return FileResponse(
        path=abs_path,
        filename=sub.file_name or os.path.basename(abs_path),
        media_type="application/octet-stream",
    )


# ==============================================================================
# Mentor Review & Grading
# ==============================================================================
@router.post("/submissions/{submission_id}/review")
@router.put("/submissions/{submission_id}/review")
async def review_submission(
    submission_id: int,
    request: Request,
    db: DbSession,
    data: AssignmentReviewPayload | None = Body(None),
):
    user = get_optional_user(request, db)
    if not user or user.role == UserRole.INTERN:
        raise HTTPException(status_code=403, detail="Mentor or Admin privileges required.")

    sub = (
        db.query(AssignmentSubmission)
        .options(
            joinedload(AssignmentSubmission.assignment),
            joinedload(AssignmentSubmission.user),
        )
        .filter_by(id=submission_id)
        .first()
    )
    if not sub:
        raise HTTPException(status_code=404, detail="Submission not found.")
    ensure_in_org(request, user, db, sub.assignment.organization_id if sub.assignment else None, "Submission not found.")

    payload = await get_payload(request, data)

    if "score" in payload and payload["score"] is not None:
        try:
            score_val = float(payload["score"])
            if sub.assignment and sub.assignment.max_score and score_val > sub.assignment.max_score:
                raise HTTPException(
                    status_code=422,
                    detail=f"Score {score_val} exceeds maximum allowed score {sub.assignment.max_score}.",
                )
            sub.score = score_val
        except (TypeError, ValueError):
            raise HTTPException(status_code=422, detail="Invalid score format.")

    if "feedback" in payload and payload["feedback"] is not None:
        sub.feedback = str(payload["feedback"]).strip()

    status_val = payload.get("status", AssignmentSubmissionStatus.APPROVED)
    if status_val in (
        AssignmentSubmissionStatus.APPROVED,
        AssignmentSubmissionStatus.REJECTED,
        AssignmentSubmissionStatus.RESUBMITTED,
        AssignmentSubmissionStatus.UNDER_REVIEW,
    ):
        sub.status = status_val
    else:
        sub.status = AssignmentSubmissionStatus.APPROVED

    sub.reviewed_by_id = user.id
    sub.reviewed_at = _utcnow()
    db.commit()
    db.refresh(sub)

    record_audit(
        db,
        user,
        "assignment.review",
        f"graded submission with status '{sub.status}' and score {sub.score}",
        sub.assignment.title if sub.assignment else "assignment",
        target_id=sub.id,
    )

    # Notify student
    push_notification(
        db,
        user_id=sub.user_id,
        message=f"Your submission for '{sub.assignment.title}' was reviewed. Status: {sub.status}, Score: {sub.score}",
        link=f"/assignments/{sub.assignment_id}",
    )

    intern_user = db.get(User, sub.user_id)
    if intern_user and sub.assignment:
        from email_service import send_assignment_graded_email
        send_assignment_graded_email(db, sub.assignment.organization_id, sub.assignment, sub, intern_user, user)

    return {
        "success": True,
        "message": "Submission reviewed successfully.",
        "submission": sub.to_dict(),
    }
