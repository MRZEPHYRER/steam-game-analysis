"""Hard gates and invariants for final eligibility and sampling outputs."""

from __future__ import annotations

import pandas as pd

from config.settings import END_DATE, START_DATE


class FullRunValidationError(RuntimeError):
    """A full-run completeness or uniqueness invariant failed."""


class TechnicalFailureBlock(FullRunValidationError):
    """Unresolved transport or schema failures block analytical finalization."""

    def __init__(self, request_failed: int, schema_invalid: int) -> None:
        self.request_failed = request_failed
        self.schema_invalid = schema_invalid
        super().__init__(
            "Full appdetails collection contains unresolved technical failures: "
            f"request_failed={request_failed}, schema_invalid={schema_invalid}."
        )


def _unique_appids(frame: pd.DataFrame, label: str) -> set[int]:
    if "appid" not in frame:
        raise FullRunValidationError(f"{label} is missing appid.")
    if frame["appid"].isna().any():
        raise FullRunValidationError(f"{label} contains missing AppIDs.")
    if frame["appid"].duplicated().any():
        raise FullRunValidationError(f"{label} contains duplicate AppIDs.")
    return set(frame["appid"].map(int))


def validate_metadata_finalization(
    expected_candidates: pd.DataFrame,
    metadata: pd.DataFrame,
) -> None:
    """Require exact AppID coverage and zero unresolved technical failures."""
    expected = _unique_appids(expected_candidates, "Study-window candidates")
    actual = _unique_appids(metadata, "appdetails metadata")
    if expected != actual:
        missing = len(expected.difference(actual))
        unexpected = len(actual.difference(expected))
        raise FullRunValidationError(
            "Metadata AppID coverage mismatch: "
            f"missing={missing}, unexpected={unexpected}."
        )
    if "appdetails_status" not in metadata:
        raise FullRunValidationError("appdetails metadata is missing status.")
    request_failed = int((metadata["appdetails_status"] == "request_failed").sum())
    schema_invalid = int((metadata["appdetails_status"] == "schema_invalid").sum())
    if request_failed or schema_invalid:
        raise TechnicalFailureBlock(request_failed, schema_invalid)


def validate_audit_coverage(
    expected_candidates: pd.DataFrame,
    audit: pd.DataFrame,
) -> None:
    """Require exactly one eligibility decision per study-window candidate."""
    expected = _unique_appids(expected_candidates, "Study-window candidates")
    actual = _unique_appids(audit, "Eligibility audit")
    if expected != actual:
        raise FullRunValidationError(
            "Eligibility audit does not cover every study-window candidate exactly once."
        )


def validate_eligible_frame(
    eligible: pd.DataFrame,
    *,
    start_date: str = START_DATE,
    end_date: str = END_DATE,
) -> None:
    """Require unique eligible AppIDs and exact dates inside the study window."""
    _unique_appids(eligible, "Eligible frame")
    if "release_date" not in eligible:
        raise FullRunValidationError("Eligible frame is missing release_date.")
    dates = pd.to_datetime(eligible["release_date"], errors="coerce")
    if dates.isna().any():
        raise FullRunValidationError("Eligible frame contains invalid release dates.")
    if not dates.between(pd.Timestamp(start_date), pd.Timestamp(end_date)).all():
        raise FullRunValidationError(
            "Eligible frame contains release dates outside the study window."
        )


def validate_final_sample(
    eligible: pd.DataFrame,
    sample: pd.DataFrame,
    *,
    target_size: int,
) -> None:
    """Require size, uniqueness, and subset invariants after sampling."""
    eligible_ids = _unique_appids(eligible, "Eligible frame")
    sample_ids = _unique_appids(sample, "Final sample")
    expected_size = min(target_size, len(eligible_ids))
    if len(sample) != expected_size:
        raise FullRunValidationError(
            f"Final sample size is {len(sample)}; expected {expected_size}."
        )
    if not sample_ids.issubset(eligible_ids):
        raise FullRunValidationError(
            "Final sample contains AppIDs outside the eligible frame."
        )
