"""Purely local materialization of the frozen final-sample metadata layer."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

import pandas as pd

from config.settings import (
    END_DATE,
    GAME_GENRES_PATH,
    GAMES_PATH,
    RANDOM_SEED,
    SAMPLE_GAMES_PATH,
    START_DATE,
    STEP3A_METADATA_REPORT_PATH,
    TARGET_SAMPLE_SIZE,
)
from src.io_utils import atomic_write_csv, atomic_write_text
from src.preflight import build_genre_relations


SAMPLING_SOURCE = "proportional_stratified_random_sample"
EXPECTED_MONTH_COUNTS = {
    "2025-07": 497,
    "2025-08": 470,
    "2025-09": 427,
    "2025-10": 544,
    "2025-11": 580,
    "2025-12": 482,
}

GAMES_COLUMNS = [
    "sample_id",
    "appid",
    "name",
    "release_date",
    "release_month",
    "developer",
    "publisher",
    "is_free",
    "platform_windows",
    "platform_mac",
    "platform_linux",
    "appdetails_status",
    "app_type",
    "list_price_cents",
    "current_price_cents",
    "discount_percent",
    "price_currency",
    "price_overview_present",
    "list_price_usd",
    "current_price_usd",
    "metadata_collected_at",
    "search_release_date",
    "store_release_date",
    "release_date_conflict",
    "is_early_access",
    "sample_seed",
    "sampling_stratum",
    "sampling_source",
]
GAME_GENRE_COLUMNS = ["appid", "genre_id", "genre_name"]
MISSING_AUDIT_COLUMNS = [
    "name",
    "release_date",
    "developer",
    "publisher",
    "is_free",
    "platform_windows",
    "platform_mac",
    "platform_linux",
    "list_price_cents",
    "current_price_cents",
    "discount_percent",
    "price_currency",
    "metadata_collected_at",
    "is_early_access",
]


class MetadataMaterializationError(ValueError):
    """A local source or derived-output invariant failed."""


def _require_columns(frame: pd.DataFrame, required: Iterable[str], label: str) -> None:
    missing = set(required).difference(frame.columns)
    if missing:
        raise MetadataMaterializationError(
            f"{label} is missing required columns: {sorted(missing)}"
        )


def _blank_mask(series: pd.Series) -> pd.Series:
    return series.isna() | series.astype("string").str.strip().eq("").fillna(True)


def _normalize_unique_appids(frame: pd.DataFrame, label: str) -> pd.DataFrame:
    _require_columns(frame, ["appid"], label)
    result = frame.copy()
    numeric = pd.to_numeric(result["appid"], errors="coerce")
    if numeric.isna().any() or (numeric.dropna() % 1 != 0).any():
        raise MetadataMaterializationError(f"{label} contains invalid AppIDs.")
    result["appid"] = numeric.astype("int64")
    duplicate_mask = result["appid"].duplicated(keep=False)
    if duplicate_mask.any():
        examples = sorted(result.loc[duplicate_mask, "appid"].unique())[:5]
        raise MetadataMaterializationError(
            f"{label} contains duplicate AppID values; examples={examples}."
        )
    return result


def _nullable_boolean(series: pd.Series, field: str) -> pd.Series:
    missing = _blank_mask(series)
    normalized = series.astype("string").str.strip().str.casefold()
    accepted = normalized.isin(["true", "false", "1", "0"])
    invalid = ~missing & ~accepted
    if invalid.any():
        examples = series.loc[invalid].astype(str).unique()[:5].tolist()
        raise MetadataMaterializationError(
            f"{field} contains non-boolean values; examples={examples}."
        )
    result = pd.Series(pd.NA, index=series.index, dtype="boolean")
    result.loc[normalized.isin(["true", "1"])] = True
    result.loc[normalized.isin(["false", "0"])] = False
    return result


def _nullable_integer(
    series: pd.Series,
    field: str,
    *,
    minimum: int | None = None,
    maximum: int | None = None,
) -> pd.Series:
    missing = _blank_mask(series)
    numeric = pd.to_numeric(series.where(~missing), errors="coerce")
    invalid = ~missing & numeric.isna()
    if invalid.any() or (numeric.dropna() % 1 != 0).any():
        raise MetadataMaterializationError(f"{field} must be a nullable integer.")
    if minimum is not None and numeric.dropna().lt(minimum).any():
        raise MetadataMaterializationError(f"{field} cannot be below {minimum}.")
    if maximum is not None and numeric.dropna().gt(maximum).any():
        raise MetadataMaterializationError(f"{field} cannot exceed {maximum}.")
    return numeric.astype("Int64")


def _exact_dates(series: pd.Series, field: str) -> pd.Series:
    missing = _blank_mask(series)
    parsed = pd.to_datetime(series.where(~missing), format="%Y-%m-%d", errors="coerce")
    if missing.any() or parsed.isna().any():
        raise MetadataMaterializationError(
            f"{field} must contain complete YYYY-MM-DD dates."
        )
    return parsed


def _assert_series_equal(left: pd.Series, right: pd.Series, label: str) -> None:
    left_values = left.astype("string").fillna("<NULL>")
    right_values = right.astype("string").fillna("<NULL>")
    mismatch = left_values.ne(right_values)
    if mismatch.any():
        raise MetadataMaterializationError(
            f"{label} differs for {int(mismatch.sum())} sample AppID(s)."
        )


def validate_price_schema(games: pd.DataFrame) -> None:
    """Validate source-unit prices without treating missing prices as free status."""
    _require_columns(
        games,
        [
            "is_free",
            "price_overview_present",
            "list_price_cents",
            "current_price_cents",
            "discount_percent",
            "price_currency",
        ],
        "games",
    )
    if games["is_free"].isna().any() or games["price_overview_present"].isna().any():
        raise MetadataMaterializationError(
            "is_free and price_overview_present must be known for every game."
        )

    price_fields = [
        "list_price_cents",
        "current_price_cents",
        "discount_percent",
        "price_currency",
    ]
    overview = games["price_overview_present"].astype(bool)
    incomplete_overview = overview & games[price_fields].isna().any(axis=1)
    if incomplete_overview.any():
        raise MetadataMaterializationError(
            "price_overview_present=True requires complete cents, discount, and currency."
        )
    values_without_overview = ~overview & games[price_fields].notna().any(axis=1)
    if values_without_overview.any():
        raise MetadataMaterializationError(
            "Price values are present while price_overview_present=False."
        )


def validate_genre_relations(
    relations: pd.DataFrame,
    game_appids: Iterable[int],
) -> None:
    """Require in-sample, non-conflicting game/genre relationship rows."""
    _require_columns(relations, GAME_GENRE_COLUMNS, "game_genres")
    game_ids = {int(value) for value in game_appids}
    if relations.empty:
        return
    relation_ids = pd.to_numeric(relations["appid"], errors="coerce")
    if relation_ids.isna().any() or (relation_ids % 1 != 0).any():
        raise MetadataMaterializationError("game_genres contains invalid AppIDs.")
    outside = set(relation_ids.astype(int)).difference(game_ids)
    if outside:
        raise MetadataMaterializationError(
            f"game_genres contains AppIDs outside games; examples={sorted(outside)[:5]}."
        )
    if _blank_mask(relations["genre_name"]).any():
        raise MetadataMaterializationError("game_genres contains missing genre names.")

    genre_id_available = ~_blank_mask(relations["genre_id"])
    keyed = relations.loc[genre_id_available]
    duplicate_keys = keyed.duplicated(["appid", "genre_id"], keep=False)
    if duplicate_keys.any():
        duplicates = keyed.loc[duplicate_keys]
        conflicts = int(
            (duplicates.groupby(["appid", "genre_id"])["genre_name"].nunique() > 1).sum()
        )
        exact_rows = int(
            duplicates.duplicated(
                ["appid", "genre_id", "genre_name"], keep=False
            ).sum()
        )
        raise MetadataMaterializationError(
            "Duplicate (appid, genre_id) relationships detected: "
            f"exact_duplicate_rows={exact_rows}, conflicting_keys={conflicts}."
        )
    missing_id_exact = relations.loc[~genre_id_available].duplicated(
        ["appid", "genre_name"], keep=False
    )
    if missing_id_exact.any():
        raise MetadataMaterializationError(
            "Exact duplicate genre relationships with missing genre_id detected."
        )


def validate_monthly_counts(
    games: pd.DataFrame,
    expected: Mapping[str, int],
) -> None:
    actual = games["release_month"].value_counts().sort_index().to_dict()
    expected_values = dict(expected)
    if actual != expected_values:
        raise MetadataMaterializationError(
            f"Monthly sample allocation differs: actual={actual}, expected={expected_values}."
        )


def materialize_sample_metadata(
    sample_games: pd.DataFrame,
    metadata: pd.DataFrame,
    eligible_frame: pd.DataFrame,
    *,
    expected_size: int | None = None,
    expected_month_counts: Mapping[str, int] | None = None,
    start_date: str = START_DATE,
    end_date: str = END_DATE,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Build one games row per authoritative sample AppID plus genre relations."""
    sample = _normalize_unique_appids(sample_games, "sample_games")
    metadata = _normalize_unique_appids(metadata, "candidate_appdetails")
    eligible = _normalize_unique_appids(eligible_frame, "eligible_sampling_frame")
    if expected_size is not None and len(sample) != expected_size:
        raise MetadataMaterializationError(
            f"sample_games has {len(sample)} rows; expected {expected_size}."
        )

    sample_required = [
        "appid",
        "name",
        "release_date",
        "release_month",
        "developer",
        "publisher",
        "is_free",
        "platform_windows",
        "platform_mac",
        "platform_linux",
        "search_release_date",
        "store_release_date",
        "release_date_conflict",
        "is_early_access",
    ]
    metadata_required = [
        "appid",
        "appdetails_status",
        "app_type",
        "store_name",
        "is_free",
        "store_release_date",
        "platform_windows",
        "platform_mac",
        "platform_linux",
        "genres",
        "list_price_cents",
        "current_price_cents",
        "discount_percent",
        "price_currency",
        "price_overview_present",
        "metadata_collected_at",
    ]
    _require_columns(sample, sample_required, "sample_games")
    _require_columns(metadata, metadata_required, "candidate_appdetails")
    _require_columns(eligible, ["appid", "release_date"], "eligible_sampling_frame")

    sample_ids = set(sample["appid"])
    metadata_ids = set(metadata["appid"])
    eligible_ids = set(eligible["appid"])
    missing_metadata = sample_ids.difference(metadata_ids)
    missing_eligible = sample_ids.difference(eligible_ids)
    if missing_metadata or missing_eligible:
        raise MetadataMaterializationError(
            "Sample AppID join coverage failed: "
            f"missing_metadata={len(missing_metadata)}, "
            f"missing_eligible={len(missing_eligible)}."
        )

    selected_metadata = metadata.loc[metadata["appid"].isin(sample_ids)].copy()
    selected_eligible = eligible.loc[
        eligible["appid"].isin(sample_ids), ["appid", "release_date"]
    ].rename(columns={"release_date": "eligible_release_date"})
    metadata_join = selected_metadata[metadata_required].rename(
        columns={
            "is_free": "metadata_is_free",
            "store_release_date": "metadata_store_release_date",
            "platform_windows": "metadata_platform_windows",
            "platform_mac": "metadata_platform_mac",
            "platform_linux": "metadata_platform_linux",
        }
    )
    joined = sample.merge(metadata_join, on="appid", how="left", validate="one_to_one")
    joined = joined.merge(
        selected_eligible, on="appid", how="left", validate="one_to_one"
    )
    if len(joined) != len(sample) or set(joined["appid"]) != sample_ids:
        raise MetadataMaterializationError("Metadata join added, removed, or replaced AppIDs.")
    if joined["appdetails_status"].ne("success").any():
        raise MetadataMaterializationError(
            "Every final-sample AppID must have successful appdetails metadata."
        )
    if joined["app_type"].ne("game").any():
        raise MetadataMaterializationError("Every final-sample AppID must be a game.")

    for field in ["is_free", "platform_windows", "platform_mac", "platform_linux"]:
        joined[field] = _nullable_boolean(joined[field], field)
        metadata_field = f"metadata_{field}"
        joined[metadata_field] = _nullable_boolean(
            joined[metadata_field], metadata_field
        )
        _assert_series_equal(joined[field], joined[metadata_field], f"{field} authority")
    joined["release_date_conflict"] = _nullable_boolean(
        joined["release_date_conflict"], "release_date_conflict"
    )
    joined["is_early_access"] = _nullable_boolean(
        joined["is_early_access"], "is_early_access"
    )
    if joined["is_early_access"].notna().any():
        raise MetadataMaterializationError(
            "is_early_access must remain unknown for the current metadata source."
        )

    search_dates = _exact_dates(joined["search_release_date"], "search_release_date")
    sample_store_dates = _exact_dates(
        joined["store_release_date"], "store_release_date"
    )
    store_dates = _exact_dates(
        joined["metadata_store_release_date"], "metadata store_release_date"
    )
    eligible_dates = _exact_dates(
        joined["eligible_release_date"], "eligible release_date"
    )
    sample_dates = _exact_dates(joined["release_date"], "sample release_date")
    _assert_series_equal(sample_store_dates, store_dates, "Store release date")
    _assert_series_equal(sample_dates, store_dates, "Final release date")
    _assert_series_equal(eligible_dates, store_dates, "Eligible-frame release date")
    computed_conflict = search_dates.ne(store_dates)
    _assert_series_equal(
        joined["release_date_conflict"],
        computed_conflict,
        "release_date_conflict",
    )
    start = pd.Timestamp(start_date)
    end = pd.Timestamp(end_date)
    if not store_dates.between(start, end).all():
        raise MetadataMaterializationError(
            "Final release dates fall outside the study window."
        )
    derived_month = store_dates.dt.strftime("%Y-%m")
    _assert_series_equal(joined["release_month"], derived_month, "release_month")

    games = pd.DataFrame(index=joined.index)
    games["appid"] = joined["appid"].astype("int64")
    store_names = joined["store_name"].mask(_blank_mask(joined["store_name"]))
    sample_names = joined["name"].mask(_blank_mask(joined["name"]))
    games["name"] = store_names.combine_first(sample_names).astype("string")
    if games["name"].isna().any():
        raise MetadataMaterializationError("Name is missing from both Store and Search.")
    games["release_date"] = store_dates.dt.strftime("%Y-%m-%d")
    games["release_month"] = derived_month
    games["developer"] = joined["developer"].mask(_blank_mask(joined["developer"]))
    games["publisher"] = joined["publisher"].mask(_blank_mask(joined["publisher"]))
    if games["developer"].isna().any():
        raise MetadataMaterializationError("Final games contain missing developers.")
    for field in ["is_free", "platform_windows", "platform_mac", "platform_linux"]:
        games[field] = joined[field]
    games["appdetails_status"] = joined["appdetails_status"].astype("string")
    games["app_type"] = joined["app_type"].astype("string")
    games["list_price_cents"] = _nullable_integer(
        joined["list_price_cents"], "list_price_cents", minimum=0
    )
    games["current_price_cents"] = _nullable_integer(
        joined["current_price_cents"], "current_price_cents", minimum=0
    )
    games["discount_percent"] = _nullable_integer(
        joined["discount_percent"],
        "discount_percent",
        minimum=0,
        maximum=100,
    )
    games["price_currency"] = joined["price_currency"].astype("string").str.strip()
    games.loc[_blank_mask(games["price_currency"]), "price_currency"] = pd.NA
    games["price_overview_present"] = _nullable_boolean(
        joined["price_overview_present"], "price_overview_present"
    )
    games["list_price_usd"] = games["list_price_cents"].astype("Float64") / 100
    games["current_price_usd"] = (
        games["current_price_cents"].astype("Float64") / 100
    )
    games["metadata_collected_at"] = (
        joined["metadata_collected_at"].astype("string").str.strip()
    )
    games.loc[
        _blank_mask(games["metadata_collected_at"]), "metadata_collected_at"
    ] = pd.NA
    if games["metadata_collected_at"].isna().any():
        raise MetadataMaterializationError("metadata_collected_at is required.")
    games["search_release_date"] = search_dates.dt.strftime("%Y-%m-%d")
    games["store_release_date"] = store_dates.dt.strftime("%Y-%m-%d")
    games["release_date_conflict"] = joined["release_date_conflict"]
    games["is_early_access"] = joined["is_early_access"]
    games["sample_seed"] = RANDOM_SEED
    games["sampling_stratum"] = games["release_month"]
    games["sampling_source"] = SAMPLING_SOURCE
    validate_price_schema(games)

    games = games.sort_values(["release_date", "appid"], kind="stable").reset_index(
        drop=True
    )
    games.insert(0, "sample_id", range(1, len(games) + 1))
    games = games[GAMES_COLUMNS]

    relations = build_genre_relations(selected_metadata)
    if not relations.empty:
        relations["appid"] = pd.to_numeric(
            relations["appid"], errors="raise"
        ).astype("int64")
        relations["genre_id"] = relations["genre_id"].astype("string")
        relations["genre_name"] = relations["genre_name"].astype("string")
        relations = relations.sort_values(
            ["appid", "genre_id", "genre_name"],
            kind="stable",
            na_position="last",
        ).reset_index(drop=True)
    relations = relations[GAME_GENRE_COLUMNS]
    validate_genre_relations(relations, games["appid"])

    if expected_month_counts is not None:
        validate_monthly_counts(games, expected_month_counts)
    return games, relations


