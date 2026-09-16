from __future__ import annotations

from datetime import datetime, timezone

import pytest

from src.schema import (
    EligibilityDecision,
    PriceSnapshot,
    ReviewSnapshot,
    calculate_positive_rate,
)


def test_positive_rate_is_none_for_zero_reviews() -> None:
    assert calculate_positive_rate(0, 0) is None


def test_positive_rate_is_calculated_from_counts() -> None:
    snapshot = ReviewSnapshot(
        appid=1,
        positive_reviews=17,
        negative_reviews=3,
        total_reviews=20,
        review_score=8,
        review_score_desc="Very Positive",
        collected_at=datetime.now(timezone.utc),
    )
    assert snapshot.positive_rate == pytest.approx(0.85)


def test_review_snapshot_rejects_inconsistent_total() -> None:
    with pytest.raises(ValueError, match="must equal"):
        ReviewSnapshot(
            appid=1,
            positive_reviews=10,
            negative_reviews=5,
            total_reviews=20,
            review_score=None,
            review_score_desc=None,
            collected_at=datetime.now(timezone.utc),
        )


def test_positive_rate_rejects_invalid_counts() -> None:
    with pytest.raises(ValueError):
        calculate_positive_rate(2, 1)


def test_ineligible_application_requires_reason() -> None:
    with pytest.raises(ValueError, match="require an exclusion_reason"):
        EligibilityDecision(
            appid=1,
            is_eligible=False,
            exclusion_reason=None,
            evaluated_at=datetime.now(timezone.utc),
        )


def test_eligible_application_has_no_exclusion_reason() -> None:
    decision = EligibilityDecision(
        appid=1,
        is_eligible=True,
        exclusion_reason=None,
        evaluated_at=datetime.now(timezone.utc),
    )
    assert decision.exclusion_reason is None


@pytest.mark.parametrize("price_cents", [1999, 999, 0, None])
def test_price_snapshot_accepts_integer_source_units(
    price_cents: int | None,
) -> None:
    snapshot = PriceSnapshot(
        appid=1,
        list_price_cents=price_cents,
        current_price_cents=price_cents,
        discount_percent=0 if price_cents is not None else None,
        price_currency="USD" if price_cents is not None else None,
        collected_at=datetime.now(timezone.utc),
    )
    assert snapshot.list_price_cents == price_cents
    assert snapshot.current_price_cents == price_cents


def test_zero_price_does_not_infer_free_status() -> None:
    snapshot = PriceSnapshot(
        appid=1,
        list_price_cents=0,
        current_price_cents=0,
        discount_percent=0,
        price_currency="USD",
        collected_at=datetime.now(timezone.utc),
    )
    assert not hasattr(snapshot, "is_free")


def test_price_snapshot_rejects_string_price() -> None:
    with pytest.raises(TypeError, match="must be an integer or None"):
        PriceSnapshot(
            appid=1,
            list_price_cents="19.99",  # type: ignore[arg-type]
            current_price_cents=1999,
            discount_percent=0,
            price_currency="USD",
            collected_at=datetime.now(timezone.utc),
        )
