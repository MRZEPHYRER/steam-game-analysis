"""Run only the isolated 10-AppID Steam review-query contract A/B test."""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (  # noqa: E402
    LOG_DIR,
    REVIEW_PREFLIGHT_RAW_DATA_DIR,
    REVIEW_PREFLIGHT_SAMPLE_PATH,
    REVIEW_PREFLIGHT_SNAPSHOT_PATH,
    REVIEW_QUERY_CONTRACT_COMPARISON_PATH,
    REVIEW_QUERY_CONTRACT_RAW_DATA_DIR,
    REVIEW_QUERY_CONTRACT_SAMPLE_PATH,
    STEP3B_QUERY_CONTRACT_REPORT_PATH,
)
from src.io_utils import atomic_write_csv, atomic_write_text  # noqa: E402
from src.review_contract import (  # noqa: E402
    build_query_contract_report,
    collect_query_contract_test,
    select_query_contract_sample,
)
from src.steam_client import SteamClient  # noqa: E402


def configure_logging() -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("step3b_query_contract")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    handler = logging.FileHandler(
        LOG_DIR / "step3b_query_contract.log", encoding="utf-8"
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    return logger


def main() -> int:
    logger = configure_logging()
    preflight_sample = pd.read_csv(REVIEW_PREFLIGHT_SAMPLE_PATH, low_memory=False)
    preflight_snapshot = pd.read_csv(
        REVIEW_PREFLIGHT_SNAPSHOT_PATH, low_memory=False
    )
    preflight_raw_count = len(
        list(REVIEW_PREFLIGHT_RAW_DATA_DIR.glob("review_*.json"))
    )
    if preflight_raw_count != 30:
        raise RuntimeError("Exactly 30 existing Step 3B preflight Raw files are required.")

    selection = select_query_contract_sample(
        preflight_sample,
        preflight_snapshot,
    )
    atomic_write_csv(REVIEW_QUERY_CONTRACT_SAMPLE_PATH, selection)
    with SteamClient(logger=logger) as client:
        comparison, result = collect_query_contract_test(
            client,
            selection,
            current_raw_dir=REVIEW_PREFLIGHT_RAW_DATA_DIR,
            candidate_raw_dir=REVIEW_QUERY_CONTRACT_RAW_DATA_DIR,
            output_path=REVIEW_QUERY_CONTRACT_COMPARISON_PATH,
            logger=logger,
        )
    report = build_query_contract_report(selection, comparison, result)
    atomic_write_text(STEP3B_QUERY_CONTRACT_REPORT_PATH, report)

    print("[OK] Step 3B.1 10-AppID query-contract test finished.")
    print(f"query_summary exact matches: {result.exact_matches}/10")
    print(
        "zero-review semantics: "
        f"{result.zero_review_passes}/{result.zero_review_checks}"
    )
    print(f"count identities: {result.count_identity_passes}/10")
    print(f"Step 3B.1: {'PASS' if result.passed else 'FAIL'}")
    return 0 if result.passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
