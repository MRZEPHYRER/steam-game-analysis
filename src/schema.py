"""Small, dependency-free data contracts for the first project version."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from numbers import Integral


def calculate_positive_rate(positive_reviews: int, total_reviews: int) -> float | None:
    """Return the positive-review share, preserving no-review games as missing."""
    if positive_reviews < 0 or total_reviews < 0:
        raise ValueError("Review counts cannot be negative.")
    if positive_reviews > total_reviews:
        raise ValueError("positive_reviews cannot exceed total_reviews.")
    return positive_reviews / total_reviews if total_reviews > 0 else None


@dataclass(frozen=True, slots=True)
class CandidateGame:
    """A game discovered while constructing the raw sampling frame."""

    appid: int
    name: str
    release_date_raw: str | None
    release_date: date | None
    source: str
    candidate_collected_at: datetime
    search_page: int | None = None
    search_position: int | None = None
    search_rank: int | None = None


@dataclass(frozen=True, slots=True)
class GameMetadata:
    """Relatively stable store metadata for an eligible application."""

    appid: int
    name: str
    release_date_raw: str | None
    release_date: date | None
    coming_soon: bool
    developer: tuple[str, ...]
    publisher: tuple[str, ...]
    platform_windows: bool
    platform_mac: bool
    platform_linux: bool
    is_free: bool
    is_early_access: bool | None


@dataclass(frozen=True, slots=True)
class EligibilityDecision:
    """Auditable base-game inclusion decision made after metadata collection."""

    appid: int
    is_eligible: bool
    exclusion_reason: str | None
    evaluated_at: datetime

    def __post_init__(self) -> None:
        if not self.is_eligible and not self.exclusion_reason:
            raise ValueError("Ineligible applications require an exclusion_reason.")
        if self.is_eligible and self.exclusion_reason is not None:
            raise ValueError("Eligible applications cannot have an exclusion_reason.")


@dataclass(frozen=True, slots=True)
class PriceSnapshot:
    """US Steam store source-unit price fields observed at one point in time."""

    appid: int
    list_price_cents: int | None
    current_price_cents: int | None
    discount_percent: int | None
    price_currency: str | None
    collected_at: datetime

    def __post_init__(self) -> None:
        for field_name in ("list_price_cents", "current_price_cents"):
            value = getattr(self, field_name)
            if value is None:
                continue
            if isinstance(value, bool) or not isinstance(value, Integral):
                raise TypeError(f"{field_name} must be an integer or None.")
            if value < 0:
                raise ValueError(f"{field_name} cannot be negative.")
            object.__setattr__(self, field_name, int(value))

        if self.discount_percent is not None:
            if isinstance(self.discount_percent, bool) or not isinstance(
                self.discount_percent, Integral
            ):
                raise TypeError("discount_percent must be an integer or None.")
            if not 0 <= self.discount_percent <= 100:
                raise ValueError("discount_percent must be between 0 and 100.")
            object.__setattr__(self, "discount_percent", int(self.discount_percent))


@dataclass(frozen=True, slots=True)
class ReviewSnapshot:
    """Steam-purchase review summary observed at one point in time."""

    appid: int
    positive_reviews: int
    negative_reviews: int
    total_reviews: int
    review_score: int | None
    review_score_desc: str | None
    collected_at: datetime
    positive_rate: float | None = field(init=False)

    def __post_init__(self) -> None:
        if self.positive_reviews + self.negative_reviews != self.total_reviews:
            raise ValueError(
                "total_reviews must equal positive_reviews + negative_reviews."
            )
        object.__setattr__(
            self,
            "positive_rate",
            calculate_positive_rate(self.positive_reviews, self.total_reviews),
        )


@dataclass(frozen=True, slots=True)
class GameGenre:
    """One game-to-genre relationship; games may have multiple rows."""

    appid: int
    genre_id: str | None
    genre_name: str
    source: str
    collected_at: datetime


@dataclass(frozen=True, slots=True)
class GameTag:
    """Optional future game-to-tag relationship."""

    appid: int
    tag_id: int | None
    tag_name: str
    tag_rank: int | None
    source: str
    collected_at: datetime
