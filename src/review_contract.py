"""A/B validation for the Steam review-query request contract."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from config.settings import RANDOM_SEED, STEAM_REVIEWS_URL
from src.io_utils import atomic_write_csv, atomic_write_json, read_json
from src.reviews import (
    documented_review_request_params,
    preflight_review_request_params,
    review_record_from_raw,
)
from src.steam_client import SteamClient, SteamClientError


QUERY_SUMMARY_FIELDS = [
    "total_positive",
    "total_negative",
    "total_reviews",
    "review_score",
    "review_score_desc",
]
QUERY_CONTRACT_BIN_QUOTAS = {
    "zero": 2,
    "1-9": 2,
    "10-19": 1,
    "20-49": 2,
    "50+": 3,
}
QUERY_CONTRACT_SAMPLE_COLUMNS = [
    "appid",
    "name",
    "is_free",
    "total_reviews",
    "review_count_bin",
    "sample_seed",
    "selection_method",
]
SELECTION_METHOD = "seeded_review_count_bin_quota_from_step3b_preflight"


@dataclass(frozen=True, slots=True)
class QueryContractResult:
    tested: int
    requested: int
    reused: int
    request_failed: int
    schema_invalid: int
    exact_matches: int
    count_identity_passes: int
    zero_review_checks: int
    zero_review_passes: int
    passed: bool


def review_count_bin(total_reviews: int) -> str:
    if total_reviews == 0:
        return "zero"
    if total_reviews < 10:
        return "1-9"
    if total_reviews < 20:
        return "10-19"
    if total_reviews < 50:
        return "20-49"
    return "50+"


def select_query_contract_sample(
    preflight_sample: pd.DataFrame,
    preflight_snapshot: pd.DataFrame,
    *,
    random_seed: int = RANDOM_SEED,
) -> pd.DataFrame:
    """Select ten deterministic AppIDs only from the completed Step 3B sample."""
    if len(preflight_sample) != 30 or len(preflight_snapshot) != 30:
        raise ValueError("Step 3B inputs must each contain exactly 30 rows.")
    if preflight_sample["appid"].duplicated().any():
        raise ValueError("Step 3B sample contains duplicate AppIDs.")
    if preflight_snapshot["appid"].duplicated().any():
        raise ValueError("Step 3B snapshot contains duplicate AppIDs.")

    sample = preflight_sample[["appid", "name", "is_free"]].copy()
    snapshot = preflight_snapshot[
        ["appid", "total_reviews", "review_status"]
    ].copy()
    merged = sample.merge(snapshot, on="appid", how="inner", validate="one_to_one")
    if len(merged) != 30:
        raise ValueError("Step 3B sample and snapshot AppIDs do not match exactly.")
    if not merged["review_status"].eq("success").all():
        raise ValueError("All Step 3B rows must be successful before A/B selection.")
    merged["appid"] = pd.to_numeric(merged["appid"], errors="raise").astype("int64")
    merged["total_reviews"] = pd.to_numeric(
        merged["total_reviews"], errors="raise"
    ).astype("int64")
    free_values = merged["is_free"].astype("string").str.casefold()
    if not free_values.isin(["true", "false"]).all():
        raise ValueError("Step 3B is_free values must be boolean.")
    merged["is_free"] = free_values.eq("true")
    merged["review_count_bin"] = merged["total_reviews"].map(review_count_bin)

    selected: list[pd.DataFrame] = []
    for position, (bucket, quota) in enumerate(
        QUERY_CONTRACT_BIN_QUOTAS.items()
    ):
        candidates = merged.loc[merged["review_count_bin"] == bucket]
        if len(candidates) < quota:
            raise ValueError(
                f"Step 3B does not contain {quota} rows for review bin {bucket}."
            )
        selected.append(
            candidates.sample(
                n=quota,
                replace=False,
                random_state=random_seed + position,
            )
        )

    result = pd.concat(selected, ignore_index=True)
    if len(result) != 10 or result["appid"].nunique() != 10:
        raise RuntimeError("A/B selection must contain 10 unique AppIDs.")
    if not result["is_free"].any() or result["is_free"].all():
        raise RuntimeError("A/B selection must cover both free and paid games.")
    result["sample_seed"] = random_seed
    result["selection_method"] = SELECTION_METHOD
    return (
        result.sort_values(["review_count_bin", "appid"], kind="stable")
        .reset_index(drop=True)
        .reindex(columns=QUERY_CONTRACT_SAMPLE_COLUMNS)
    )


def _query_summary(raw: dict[str, Any]) -> dict[str, Any]:
    payload = raw.get("payload")
    if not isinstance(payload, dict):
        raise ValueError("Raw wrapper is missing an object payload.")
    summary = payload.get("query_summary")
    if not isinstance(summary, dict):
        raise ValueError("Raw payload is missing query_summary.")
    missing = [field for field in QUERY_SUMMARY_FIELDS if field not in summary]
    if missing:
        raise ValueError(f"query_summary is missing fields: {missing}.")
    return summary


def _individual_review_count(raw: dict[str, Any]) -> int:
    payload = raw.get("payload")
    if not isinstance(payload, dict):
        raise ValueError("Raw wrapper is missing an object payload.")
    reviews = payload.get("reviews", [])
    if not isinstance(reviews, list):
        raise ValueError("Raw payload reviews must be an array.")
    return len(reviews)


def _response_payload_bytes(raw: dict[str, Any]) -> int:
    payload = raw.get("payload")
    if not isinstance(payload, dict):
        raise ValueError("Raw wrapper is missing an object payload.")
    serialized = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return len(serialized.encode("utf-8"))


def _same_value(left: Any, right: Any) -> bool:
    return type(left) is type(right) and left == right


def compare_review_raw(
    *,
    appid: int,
    name: str,
    is_free: bool,
    review_bin: str,
    current_path: Path,
    candidate_path: Path,
) -> dict[str, Any]:
    """Compare every required query_summary field and payload-size measure."""
    current_raw = read_json(current_path)
    candidate_raw = read_json(candidate_path)
    current_record = review_record_from_raw(current_path)
    candidate_record = review_record_from_raw(candidate_path)
    if current_record["review_status"] != "success":
        raise ValueError("Current preflight Raw is not successful.")
    if candidate_record["review_status"] != "success":
        raise ValueError("Candidate Raw is not successful.")
    current_summary = _query_summary(current_raw)
    candidate_summary = _query_summary(candidate_raw)

    row: dict[str, Any] = {
        "appid": appid,
        "name": name,
        "is_free": is_free,
        "review_count_bin": review_bin,
        "comparison_status": "success",
        "comparison_error": None,
    }
    matches: list[bool] = []
    for field in QUERY_SUMMARY_FIELDS:
        row[f"current_{field}"] = current_summary[field]
        row[f"candidate_{field}"] = candidate_summary[field]
        field_match = _same_value(
            current_summary[field], candidate_summary[field]
        )
        row[f"match_{field}"] = field_match
        matches.append(field_match)
    row["query_summary_match"] = all(matches)
    row["current_individual_review_count"] = _individual_review_count(current_raw)
    row["candidate_individual_review_count"] = _individual_review_count(
        candidate_raw
    )
    row["current_response_bytes"] = _response_payload_bytes(current_raw)
    row["candidate_response_bytes"] = _response_payload_bytes(candidate_raw)
    row["current_raw_wrapper_bytes"] = current_path.stat().st_size
    row["candidate_raw_wrapper_bytes"] = candidate_path.stat().st_size

    total = candidate_summary["total_reviews"]
    positive = candidate_summary["total_positive"]
    negative = candidate_summary["total_negative"]
    row["candidate_count_identity"] = positive + negative == total
    row["zero_review_check_applicable"] = (
        current_summary["total_reviews"] == 0
    )
    row["candidate_zero_review_semantics"] = (
        not row["zero_review_check_applicable"]
        or (
            total == 0
            and positive == 0
            and negative == 0
            and candidate_record["positive_rate"] is None
        )
    )
    return row


def collect_query_contract_test(
    client: SteamClient,
    selection: pd.DataFrame,
    *,
    current_raw_dir: Path,
    candidate_raw_dir: Path,
    output_path: Path,
    logger: logging.Logger | None = None,
) -> tuple[pd.DataFrame, QueryContractResult]:
    """Request only the ten candidate responses, preserving them separately."""
    logger = logger or logging.getLogger(__name__)
    if len(selection) != 10 or selection["appid"].nunique() != 10:
        raise ValueError("Query-contract selection must contain 10 unique AppIDs.")
    candidate_raw_dir.mkdir(parents=True, exist_ok=True)
    requested = 0
    reused = 0
    request_failed = 0
    schema_invalid = 0
    rows: list[dict[str, Any]] = []

    for position, selected in enumerate(selection.itertuples(index=False), start=1):
        appid = int(selected.appid)
        current_path = current_raw_dir / f"review_{appid:010d}.json"
        candidate_path = candidate_raw_dir / f"review_{appid:010d}.json"
        if not current_path.exists():
            raise FileNotFoundError(f"Missing preflight Raw for AppID {appid}.")

        should_request = not candidate_path.exists()
        if candidate_path.exists():
            existing = read_json(candidate_path)
            if "request_error" in existing:
                should_request = True
            else:
                reused += 1
        if should_request:
            requested += 1
            params = documented_review_request_params()
            try:
                response = client.get_json(
                    STEAM_REVIEWS_URL.format(appid=appid),
                    params=params,
                    collector="review_query_contract",
                    context=f"appid={appid} position={position}/10",
                )
                raw = {
                    "appid": appid,
                    "requested_at": response.requested_at,
                    "request_params": params,
                    "http_status": response.status_code,
                    "payload": response.payload,
                    "request_retry_count": response.retry_count,
                    "retryable_status_codes": list(
                        response.retryable_status_codes
                    ),
                    "request_latency_seconds": response.elapsed_seconds,
                }
            except SteamClientError as exc:
                request_failed += 1
                raw = {
                    "appid": appid,
                    "requested_at": datetime.now(timezone.utc).isoformat(),
                    "request_params": params,
                    "http_status": None,
                    "request_error": str(exc),
                    "request_retry_count": 0,
                    "retryable_status_codes": [],
                    "request_latency_seconds": None,
                }
            atomic_write_json(candidate_path, raw)

        try:
            row = compare_review_raw(
                appid=appid,
                name=str(selected.name),
                is_free=bool(selected.is_free),
                review_bin=str(selected.review_count_bin),
                current_path=current_path,
                candidate_path=candidate_path,
            )
        except (KeyError, TypeError, ValueError) as exc:
            schema_invalid += 1
            row = {
                "appid": appid,
                "name": str(selected.name),
                "is_free": bool(selected.is_free),
                "review_count_bin": str(selected.review_count_bin),
                "comparison_status": "schema_invalid",
                "comparison_error": str(exc),
                "query_summary_match": False,
                "candidate_count_identity": False,
                "zero_review_check_applicable": False,
                "candidate_zero_review_semantics": False,
            }
            logger.error(
                "collector=review_query_contract appid=%s schema_invalid=%s",
                appid,
                exc,
            )
        rows.append(row)

    comparison = pd.DataFrame(rows).sort_values("appid", kind="stable")
    comparison = comparison.reset_index(drop=True)
    atomic_write_csv(output_path, comparison)
    exact_matches = int(comparison["query_summary_match"].fillna(False).sum())
    identity_passes = int(
        comparison["candidate_count_identity"].fillna(False).sum()
    )
    zero_rows = comparison["zero_review_check_applicable"].fillna(False)
    zero_checks = int(zero_rows.sum())
    zero_passes = int(
        comparison.loc[zero_rows, "candidate_zero_review_semantics"]
        .fillna(False)
        .sum()
    )
    passed = (
        len(comparison) == 10
        and request_failed == 0
        and schema_invalid == 0
        and exact_matches == 10
        and identity_passes == 10
        and zero_checks > 0
        and zero_passes == zero_checks
    )
    return comparison, QueryContractResult(
        tested=len(comparison),
        requested=requested,
        reused=reused,
        request_failed=request_failed,
        schema_invalid=schema_invalid,
        exact_matches=exact_matches,
        count_identity_passes=identity_passes,
        zero_review_checks=zero_checks,
        zero_review_passes=zero_passes,
        passed=passed,
    )


def build_query_contract_report(
    selection: pd.DataFrame,
    comparison: pd.DataFrame,
    result: QueryContractResult,
) -> str:
    successful = comparison.loc[comparison["comparison_status"] == "success"]
    current_reviews = int(
        successful["current_individual_review_count"].fillna(0).sum()
    )
    candidate_reviews = int(
        successful["candidate_individual_review_count"].fillna(0).sum()
    )
    current_bytes = int(successful["current_response_bytes"].fillna(0).sum())
    candidate_bytes = int(
        successful["candidate_response_bytes"].fillna(0).sum()
    )
    delta = candidate_bytes - current_bytes
    reduction = (
        (current_bytes - candidate_bytes) / current_bytes
        if current_bytes
        else 0.0
    )
    selected_contract = (
        documented_review_request_params()
        if result.passed
        else preflight_review_request_params()
    )
    reason = (
        "All 10 query_summary comparisons were exact, all count identities "
        "held, and all zero-review semantics checks passed."
        if result.passed
        else "The documented candidate did not satisfy every switch criterion; "
        "the current preflight contract remains selected."
    )
    lines = [
        "# Step 3B.1 Steam Review Query Contract Validation",
        "",
        "This was an isolated 10-AppID A/B request-contract check. It did not run "
        "the 3,000-AppID review collection.",
        "",
        "## Contracts",
        "",
        f"- Current preflight contract: `{preflight_review_request_params()}`",
        f"- Candidate documented contract: `{documented_review_request_params()}`",
        "- Added candidate parameter: `day_range=365`. Steam's documented "
        "`filter=all` table marks day_range as required and allows at most 365.",
        "- Research population remained language=all, purchase_type=steam, "
        "review_type=all, filter_offtopic_activity=1.",
        "- Official contract reference: "
        "https://partner.steamgames.com/doc/store/getreviews?language=english",
        "",
        "## A/B sample",
        "",
        f"- A/B sample size: {len(selection)}",
        f"- AppIDs tested: {result.tested}",
        f"- Free games: {int(selection['is_free'].sum())}",
        f"- Paid games: {int((~selection['is_free']).sum())}",
        "- Review-count bin counts: "
        + ", ".join(
            f"{bucket}={int((selection['review_count_bin'] == bucket).sum())}"
            for bucket in QUERY_CONTRACT_BIN_QUOTAS
        ),
        "",
        "## Validation results",
        "",
        f"- query_summary exact matches: {result.exact_matches}/10",
        f"- query_summary mismatches: {10 - result.exact_matches}/10",
        f"- Candidate count identities: {result.count_identity_passes}/10",
        f"- Zero-review semantics: {result.zero_review_passes}/{result.zero_review_checks}",
        f"- Request failures: {result.request_failed}",
        f"- Schema-invalid comparisons: {result.schema_invalid}",
        f"- Candidate Raw requested this execution: {result.requested}",
        f"- Candidate Raw reused this execution: {result.reused}",
        "- Required field exact-match counts:",
    ]
    lines.extend(
        f"  - {field}: "
        f"{int(successful[f'match_{field}'].fillna(False).sum())}/10"
        for field in QUERY_SUMMARY_FIELDS
    )
    lines.extend(
        [
        "",
        "## Payload comparison",
        "",
        f"- Current individual review objects: {current_reviews}",
        f"- Candidate individual review objects: {candidate_reviews}",
        f"- Current response payload bytes: {current_bytes}",
        f"- Candidate response payload bytes: {candidate_bytes}",
        f"- Candidate minus current bytes: {delta}",
        f"- Response payload reduction: {reduction:.2%}",
        "- Byte counts use the same canonical UTF-8 JSON serialization of each "
        "preserved response payload; Raw wrapper metadata is excluded.",
        "",
        "## Field-level comparison",
        "",
        "| AppID | Bin | Free | Summary match | Count identity | Zero semantics | "
        "Current objects | Candidate objects | Current bytes | Candidate bytes |",
        "|---:|---|:---:|:---:|:---:|:---:|---:|---:|---:|---:|",
        ]
    )
    for row in comparison.itertuples(index=False):
        lines.append(
            f"| {row.appid} | {row.review_count_bin} | "
            f"{'YES' if row.is_free else 'NO'} | "
            f"{'PASS' if bool(row.query_summary_match) else 'FAIL'} | "
            f"{'PASS' if bool(row.candidate_count_identity) else 'FAIL'} | "
            f"{'PASS' if bool(row.candidate_zero_review_semantics) else 'FAIL'} | "
            f"{getattr(row, 'current_individual_review_count', '')} | "
            f"{getattr(row, 'candidate_individual_review_count', '')} | "
            f"{getattr(row, 'current_response_bytes', '')} | "
            f"{getattr(row, 'candidate_response_bytes', '')} |"
        )
    lines.extend(
        [
            "",
            "The comparison covers total_positive, total_negative, total_reviews, "
            "review_score, and review_score_desc individually. No review text was "
            "analyzed or included in this report.",
            "",
            "## Decision",
            "",
            f"- Final selected contract: `{selected_contract}`",
            f"- Reason: {reason}",
            f"- Query-summary equivalence: {'PASS' if result.exact_matches == 10 else 'FAIL'}",
            f"- Zero-review semantics: {'PASS' if result.zero_review_passes == result.zero_review_checks and result.zero_review_checks > 0 else 'FAIL'}",
            f"- Research definition preserved: {'PASS' if result.schema_invalid == 0 else 'FAIL'}",
            f"- Minimal payload contract: {'PASS' if result.passed else 'FAIL'}",
            f"- Step 3B.1: {'PASS' if result.passed else 'FAIL'}",
            f"- Ready for 3,000-review full collection: {'YES' if result.passed else 'NO'}",
            "",
        ]
    )
    return "\n".join(lines)
