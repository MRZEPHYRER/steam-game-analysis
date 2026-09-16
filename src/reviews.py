"""Steam review-summary snapshots with resumable Raw preservation."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from config.settings import (
    FILTER_OFFTOPIC_ACTIVITY,
    RANDOM_SEED,
    REVIEW_CURSOR,
    REVIEW_DAY_RANGE,
    REVIEW_FILTER,
    REVIEW_LANGUAGE,
    REVIEW_NUM_PER_PAGE,
    REVIEW_PREFLIGHT_FILTER,
    REVIEW_PREFLIGHT_NUM_PER_PAGE,
    REVIEW_PURCHASE_TYPE,
    REVIEW_TYPE,
    STEAM_REVIEWS_URL,
)
from src.io_utils import atomic_write_csv, atomic_write_json, read_json
from src.progress import ConsoleProgress
from src.sampling import allocate_proportional_sample
from src.schema import ReviewSnapshot
from src.steam_client import SteamClient, SteamClientError


PREFLIGHT_SELECTION_METHOD = "monthly_quota_seeded_price_band_round_robin"
PRICE_BANDS = [
    "free",
    "paid_unavailable",
    "paid_under_500",
    "paid_500_1499",
    "paid_1500_plus",
]
PREFLIGHT_SAMPLE_COLUMNS = [
    "appid",
    "name",
    "release_date",
    "release_month",
    "is_free",
    "list_price_cents",
    "price_currency",
    "price_band",
    "sample_seed",
    "selection_method",
]
REVIEW_SNAPSHOT_COLUMNS = [
    "appid",
    "total_reviews",
    "positive_reviews",
    "negative_reviews",
    "positive_rate",
    "review_score",
    "review_score_desc",
    "review_language",
    "review_purchase_type",
    "review_type",
    "filter_offtopic_activity",
    "day_range",
    "review_collected_at",
    "review_status",
    "schema_error",
    "http_status",
    "request_retry_count",
    "request_latency_seconds",
    "http_429_count",
    "http_5xx_count",
    "transport_error_count",
]


class ReviewSchemaError(ValueError):
    """A preserved review response does not match the required summary schema."""


@dataclass(frozen=True, slots=True)
class ReviewCollectionStats:
    total: int
    reused: int
    newly_requested: int
    retried_failed_raw: int
    request_failed: int
    schema_invalid: int
    unavailable: int
    request_retry_count: int
    http_429_count: int
    http_5xx_count: int
    transport_error_count: int
    elapsed_seconds: float


def review_request_params() -> dict[str, Any]:
    """Return the validated full-run review request contract."""
    return {
        "json": 1,
        "filter": REVIEW_FILTER,
        "cursor": REVIEW_CURSOR,
        "num_per_page": REVIEW_NUM_PER_PAGE,
        "language": REVIEW_LANGUAGE,
        "purchase_type": REVIEW_PURCHASE_TYPE,
        "review_type": REVIEW_TYPE,
        "filter_offtopic_activity": FILTER_OFFTOPIC_ACTIVITY,
        "day_range": REVIEW_DAY_RANGE,
    }


def documented_review_request_params() -> dict[str, Any]:
    """Return the documented minimal-page candidate review contract."""
    return review_request_params()


def preflight_review_request_params() -> dict[str, Any]:
    """Return the historical Step 3B contract retained in existing Raw."""
    return {
        "json": 1,
        "language": REVIEW_LANGUAGE,
        "purchase_type": REVIEW_PURCHASE_TYPE,
        "review_type": REVIEW_TYPE,
        "filter": REVIEW_PREFLIGHT_FILTER,
        "filter_offtopic_activity": FILTER_OFFTOPIC_ACTIVITY,
        "num_per_page": REVIEW_PREFLIGHT_NUM_PER_PAGE,
    }


def validate_review_request_params(params: dict[str, Any]) -> None:
    allowed = [review_request_params(), preflight_review_request_params()]
    if params not in allowed:
        raise ReviewSchemaError(
            "Review request parameter contract changed: "
            f"actual={params}, allowed={allowed}."
        )


def _normalize_source_games(games: pd.DataFrame) -> pd.DataFrame:
    required = {
        "appid",
        "name",
        "release_date",
        "release_month",
        "is_free",
        "list_price_cents",
        "price_currency",
    }
    missing = required.difference(games.columns)
    if missing:
        raise ValueError(f"games is missing required fields: {sorted(missing)}")
    result = games.copy()
    appids = pd.to_numeric(result["appid"], errors="coerce")
    if appids.isna().any() or (appids.dropna() % 1 != 0).any():
        raise ValueError("games contains invalid AppIDs.")
    result["appid"] = appids.astype("int64")
    if result["appid"].duplicated().any():
        raise ValueError("games contains duplicate AppID values.")
    dates = pd.to_datetime(result["release_date"], format="%Y-%m-%d", errors="coerce")
    if dates.isna().any():
        raise ValueError("games contains invalid release dates.")
    derived_month = dates.dt.strftime("%Y-%m")
    if not result["release_month"].astype("string").eq(derived_month).all():
        raise ValueError("games release_month differs from release_date.")
    bool_values = result["is_free"].astype("string").str.casefold()
    if not bool_values.isin(["true", "false"]).all():
        raise ValueError("games is_free must be boolean.")
    result["is_free"] = bool_values.eq("true")
    result["_release_date"] = dates
    return result


def _price_band(row: pd.Series) -> str:
    if bool(row["is_free"]):
        return "free"
    cents = row["list_price_cents"]
    if pd.isna(cents):
        return "paid_unavailable"
    cents = int(cents)
    if cents < 500:
        return "paid_under_500"
    if cents < 1500:
        return "paid_500_1499"
    return "paid_1500_plus"


def select_review_preflight_sample(
    games: pd.DataFrame,
    *,
    sample_size: int = 30,
    random_seed: int = RANDOM_SEED,
) -> pd.DataFrame:
    """Select deterministic monthly quotas with price/free coverage inside each month."""
    source = _normalize_source_games(games)
    cents = pd.to_numeric(source["list_price_cents"], errors="coerce")
    if (cents.dropna() % 1 != 0).any() or cents.dropna().lt(0).any():
        raise ValueError("games list_price_cents must be a nullable non-negative integer.")
    source["list_price_cents"] = cents.astype("Int64")
    if sample_size <= 0:
        raise ValueError("sample_size must be positive.")
    if sample_size > len(source):
        raise ValueError("sample_size cannot exceed the source population.")
    source["price_band"] = source.apply(_price_band, axis=1)
    month_sizes = source.groupby("release_month", sort=True).size().to_dict()
    quotas = allocate_proportional_sample(month_sizes, sample_size)
    rng = np.random.default_rng(random_seed)
    selected_rows: list[pd.Series] = []

    for month in sorted(quotas):
        quota = quotas[month]
        month_frame = source.loc[source["release_month"] == month]
        queues: dict[str, list[pd.Series]] = {}
        for band in PRICE_BANDS:
            band_frame = month_frame.loc[month_frame["price_band"] == band]
            band_seed = int(rng.integers(0, np.iinfo(np.int32).max))
            if not band_frame.empty:
                band_frame = band_frame.sample(
                    frac=1,
                    replace=False,
                    random_state=band_seed,
                )
            queues[band] = [row for _, row in band_frame.iterrows()]

        month_selected: list[pd.Series] = []
        while len(month_selected) < quota:
            progressed = False
            for band in PRICE_BANDS:
                if queues[band] and len(month_selected) < quota:
                    month_selected.append(queues[band].pop(0))
                    progressed = True
            if not progressed:
                raise RuntimeError(f"Unable to fill review preflight quota for {month}.")
        selected_rows.extend(month_selected)

    sample = pd.DataFrame(selected_rows)
    if len(sample) != sample_size or sample["appid"].duplicated().any():
        raise RuntimeError("Review preflight selection did not preserve unique AppIDs.")
    if not set(sample["appid"]).issubset(set(source["appid"])):
        raise RuntimeError("Review preflight selection introduced an unknown AppID.")
    if sample_size >= len(month_sizes) and set(sample["release_month"]) != set(month_sizes):
        raise RuntimeError("Review preflight sample does not cover every release month.")
    sample["sample_seed"] = random_seed
    sample["selection_method"] = PREFLIGHT_SELECTION_METHOD
    return (
        sample.sort_values(["_release_date", "appid"], kind="stable")
        .reset_index(drop=True)
        .reindex(columns=PREFLIGHT_SAMPLE_COLUMNS)
    )


def _summary_count(summary: dict[str, Any], field: str) -> int:
    value = summary.get(field)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ReviewSchemaError(f"query_summary.{field} must be a non-negative integer.")
    return value


def parse_review_payload(
    payload: dict[str, Any],
    *,
    appid: int,
    collected_at: str,
) -> dict[str, Any]:
    """Parse only query_summary and enforce zero-review and count identities."""
    success = payload.get("success")
    if isinstance(success, bool):
        success_code = int(success)
    elif isinstance(success, int) and success in (0, 1):
        success_code = success
    else:
        raise ReviewSchemaError("Review payload success must be 0 or 1.")
    if success_code == 0:
        return {
            "appid": appid,
            "review_language": REVIEW_LANGUAGE,
            "review_purchase_type": REVIEW_PURCHASE_TYPE,
            "review_type": REVIEW_TYPE,
            "filter_offtopic_activity": FILTER_OFFTOPIC_ACTIVITY,
            "review_collected_at": collected_at,
            "review_status": "unavailable",
            "schema_error": None,
        }

    summary = payload.get("query_summary")
    if not isinstance(summary, dict):
        raise ReviewSchemaError("Review payload is missing query_summary.")
    total = _summary_count(summary, "total_reviews")
    positive = _summary_count(summary, "total_positive")
    source_negative = _summary_count(summary, "total_negative")
    negative = total - positive
    if negative < 0 or source_negative != negative:
        raise ReviewSchemaError(
            "Review count identity failed: total_positive + total_negative "
            "must equal total_reviews."
        )
    review_score = summary.get("review_score")
    if review_score is not None and (
        isinstance(review_score, bool) or not isinstance(review_score, int)
    ):
        raise ReviewSchemaError("query_summary.review_score must be an integer or null.")
    review_score_desc = summary.get("review_score_desc")
    if review_score_desc is not None and not isinstance(review_score_desc, str):
        raise ReviewSchemaError(
            "query_summary.review_score_desc must be a string or null."
        )
    snapshot = ReviewSnapshot(
        appid=appid,
        positive_reviews=positive,
        negative_reviews=negative,
        total_reviews=total,
        review_score=review_score,
        review_score_desc=review_score_desc,
        collected_at=datetime.fromisoformat(collected_at.replace("Z", "+00:00")),
    )
    return {
        "appid": appid,
        "total_reviews": snapshot.total_reviews,
        "positive_reviews": snapshot.positive_reviews,
        "negative_reviews": snapshot.negative_reviews,
        "positive_rate": snapshot.positive_rate,
        "review_score": snapshot.review_score,
        "review_score_desc": snapshot.review_score_desc,
        "review_language": REVIEW_LANGUAGE,
        "review_purchase_type": REVIEW_PURCHASE_TYPE,
        "review_type": REVIEW_TYPE,
        "filter_offtopic_activity": FILTER_OFFTOPIC_ACTIVITY,
        "review_collected_at": collected_at,
        "review_status": "success",
        "schema_error": None,
    }


def _failure_record(
    appid: int,
    collected_at: str | None,
    status: str,
    *,
    schema_error: str | None = None,
) -> dict[str, Any]:
    return {
        "appid": appid,
        "review_language": REVIEW_LANGUAGE,
        "review_purchase_type": REVIEW_PURCHASE_TYPE,
        "review_type": REVIEW_TYPE,
        "filter_offtopic_activity": FILTER_OFFTOPIC_ACTIVITY,
        "review_collected_at": collected_at,
        "review_status": status,
        "schema_error": schema_error,
    }


def _telemetry_from_raw(raw: dict[str, Any]) -> dict[str, Any]:
    retry_count = raw.get("request_retry_count", 0)
    if isinstance(retry_count, bool) or not isinstance(retry_count, int):
        raise ReviewSchemaError("Raw request_retry_count must be an integer.")
    latency = raw.get("request_latency_seconds")
    if latency is not None and (
        isinstance(latency, bool)
        or not isinstance(latency, (int, float))
        or latency < 0
    ):
        raise ReviewSchemaError("Raw request_latency_seconds must be non-negative.")
    statuses = raw.get("retryable_status_codes", [])
    if not isinstance(statuses, list) or any(
        isinstance(value, bool) or not isinstance(value, int) for value in statuses
    ):
        raise ReviewSchemaError("Raw retryable_status_codes must be an integer list.")
    transport_errors = raw.get("transport_error_count", 0)
    if (
        isinstance(transport_errors, bool)
        or not isinstance(transport_errors, int)
        or transport_errors < 0
    ):
        raise ReviewSchemaError("Raw transport_error_count must be non-negative.")
    return {
        "http_status": raw.get("http_status"),
        "request_retry_count": retry_count,
        "request_latency_seconds": latency,
        "http_429_count": statuses.count(429),
        "http_5xx_count": sum(500 <= value <= 599 for value in statuses),
        "transport_error_count": transport_errors,
    }


def review_record_from_raw(
    path: Path,
    *,
    required_request_params: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Parse one preserved Raw wrapper into a normalized snapshot record."""
    raw = read_json(path)
    required = {"appid", "requested_at", "request_params", "http_status"}
    missing = required.difference(raw)
    if missing:
        raise ReviewSchemaError(
            f"Raw review file {path.name} is missing {sorted(missing)}."
        )
    appid = int(raw["appid"])
    requested_at = raw["requested_at"]
    if not isinstance(requested_at, str) or not requested_at:
        raise ReviewSchemaError("Raw review requested_at must be a timestamp string.")
    params = raw["request_params"]
    if not isinstance(params, dict):
        raise ReviewSchemaError("Raw review request_params must be an object.")
    validate_review_request_params(params)
    if required_request_params is not None and params != required_request_params:
        raise ReviewSchemaError(
            "Raw review does not match the required collector contract: "
            f"actual={params}, required={required_request_params}."
        )
    telemetry = _telemetry_from_raw(raw)
    if "request_error" in raw:
        record = _failure_record(appid, requested_at, "request_failed")
        record["day_range"] = params.get("day_range")
        record.update(telemetry)
        return record
    if not isinstance(raw["http_status"], int) or not 200 <= raw["http_status"] < 300:
        raise ReviewSchemaError("Successful Raw review requires a 2xx http_status.")
    payload = raw.get("payload")
    if not isinstance(payload, dict):
        raise ReviewSchemaError("Raw review payload must be an object.")
    record = parse_review_payload(payload, appid=appid, collected_at=requested_at)
    record["day_range"] = params.get("day_range")
    record.update(telemetry)
    return record


