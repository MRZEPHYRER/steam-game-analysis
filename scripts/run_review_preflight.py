"""Run only the deterministic 30-AppID Steam review-summary preflight."""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (  # noqa: E402
    GAMES_PATH,
    LOG_DIR,
    REVIEW_PREFLIGHT_RAW_DATA_DIR,
    REVIEW_PREFLIGHT_SAMPLE_PATH,
    REVIEW_PREFLIGHT_SIZE,
    REVIEW_PREFLIGHT_SNAPSHOT_PATH,
    STEP3B_PREFLIGHT_REPORT_PATH,
)
from src.io_utils import atomic_write_csv, atomic_write_text  # noqa: E402
from src.reviews import (  # noqa: E402
    build_review_preflight_report,
    collect_review_snapshots,
    select_review_preflight_sample,
)
from src.steam_client import SteamClient  # noqa: E402


def configure_logging() -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("step3b_review_preflight")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    file_handler = logging.FileHandler(
        LOG_DIR / "step3b_review_preflight.log", encoding="utf-8"
    )
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    logger.addHandler(file_handler)
    return logger


def main() -> int:
    logger = configure_logging()
    games = pd.read_csv(GAMES_PATH, low_memory=False)
    if len(games) != 3_000 or games["appid"].nunique() != 3_000:
        raise RuntimeError("Frozen games source must contain 3,000 unique AppIDs.")
    sample = select_review_preflight_sample(
        games,
        sample_size=REVIEW_PREFLIGHT_SIZE,
    )
    atomic_write_csv(REVIEW_PREFLIGHT_SAMPLE_PATH, sample)

    with SteamClient(logger=logger) as client:
        snapshot, stats = collect_review_snapshots(
            client,
            sample,
            raw_dir=REVIEW_PREFLIGHT_RAW_DATA_DIR,
            output_path=REVIEW_PREFLIGHT_SNAPSHOT_PATH,
            logger=logger,
        )
    report = build_review_preflight_report(
        source_population_size=len(games),
        sample=sample,
        snapshot=snapshot,
        stats=stats,
        raw_dir=REVIEW_PREFLIGHT_RAW_DATA_DIR,
    )
    atomic_write_text(STEP3B_PREFLIGHT_REPORT_PATH, report)

    print("[OK] Step 3B 30-AppID review preflight finished.")
    print(f"success: {(snapshot['review_status'] == 'success').sum()}")
    print(f"request_failed: {stats.request_failed}")
    print(f"schema_invalid: {stats.schema_invalid}")
    print(f"unavailable: {stats.unavailable}")
    clean = (
        stats.request_failed == 0
        and stats.schema_invalid == 0
        and stats.unavailable == 0
    )
    return 0 if clean else 2


if __name__ == "__main__":
    raise SystemExit(main())
