"""Collect/resume the formal 3,000-game Steam review summary snapshot."""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (  # noqa: E402
    FROZEN_INPUT_SHA256,
    GAMES_PATH,
    LOG_DIR,
    REVIEW_COLLECTION_AUDIT_PATH,
    REVIEW_FULL_RAW_DATA_DIR,
    REVIEW_SNAPSHOTS_PATH,
    STEP3B_FULL_REVIEW_REPORT_PATH,
    TARGET_SAMPLE_SIZE,
)
from src.io_utils import atomic_write_text  # noqa: E402
from src.review_full import (  # noqa: E402
    FrozenInputError,
    ReviewCountIdentityBlock,
    ReviewFinalizationError,
    ReviewTechnicalFailureBlock,
    build_full_review_report,
    finalize_review_snapshot,
    validate_frozen_inputs_unchanged,
    validate_review_source,
    verify_frozen_inputs,
)
from src.reviews import collect_review_snapshots, review_request_params  # noqa: E402
from src.steam_client import SteamClient  # noqa: E402


def configure_logging() -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("step3b_full_reviews")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    handler = logging.FileHandler(
        LOG_DIR / "step3b_full_reviews.log",
        encoding="utf-8",
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    return logger


def main() -> int:
    logger = configure_logging()
    print("[START] Step 3B.2 full review snapshot collection")
    print(f"[CONTRACT] {review_request_params()}")
    try:
        frozen_before = verify_frozen_inputs(FROZEN_INPUT_SHA256)
        games = pd.read_csv(GAMES_PATH, low_memory=False)
        validate_review_source(games, expected_size=TARGET_SAMPLE_SIZE)
    except ReviewFinalizationError as exc:
        print(f"[BLOCK] {exc}")
        return 2

    try:
        with SteamClient(logger=logger) as client:
            snapshot, stats = collect_review_snapshots(
                client,
                games,
                raw_dir=REVIEW_FULL_RAW_DATA_DIR,
                output_path=REVIEW_COLLECTION_AUDIT_PATH,
                logger=logger,
                required_request_params=review_request_params(),
            )
    except KeyboardInterrupt:
        try:
            frozen_after_interrupt = verify_frozen_inputs(FROZEN_INPUT_SHA256)
            validate_frozen_inputs_unchanged(
                frozen_before,
                frozen_after_interrupt,
            )
        except FrozenInputError as exc:
            print(f"[BLOCK] {exc}")
            return 2
        print("[STOP] Collection interrupted; completed Raw files were preserved.")
        print("[RESUME] Run the same command again; --restart is not required.")
        return 130

    try:
        frozen_after = verify_frozen_inputs(FROZEN_INPUT_SHA256)
        validate_frozen_inputs_unchanged(frozen_before, frozen_after)
    except FrozenInputError as exc:
        print(f"[BLOCK] {exc}")
        return 2

    try:
        finalize_review_snapshot(
            games,
            snapshot,
            output_path=REVIEW_SNAPSHOTS_PATH,
            expected_size=TARGET_SAMPLE_SIZE,
        )
        finalized = True
        block: ReviewFinalizationError | None = None
    except ReviewFinalizationError as exc:
        finalized = False
        block = exc

    report = build_full_review_report(
        source=games,
        snapshot=snapshot,
        stats=stats,
        raw_dir=REVIEW_FULL_RAW_DATA_DIR,
        frozen_before=frozen_before,
        frozen_after=frozen_after,
        finalized=finalized,
    )
    atomic_write_text(STEP3B_FULL_REVIEW_REPORT_PATH, report)

    if not finalized:
        assert block is not None
        if isinstance(block, ReviewTechnicalFailureBlock):
            if block.request_failed:
                print("[BLOCK] unresolved request failures")
                print("[RESUME] Run the same command again to retry request_error Raw.")
            if block.schema_invalid:
                print("[BLOCK] schema-invalid review response(s)")
                print("[REVIEW] Inspect AppIDs in the log; repeated refetch is disabled.")
        elif isinstance(block, ReviewCountIdentityBlock):
            print("[BLOCK] review count/positive-rate integrity failure")
        else:
            print(f"[BLOCK] {block}")
        return 2

    print("[OK] Step 3B.2 full review snapshot finalized.")
    print(f"rows: {len(snapshot)}")
    print(f"success: {(snapshot['review_status'] == 'success').sum()}")
    print(f"unavailable: {(snapshot['review_status'] == 'unavailable').sum()}")
    print(f"new: {stats.newly_requested}")
    print(f"reused: {stats.reused}")
    print(f"retried: {stats.retried_failed_raw}")
    print(f"elapsed_seconds: {stats.elapsed_seconds:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
