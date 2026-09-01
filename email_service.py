"""Tenant-aware SMTP Email Service with HTML templating and background dispatch."""
import email.utils
import html
import logging
import smtplib
import threading
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any

from config import Config
from database import SessionLocal
from models import EmailLog, Organization, TenantSmtpConfig, User, _utcnow

logger = logging.getLogger(__name__)


def _get_tenant_smtp(db, org_id: int) -> dict[str, Any] | None:
    """Resolve active SMTP configuration for a tenant (or fallback to platform config)."""
    cfg: TenantSmtpConfig | None = (
        db.query(TenantSmtpConfig).filter_by(organization_id=org_id).first()
    )

    if cfg and cfg.is_enabled and cfg.host:
        return {
            "source": "tenant",
            "host": cfg.host,
            "port": cfg.port,
            "username": cfg.username,
            "password": cfg.password,
            "sender_email": cfg.sender_email or cfg.username,
            "sender_name": cfg.sender_name or "InternHub",
            "encryption": cfg.encryption or "tls",
            "triggers": {
                "welcome": cfg.notify_welcome,
                "leave_request": cfg.notify_leave_request,
                "leave_decision": cfg.notify_leave_decision,
                "assignment_new": cfg.notify_assignment_new,
                "assignment_submit": cfg.notify_assignment_submit,
                "assignment_grade": cfg.notify_assignment_grade,
                "task_assigned": cfg.notify_task_assigned,
                "attendance_alert": cfg.notify_attendance_alert,
            },
        }

    # Platform default fallback
    if Config.SMTP_HOST:
        return {
            "source": "platform",
            "host": Config.SMTP_HOST,
            "port": Config.SMTP_PORT,
            "username": Config.SMTP_USER,
            "password": Config.SMTP_PASSWORD,
            "sender_email": Config.SMTP_SENDER_EMAIL or Config.SMTP_USER,
            "sender_name": Config.SMTP_SENDER_NAME or "InternHub",
            "encryption": Config.SMTP_ENCRYPTION or "tls",
            "triggers": {
                "welcome": True,
                "leave_request": True,
                "leave_decision": True,
                "assignment_new": True,
                "assignment_submit": True,
                "assignment_grade": True,
                "task_assigned": True,
                "attendance_alert": True,
            },
        }

    return None


