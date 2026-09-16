"""Reproducible proportional stratified sampling utilities."""

from __future__ import annotations

import json
import math
import warnings
from collections.abc import Hashable, Mapping
from datetime import date, datetime
from numbers import Integral

import numpy as np
import pandas as pd


def allocate_proportional_sample(
    stratum_sizes: Mapping[Hashable, int],
    target_size: int,
) -> dict[Hashable, int]:
    """Allocate a capped proportional sample using largest remainders.

    Ties in fractional remainders are resolved by the string representation of
    the stratum key, making the allocation deterministic across runs.
    """
    if isinstance(target_size, bool) or not isinstance(target_size, Integral):
        raise TypeError("target_size must be an integer.")
    target_size = int(target_size)
    if target_size < 0:
        raise ValueError("target_size cannot be negative.")

    sizes: dict[Hashable, int] = {}
    for key, value in stratum_sizes.items():
        if isinstance(value, bool) or not isinstance(value, Integral):
            raise TypeError("Every stratum size must be an integer.")
        if value < 0:
            raise ValueError("Stratum sizes cannot be negative.")
        sizes[key] = int(value)

    total_size = sum(sizes.values())
    if total_size == 0 or target_size == 0:
        return {key: 0 for key in sizes}
    if target_size >= total_size:
        return sizes.copy()

    exact = {
        key: target_size * stratum_size / total_size
        for key, stratum_size in sizes.items()
    }
    allocation = {
        key: min(math.floor(exact[key]), sizes[key]) for key in sizes
    }
    seats_remaining = target_size - sum(allocation.values())

    remainder_order = sorted(
        sizes,
        key=lambda key: (-(exact[key] - math.floor(exact[key])), str(key)),
    )

    while seats_remaining:
        seats_assigned = 0
        for key in remainder_order:
            if allocation[key] >= sizes[key]:
                continue
            allocation[key] += 1
            seats_remaining -= 1
            seats_assigned += 1
            if seats_remaining == 0:
                break
        if seats_assigned == 0:
            raise RuntimeError("Unable to distribute all sample seats.")

    return allocation


def _parse_study_window(
    start_date: str | date | datetime | pd.Timestamp,
    end_date: str | date | datetime | pd.Timestamp,
) -> tuple[pd.Timestamp, pd.Timestamp]:
    """Parse and validate inclusive study-window boundaries."""
    try:
        start = pd.Timestamp(start_date).normalize()
        end = pd.Timestamp(end_date).normalize()
    except (TypeError, ValueError) as exc:
        raise ValueError("start_date and end_date must be valid dates.") from exc
    if pd.isna(start) or pd.isna(end):
        raise ValueError("start_date and end_date must be valid dates.")
    if start > end:
        raise ValueError("start_date cannot be after end_date.")
    return start, end


def _stable_value(value: object) -> object:
    """Convert a scalar candidate value to a deterministic JSON representation."""
    if value is None:
        return None
    if isinstance(value, (pd.Timestamp, datetime, date)):
        return value.isoformat()
    try:
        if bool(pd.isna(value)):
            return None
    except (TypeError, ValueError):
        pass
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, (str, int, float, bool)):
        return value
    return str(value)


def _example_rows(frame: pd.DataFrame, mask: pd.Series, limit: int = 3) -> str:
    examples = frame.loc[mask, ["appid", "release_date"]].head(limit)
    return "; ".join(
        f"appid={row.appid}, release_date={row.release_date!r}"
        for row in examples.itertuples(index=False)
    )


