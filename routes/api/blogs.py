"""Public marketing blog endpoints — published posts are readable without login; admins manage posts."""
import re
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from database import get_db
from dependencies import get_optional_user
from models import BlogPost, BinEntityType
from recycle_bin import move_to_bin
from routes.api.schemas import BlogCreatePayload, BlogUpdatePayload, get_payload
from utils import record_audit, isoformat_utc

router = APIRouter(prefix="/api/blogs", tags=["Blogs"])
DbSession = Annotated[Session, Depends(get_db)]

VALID_STATUSES = ("draft", "published")


def _utcnow() -> datetime:
    """Naive UTC now — matches DateTime columns without timezone=True."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.strip().lower()).strip("-")
    return slug[:200] or "post"


def _parse_tags(value) -> list[str]:
    """Accept a list of tags or a comma-separated string; return a clean list."""
    if value is None:
        return []
    if isinstance(value, str):
        parts = value.split(",")
    elif isinstance(value, (list, tuple)):
        parts = [str(v) for v in value]
    else:
        return []
    return [p.strip() for p in parts if p.strip()][:20]


def _unique_slug(db: Session, base: str, exclude_id: int | None = None) -> str:
    slug = base
    suffix = 2
    while True:
        q = db.query(BlogPost.id).filter(BlogPost.slug == slug)
        if exclude_id is not None:
            q = q.filter(BlogPost.id != exclude_id)
        if not q.first():
            return slug
        tail = f"-{suffix}"
        slug = f"{base[:200 - len(tail)]}{tail}"
        suffix += 1


def _clean_optional_str(value) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _blog_dict(post: BlogPost, include_content: bool = True) -> dict:
    data = {
        "id": post.id,
        "title": post.title,
        "slug": post.slug,
        "excerpt": post.excerpt,
        "cover_image_url": post.cover_image_url,
        "tags": _parse_tags(post.tags),
        "status": post.status,
        "author_id": post.author_id,
        "author_name": post.author.name if post.author else None,
        "published_at": isoformat_utc(post.published_at),
        "created_at": isoformat_utc(post.created_at),
        "updated_at": isoformat_utc(post.updated_at),
    }
    if include_content:
        data["content"] = post.content
    return data


def _require_admin(request: Request, db: Session):
    user = get_optional_user(request, db)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403)
    return user


@router.get("")
async def list_published_blogs(
    db: DbSession,
    page: int = Query(1, ge=1, description="1-based page number"),
    per_page: int = Query(12, ge=1, le=50, description="Items per page"),
    tag: str | None = Query(None, description="Filter by tag"),
    search: str | None = Query(None, description="Search title/excerpt/content"),
):
    q = (
        db.query(BlogPost)
        .options(joinedload(BlogPost.author))
        .filter(BlogPost.is_deleted == False, BlogPost.status == "published")  # noqa: E712
    )
    if tag:
        q = q.filter(BlogPost.tags.like(f"%{tag.strip()}%"))
    if search:
        term = f"%{search.strip()}%"
        q = q.filter(or_(BlogPost.title.ilike(term), BlogPost.excerpt.ilike(term), BlogPost.content.ilike(term)))

    total = q.count()
    posts = (
        q.order_by(BlogPost.published_at.desc(), BlogPost.created_at.desc())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
    return {
        "items": [_blog_dict(p, include_content=False) for p in posts],
        "total": total,
        "page": page,
        "per_page": per_page,
    }


@router.get("/admin/all")
async def list_all_blogs(
    request: Request,
    db: DbSession,
    status: str | None = Query(None, description="Filter by status: draft or published"),
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
):
    _require_admin(request, db)
    q = db.query(BlogPost).options(joinedload(BlogPost.author)).filter(BlogPost.is_deleted == False)  # noqa: E712
    if status and status in VALID_STATUSES:
        q = q.filter(BlogPost.status == status)
    total = q.count()
    posts = (
        q.order_by(BlogPost.created_at.desc())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
    return {"items": [_blog_dict(p) for p in posts], "total": total, "page": page, "per_page": per_page}


@router.get("/{slug}")
async def get_blog_by_slug(slug: str, request: Request, db: DbSession):
    post = (
        db.query(BlogPost)
        .options(joinedload(BlogPost.author))
        .filter(BlogPost.slug == slug, BlogPost.is_deleted == False)  # noqa: E712
        .first()
    )
    if not post:
        raise HTTPException(status_code=404)
    if post.status != "published":
        # Drafts are only visible to admins (preview).
        user = get_optional_user(request, db)
        if not user or not user.is_admin:
            raise HTTPException(status_code=404)
    return _blog_dict(post)


@router.post("")
async def create_blog(request: Request, db: DbSession, data: BlogCreatePayload | None = Body(None)):
    user = _require_admin(request, db)

    payload = await get_payload(request, data)
    title = str(payload.get("title", "")).strip()
    content = str(payload.get("content", "")).strip()
    if not title or not content:
        raise HTTPException(status_code=422, detail="Title and content are required.")

    status = str(payload.get("status") or "draft").strip().lower()
    if status not in VALID_STATUSES:
        raise HTTPException(status_code=422, detail="Status must be 'draft' or 'published'.")

    custom_slug = str(payload.get("slug") or "").strip()
    base_slug = _slugify(custom_slug) if custom_slug else _slugify(title)
    slug = _unique_slug(db, base_slug)

    tags = _parse_tags(payload.get("tags"))

    post = BlogPost(
        title=title[:200],
        slug=slug,
        excerpt=_clean_optional_str(payload.get("excerpt")),
        content=content,
        cover_image_url=_clean_optional_str(payload.get("cover_image_url")),
        tags=",".join(tags) if tags else None,
        status=status,
        author_id=user.id,
        published_at=_utcnow() if status == "published" else None,
    )
    db.add(post)
    db.flush()
    record_audit(
        db,
        user,
        "blog.create",
        "created blog post",
        post.title,
        target_id=post.id,
    )
    db.commit()
    db.refresh(post)
    return _blog_dict(post)


@router.put("/{post_id}")
async def update_blog(post_id: int, request: Request, db: DbSession, data: BlogUpdatePayload | None = Body(None)):
    user = _require_admin(request, db)
    post = db.get(BlogPost, post_id)
    if not post or post.is_deleted:
        raise HTTPException(status_code=404)

    payload = await get_payload(request, data)
    changed = False

    new_title = payload.get("title")
    if new_title is not None:
        title = str(new_title).strip()
        if not title:
            raise HTTPException(status_code=422, detail="Title cannot be empty.")
        post.title = title[:200]
        changed = True

    requested_slug = payload.get("slug")
    if requested_slug is not None:
        desired = _slugify(str(requested_slug))
        if desired != post.slug:
            post.slug = _unique_slug(db, desired, exclude_id=post.id)
            changed = True
    elif new_title is not None:
        # Title changed without an explicit slug — regenerate from the new title.
        desired = _slugify(post.title)
        if desired != post.slug:
            post.slug = _unique_slug(db, desired, exclude_id=post.id)
            changed = True

    new_content = payload.get("content")
    if new_content is not None:
        content_text = str(new_content).strip()
        if not content_text:
            raise HTTPException(status_code=422, detail="Content cannot be empty.")
        post.content = content_text
        changed = True

    if "excerpt" in payload:
        post.excerpt = _clean_optional_str(payload.get("excerpt"))
        changed = True
    if "cover_image_url" in payload:
        post.cover_image_url = _clean_optional_str(payload.get("cover_image_url"))
        changed = True
    if "tags" in payload:
        tags = _parse_tags(payload.get("tags"))
        post.tags = ",".join(tags) if tags else None
        changed = True

    new_status = payload.get("status")
    if new_status is not None:
        status = str(new_status).strip().lower()
        if status not in VALID_STATUSES:
            raise HTTPException(status_code=422, detail="Status must be 'draft' or 'published'.")
        if status != post.status:
            post.status = status
            changed = True
            if status == "published":
                post.published_at = post.published_at or _utcnow()
            else:
                post.published_at = None

    if not changed:
        return _blog_dict(post)

    record_audit(
        db,
        user,
        "blog.update",
        "updated blog post",
        post.title,
        target_id=post.id,
    )
    db.commit()
    db.refresh(post)
    return _blog_dict(post)


@router.delete("/{post_id}")
async def delete_blog(post_id: int, request: Request, db: DbSession):
    user = _require_admin(request, db)
    post = db.get(BlogPost, post_id)
    if not post or post.is_deleted:
        raise HTTPException(status_code=404)
    record_audit(
        db,
        user,
        "blog.delete",
        "deleted blog post",
        post.title,
        target_id=post.id,
    )
    move_to_bin(db, user, BinEntityType.BLOG_POST, post, title=post.title)
    db.commit()
    return {"ok": True}
