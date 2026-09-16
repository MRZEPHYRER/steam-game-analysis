from __future__ import annotations

import pandas as pd
import pytest

from src.catalog import (
    CatalogPaginationError,
    api_key_is_configured,
    match_candidates_to_catalog,
    resolve_catalog_pagination,
    validate_catalog_payload,
)
from src.search_collector import SchemaDriftError


def catalog_response(
    appids: list[int],
    *,
    have_more_results: bool | None = None,
    last_appid: int | None = None,
) -> dict:
    response: dict = {
        "apps": [{"appid": appid, "name": f"Game {appid}"} for appid in appids]
    }
    if have_more_results is not None:
        response["have_more_results"] = have_more_results
    if last_appid is not None:
        response["last_appid"] = last_appid
    return response


def test_explicit_have_more_true_continues() -> None:
    response = catalog_response(
        [11, 12], have_more_results=True, last_appid=12
    )
    assert resolve_catalog_pagination(
        response, previous_last_appid=10, requested_page_size=2
    ) == (12, False)


def test_explicit_have_more_false_stops() -> None:
    response = catalog_response(
        [11, 12], have_more_results=False, last_appid=12
    )
    assert resolve_catalog_pagination(
        response, previous_last_appid=10, requested_page_size=2
    ) == (12, True)


def test_missing_have_more_flag_is_valid() -> None:
    response = validate_catalog_payload({"response": catalog_response([11])})
    assert "have_more_results" not in response


def test_missing_flag_full_page_continues() -> None:
    assert resolve_catalog_pagination(
        catalog_response([11, 12]),
        previous_last_appid=10,
        requested_page_size=2,
    ) == (12, False)


def test_missing_flag_short_page_stops() -> None:
    assert resolve_catalog_pagination(
        catalog_response([11]),
        previous_last_appid=10,
        requested_page_size=2,
    ) == (11, True)


def test_empty_apps_stops() -> None:
    assert resolve_catalog_pagination(
        catalog_response([]),
        previous_last_appid=10,
        requested_page_size=2,
    ) == (10, True)


def test_cursor_must_advance() -> None:
    with pytest.raises(CatalogPaginationError, match="did not advance"):
        resolve_catalog_pagination(
            catalog_response([10]),
            previous_last_appid=10,
            requested_page_size=1,
        )


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"response": {}},
        {"response": {"apps": "not-a-list"}},
        {"response": {"apps": [{"appid": 1}]}},
        {"response": {"apps": [{"appid": "1", "name": "Game"}]}},
    ],
)
def test_malformed_or_missing_apps_raise_schema_drift(payload: dict) -> None:
    with pytest.raises(SchemaDriftError):
        validate_catalog_payload(payload)


def test_catalog_join_marks_matches_unmatched_and_ignores_duplicates() -> None:
    candidates = pd.DataFrame({"appid": [1, 2, 3], "name": ["A", "B", "C"]})
    catalog = pd.DataFrame({"appid": [1, 1, 3], "name": ["A", "A", "C"]})
    result = match_candidates_to_catalog(candidates, catalog)
    assert result["in_official_game_catalog"].tolist() == [True, False, True]
    assert len(result) == len(candidates)


def test_missing_api_key_safely_disables_catalog_only() -> None:
    assert api_key_is_configured(None) is False
    assert api_key_is_configured("") is False
    assert api_key_is_configured("   ") is False
    assert api_key_is_configured("configured-but-never-logged") is True