def canonicalize_candidates(
    candidates: pd.DataFrame,
    start_date: str | date | datetime | pd.Timestamp,
    end_date: str | date | datetime | pd.Timestamp,
) -> pd.DataFrame:
    """Choose one deterministic canonical record for each candidate AppID.

    Records with an in-window parseable release date are preferred. Remaining
    ties use the earliest valid collection timestamp, then stable metadata and
    a serialization of every input field. Duplicate and conflicting AppID-group
    counts are always surfaced in a warning.
    """
    required_columns = {"appid", "release_date"}
    missing_columns = required_columns.difference(candidates.columns)
    if missing_columns:
        missing = ", ".join(sorted(missing_columns))
        raise ValueError(f"Missing required columns: {missing}")

    start, end = _parse_study_window(start_date, end_date)
    frame = candidates.copy()

    valid_appid = frame["appid"].map(
        lambda value: not isinstance(value, bool) and isinstance(value, Integral)
    )
    if not valid_appid.all():
        invalid_count = int((~valid_appid).sum())
        examples = frame.loc[~valid_appid, "appid"].head(3).tolist()
        raise ValueError(
            f"appid contains {invalid_count} invalid value(s); examples={examples}."
        )
    frame["appid"] = frame["appid"].map(int)

    parsed_release = pd.to_datetime(frame["release_date"], errors="coerce")
    frame["__release_sort"] = parsed_release
    frame["__in_window"] = parsed_release.notna() & parsed_release.between(start, end)

    if "candidate_collected_at" in frame.columns:
        frame["__collected_sort"] = pd.to_datetime(
            frame["candidate_collected_at"], errors="coerce", utc=True
        )
    else:
        frame["__collected_sort"] = pd.Series(
            pd.NaT, index=frame.index, dtype="datetime64[ns, UTC]"
        )

    frame["__name_sort"] = (
        frame["name"].fillna("").astype(str) if "name" in frame.columns else ""
    )
    frame["__source_sort"] = (
        frame["source"].fillna("").astype(str) if "source" in frame.columns else ""
    )

    original_columns = list(candidates.columns)
    stable_columns = sorted(original_columns)
    provenance_columns = {
        "candidate_collected_at",
        "search_page",
        "search_position",
        "search_rank",
        "source",
    }
    content_columns = [
        column for column in stable_columns if column not in provenance_columns
    ]
    frame["__row_key"] = frame.apply(
        lambda row: json.dumps(
            {column: _stable_value(row[column]) for column in stable_columns},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ),
        axis=1,
    )
    frame["__content_key"] = frame.apply(
        lambda row: json.dumps(
            {column: _stable_value(row[column]) for column in content_columns},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ),
        axis=1,
    )

    group_sizes = frame.groupby("appid", sort=False).size()
    duplicate_appids = group_sizes[group_sizes > 1].index
    duplicate_count = len(duplicate_appids)
    if duplicate_count:
        conflicting_count = sum(
            frame.loc[frame["appid"] == appid, "__content_key"].nunique(
                dropna=False
            )
            > 1
            for appid in duplicate_appids
        )
        warnings.warn(
            "Canonicalized "
            f"{duplicate_count} duplicate AppID group(s); "
            f"{conflicting_count} group(s) contained conflicting records.",
            RuntimeWarning,
            stacklevel=2,
        )

    ordered = frame.sort_values(
        [
            "appid",
            "__in_window",
            "__collected_sort",
            "__release_sort",
            "__name_sort",
            "__source_sort",
            "__row_key",
        ],
        ascending=[True, False, True, True, True, True, True],
        na_position="last",
        kind="stable",
    )
    canonical = ordered.drop_duplicates(subset="appid", keep="first")
    return (
        canonical.loc[:, original_columns]
        .sort_values("appid", kind="stable")
        .reset_index(drop=True)
    )


def proportional_stratified_sample(
    candidates: pd.DataFrame,
    target_size: int,
    random_seed: int,
    start_date: str | date | datetime | pd.Timestamp,
    end_date: str | date | datetime | pd.Timestamp,
) -> pd.DataFrame:
    """Sample candidates proportionally by release month.

    Canonical records must have valid dates inside the inclusive study window.
    If the unique candidate pool is smaller than the requested target, the full
    pool is returned with a warning.
    """
    required_columns = {"appid", "release_date"}
    missing_columns = required_columns.difference(candidates.columns)
    if missing_columns:
        missing = ", ".join(sorted(missing_columns))
        raise ValueError(f"Missing required columns: {missing}")
    if isinstance(target_size, bool) or not isinstance(target_size, Integral):
        raise TypeError("target_size must be an integer.")
    target_size = int(target_size)
    if target_size < 0:
        raise ValueError("target_size cannot be negative.")

    if isinstance(random_seed, bool) or not isinstance(random_seed, Integral):
        raise TypeError("random_seed must be an integer.")
    random_seed = int(random_seed)

    start, end = _parse_study_window(start_date, end_date)
    frame = canonicalize_candidates(candidates, start, end)
    parsed_dates = pd.to_datetime(frame["release_date"], errors="coerce")
    invalid_mask = parsed_dates.isna()
    if invalid_mask.any():
        invalid_count = int(invalid_mask.sum())
        examples = _example_rows(frame, invalid_mask)
        raise ValueError(
            "release_date contains "
            f"{invalid_count} invalid or missing value(s). Examples: {examples}"
        )
    frame["release_date"] = parsed_dates.dt.normalize()

    outside_mask = ~frame["release_date"].between(start, end)
    if outside_mask.any():
        invalid_count = int(outside_mask.sum())
        examples = _example_rows(frame, outside_mask)
        raise ValueError(
            f"release_date contains {invalid_count} value(s) outside study window "
            f"[{start.date()}, {end.date()}]. Examples: {examples}"
        )

    frame["release_month"] = frame["release_date"].dt.to_period("M").astype(str)

    if len(frame) <= target_size:
        if len(frame) < target_size:
            warnings.warn(
                "Candidate pool is smaller than target_size; returning the full "
                "unique candidate pool.",
                RuntimeWarning,
                stacklevel=2,
            )
        return frame.sort_values(["release_date", "appid"], kind="stable").reset_index(
            drop=True
        )

    month_sizes = frame.groupby("release_month", sort=True).size().to_dict()
    quotas = allocate_proportional_sample(month_sizes, target_size)
    rng = np.random.default_rng(random_seed)

    sampled_parts: list[pd.DataFrame] = []
    for month in sorted(quotas, key=str):
        quota = quotas[month]
        if quota == 0:
            continue
        month_frame = frame.loc[frame["release_month"] == month]
        month_seed = int(rng.integers(0, np.iinfo(np.int32).max))
        sampled_parts.append(
            month_frame.sample(n=quota, replace=False, random_state=month_seed)
        )

    sampled = pd.concat(sampled_parts, ignore_index=True)
    if len(sampled) != target_size:
        raise RuntimeError("Internal error: sampled row count does not match target_size.")
    if sampled["appid"].duplicated().any():
        raise RuntimeError("Internal error: duplicate AppIDs found in sample.")

    return sampled.sort_values(["release_date", "appid"], kind="stable").reset_index(
        drop=True
    )