def missing_value_summary(games: pd.DataFrame) -> pd.DataFrame:
    """Classify known source absence separately from unexpected missingness."""
    _require_columns(games, MISSING_AUDIT_COLUMNS, "games")
    free = games["is_free"].fillna(False).astype(bool)
    unavailable_paid = (
        ~free & ~games["price_overview_present"].fillna(False).astype(bool)
    )
    expected_price_missing = free | unavailable_paid
    rows: list[dict[str, Any]] = []
    for field in MISSING_AUDIT_COLUMNS:
        missing = _blank_mask(games[field])
        if field in {
            "list_price_cents",
            "current_price_cents",
            "discount_percent",
            "price_currency",
        }:
            expected = missing & expected_price_missing
            note = (
                "Expected for free games or paid games without a Store price overview"
            )
        elif field == "publisher":
            expected = missing
            note = "Source publisher can be absent; retained as null"
        elif field == "is_early_access":
            expected = missing
            note = "Unknown because appdetails has no reliable explicit field"
        else:
            expected = pd.Series(False, index=games.index)
            note = "Required final metadata field"
        rows.append(
            {
                "field": field,
                "missing": int(missing.sum()),
                "expected_missing": int(expected.sum()),
                "unexpected_missing": int((missing & ~expected).sum()),
                "interpretation": note,
            }
        )
    return pd.DataFrame(rows)