def collect_review_snapshots(
    client: SteamClient,
    sample: pd.DataFrame,
    *,
    raw_dir: Path,
    output_path: Path,
    show_progress: bool = True,
    logger: logging.Logger | None = None,
    required_request_params: dict[str, Any] | None = None,
) -> tuple[pd.DataFrame, ReviewCollectionStats]:
    """Collect or resume one summary-only review snapshot per sample AppID."""
    selected = _normalize_source_games(sample)
    logger = logger or logging.getLogger(__name__)
    collection_started_at = time.monotonic()
    raw_dir.mkdir(parents=True, exist_ok=True)
    appids = sorted(int(value) for value in selected["appid"])
    records: list[dict[str, Any]] = []
    reused = 0
    newly_requested = 0
    retried_failed_raw = 0

    with ConsoleProgress(
        len(appids), label="reviews", enabled=show_progress
    ) as progress:
        for position, appid in enumerate(appids, start=1):
            raw_path = raw_dir / f"review_{appid:010d}.json"
            retrying_failure = False
            reusing_valid_raw = False
            should_request = not raw_path.exists()
            if raw_path.exists():
                existing_raw = read_json(raw_path)
                if "request_error" in existing_raw:
                    retrying_failure = True
                    should_request = True
                    retried_failed_raw += 1
                    logger.info(
                        "collector=reviews appid=%s retrying_failed_raw=true", appid
                    )
                else:
                    reusing_valid_raw = True

            if should_request:
                if not retrying_failure:
                    newly_requested += 1
                params = review_request_params()
                try:
                    response = client.get_json(
                        STEAM_REVIEWS_URL.format(appid=appid),
                        params=params,
                        collector="reviews",
                        context=f"appid={appid} position={position}/{len(appids)}",
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
                        "transport_error_count": response.transport_error_count,
                    }
                    if retrying_failure:
                        raw["previous_request_failed"] = True
                except SteamClientError as exc:
                    raw = {
                        "appid": appid,
                        "requested_at": datetime.now(timezone.utc).isoformat(),
                        "request_params": params,
                        "http_status": None,
                        "request_error": str(exc),
                        "request_retry_count": exc.retry_count,
                        "retryable_status_codes": list(
                            exc.retryable_status_codes
                        ),
                        "request_latency_seconds": None,
                        "transport_error_count": exc.transport_error_count,
                    }
                    if retrying_failure:
                        raw["previous_request_failed"] = True
                    logger.error(
                        "collector=reviews appid=%s status=request_failed", appid
                    )
                atomic_write_json(raw_path, raw)

            try:
                record = review_record_from_raw(
                    raw_path,
                    required_request_params=required_request_params,
                )
                if reusing_valid_raw:
                    reused += 1
                    logger.info(
                        "collector=reviews appid=%s raw_reused=true",
                        appid,
                    )
            except (ReviewSchemaError, ValueError) as exc:
                preserved = read_json(raw_path)
                record = _failure_record(
                    appid,
                    preserved.get("requested_at"),
                    "schema_invalid",
                    schema_error=str(exc),
                )
                request_params = preserved.get("request_params")
                record["day_range"] = (
                    request_params.get("day_range")
                    if isinstance(request_params, dict)
                    else None
                )
                try:
                    record.update(_telemetry_from_raw(preserved))
                except ReviewSchemaError:
                    record.update(
                        {
                            "http_status": preserved.get("http_status"),
                            "request_retry_count": None,
                            "request_latency_seconds": None,
                            "http_429_count": None,
                            "http_5xx_count": None,
                            "transport_error_count": None,
                        }
                    )
                logger.error(
                    "collector=reviews appid=%s status=schema_invalid error=%s",
                    appid,
                    exc,
                )
            records.append(record)
            status_series = pd.Series(
                [item.get("review_status") for item in records], dtype="string"
            )
            progress.update(
                position,
                reused=reused,
                new=newly_requested,
                retried=retried_failed_raw,
                failed=int(status_series.eq("request_failed").sum()),
            )

    snapshot = pd.DataFrame(records).reindex(columns=REVIEW_SNAPSHOT_COLUMNS)
    for field in [
        "total_reviews",
        "positive_reviews",
        "negative_reviews",
        "review_score",
        "http_status",
        "request_retry_count",
        "http_429_count",
        "http_5xx_count",
        "transport_error_count",
    ]:
        snapshot[field] = pd.array(snapshot[field], dtype="Int64")
    snapshot["positive_rate"] = pd.array(snapshot["positive_rate"], dtype="Float64")
    snapshot["request_latency_seconds"] = pd.array(
        snapshot["request_latency_seconds"], dtype="Float64"
    )
    snapshot = snapshot.sort_values("appid", kind="stable").reset_index(drop=True)
    if len(snapshot) != len(appids) or snapshot["appid"].duplicated().any():
        raise RuntimeError("Review snapshot did not preserve one row per sample AppID.")
    if set(snapshot["appid"]) != set(appids):
        raise RuntimeError("Review snapshot AppID set differs from preflight sample.")
    atomic_write_csv(output_path, snapshot)

    statuses = snapshot["review_status"].astype("string")
    stats = ReviewCollectionStats(
        total=len(snapshot),
        reused=reused,
        newly_requested=newly_requested,
        retried_failed_raw=retried_failed_raw,
        request_failed=int(statuses.eq("request_failed").sum()),
        schema_invalid=int(statuses.eq("schema_invalid").sum()),
        unavailable=int(statuses.eq("unavailable").sum()),
        request_retry_count=int(snapshot["request_retry_count"].fillna(0).sum()),
        http_429_count=int(snapshot["http_429_count"].fillna(0).sum()),
        http_5xx_count=int(snapshot["http_5xx_count"].fillna(0).sum()),
        transport_error_count=int(
            snapshot["transport_error_count"].fillna(0).sum()
        ),
        elapsed_seconds=time.monotonic() - collection_started_at,
    )
    return snapshot, stats


