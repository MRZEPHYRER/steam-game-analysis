"""Frozen-source loading and transactional MySQL analytical database build."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

import pandas as pd
import pymysql
from dotenv import load_dotenv

from config.settings import (
    FROZEN_INPUT_SHA256,
    GAME_GENRES_PATH,
    GAMES_PATH,
    REVIEW_SNAPSHOTS_PATH,
    REVIEW_SNAPSHOT_SHA256,
)
from src.review_full import sha256_file
from src.reviews import review_request_params


EXPECTED_COUNTS = {
    "games": 3_000,
    "genres": 13,
    "game_genres": 8_796,
    "review_snapshots": 3_000,
    "price_snapshots": 3_000,
    "collection_runs": 2,
    "vw_game_analysis": 3_000,
    "vw_game_genres": 8_796,
    "vw_model_sample_20": 844,
}
EXPECTED_THRESHOLDS = {10: 1_139, 20: 844, 50: 551}
EXPECTED_MARKET = {
    "free_games": 402,
    "paid_games": 2_598,
    "windows_games": 2_999,
    "mac_games": 439,
    "linux_games": 363,
    "missing_developer": 0,
    "missing_publisher": 3,
}
EXPECTED_PRICE = {
    "priced_rows": 2_597,
    "missing_price_rows": 403,
    "usd_rows": 2_597,
    "negative_price_rows": 0,
    "current_above_list_rows": 0,
}
CORE_TABLES = [
    "collection_runs",
    "price_snapshots",
    "review_snapshots",
    "game_genres",
    "genres",
    "games",
]
VIEWS = ["vw_model_sample_20", "vw_game_genres", "vw_game_analysis"]


class DatabaseBuildError(RuntimeError):
    """A source, configuration, load, or database audit failed."""


@dataclass(frozen=True, slots=True)
class DatabaseConfig:
    host: str
    port: int
    database: str
    user: str
    password: str = field(repr=False)

    @classmethod
    def from_environment(cls, *, load_env_file: bool = True) -> "DatabaseConfig":
        if load_env_file:
            load_dotenv(override=False)
        names = [
            "MYSQL_HOST",
            "MYSQL_PORT",
            "MYSQL_DATABASE",
            "MYSQL_USER",
            "MYSQL_PASSWORD",
        ]
        values = {name: os.getenv(name, "") for name in names}
        missing = [name for name, value in values.items() if not value]
        if missing:
            raise DatabaseBuildError(
                "Missing required MySQL environment variables: "
                + ", ".join(missing)
            )
        try:
            port = int(values["MYSQL_PORT"])
        except ValueError as exc:
            raise DatabaseBuildError("MYSQL_PORT must be an integer.") from exc
        if not 1 <= port <= 65_535:
            raise DatabaseBuildError("MYSQL_PORT is outside 1..65535.")
        if values["MYSQL_DATABASE"] != "steam_game_analysis":
            raise DatabaseBuildError(
                "MYSQL_DATABASE must be steam_game_analysis for this project."
            )
        return cls(
            host=values["MYSQL_HOST"],
            port=port,
            database=values["MYSQL_DATABASE"],
            user=values["MYSQL_USER"],
            password=values["MYSQL_PASSWORD"],
        )

    def connect_kwargs(self) -> dict[str, Any]:
        return {
            "host": self.host,
            "port": self.port,
            "database": self.database,
            "user": self.user,
            "password": self.password,
            "charset": "utf8mb4",
            "autocommit": False,
            "cursorclass": pymysql.cursors.DictCursor,
        }


@dataclass(frozen=True, slots=True)
class SourceBundle:
    games: pd.DataFrame
    game_genres: pd.DataFrame
    reviews: pd.DataFrame
    hashes: dict[str, str]


def _read_csv_strings(path: Path) -> pd.DataFrame:
    return pd.read_csv(path, dtype=str, keep_default_na=False, low_memory=False)


def _as_int(value: str, *, nullable: bool = False) -> int | None:
    if value == "" and nullable:
        return None
    try:
        number = Decimal(value)
    except Exception as exc:
        raise DatabaseBuildError(f"Invalid integer source value: {value!r}.") from exc
    if number != number.to_integral_value():
        raise DatabaseBuildError(f"Non-integer source value: {value!r}.")
    return int(number)


def _as_bool(value: str, *, nullable: bool = False) -> bool | None:
    if value == "" and nullable:
        return None
    normalized = value.casefold()
    if normalized in {"true", "1"}:
        return True
    if normalized in {"false", "0"}:
        return False
    raise DatabaseBuildError(f"Invalid boolean source value: {value!r}.")


def _as_decimal(value: str) -> Decimal | None:
    return None if value == "" else Decimal(value)


def _as_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise DatabaseBuildError(f"Invalid source date: {value!r}.") from exc


def _as_datetime(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise DatabaseBuildError(f"Invalid source timestamp: {value!r}.") from exc
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _as_json_array(value: str, *, nullable: bool = False) -> str | None:
    if value == "" and nullable:
        return None
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise DatabaseBuildError("Developer/publisher value is invalid JSON.") from exc
    if not isinstance(parsed, list) or any(
        not isinstance(item, str) for item in parsed
    ):
        raise DatabaseBuildError("Developer/publisher JSON must be a string array.")
    return json.dumps(parsed, ensure_ascii=False, separators=(",", ":"))


def load_and_validate_sources() -> SourceBundle:
    """Validate the three frozen CSVs and return lossless string frames."""
    expected_hashes = {
        GAMES_PATH: FROZEN_INPUT_SHA256[GAMES_PATH],
        GAME_GENRES_PATH: FROZEN_INPUT_SHA256[GAME_GENRES_PATH],
        REVIEW_SNAPSHOTS_PATH: REVIEW_SNAPSHOT_SHA256,
    }
    actual_hashes = {str(path): sha256_file(path) for path in expected_hashes}
    drift = [
        str(path)
        for path, expected in expected_hashes.items()
        if actual_hashes[str(path)] != expected
    ]
    if drift:
        raise DatabaseBuildError(
            "Frozen source hash mismatch; import blocked: " + ", ".join(drift)
        )
    games = _read_csv_strings(GAMES_PATH)
    genres = _read_csv_strings(GAME_GENRES_PATH)
    reviews = _read_csv_strings(REVIEW_SNAPSHOTS_PATH)
    if len(games) != 3_000 or games["appid"].nunique() != 3_000:
        raise DatabaseBuildError("games.csv must contain 3,000 unique AppIDs.")
    if len(reviews) != 3_000 or reviews["appid"].nunique() != 3_000:
        raise DatabaseBuildError(
            "review_snapshots.csv must contain 3,000 unique AppIDs."
        )
    game_ids = set(games["appid"])
    if set(reviews["appid"]) != game_ids:
        raise DatabaseBuildError("Review AppID coverage differs from games.csv.")
    if len(genres) != 8_796:
        raise DatabaseBuildError("game_genres.csv must contain 8,796 rows.")
    if genres.duplicated(["appid", "genre_id"]).any():
        raise DatabaseBuildError("game_genres.csv contains duplicate keys.")
    if not set(genres["appid"]).issubset(game_ids):
        raise DatabaseBuildError("game_genres.csv contains external AppIDs.")
    mapping = genres[["genre_id", "genre_name"]].drop_duplicates()
    if (
        mapping["genre_id"].nunique() != 13
        or mapping["genre_name"].nunique() != 13
        or (mapping.groupby("genre_id")["genre_name"].nunique() != 1).any()
        or (mapping.groupby("genre_name")["genre_id"].nunique() != 1).any()
    ):
        raise DatabaseBuildError("Genre IDs and names are not one-to-one.")
    for field in ["developer", "publisher"]:
        nullable = field == "publisher"
        for value in games[field]:
            _as_json_array(value, nullable=nullable)
    totals = reviews["total_reviews"].map(_as_int)
    positives = reviews["positive_reviews"].map(_as_int)
    negatives = reviews["negative_reviews"].map(_as_int)
    if (totals < 0).any() or (positives < 0).any() or (negatives < 0).any():
        raise DatabaseBuildError("Review counts must be non-negative.")
    if not (positives + negatives).eq(totals).all():
        raise DatabaseBuildError("Review count identity failed before import.")
    thresholds = {
        threshold: int(totals.ge(threshold).sum())
        for threshold in EXPECTED_THRESHOLDS
    }
    if thresholds != EXPECTED_THRESHOLDS:
        raise DatabaseBuildError(
            f"Review threshold counts changed: {thresholds}."
        )
    zero = totals.eq(0)
    if (
        not reviews.loc[zero, "positive_rate"].eq("").all()
        or not positives[zero].eq(0).all()
        or not negatives[zero].eq(0).all()
    ):
        raise DatabaseBuildError("Zero-review semantics failed before import.")
    if reviews.loc[~zero, "positive_rate"].eq("").any():
        raise DatabaseBuildError("Nonzero review rows must have positive_rate.")
    for field, expected in {
        "review_language": "all",
        "review_purchase_type": "steam",
        "review_type": "all",
        "filter_offtopic_activity": "1",
    }.items():
        if set(reviews[field]) != {expected}:
            raise DatabaseBuildError(f"Research definition changed in {field}.")
    market = {
        "free_games": int(games["is_free"].str.casefold().eq("true").sum()),
        "paid_games": int(games["is_free"].str.casefold().eq("false").sum()),
        "windows_games": int(games["platform_windows"].str.casefold().eq("true").sum()),
        "mac_games": int(games["platform_mac"].str.casefold().eq("true").sum()),
        "linux_games": int(games["platform_linux"].str.casefold().eq("true").sum()),
        "missing_developer": int(games["developer"].eq("").sum()),
        "missing_publisher": int(games["publisher"].eq("").sum()),
    }
    if market != EXPECTED_MARKET:
        raise DatabaseBuildError(f"Frozen market counts changed: {market}.")
    list_price = games["list_price_cents"].map(
        lambda value: _as_int(value, nullable=True)
    )
    current_price = games["current_price_cents"].map(
        lambda value: _as_int(value, nullable=True)
    )
    price = {
        "priced_rows": int(list_price.notna().sum()),
        "missing_price_rows": int(list_price.isna().sum()),
        "usd_rows": int(games["price_currency"].eq("USD").sum()),
        "negative_price_rows": int(
            ((list_price < 0) | (current_price < 0)).fillna(False).sum()
        ),
        "current_above_list_rows": int(
            (current_price > list_price).fillna(False).sum()
        ),
    }
    if price != EXPECTED_PRICE:
        raise DatabaseBuildError(f"Frozen price checks changed: {price}.")
    if len(set(genres["appid"])) != 3_000:
        raise DatabaseBuildError("Every sampled game must have at least one genre.")
    return SourceBundle(games, genres, reviews, actual_hashes)


def source_rows(bundle: SourceBundle) -> dict[str, list[tuple[Any, ...]]]:
    """Convert frozen CSV strings to MySQL-ready rows without lossy inference."""
    games: list[tuple[Any, ...]] = []
    prices: list[tuple[Any, ...]] = []
    for row in bundle.games.to_dict("records"):
        appid = _as_int(row["appid"])
        collected_at = _as_datetime(row["metadata_collected_at"])
        games.append(
            (
                appid,
                _as_int(row["sample_id"]),
                row["name"],
                _as_date(row["release_date"]),
                row["release_month"],
                _as_json_array(row["developer"]),
                _as_json_array(row["publisher"], nullable=True),
                _as_bool(row["is_free"]),
                _as_bool(row["platform_windows"]),
                _as_bool(row["platform_mac"]),
                _as_bool(row["platform_linux"]),
                _as_bool(row["is_early_access"], nullable=True),
                collected_at,
                _as_int(row["sample_seed"]),
                row["sampling_stratum"],
                row["sampling_source"],
            )
        )
        prices.append(
            (
                appid,
                _as_int(row["list_price_cents"], nullable=True),
                _as_int(row["current_price_cents"], nullable=True),
                _as_int(row["discount_percent"], nullable=True),
                row["price_currency"] or None,
                collected_at,
            )
        )

    genre_pairs = (
        bundle.game_genres[["genre_id", "genre_name"]]
        .drop_duplicates()
        .sort_values("genre_id", key=lambda values: values.map(int))
    )
    genres = [
        (_as_int(row.genre_id), row.genre_name)
        for row in genre_pairs.itertuples(index=False)
    ]
    game_genres = [
        (_as_int(row.appid), _as_int(row.genre_id))
        for row in bundle.game_genres.itertuples(index=False)
    ]
    reviews = [
        (
            _as_int(row["appid"]),
            _as_int(row["total_reviews"]),
            _as_int(row["positive_reviews"]),
            _as_int(row["negative_reviews"]),
            _as_decimal(row["positive_rate"]),
            _as_int(row["review_score"], nullable=True),
            row["review_score_desc"] or None,
            row["review_language"],
            row["review_purchase_type"],
            row["review_type"],
            _as_bool(row["filter_offtopic_activity"]),
            _as_int(row["day_range"]),
            _as_datetime(row["review_collected_at"]),
            row["review_status"],
            row["schema_error"] or None,
            _as_int(row["http_status"], nullable=True),
            _as_int(row["request_retry_count"], nullable=True),
            _as_decimal(row["request_latency_seconds"]),
            _as_int(row["http_429_count"], nullable=True),
            _as_int(row["http_5xx_count"], nullable=True),
            _as_int(row["transport_error_count"], nullable=True),
        )
        for row in bundle.reviews.to_dict("records")
    ]
    metadata_completed = max(row[12] for row in games)
    review_completed = max(row[12] for row in reviews)
    runs = [
        (
            "metadata_snapshot_step3a",
            "steam_store_metadata",
            "games.csv + game_genres.csv",
            None,
            metadata_completed,
            len(games),
            "success",
            None,
            bundle.hashes[str(GAMES_PATH)].upper(),
            "game_genres_sha256=" + bundle.hashes[str(GAME_GENRES_PATH)].upper(),
        ),
        (
            "review_snapshot_step3b",
            "steam_reviews",
            "review_snapshots.csv",
            None,
            review_completed,
            len(reviews),
            "success",
            json.dumps(review_request_params(), ensure_ascii=False, sort_keys=True),
            bundle.hashes[str(REVIEW_SNAPSHOTS_PATH)].upper(),
            "Validated full 3,000-game review snapshot.",
        ),
    ]
    return {
        "games": games,
        "genres": genres,
        "game_genres": game_genres,
        "review_snapshots": reviews,
        "price_snapshots": prices,
        "collection_runs": runs,
    }


INSERT_SQL = {
    "games": """INSERT INTO games (
      appid, sample_id, name, release_date, release_month, developer, publisher,
      is_free, platform_windows, platform_mac, platform_linux, is_early_access,
      metadata_collected_at, sample_seed, sampling_stratum, sampling_source
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
    "genres": "INSERT INTO genres (genre_id, genre_name) VALUES (%s, %s)",
    "game_genres": "INSERT INTO game_genres (appid, genre_id) VALUES (%s, %s)",
    "review_snapshots": """INSERT INTO review_snapshots (
      appid, total_reviews, positive_reviews, negative_reviews, positive_rate,
      review_score, review_score_desc, review_language, review_purchase_type,
      review_type, filter_offtopic_activity, day_range, review_collected_at,
      review_status, schema_error, http_status, request_retry_count,
      request_latency_seconds, http_429_count, http_5xx_count,
      transport_error_count
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
    "price_snapshots": """INSERT INTO price_snapshots (
      appid, list_price_cents, current_price_cents, discount_percent,
      price_currency, price_collected_at
    ) VALUES (%s, %s, %s, %s, %s, %s)""",
    "collection_runs": """INSERT INTO collection_runs (
      run_id, source_type, dataset_name, started_at, completed_at, row_count,
      status, query_contract, dataset_sha256, notes
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
}


def split_sql_statements(text: str) -> list[str]:
    """Split this project's plain DDL files while ignoring comment-only lines."""
    cleaned = "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("--")
    )
    return [
        statement.strip()
        for statement in cleaned.split(";")
        if statement.strip()
    ]


