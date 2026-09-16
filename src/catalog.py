"""Documented Steam game-catalog collection and candidate intersection."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import pandas as pd

from config.settings import CATALOG_PAGE_SIZE, STEAM_CATALOG_URL
from src.io_utils import atomic_write_csv, atomic_write_json, read_json
from src.search_collector import SchemaDriftError
from src.steam_client import SteamClient


CATALOG_SOURCE = "IStoreService/GetAppList"
CATALOG_COLUMNS = ["appid", "name", "source", "catalog_collected_at"]


class CatalogPaginationError(RuntimeError):
    """The official catalog cursor cannot advance safely."""


def api_key_is_configured(api_key: str | None) -> bool:
    """Return only key presence; never inspect, print, or persist its value."""
    return bool(api_key and api_key.strip())


def default_catalog_checkpoint() -> dict[str, Any]:
    return {
        "last_appid": 0,
        "pages_completed": 0,
        "last_request_at": None,
        "catalog_count": 0,
        "completed": False,
    }


def load_catalog_checkpoint(path: Path) -> dict[str, Any]:
    if not path.exists():
        return default_catalog_checkpoint()
    checkpoint = read_json(path)
    missing = set(default_catalog_checkpoint()).difference(checkpoint)
    if missing:
        raise ValueError(f"Catalog checkpoint is missing fields: {sorted(missing)}")
    return checkpoint


def reset_catalog_state(
    raw_dir: Path,
    checkpoint_path: Path,
    output_paths: list[Path] | None = None,
) -> None:
    if raw_dir.exists():
        for path in raw_dir.glob("catalog_[0-9][0-9][0-9][0-9][0-9][0-9].json"):
            path.unlink()
    checkpoint_path.unlink(missing_ok=True)
    for path in output_paths or []:
        path.unlink(missing_ok=True)


def validate_catalog_payload(payload: dict[str, Any]) -> dict[str, Any]:
    response = payload.get("response")
    if not isinstance(response, dict):
        raise SchemaDriftError(
            "Schema Drift Suspected: official catalog response object is missing."
        )
    apps = response.get("apps")
    if not isinstance(apps, list):
        raise SchemaDriftError(
            "Schema Drift Suspected: official catalog apps is not a list."
        )
    for app in apps:
        if (
            not isinstance(app, dict)
            or isinstance(app.get("appid"), bool)
            or not isinstance(app.get("appid"), int)
            or "name" not in app
            or not isinstance(app["name"], str)
        ):
            raise SchemaDriftError(
                "Schema Drift Suspected: official catalog app structure changed."
            )
    if "have_more_results" in response and not isinstance(
        response["have_more_results"], bool
    ):
        raise SchemaDriftError(
            "Schema Drift Suspected: official catalog pagination flag changed type."
        )
    return response


def resolve_catalog_pagination(
    response: dict[str, Any],
    *,
    previous_last_appid: int,
    requested_page_size: int,
) -> tuple[int, bool]:
    """Return ``(next_last_appid, completed)`` for both response variants."""
    apps = response["apps"]
    if not apps:
        return previous_last_appid, True

    appids = [int(app["appid"]) for app in apps]
    if any(current <= prior for prior, current in zip(appids, appids[1:])):
        raise CatalogPaginationError(
            "Official catalog AppIDs are duplicate or not strictly increasing."
        )

    returned_last_appid = response.get("last_appid")
    if returned_last_appid is not None:
        if isinstance(returned_last_appid, bool) or not isinstance(
            returned_last_appid, int
        ):
            raise CatalogPaginationError(
                "Official catalog last_appid is not an integer cursor."
            )
        if returned_last_appid != appids[-1]:
            raise CatalogPaginationError(
                "Official catalog last_appid does not match the final returned AppID."
            )
        next_last_appid = returned_last_appid
    else:
        next_last_appid = appids[-1]

    if next_last_appid <= previous_last_appid:
        raise CatalogPaginationError(
            "Official catalog pagination cursor did not advance."
        )

    if "have_more_results" in response:
        completed = not response["have_more_results"]
    else:
        completed = len(apps) < requested_page_size
    return next_last_appid, completed


def print_catalog_response_diagnostic(response: dict[str, Any]) -> None:
    """Print first-page shape information without request or credential data."""
    apps = response["apps"]
    print(f"Catalog response keys: {sorted(response)}")
    print(f"Catalog app count: {len(apps)}")
    print(
        "Has have_more_results: "
        f"{'YES' if 'have_more_results' in response else 'NO'}"
    )
    print(f"Has last_appid: {'YES' if 'last_appid' in response else 'NO'}")
    print(f"First appid: {apps[0]['appid'] if apps else 'None'}")
    print(f"Last appid: {apps[-1]['appid'] if apps else 'None'}")


def _catalog_page_path(raw_dir: Path, page_number: int) -> Path:
    return raw_dir / f"catalog_{page_number:06d}.json"


def _catalog_records_from_raw(path: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    raw = read_json(path)
    required = {"requested_at", "http_status", "request_input", "response"}
    missing = required.difference(raw)
    if missing:
        raise SchemaDriftError(
            f"Raw catalog page {path.name} is missing {sorted(missing)}."
        )
    response = validate_catalog_payload({"response": raw["response"]})
    records = [
        {
            "appid": int(app["appid"]),
            "name": str(app.get("name") or ""),
            "source": CATALOG_SOURCE,
            "catalog_collected_at": raw["requested_at"],
        }
        for app in response["apps"]
    ]
    return records, response


def rebuild_official_catalog(raw_dir: Path, pages_completed: int) -> pd.DataFrame:
    records: list[dict[str, Any]] = []
    for page_number in range(1, pages_completed + 1):
        path = _catalog_page_path(raw_dir, page_number)
        if not path.exists():
            raise FileNotFoundError(
                f"Catalog checkpoint references missing raw page {path.name}."
            )
        page_records, _ = _catalog_records_from_raw(path)
        records.extend(page_records)
    frame = pd.DataFrame(records, columns=CATALOG_COLUMNS)
    return frame.drop_duplicates(subset="appid", keep="first").sort_values(
        "appid", kind="stable"
    ).reset_index(drop=True)


def collect_official_game_catalog(
    client: SteamClient,
    *,
    api_key: str,
    raw_dir: Path,
    checkpoint_path: Path,
    output_path: Path,
    page_size: int = CATALOG_PAGE_SIZE,
    restart: bool = False,
    logger: logging.Logger | None = None,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Collect the documented game-only catalog without persisting the key."""
    if not api_key_is_configured(api_key):
        raise ValueError("A Steam Web API key is required for catalog collection.")
    logger = logger or logging.getLogger(__name__)
    raw_dir.mkdir(parents=True, exist_ok=True)
    if restart:
        reset_catalog_state(raw_dir, checkpoint_path, [output_path])
    checkpoint = load_catalog_checkpoint(checkpoint_path)
    diagnostic_printed = False

    while not checkpoint["completed"]:
        page_number = int(checkpoint["pages_completed"]) + 1
        last_appid = int(checkpoint["last_appid"])
        raw_path = _catalog_page_path(raw_dir, page_number)
        request_input = {
            "include_games": True,
            "include_dlc": False,
            "include_software": False,
            "include_videos": False,
            "include_hardware": False,
            "last_appid": last_appid,
            "max_results": page_size,
        }

        if raw_path.exists():
            records, response_body = _catalog_records_from_raw(raw_path)
            raw = read_json(raw_path)
            requested_at = raw["requested_at"]
            logger.info(
                "collector=official_catalog page=%s last_appid=%s "
                "raw_page_reused=true",
                page_number,
                last_appid,
            )
        else:
            response = client.get_json(
                STEAM_CATALOG_URL,
                params={"key": api_key, "input_json": json.dumps(request_input)},
                collector="official_catalog",
                context=f"page={page_number} last_appid={last_appid}",
            )
            response_body = validate_catalog_payload(response.payload)
            requested_at = response.requested_at
            raw = {
                "requested_at": requested_at,
                "http_status": response.status_code,
                "request_input": request_input,
                "response": response_body,
            }
            atomic_write_json(raw_path, raw)
            records, _ = _catalog_records_from_raw(raw_path)

        if not diagnostic_printed:
            print_catalog_response_diagnostic(response_body)
            diagnostic_printed = True
        next_last_appid, completed = resolve_catalog_pagination(
            response_body,
            previous_last_appid=last_appid,
            requested_page_size=page_size,
        )

        checkpoint = {
            "last_appid": next_last_appid,
            "pages_completed": page_number,
            "last_request_at": requested_at,
            "catalog_count": int(checkpoint["catalog_count"]) + len(records),
            "completed": completed,
        }
        atomic_write_json(checkpoint_path, checkpoint)
        logger.info(
            "collector=official_catalog page=%s records_parsed=%s completed=%s",
            page_number,
            len(records),
            checkpoint["completed"],
        )

    catalog = rebuild_official_catalog(raw_dir, int(checkpoint["pages_completed"]))
    atomic_write_csv(output_path, catalog)
    return catalog, checkpoint


def match_candidates_to_catalog(
    candidates: pd.DataFrame,
    catalog: pd.DataFrame,
) -> pd.DataFrame:
    """Annotate, but do not equate, official game-catalog membership."""
    if "appid" not in candidates or "appid" not in catalog:
        raise ValueError("Both candidates and catalog must contain appid.")
    catalog_appids = set(catalog["appid"].dropna().map(int).unique())
    result = candidates.copy()
    result["in_official_game_catalog"] = result["appid"].map(int).isin(
        catalog_appids
    )
    return result
