"""Markdown quality reporting for Step 2 candidate-frame construction."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.io_utils import atomic_write_text


STUDY_MONTHS = [f"2025-{month:02d}" for month in range(7, 13)]


def _count(frame: pd.DataFrame | None) -> int | None:
    return None if frame is None else len(frame)


def _display(value: int | None) -> str:
    return "Not run" if value is None else f"{value:,}"


def build_step2_report(
    path: Path,
    *,
    discovered: pd.DataFrame,
    canonical: pd.DataFrame,
    candidate_match: pd.DataFrame | None = None,
    metadata: pd.DataFrame | None = None,
    eligible: pd.DataFrame | None = None,
    audit: pd.DataFrame | None = None,
    sample: pd.DataFrame | None = None,
    discovery_completed: bool,
    api_key_detected: bool,
) -> str:
    """Build and atomically persist the current Step 2 quality report."""
    parseable = int(discovered["release_date"].notna().sum())
    unparseable = len(discovered) - parseable
    matches = (
        int(candidate_match["in_official_game_catalog"].sum())
        if candidate_match is not None
        else None
    )
    nonmatches = (
        len(candidate_match) - int(candidate_match["in_official_game_catalog"].sum())
        if candidate_match is not None
        else None
    )
    metadata_successes = (
        int((metadata["appdetails_status"] == "success").sum())
        if metadata is not None
        else None
    )
    metadata_failures = (
        len(metadata) - int((metadata["appdetails_status"] == "success").sum())
        if metadata is not None
        else None
    )

    discovered_dates = pd.to_datetime(discovered["release_date"], errors="coerce")
    discovered_months = discovered_dates.dt.to_period("M").astype("string")
    eligible_months = (
        pd.to_datetime(eligible["release_date"], errors="coerce")
        .dt.to_period("M")
        .astype("string")
        if eligible is not None and not eligible.empty
        else pd.Series(dtype="string")
    )
    sampled_months = (
        sample["release_month"].astype("string")
        if sample is not None and not sample.empty
        else pd.Series(dtype="string")
    )

    lines = [
        "# Step 2 Candidate Frame Report",
        "",
        "This report describes the current state of candidate-frame construction. "
        "Values marked `Not run` depend on a completed upstream stage.",
        "",
        "## Pipeline Status",
        "",
        f"- Steam Search discovery completed: {'YES' if discovery_completed else 'NO'}",
        f"- Steam API key detected: {'YES' if api_key_detected else 'NO'}",
        "",
        "## Quality Counts",
        "",
        "| Metric | Count |",
        "|---|---:|",
        f"| Steam Search total discovered | {len(discovered):,} |",
        f"| Unique AppIDs after canonicalization | {len(canonical):,} |",
        f"| Parseable release dates | {parseable:,} |",
        f"| Unparseable release dates | {unparseable:,} |",
        f"| Official catalog matches | {_display(matches)} |",
        f"| Catalog non-matches | {_display(nonmatches)} |",
        f"| appdetails successes | {_display(metadata_successes)} |",
        f"| appdetails failures | {_display(metadata_failures)} |",
        f"| Eligible games | {_display(_count(eligible))} |",
        f"| Excluded games | {_display(_count(audit) - _count(eligible) if audit is not None and eligible is not None else None)} |",
        f"| Final sample size | {_display(_count(sample))} |",
        "",
        "## Monthly Distribution",
        "",
        "| Month | Discovered | Eligible | Sampled | Sampling fraction |",
        "|---|---:|---:|---:|---:|",
    ]
    for month in STUDY_MONTHS:
        discovered_count = int((discovered_months == month).sum())
        eligible_count = (
            int((eligible_months == month).sum()) if eligible is not None else None
        )
        sampled_count = (
            int((sampled_months == month).sum()) if sample is not None else None
        )
        fraction = (
            f"{sampled_count / eligible_count:.2%}"
            if sampled_count is not None and eligible_count
            else "Not run"
        )
        lines.append(
            f"| {month} | {discovered_count:,} | {_display(eligible_count)} | "
            f"{_display(sampled_count)} | {fraction} |"
        )

    lines.extend(["", "## Exclusion Summary", ""])
    if audit is None:
        lines.append("Not run.")
    else:
        excluded = audit.loc[~audit["is_eligible"]]
        if excluded.empty:
            lines.append("No exclusions recorded.")
        else:
            counts = excluded["exclusion_reason"].value_counts(dropna=False)
            total = len(excluded)
            lines.extend(
                [
                    "| Exclusion reason | Count | Percentage |",
                    "|---|---:|---:|",
                ]
            )
            for reason, count in counts.items():
                lines.append(
                    f"| {reason} | {count:,} | {count / total:.2%} |"
                )

    report = "\n".join(lines) + "\n"
    atomic_write_text(path, report)
    return report

