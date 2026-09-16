from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from src.io_utils import read_json
from src.search_collector import (
    SchemaDriftError,
    collect_search_candidates,
    parse_search_results,
    update_old_page_streak,
    validate_search_payload,
)
from src.steam_client import JSONResponse


def search_html(appid: int, name: str, release_date: str | None) -> str:
    release = (
        f'<div class="search_released responsive_secondrow">{release_date}</div>'
        if release_date is not None
        else '<div class="search_released responsive_secondrow"></div>'
    )
    return (
        f'<a class="search_result_row" data-ds-appid="{appid}">'
        f'<span class="title">{name}</span>{release}</a>'
    )


def parse(html: str) -> list[dict[str, object]]:
    return parse_search_results(
        html,
        requested_at="2026-09-12T00:00:00+00:00",
        start=50,
        page_size=50,
        search_page=2,
    )


def test_search_parser_extracts_appid_name_date_and_provenance() -> None:
    records = parse(search_html(123, "A &amp; B", "Sep 7, 2025"))
    assert records == [
        {
            "appid": 123,
            "name": "A & B",
            "release_date_raw": "Sep 7, 2025",
            "release_date": "2025-09-07",
            "source": "steam_search",
            "candidate_collected_at": "2026-09-12T00:00:00+00:00",
            "search_page": 2,
            "search_position": 1,
            "search_rank": 51,
        }
    ]


@pytest.mark.parametrize("raw_date", [None, "Coming Soon", "Sep 2025", "2025"])
def test_search_parser_preserves_ambiguous_or_missing_date(
    raw_date: str | None,
) -> None:
    record = parse(search_html(123, "Game", raw_date))[0]
    assert record["release_date_raw"] == raw_date
    assert record["release_date"] is None


def test_search_parser_handles_malformed_html_without_inventing_appid() -> None:
    assert parse('<a data-ds-appid="not-an-id"><span class="title">Broken') == []


def test_search_parser_preserves_duplicate_appids_for_canonicalization() -> None:
    records = parse(
        search_html(123, "First", "Jul 1, 2025")
        + search_html(123, "Second", "Jul 2, 2025")
    )
    assert [record["appid"] for record in records] == [123, 123]


def test_search_schema_drift_missing_key_stops() -> None:
    with pytest.raises(SchemaDriftError, match="Schema Drift Suspected"):
        validate_search_payload(
            {"success": 1, "results_html": "", "total_count": 0}
        )


def test_stop_rule_continues_for_in_window_page() -> None:
    records = [{"release_date": "2025-08-01"}]
    assert update_old_page_streak(
        records, start_date="2025-07-01", current_streak=2, threshold=3
    ) == (0, False)


def test_stop_rule_continues_after_one_old_page() -> None:
    records = [{"release_date": "2025-06-30"}]
    assert update_old_page_streak(
        records, start_date="2025-07-01", current_streak=0, threshold=3
    ) == (1, False)


def test_stop_rule_stops_at_consecutive_old_page_threshold() -> None:
    records = [{"release_date": "2025-06-30"}, {"release_date": None}]
    assert update_old_page_streak(
        records, start_date="2025-07-01", current_streak=2, threshold=3
    ) == (3, True)


class FakeSearchClient:
    def __init__(self, dates: list[str]) -> None:
        self.dates = dates
        self.starts: list[int] = []

    def get_json(self, _url, *, params, collector, context) -> JSONResponse:
        del collector, context
        self.starts.append(params["start"])
        raw_date = self.dates.pop(0)
        payload = {
            "success": 1,
            "results_html": search_html(params["start"] + 1, "Game", raw_date),
            "total_count": 1_000,
            "start": params["start"],
        }
        return JSONResponse(payload, 200, "2026-09-12T00:00:00+00:00")


def test_collector_checkpoint_resumes_at_next_start_and_preserves_raw(
    tmp_path: Path,
) -> None:
    raw_dir = tmp_path / "raw"
    checkpoint = tmp_path / "checkpoint.json"
    output = tmp_path / "candidates.csv"

    first_client = FakeSearchClient(["Sep 1, 2025"])
    first, first_checkpoint = collect_search_candidates(
        first_client,  # type: ignore[arg-type]
        raw_dir=raw_dir,
        checkpoint_path=checkpoint,
        output_path=output,
        max_pages=1,
    )
    assert first_client.starts == [0]
    assert first_checkpoint["next_start"] == 50
    assert (raw_dir / "search_000001.json").exists()
    raw = read_json(raw_dir / "search_000001.json")
    assert {
        "requested_at",
        "request_params",
        "http_status",
        "start",
        "count",
        "total_count",
        "results_html",
    }.issubset(raw)
    assert len(first) == 1

    second_client = FakeSearchClient(["Aug 31, 2025"])
    second, second_checkpoint = collect_search_candidates(
        second_client,  # type: ignore[arg-type]
        raw_dir=raw_dir,
        checkpoint_path=checkpoint,
        output_path=output,
        max_pages=1,
    )
    assert second_client.starts == [50]
    assert second_checkpoint["next_start"] == 100
    assert len(second) == 2
    persisted = pd.read_csv(output)
    assert len(persisted) == 2