def _render_html_template(
    org_name: str,
    title: str,
    preheader: str,
    body_html: str,
    cta_text: str | None = None,
    cta_url: str | None = None,
) -> str:
    """Generate a clean, responsive, branded HTML email template."""
    action_button_html = ""
    if cta_text and cta_url:
        action_button_html = f"""
        <div style="margin: 32px 0 24px; text-align: center;">
            <a href="{html.escape(cta_url)}" style="background: linear-gradient(135deg, #4f46e5 0%, #6366f1 100%); color: #ffffff; text-decoration: none; padding: 14px 32px; border-radius: 8px; font-weight: 600; font-size: 15px; display: inline-block; box-shadow: 0 4px 12px rgba(99, 102, 241, 0.35);">
                {html.escape(cta_text)}
            </a>
        </div>
        """

    return f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{html.escape(title)}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1e293b;">
    <div style="display: none; max-height: 0px; overflow: hidden;">{html.escape(preheader)}</div>
    <table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #f8fafc; padding: 40px 16px;">
        <tr>
            <td align="center">
                <table width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width: 580px; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.05); border: 1px solid #e2e8f0;">
                    <!-- Header -->
                    <tr>
                        <td style="padding: 28px 32px; background-color: #0f172a; text-align: left;">
                            <div style="font-size: 20px; font-weight: 700; color: #ffffff; letter-spacing: -0.5px;">
                                {html.escape(org_name or "InternHub")}
                            </div>
                        </td>
                    </tr>
                    <!-- Content -->
                    <tr>
                        <td style="padding: 36px 32px 28px;">
                            <h1 style="margin: 0 0 16px; font-size: 22px; font-weight: 700; color: #0f172a; line-height: 1.3;">
                                {html.escape(title)}
                            </h1>
                            <div style="font-size: 15px; line-height: 1.6; color: #334155;">
                                {body_html}
                            </div>
                            {action_button_html}
                        </td>
                    </tr>
                    <!-- Footer -->
                    <tr>
                        <td style="padding: 24px 32px; background-color: #f1f5f9; border-top: 1px solid #e2e8f0; text-align: center; font-size: 13px; color: #64748b; line-height: 1.5;">
                            This is an automated notification from <strong>{html.escape(org_name or "InternHub")}</strong>.<br>
                            If you have questions, please contact your workspace administrator.
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>"""


def _create_thread_session(source_db=None):
    if source_db is not None:
        try:
            bind = source_db.get_bind()
            from sqlalchemy.orm import sessionmaker
            return sessionmaker(bind=bind, autocommit=False, autoflush=False)()
        except Exception:
            pass
    try:
        return SessionLocal()
    except Exception:
        return None


_email_log_lock = threading.Lock()


def send_email_sync(
    org_id: int,
    recipient_email: str,
    subject: str,
    html_content: str,
    plain_content: str,
    email_type: str,
    recipient_name: str | None = None,
    smtp_override: dict | None = None,
    db: Any = None,
) -> tuple[bool, str | None]:
    """Synchronously send an email via tenant/platform SMTP and record in EmailLog."""
    session = _create_thread_session(db)
    status = "sent"
    error_msg = None

    try:
        smtp_cfg = smtp_override or (_get_tenant_smtp(session, org_id) if session else None)

        if not smtp_cfg or not smtp_cfg.get("host"):
            # Simulated mode for development/tests without SMTP configured
            logger.info("Simulated email [%s] to %s: %s", email_type, recipient_email, subject)
            status = "simulated"
        else:
            host = smtp_cfg["host"]
            port = int(smtp_cfg.get("port") or 587)
            username = smtp_cfg.get("username", "")
            password = smtp_cfg.get("password", "")
            sender_email = smtp_cfg.get("sender_email") or username
            sender_name = smtp_cfg.get("sender_name") or "InternHub"
            encryption = str(smtp_cfg.get("encryption") or "tls").lower()

            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = email.utils.formataddr((sender_name, sender_email))
            msg["To"] = email.utils.formataddr((recipient_name or "", recipient_email))
            msg["Date"] = email.utils.formatdate(localtime=True)

            msg.attach(MIMEText(plain_content, "plain", "utf-8"))
            msg.attach(MIMEText(html_content, "html", "utf-8"))

            if encryption == "ssl" or port == 465:
                server = smtplib.SMTP_SSL(host, port, timeout=12)
            else:
                server = smtplib.SMTP(host, port, timeout=12)
                if encryption == "tls":
                    server.starttls()

            if username and password:
                server.login(username, password)

            server.sendmail(sender_email, [recipient_email], msg.as_string())
            server.quit()
            logger.info("Email [%s] sent to %s via %s SMTP", email_type, recipient_email, smtp_cfg.get("source", "smtp"))

    except Exception as e:
        status = "failed"
        error_msg = str(e)
        logger.warning("Failed to send email [%s] to %s: %s", email_type, recipient_email, e)

    finally:
        if session is not None:
            try:
                with _email_log_lock:
                    log_entry = EmailLog(
                        organization_id=org_id,
                        recipient_email=recipient_email,
                        recipient_name=recipient_name,
                        subject=subject,
                        email_type=email_type,
                        status=status,
                        error_message=error_msg,
                    )
                    session.add(log_entry)
                    session.commit()
            except Exception as log_err:
                logger.error("Failed to write email log: %s", log_err)
            finally:
                session.close()

    return (status in ("sent", "simulated")), error_msg


def send_email_async(
    org_id: int,
    recipient_email: str,
    subject: str,
    html_content: str,
    plain_content: str,
    email_type: str,
    recipient_name: str | None = None,
    smtp_override: dict | None = None,
    db: Any = None,
) -> threading.Thread:
    """Dispatch an email in a background daemon thread to keep API calls non-blocking."""
    t = threading.Thread(
        target=send_email_sync,
        kwargs={
            "org_id": org_id,
            "recipient_email": recipient_email,
            "subject": subject,
            "html_content": html_content,
            "plain_content": plain_content,
            "email_type": email_type,
            "recipient_name": recipient_name,
            "smtp_override": smtp_override,
            "db": db,
        },
        daemon=True,
    )
    t.start()
    return t


# ---------------------------------------------------------------------------
# High-Level Event Email Trigger Helpers
# ---------------------------------------------------------------------------

def _get_org_name(db, org_id: int) -> str:
    org = db.query(Organization).filter_by(id=org_id).first()
    return org.name if org else "InternHub"


def send_welcome_email(
    db,
    org_id: int,
    user: User,
    temp_password: str | None = None,
    invite_url: str | None = None,
):
    """Send welcome onboarding email to new intern or team member."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("welcome", True):
        return

    org_name = _get_org_name(db, org_id)
    title = f"Welcome to {org_name} on InternHub!"
    preheader = f"Your account for {org_name} is now ready."

    body_html = f"""
    <p>Hello <strong>{html.escape(user.name)}</strong>,</p>
    <p>Welcome to <strong>{html.escape(org_name)}</strong>! Your account has been provisioned on our internship and team workspace.</p>
    """

    if temp_password:
        body_html += f"""
        <div style="background-color: #f1f5f9; border-left: 4px solid #4f46e5; padding: 14px 18px; margin: 20px 0; border-radius: 6px;">
            <div style="font-size: 13px; color: #64748b; margin-bottom: 4px;">Temporary Password</div>
            <code style="font-size: 16px; font-weight: bold; color: #0f172a; font-family: monospace;">{html.escape(temp_password)}</code>
        </div>
        <p style="font-size: 13px; color: #64748b;">Please sign in and change your password immediately.</p>
        """

    cta_url = invite_url or f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/login"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="Sign In to Dashboard", cta_url=cta_url)
    plain_msg = f"Welcome to {org_name}!\nSign in here: {cta_url}\n"

    send_email_async(org_id, user.email, title, html_msg, plain_msg, "welcome", user.name, db=db)