def build_step3a_report(
    sample_games: pd.DataFrame,
    games: pd.DataFrame,
    genres: pd.DataFrame,
) -> str:
    """Render the required data-quality report for the materialized outputs."""
    monthly = games["release_month"].value_counts().sort_index()
    paid = games.loc[~games["is_free"].astype(bool)]
    currencies = paid["price_currency"].fillna("<missing>").value_counts()
    missing = missing_value_summary(games)
    genre_games = int(genres["appid"].nunique()) if not genres.empty else 0
    unique_genre_ids = int(genres["genre_id"].dropna().nunique())
    unique_genre_names = int(genres["genre_name"].dropna().nunique())
    unexpected_missing = int(missing["unexpected_missing"].sum())
    price_missing = missing.loc[
        missing["field"].isin(
            [
                "list_price_cents",
                "current_price_cents",
                "discount_percent",
                "price_currency",
            ]
        )
    ]
    paid_without_overview = int((~paid["price_overview_present"].astype(bool)).sum())

    lines = [
        "# Step 3A Metadata Materialization Report",
        "",
        "This report covers local joins and normalization only. No network source was accessed.",
        "",
        "## Sample and join integrity",
        "",
        f"- Input final sample rows: {len(sample_games):,}",
        f"- Input unique AppIDs: {sample_games['appid'].nunique():,}",
        f"- Output games rows: {len(games):,}",
        f"- Output unique AppIDs: {games['appid'].nunique():,}",
        f"- Join coverage: {len(games):,}/{sample_games['appid'].nunique():,} (100.00%)",
        "- Final sample AppID set preserved: PASS",
        "",
        "## Monthly counts",
        "",
        "| Release month | Games |",
        "|---|---:|",
    ]
    lines.extend(f"| {month} | {count:,} |" for month, count in monthly.items())
    lines.extend(
        [
            f"| **Total** | **{int(monthly.sum()):,}** |",
            "",
            "## Free, paid, and platform counts",
            "",
            f"- Free games: {int(games['is_free'].sum()):,}",
            f"- Paid games: {int((~games['is_free'].astype(bool)).sum()):,}",
            f"- Windows-supported: {int(games['platform_windows'].sum()):,}",
            f"- macOS-supported: {int(games['platform_mac'].sum()):,}",
            f"- Linux-supported: {int(games['platform_linux'].sum()):,}",
            "",
            "## Paid-game price currency distribution",
            "",
        ]
    )
    lines.extend(f"- {currency}: {count:,}" for currency, count in currencies.items())
    lines.extend(
        [
            f"- Paid games without a Store price overview: {paid_without_overview:,}",
            "",
            "Prices are storefront snapshots at metadata_collected_at; they are not historical launch prices.",
            "Source *_cents columns remain nullable integers. Derived *_usd columns equal cents divided by 100 and remain null when cents are null.",
            "",
            "## Price missingness",
            "",
            "| Field | Missing | Expected | Unexpected |",
            "|---|---:|---:|---:|",
        ]
    )
    lines.extend(
        f"| {row.field} | {row.missing:,} | {row.expected_missing:,} | {row.unexpected_missing:,} |"
        for row in price_missing.itertuples(index=False)
    )
    lines.extend(
        [
            "",
            "## Developer and publisher missingness",
            "",
            f"- Missing developer: {int(games['developer'].isna().sum()):,}",
            f"- Missing publisher: {int(games['publisher'].isna().sum()):,} (allowed source missingness)",
            "",
            "## Genre integrity",
            "",
            f"- Games with at least one genre: {genre_games:,}",
            f"- Games without genres: {len(games) - genre_games:,}",
            f"- Total genre relation rows: {len(genres):,}",
            f"- Unique genre IDs: {unique_genre_ids:,}",
            f"- Unique genre names: {unique_genre_names:,}",
            f"- Mean genres per game (including zero-genre games): {len(genres) / len(games):.3f}",
            "",
            "## Duplicate and release-date checks",
            "",
            f"- Duplicate games AppIDs: {int(games['appid'].duplicated().sum())}",
            f"- Duplicate (appid, genre_id) keys where ID is available: {int(genres.dropna(subset=['genre_id']).duplicated(['appid', 'genre_id']).sum())}",
            f"- Release-date conflicts: {int(games['release_date_conflict'].sum())}",
            "- All release dates within the frozen study window: PASS",
            "- Release month derived from final Store release date: PASS",
            "- Frozen monthly allocation preserved: PASS",
            "",
            "## Missing-value audit",
            "",
            "| Field | Missing | Expected | Unexpected | Interpretation |",
            "|---|---:|---:|---:|---|",
        ]
    )
    lines.extend(
        f"| {row.field} | {row.missing:,} | {row.expected_missing:,} | {row.unexpected_missing:,} | {row.interpretation} |"
        for row in missing.itertuples(index=False)
    )
    lines.extend(
        [
            "",
            f"Total unexpected missing values across audited fields: {unexpected_missing:,}",
            "",
            "## Files generated",
            "",
            "- data/processed/games.csv",
            "- data/processed/game_genres.csv",
            "- reports/step3a_metadata_report.md",
            "",
            "## PASS / FAIL summary",
            "",
            "- Final sample preservation: PASS",
            "- Metadata join integrity: PASS",
            "- Price schema: PASS",
            "- Genre normalization: PASS",
            f"- Missing-value audit: {'PASS' if unexpected_missing == 0 else 'FAIL'}",
            f"- Step 3A: {'PASS' if unexpected_missing == 0 else 'FAIL'}",
            "",
        ]
    )
    return "\n".join(lines)


