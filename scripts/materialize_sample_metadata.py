"""Build Step 3A final-sample metadata outputs from frozen local files."""

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config.settings import (  # noqa: E402
    APPDETAILS_METADATA_PATH,
    ELIGIBLE_SAMPLING_FRAME_PATH,
)
from src.metadata_materialization import run_step3a_materialization  # noqa: E402


def main() -> int:
    games, genres = run_step3a_materialization(
        metadata_path=APPDETAILS_METADATA_PATH,
        eligible_path=ELIGIBLE_SAMPLING_FRAME_PATH,
    )
    print("[OK] Step 3A final sample metadata materialized locally.")
    print(f"games rows: {len(games)}")
    print(f"unique AppIDs: {games['appid'].nunique()}")
    print(f"genre relation rows: {len(genres)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
