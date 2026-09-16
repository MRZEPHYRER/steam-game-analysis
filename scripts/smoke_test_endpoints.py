"""Perform a tiny, non-collecting validation of the public Steam endpoints."""

from __future__ import annotations

import sys
from collections.abc import Callable
from pathlib import Path

import requests

# Allow direct execution with `python scripts/smoke_test_endpoints.py`.
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (
    COUNTRY_CODE,
    CURRENCY,
    LANGUAGE,
)
from src.reviews import review_request_params


APPID = 1_086_940  # Baldur's Gate 3: a paid game with reviews and USD pricing.
TIMEOUT_SECONDS = 30
USER_AGENT = "steam-game-analysis-step1-smoke-test/1.0"


def check_search(session: requests.Session) -> None:
    response = session.get(
        "https://store.steampowered.com/search/results/",
        params={
            "query": "",
            "start": 0,
            "count": 1,
            "sort_by": "Released_DESC",
            "category1": 998,
            "cc": COUNTRY_CODE,
            "l": LANGUAGE,
            "ndl": 1,
            "infinite": 1,
        },
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    required = {"success", "results_html", "total_count", "start"}
    if not required.issubset(payload) or "data-ds-appid" not in payload["results_html"]:
        raise ValueError("Search response is missing expected fields or AppID markup.")


def check_appdetails(session: requests.Session) -> None:
    response = session.get(
        "https://store.steampowered.com/api/appdetails",
        params={"appids": APPID, "cc": COUNTRY_CODE, "l": LANGUAGE},
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    app_payload = response.json().get(str(APPID), {})
    if not app_payload.get("success"):
        raise ValueError("appdetails returned an unsuccessful AppID payload.")

    data = app_payload.get("data", {})
    required = {
        "type",
        "name",
        "steam_appid",
        "is_free",
        "platforms",
        "release_date",
    }
    if not required.issubset(data):
        raise ValueError("appdetails data is missing expected metadata fields.")
    price = data.get("price_overview")
    if not price or price.get("currency") != CURRENCY:
        raise ValueError(f"Expected a paid {CURRENCY} price under cc={COUNTRY_CODE}.")
    for field_name in ("initial", "final"):
        value = price.get(field_name)
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(
                f"Expected price_overview.{field_name} to be integer source units."
            )


def check_appreviews(session: requests.Session) -> None:
    response = session.get(
        f"https://store.steampowered.com/appreviews/{APPID}",
        params=review_request_params(),
        timeout=TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    summary = payload.get("query_summary", {})
    required = {
        "review_score",
        "review_score_desc",
        "total_positive",
        "total_negative",
        "total_reviews",
    }
    if payload.get("success") != 1 or not required.issubset(summary):
        raise ValueError("appreviews response is missing the expected query summary.")


def main() -> int:
    checks: list[tuple[str, Callable[[requests.Session], None]]] = [
        ("Steam Search", check_search),
        ("appdetails", check_appdetails),
        ("appreviews", check_appreviews),
    ]
    failures = 0
    with requests.Session() as session:
        session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})
        for label, check in checks:
            try:
                check(session)
            except (requests.RequestException, ValueError) as exc:
                failures += 1
                print(f"[FAIL] {label}: {exc}")
            else:
                print(f"[OK] {label}")

    if failures:
        print(f"Smoke test completed with {failures} failure(s).")
        return 1
    print("[OK] price source units (integer cents, USD, cc=us)")
    print("[OK] review summary")
    return 0


if __name__ == "__main__":
    sys.exit(main())