def send_leave_request_email(db, org_id: int, leave_request, intern: User, reviewers: list[User]):
    """Notify mentor/admin that an intern has submitted a leave request."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("leave_request", True):
        return

    org_name = _get_org_name(db, org_id)
    title = f"New Leave Request: {intern.name} ({leave_request.days} day{'s' if leave_request.days > 1 else ''})"
    preheader = f"{intern.name} requested leave from {leave_request.start_date} to {leave_request.end_date}."

    body_html = f"""
    <p><strong>{html.escape(intern.name)}</strong> has submitted a new leave application:</p>
    <table style="width: 100%; border-collapse: collapse; margin: 18px 0; font-size: 14px;">
        <tr style="border-bottom: 1px solid #e2e8f0;"><td style="padding: 8px 0; color: #64748b;">Dates</td><td style="padding: 8px 0; font-weight: 600;">{leave_request.start_date} to {leave_request.end_date} ({leave_request.days} day{'s' if leave_request.days > 1 else ''})</td></tr>
        <tr style="border-bottom: 1px solid #e2e8f0;"><td style="padding: 8px 0; color: #64748b;">Type</td><td style="padding: 8px 0; font-weight: 600; text-transform: capitalize;">{html.escape(str(leave_request.leave_type or 'casual'))}</td></tr>
        <tr style="border-bottom: 1px solid #e2e8f0;"><td style="padding: 8px 0; color: #64748b;">Reason</td><td style="padding: 8px 0;">{html.escape(str(leave_request.reason or 'No reason provided'))}</td></tr>
    </table>
    """
    cta_url = f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/admin/leave"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="Review Leave Application", cta_url=cta_url)
    plain_msg = f"{intern.name} requested leave for {leave_request.days} days ({leave_request.start_date} to {leave_request.end_date}). Reason: {leave_request.reason}"

    for reviewer in reviewers:
        if reviewer.email:
            send_email_async(org_id, reviewer.email, title, html_msg, plain_msg, "leave_request", reviewer.name, db=db)


def send_leave_status_email(db, org_id: int, leave_request, intern: User, reviewer: User | None = None):
    """Notify intern that their leave request has been approved or rejected."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("leave_decision", True):
        return

    org_name = _get_org_name(db, org_id)
    status_display = str(leave_request.status).upper()
    is_approved = str(leave_request.status).lower() == "approved"
    status_color = "#16a34a" if is_approved else "#dc2626"

    title = f"Leave Request {status_display}: {leave_request.start_date} to {leave_request.end_date}"
    preheader = f"Your leave request has been marked as {status_display}."

    body_html = f"""
    <p>Hello <strong>{html.escape(intern.name)}</strong>,</p>
    <p>Your leave application from <strong>{leave_request.start_date}</strong> to <strong>{leave_request.end_date}</strong> has been updated:</p>
    <div style="display: inline-block; padding: 6px 14px; border-radius: 20px; font-weight: 700; font-size: 14px; color: #ffffff; background-color: {status_color}; margin: 12px 0 20px;">
        {status_display}
    </div>
    """
    if reviewer:
        body_html += f"<p style='color: #64748b; font-size: 14px;'>Reviewed by: <strong>{html.escape(reviewer.name)}</strong></p>"

    cta_url = f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/leave"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="View Leave Status", cta_url=cta_url)
    plain_msg = f"Your leave request ({leave_request.start_date} to {leave_request.end_date}) was {status_display}."

    send_email_async(org_id, intern.email, title, html_msg, plain_msg, "leave_decision", intern.name, db=db)