def execute_sql_file(connection: Any, path: Path) -> None:
    with connection.cursor() as cursor:
        for statement in split_sql_statements(path.read_text(encoding="utf-8")):
            cursor.execute(statement)


def schema_objects(connection: Any) -> tuple[set[str], set[str]]:
    query = """SELECT TABLE_NAME, TABLE_TYPE
               FROM information_schema.TABLES
               WHERE TABLE_SCHEMA = DATABASE()"""
    with connection.cursor() as cursor:
        cursor.execute(query)
        records = cursor.fetchall()
    tables = {
        row["TABLE_NAME"]
        for row in records
        if row["TABLE_TYPE"] == "BASE TABLE"
    }
    views = {
        row["TABLE_NAME"]
        for row in records
        if row["TABLE_TYPE"] == "VIEW"
    }
    return tables, views


def _scalar(connection: Any, query: str) -> int:
    with connection.cursor() as cursor:
        cursor.execute(query)
        row = cursor.fetchone()
    return int(next(iter(row.values())))


def audit_database(connection: Any) -> dict[str, Any]:
    """Return and enforce the complete Step 3C database acceptance audit."""
    counts = {
        name: _scalar(connection, f"SELECT COUNT(*) FROM `{name}`")
        for name in EXPECTED_COUNTS
    }
    thresholds = {
        threshold: _scalar(
            connection,
            "SELECT COUNT(*) FROM review_snapshots "
            f"WHERE total_reviews >= {threshold}",
        )
        for threshold in EXPECTED_THRESHOLDS
    }
    market_queries = {
        "free_games": "SELECT COUNT(*) FROM games WHERE is_free = 1",
        "paid_games": "SELECT COUNT(*) FROM games WHERE is_free = 0",
        "windows_games": "SELECT COUNT(*) FROM games WHERE platform_windows = 1",
        "mac_games": "SELECT COUNT(*) FROM games WHERE platform_mac = 1",
        "linux_games": "SELECT COUNT(*) FROM games WHERE platform_linux = 1",
        "missing_developer": "SELECT COUNT(*) FROM games WHERE developer IS NULL",
        "missing_publisher": "SELECT COUNT(*) FROM games WHERE publisher IS NULL",
    }
    market = {
        name: _scalar(connection, query)
        for name, query in market_queries.items()
    }
    price_queries = {
        "priced_rows": "SELECT COUNT(*) FROM price_snapshots WHERE list_price_cents IS NOT NULL",
        "missing_price_rows": "SELECT COUNT(*) FROM price_snapshots WHERE list_price_cents IS NULL",
        "usd_rows": "SELECT COUNT(*) FROM price_snapshots WHERE price_currency = 'USD'",
        "negative_price_rows": """SELECT COUNT(*) FROM price_snapshots
          WHERE list_price_cents < 0 OR current_price_cents < 0""",
        "current_above_list_rows": """SELECT COUNT(*) FROM price_snapshots
          WHERE current_price_cents > list_price_cents""",
    }
    price = {
        name: _scalar(connection, query)
        for name, query in price_queries.items()
    }
    integrity_queries = {
        "game_genre_orphans": """SELECT COUNT(*) FROM game_genres gg
          LEFT JOIN games g ON g.appid=gg.appid
          LEFT JOIN genres ge ON ge.genre_id=gg.genre_id
          WHERE g.appid IS NULL OR ge.genre_id IS NULL""",
        "review_orphans": """SELECT COUNT(*) FROM review_snapshots r
          LEFT JOIN games g ON g.appid=r.appid WHERE g.appid IS NULL""",
        "price_orphans": """SELECT COUNT(*) FROM price_snapshots p
          LEFT JOIN games g ON g.appid=p.appid WHERE g.appid IS NULL""",
        "review_identity_failures": """SELECT COUNT(*) FROM review_snapshots
          WHERE positive_reviews + negative_reviews <> total_reviews""",
        "zero_review_failures": """SELECT COUNT(*) FROM review_snapshots
          WHERE total_reviews=0 AND (
            positive_reviews<>0 OR negative_reviews<>0 OR positive_rate IS NOT NULL
          )""",
        "positive_rate_failures": """SELECT COUNT(*) FROM review_snapshots
          WHERE total_reviews>0 AND (
            positive_rate IS NULL OR positive_rate<0 OR positive_rate>1
          )""",
        "games_without_genres": """SELECT COUNT(*) FROM games g
          LEFT JOIN game_genres gg ON gg.appid=g.appid WHERE gg.appid IS NULL""",
        "duplicate_game_genres": """SELECT COUNT(*) FROM (
          SELECT appid,genre_id FROM game_genres
          GROUP BY appid,genre_id HAVING COUNT(*)>1
        ) d""",
    }
    integrity = {
        name: _scalar(connection, query)
        for name, query in integrity_queries.items()
    }
    failures: list[str] = []
    if counts != EXPECTED_COUNTS:
        failures.append(f"counts={counts}")
    if thresholds != EXPECTED_THRESHOLDS:
        failures.append(f"thresholds={thresholds}")
    if market != EXPECTED_MARKET:
        failures.append(f"market={market}")
    if price != EXPECTED_PRICE:
        failures.append(f"price={price}")
    nonzero = {name: value for name, value in integrity.items() if value != 0}
    if nonzero:
        failures.append(f"integrity={nonzero}")
    if failures:
        raise DatabaseBuildError("Database audit failed: " + "; ".join(failures))
    return {
        "counts": counts,
        "thresholds": thresholds,
        "market": market,
        "price": price,
        "integrity": integrity,
    }


