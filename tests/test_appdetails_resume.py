from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.eligibility import collect_candidate_appdetails
from src.io_utils import atomic_write_json, read_json
from src.steam_client import JSONResponse, SteamClientError


def candidates(appid: int = 1) -> pd.DataFrame:
    return pd.DataFrame(
        {"appid": [appid], "in_official_game_catalog": [True]}
    )


def payload(appid: int, *, returned_appid: int | None = None) -> dict:
    return {
        str(appid): {
            "success": True,
            "data": {
                "steam_appid": appid if returned_appid is None else returned_appid,
                "type": "game",
                "name": "Game",
                "is_free": False,
                "release_date": {"coming_soon": False, "date": "1 July, 2025"},
                "platforms": {"windows": True, "mac": False, "linux": False},
            },
        }
    }


def completed_raw(appid: int, source_payload: dict) -> dict:
    return {
        "requested_at": "2026-09-12T00:00:00+00:00",
        "request_params": {"appids": appid, "cc": "us", "l": "english"},
        "http_status": 200,
        "appid": appid,
        "payload": source_payload,
    }


def failed_raw(appid: int) -> dict:
    return {
        "requested_at": "2026-09-12T00:00:00+00:00",
        "request_params": {"appids": appid, "cc": "us", "l": "english"},
        "http_status": None,
        "appid": appid,
        "request_error": "sanitized timeout",
    }


class FakeClient:
    def __init__(self, result: dict | Exception) -> None:
        self.result = result
        self.calls = 0

    def get_json(self, _url, *, params, collector, context) -> JSONResponse:
        del collector, context
        self.calls += 1
        if isinstance(self.result, Exception):
            raise self.result
        return JSONResponse(
            self.result,
            200,
            "2026-09-12T01:00:00+00:00",
        )


def collect_one(tmp_path: Path, client: FakeClient) -> tuple[pd.DataFrame, Path]:
    raw_dir = tmp_path / "raw"
    metadata, _ = collect_candidate_appdetails(
        client,  # type: ignore[arg-type]
        candidates(),
        raw_dir=raw_dir,
        output_path=tmp_path / "metadata.csv",
        show_progress=False,
    )
    return metadata, raw_dir / "appdetails_0000000001.json"


def test_successful_existing_raw_is_reused(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "appdetails_0000000001.json"
    atomic_write_json(raw_path, completed_raw(1, payload(1)))
    client = FakeClient(AssertionError("network must not be called"))
    metadata, _ = collect_one(tmp_path, client)
    assert client.calls == 0
    assert metadata.loc[0, "appdetails_status"] == "success"


def test_existing_request_error_is_retried_and_success_replaces_raw(
    tmp_path: Path,
) -> None:
    raw_path = tmp_path / "raw" / "appdetails_0000000001.json"
    atomic_write_json(raw_path, failed_raw(1))
    client = FakeClient(payload(1))
    metadata, raw_path = collect_one(tmp_path, client)
    replacement = read_json(raw_path)
    assert client.calls == 1
    assert metadata.loc[0, "appdetails_status"] == "success"
    assert "request_error" not in replacement
    assert replacement["previous_request_failed"] is True


def test_retry_failure_remains_auditable(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "appdetails_0000000001.json"
    atomic_write_json(raw_path, failed_raw(1))
    client = FakeClient(SteamClientError("still unavailable"))
    metadata, raw_path = collect_one(tmp_path, client)
    replacement = read_json(raw_path)
    assert client.calls == 1
    assert metadata.loc[0, "appdetails_status"] == "request_failed"
    assert replacement["request_error"] == "still unavailable"
    assert replacement["previous_request_failed"] is True


def test_schema_invalid_raw_is_not_refetched(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "appdetails_0000000001.json"
    atomic_write_json(raw_path, completed_raw(1, payload(1, returned_appid=2)))
    client = FakeClient(AssertionError("network must not be called"))
    metadata, _ = collect_one(tmp_path, client)
    assert client.calls == 0
    assert metadata.loc[0, "appdetails_status"] == "schema_invalid"


def test_success_false_is_reused_as_source_outcome(tmp_path: Path) -> None:
    raw_path = tmp_path / "raw" / "appdetails_0000000001.json"
    atomic_write_json(raw_path, completed_raw(1, {"1": {"success": False}}))
    client = FakeClient(AssertionError("network must not be called"))
    metadata, _ = collect_one(tmp_path, client)
    assert client.calls == 0
    assert metadata.loc[0, "appdetails_status"] == "unsuccessful"
