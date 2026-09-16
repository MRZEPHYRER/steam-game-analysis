"""Small shared helpers used by collection and ETL scripts."""

from __future__ import annotations

from datetime import datetime, timezone

import os
from pathlib import Path

from config.settings import (
    APPDETAILS_RAW_DATA_DIR,
    APPDETAILS_PREFLIGHT_RAW_DATA_DIR,
    CATALOG_RAW_DATA_DIR,
    INTERIM_DATA_DIR,
    LOG_DIR,
    PROCESSED_DATA_DIR,
    RAW_DATA_DIR,
    REPORT_DIR,
    SEARCH_RAW_DATA_DIR,
)


def utc_now() -> datetime:
    """Return a timezone-aware UTC timestamp for snapshot fields."""
    return datetime.now(timezone.utc)


def ensure_data_directories() -> None:
    """Create portable data-layer directories when an executable step needs them."""
    for directory in (
        RAW_DATA_DIR,
        INTERIM_DATA_DIR,
        PROCESSED_DATA_DIR,
        SEARCH_RAW_DATA_DIR,
        CATALOG_RAW_DATA_DIR,
        APPDETAILS_RAW_DATA_DIR,
        APPDETAILS_PREFLIGHT_RAW_DATA_DIR,
        LOG_DIR,
        REPORT_DIR,
    ):
        directory.mkdir(parents=True, exist_ok=True)


def load_local_env(env_path: Path) -> None:
    """Load only simple KEY=VALUE entries without overwriting the environment."""
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key == "STEAM_API_KEY" and value:
            os.environ.setdefault(key, value)
