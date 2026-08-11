"""Create MySQL database and tables."""
import sys

from sqlalchemy import create_engine, text

from config import Config
from database import Base, engine
from models import Attendance, LeaveRequest, Notification, Project, ProjectAssignment, Task, User  # noqa: F401


def create_database() -> None:
    server_engine = create_engine(Config.server_url(), isolation_level="AUTOCOMMIT")
    db_name = Config.MYSQL_DATABASE
    with server_engine.connect() as conn:
        conn.execute(
            text(
                f"CREATE DATABASE IF NOT EXISTS `{db_name}` "
                "CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
        )
    server_engine.dispose()
    print(f"[OK] Database '{db_name}' ready.")


def create_tables() -> None:
    Base.metadata.create_all(bind=engine)
    print("[OK] Tables created.")


if __name__ == "__main__":
    try:
        create_database()
        create_tables()
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        print(
            "\nMake sure MySQL is running and credentials in .env are correct.",
            file=sys.stderr,
        )
        sys.exit(1)
