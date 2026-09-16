"""Candidate appdetails collection and auditable eligibility evaluation."""

from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from config.settings import (
    COUNTRY_CODE,
    END_DATE,
    LANGUAGE,
    START_DATE,
    STEAM_APPDETAILS_URL,
)
from src.io_utils import atomic_write_csv, atomic_write_json, read_json
from src.progress import ConsoleProgress
from src.search_collector import SchemaDriftError
from src.steam_client import SteamClient, SteamClientError


EXCLUSION_NOT_IN_CATALOG = "not_in_official_game_catalog"
EXCLUSION_NON_GAME = "non_game_app_type"
EXCLUSION_OUTSIDE_WINDOW = "release_date_outside_window"
EXCLUSION_UNPARSEABLE_DATE = "release_date_unparseable"
EXCLUSION_COMING_SOON = "coming_soon"
EXCLUSION_APPDETAILS_UNSUCCESSFUL = "appdetails_unsuccessful"
EXCLUSION_APPDETAILS_REQUEST_FAILED = "appdetails_request_failed"
EXCLUSION_APPDETAILS_SCHEMA_INVALID = "appdetails_schema_invalid"
EXCLUSION_METADATA_MISSING = "store_metadata_missing"

METADATA_COLUMNS = [
    "appid",
    "appdetails_status",
    "app_type",
    "store_name",
    "is_free",
    "store_release_date_raw",
    "store_release_date",
    "coming_soon",
    "developers",
    "developers_present",
    "publishers",
    "publishers_present",
    "platform_windows",
    "platform_mac",
    "platform_linux",
    "genres",
    "genres_present",
    "list_price_cents",
    "current_price_cents",
    "discount_percent",
    "price_currency",
    "price_overview_present",
    "metadata_collected_at",
    "schema_error",
]

ELIGIBLE_COLUMNS = [
    "appid",
    "name",
    "release_date",
    "search_release_date",
    "store_release_date",
    "release_date_conflict",
    "developer",
    "publisher",
    "is_free",
    "platform_windows",
    "platform_mac",
    "platform_linux",
    "is_early_access",
]

AUDIT_COLUMNS = [
    "appid",
    "is_eligible",
    "exclusion_reason",
    "evaluated_at",
    "appdetails_status",
    "app_type",
    "search_release_date",
    "store_release_date_raw",
    "store_release_date",
    "release_date_status",
]


def parse_exact_store_date(raw_date: str | None) -> str | None:
    """Parse only complete English dates returned by Store appdetails.

    Steam has returned both day-first (``7 Sep, 2025``) and month-first
    (``Sep 7, 2025``) English renderings. Ambiguous values remain unresolved.
    """
    if not raw_date:
        return None
    normalized = " ".join(raw_date.split())
    formats = (
        (r"\d{1,2} [A-Z][a-z]{2}, \d{4}", "%d %b, %Y"),
        (r"[A-Z][a-z]{2} \d{1,2}, \d{4}", "%b %d, %Y"),
        (r"\d{1,2} [A-Z][a-z]+, \d{4}", "%d %B, %Y"),
        (r"[A-Z][a-z]+ \d{1,2}, \d{4}", "%B %d, %Y"),
    )
    for pattern, date_format in formats:
        if not re.fullmatch(pattern, normalized):
            continue
        try:
            return datetime.strptime(normalized, date_format).date().isoformat()
        except ValueError:
            return None
    return None


def validate_appdetails_payload(payload: dict[str, Any], appid: int) -> None:
    app_payload = payload.get(str(appid))
    if (
        not isinstance(app_payload, dict)
        or "success" not in app_payload
        or not isinstance(app_payload["success"], bool)
    ):
        raise SchemaDriftError(
            "Schema Drift Suspected: appdetails AppID envelope changed."
        )
    if not app_payload["success"]:
        return
    data = app_payload.get("data")
    required = {
        "steam_appid",
        "type",
        "name",
        "is_free",
        "release_date",
        "platforms",
    }
    if not isinstance(data, dict) or not required.issubset(data):
        raise SchemaDriftError(
            "Schema Drift Suspected: appdetails is missing critical metadata fields."
        )
    if data["steam_appid"] != appid:
        raise SchemaDriftError(
            "Schema Drift Suspected: appdetails returned a different steam_appid."
        )
    if (
        isinstance(data["steam_appid"], bool)
        or not isinstance(data["steam_appid"], int)
        or not isinstance(data["type"], str)
        or not isinstance(data["name"], str)
        or not isinstance(data["is_free"], bool)
        or not isinstance(data["release_date"], dict)
        or not isinstance(data["platforms"], dict)
    ):
        raise SchemaDriftError(
            "Schema Drift Suspected: appdetails critical metadata changed type."
        )
    for field_name in ("developers", "publishers"):
        value = data.get(field_name)
        if value is not None and (
            not isinstance(value, list)
            or any(not isinstance(item, str) for item in value)
        ):
            raise SchemaDriftError(
                f"Schema Drift Suspected: appdetails {field_name} changed type."
            )
    genres = data.get("genres")
    if genres is not None and (
        not isinstance(genres, list)
        or any(not isinstance(item, dict) for item in genres)
    ):
        raise SchemaDriftError(
            "Schema Drift Suspected: appdetails genres changed type."
        )
    price = data.get("price_overview")
    if price is not None:
        if not isinstance(price, dict):
            raise SchemaDriftError(
                "Schema Drift Suspected: appdetails price_overview changed type."
            )
        for field_name in ("initial", "final"):
            value = price.get(field_name)
            if isinstance(value, bool) or not isinstance(value, int):
                raise SchemaDriftError(
                    "Schema Drift Suspected: appdetails price source units are "
                    "not integers."
                )


