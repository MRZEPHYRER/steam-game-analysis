"""Steam Search candidate discovery, parsing, stop rules, and checkpoints."""

from __future__ import annotations

import logging
import re
from datetime import date, datetime
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

import pandas as pd

from config.settings import (
    COUNTRY_CODE,
    END_DATE,
    LANGUAGE,
    SEARCH_PAGE_SIZE,
    START_DATE,
    STEAM_SEARCH_URL,
    STOP_AFTER_OLD_PAGES,
)
from src.io_utils import atomic_write_csv, atomic_write_json, read_json
from src.steam_client import SteamClient


SEARCH_SOURCE = "steam_search"
SEARCH_REQUIRED_KEYS = {"success", "results_html", "total_count", "start"}
CANDIDATE_COLUMNS = [
    "appid",
    "name",
    "release_date_raw",
    "release_date",
    "source",
    "candidate_collected_at",
    "search_page",
    "search_position",
    "search_rank",
]


class SchemaDriftError(RuntimeError):
    """A public response no longer matches the expected minimal contract."""


class _SearchResultsParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.records: list[dict[str, Any]] = []
        self.current: dict[str, Any] | None = None
        self.capture_field: str | None = None
        self.capture_tag: str | None = None
        self.capture_nested_depth = 0

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        attributes = dict(attrs)
        if tag == "a" and attributes.get("data-ds-appid"):
            self._finish_current()
            raw_appid = attributes["data-ds-appid"] or ""
            if re.fullmatch(r"\d+", raw_appid):
                self.current = {
                    "appid": int(raw_appid),
                    "name_parts": [],
                    "release_parts": [],
                }
            return

        if self.current is None:
            return
        if self.capture_field is not None:
            self.capture_nested_depth += 1
            return

        classes = set((attributes.get("class") or "").split())
        if "title" in classes:
            self.capture_field = "name_parts"
            self.capture_tag = tag
            self.capture_nested_depth = 0
        elif "search_released" in classes:
            self.capture_field = "release_parts"
            self.capture_tag = tag
            self.capture_nested_depth = 0

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        # Nested self-closing elements have no matching end tag, so they must
        # not increase capture_nested_depth. A self-closing result anchor has
        # no useful content to retain.
        attributes = dict(attrs)
        if tag == "a" and attributes.get("data-ds-appid"):
            self._finish_current()

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self.current is not None:
            self._finish_current()
            return
        if self.capture_field is None:
            return
        if self.capture_nested_depth:
            self.capture_nested_depth -= 1
        elif tag == self.capture_tag:
            self.capture_field = None
            self.capture_tag = None

    def handle_data(self, data: str) -> None:
        if self.current is not None and self.capture_field is not None:
            self.current[self.capture_field].append(data)

    def finish(self) -> None:
        self._finish_current()

    def _finish_current(self) -> None:
        if self.current is not None:
            self.records.append(self.current)
        self.current = None
        self.capture_field = None
        self.capture_tag = None
        self.capture_nested_depth = 0


def parse_exact_search_date(raw_date: str | None) -> str | None:
    """Parse only an exact English `Mon D, YYYY` store date."""
    if not raw_date:
        return None
    normalized = " ".join(raw_date.split())
    if not re.fullmatch(r"[A-Z][a-z]{2} \d{1,2}, \d{4}", normalized):
        return None
    try:
        return datetime.strptime(normalized, "%b %d, %Y").date().isoformat()
    except ValueError:
        return None


def parse_search_results(
    results_html: str,
    *,
    requested_at: str,
    start: int,
    page_size: int,
    search_page: int,
) -> list[dict[str, Any]]:
    """Extract candidate records while preserving ambiguous raw dates."""
    parser = _SearchResultsParser()
    parser.feed(results_html)
    parser.close()
    parser.finish()

    records: list[dict[str, Any]] = []
    for position, parsed in enumerate(parser.records, start=1):
        name = " ".join("".join(parsed["name_parts"]).split())
        release_date_raw = " ".join(
            "".join(parsed["release_parts"]).split()
        ) or None
        records.append(
            {
                "appid": parsed["appid"],
                "name": name,
                "release_date_raw": release_date_raw,
                "release_date": parse_exact_search_date(release_date_raw),
                "source": SEARCH_SOURCE,
                "candidate_collected_at": requested_at,
                "search_page": search_page,
                "search_position": position,
                "search_rank": start + position,
            }
        )
    return records


