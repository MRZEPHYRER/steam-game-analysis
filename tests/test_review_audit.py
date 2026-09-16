from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from src.io_utils import atomic_write_json
from src.review_audit import (
    audit_raw_and_spot_check,
    audit_snapshot_tables,
    build_final_audit_report,
)
from src.reviews import review_request_params


COLLECTED_AT = "2026-09-14T01:00:00+00:00"


def frames(size: int = 30) -> tuple[pd.DataFrame, pd.DataFrame]:
    appids = list(range(1, size + 1))
    games = pd.DataFrame({"appid": appids})
    rows = []
    for appid in appids:
        total = 0 if appid % 5 == 0 else 10
        positive = 0 if total == 0 else 8
        rows.append(
            {
                "appid": appid,
                "total_reviews": total,
                "positive_reviews": positive,
                "negative_reviews": total - positive,
                "positive_rate": None if total == 0 else positive / total,
                "review_score": 0 if total == 0 else 8,
                "review_score_desc": (
                    "No user reviews" if total == 0 else "Very Positive"
                ),
                "review_language": "all",
                "review_purchase_type": "steam",
                "review_type": "all",
                "filter_offtopic_activity": 1,
                "day_range": 365,
                "review_collected_at": COLLECTED_AT,
                "review_status": "success",
            }
        )
    return games, pd.DataFrame(rows)


def write_raw(raw_dir: Path, row: pd.Series) -> None:
    total = int(row["total_reviews"])
    positive = int(row["positive_reviews"])
    atomic_write_json(
        raw_dir / f"review_{int(row['appid']):010d}.json",
        {
            "appid": int(row["appid"]),
            "requested_at": COLLECTED_AT,
            "request_params": review_request_params(),
            "http_status": 200,
            "payload": {
                "success": 1,
                "query_summary": {
                    "total_positive": positive,
                    "total_negative": int(row["negative_reviews"]),
                    "total_reviews": total,
                    "review_score": int(row["review_score"]),
                    "review_score_desc": row["review_score_desc"],
                },
                "reviews": [],
            },
        },
    )


def test_snapshot_audit_covers_counts_rates_contract_and_timestamps() -> None:
    games, snapshot = frames()
    audit = audit_snapshot_tables(games, snapshot)
    assert audit["missing_review_appids"] == 0
    assert audit["count_identity_failures"] == 0
    assert audit["zero_review_count"] == 6
    assert audit["zero_semantic_failures"] == 0
    assert audit["positive_rate_failures"] == 0
    assert audit["zero_rate_failures"] == 0
    assert sum(audit["snapshot_contract_drift"].values()) == 0
    assert audit["missing_timestamps"] == 0
    assert audit["unparseable_timestamps"] == 0


def test_snapshot_audit_detects_rate_timestamp_and_contract_drift() -> None:
    games, snapshot = frames()
    snapshot.loc[0, "positive_rate"] = 0.5
    snapshot.loc[1, "review_collected_at"] = "not-a-time"
    snapshot.loc[2, "day_range"] = 30
    audit = audit_snapshot_tables(games, snapshot)
    assert audit["positive_rate_failures"] == 1
    assert audit["unparseable_timestamps"] == 1
    assert audit["snapshot_contract_drift"]["day_range"] == 1


def test_raw_coverage_and_spot_check_are_deterministic(tmp_path: Path) -> None:
    games, snapshot = frames()
    raw_dir = tmp_path / "raw"
    for _, row in snapshot.iterrows():
        write_raw(raw_dir, row)
    first = audit_raw_and_spot_check(
        games, snapshot, raw_dir, spot_size=10
    )
    second = audit_raw_and_spot_check(
        games, snapshot, raw_dir, spot_size=10
    )
    assert first["raw_files"] == first["raw_unique_appids"] == 30
    assert first["missing_raw_appids"] == first["extra_raw_appids"] == 0
    assert first["raw_contract_drift_files"] == 0
    assert first["spot_matches"] == 10
    assert first["spot_mismatches"] == []
    assert first["spot_appids"] == second["spot_appids"]


def test_raw_spot_check_reports_a_field_mismatch(tmp_path: Path) -> None:
    games, snapshot = frames()
    raw_dir = tmp_path / "raw"
    for _, row in snapshot.iterrows():
        write_raw(raw_dir, row)
    selected = audit_raw_and_spot_check(
        games, snapshot, raw_dir, spot_size=1
    )["spot_appids"][0]
    raw_path = raw_dir / f"review_{selected:010d}.json"
    raw = json.loads(raw_path.read_text(encoding="utf-8"))
    raw["payload"]["query_summary"]["total_positive"] += 1
    atomic_write_json(raw_path, raw)
    audit = audit_raw_and_spot_check(
        games, snapshot, raw_dir, spot_size=1
    )
    assert audit["spot_matches"] == 0
    assert "total_positive" in audit["spot_mismatches"][0]


def test_final_audit_report_records_fingerprint_and_decision(
    tmp_path: Path,
) -> None:
    games, snapshot = frames()
    raw_dir = tmp_path / "raw"
    for _, row in snapshot.iterrows():
        write_raw(raw_dir, row)
    report = build_final_audit_report(
        audit_snapshot_tables(games, snapshot),
        audit_raw_and_spot_check(
            games, snapshot, raw_dir, spot_size=10
        ),
        frozen_hashes_before={"games.csv": "ABC"},
        frozen_hashes_after={"games.csv": "ABC"},
        snapshot_sha256="DEF",
        passed=True,
    )
    assert "HTTP requests made by this audit: **0**" in report
    assert "review_snapshots.csv" in report
    assert "DEF" in report
    assert "Step 3B Final Audit: PASS" in report
    assert "Review dataset: FROZEN" in report
