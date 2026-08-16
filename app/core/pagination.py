"""Pagination utilities and response schemas."""
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
    total_count: int


def calculate_pagination(total: int, page: int, page_size: int) -> tuple[int, int, int]:
    """Calculate sanitized (page, page_size, total_pages)."""
    p = max(1, page)
    ps = max(1, min(PAGE_SIZE_MAX, page_size or PAGE_SIZE_DEFAULT))
    tp = math.ceil(total / ps) if total > 0 else 1
    return p, ps, tp
