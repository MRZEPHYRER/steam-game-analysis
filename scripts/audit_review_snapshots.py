"""Run the purely local Step 3B final review-snapshot audit."""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (  # noqa: E402
    FROZEN_INPUT_SHA256,
    GAMES_PATH,
    REVIEW_FULL_RAW_DATA_DIR,
    REVIEW_SNAPSHOTS_PATH,
    STEP3B_FINAL_AUDIT_REPORT_PATH,
)
from src.io_utils import atomic_write_text  # noqa: E402
from src.review_audit import (  # noqa: E402
    audit_passed,
    audit_raw_and_spot_check,
    audit_snapshot_tables,
    build_final_audit_report,
)
from src.review_full import (  # noqa: E402
    sha256_file,
    validate_frozen_inputs_unchanged,
    verify_frozen_inputs,
)


def _stringify_hashes(hashes: dict[Path, str]) -> dict[str, str]:
    return {
        str(path.relative_to(PROJECT_ROOT)): digest
        for path, digest in hashes.items()
    }


def main() -> int:
    print("[START] Step 3B final audit (local files only; HTTP requests: 0)")
    frozen_before = verify_frozen_inputs(FROZEN_INPUT_SHA256)
    snapshot_hash_before = sha256_file(REVIEW_SNAPSHOTS_PATH)
    games = pd.read_csv(GAMES_PATH, low_memory=False)
    snapshot = pd.read_csv(REVIEW_SNAPSHOTS_PATH, low_memory=False)

    snapshot_audit = audit_snapshot_tables(games, snapshot)
    raw_audit = audit_raw_and_spot_check(
        games,
        snapshot,
        REVIEW_FULL_RAW_DATA_DIR,
    )

    frozen_after = verify_frozen_inputs(FROZEN_INPUT_SHA256)
    validate_frozen_inputs_unchanged(frozen_before, frozen_after)
    snapshot_hash_after = sha256_file(REVIEW_SNAPSHOTS_PATH)
    snapshot_preserved = snapshot_hash_before == snapshot_hash_after
    passed = (
        snapshot_preserved
        and audit_passed(
            snapshot_audit,
            raw_audit,
            frozen_inputs_preserved=True,
        )
    )
    report = build_final_audit_report(
        snapshot_audit,
        raw_audit,
        frozen_hashes_before=_stringify_hashes(frozen_before),
        frozen_hashes_after=_stringify_hashes(frozen_after),
        snapshot_sha256=snapshot_hash_after,
        passed=passed,
    )
    atomic_write_text(STEP3B_FINAL_AUDIT_REPORT_PATH, report)

    statuses = snapshot_audit["status_counts"]
    print(
        "[COVERAGE] "
        f"{snapshot_audit['snapshot_rows']}/"
        f"{snapshot_audit['games_rows']} rows"
    )
    print(
        "[STATUS] "
        f"success={statuses['success']} unavailable={statuses['unavailable']} "
        f"request_failed={statuses['request_failed']} "
        f"schema_invalid={statuses['schema_invalid']}"
    )
    print(
        "[SPOT CHECK] "
        f"{raw_audit['spot_matches']}/{raw_audit['spot_size']} exact matches"
    )
    print(f"[HASH] review_snapshots.csv={snapshot_hash_after}")
    print(f"[RESULT] Step 3B Final Audit: {'PASS' if passed else 'FAIL'}")
    print(f"[RESULT] Review dataset: {'FROZEN' if passed else 'NOT FROZEN'}")
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
