"""SQLAlchemy engine and session factory."""
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from config import Config

# Smaller pools by default on Railway (single dyno); override via env if needed.
_pool_size = int(os.environ.get("DB_POOL_SIZE", "5" if Config.IS_PRODUCTION else "10"))
_max_overflow = int(os.environ.get("DB_MAX_OVERFLOW", "10" if Config.IS_PRODUCTION else "20"))

db_url = Config.database_url()
engine_kwargs = {"pool_pre_ping": True}
if db_url.startswith("sqlite"):
    engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    engine_kwargs.update({
        "pool_recycle": 280,
        "pool_size": _pool_size,
        "max_overflow": _max_overflow,
    })

engine = create_engine(db_url, **engine_kwargs)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass  # don't mask the original exception with a rollback failure
        raise
    finally:
        db.close()
