"""Execute all named Step 4A SQL queries and export deterministic CSVs."""

from __future__ import annotations

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.mysql_database import DatabaseBuildError, DatabaseConfig  # noqa: E
from src.sql_analysis import SqlAnalysisError, run_sql_analysis  # noqa: E402


def main() -> int:
    try:
        config = DatabaseConfig.from_environment()
        results = run_sql_analysis(config)
    except (DatabaseBuildError, SqlAnalysisError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"Step 4A SQL analysis: PASS ({len(results)} queries)")
    print("Manifest: reports/step4a_sql_analysis_manifest.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
