"""Pagination utilities and response schemas.

Every list endpoint must return the same envelope shape:

    { items: T[], page: int, page_size: int, total: int, total_pages: int }

`get_page_params` reads + sanitizes ?page / ?page_size (page is 1-based;
page_size is hard-capped at PAGE_SIZE_MAX so callers can never get an
unbounded dump back once page_size is set).
"""
import math
from typing import Generic, Sequence, TypeVar
from pydantic import BaseModel

from app.core.constants import PAGE_SIZE_DEFAULT, PAGE_SIZE_MAX

T = TypeVar("T")


class PaginatedResponse(BaseModel, Generic[T]):
    items: Sequence[T]
    page: int
    page_size: int
    total_pages: int
    total: int


def get_page_params(request, default_page_size: int = PAGE_SIZE_DEFAULT) -> tuple[int, int]:
    """Read and sanitize ?page / ?page_size from the request query string.

    - page < 1 or non-numeric  -> 1
    - page_size < 1            -> default_page_size
    - page_size > PAGE_SIZE_MAX -> PAGE_SIZE_MAX
    Works with both live FastAPI requests and the hand-built starlette Request
    objects used in unit tests.
    """
    params = request.query_params
    try:
        page = int(params.get("page", 1))
    except (TypeError, ValueError):
        page = 1
    try:
        page_size = int(params.get("page_size", default_page_size))
    except (TypeError, ValueError):
        page_size = default_page_size
    page = max(1, page)
    page_size = max(1, min(PAGE_SIZE_MAX, page_size))
    return page, page_size


def build_page_response(items: Sequence[T], page: int, page_size: int, total: int) -> dict:
    """Assemble the canonical paginated envelope."""
    total_pages = math.ceil(total / page_size) if total > 0 else 1
    return {
        "items": list(items),
        "page": page,
        "page_size": page_size,
        "total": total,
        "total_pages": total_pages,
    }


def calculate_pagination(total: int, page: int, page_size: int) -> tuple[int, int, int]:
    """Calculate sanitized (page, page_size, total_pages)."""
    p = max(1, page)
    ps = max(1, min(PAGE_SIZE_MAX, page_size or PAGE_SIZE_DEFAULT))
    tp = math.ceil(total / ps) if total > 0 else 1
    return p, ps, tp
