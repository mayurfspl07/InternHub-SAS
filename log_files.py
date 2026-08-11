"""Write application logs to the project ``logs/`` directory."""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone

from config import Config

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
LOGS_DIR = os.path.join(BASE_DIR, "logs")
ACTIVITY_LOG = os.path.join(LOGS_DIR, "activity.log")
TERMINAL_LOG = os.path.join(LOGS_DIR, "terminal.log")

_terminal_configured = False


def ensure_logs_dir() -> str:
    os.makedirs(LOGS_DIR, exist_ok=True)
    return LOGS_DIR


def _utc_iso(value: datetime | None = None) -> str:
    value = value or datetime.now(timezone.utc)
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    else:
        value = value.astimezone(timezone.utc)
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write_activity_log(
    *,
    created_at: datetime | None = None,
    actor_id: int | None,
    actor_name: str,
    action: str,
    verb: str,
    target: str,
    target_id: int | None = None,
    project_id: int | None = None,
    affected_user_id: int | None = None,
) -> None:
    ensure_logs_dir()
    entry = {
        "ts": _utc_iso(created_at),
        "actor_id": actor_id,
        "actor_name": actor_name,
        "action": action,
        "verb": verb,
        "target": target,
        "target_id": target_id,
        "project_id": project_id,
        "affected_user_id": affected_user_id,
    }
    with open(ACTIVITY_LOG, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


def setup_terminal_logging() -> logging.Logger:
    """Route application messages to ``logs/terminal.log`` and the console."""
    global _terminal_configured
    ensure_logs_dir()
    logger = logging.getLogger("internhub")
    if _terminal_configured:
        return logger

    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")

    file_handler = logging.FileHandler(TERMINAL_LOG, encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    _terminal_configured = True
    logger.info("Terminal logging initialized (logs/terminal.log)")
    return logger