def _metadata_record_from_raw(path: Path) -> dict[str, Any]:
    raw = read_json(path)
    required_raw = {"appid", "requested_at", "request_params", "http_status"}
    missing_raw = required_raw.difference(raw)
    if missing_raw:
        raise SchemaDriftError(
            f"Raw appdetails file {path.name} is missing {sorted(missing_raw)}."
        )
    appid = int(raw["appid"])
    collected_at = raw["requested_at"]
    if "request_error" in raw:
        return {
            "appid": appid,
            "appdetails_status": "request_failed",
            "metadata_collected_at": collected_at,
        }

    payload = raw.get("payload")
    if not isinstance(payload, dict):
        raise SchemaDriftError(
            f"Raw appdetails file {path.name} has no object payload."
        )
    validate_appdetails_payload(payload, appid)
    app_payload = payload[str(appid)]
    if not app_payload["success"]:
        return {
            "appid": appid,
            "appdetails_status": "unsuccessful",
            "metadata_collected_at": collected_at,
        }

    data = app_payload["data"]
    release = data.get("release_date") or {}
    platforms = data.get("platforms") or {}
    price = data.get("price_overview")
    store_release_raw = release.get("date") if isinstance(release, dict) else None
    record = {
        "appid": appid,
        "appdetails_status": "success",
        "app_type": data.get("type"),
        "store_name": data.get("name"),
        "is_free": data.get("is_free"),
        "store_release_date_raw": store_release_raw,
        "store_release_date": parse_exact_store_date(store_release_raw),
        "coming_soon": bool(release.get("coming_soon"))
        if isinstance(release, dict)
        else None,
        "developers": json.dumps(
            data["developers"], ensure_ascii=False, separators=(",", ":")
        )
        if data.get("developers") is not None
        else None,
        "developers_present": "developers" in data,
        "publishers": json.dumps(
            data["publishers"], ensure_ascii=False, separators=(",", ":")
        )
        if data.get("publishers") is not None
        else None,
        "publishers_present": "publishers" in data,
        "platform_windows": platforms.get("windows")
        if isinstance(platforms, dict)
        else None,
        "platform_mac": platforms.get("mac")
        if isinstance(platforms, dict)
        else None,
        "platform_linux": platforms.get("linux")
        if isinstance(platforms, dict)
        else None,
        "genres": json.dumps(
            data["genres"], ensure_ascii=False, separators=(",", ":")
        )
        if data.get("genres") is not None
        else None,
        "genres_present": "genres" in data,
        "list_price_cents": price.get("initial") if price else None,
        "current_price_cents": price.get("final") if price else None,
        "discount_percent": price.get("discount_percent") if price else None,
        "price_currency": price.get("currency") if price else None,
        "price_overview_present": "price_overview" in data,
        "metadata_collected_at": collected_at,
        "schema_error": None,
    }
    return record