def run_step3a_materialization(
    *,
    sample_path: Path = SAMPLE_GAMES_PATH,
    metadata_path: Path,
    eligible_path: Path,
    games_path: Path = GAMES_PATH,
    genres_path: Path = GAME_GENRES_PATH,
    report_path: Path = STEP3A_METADATA_REPORT_PATH,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Read frozen local inputs, validate, and atomically write Step 3A outputs."""
    sample = pd.read_csv(sample_path, low_memory=False)
    metadata = pd.read_csv(metadata_path, low_memory=False)
    eligible = pd.read_csv(eligible_path, low_memory=False)
    games, genres = materialize_sample_metadata(
        sample,
        metadata,
        eligible,
        expected_size=TARGET_SAMPLE_SIZE,
        expected_month_counts=EXPECTED_MONTH_COUNTS,
    )
    if set(games["appid"]) != set(sample["appid"].astype(int)):
        raise MetadataMaterializationError("Final sample AppID set was not preserved.")
    missing = missing_value_summary(games)
    if int(missing["unexpected_missing"].sum()) != 0:
        raise MetadataMaterializationError("Unexpected missing values block Step 3A.")
    report = build_step3a_report(sample, games, genres)
    atomic_write_csv(games_path, games)
    atomic_write_csv(genres_path, genres)
    atomic_write_text(report_path, report)
    return games, genres
