from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from src.review_contract import compare_review_raw, select_query_contract_sample
from src.reviews import (
    documented_review_request_params,
    preflight_review_request_params,
)


COLLECTED_AT = "2026-09-14T00:00:00+00:00"


def _inputs() -> tuple[pd.DataFrame, pd.DataFrame]:
    totals = (
        [0] * 9
        + list(range(1, 10))
        + [15]
        + [25, 40]
        + [50, 60, 70, 80, 90, 100, 110, 120, 130]
    )
    appids = list(range(1, 31))
    sample = pd.DataFrame(
        {
            "appid": appids,
            "name": [f"Game {value}" for value in appids],
            "is_free": [value <= 9 or value == 30 for value in appids],
        }
    )
    snapshot = pd.DataFrame(
        {
            "appid": appids,
            "total_reviews": totals,
            "review_status": ["success"] * 30,
        }
    )
    return sample, snapshot


def _raw(appid: int, params: dict, *, total: int = 0) -> dict:
    return {
        "appid": appid,
        "requested_at": COLLECTED_AT,
        "request_params": params,
        "http_status": 200,
        "payload": {
            "success": 1,
            "query_summary": {
                "total_positive": total,
                "total_negative": 0,
                "total_reviews": total,
                "review_score": 0,
                "review_score_desc": "No user reviews" if total == 0 else "Positive",
            },
            "reviews": [],
        },
        "request_retry_count": 0,
        "retryable_status_codes": [],
        "request_latency_seconds": 0.1,
    }


def test_contract_sample_is_deterministic_and_covers_required_groups() -> None:
    sample, snapshot = _inputs()
    first = select_query_contract_sample(sample, snapshot)
    second = select_query_contract_sample(sample, snapshot)
    pd.testing.assert_frame_equal(first, second)
    assert len(first) == first["appid"].nunique() == 10
    assert first["review_count_bin"].value_counts().to_dict() == {
        "50+": 3,
        "zero": 2,
        "1-9": 2,
        "20-49": 2,
        "10-19": 1,
    }
    assert first["is_free"].any()
    assert (~first["is_free"]).any()


def test_documented_candidate_contract_is_complete() -> None:
    assert documented_review_request_params() == {
        "json": 1,
        "filter": "all",
        "cursor": "*",
        "num_per_page": 1,
        "language": "all",
        "purchase_type": "steam",
        "review_type": "all",
        "filter_offtopic_activity": 1,
        "day_range": 365,
    }


def test_historical_preflight_contract_remains_supported() -> None:
    assert preflight_review_request_params() == {
        "json": 1,
        "language": "all",
        "purchase_type": "steam",
        "review_type": "all",
        "filter": "summary",
        "filter_offtopic_activity": 1,
        "num_per_page": 0,
    }


def test_comparison_checks_all_summary_fields_and_zero_semantics(
    tmp_path: Path,
) -> None:
    current_path = tmp_path / "current.json"
    candidate_path = tmp_path / "candidate.json"
    current_path.write_text(
        json.dumps(_raw(1, preflight_review_request_params())), encoding="utf-8"
    )
    candidate_path.write_text(
        json.dumps(_raw(1, documented_review_request_params())), encoding="utf-8"
    )
    row = compare_review_raw(
        appid=1,
        name="Game",
        is_free=True,
        review_bin="zero",
        current_path=current_path,
        candidate_path=candidate_path,
    )
    assert row["query_summary_match"] is True
    assert row["candidate_count_identity"] is True
    assert row["candidate_zero_review_semantics"] is True
    for field in [
        "total_positive",
        "total_negative",
        "total_reviews",
        "review_score",
        "review_score_desc",
    ]:
        assert row[f"match_{field}"] is True