def collect_candidate_appdetails(
    client: SteamClient,
    candidates: pd.DataFrame,
    *,
    raw_dir: Path,
    output_path: Path,
    max_apps: int | None = None,
    show_progress: bool = True,
    logger: logging.Logger | None = None,
) -> tuple[pd.DataFrame, bool]:
    """Collect appdetails only for official-catalog matched candidates."""
    if not {"appid", "in_official_game_catalog"}.issubset(candidates.columns):
        raise ValueError(
            "Candidates require appid and in_official_game_catalog fields."
        )
    logger = logger or logging.getLogger(__name__)
    raw_dir.mkdir(parents=True, exist_ok=True)
    all_appids = sorted(
        int(appid)
        for appid in candidates.loc[
            candidates["in_official_game_catalog"], "appid"
        ]
        .dropna()
        .unique()
    )
    selected_appids = all_appids if max_apps is None else all_appids[:max_apps]

    records: list[dict[str, Any]] = []
    reused = 0
    newly_requested = 0
    retried_failures = 0
    unresolved_failures = 0
    with ConsoleProgress(len(selected_appids), enabled=show_progress) as progress:
        for position, appid in enumerate(selected_appids, start=1):
            raw_path = raw_dir / f"appdetails_{appid:010d}.json"
            retrying_failure = False
            should_request = not raw_path.exists()
            if raw_path.exists():
                existing_raw = read_json(raw_path)
                if "request_error" in existing_raw:
                    retrying_failure = True
                    should_request = True
                    retried_failures += 1
                    logger.info(
                        "collector=appdetails appid=%s retrying_failed_raw=true", appid
                    )
                else:
                    reused += 1
                    logger.info("collector=appdetails appid=%s raw_reused=true", appid)

            if should_request:
                if not retrying_failure:
                    newly_requested += 1
                try:
                    response = client.get_json(
                        STEAM_APPDETAILS_URL,
                        params={"appids": appid, "cc": COUNTRY_CODE, "l": LANGUAGE},
                        collector="appdetails",
                        context=(
                            f"appid={appid} position={position}/{len(selected_appids)}"
                        ),
                    )
                    raw = {
                        "requested_at": response.requested_at,
                        "request_params": {
                            "appids": appid,
                            "cc": COUNTRY_CODE,
                            "l": LANGUAGE,
                        },
                        "http_status": response.status_code,
                        "appid": appid,
                        "payload": response.payload,
                    }
                    if retrying_failure:
                        raw["previous_request_failed"] = True
                except SteamClientError as exc:
                    raw = {
                        "requested_at": datetime.now(timezone.utc).isoformat(),
                        "request_params": {
                            "appids": appid,
                            "cc": COUNTRY_CODE,
                            "l": LANGUAGE,
                        },
                        "http_status": None,
                        "appid": appid,
                        "request_error": str(exc),
                    }
                    if retrying_failure:
                        raw["previous_request_failed"] = True
                    logger.error(
                        "collector=appdetails appid=%s status=request_failed", appid
                    )
                atomic_write_json(raw_path, raw)

            try:
                record = _metadata_record_from_raw(raw_path)
            except SchemaDriftError as exc:
                logger.error(
                    "collector=appdetails appid=%s status=schema_invalid error=%s",
                    appid,
                    exc,
                )
                record = {
                    "appid": appid,
                    "appdetails_status": "schema_invalid",
                    "metadata_collected_at": read_json(raw_path).get("requested_at"),
                    "schema_error": str(exc),
                }
            records.append(record)
            if record.get("appdetails_status") == "request_failed":
                unresolved_failures += 1
            progress.update(
                position,
                reused=reused,
                new=newly_requested,
                retried=retried_failures,
                failed=unresolved_failures,
            )
    metadata = pd.DataFrame(records).reindex(columns=METADATA_COLUMNS)
    for column in ("list_price_cents", "current_price_cents", "discount_percent"):
        metadata[column] = pd.array(metadata[column], dtype="Int64")
    atomic_write_csv(output_path, metadata)
    return metadata, len(selected_appids) == len(all_appids)


def _optional_value(record: dict[str, Any] | None, key: str) -> Any:
    if record is None:
        return None
    value = record.get(key)
    try:
        return None if pd.isna(value) else value
    except (TypeError, ValueError):
        return value


def release_date_status(
    search_release_date: object,
    store_release_date_raw: object,
    store_release_date: object,
) -> str:
    """Classify Search/Store reconciliation using a finite vocabulary."""
    search_value = None if pd.isna(search_release_date) else str(search_release_date)
    raw_value = None if pd.isna(store_release_date_raw) else store_release_date_raw
    store_value = None if pd.isna(store_release_date) else str(store_release_date)
    if not raw_value:
        return "store_missing"
    if not store_value:
        return "store_unparseable"
    return "exact_match" if search_value == store_value else "different_date"


