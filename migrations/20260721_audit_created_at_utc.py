"""Store audit timestamps as UTC values with microsecond precision.

MySQL DATETIME does not retain an offset. Existing values were already
generated in UTC, so this migration preserves them and adds fractional-second
precision. The API restores the explicit UTC offset when serializing.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not inspector.has_table("audit_logs"):
        return

    if engine.dialect.name != "mysql":
        return

    created_at = next(
        (
            column
            for column in inspector.get_columns("audit_logs")
            if column["name"] == "created_at"
        ),
        None,
    )
    if created_at is None:
        return

    if getattr(created_at["type"], "fsp", None) == 6:
        return

    with engine.begin() as connection:
        connection.execute(
            text(
                "ALTER TABLE `audit_logs` "
                "MODIFY COLUMN `created_at` DATETIME(6) NOT NULL"
            )
        )