def validate_search_payload(payload: dict[str, Any]) -> None:
    missing = SEARCH_REQUIRED_KEYS.difference(payload)
    if missing:
        raise SchemaDriftError(
            "Schema Drift Suspected: Steam Search response is missing "
            f"{sorted(missing)}."
        )
    if payload["success"] not in (1, True):
        raise SchemaDriftError(
            "Schema Drift Suspected: Steam Search success flag is not successful."
        )
    if not isinstance(payload["results_html"], str):
        raise SchemaDriftError(
            "Schema Drift Suspected: Steam Search results_html is not text."
        )
    if not isinstance(payload["total_count"], int) or not isinstance(
        payload["start"], int
    ):
        raise SchemaDriftError(
            "Schema Drift Suspected: Steam Search pagination fields changed type."
        )


def update_old_page_streak(
    records: list[dict[str, Any]],
    *,
    start_date: str | date,
    current_streak: int,
    threshold: int,
) -> tuple[int, bool]:
    """Stop only after consecutive pages whose parseable dates are all old."""
    boundary = pd.Timestamp(start_date).date()
    parsed_dates = [
        date.fromisoformat(record["release_date"])
        for record in records
        if record.get("release_date")
    ]
    if parsed_dates and all(parsed_date < boundary for parsed_date in parsed_dates):
        current_streak += 1
    else:
        current_streak = 0
    return current_streak, current_streak >= threshold


def default_search_checkpoint() -> dict[str, Any]:
    return {
        "next_start": 0,
        "pages_completed": 0,
        "last_request_at": None,
        "candidate_count": 0,
        "consecutive_old_pages": 0,
        "completed": False,
    }


def load_search_checkpoint(path: Path) -> dict[str, Any]:
    if not path.exists():
        return default_search_checkpoint()
    checkpoint = read_json(path)
    required = set(default_search_checkpoint())
    missing = required.difference(checkpoint)
    if missing:
        raise ValueError(f"Search checkpoint is missing fields: {sorted(missing)}")
    return checkpoint


def reset_search_state(
    raw_dir: Path,
    checkpoint_path: Path,
    output_paths: list[Path] | None = None,
) -> None:
    """Remove only known generated Search state for an explicit restart."""
    if raw_dir.exists():
        for path in raw_dir.glob("search_[0-9][0-9][0-9][0-9][0-9][0-9].json"):
            path.unlink()
    checkpoint_path.unlink(missing_ok=True)
    for path in output_paths or []:
        path.unlink(missing_ok=True)


def _raw_page_path(raw_dir: Path, page_number: int) -> Path:
    return raw_dir / f"search_{page_number:06d}.json"


def _records_from_raw_page(path: Path) -> list[dict[str, Any]]:
    raw_page = read_json(path)
    required = {
        "requested_at",
        "request_params",
        "http_status",
        "start",
        "count",
        "total_count",
        "results_html",
    }
    missing = required.difference(raw_page)
    if missing:
        raise SchemaDriftError(
            f"Raw Search page {path.name} is missing {sorted(missing)}."
        )
    synthetic_payload = {
        "success": 1,
        "results_html": raw_page["results_html"],
        "total_count": raw_page["total_count"],
        "start": raw_page["start"],
    }
    validate_search_payload(synthetic_payload)
    page_number = int(path.stem.split("_")[-1])
    return parse_search_results(
        raw_page["results_html"],
        requested_at=raw_page["requested_at"],
        start=raw_page["start"],
        page_size=raw_page["count"],
        search_page=page_number,
    )


def rebuild_discovered_candidates(raw_dir: Path, pages_completed: int) -> pd.DataFrame:
    records: list[dict[str, Any]] = []
    for page_number in range(1, pages_completed + 1):
        path = _raw_page_path(raw_dir, page_number)
        if not path.exists():
            raise FileNotFoundError(
                f"Search checkpoint references missing raw page {path.name}."
            )
        records.extend(_records_from_raw_page(path))
    return pd.DataFrame(records, columns=CANDIDATE_COLUMNS)


