"""Deterministic appdetails preflight selection and audit reporting."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pandas as pd

from config.settings import END_DATE, RANDOM_SEED, START_DATE
from src.io_utils import atomic_write_text
from src.sampling import proportional_stratified_sample


PREFLIGHT_SAMPLE_COLUMNS = [
    "appid",
    "name",
    "search_release_date",
    "release_month",
    "search_rank",
    "candidate_collected_at",
    "in_official_game_catalog",
]
GENRE_RELATION_COLUMNS = ["appid", "genre_id", "genre_name"]


def build_study_window_population(candidate_match: pd.DataFrame) -> pd.DataFrame:
    """Return catalog-matched candidates with exact Search dates in the window."""
    required = {"appid", "name", "release_date", "in_official_game_catalog"}
    missing = required.difference(candidate_match.columns)
    if missing:
        raise ValueError(f"Candidate catalog match is missing: {sorted(missing)}")

    dates = pd.to_datetime(candidate_match["release_date"], errors="coerce")
    catalog_values = candidate_match["in_official_game_catalog"]
    if pd.api.types.is_bool_dtype(catalog_values.dtype):
        in_catalog = catalog_values.fillna(False)
    else:
        in_catalog = catalog_values.astype("string").str.casefold().eq("true")
    mask = in_catalog & dates.between(pd.Timestamp(START_DATE), pd.Timestamp(END_DATE))
    population = candidate_match.loc[mask].copy()
    population["release_date"] = dates.loc[mask].dt.strftime("%Y-%m-%d")
    return population.sort_values("appid", kind="stable").reset_index(drop=True)


def select_preflight_sample(
    population: pd.DataFrame,
    *,
    sample_size: int = 20,
) -> pd.DataFrame:
    """Select a reproducible, month-stratified appdetails preflight sample."""
    sampled = proportional_stratified_sample(
        population,
        target_size=sample_size,
        random_seed=RANDOM_SEED,
        start_date=START_DATE,
        end_date=END_DATE,
    )
    sampled["search_release_date"] = sampled["release_date"].dt.strftime(
        "%Y-%m-%d"
    )
    for column in PREFLIGHT_SAMPLE_COLUMNS:
        if column not in sampled:
            sampled[column] = None
    return sampled[PREFLIGHT_SAMPLE_COLUMNS].reset_index(drop=True)


def preflight_sample_as_candidates(sample: pd.DataFrame) -> pd.DataFrame:
    """Restore the candidate field name expected by the eligibility evaluator."""
    candidates = sample.copy()
    candidates["release_date"] = candidates["search_release_date"]
    return candidates


def build_genre_relations(metadata: pd.DataFrame) -> pd.DataFrame:
    """Normalize every returned genre into one AppID/genre relation row."""
    records: list[dict[str, Any]] = []
    for row in metadata.to_dict(orient="records"):
        raw_genres = row.get("genres")
        if not isinstance(raw_genres, str) or not raw_genres:
            continue
        genres = json.loads(raw_genres)
        for genre in genres:
            records.append(
                {
                    "appid": int(row["appid"]),
                    "genre_id": genre.get("id"),
                    "genre_name": genre.get("description"),
                }
            )
    return pd.DataFrame(records, columns=GENRE_RELATION_COLUMNS)


def _value_counts_lines(series: pd.Series, empty_message: str) -> list[str]:
    counts = series.value_counts(dropna=False)
    if counts.empty:
        return [empty_message]
    return [f"- `{value}`: {count}" for value, count in counts.items()]


def build_preflight_report(
    path: Path,
    *,
    source_population: pd.DataFrame,
    sample: pd.DataFrame,
    metadata: pd.DataFrame,
    audit: pd.DataFrame,
    genre_relations: pd.DataFrame,
) -> str:
    """Write the Step 2C preflight validation report."""
    statuses = metadata["appdetails_status"].fillna("missing")
    successes = metadata.loc[statuses == "success"]
    failures = metadata.loc[statuses != "success"]
    eligible_count = int(audit["is_eligible"].sum())
    date_counts = audit["release_date_status"].value_counts()
    free_count = int((successes["is_free"] == True).sum())  # noqa: E712
    paid_count = int((successes["is_free"] == False).sum())  # noqa: E712
    paid_prices = successes.loc[successes["is_free"] == False]  # noqa: E712
    currencies = paid_prices["price_currency"].dropna().astype(str)
    unexpected_currencies = sorted(set(currencies).difference({"USD"}))
    cents_valid = all(
        pd.api.types.is_integer_dtype(metadata[column].dtype)
        for column in ("list_price_cents", "current_price_cents")
    )
    genre_games = int(genre_relations["appid"].nunique())
    mean_genres = (
        len(genre_relations) / genre_games if genre_games else 0.0
    )
    developer_missing = int(
        (~metadata["developers_present"].fillna(False).astype(bool)).sum()
    )
    publisher_missing = int(
        (~metadata["publishers_present"].fillna(False).astype(bool)).sum()
    )
    schema_invalid = int((statuses == "schema_invalid").sum())
    identity_errors = int(
        metadata["schema_error"]
        .fillna("")
        .str.contains("different steam_appid", regex=False)
        .sum()
    )
    month_counts = sample["release_month"].value_counts().sort_index()
    exclusions = audit.loc[~audit["is_eligible"], "exclusion_reason"]

    problems: list[str] = []
    if len(failures):
        problems.append(f"{len(failures)} appdetails response(s) were not successful.")
    if schema_invalid:
        problems.append(f"{schema_invalid} response(s) failed schema validation.")
    if unexpected_currencies:
        problems.append(f"Unexpected currencies: {unexpected_currencies}.")
    if int(date_counts.get("different_date", 0)):
        problems.append(
            f"{int(date_counts.get('different_date', 0))} Search/Store date conflict(s)."
        )
    problems.append(
        "Early Access reliable classification unavailable from current source."
    )

    lines = [
        "# Step 2C appdetails Preflight Report",
        "",
        "## Population and sample",
        "",
        f"- Source study-window population: {len(source_population):,}",
        f"- Preflight sample size: {len(sample)}",
        f"- Random seed: {RANDOM_SEED}",
        "",
        "### Monthly preflight distribution",
        "",
        "| Month | Count |",
        "|---|---:|",
    ]
    lines.extend(f"| {month} | {count} |" for month, count in month_counts.items())
    lines.extend(
        [
            "",
            "## Response and eligibility validation",
            "",
            f"- Successful appdetails responses: {len(successes)}",
            f"- Failed appdetails responses: {len(failures)}",
            f"- AppID identity errors: {identity_errors}",
            f"- Eligible: {eligible_count}",
            f"- Ineligible: {len(audit) - eligible_count}",
            "",
            "### App type distribution",
            "",
            *_value_counts_lines(successes["app_type"], "No successful responses."),
            "",
            "### Exclusion reasons",
            "",
            *_value_counts_lines(exclusions, "No exclusions."),
            "",
            "## Release-date reconciliation",
            "",
            f"- Exact matches: {int(date_counts.get('exact_match', 0))}",
            f"- Different dates: {int(date_counts.get('different_date', 0))}",
            f"- Store unparseable: {int(date_counts.get('store_unparseable', 0))}",
            f"- Store missing: {int(date_counts.get('store_missing', 0))}",
            "",
            "## Price validation",
            "",
            f"- Free games: {free_count}",
            f"- Paid games: {paid_count}",
            f"- Returned paid-game currencies: {sorted(set(currencies)) or 'None'}",
            f"- Unexpected currencies: {unexpected_currencies or 'None'}",
            f"- Integer cents validation: {'PASS' if cents_valid else 'FAIL'}",
            "",
            "## Multi-value and platform fields",
            "",
            f"- Games with genres: {genre_games}",
            f"- Games without genres: {len(metadata) - genre_games}",
            f"- Total genre relation rows: {len(genre_relations)}",
            f"- Mean genres per game with genres: {mean_genres:.2f}",
            f"- Windows supported: {int((successes['platform_windows'] == True).sum())}",  # noqa: E501,E712
            f"- macOS supported: {int((successes['platform_mac'] == True).sum())}",  # noqa: E501,E712
            f"- Linux supported: {int((successes['platform_linux'] == True).sum())}",  # noqa: E501,E712
            f"- Missing developer fields: {developer_missing}",
            f"- Missing publisher fields: {publisher_missing}",
            "",
            "## Early Access",
            "",
            "- True: 0",
            "- False: 0",
            f"- Unknown: {len(metadata)}",
            "- Early Access reliable classification unavailable from current source.",
            "",
            "## Schema and problems",
            "",
            f"- Schema-invalid responses: {schema_invalid}",
            f"- Schema drift status: {'DETECTED' if schema_invalid else 'NONE'}",
            "",
            "### Problems discovered",
            "",
            *[f"- {problem}" for problem in problems],
            "",
            "## Recommendation",
            "",
            "Do not expand automatically. Review this preflight, then authorize the "
            "full 10,115-AppID collection only if the observed schema and quality "
            "results are acceptable.",
        ]
    )
    report = "\n".join(lines) + "\n"
    atomic_write_text(path, report)
    return report
