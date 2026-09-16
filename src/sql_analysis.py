"""Read-only MySQL SQL-analysis execution and deterministic CSV export."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pandas as pd
import pymysql

from config.settings import PROJECT_ROOT
from src.io_utils import atomic_write_csv, atomic_write_text
from src.mysql_database import DatabaseBuildError, DatabaseConfig, audit_database


ANALYSIS_SQL_DIR = PROJECT_ROOT / "sql" / "analysis"
ANALYSIS_OUTPUT_DIR = PROJECT_ROOT / "data" / "analysis" / "sql"
MANIFEST_PATH = PROJECT_ROOT / "reports" / "step4a_sql_analysis_manifest.md"
FORBIDDEN_SQL = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|REPLACE|CREATE|GRANT|REVOKE|LOAD|CALL|SET)\b",
    flags=re.IGNORECASE,
)
RESULT_MARKER = re.compile(r"^\s*--\s*result:\s*([a-z][a-z0-9_]*)\s*$", re.MULTILINE)
PURPOSE_MARKER = re.compile(r"^\s*--\s*purpose:\s*(.+?)\s*$", re.MULTILINE)


class SqlAnalysisError(RuntimeError):
    """A read-only, query-contract, execution, or export invariant failed."""


@dataclass(frozen=True, slots=True)
class NamedQuery:
    source_path: Path
    name: str
    purpose: str
    sql: str


@dataclass(frozen=True, slots=True)
class QueryResult:
    query: NamedQuery
    frame: pd.DataFrame
    output_path: Path


def _without_line_comments(sql: str) -> str:
    return "\n".join(
        line for line in sql.splitlines() if not line.lstrip().startswith("--")
    ).strip()


def assert_read_only(sql: str) -> None:
    cleaned = _without_line_comments(sql)
    if not re.match(r"^(SELECT|WITH)\b", cleaned, flags=re.IGNORECASE):
        raise SqlAnalysisError("Analysis statements must start with SELECT or WITH.")
    match = FORBIDDEN_SQL.search(cleaned)
    if match:
        raise SqlAnalysisError(
            f"Blocked non-read-only SQL keyword: {match.group(1).upper()}."
        )


def parse_analysis_file(path: Path) -> list[NamedQuery]:
    text = path.read_text(encoding="utf-8")
    queries: list[NamedQuery] = []
    for chunk in text.split(";"):
        if not chunk.strip():
            continue
        result_match = RESULT_MARKER.search(chunk)
        purpose_match = PURPOSE_MARKER.search(chunk)
        if result_match is None or purpose_match is None:
            raise SqlAnalysisError(
                f"Every statement in {path.name} needs result and purpose markers."
            )
        sql = _without_line_comments(chunk)
        assert_read_only(sql)
        queries.append(
            NamedQuery(
                source_path=path,
                name=result_match.group(1),
                purpose=purpose_match.group(1),
                sql=sql,
            )
        )
    if not queries:
        raise SqlAnalysisError(f"No named queries found in {path.name}.")
    return queries


def discover_queries(directory: Path = ANALYSIS_SQL_DIR) -> list[NamedQuery]:
    paths = sorted(directory.glob("[0-9][0-9]_*.sql"))
    if not paths:
        raise SqlAnalysisError(f"No SQL analysis files found in {directory}.")
    queries = [query for path in paths for query in parse_analysis_file(path)]
    names = [query.name for query in queries]
    if len(names) != len(set(names)):
        raise SqlAnalysisError("SQL result names must be unique across analysis files.")
    return queries


def _query_frame(connection: Any, query: NamedQuery) -> pd.DataFrame:
    with connection.cursor() as cursor:
        cursor.execute(query.sql)
        records = cursor.fetchall()
        columns = [column[0] for column in cursor.description or ()]
    return pd.DataFrame(records, columns=columns)


def render_manifest(results: list[QueryResult]) -> str:
    rows = "".join(
        "| `{source}` | {purpose} | `{output}` | {count:,} | PASS |\n".format(
            source=result.query.source_path.relative_to(PROJECT_ROOT).as_posix(),
            purpose=result.query.purpose.replace("|", "\\|"),
            output=result.output_path.relative_to(PROJECT_ROOT).as_posix(),
            count=len(result.frame),
        )
        for result in results
    )
    return f"""# Step 4A SQL Analysis Manifest

All statements were executed inside a MySQL read-only transaction. CSV files
were written only after every query and the post-query database audit passed.

| Query file | Purpose | Output CSV | Rows | Status |
|---|---|---|---:|---|
{rows}
Queries executed: **{len(results)}**

Database mutation guard: **PASS**
"""


def run_sql_analysis(
    config: DatabaseConfig,
    *,
    output_dir: Path = ANALYSIS_OUTPUT_DIR,
    manifest_path: Path = MANIFEST_PATH,
) -> list[QueryResult]:
    queries = discover_queries()
    try:
        connection = pymysql.connect(**config.connect_kwargs())
    except pymysql.MySQLError as exc:
        code = exc.args[0] if exc.args else "unknown"
        raise SqlAnalysisError(
            f"MySQL connection failed ({exc.__class__.__name__}, code={code})."
        ) from exc
    pending: list[QueryResult] = []
    try:
        with connection.cursor() as cursor:
            cursor.execute("SET TRANSACTION READ ONLY")
        connection.begin()
        before = audit_database(connection)
        for query in queries:
            frame = _query_frame(connection, query)
            pending.append(
                QueryResult(query, frame, output_dir / f"{query.name}.csv")
            )
        after = audit_database(connection)
        if before != after:
            raise SqlAnalysisError("Database audit changed during SQL analysis.")
        connection.rollback()
    except (DatabaseBuildError, pymysql.MySQLError) as exc:
        connection.rollback()
        if isinstance(exc, DatabaseBuildError):
            raise SqlAnalysisError(str(exc)) from exc
        code = exc.args[0] if exc.args else "unknown"
        raise SqlAnalysisError(
            f"SQL analysis failed ({exc.__class__.__name__}, code={code})."
        ) from exc
    finally:
        connection.close()
    for result in pending:
        atomic_write_csv(result.output_path, result.frame)
    atomic_write_text(manifest_path, render_manifest(pending))
    return pending