def send_assignment_created_email(db, org_id: int, assignment, recipient_users: list[User]):
    """Notify interns that a new assignment has been published."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("assignment_new", True):
        return

    org_name = _get_org_name(db, org_id)
    title = f"New Assignment: {assignment.title}"
    preheader = f"A new assignment has been posted with due date {assignment.due_date}."

    body_html = f"""
    <p>A new assignment has been assigned to you:</p>
    <h3 style="margin: 12px 0 6px; color: #0f172a;">{html.escape(assignment.title)}</h3>
    <p style="color: #475569; margin-bottom: 16px;">{html.escape(str(assignment.description or ''))}</p>
    <table style="width: 100%; border-collapse: collapse; margin: 14px 0; font-size: 14px;">
        <tr style="border-bottom: 1px solid #e2e8f0;"><td style="padding: 6px 0; color: #64748b;">Due Date</td><td style="padding: 6px 0; font-weight: 600;">{assignment.due_date}</td></tr>
        <tr style="border-bottom: 1px solid #e2e8f0;"><td style="padding: 6px 0; color: #64748b;">Max Score</td><td style="padding: 6px 0; font-weight: 600;">{assignment.max_score} pts</td></tr>
    </table>
    """
    cta_url = f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/assignments/{assignment.id}"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="View Assignment & Submit", cta_url=cta_url)
    plain_msg = f"New assignment posted: {assignment.title}. Due date: {assignment.due_date}. Max score: {assignment.max_score}."

    for user in recipient_users:
        if user.email:
            send_email_async(org_id, user.email, title, html_msg, plain_msg, "assignment_new", user.name, db=db)


def send_assignment_submitted_email(db, org_id: int, assignment, submission, intern: User, mentor_users: list[User]):
    """Notify mentor that an intern submitted an assignment solution."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("assignment_submit", True):
        return

    org_name = _get_org_name(db, org_id)
    title = f"Assignment Solution Submitted: {intern.name} - {assignment.title}"
    preheader = f"{intern.name} has submitted their work for {assignment.title}."

    body_html = f"""
    <p><strong>{html.escape(intern.name)}</strong> has submitted work for <strong>{html.escape(assignment.title)}</strong>.</p>
    """
    if submission.github_url:
        body_html += f"<p><strong>GitHub Link:</strong> <a href='{html.escape(submission.github_url)}'>{html.escape(submission.github_url)}</a></p>"
    if submission.submission_text:
        body_html += f"<blockquote style='border-left: 3px solid #6366f1; margin: 14px 0; padding-left: 12px; color: #475569;'>{html.escape(submission.submission_text)}</blockquote>"

    cta_url = f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/assignments/{assignment.id}"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="Review Submission", cta_url=cta_url)
    plain_msg = f"{intern.name} submitted solution for {assignment.title}."

    for mentor in mentor_users:
        if mentor.email:
            send_email_async(org_id, mentor.email, title, html_msg, plain_msg, "assignment_submit", mentor.name, db=db)


