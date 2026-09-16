"""Conservative synchronous HTTP client for public Steam endpoints."""

from __future__ import annotations

import logging
import random
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlsplit

import requests

from config.settings import (
    BACKOFF_BASE_SECONDS,
    MAX_RETRIES,
    REQUEST_DELAY_SECONDS,
    REQUEST_JITTER_SECONDS,
    REQUEST_TIMEOUT_SECONDS,
    USER_AGENT,
)


RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
SENSITIVE_PARAMETER_NAMES = {"key"}


class SteamClientError(RuntimeError):
    """A sanitized Steam failure with aggregate-safe retry telemetry."""

    def __init__(
        self,
        message: str,
        *,
        retry_count: int = 0,
        retryable_status_codes: tuple[int, ...] = (),
        transport_error_count: int = 0,
    ) -> None:
        super().__init__(message)
        self.retry_count = retry_count
        self.retryable_status_codes = retryable_status_codes
        self.transport_error_count = transport_error_count


@dataclass(frozen=True, slots=True)
class JSONResponse:
    payload: dict[str, Any]
    status_code: int
    requested_at: str
    retry_count: int = 0
    retryable_status_codes: tuple[int, ...] = ()
    elapsed_seconds: float | None = None
    transport_error_count: int = 0


class SteamClient:
    """Apply common throttling, retries, and sanitized logging."""

    def __init__(
        self,
        *,
        session: requests.Session | None = None,
        timeout_seconds: float = REQUEST_TIMEOUT_SECONDS,
        request_delay_seconds: float = REQUEST_DELAY_SECONDS,
        jitter_seconds: float = REQUEST_JITTER_SECONDS,
        max_retries: int = MAX_RETRIES,
        backoff_base_seconds: float = BACKOFF_BASE_SECONDS,
        logger: logging.Logger | None = None,
    ) -> None:
        self.session = session or requests.Session()
        self.session.headers.update(
            {"User-Agent": USER_AGENT, "Accept": "application/json"}
        )
        self.timeout_seconds = timeout_seconds
        self.request_delay_seconds = request_delay_seconds
        self.jitter_seconds = jitter_seconds
        self.max_retries = max_retries
        self.backoff_base_seconds = backoff_base_seconds
        self.logger = logger or logging.getLogger(__name__)
        self._last_request_started_at: float | None = None

    def _throttle(self) -> None:
        if self._last_request_started_at is None:
            return
        target_delay = self.request_delay_seconds + random.uniform(
            0, self.jitter_seconds
        )
        elapsed = time.monotonic() - self._last_request_started_at
        if elapsed < target_delay:
            time.sleep(target_delay - elapsed)

    def get_json(
        self,
        url: str,
        *,
        params: dict[str, Any],
        collector: str,
        context: str,
    ) -> JSONResponse:
        """GET a JSON object, retrying only transient failures.

        Sensitive query values are never logged or included in raised errors.
        """
        endpoint = urlsplit(url).path
        safe_parameter_names = sorted(
            name for name in params if name.lower() not in SENSITIVE_PARAMETER_NAMES
        )
        request_started_at = time.monotonic()
        retryable_status_codes: list[int] = []
        transport_error_count = 0

        for attempt in range(self.max_retries + 1):
            self._throttle()
            self._last_request_started_at = time.monotonic()
            requested_at = datetime.now(timezone.utc).isoformat()
            self.logger.info(
                "collector=%s context=%s endpoint=%s retry=%s params=%s",
                collector,
                context,
                endpoint,
                attempt,
                safe_parameter_names,
            )
            try:
                response = self.session.get(
                    url,
                    params=params,
                    timeout=self.timeout_seconds,
                )
            except (requests.Timeout, requests.ConnectionError) as exc:
                transport_error_count += 1
                if attempt >= self.max_retries:
                    raise SteamClientError(
                        f"{collector} request failed after {attempt + 1} attempts "
                        f"at {endpoint}: {type(exc).__name__}.",
                        retry_count=attempt,
                        retryable_status_codes=tuple(retryable_status_codes),
                        transport_error_count=transport_error_count,
                    ) from None
                self._sleep_for_retry(collector, context, attempt, None)
                continue
            except requests.RequestException as exc:
                raise SteamClientError(
                    f"{collector} non-retryable request failure at {endpoint}: "
                    f"{type(exc).__name__}.",
                    retry_count=attempt,
                    retryable_status_codes=tuple(retryable_status_codes),
                    transport_error_count=transport_error_count,
                ) from None

            status_code = response.status_code
            self.logger.info(
                "collector=%s context=%s http_status=%s retry=%s",
                collector,
                context,
                status_code,
                attempt,
            )
            if status_code in RETRYABLE_STATUS_CODES:
                retryable_status_codes.append(status_code)
                if attempt >= self.max_retries:
                    raise SteamClientError(
                        f"{collector} received HTTP {status_code} after "
                        f"{attempt + 1} attempts at {endpoint}.",
                        retry_count=attempt,
                        retryable_status_codes=tuple(retryable_status_codes),
                        transport_error_count=transport_error_count,
                    )
                self._sleep_for_retry(
                    collector,
                    context,
                    attempt,
                    response.headers.get("Retry-After"),
                )
                continue
            if not 200 <= status_code < 300:
                raise SteamClientError(
                    f"{collector} received non-retryable HTTP {status_code} "
                    f"at {endpoint}.",
                    retry_count=attempt,
                    retryable_status_codes=tuple(retryable_status_codes),
                    transport_error_count=transport_error_count,
                )

            try:
                payload = response.json()
            except requests.exceptions.JSONDecodeError:
                raise SteamClientError(
                    f"{collector} returned invalid JSON at {endpoint}."
                ) from None
            if not isinstance(payload, dict):
                raise SteamClientError(
                    f"{collector} returned a non-object JSON payload at {endpoint}."
                )
            return JSONResponse(
                payload,
                status_code,
                requested_at,
                retry_count=attempt,
                retryable_status_codes=tuple(retryable_status_codes),
                elapsed_seconds=time.monotonic() - request_started_at,
                transport_error_count=transport_error_count,
            )

        raise SteamClientError(f"{collector} exhausted retries at {endpoint}.")

    def _sleep_for_retry(
        self,
        collector: str,
        context: str,
        attempt: int,
        retry_after: str | None,
    ) -> None:
        backoff = self.backoff_base_seconds * (2**attempt)
        if retry_after:
            try:
                backoff = max(backoff, float(retry_after))
            except ValueError:
                pass
        self.logger.warning(
            "collector=%s context=%s retry=%s backoff_seconds=%.2f",
            collector,
            context,
            attempt + 1,
            backoff,
        )
        time.sleep(backoff)

    def close(self) -> None:
        self.session.close()

    def __enter__(self) -> SteamClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
