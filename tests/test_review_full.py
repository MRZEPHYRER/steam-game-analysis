from __future__ import annotations

import hashlib
from pathlib import Path

import pandas as pd
import pytest

from config.settings import FROZEN_INPUT_SHA256, GAMES_PATH
from src.io_utils import atomic_write_json, read_json
from src.review_full import (
    FrozenInputError,
    ReviewCountIdentityBlock,
    ReviewFinalizationError,
    ReviewTechnicalFailureBlock,
    build_full_review_report,
    finalize_review_snapshot,
    validate_frozen_inputs_unchanged,
    validate_review_finalization,
    validate_review_source,
    verify_frozen_inputs,
)
from src.reviews import (
    ReviewCollectionStats,
    collect_review_snapshots,
    preflight_review_request_params,
    review_request_params,
)
from src.steam_client import JSONResponse, SteamClientError


COLLECTED_AT = "2026-09-14T00:00:00+00:00"


def games_frame(appids: list[int]) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "appid": appids,
            "name": [f"Game {appid}" for appid in appids],
            "release_date": ["2025-07-01"] * len(appids),
            "release_month": ["2025-07"] * len(appids),
            "is_free": [False] * len(appids),
            "list_price_cents": [999] * len(appids),
            "price_currency": ["USD"] * len(appids),
        }
    )


def payload(
    *,
    total: int = 10,
    positive: int = 8,
    negative: int = 2,
    success: int = 1,
) -> dict:
    if success == 0:
        return {"success": 0}
    return {
        "success": 1,
        "query_summary": {
            "total_reviews": total,
            "total_positive": positive,
            "total_negative": negative,
            "review_score": 8 if total else 0,
            "review_score_desc": "Very Positive" if total else "No user reviews",
        },
        "reviews": [],
    }


def raw_wrapper(appid: int, source_payload: dict) -> dict:
    return {
        "appid": appid,
        "requested_at": COLLECTED_AT,
        "request_params": review_request_params(),
        "http_status": 200,
        "payload": source_payload,
        "request_retry_count": 0,
        "retryable_status_codes": [],
        "request_latency_seconds": 0.1,
        "transport_error_count": 0,
    }


def failed_raw(appid: int) -> dict:
    return {
        "appid": appid,
        "requested_at": COLLECTED_AT,
        "request_params": review_request_params(),
        "http_status": None,
        "request_error": "sanitized timeout",
        "request_retry_count": 1,
        "retryable_status_codes": [500],
        "request_latency_seconds": None,
        "transport_error_count": 1,
    }


class FakeClient:
    def __init__(self, responses: dict[int, dict | BaseException]) -> None:
        self.responses = responses
        self.calls: list[int] = []

    def get_json(self, url, *, params, collector, context) -> JSONResponse:
        del collector, context
        assert params == review_request_params()
        appid = int(str(url).rstrip("/").rsplit("/", 1)[-1])
        self.calls.append(appid)
        result = self.responses[appid]
        if isinstance(result, BaseException):
            raise result
        return JSONResponse(
            result,
            200,
            COLLECTED_AT,
            retry_count=0,
            retryable_status_codes=(),
            elapsed_seconds=0.1,
            transport_error_count=0,
        )


def snapshot_frame(
    appids: list[int],
    *,
    statuses: list[str] | None = None,
) -> pd.DataFrame:
    statuses = statuses or ["success"] * len(appids)
    rows = []
    for appid, status in zip(appids, statuses, strict=True):
        success = status == "success"
        rows.append(
            {
                "appid": appid,
                "total_reviews": 10 if success else pd.NA,
                "positive_reviews": 8 if success else pd.NA,
                "negative_reviews": 2 if success else pd.NA,
                "positive_rate": 0.8 if success else pd.NA,
                "review_score": 8 if success else pd.NA,
                "review_score_desc": "Very Positive" if success else pd.NA,
                "review_status": status,
            }
        )
    return pd.DataFrame(rows)


def stats(total: int) -> ReviewCollectionStats:
    return ReviewCollectionStats(
        total=total,
        reused=0,
        newly_requested=total,
        retried_failed_raw=0,
        request_failed=0,
        schema_invalid=0,
        unavailable=0,
        request_retry_count=0,
        http_429_count=0,
        http_5xx_count=0,
        transport_error_count=0,
        elapsed_seconds=1.25,
    )


def test_frozen_full_source_is_exactly_3000_unique_games() -> None:
    games = pd.read_csv(GAMES_PATH, low_memory=False)
    assert len(validate_review_source(games)) == 3_000


def test_duplicate_source_appid_is_blocked() -> None:
    games = games_frame([1, 1])
    with pytest.raises(ReviewFinalizationError, match="duplicate"):
        validate_review_source(games, expected_size=2)


def test_successful_full_raw_is_reused(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    atomic_write_json(raw_path, raw_wrapper(1, payload()))
    client = FakeClient({1: AssertionError("network must not be called")})
    snapshot, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "audit.csv",
        show_progress=False,
    )
    assert client.calls == []
    assert result.reused == 1
    assert snapshot.loc[0, "review_status"] == "success"


