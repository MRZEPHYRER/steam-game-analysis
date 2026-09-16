from __future__ import annotations

from pathlib import Path

from src.io_utils import atomic_write_json
from src.search_collector import (
    default_search_checkpoint,
    load_search_checkpoint,
    reset_search_state,
)


def test_checkpoint_round_trip_restores_state(tmp_path: Path) -> None:
    checkpoint_path = tmp_path / "checkpoint.json"
    checkpoint = default_search_checkpoint()
    checkpoint.update({"next_start": 150, "pages_completed": 3})
    atomic_write_json(checkpoint_path, checkpoint)
    assert load_search_checkpoint(checkpoint_path) == checkpoint


def test_restart_clears_only_known_search_state(tmp_path: Path) -> None:
    raw_dir = tmp_path / "raw"
    raw_dir.mkdir()
    generated = raw_dir / "search_000001.json"
    unrelated = raw_dir / "keep.json"
    checkpoint = tmp_path / "checkpoint.json"
    output = tmp_path / "candidate.csv"
    for path in (generated, unrelated, checkpoint):
        path.write_text("{}", encoding="utf-8")
    output.write_text("appid\n", encoding="utf-8")

    reset_search_state(raw_dir, checkpoint, [output])

    assert not generated.exists()
    assert not checkpoint.exists()
    assert not output.exists()
    assert unrelated.exists()

