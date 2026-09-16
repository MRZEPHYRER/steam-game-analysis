from __future__ import annotations

import json

import pandas as pd
import pytest

from src.eligibility import (
    EXCLUSION_APPDETAILS_REQUEST_FAILED,
    EXCLUSION_APPDETAILS_SCHEMA_INVALID,
    EXCLUSION_APPDETAILS_UNSUCCESSFUL,
    EXCLUSION_COMING_SOON,
    EXCLUSION_NON_GAME,
    EXCLUSION_OUTSIDE_WINDOW,
    EXCLUSION_UNPARSEABLE_DATE,
    build_eligibility_frame,
    parse_exact_store_date,
)


@pytest.mark.parametrize(
    ("raw_date", "expected"),
    [
        ("7 Sep, 2025", "2025-09-07"),
        ("Sep 7, 2025", "2025-09-07"),
        ("7 September, 2025", "2025-09-07"),
        ("September 7, 2025", "2025-09-07"),
        ("Sep 2025", None),
        ("2025", None),
        ("Coming Soon", None),
        (None, None),
    ],
)
def test_parse_exact_store_date(raw_date: str | None, expected: str | None) -> None:
    assert parse_exact_store_date(raw_date) == expected


def candidate(appid: int = 1) -> pd.DataFrame:
    return pd.DataFrame(
        {
            "appid": [appid],
            "name": ["Search name"],
            "release_date": ["2025-08-02"],
            "in_official_game_catalog": [True],
        }
    )


def metadata(**overrides) -> pd.DataFrame:
    row = {
        "appid": 1,
        "appdetails_status": "success",
        "app_type": "game",
        "store_name": "Store name",
        "is_free": False,
        "store_release_date_raw": "Aug 2, 2025",
        "store_release_date": "2025-08-02",
        "coming_soon": False,
        "developers": json.dumps(["Developer"]),
        "publishers": json.dumps(["Publisher"]),
        "platform_windows": True,
        "platform_mac": False,
        "platform_linux": False,
        "genres": json.dumps([{"id": "1", "description": "Action"}]),
    }
    row.update(overrides)
    return pd.DataFrame([row])


def evaluate_reason(metadata_frame: pd.DataFrame) -> tuple[pd.DataFrame, str | None]:
    eligible, audit = build_eligibility_frame(
        candidate(), metadata_frame, evaluated_at="2026-09-12T00:00:00+00:00"
    )
    return eligible, audit.loc[0, "exclusion_reason"]


def test_game_with_valid_store_date_is_eligible() -> None:
    eligible, reason = evaluate_reason(
        metadata(genres=json.dumps([{"id": "70", "description": "Early Access"}]))
    )
    assert reason is None
    assert len(eligible) == 1
    assert eligible.loc[0, "release_date"] == "2025-08-02"
    assert pd.isna(eligible.loc[0, "is_early_access"])


def test_release_date_reconciliation_is_audited() -> None:
    _, audit = build_eligibility_frame(
        candidate(),
        metadata(store_release_date_raw="3 Aug, 2025", store_release_date="2025-08-03"),
        evaluated_at="2026-09-12T00:00:00+00:00",
    )
    assert audit.loc[0, "search_release_date"] == "2025-08-02"
    assert audit.loc[0, "store_release_date_raw"] == "3 Aug, 2025"
    assert audit.loc[0, "store_release_date"] == "2025-08-03"
    assert audit.loc[0, "release_date_status"] == "different_date"


def test_dlc_is_excluded() -> None:
    eligible, reason = evaluate_reason(metadata(app_type="dlc"))
    assert eligible.empty
    assert reason == EXCLUSION_NON_GAME


@pytest.mark.parametrize(
    ("status", "expected_reason"),
    [
        ("unsuccessful", EXCLUSION_APPDETAILS_UNSUCCESSFUL),
        ("request_failed", EXCLUSION_APPDETAILS_REQUEST_FAILED),
        ("schema_invalid", EXCLUSION_APPDETAILS_SCHEMA_INVALID),
    ],
)
def test_appdetails_statuses_have_distinct_exclusion_reasons(
    status: str,
    expected_reason: str,
) -> None:
    eligible, reason = evaluate_reason(metadata(appdetails_status=status))
    assert eligible.empty
    assert reason == expected_reason


def test_unparseable_store_release_date_is_excluded() -> None:
    eligible, reason = evaluate_reason(
        metadata(store_release_date_raw="Aug 2025", store_release_date=None)
    )
    assert eligible.empty
    assert reason == EXCLUSION_UNPARSEABLE_DATE


@pytest.mark.parametrize("release_date", ["2025-06-30", "2026-01-01"])
def test_outside_store_release_date_is_excluded(release_date: str) -> None:
    eligible, reason = evaluate_reason(
        metadata(
            store_release_date_raw=release_date,
            store_release_date=release_date,
        )
    )
    assert eligible.empty
    assert reason == EXCLUSION_OUTSIDE_WINDOW


def test_coming_soon_is_excluded() -> None:
    eligible, reason = evaluate_reason(metadata(coming_soon=True))
    assert eligible.empty
    assert reason == EXCLUSION_COMING_SOON
