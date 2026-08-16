"""Reusable SQLAlchemy mixins for tenancy, timestamps, and soft deletion."""
from datetime import datetime, timezone
from sqlalchemy import BigInteger, Boolean, Column, DateTime, ForeignKey, Integer
from sqlalchemy.orm import declared_attr


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class TimestampMixin:
    @declared_attr
    def created_at(cls):
        return Column(DateTime, default=_utcnow, nullable=False)

    @declared_attr
    def updated_at(cls):
        return Column(DateTime, default=_utcnow, onupdate=_utcnow, nullable=True)


class SoftDeleteMixin:
    @declared_attr
    def is_deleted(cls):
        return Column(Boolean, default=False, nullable=False, index=True)

    @declared_attr
    def deleted_at(cls):
        return Column(DateTime, nullable=True)


class TenantMixin(TimestampMixin, SoftDeleteMixin):
    @declared_attr
    def organization_id(cls):
        return Column(
            BigInteger,
            ForeignKey("organizations.id", ondelete="CASCADE"),
            nullable=False,
            default=1,
            index=True,
        )
