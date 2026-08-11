"""Recycle bin table and soft-delete columns.

This project uses idempotent Python migrations rather than Alembic revisions.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

SOFT_DELETE_TABLES = (
    ("users", ("is_deleted", "deleted_at")),
    ("task_comments", ("is_deleted", "deleted_at")),
    ("announcements", ("is_deleted", "deleted_at")),
    ("performance_reviews", ("is_deleted", "deleted_at")),
    ("standup_logs", ("is_deleted", "deleted_at")),
    ("cohorts", ("is_deleted", "deleted_at")),
    ("leave_requests", ("is_deleted", "deleted_at")),
)


def _add_column_if_missing(connection, table: str, column: str, ddl: str) -> None:
    connection.execute(text(f"ALTER TABLE `{table}` ADD COLUMN `{column}` {ddl}"))


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)

    if not inspector.has_table("bin_items"):
        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    CREATE TABLE `bin_items` (
                        `id` INTEGER NOT NULL AUTO_INCREMENT,
                        `entity_type` VARCHAR(40) NOT NULL,
                        `entity_id` INTEGER NOT NULL,
                        `title` VARCHAR(200) NOT NULL,
                        `deleted_by_id` INTEGER NULL,
                        `deleted_by_name` VARCHAR(120) NOT NULL DEFAULT '',
                        `deleted_at` DATETIME NOT NULL,
                        `expires_at` DATETIME NOT NULL,
                        `restored_at` DATETIME NULL,
                        `snapshot_json` TEXT NULL,
                        PRIMARY KEY (`id`),
                        INDEX `ix_bin_items_entity_type` (`entity_type`),
                        INDEX `ix_bin_items_entity_id` (`entity_id`),
                        INDEX `ix_bin_items_deleted_at` (`deleted_at`),
                        INDEX `ix_bin_items_expires_at` (`expires_at`),
                        CONSTRAINT `fk_bin_items_deleted_by_id_users`
                            FOREIGN KEY (`deleted_by_id`) REFERENCES `users` (`id`)
                            ON DELETE SET NULL
                    )
                    """
                )
            )

    for table, columns in SOFT_DELETE_TABLES:
        if not inspector.has_table(table):
            continue
        existing = {c["name"] for c in inspector.get_columns(table)}
        with engine.begin() as connection:
            if "is_deleted" not in existing:
                _add_column_if_missing(
                    connection,
                    table,
                    "is_deleted",
                    "BOOL NOT NULL DEFAULT 0",
                )
            if "deleted_at" not in existing:
                _add_column_if_missing(
                    connection,
                    table,
                    "deleted_at",
                    "DATETIME NULL",
                )