def _drop_schema_objects(connection: Any) -> None:
    with connection.cursor() as cursor:
        for view in VIEWS:
            cursor.execute(f"DROP VIEW IF EXISTS `{view}`")
        for table in CORE_TABLES:
            cursor.execute(f"DROP TABLE IF EXISTS `{table}`")


def build_database(
    config: DatabaseConfig,
    *,
    rebuild: bool = False,
) -> tuple[str, dict[str, Any]]:
    """Build once or audit an already complete DB; never silently replace it."""
    bundle = load_and_validate_sources()
    rows = source_rows(bundle)
    try:
        connection = pymysql.connect(**config.connect_kwargs())
    except pymysql.MySQLError as exc:
        code = exc.args[0] if exc.args else "unknown"
        raise DatabaseBuildError(
            f"MySQL connection failed ({exc.__class__.__name__}, code={code})."
        ) from exc
    try:
        tables, views = schema_objects(connection)
        known_tables = tables.intersection(CORE_TABLES)
        known_views = views.intersection(VIEWS)
        if rebuild:
            _drop_schema_objects(connection)
            connection.commit()
            known_tables, known_views = set(), set()
        if known_tables == set(CORE_TABLES) and known_views == set(VIEWS):
            return "reused", audit_database(connection)
        if known_tables or known_views:
            raise DatabaseBuildError(
                "Database contains a partial Step 3C schema. Use --rebuild --yes "
                "only after confirming it is safe to replace."
            )
        execute_sql_file(connection, Path("sql/01_create_schema.sql"))
        connection.commit()
        try:
            with connection.cursor() as cursor:
                for name in [
                    "games",
                    "genres",
                    "game_genres",
                    "review_snapshots",
                    "price_snapshots",
                    "collection_runs",
                ]:
                    cursor.executemany(INSERT_SQL[name], rows[name])
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        execute_sql_file(connection, Path("sql/02_create_indexes.sql"))
        connection.commit()
        return "built", audit_database(connection)
    except DatabaseBuildError:
        raise
    except pymysql.MySQLError as exc:
        connection.rollback()
        code = exc.args[0] if exc.args else "unknown"
        raise DatabaseBuildError(
            f"MySQL operation failed ({exc.__class__.__name__}, code={code})."
        ) from exc
    finally:
        connection.close()


