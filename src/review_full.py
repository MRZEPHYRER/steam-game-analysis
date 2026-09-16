"""Technical finalization and reporting for the full review snapshot."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Mapping

import pandas as pd

from src.io_utils import atomic_write_csv
from src.reviews import ReviewCollectionStats, review_request_params


class ReviewFinalizationError(RuntimeError):
    """A full review snapshot violates a required finalization invariant."""


class ReviewTechnicalFailureBlock(ReviewFinalizationError):
    """Unresolved request or schema failures prevent finalization."""

    def __init__(self, request_failed: int, schema_invalid: int) -> None:
        self.request_failed = request_failed
        self.schema_invalid = schema_invalid
        super().__init__(
            "Full review collection contains unresolved technical failures: "
            f"request_failed={request_failed}, schema_invalid={schema_invalid}."
        )


class ReviewCountIdentityBlock(ReviewFinalizationError):
    """Review counts or positive-rate semantics are inconsistent."""


class FrozenInputError(ReviewFinalizationError):
    """A frozen project input is missing or has changed."""


def _unique_appids(frame: pd.DataFrame, label: str) -> set[int]:
    if "appid" not in frame:
        raise ReviewFinalizationError(f"{label} is missing appid.")
    values = pd.to_numeric(frame["appid"], errors="coerce")
    if values.isna().any() or (values.dropna() % 1 != 0).any():
        raise ReviewFinalizationError(f"{label} contains invalid AppIDs.")
    normalized = values.astype("int64")
    if normalized.duplicated().any():
        raise ReviewFinalizationError(f"{label} contains duplicate AppIDs.")
    return set(normalized)


def validate_review_source(
    games: pd.DataFrame,
    *,
    expected_size: int = 3_000,
) -> set[int]:
    """Require the frozen source to contain exactly 3,000 unique AppIDs."""
    appids = _unique_appids(games, "games.csv")
    if len(games) != expected_size or len(appids) != expected_size:
        raise ReviewFinalizationError(
            f"games.csv must contain {expected_size} rows and unique AppIDs; "
            f"rows={len(games)}, unique_appids={len(appids)}."
        )
    return appids


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def verify_frozen_inputs(
    expected_hashes: Mapping[Path, str],
) -> dict[Path, str]:
    """Return current hashes only when every frozen input matches its baseline."""
    current: dict[Path, str] = {}
    problems: list[str] = []
    for path, expected in expected_hashes.items():
        if not path.is_file():
            problems.append(f"missing={path}")
            continue
        actual = sha256_file(path)
        current[path] = actual
        if actual != expected.upper():
            problems.append(
                f"changed={path} expected={expected.upper()} actual={actual}"
            )
    if problems:
        raise FrozenInputError(
            "Frozen input validation failed: " + "; ".join(problems)
        )
    return current


def validate_frozen_inputs_unchanged(
    before: Mapping[Path, str],
    after: Mapping[Path, str],
) -> None:
    if dict(before) != dict(after):
        raise FrozenInputError("Frozen inputs changed during review collection.")


def _review_integrity_counts(
    source: pd.DataFrame,
    snapshot: pd.DataFrame,
) -> dict[str, int]:
    expected = _unique_appids(source, "games.csv")
    actual = _unique_appids(snapshot, "review snapshot")
    successful = snapshot.loc[snapshot["review_status"] == "success"].copy()
    numeric_fields = ["total_reviews", "positive_reviews", "negative_reviews"]
    numeric = {
        field: pd.to_numeric(successful[field], errors="coerce")
        for field in numeric_fields
    }
    invalid_numeric = sum(
        int(
            series.isna().sum()
            + series.lt(0).sum()
            + series.dropna().mod(1).ne(0).sum()
        )
        for series in numeric.values()
    )
    identity_failures = int(
        (
            numeric["positive_reviews"]
            + numeric["negative_reviews"]
            != numeric["total_reviews"]
        ).sum()
    )
    rates = pd.to_numeric(successful["positive_rate"], errors="coerce")
    zero = numeric["total_reviews"].eq(0)
    zero_rate_failures = int(rates.loc[zero].notna().sum())
    nonzero = numeric["total_reviews"].gt(0)
    expected_rates = (
        numeric["positive_reviews"].loc[nonzero]
        / numeric["total_reviews"].loc[nonzero]
    )
    rate_failures = int(
        ((rates.loc[nonzero] - expected_rates).abs() > 1e-12).sum()
        + rates.loc[nonzero].isna().sum()
    )
    statuses = snapshot["review_status"].astype("string")
    return {
        "duplicate_appids": int(snapshot["appid"].duplicated().sum()),
        "missing_appids": len(expected.difference(actual)),
        "external_appids": len(actual.difference(expected)),
        "request_failed": int(statuses.eq("request_failed").sum()),
        "schema_invalid": int(statuses.eq("schema_invalid").sum()),
        "invalid_numeric_counts": invalid_numeric,
        "count_identity_failures": identity_failures,
        "positive_rate_failures": zero_rate_failures + rate_failures,
    }


def validate_review_finalization(
    source: pd.DataFrame,
    snapshot: pd.DataFrame,
    *,
    expected_size: int = 3_000,
) -> None:
    """Enforce exact coverage, technical success, and count/rate integrity."""
    expected = validate_review_source(source, expected_size=expected_size)
    required = {
        "appid",
        "review_status",
        "total_reviews",
        "positive_reviews",
        "negative_reviews",
        "positive_rate",
    }
    missing_columns = required.difference(snapshot.columns)
    if missing_columns:
        raise ReviewFinalizationError(
            f"Review snapshot is missing columns: {sorted(missing_columns)}."
        )
    actual = _unique_appids(snapshot, "review snapshot")
    if len(snapshot) != expected_size or actual != expected:
        raise ReviewFinalizationError(
            "Review snapshot AppID coverage mismatch: "
            f"rows={len(snapshot)}, unique={len(actual)}, "
            f"missing={len(expected.difference(actual))}, "
            f"unexpected={len(actual.difference(expected))}."
        )
    allowed_statuses = {
        "success",
        "unavailable",
        "request_failed",
        "schema_invalid",
    }
    actual_statuses = set(snapshot["review_status"].dropna().astype(str))
    unknown_statuses = actual_statuses.difference(allowed_statuses)
    if snapshot["review_status"].isna().any() or unknown_statuses:
        raise ReviewFinalizationError(
            "Review snapshot contains invalid status values: "
            f"{sorted(unknown_statuses)}."
        )
    integrity = _review_integrity_counts(source, snapshot)
    if integrity["request_failed"] or integrity["schema_invalid"]:
        raise ReviewTechnicalFailureBlock(
            integrity["request_failed"],
            integrity["schema_invalid"],
        )
    if (
        integrity["invalid_numeric_counts"]
        or integrity["count_identity_failures"]
        or integrity["positive_rate_failures"]
    ):
        raise ReviewCountIdentityBlock(
            "Review count/rate integrity failed: "
            f"invalid_numeric={integrity['invalid_numeric_counts']}, "
            f"identity={integrity['count_identity_failures']}, "
            f"positive_rate={integrity['positive_rate_failures']}."
        )


def finalize_review_snapshot(
    source: pd.DataFrame,
    snapshot: pd.DataFrame,
    *,
    output_path: Path,
    expected_size: int = 3_000,
) -> None:
    """Atomically write the formal snapshot only after all gates pass."""
    validate_review_finalization(
        source,
        snapshot,
        expected_size=expected_size,
    )
    atomic_write_csv(output_path, snapshot)


def build_full_review_report(
    *,
    source: pd.DataFrame,
    snapshot: pd.DataFrame,
    stats: ReviewCollectionStats,
    raw_dir: Path,
    frozen_before: Mapping[Path, str],
    frozen_after: Mapping[Path, str],
    finalized: bool,
) -> str:
    """Build collection QA and descriptive summaries without substantive EDA."""
    integrity = _review_integrity_counts(source, snapshot)
    successful = snapshot.loc[snapshot["review_status"] == "success"].copy()
    totals = pd.to_numeric(successful["total_reviews"], errors="coerce").dropna()
    count_bins = {
        "zero": int(totals.eq(0).sum()),
        "1-9": int(totals.between(1, 9).sum()),
        "10-19": int(totals.between(10, 19).sum()),
        "20-49": int(totals.between(20, 49).sum()),
        "50-99": int(totals.between(50, 99).sum()),
        "100-499": int(totals.between(100, 499).sum()),
        "500-999": int(totals.between(500, 999).sum()),
        "1000+": int(totals.ge(1000).sum()),
    }
    total_summary = (
        "N/A"
        if totals.empty
        else (
            f"min={int(totals.min()):,}, median={totals.median():,.1f}, "
            f"mean={totals.mean():,.2f}, max={int(totals.max()):,}"
        )
    )
    nonzero = successful.loc[
        pd.to_numeric(successful["total_reviews"], errors="coerce").gt(0)
    ]
    rates = pd.to_numeric(nonzero["positive_rate"], errors="coerce").dropna()
    rate_summary = (
        "N/A"
        if rates.empty
        else (
            f"min={rates.min():.6f}, median={rates.median():.6f}, "
            f"mean={rates.mean():.6f}, max={rates.max():.6f}"
        )
    )
    statuses = snapshot["review_status"].value_counts(dropna=False)
    scores = successful["review_score"].fillna("<missing>").value_counts()
    descriptions = (
        successful["review_score_desc"].fillna("<missing>").value_counts()
    )
    frozen_ok = dict(frozen_before) == dict(frozen_after)
    lines = [
        "# Step 3B.2 Full Steam Review Snapshot Collection",
        "",
        "This report contains collection QA and descriptive volume summaries only. "
        "It does not perform substantive EDA or modeling.",
        "",
        "## Coverage",
        "",
        f"- Source games: {len(source):,}",
        f"- Snapshot rows: {len(snapshot):,}",
        f"- Unique snapshot AppIDs: {snapshot['appid'].nunique():,}",
        f"- Coverage: {len(snapshot) / len(source):.2%}",
        f"- Full Raw wrappers present: {len(list(raw_dir.glob('review_*.json'))):,}",
        "",
        "## Frozen query contract",
        "",
        f"- Parameters: `{review_request_params()}`",
        "- Only query_summary and technical/source metadata are materialized.",
        "- No review pagination or individual-review corpus collection is performed.",
        "",
        "## Technical status",
        "",
        f"- Success: {int(statuses.get('success', 0)):,}",
        f"- Steam unavailable: {int(statuses.get('unavailable', 0)):,}",
        f"- request_failed: {int(statuses.get('request_failed', 0)):,}",
        f"- schema_invalid: {int(statuses.get('schema_invalid', 0)):,}",
        "",
        "## Review-count distribution",
        "",
    ]
    lines.extend(f"- {label}: {count:,}" for label, count in count_bins.items())
    lines.extend(
        [
            f"- Summary: {total_summary}",
            "- Mean is descriptive only; review volume may be strongly right-skewed.",
            "",
            "## Model-threshold counts (not a model-table filter)",
            "",
            f"- total_reviews >= 10: {int(totals.ge(10).sum()):,}",
            f"- total_reviews >= 20: {int(totals.ge(20).sum()):,}",
            f"- total_reviews >= 50: {int(totals.ge(50).sum()):,}",
            "",
            "## Positive rate",
            "",
            f"- Available count: {int(successful['positive_rate'].notna().sum()):,}",
            f"- NULL count: {int(successful['positive_rate'].isna().sum()):,}",
            f"- Distribution for total_reviews > 0 only: {rate_summary}",
            "",
            "## Review score frequency",
            "",
            "| review_score | Count |",
            "|---|---:|",
        ]
    )
    lines.extend(f"| {value} | {count:,} |" for value, count in scores.items())
    lines.extend(
        [
            "",
            "## Review score description frequency",
            "",
            "| review_score_desc | Count |",
            "|---|---:|",
        ]
    )
    lines.extend(
        f"| {str(value).replace('|', '/')} | {count:,} |"
        for value, count in descriptions.items()
    )
    lines.extend(
        [
            "",
            "## Integrity",
            "",
            f"- Count-identity failures: {integrity['count_identity_failures']:,}",
            f"- Positive-rate semantic failures: {integrity['positive_rate_failures']:,}",
            f"- Duplicate AppIDs: {integrity['duplicate_appids']:,}",
            f"- Missing AppIDs: {integrity['missing_appids']:,}",
            f"- Sample-external AppIDs: {integrity['external_appids']:,}",
            "",
            "## Collection telemetry",
            "",
            f"- New: {stats.newly_requested:,}",
            f"- Reused: {stats.reused:,}",
            f"- Retried failed Raw: {stats.retried_failed_raw:,}",
            f"- Unresolved failures: {stats.request_failed:,}",
            f"- HTTP retries: {stats.request_retry_count:,}",
            f"- HTTP 429 responses: {stats.http_429_count:,}",
            f"- Transient HTTP 5xx responses: {stats.http_5xx_count:,}",
            f"- Timeout/connection failures: {stats.transport_error_count:,}",
            f"- Elapsed seconds: {stats.elapsed_seconds:.3f}",
            "",
            "## Frozen inputs",
            "",
            f"- Before/after hashes identical: {'PASS' if frozen_ok else 'FAIL'}",
        ]
    )
    for path, digest in frozen_after.items():
        lines.append(f"- `{path}`: `{digest}`")
    lines.extend(
        [
            "",
            "## Finalization",
            "",
            f"- Technical finalization gate: {'PASS' if finalized else 'BLOCKED'}",
            f"- Formal review_snapshots.csv written: {'YES' if finalized else 'NO'}",
            "",
        ]
    )
    return "\n".join(lines)
