from __future__ import annotations

from io import StringIO

import pytest

from src.progress import ConsoleProgress, format_duration


class FakeClock:
    def __init__(self, *values: float) -> None:
        self.values = iter(values)

    def __call__(self) -> float:
        return next(self.values)


def test_progress_displays_completion_rate_elapsed_eta_and_counters() -> None:
    output = StringIO()
    progress = ConsoleProgress(
        4,
        stream=output,
        clock=FakeClock(10.0, 10.0, 12.0, 14.0),
        refresh_seconds=0,
    )
    with progress:
        progress.update(2, reused=2, new=0, retried=0, failed=0)
        progress.update(4, reused=2, new=2, retried=0, failed=0)

    rendered = output.getvalue()
    assert "50.0%" in rendered
    assert "2/4" in rendered
    assert "100.0%" in rendered
    assert "4/4" in rendered
    assert "00:00:02<00:00:02" in rendered
    assert "1.00 app/s" in rendered
    assert "reused=2" in rendered
    assert "new=2" in rendered
    assert rendered.endswith("\n")


def test_duration_formatting() -> None:
    assert format_duration(3_661.9) == "01:01:01"
    assert format_duration(None) == "--:--:--"


def test_progress_does_not_swallow_keyboard_interrupt() -> None:
    output = StringIO()
    progress = ConsoleProgress(
        10,
        stream=output,
        clock=FakeClock(0.0, 0.0),
    )
    with pytest.raises(KeyboardInterrupt):
        with progress:
            raise KeyboardInterrupt
    assert output.getvalue().endswith("\n")
