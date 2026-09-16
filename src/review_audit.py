"""Purely local final audit for the frozen full review snapshot."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from src.reviews import review_request_params


AUDIT_SEED = 20_250_911
SPOT_CHECK_SIZE = 30
SNAPSHOT_CONTRACT = {
    "review_language": "all",
    "review_purchase_type": "steam",
    "review_type": "all",
    "filter_offtopic_activity": 1,
    "day_range": 365,
}
SUMMARY_FIELDS = [
    ("total_positive", "positive_reviews"),
    ("total_negative", "negative_reviews"),
    ("total_reviews", "total_reviews"),
    ("review_score", "review_score"),
    ("review_score_desc", "review_score_desc"),
]


class ReviewAuditError(RuntimeError):
    """The local audit cannot be completed safely."""


def _normalized_appids(frame: pd.DataFrame, label: str) -> pd.Series:
    if "appid" not in frame:
        raise ReviewAuditError(f"{label} is missing appid.")
    values = pd.to_numeric(frame["appid"], errors="coerce")
    if values.isna().any() or values.dropna().mod(1).ne(0).any():
        raise ReviewAuditError(f"{label} contains invalid AppIDs.")
    return values.astype("int64")


def _nullable_equal(left: Any, right: Any) -> bool:
    if pd.isna(left) and right is None:
        return True
    if pd.isna(left) and pd.isna(right):
        return True
    return type(left) is type(right) and left == right


def _distribution(values: pd.Series) -> dict[str, int]:
    return {
        "zero": int(values.eq(0).sum()),
        "1-9": int(values.between(1, 9).sum()),
        "10-19": int(values.between(10, 19).sum()),
        "20-49": int(values.between(20, 49).sum()),
        "50-99": int(values.between(50, 99).sum()),
        "100-499": int(values.between(100, 499).sum()),
        "500-999": int(values.between(500, 999).sum()),
        "1000+": int(values.ge(1000).sum()),
    }


def _six_number_summary(values: pd.Series) -> dict[str, float]:
    if values.empty:
        return {
            key: float("nan")
            for key in ["min", "q1", "median", "mean", "q3", "max"]
        }
    return {
        "min": float(values.min()),
        "q1": float(values.quantile(0.25)),
        "median": float(values.median()),
        "mean": float(values.mean()),
        "q3": float(values.quantile(0.75)),
        "max": float(values.max()),
    }


def audit_snapshot_tables(
    games: pd.DataFrame,
    snapshot: pd.DataFrame,
) -> dict[str, Any]:
    """Audit coverage, status, counts, rates, contract, and timestamps."""
    required = {
        "appid",
        "total_reviews",
        "positive_reviews",
        "negative_reviews",
        "positive_rate",
        "review_score",
        "review_score_desc",
        "review_collected_at",
        "review_status",
        *SNAPSHOT_CONTRACT,
    }
    missing_columns = required.difference(snapshot.columns)
    if missing_columns:
        raise ReviewAuditError(
            f"review_snapshots.csv is missing {sorted(missing_columns)}."
        )
    game_ids = _normalized_appids(games, "games.csv")
    snapshot_ids = _normalized_appids(snapshot, "review_snapshots.csv")
    game_set = set(game_ids)
    snapshot_set = set(snapshot_ids)
    status_counts = snapshot["review_status"].value_counts(dropna=False)
    successful = snapshot.loc[snapshot["review_status"] == "success"].copy()

    counts = {
        field: pd.to_numeric(successful[field], errors="coerce")
        for field in ["total_reviews", "positive_reviews", "negative_reviews"]
    }
    invalid_count_values = int(
        sum(
            series.isna().sum() + series.dropna().mod(1).ne(0).sum()
            for series in counts.values()
        )
    )
    negative_count_failures = int(
        sum(series.dropna().lt(0).sum() for series in counts.values())
    )
    identity_failures = int(
        (
            counts["positive_reviews"]
            + counts["negative_reviews"]
            != counts["total_reviews"]
        ).sum()
    )

    rates = pd.to_numeric(successful["positive_rate"], errors="coerce")
    nonzero = counts["total_reviews"].gt(0)
    zero = counts["total_reviews"].eq(0)
    expected_rate = (
        counts["positive_reviews"].loc[nonzero]
        / counts["total_reviews"].loc[nonzero]
    )
    actual_rate = rates.loc[nonzero]
    positive_rate_failures = int(
        (
            ~np.isclose(
                actual_rate.fillna(np.inf),
                expected_rate,
                rtol=0,
                atol=1e-12,
            )
        ).sum()
    )
    zero_rate_failures = int(rates.loc[zero].notna().sum())
    range_failures = int(
        (rates.dropna().lt(0) | rates.dropna().gt(1)).sum()
    )
    zero_rows = successful.loc[zero]
    zero_semantic_failures = int(
        (
            zero_rows["positive_reviews"].ne(0)
            | zero_rows["negative_reviews"].ne(0)
            | zero_rows["positive_rate"].notna()
            | zero_rows["review_status"].ne("success")
        ).sum()
    )

    totals = counts["total_reviews"].dropna()
    positive_values = rates.loc[nonzero].dropna()
    threshold_counts = {
        threshold: int(totals.ge(threshold).sum())
        for threshold in [10, 20, 50]
    }
    contract_drift: dict[str, int] = {}
    for field, expected in SNAPSHOT_CONTRACT.items():
        contract_drift[field] = int(snapshot[field].ne(expected).sum())

    raw_timestamps = snapshot["review_collected_at"]
    missing_timestamp = raw_timestamps.isna() | raw_timestamps.astype(
        "string"
    ).str.strip().eq("")
    parsed_timestamps = pd.to_datetime(
        raw_timestamps.where(~missing_timestamp),
        errors="coerce",
        utc=True,
    )
    unparseable_timestamp = (~missing_timestamp) & parsed_timestamps.isna()
    valid_timestamps = parsed_timestamps.dropna()
    timestamp_min = valid_timestamps.min() if not valid_timestamps.empty else None
    timestamp_max = valid_timestamps.max() if not valid_timestamps.empty else None
    duration_seconds = (
        float((timestamp_max - timestamp_min).total_seconds())
        if timestamp_min is not None and timestamp_max is not None
        else None
    )
    score_desc = snapshot["review_score_desc"].astype("string")
    missing_desc = snapshot["review_score_desc"].isna() | score_desc.str.strip().eq("")

    return {
        "games_rows": len(games),
        "games_unique_appids": int(game_ids.nunique()),
        "snapshot_rows": len(snapshot),
        "snapshot_unique_appids": int(snapshot_ids.nunique()),
        "missing_review_appids": len(game_set.difference(snapshot_set)),
        "external_review_appids": len(snapshot_set.difference(game_set)),
        "duplicate_review_appids": int(snapshot_ids.duplicated().sum()),
        "status_counts": {
            status: int(status_counts.get(status, 0))
            for status in [
                "success",
                "unavailable",
                "request_failed",
                "schema_invalid",
            ]
        },
        "invalid_count_values": invalid_count_values,
        "negative_count_failures": negative_count_failures,
        "count_identity_failures": identity_failures,
        "positive_rate_failures": positive_rate_failures,
        "zero_rate_failures": zero_rate_failures,
        "positive_rate_range_failures": range_failures,
        "zero_review_count": int(zero.sum()),
        "zero_semantic_failures": zero_semantic_failures,
        "review_volume_distribution": _distribution(totals),
        "review_volume_summary": _six_number_summary(totals),
        "threshold_counts": threshold_counts,
        "threshold_percentages": {
            threshold: count / len(snapshot)
            for threshold, count in threshold_counts.items()
        },
        "positive_rate_available": int(rates.notna().sum()),
        "positive_rate_null": int(rates.isna().sum()),
        "positive_rate_nonzero_null": int(rates.loc[nonzero].isna().sum()),
        "positive_rate_summary": _six_number_summary(positive_values),
        "missing_review_score": int(snapshot["review_score"].isna().sum()),
        "missing_review_score_desc": int(missing_desc.sum()),
        "review_score_counts": {
            str(key): int(value)
            for key, value in snapshot["review_score"]
            .value_counts(dropna=False)
            .sort_index()
            .items()
        },
        "review_score_desc_counts": {
            str(key): int(value)
            for key, value in snapshot["review_score_desc"]
            .value_counts(dropna=False)
            .items()
        },
        "snapshot_contract_drift": contract_drift,
        "missing_timestamps": int(missing_timestamp.sum()),
        "unparseable_timestamps": int(unparseable_timestamp.sum()),
        "timestamp_min": timestamp_min.isoformat() if timestamp_min is not None else None,
        "timestamp_max": timestamp_max.isoformat() if timestamp_max is not None else None,
        "collection_window_seconds": duration_seconds,
    }


def audit_raw_and_spot_check(
    games: pd.DataFrame,
    snapshot: pd.DataFrame,
    raw_dir: Path,
    *,
    seed: int = AUDIT_SEED,
    spot_size: int = SPOT_CHECK_SIZE,
) -> dict[str, Any]:
    """Audit every local Raw wrapper, then compare a deterministic 30-row sample."""
    game_ids = sorted(set(_normalized_appids(games, "games.csv")))
    if spot_size > len(game_ids):
        raise ReviewAuditError("Spot-check size exceeds the game population.")
    raw_files = sorted(raw_dir.glob("review_*.json"))
    wrapper_ids: list[int] = []
    raw_by_appid: dict[int, dict[str, Any]] = {}
    malformed_raw = 0
    request_error_raw = 0
    invalid_response_raw = 0
    contract_drift_files = 0
    parameter_drift = {key: 0 for key in review_request_params()}

    for path in raw_files:
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            malformed_raw += 1
            continue
        if not isinstance(raw, dict):
            malformed_raw += 1
            continue
        appid = raw.get("appid")
        if isinstance(appid, bool) or not isinstance(appid, int):
            malformed_raw += 1
            continue
        wrapper_ids.append(appid)
        raw_by_appid.setdefault(appid, raw)
        if "request_error" in raw:
            request_error_raw += 1
        status = raw.get("http_status")
        payload = raw.get("payload")
        if (
            "request_error" not in raw
            and (
                isinstance(status, bool)
                or not isinstance(status, int)
                or not 200 <= status < 300
                or not isinstance(payload, dict)
            )
        ):
            invalid_response_raw += 1
        params = raw.get("request_params")
        expected_params = review_request_params()
        if params != expected_params:
            contract_drift_files += 1
        if not isinstance(params, dict):
            for key in parameter_drift:
                parameter_drift[key] += 1
        else:
            for key, expected in expected_params.items():
                if params.get(key) != expected:
                    parameter_drift[key] += 1

    game_set = set(game_ids)
    raw_set = set(wrapper_ids)
    rng = np.random.default_rng(seed)
    spot_appids = sorted(
        int(value)
        for value in rng.choice(
            np.asarray(game_ids, dtype="int64"),
            size=spot_size,
            replace=False,
        )
    )
    indexed_snapshot = snapshot.set_index("appid", verify_integrity=True)
    spot_mismatches: list[str] = []
    spot_matches = 0
    for appid in spot_appids:
        raw = raw_by_appid.get(appid)
        if raw is None or appid not in indexed_snapshot.index:
            spot_mismatches.append(f"appid={appid}: missing Raw or snapshot")
            continue
        payload = raw.get("payload")
        summary = payload.get("query_summary") if isinstance(payload, dict) else None
        if not isinstance(summary, dict):
            spot_mismatches.append(f"appid={appid}: missing query_summary")
            continue
        row = indexed_snapshot.loc[appid]
        field_failures: list[str] = []
        for source_field, snapshot_field in SUMMARY_FIELDS:
            source_value = summary.get(source_field)
            snapshot_value = row[snapshot_field]
            if source_field == "review_score_desc":
                matches = _nullable_equal(snapshot_value, source_value)
            elif source_value is None:
                matches = pd.isna(snapshot_value)
            else:
                try:
                    matches = float(snapshot_value) == float(source_value)
                except (TypeError, ValueError):
                    matches = False
            if not matches:
                field_failures.append(source_field)
        total = summary.get("total_reviews")
        positive = summary.get("total_positive")
        if (
            isinstance(total, int)
            and not isinstance(total, bool)
            and isinstance(positive, int)
            and not isinstance(positive, bool)
        ):
            expected_rate = positive / total if total > 0 else None
            actual_rate = row["positive_rate"]
            rate_match = (
                pd.isna(actual_rate)
                if expected_rate is None
                else bool(
                    np.isclose(
                        float(actual_rate),
                        expected_rate,
                        rtol=0,
                        atol=1e-12,
                    )
                )
            )
        else:
            rate_match = False
        if not rate_match:
            field_failures.append("positive_rate")
        if field_failures:
            spot_mismatches.append(
                f"appid={appid}: fields={','.join(field_failures)}"
            )
        else:
            spot_matches += 1

    return {
        "raw_files": len(raw_files),
        "raw_unique_appids": len(raw_set),
        "raw_duplicate_appids": len(wrapper_ids) - len(raw_set),
        "missing_raw_appids": len(game_set.difference(raw_set)),
        "extra_raw_appids": len(raw_set.difference(game_set)),
        "malformed_raw": malformed_raw,
        "request_error_raw": request_error_raw,
        "invalid_response_raw": invalid_response_raw,
        "raw_contract_drift_files": contract_drift_files,
        "raw_parameter_drift": parameter_drift,
        "spot_seed": seed,
        "spot_size": spot_size,
        "spot_appids": spot_appids,
        "spot_matches": spot_matches,
        "spot_mismatches": spot_mismatches,
    }


def audit_passed(
    snapshot_audit: dict[str, Any],
    raw_audit: dict[str, Any],
    *,
    frozen_inputs_preserved: bool,
) -> bool:
    statuses = snapshot_audit["status_counts"]
    return all(
        [
            snapshot_audit["games_rows"] == 3_000,
            snapshot_audit["games_unique_appids"] == 3_000,
            snapshot_audit["snapshot_rows"] == 3_000,
            snapshot_audit["snapshot_unique_appids"] == 3_000,
            snapshot_audit["missing_review_appids"] == 0,
            snapshot_audit["external_review_appids"] == 0,
            snapshot_audit["duplicate_review_appids"] == 0,
            statuses["success"] == 3_000,
            statuses["unavailable"] == 0,
            statuses["request_failed"] == 0,
            statuses["schema_invalid"] == 0,
            snapshot_audit["invalid_count_values"] == 0,
            snapshot_audit["negative_count_failures"] == 0,
            snapshot_audit["count_identity_failures"] == 0,
            snapshot_audit["positive_rate_failures"] == 0,
            snapshot_audit["zero_rate_failures"] == 0,
            snapshot_audit["positive_rate_range_failures"] == 0,
            snapshot_audit["zero_semantic_failures"] == 0,
            sum(snapshot_audit["snapshot_contract_drift"].values()) == 0,
            snapshot_audit["missing_timestamps"] == 0,
            snapshot_audit["unparseable_timestamps"] == 0,
            raw_audit["raw_files"] == 3_000,
            raw_audit["raw_unique_appids"] == 3_000,
            raw_audit["raw_duplicate_appids"] == 0,
            raw_audit["missing_raw_appids"] == 0,
            raw_audit["extra_raw_appids"] == 0,
            raw_audit["malformed_raw"] == 0,
            raw_audit["request_error_raw"] == 0,
            raw_audit["invalid_response_raw"] == 0,
            raw_audit["raw_contract_drift_files"] == 0,
            raw_audit["spot_matches"] == raw_audit["spot_size"] == 30,
            not raw_audit["spot_mismatches"],
            frozen_inputs_preserved,
        ]
    )


def _format_summary(summary: dict[str, float], *, decimals: int) -> str:
    return ", ".join(
        f"{key}={value:,.{decimals}f}"
        for key, value in summary.items()
    )


def build_final_audit_report(
    snapshot_audit: dict[str, Any],
    raw_audit: dict[str, Any],
    *,
    frozen_hashes_before: dict[str, str],
    frozen_hashes_after: dict[str, str],
    snapshot_sha256: str,
    passed: bool,
) -> str:
    """Render the reproducible local audit report without analytical claims."""
    statuses = snapshot_audit["status_counts"]
    volume_bins = snapshot_audit["review_volume_distribution"]
    thresholds = snapshot_audit["threshold_counts"]
    threshold_rates = snapshot_audit["threshold_percentages"]
    contract_drift = snapshot_audit["snapshot_contract_drift"]
    frozen_preserved = frozen_hashes_before == frozen_hashes_after
    lines = [
        "# Step 3B Final Audit — Full Review Snapshot Validation",
        "",
        "This was a purely local, read-only validation of the completed review "
        "collection. HTTP requests made by this audit: **0**.",
        "",
        "## Final sample coverage",
        "",
        f"- games rows / unique AppIDs: {snapshot_audit['games_rows']:,} / "
        f"{snapshot_audit['games_unique_appids']:,}",
        f"- review snapshot rows / unique AppIDs: "
        f"{snapshot_audit['snapshot_rows']:,} / "
        f"{snapshot_audit['snapshot_unique_appids']:,}",
        f"- Missing review AppIDs: {snapshot_audit['missing_review_appids']:,}",
        f"- Sample-external review AppIDs: "
        f"{snapshot_audit['external_review_appids']:,}",
        f"- Duplicate review AppIDs: "
        f"{snapshot_audit['duplicate_review_appids']:,}",
        "",
        "## Review status",
        "",
        f"- success: {statuses['success']:,}",
        f"- unavailable: {statuses['unavailable']:,}",
        f"- request_failed: {statuses['request_failed']:,}",
        f"- schema_invalid: {statuses['schema_invalid']:,}",
        "",
        "## Count and zero-review integrity",
        "",
        f"- Invalid/non-integer count values: "
        f"{snapshot_audit['invalid_count_values']:,}",
        f"- Negative-count failures: "
        f"{snapshot_audit['negative_count_failures']:,}",
        f"- Count-identity failures: "
        f"{snapshot_audit['count_identity_failures']:,}",
        f"- Zero-review games: {snapshot_audit['zero_review_count']:,}",
        f"- Zero-review semantic failures: "
        f"{snapshot_audit['zero_semantic_failures']:,}",
        "",
        "## Review volume distribution",
        "",
    ]
    lines.extend(f"- {label}: {count:,}" for label, count in volume_bins.items())
    lines.extend(
        [
            "- Six-number summary: "
            + _format_summary(
                snapshot_audit["review_volume_summary"],
                decimals=2,
            ),
            "- Mean is descriptive only; review volume is strongly right-skewed.",
            "",
            "## Model-threshold counts",
            "",
        ]
    )
    for threshold in [10, 20, 50]:
        lines.append(
            f"- total_reviews >= {threshold}: {thresholds[threshold]:,} "
            f"({threshold_rates[threshold]:.2%} of 3,000)"
        )
    lines.extend(
        [
            "",
            "## Positive-rate integrity and distribution",
            "",
            f"- Available: {snapshot_audit['positive_rate_available']:,}",
            f"- NULL: {snapshot_audit['positive_rate_null']:,}",
            f"- NULL among total_reviews > 0: "
            f"{snapshot_audit['positive_rate_nonzero_null']:,}",
            f"- Calculation failures: "
            f"{snapshot_audit['positive_rate_failures']:,}",
            f"- Zero-review positive_rate failures: "
            f"{snapshot_audit['zero_rate_failures']:,}",
            f"- Range failures outside [0, 1]: "
            f"{snapshot_audit['positive_rate_range_failures']:,}",
            "- Nonzero-review six-number summary: "
            + _format_summary(
                snapshot_audit["positive_rate_summary"],
                decimals=6,
            ),
            "",
            "## Review score audit",
            "",
            f"- Missing review_score: {snapshot_audit['missing_review_score']:,}",
            f"- Missing/blank review_score_desc: "
            f"{snapshot_audit['missing_review_score_desc']:,}",
            "",
            "| review_score | Count |",
            "|---|---:|",
        ]
    )
    lines.extend(
        f"| {value} | {count:,} |"
        for value, count in snapshot_audit["review_score_counts"].items()
    )
    lines.extend(
        [
            "",
            "| review_score_desc | Count |",
            "|---|---:|",
        ]
    )
    lines.extend(
        f"| {value.replace('|', '/')} | {count:,} |"
        for value, count in snapshot_audit["review_score_desc_counts"].items()
    )
    lines.extend(
        [
            "",
            "## Query contract audit",
            "",
            f"- Frozen full-run contract: `{review_request_params()}`",
            f"- Snapshot parameter drift total: {sum(contract_drift.values()):,}",
        ]
    )
    lines.extend(
        f"- {field} drift: {count:,}"
        for field, count in contract_drift.items()
    )
    lines.extend(
        [
            f"- Raw contract-drift files: "
            f"{raw_audit['raw_contract_drift_files']:,}",
            "",
            "## Timestamp audit",
            "",
            f"- Missing timestamps: {snapshot_audit['missing_timestamps']:,}",
            f"- Unparseable timestamps: "
            f"{snapshot_audit['unparseable_timestamps']:,}",
            f"- Minimum collection timestamp: {snapshot_audit['timestamp_min']}",
            f"- Maximum collection timestamp: {snapshot_audit['timestamp_max']}",
            f"- Collection window duration: "
            f"{snapshot_audit['collection_window_seconds']:,.3f} seconds",
            "- These timestamps describe collection time, not release-time review state.",
            "",
            "## Raw coverage",
            "",
            f"- Raw files: {raw_audit['raw_files']:,}",
            f"- Unique Raw AppIDs: {raw_audit['raw_unique_appids']:,}",
            f"- Duplicate Raw AppIDs: {raw_audit['raw_duplicate_appids']:,}",
            f"- Missing Raw AppIDs: {raw_audit['missing_raw_appids']:,}",
            f"- Extra Raw AppIDs: {raw_audit['extra_raw_appids']:,}",
            f"- Malformed Raw: {raw_audit['malformed_raw']:,}",
            f"- request_error Raw: {raw_audit['request_error_raw']:,}",
            f"- Invalid HTTP/payload Raw: {raw_audit['invalid_response_raw']:,}",
            "",
            "## Deterministic Raw-to-snapshot spot check",
            "",
            f"- Seed: {raw_audit['spot_seed']}",
            f"- Sample size: {raw_audit['spot_size']}",
            f"- Exact matches: {raw_audit['spot_matches']}/"
            f"{raw_audit['spot_size']}",
            f"- Mismatches: {len(raw_audit['spot_mismatches'])}",
            "- Fields checked: total_positive, total_negative, total_reviews, "
            "review_score, review_score_desc, and derived positive_rate.",
            "- AppIDs: " + ", ".join(map(str, raw_audit["spot_appids"])),
        ]
    )
    if raw_audit["spot_mismatches"]:
        lines.append("- Mismatch details:")
        lines.extend(f"  - {item}" for item in raw_audit["spot_mismatches"])
    lines.extend(
        [
            "",
            "## Frozen input hashes",
            "",
            f"- Before/after preservation: {'PASS' if frozen_preserved else 'FAIL'}",
        ]
    )
    for path, digest in frozen_hashes_after.items():
        lines.append(f"- `{path}`: `{digest}`")
    lines.extend(
        [
            "",
            "## Review snapshot fingerprint",
            "",
            f"- `data/processed/review_snapshots.csv`: `{snapshot_sha256}`",
            "",
            "## Final freeze decision",
            "",
            f"- Step 3B Final Audit: {'PASS' if passed else 'FAIL'}",
            f"- Review dataset: {'FROZEN' if passed else 'NOT FROZEN'}",
            f"- Ready for Step 3C MySQL: {'YES' if passed else 'NO'}",
            "",
        ]
    )
    return "\n".join(lines)
