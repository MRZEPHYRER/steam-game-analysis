from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from src.reviews import (
    ReviewSchemaError,
    collect_review_snapshots,
    parse_review_payload,
    review_request_params,
    select_review_preflight_sample,
)
from src.steam_client import JSONResponse, SteamClientError


COLLECTED_AT = "2026-09-14T00:00:00+00:00"


def review_payload(
    *,
    total: int = 10,
    positive: int = 8,
    negative: int = 2,
) -> dict:
    return {
        "success": 1,
        "query_summary": {
            "total_reviews": total,
            "total_positive": positive,
            "total_negative": negative,
            "review_score": 8,
            "review_score_desc": "Very Positive",
        },
        "reviews": [],
    }


def games_frame(appids: list[int]) -> pd.DataFrame:
    rows = []
    for position, appid in enumerate(appids):
        month = 7 + (position % 6)
        is_free = position % 7 == 0
        rows.append(
            {
                "appid": appid,
                "name": f"Game {appid}",
                "release_date": f"2025-{month:02d}-01",
                "release_month": f"2025-{month:02d}",
                "is_free": is_free,
                "list_price_cents": None if is_free else [299, 999, 1999][position % 3],
                "price_currency": None if is_free else "USD",
            }
        )
    return pd.DataFrame(rows)


def raw_wrapper(appid: int, payload: dict) -> dict:
    return {
        "appid": appid,
        "requested_at": COLLECTED_AT,
        "request_params": review_request_params(),
        "http_status": 200,
        "payload": payload,
        "request_retry_count": 0,
        "retryable_status_codes": [],
        "request_latency_seconds": 0.1,
    }


class FakeReviewClient:
    def __init__(self, *, failures: set[int] | None = None) -> None:
        self.failures = failures or set()
        self.calls: list[int] = []

    def get_json(self, url, *, params, collector, context) -> JSONResponse:
        del collector, context
        assert params == review_request_params()
        appid = int(str(url).rstrip("/").rsplit("/", 1)[-1])
        self.calls.append(appid)
        if appid in self.failures:
            raise SteamClientError("isolated test failure")
        return JSONResponse(
            review_payload(),
            200,
            COLLECTED_AT,
            retry_count=0,
            retryable_status_codes=(),
            elapsed_seconds=0.1,
        )


def write_raw(path: Path, raw: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(raw), encoding="utf-8")


def test_normal_review_summary_parsing() -> None:
    record = parse_review_payload(review_payload(), appid=1, collected_at=COLLECTED_AT)
    assert record["review_status"] == "success"
    assert record["total_reviews"] == 10
    assert record["positive_reviews"] == 8
    assert record["negative_reviews"] == 2


def test_positive_negative_total_identity_is_enforced() -> None:
    with pytest.raises(ReviewSchemaError, match="identity"):
        parse_review_payload(
            review_payload(total=10, positive=8, negative=1),
            appid=1,
            collected_at=COLLECTED_AT,
        )


def test_zero_review_counts_are_valid_success() -> None:
    record = parse_review_payload(
        review_payload(total=0, positive=0, negative=0),
        appid=1,
        collected_at=COLLECTED_AT,
    )
    assert record["review_status"] == "success"
    assert record["positive_reviews"] == record["negative_reviews"] == 0


def test_zero_reviews_produce_null_positive_rate() -> None:
    record = parse_review_payload(
        review_payload(total=0, positive=0, negative=0),
        appid=1,
        collected_at=COLLECTED_AT,
    )
    assert record["positive_rate"] is None


def test_normal_positive_rate_calculation() -> None:
    record = parse_review_payload(review_payload(), appid=1, collected_at=COLLECTED_AT)
    assert record["positive_rate"] == pytest.approx(0.8)


def test_request_failure_is_isolated(tmp_path: Path) -> None:
    sample = games_frame([1, 2])
    client = FakeReviewClient(failures={2})
    snapshot, stats = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        sample,
        raw_dir=tmp_path / "raw",
        output_path=tmp_path / "snapshot.csv",
        show_progress=False,
    )
    assert snapshot.set_index("appid").loc[1, "review_status"] == "success"
    assert snapshot.set_index("appid").loc[2, "review_status"] == "request_failed"
    assert stats.request_failed == 1


def test_failed_raw_is_retried(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    failed = {
        "appid": 1,
        "requested_at": COLLECTED_AT,
        "request_params": review_request_params(),
        "http_status": None,
        "request_error": "old failure",
    }
    write_raw(raw_path, failed)
    client = FakeReviewClient()
    snapshot, stats = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "snapshot.csv",
        show_progress=False,
    )
    assert client.calls == [1]
    assert snapshot.loc[0, "review_status"] == "success"
    assert stats.retried_failed_raw == 1
    assert json.loads(raw_path.read_text(encoding="utf-8"))["previous_request_failed"]


def test_successful_raw_is_reused(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    write_raw(raw_path, raw_wrapper(1, review_payload()))
    client = FakeReviewClient(failures={1})
    snapshot, stats = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "snapshot.csv",
        show_progress=False,
    )
    assert client.calls == []
    assert snapshot.loc[0, "review_status"] == "success"
    assert stats.reused == 1


def test_schema_invalid_raw_is_preserved_without_refetch(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    original = raw_wrapper(1, {"success": 1})
    write_raw(raw_path, original)
    client = FakeReviewClient(failures={1})
    snapshot, stats = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "snapshot.csv",
        show_progress=False,
    )
    assert client.calls == []
    assert snapshot.loc[0, "review_status"] == "schema_invalid"
    assert stats.schema_invalid == 1
    assert json.loads(raw_path.read_text(encoding="utf-8")) == original


def test_preflight_sample_preserves_source_appids_and_all_months() -> None:
    games = games_frame(list(range(1, 61)))
    sample = select_review_preflight_sample(games, sample_size=30)
    assert len(sample) == sample["appid"].nunique() == 30
    assert set(sample["appid"]).issubset(set(games["appid"]))
    assert set(sample["release_month"]) == {
        "2025-07",
        "2025-08",
        "2025-09",
        "2025-10",
        "2025-11",
        "2025-12",
    }


def test_duplicate_source_appid_is_blocked() -> None:
    games = games_frame([1, 2])
    games = pd.concat([games, games.iloc[[0]]], ignore_index=True)
    with pytest.raises(ValueError, match="duplicate AppID"):
        select_review_preflight_sample(games, sample_size=2)


def test_review_snapshot_timestamp_is_preserved() -> None:
    record = parse_review_payload(review_payload(), appid=1, collected_at=COLLECTED_AT)
    assert record["review_collected_at"] == COLLECTED_AT


def test_query_parameter_contract() -> None:
    assert review_request_params() == {
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