def test_request_error_retry_success_atomically_replaces_raw(
    tmp_path: Path,
) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    atomic_write_json(raw_path, failed_raw(1))
    client = FakeClient({1: payload()})
    snapshot, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "audit.csv",
        show_progress=False,
    )
    replacement = read_json(raw_path)
    assert client.calls == [1]
    assert result.retried_failed_raw == 1
    assert "request_error" not in replacement
    assert replacement["previous_request_failed"] is True
    assert snapshot.loc[0, "review_status"] == "success"
    assert snapshot.loc[0, "day_range"] == 365


def test_request_error_retry_failure_keeps_latest_failure(
    tmp_path: Path,
) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    atomic_write_json(raw_path, failed_raw(1))
    error = SteamClientError(
        "latest sanitized failure",
        retry_count=2,
        retryable_status_codes=(429, 503),
        transport_error_count=1,
    )
    client = FakeClient({1: error})
    snapshot, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "audit.csv",
        show_progress=False,
    )
    latest = read_json(raw_path)
    assert result.retried_failed_raw == 1
    assert result.request_failed == 1
    assert latest["request_error"] == "latest sanitized failure"
    assert latest["previous_request_failed"] is True
    assert latest["request_retry_count"] == 2
    assert latest["retryable_status_codes"] == [429, 503]
    assert snapshot.loc[0, "review_status"] == "request_failed"


def test_schema_invalid_raw_is_preserved_without_refetch(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    original = raw_wrapper(1, {"success": 1})
    atomic_write_json(raw_path, original)
    client = FakeClient({1: AssertionError("network must not be called")})
    snapshot, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "audit.csv",
        show_progress=False,
    )
    assert client.calls == []
    assert result.schema_invalid == 1
    assert snapshot.loc[0, "review_status"] == "schema_invalid"
    assert read_json(raw_path) == original


def test_finalization_requires_exact_coverage_and_no_external_appids() -> None:
    source = games_frame([1, 2, 3])
    with pytest.raises(ReviewFinalizationError, match="coverage mismatch"):
        validate_review_finalization(
            source,
            snapshot_frame([1, 2, 4]),
            expected_size=3,
        )


@pytest.mark.parametrize("status", ["request_failed", "schema_invalid"])
def test_technical_failures_block_formal_snapshot(status: str) -> None:
    source = games_frame([1, 2])
    snapshot = snapshot_frame([1, 2], statuses=["success", status])
    with pytest.raises(ReviewTechnicalFailureBlock) as error:
        validate_review_finalization(source, snapshot, expected_size=2)
    assert getattr(error.value, status) == 1


def test_unknown_review_status_is_blocked() -> None:
    with pytest.raises(ReviewFinalizationError, match="invalid status"):
        validate_review_finalization(
            games_frame([1]),
            snapshot_frame([1], statuses=["mystery"]),
            expected_size=1,
        )


def test_count_identity_blocks_formal_snapshot(tmp_path: Path) -> None:
    source = games_frame([1])
    snapshot = snapshot_frame([1])
    snapshot.loc[0, "negative_reviews"] = 1
    output = tmp_path / "review_snapshots.csv"
    with pytest.raises(ReviewCountIdentityBlock, match="identity=1"):
        finalize_review_snapshot(
            source,
            snapshot,
            output_path=output,
            expected_size=1,
        )
    assert not output.exists()


def test_zero_review_and_positive_rate_semantics_are_gated(tmp_path: Path) -> None:
    source = games_frame([1, 2])
    snapshot = snapshot_frame([1, 2])
    snapshot.loc[0, [
        "total_reviews",
        "positive_reviews",
        "negative_reviews",
    ]] = [0, 0, 0]
    snapshot.loc[0, "positive_rate"] = pd.NA
    output = tmp_path / "review_snapshots.csv"
    finalize_review_snapshot(
        source,
        snapshot,
        output_path=output,
        expected_size=2,
    )
    finalized = pd.read_csv(output)
    assert pd.isna(finalized.loc[finalized["appid"] == 1, "positive_rate"]).all()

    snapshot.loc[0, "positive_rate"] = 0.0
    with pytest.raises(ReviewCountIdentityBlock, match="positive_rate=1"):
        validate_review_finalization(source, snapshot, expected_size=2)