def render_report(action: str, audit: dict[str, Any]) -> str:
    """Render a report only from a successful live-database audit result."""
    counts = audit["counts"]
    market = audit["market"]
    price = audit["price"]
    thresholds = audit["thresholds"]
    count_rows = "".join(
        f"| `{name}` | {value:,} |\n"
        for name, value in counts.items()
    )
    return f"""# Step 3C MySQL Analytical Database Report

Generated from an actual successful database audit. Build action: `{action}`.

## Row counts

| Object | Rows |
|---|---:|
{count_rows}
## Acceptance metrics

- Reviews >= 10: {thresholds[10]:,}
- Reviews >= 20: {thresholds[20]:,}
- Reviews >= 50: {thresholds[50]:,}
- Free / paid: {market["free_games"]:,} / {market["paid_games"]:,}
- Windows / macOS / Linux: {market["windows_games"]:,} / {market["mac_games"]:,} / {market["linux_games"]:,}
- Missing developer / publisher: {market["missing_developer"]:,} / {market["missing_publisher"]:,}
- Priced / missing-price snapshots: {price["priced_rows"]:,} / {price["missing_price_rows"]:,}
- USD price snapshots: {price["usd_rows"]:,}
- Negative-price / current-above-list failures: {price["negative_price_rows"]:,} / {price["current_above_list_rows"]:,}

## Integrity

All foreign-key orphan, review identity, zero-review, positive-rate, duplicate-key,
and game-without-genre checks returned zero failures.

## Result

`Step 3C database audit: PASS`
"""