def build_eligibility_frame(
    candidate_catalog_match: pd.DataFrame,
    metadata: pd.DataFrame,
    *,
    start_date: str = START_DATE,
    end_date: str = END_DATE,
    evaluated_at: str | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Create the eligible frame and one finite-code audit row per candidate."""
    required = {"appid", "name", "release_date", "in_official_game_catalog"}
    missing = required.difference(candidate_catalog_match.columns)
    if missing:
        raise ValueError(f"Candidate match is missing fields: {sorted(missing)}")
    metadata_by_appid = (
        metadata.drop_duplicates(subset="appid", keep="first").set_index("appid")
        if not metadata.empty
        else pd.DataFrame(columns=METADATA_COLUMNS).set_index("appid")
    )
    start = pd.Timestamp(start_date)
    end = pd.Timestamp(end_date)
    evaluated_at = evaluated_at or datetime.now(timezone.utc).isoformat()

    audit_records: list[dict[str, Any]] = []
    eligible_records: list[dict[str, Any]] = []
    for candidate in candidate_catalog_match.to_dict(orient="records"):
        appid = int(candidate["appid"])
        metadata_record = (
            metadata_by_appid.loc[appid].to_dict()
            if appid in metadata_by_appid.index
            else None
        )
        exclusion_reason: str | None = None
        final_release_date: str | None = None
        search_release_date = candidate.get("release_date")
        if pd.isna(search_release_date):
            search_release_date = None
        metadata_status = _optional_value(metadata_record, "appdetails_status")
        app_type = _optional_value(metadata_record, "app_type")
        store_release_date_raw = _optional_value(
            metadata_record, "store_release_date_raw"
        )
        store_release_date = _optional_value(metadata_record, "store_release_date")
        date_status = release_date_status(
            search_release_date,
            store_release_date_raw,
            store_release_date,
        )

        if not bool(candidate["in_official_game_catalog"]):
            exclusion_reason = EXCLUSION_NOT_IN_CATALOG
        elif metadata_record is None:
            exclusion_reason = EXCLUSION_APPDETAILS_REQUEST_FAILED
        elif metadata_status == "unsuccessful":
            exclusion_reason = EXCLUSION_APPDETAILS_UNSUCCESSFUL
        elif metadata_status == "request_failed":
            exclusion_reason = EXCLUSION_APPDETAILS_REQUEST_FAILED
        elif metadata_status == "schema_invalid":
            exclusion_reason = EXCLUSION_APPDETAILS_SCHEMA_INVALID
        elif metadata_status != "success":
            exclusion_reason = EXCLUSION_APPDETAILS_SCHEMA_INVALID
        elif _optional_value(metadata_record, "coming_soon") is True:
            exclusion_reason = EXCLUSION_COMING_SOON
        elif app_type != "game":
            exclusion_reason = EXCLUSION_NON_GAME
        elif not store_release_date_raw:
            exclusion_reason = EXCLUSION_METADATA_MISSING
        elif not store_release_date:
            exclusion_reason = EXCLUSION_UNPARSEABLE_DATE
        else:
            store_date = pd.Timestamp(store_release_date)
            final_release_date = store_date.date().isoformat()
            if not start <= store_date <= end:
                exclusion_reason = EXCLUSION_OUTSIDE_WINDOW

        is_eligible = exclusion_reason is None
        audit_records.append(
            {
                "appid": appid,
                "is_eligible": is_eligible,
                "exclusion_reason": exclusion_reason,
                "evaluated_at": evaluated_at,
                "appdetails_status": metadata_status,
                "app_type": app_type,
                "search_release_date": search_release_date,
                "store_release_date_raw": store_release_date_raw,
                "store_release_date": store_release_date,
                "release_date_status": date_status,
            }
        )
        if not is_eligible or metadata_record is None:
            continue

        release_date_conflict = bool(
            search_release_date
            and final_release_date
            and str(search_release_date) != final_release_date
        )
        eligible_records.append(
            {
                "appid": appid,
                "name": metadata_record.get("store_name") or candidate["name"],
                "release_date": final_release_date,
                "search_release_date": search_release_date,
                "store_release_date": final_release_date,
                "release_date_conflict": release_date_conflict,
                "developer": _optional_value(metadata_record, "developers"),
                "publisher": _optional_value(metadata_record, "publishers"),
                "is_free": _optional_value(metadata_record, "is_free"),
                "platform_windows": _optional_value(
                    metadata_record, "platform_windows"
                ),
                "platform_mac": _optional_value(metadata_record, "platform_mac"),
                "platform_linux": _optional_value(
                    metadata_record, "platform_linux"
                ),
                # appdetails has no explicit, reliable Early Access field.
                "is_early_access": None,
            }
        )

    eligible = pd.DataFrame(eligible_records, columns=ELIGIBLE_COLUMNS)
    audit = pd.DataFrame(audit_records, columns=AUDIT_COLUMNS)
    return eligible, audit
