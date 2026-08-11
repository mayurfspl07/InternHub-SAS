"""Jinja2 templates and render helpers."""
from starlette.requests import Request
from starlette.templating import Jinja2Templates

from models import GuestUser
from utils import get_csrf_token, unread_notification_count

templates = Jinja2Templates(directory="templates")


def flash(request: Request, message: str, category: str = "info") -> None:
    flashes = request.session.setdefault("_flashes", [])
    flashes.append((category, message))


def pop_flashes(request: Request) -> list[tuple[str, str]]:
    return request.session.pop("_flashes", [])


def render(
    request: Request,
    template: str,
    context: dict | None = None,
    *,
    user=None,
    page: str | None = None,
):
    current_user = user or GuestUser()

    # Unread notification count for the bell icon
    notif_count = 0
    if current_user.is_authenticated:
        try:
            from database import SessionLocal
            db = SessionLocal()
            try:
                notif_count = unread_notification_count(db, current_user.id)
            finally:
                db.close()
        except Exception:
            pass

    ctx = {
        "request": request,
        "current_user": current_user,
        "messages": pop_flashes(request),
        "page": page or "",
        "csrf_token": get_csrf_token(request),
        "notif_count": notif_count,
    }
    if context:
        ctx.update(context)
    return templates.TemplateResponse(request, template, ctx)
