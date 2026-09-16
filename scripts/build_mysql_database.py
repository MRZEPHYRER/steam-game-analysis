"""Build or audit the Step 3C MySQL analytical database."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.mysql_database import (  # noqa: E402
    DatabaseBuildError,
    DatabaseConfig,
    build_database,
    render_report,
)


REPORT_PATH = Path("reports/step3c_mysql_database_report.md")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build or validate steam_game_analysis without exposing credentials."
    )
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="Explicitly drop and rebuild only the known Step 3C schema objects.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Required confirmation for --rebuild.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.rebuild and not args.yes:
        print("ERROR: --rebuild requires --yes.", file=sys.stderr)
        return 2
    try:
        config = DatabaseConfig.from_environment()
        action, audit = build_database(config, rebuild=args.rebuild)
    except DatabaseBuildError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(render_report(action, audit), encoding="utf-8")
    print(f"Step 3C database audit: PASS ({action})")
    print(f"Report: {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
