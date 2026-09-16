"""Small dependency-free single-line console progress display."""

from __future__ import annotations

import sys
import time
from collections.abc import Callable
from typing import TextIO


def format_duration(seconds: float | None) -> str:
    """Format a non-negative duration as HH:MM:SS or an unknown placeholder."""
    if seconds is None:
        return "--:--:--"
    whole_seconds = max(0, int(seconds))
    hours, remainder = divmod(whole_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


class ConsoleProgress:
    """Render average throughput and ETA on one carriage-returned console line."""

    def __init__(
        self,
        total: int,
        *,
        label: str = "appdetails",
        width: int = 24,
        refresh_seconds: float = 0.2,
        stream: TextIO | None = None,
        clock: Callable[[], float] = time.monotonic,
        enabled: bool = True,
    ) -> None:
        self.total = total
        self.label = label
        self.width = width
        self.refresh_seconds = refresh_seconds
        self.stream = stream or sys.stdout
        self.clock = clock
        self.enabled = enabled
        self.processed = 0
        self.started_at: float | None = None
        self.last_rendered_at: float | None = None
        self.last_line_length = 0

    def __enter__(self) -> ConsoleProgress:
        self.started_at = self.clock()
        self._render({}, force=True)
        return self

    def update(self, processed: int, **counters: int) -> None:
        self.processed = processed
        self._render(counters, force=processed >= self.total)

    def _render(self, counters: dict[str, int], *, force: bool) -> None:
        if not self.enabled:
            return
        now = self.clock()
        if (
            not force
            and self.last_rendered_at is not None
            and now - self.last_rendered_at < self.refresh_seconds
        ):
            return
        started_at = self.started_at if self.started_at is not None else now
        elapsed = max(0.0, now - started_at)
        rate = self.processed / elapsed if elapsed > 0 else 0.0
        remaining = max(0, self.total - self.processed)
        eta = remaining / rate if rate > 0 else None
        fraction = self.processed / self.total if self.total else 1.0
        filled = min(self.width, int(self.width * fraction))
        bar = "#" * filled + "-" * (self.width - filled)
        postfix = " ".join(
            f"{name}={value}"
            for name, value in counters.items()
        )
        line = (
            f"{self.label} |{bar}| {fraction:6.1%} "
            f"{self.processed}/{self.total} "
            f"[{format_duration(elapsed)}<{format_duration(eta)}, "
            f"{rate:.2f} app/s"
        )
        if postfix:
            line += f", {postfix}"
        line += "]"
        padding = " " * max(0, self.last_line_length - len(line))
        self.stream.write(f"\r{line}{padding}")
        self.stream.flush()
        self.last_line_length = len(line)
        self.last_rendered_at = now

    def close(self) -> None:
        if self.enabled:
            self.stream.write("\n")
            self.stream.flush()

    def __exit__(self, *_: object) -> None:
        self.close()