def collect_search_candidates(
    client: SteamClient,
    *,
    raw_dir: Path,
    checkpoint_path: Path,
    output_path: Path,
    page_size: int = SEARCH_PAGE_SIZE,
    stop_after_old_pages: int = STOP_AFTER_OLD_PAGES,
    start_date: str = START_DATE,
    end_date: str = END_DATE,
    max_pages: int | None = None,
    restart: bool = False,
    logger: logging.Logger | None = None,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Collect or resume release-ordered Steam Search candidate discovery."""
    del end_date  # Preserved in the public call contract for the frozen study design.
    logger = logger or logging.getLogger(__name__)
    raw_dir.mkdir(parents=True, exist_ok=True)
    if restart:
        reset_search_state(raw_dir, checkpoint_path, [output_path])

    checkpoint = load_search_checkpoint(checkpoint_path)
    pages_this_run = 0

    while not checkpoint["completed"]:
        if max_pages is not None and pages_this_run >= max_pages:
            break

        start = int(checkpoint["next_start"])
        page_number = int(checkpoint["pages_completed"]) + 1
        raw_path = _raw_page_path(raw_dir, page_number)
        params = {
            "query": "",
            "start": start,
            "count": page_size,
            "sort_by": "Released_DESC",
            "category1": 998,
            "cc": COUNTRY_CODE,
            "l": LANGUAGE,
            "ndl": 1,
            "infinite": 1,
        }

        if raw_path.exists():
            records = _records_from_raw_page(raw_path)
            raw_page = read_json(raw_path)
            if int(raw_page["start"]) != start or int(raw_page["count"]) != page_size:
                raise SchemaDriftError(
                    "Raw Search page pagination does not match the checkpoint."
                )
            requested_at = raw_page["requested_at"]
            total_count = int(raw_page["total_count"])
            logger.info(
                "collector=steam_search page=%s start=%s raw_page_reused=true",
                page_number,
                start,
            )
        else:
            response = client.get_json(
                STEAM_SEARCH_URL,
                params=params,
                collector="steam_search",
                context=f"page={page_number} start={start}",
            )
            validate_search_payload(response.payload)
            if response.payload["start"] != start:
                raise SchemaDriftError(
                    "Schema Drift Suspected: Steam Search returned an unexpected start."
                )
            requested_at = response.requested_at
            total_count = int(response.payload["total_count"])
            raw_page = {
                "requested_at": requested_at,
                "request_params": params,
                "http_status": response.status_code,
                "start": start,
                "count": page_size,
                "total_count": total_count,
                "results_html": response.payload["results_html"],
            }
            atomic_write_json(raw_path, raw_page)
            records = parse_search_results(
                response.payload["results_html"],
                requested_at=requested_at,
                start=start,
                page_size=page_size,
                search_page=page_number,
            )

        if (
            raw_page["results_html"].strip()
            and not records
            and start < total_count
        ):
            raise SchemaDriftError(
                "Schema Drift Suspected: non-empty Steam Search HTML produced no AppIDs."
            )

        old_streak, stop_for_old_pages = update_old_page_streak(
            records,
            start_date=start_date,
            current_streak=int(checkpoint["consecutive_old_pages"]),
            threshold=stop_after_old_pages,
        )
        next_start = start + page_size
        exhausted_results = next_start >= total_count or not raw_page[
            "results_html"
        ].strip()
        checkpoint = {
            "next_start": next_start,
            "pages_completed": page_number,
            "last_request_at": requested_at,
            "candidate_count": int(checkpoint["candidate_count"]) + len(records),
            "consecutive_old_pages": old_streak,
            "completed": bool(stop_for_old_pages or exhausted_results),
        }
        atomic_write_json(checkpoint_path, checkpoint)
        pages_this_run += 1
        logger.info(
            "collector=steam_search page=%s start=%s records_parsed=%s "
            "old_page_streak=%s completed=%s",
            page_number,
            start,
            len(records),
            old_streak,
            checkpoint["completed"],
        )

    discovered = rebuild_discovered_candidates(
        raw_dir, int(checkpoint["pages_completed"])
    )
    atomic_write_csv(output_path, discovered)
    return discovered, checkpoint
