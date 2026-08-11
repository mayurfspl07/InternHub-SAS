"""Add nullable task creator ownership.

This project uses idempotent Python migrations rather than Alembic revisions.
"""
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


CONSTRAINT_NAME = "fk_tasks_created_by_id_users"


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    if not inspector.has_table("tasks"):
        return

    columns = {column["name"] for column in inspector.get_columns("tasks")}
    if "created_by_id" not in columns:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "ALTER TABLE `tasks` "
                    "ADD COLUMN `created_by_id` INTEGER NULL"
                )
            )

    inspector = inspect(engine)
    indexes = inspector.get_indexes("tasks")
    has_creator_index = any(
        index.get("column_names") == ["created_by_id"] for index in indexes
    )
    if not has_creator_index:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE INDEX `ix_tasks_created_by_id` "
                    "ON `tasks` (`created_by_id`)"
                )
            )

    inspector = inspect(engine)
    foreign_keys = inspector.get_foreign_keys("tasks")
    has_creator_foreign_key = any(
        foreign_key.get("referred_table") == "users"
        and foreign_key.get("constrained_columns") == ["created_by_id"]
        for foreign_key in foreign_keys
    )
    if not has_creator_foreign_key:
        with engine.begin() as connection:
            connection.execute(
                text(
                    f"ALTER TABLE `tasks` ADD CONSTRAINT `{CONSTRAINT_NAME}` "
                    "FOREIGN KEY (`created_by_id`) REFERENCES `users` (`id`) "
                    "ON DELETE SET NULL"
                )
            )