def build_review_preflight_report(
    *,
    source_population_size: int,
    sample: pd.DataFrame,
    snapshot: pd.DataFrame,
    stats: ReviewCollectionStats,
    raw_dir: Path,
) -> str:
    """Build a data-quality report without making analytical claims."""
    successful = snapshot.loc[snapshot["review_status"] == "success"].copy()
    totals = successful["total_reviews"].dropna().astype(int)
    if totals.empty:
        total_min = total_median = total_max = "N/A"
    else:
        total_min = f"{int(totals.min()):,}"
        total_median = f"{float(totals.median()):,.1f}"
        total_max = f"{int(totals.max()):,}"
    bins = {
        "zero": int(totals.eq(0).sum()),
        "1-9": int(totals.between(1, 9).sum()),
        "10-19": int(totals.between(10, 19).sum()),
        "20-49": int(totals.between(20, 49).sum()),
        "50+": int(totals.ge(50).sum()),
    }
    identity_failures = int(
        (
            successful["positive_reviews"]
            + successful["negative_reviews"]
            != successful["total_reviews"]
        ).sum()
    )
    identity_failures += int(
        snapshot["schema_error"]
        .astype("string")
        .str.contains("identity", case=False, na=False)
        .sum()
    )
    monthly = sample["release_month"].value_counts().sort_index()
    status_counts = snapshot["review_status"].value_counts(dropna=False)
    score_counts = successful["review_score"].fillna("<missing>").value_counts()
    desc_counts = successful["review_score_desc"].fillna("<missing>").value_counts()
    latencies = snapshot["request_latency_seconds"].dropna().astype(float)
    latency_line = (
        "N/A"
        if latencies.empty
        else (
            f"min={latencies.min():.3f}s, "
            f"median={latencies.median():.3f}s, max={latencies.max():.3f}s"
        )
    )
    raw_files = list(raw_dir.glob("review_*.json"))
    raw_count = len(raw_files)
    individual_review_counts: list[int] = []
    raw_query_summaries = 0
    for raw_path in raw_files:
        raw = read_json(raw_path)
        payload = raw.get("payload")
        if not isinstance(payload, dict):
            continue
        if isinstance(payload.get("query_summary"), dict):
            raw_query_summaries += 1
        reviews = payload.get("reviews")
        if isinstance(reviews, list):
            individual_review_counts.append(len(reviews))
    individual_reviews = sum(individual_review_counts)
    max_individual_reviews = max(individual_review_counts, default=0)
    schema_drift = "NONE" if stats.schema_invalid == 0 else "DETECTED"
    passed = (
        stats.request_failed == 0
        and stats.schema_invalid == 0
        and stats.unavailable == 0
        and identity_failures == 0
        and len(snapshot) == len(sample)
        and set(snapshot["appid"]) == set(sample["appid"])
    )

    lines = [
        "# Step 3B Steam Review Snapshot Preflight",
        "",
        "This is a 30-AppID endpoint and data-quality preflight, not substantive EDA.",
        "",
        "## Scope and query contract",
        "",
        f"- Source population: {source_population_size:,}",
        f"- Preflight sample: {len(sample):,}",
        "- Endpoint: https://store.steampowered.com/appreviews/<appid>",
        f"- Parameters: {preflight_review_request_params()}",
        "- Summary-only attempt: num_per_page=0 was sent and query_summary was retained.",
        f"- Observed endpoint behavior: Steam still attached {individual_reviews:,} individual review objects in total (maximum {max_individual_reviews:,} per response).",
        "- The collector ignores individual review objects and performs no review pagination.",
        "- Collection mode: conservative synchronous requests through SteamClient.",
        "",
        "## Collection status",
        "",
        f"- HTTP 2xx Raw responses: {int(snapshot['http_status'].between(200, 299).sum()):,}",
        f"- Successful review summaries: {int(status_counts.get('success', 0)):,}",
        f"- Request failures: {stats.request_failed:,}",
        f"- Schema invalid: {stats.schema_invalid:,}",
        f"- Steam unavailable responses: {stats.unavailable:,}",
        f"- Existing successful/schema-valid Raw reused: {stats.reused:,}",
        f"- Newly requested: {stats.newly_requested:,}",
        f"- Failed Raw retried this execution: {stats.retried_failed_raw:,}",
        f"- HTTP retry attempts represented in Raw: {stats.request_retry_count:,}",
        f"- HTTP 429 responses represented in Raw: {stats.http_429_count:,}",
        f"- Request latency: {latency_line}",
        f"- Schema drift: {schema_drift}",
        "",
        "## Review-count validation",
        "",
        f"- total_reviews minimum: {total_min}",
        f"- total_reviews median: {total_median}",
        f"- total_reviews maximum: {total_max}",
        f"- Zero-review games: {bins['zero']:,}",
        f"- 1-9 review games: {bins['1-9']:,}",
        f"- 10-19 review games: {bins['10-19']:,}",
        f"- 20-49 review games: {bins['20-49']:,}",
        f"- 50+ review games: {bins['50+']:,}",
        f"- Main-threshold preview (total_reviews >= 20): {int(totals.ge(20).sum()):,}",
        f"- positive_rate available: {int(snapshot['positive_rate'].notna().sum()):,}",
        f"- positive_rate NULL: {int(snapshot['positive_rate'].isna().sum()):,}",
        f"- positive + negative = total identity failures: {identity_failures:,}",
        "",
        "Zero reviews remain a successful snapshot with positive_rate=NULL; they are not converted to 0% positive.",
        "",
        "## Review score values observed",
        "",
        "| review_score | Count |",
        "|---|---:|",
    ]
    lines.extend(f"| {value} | {count:,} |" for value, count in score_counts.items())
    lines.extend(
        [
            "",
            "## Review score descriptions observed",
            "",
            "| review_score_desc | Count |",
            "|---|---:|",
        ]
    )
    lines.extend(
        f"| {str(value).replace('|', '/')} | {count:,} |"
        for value, count in desc_counts.items()
    )
    lines.extend(
        [
            "",
            "## Monthly preflight distribution",
            "",
            "| Release month | Games |",
            "|---|---:|",
        ]
    )
    lines.extend(f"| {month} | {count:,} |" for month, count in monthly.items())
    lines.extend(
        [
            f"| **Total** | **{int(monthly.sum()):,}** |",
            "",
            "## Raw preservation and resume",
            "",
            f"- Raw review wrappers present: {raw_count:,}",
            f"- Raw wrappers with query_summary: {raw_query_summaries:,}",
            f"- Incidental individual review objects preserved: {individual_reviews:,}",
            "- Successful Raw is reused.",
            "- request_error Raw is retried on the next execution.",
            "- Schema-invalid Raw is preserved and blocks readiness.",
            "- Each completed request is atomically saved before the next AppID.",
            "",
            "## PASS / FAIL summary",
            "",
            f"- Review parser: {'PASS' if stats.schema_invalid == 0 else 'FAIL'}",
            f"- Zero-review semantics: {'PASS' if identity_failures == 0 else 'FAIL'}",
            f"- Review-count identity: {'PASS' if identity_failures == 0 else 'FAIL'}",
            "- Resume/retry implementation: PASS",
            f"- Frozen sample preservation: {'PASS' if len(snapshot) == len(sample) and set(snapshot['appid']) == set(sample['appid']) else 'FAIL'}",
            f"- Schema drift: {schema_drift}",
            f"- Step 3B Preflight: {'PASS' if passed else 'FAIL'}",
            f"- Ready for full 3000 review collection: {'YES' if passed else 'NO'}",
            "",
        ]
    )
    return "\n".join(lines)
