from __future__ import annotations

import pandas as pd
import pytest

from config.settings import END_DATE, RANDOM_SEED, START_DATE
from src.sampling import (
    allocate_proportional_sample,
    canonicalize_candidates,
    proportional_stratified_sample,
)


def make_candidates(month_sizes: dict[str, int]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    appid = 1
    for month, size in month_sizes.items():
        for day_index in range(size):
            rows.append(
                {
                    "appid": appid,
                    "name": f"Game {appid}",
                    "release_date": f"{month}-{day_index % 28 + 1:02d}",
                }
            )
            appid += 1
    return pd.DataFrame(rows)


def sample_candidates(
    candidates: pd.DataFrame,
    target_size: int,
    random_seed: int = RANDOM_SEED,
) -> pd.DataFrame:
    return proportional_stratified_sample(
        candidates,
        target_size=target_size,
        random_seed=random_seed,
        start_date=START_DATE,
        end_date=END_DATE,
    )


def test_final_sample_size_equals_target() -> None:
    candidates = make_candidates({"2025-07": 70, "2025-08": 50, "2025-09": 30})
    sample = sample_candidates(candidates, target_size=90, random_seed=7)
    assert len(sample) == 90


def test_same_seed_produces_same_sample() -> None:
    candidates = make_candidates({"2025-07": 80, "2025-08": 80})
    first = sample_candidates(candidates, target_size=80, random_seed=42)
    second = sample_candidates(candidates, target_size=80, random_seed=42)
    pd.testing.assert_frame_equal(first, second)


def test_different_seeds_normally_produce_different_samples() -> None:
    candidates = make_candidates({"2025-07": 100, "2025-08": 100})
    first = sample_candidates(candidates, target_size=40, random_seed=1)
    second = sample_candidates(candidates, target_size=40, random_seed=2)
    assert set(first["appid"]) != set(second["appid"])


def test_sample_has_no_duplicate_appids() -> None:
    candidates = make_candidates({"2025-07": 100, "2025-08": 100})
    candidates = pd.concat([candidates, candidates.iloc[[0]]], ignore_index=True)
    with pytest.warns(RuntimeWarning, match="duplicate AppID"):
        sample = sample_candidates(candidates, target_size=120, random_seed=9)
    assert sample["appid"].is_unique


def test_pool_smaller_than_target_returns_full_pool() -> None:
    candidates = make_candidates({"2025-07": 3, "2025-08": 2})
    with pytest.warns(RuntimeWarning, match="smaller than target_size"):
        sample = sample_candidates(candidates, target_size=10)
    assert len(sample) == len(candidates)
    assert set(sample["appid"]) == set(candidates["appid"])


def test_imbalanced_months_keep_proportional_quota() -> None:
    candidates = make_candidates({"2025-07": 90, "2025-08": 10})
    sample = sample_candidates(candidates, target_size=20, random_seed=3)
    assert sample["release_month"].value_counts().to_dict() == {
        "2025-07": 18,
        "2025-08": 2,
    }


def test_largest_remainder_quota_sums_to_target() -> None:
    sizes = {"2025-07": 11, "2025-08": 7, "2025-09": 5}
    quota = allocate_proportional_sample(sizes, target_size=10)
    assert sum(quota.values()) == 10
    assert all(quota[month] <= size for month, size in sizes.items())


def test_invalid_release_date_is_rejected() -> None:
    candidates = pd.DataFrame(
        {"appid": [1, 2], "release_date": ["2025-07-01", "not-a-date"]}
    )
    with pytest.raises(ValueError, match=r"1 invalid or missing.*appid=2"):
        sample_candidates(candidates, target_size=1)


def test_date_before_study_window_is_rejected() -> None:
    candidates = pd.DataFrame(
        {"appid": [1, 2], "release_date": ["2025-06-30", "2025-07-01"]}
    )
    with pytest.raises(ValueError, match=r"1 value\(s\) outside study window.*appid=1"):
        sample_candidates(candidates, target_size=1)


def test_date_after_study_window_is_rejected() -> None:
    candidates = pd.DataFrame(
        {"appid": [1, 2], "release_date": ["2025-12-31", "2026-01-01"]}
    )
    with pytest.raises(ValueError, match=r"1 value\(s\) outside study window.*appid=2"):
        sample_candidates(candidates, target_size=1)


def test_boundary_dates_are_accepted() -> None:
    candidates = pd.DataFrame(
        {"appid": [1, 2], "release_date": ["2025-07-01", "2025-12-31"]}
    )
    sample = sample_candidates(candidates, target_size=2)
    assert sample["release_date"].dt.strftime("%Y-%m-%d").tolist() == [
        "2025-07-01",
        "2025-12-31",
    ]


def test_duplicate_canonicalization_is_input_order_invariant() -> None:
    candidates = pd.DataFrame(
        [
            {
                "appid": 123,
                "name": "Earlier discovery",
                "release_date": "2025-08-10",
                "source": "steam_search",
                "candidate_collected_at": "2026-01-01T00:00:00Z",
            },
            {
                "appid": 123,
                "name": "Later discovery",
                "release_date": "2025-07-10",
                "source": "steam_search",
                "candidate_collected_at": "2026-01-02T00:00:00Z",
            },
            {
                "appid": 456,
                "name": "Unique game",
                "release_date": "2025-09-01",
                "source": "steam_search",
                "candidate_collected_at": "2026-01-01T00:00:00Z",
            },
        ]
    )
    with pytest.warns(RuntimeWarning, match="conflicting records"):
        forward = canonicalize_candidates(candidates, START_DATE, END_DATE)
    with pytest.warns(RuntimeWarning, match="conflicting records"):
        reversed_result = canonicalize_candidates(
            candidates.iloc[::-1], START_DATE, END_DATE
        )
    pd.testing.assert_frame_equal(forward, reversed_result)


def test_conflicting_duplicate_keeps_deterministic_record() -> None:
    candidates = pd.DataFrame(
        [
            {
                "appid": 123,
                "name": "Later discovery",
                "release_date": "2025-07-10",
                "source": "steam_search",
                "candidate_collected_at": "2026-01-02T00:00:00Z",
            },
            {
                "appid": 123,
                "name": "Earlier discovery",
                "release_date": "2025-08-10",
                "source": "steam_search",
                "candidate_collected_at": "2026-01-01T00:00:00Z",
            },
        ]
    )
    with pytest.warns(
        RuntimeWarning,
        match=r"1 duplicate AppID group\(s\); 1 group\(s\) contained conflicting",
    ):
        result = canonicalize_candidates(candidates, START_DATE, END_DATE)
    assert result.iloc[0].to_dict() == candidates.iloc[1].to_dict()


def test_canonicalization_prefers_in_window_duplicate() -> None:
    candidates = pd.DataFrame(
        [
            {
                "appid": 123,
                "name": "Out of window",
                "release_date": "2025-06-30",
                "candidate_collected_at": "2025-12-01T00:00:00Z",
            },
            {
                "appid": 123,
                "name": "In window",
                "release_date": "2025-07-01",
                "candidate_collected_at": "2026-01-01T00:00:00Z",
            },
        ]
    )
    with pytest.warns(RuntimeWarning, match="conflicting records"):
        result = canonicalize_candidates(candidates, START_DATE, END_DATE)
    assert result.loc[0, "name"] == "In window"


def test_exact_duplicate_is_stably_merged() -> None:
    row = {
        "appid": 123,
        "name": "Exact duplicate",
        "release_date": "2025-07-10",
        "source": "steam_search",
        "candidate_collected_at": "2026-01-01T00:00:00Z",
    }
    candidates = pd.DataFrame([row, row])
    with pytest.warns(RuntimeWarning, match=r"0 group\(s\) contained conflicting"):
        result = canonicalize_candidates(candidates, START_DATE, END_DATE)
    assert len(result) == 1
    assert result.iloc[0].to_dict() == row

