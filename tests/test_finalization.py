from __future__ import annotations

import pandas as pd
import pytest

from src.finalization import (
    FullRunValidationError,
    TechnicalFailureBlock,
    validate_audit_coverage,
    validate_eligible_frame,
    validate_final_sample,
    validate_metadata_finalization,
)


def frame(appids: list[int], **columns) -> pd.DataFrame:
    values = {"appid": appids}
    values.update(columns)
    return pd.DataFrame(values)


@pytest.mark.parametrize("status", ["request_failed", "schema_invalid"])
def test_technical_failures_block_finalization(status: str) -> None:
    expected = frame([1, 2])
    metadata = frame([1, 2], appdetails_status=["success", status])
    with pytest.raises(TechnicalFailureBlock) as error:
        validate_metadata_finalization(expected, metadata)
    assert getattr(error.value, status) == 1


def test_unsuccessful_is_not_a_technical_failure() -> None:
    validate_metadata_finalization(
        frame([1, 2]),
        frame([1, 2], appdetails_status=["success", "unsuccessful"]),
    )


def test_metadata_and_audit_require_exact_unique_coverage() -> None:
    with pytest.raises(FullRunValidationError, match="duplicate"):
        validate_metadata_finalization(
            frame([1, 2]),
            frame([1, 1], appdetails_status=["success", "success"]),
        )
    with pytest.raises(FullRunValidationError, match="cover"):
        validate_audit_coverage(frame([1, 2]), frame([1]))


def test_eligible_and_sample_invariants_pass_with_small_pool_fallback() -> None:
    eligible = frame(
        [1, 2],
        release_date=["2025-07-01", "2025-12-31"],
    )
    sample = eligible.copy()
    validate_eligible_frame(eligible)
    validate_final_sample(eligible, sample, target_size=3_000)


def test_eligible_dates_and_sample_subset_are_enforced() -> None:
    with pytest.raises(FullRunValidationError, match="outside"):
        validate_eligible_frame(
            frame([1], release_date=["2026-01-01"])
        )
    eligible = frame([1, 2], release_date=["2025-07-01", "2025-08-01"])
    with pytest.raises(FullRunValidationError, match="outside the eligible"):
        validate_final_sample(eligible, frame([1, 3]), target_size=2)