def test_progress_processed_and_logical_counters_include_every_status(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    raw_dir = tmp_path / "raw"
    atomic_write_json(raw_dir / "review_0000000001.json", raw_wrapper(1, payload()))
    atomic_write_json(
        raw_dir / "review_0000000002.json",
        raw_wrapper(2, {"success": 1}),
    )
    atomic_write_json(
        raw_dir / "review_0000000003.json",
        raw_wrapper(3, payload(success=0)),
    )
    atomic_write_json(raw_dir / "review_0000000005.json", failed_raw(5))

    updates: list[tuple[int, dict[str, int]]] = []

    class RecordingProgress:
        def __init__(self, total, **_kwargs) -> None:
            assert total == 5

        def __enter__(self):
            return self

        def update(self, processed: int, **counters: int) -> None:
            updates.append((processed, counters))

        def __exit__(self, *_args) -> None:
            return None

    monkeypatch.setattr("src.reviews.ConsoleProgress", RecordingProgress)
    client = FakeClient({4: payload(total=0, positive=0, negative=0), 5: payload()})
    snapshot, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1, 2, 3, 4, 5]),
        raw_dir=raw_dir,
        output_path=tmp_path / "audit.csv",
    )
    assert len(snapshot) == result.total == updates[-1][0] == 5
    assert result.reused == 2
    assert result.newly_requested == 1
    assert result.retried_failed_raw == 1
    assert updates[-1][1] == {
        "reused": 2,
        "new": 1,
        "retried": 1,
        "failed": 0,
    }
    assert result.schema_invalid == 1
    assert result.unavailable == 1


def test_ctrl_c_preserves_completed_raw_and_skips_audit(tmp_path: Path) -> None:
    client = FakeClient({1: payload(), 2: KeyboardInterrupt()})
    raw_dir = tmp_path / "raw"
    audit_path = tmp_path / "audit.csv"
    with pytest.raises(KeyboardInterrupt):
        collect_review_snapshots(
            client,  # type: ignore[arg-type]
            games_frame([1, 2]),
            raw_dir=raw_dir,
            output_path=audit_path,
            show_progress=False,
        )
    assert (raw_dir / "review_0000000001.json").is_file()
    assert not (raw_dir / "review_0000000002.json").exists()
    assert not audit_path.exists()


def test_retry_telemetry_is_aggregated_from_raw(tmp_path: Path) -> None:
    raw = raw_wrapper(1, payload())
    raw["request_retry_count"] = 4
    raw["retryable_status_codes"] = [429, 500, 503]
    raw["transport_error_count"] = 1
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    atomic_write_json(raw_path, raw)
    client = FakeClient({1: AssertionError("network must not be called")})
    _, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "audit.csv",
        show_progress=False,
    )
    assert result.request_retry_count == 4
    assert result.http_429_count == 1
    assert result.http_5xx_count == 2
    assert result.transport_error_count == 1


def test_full_raw_with_historical_contract_is_preserved_and_blocked(
    tmp_path: Path,
) -> None:
    raw_path = tmp_path / "raw" / "review_0000000001.json"
    historical = raw_wrapper(1, payload())
    historical["request_params"] = preflight_review_request_params()
    atomic_write_json(raw_path, historical)
    client = FakeClient({1: AssertionError("schema-invalid Raw must not refetch")})
    snapshot, result = collect_review_snapshots(
        client,  # type: ignore[arg-type]
        games_frame([1]),
        raw_dir=raw_path.parent,
        output_path=tmp_path / "audit.csv",
        show_progress=False,
        required_request_params=review_request_params(),
    )
    assert client.calls == []
    assert result.reused == 0
    assert result.schema_invalid == 1
    assert snapshot.loc[0, "review_status"] == "schema_invalid"
    assert read_json(raw_path) == historical


def test_frozen_input_hashes_are_verified_and_compared(tmp_path: Path) -> None:
    frozen = tmp_path / "frozen.csv"
    frozen.write_bytes(b"appid\n1\n")
    expected = hashlib.sha256(frozen.read_bytes()).hexdigest().upper()
    before = verify_frozen_inputs({frozen: expected})
    after = verify_frozen_inputs({frozen: expected})
    validate_frozen_inputs_unchanged(before, after)

    frozen.write_bytes(b"appid\n2\n")
    with pytest.raises(FrozenInputError, match="changed"):
        verify_frozen_inputs({frozen: expected})


def test_project_frozen_inputs_match_baseline_hashes() -> None:
    assert verify_frozen_inputs(FROZEN_INPUT_SHA256) == {
        path: expected for path, expected in FROZEN_INPUT_SHA256.items()
    }


def test_full_report_contains_required_technical_summaries(
    tmp_path: Path,
) -> None:
    source = games_frame([1, 2])
    snapshot = snapshot_frame([1, 2])
    snapshot.loc[1, [
        "total_reviews",
        "positive_reviews",
        "negative_reviews",
    ]] = [0, 0, 0]
    snapshot.loc[1, "positive_rate"] = pd.NA
    frozen = {tmp_path / "games.csv": "ABC"}
    report = build_full_review_report(
        source=source,
        snapshot=snapshot,
        stats=stats(2),
        raw_dir=tmp_path / "raw",
        frozen_before=frozen,
        frozen_after=frozen,
        finalized=True,
    )
    for required in [
        "## Coverage",
        "## Technical status",
        "## Review-count distribution",
        "## Model-threshold counts",
        "## Positive rate",
        "## Review score frequency",
        "## Integrity",
        "## Collection telemetry",
        "Count-identity failures: 0",
        "Technical finalization gate: PASS",
    ]:
        assert required in report