def send_assignment_graded_email(db, org_id: int, assignment, submission, intern: User, reviewer: User | None = None):
    """Notify intern that their assignment submission was reviewed and scored."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("assignment_grade", True):
        return

    org_name = _get_org_name(db, org_id)
    score_display = f"{submission.score}/{assignment.max_score}" if submission.score is not None else str(submission.status).upper()
    title = f"Assignment Reviewed: {assignment.title} ({score_display})"
    preheader = f"Your assignment '{assignment.title}' has been reviewed."

    body_html = f"""
    <p>Hello <strong>{html.escape(intern.name)}</strong>,</p>
    <p>Your submission for <strong>{html.escape(assignment.title)}</strong> has been graded:</p>
    <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px 20px; margin: 18px 0;">
        <div style="font-size: 13px; color: #64748b;">Status / Score</div>
        <div style="font-size: 20px; font-weight: 700; color: #4f46e5; margin-top: 4px;">{score_display} ({str(submission.status).capitalize()})</div>
        {"<div style='margin-top: 12px; font-size: 14px; color: #334155;'><strong>Feedback:</strong> " + html.escape(str(submission.feedback)) + "</div>" if submission.feedback else ""}
    </div>
    """
    cta_url = f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/assignments/{assignment.id}"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="View Feedback", cta_url=cta_url)
    plain_msg = f"Your submission for {assignment.title} was graded: {score_display}. Feedback: {submission.feedback or ''}"

    send_email_async(org_id, intern.email, title, html_msg, plain_msg, "assignment_grade", intern.name, db=db)


def send_task_assigned_email(db, org_id: int, task, assignee: User, creator: User | None = None):
    """Notify assignee when a new project task is assigned to them."""
    smtp_cfg = _get_tenant_smtp(db, org_id)
    if smtp_cfg and not smtp_cfg["triggers"].get("task_assigned", True):
        return

    org_name = _get_org_name(db, org_id)
    title = f"New Task Assigned: {task.title}"
    preheader = f"You have been assigned task '{task.title}'."

    body_html = f"""
    <p>Hello <strong>{html.escape(assignee.name)}</strong>,</p>
    <p>A new task has been assigned to you:</p>
    <h3 style="margin: 12px 0 6px; color: #0f172a;">{html.escape(task.title)}</h3>
    <p style="color: #475569;">{html.escape(str(task.description or 'No description provided'))}</p>
    """
    if creator:
        body_html += f"<p style='font-size: 13px; color: #64748b;'>Assigned by: {html.escape(creator.name)}</p>"

    cta_url = f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/projects/{task.project_id}" if getattr(task, 'project_id', None) else f"{Config.PUBLIC_SITE_URL or 'http://localhost:5173'}/tasks"
    html_msg = _render_html_template(org_name, title, preheader, body_html, cta_text="Open Task in Project", cta_url=cta_url)
    plain_msg = f"New task assigned: {task.title}. Description: {task.description or ''}"

    send_email_async(org_id, assignee.email, title, html_msg, plain_msg, "task_assigned", assignee.name, db=db)


def send_test_email(db, org_id: int, target_email: str, smtp_override: dict | None = None) -> tuple[bool, str | None]:
    """Send a live test email to verify SMTP connection and credentials."""
    org_name = _get_org_name(db, org_id)
    title = f"InternHub SMTP Test Email - {org_name}"
    preheader = "Your SMTP configuration is active and working."
    body_html = f"""
    <p>This is a test email sent from <strong>{html.escape(org_name)}</strong> on InternHub.</p>
    <div style="background-color: #ecfdf5; border: 1px solid #a7f3d0; color: #065f46; padding: 14px 18px; border-radius: 8px; margin: 18px 0; font-weight: 600;">
        ✓ SMTP Configuration Verified Successfully!
    </div>
    <p style="font-size: 13px; color: #64748b;">Timestamp: {_utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}</p>
    """
    html_msg = _render_html_template(org_name, title, preheader, body_html)
    plain_msg = f"This is a test email from {org_name}. Your SMTP configuration is working."

    return send_email_sync(
        org_id=org_id,
        recipient_email=target_email,
        subject=title,
        html_content=html_msg,
        plain_content=plain_msg,
        email_type="test",
        recipient_name="Administrator",
        smtp_override=smtp_override,
        db=db,
    )
