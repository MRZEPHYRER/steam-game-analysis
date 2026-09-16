from __future__ import annotations

import os
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import pytest

from config.settings import REVIEW_SNAPSHOT_SHA256
from src.mysql_database import (
    CORE_TABLES,
    EXPECTED_COUNTS,
    EXPECTED_MARKET,
    EXPECTED_PRICE,
    EXPECTED_THRESHOLDS,
    VIEWS,
    DatabaseBuildError,
    DatabaseConfig,
    _as_bool,
    _as_datetime,
    _as_decimal,
    _as_int,
    _as_json_array,
    load_and_validate_sources,
    source_rows,
    split_sql_statements,
)
from src.review_full import sha256_file


@pytest.fixture(scope="module")
def frozen_bundle():
    return load_and_validate_sources()


@pytest.fixture(scope="module")
def mysql_rows(frozen_bundle):
    return source_rows(frozen_bundle)


def test_frozen_counts_hash_and_appid_coverage(frozen_bundle):
    assert len(frozen_bundle.games) == 3_000
    assert len(frozen_bundle.game_genres) == 8_796
    assert len(frozen_bundle.reviews) == 3_000
    assert sha256_file(Path("data/processed/review_snapshots.csv")) == REVIEW_SNAPSHOT_SHA256
    games = set(frozen_bundle.games["appid"])
    assert set(frozen_bundle.reviews["appid"]) == games
    assert set(frozen_bundle.game_genres["appid"]) == games


def test_genre_normalization_and_mysql_row_counts(mysql_rows):
    assert {name: len(rows) for name, rows in mysql_rows.items()} == {
        "games": 3_000,
        "genres": 13,
        "game_genres": 8_796,
        "review_snapshots": 3_000,
        "price_snapshots": 3_000,
        "collection_runs": 2,
    }
    assert len({genre_id for genre_id, _ in mysql_rows["genres"]}) == 13
    assert len({genre_name for _, genre_name in mysql_rows["genres"]}) == 13
    assert len(set(mysql_rows["game_genres"])) == 8_796


def test_review_identity_zero_semantics_and_thresholds(mysql_rows):
    reviews = mysql_rows["review_snapshots"]
    assert all(row[2] + row[3] == row[1] for row in reviews)
    zero = [row for row in reviews if row[1] == 0]
    assert zero
    assert all(row[2] == 0 and row[3] == 0 and row[4] is None for row in zero)
    assert {
        threshold: sum(row[1] >= threshold for row in reviews)
        for threshold in EXPECTED_THRESHOLDS
    } == EXPECTED_THRESHOLDS


def test_market_and_price_sanity(frozen_bundle, mysql_rows):
    games = frozen_bundle.games
    market = {
        "free_games": int(games["is_free"].eq("True").sum()),
        "paid_games": int(games["is_free"].eq("False").sum()),
        "windows_games": int(games["platform_windows"].eq("True").sum()),
        "mac_games": int(games["platform_mac"].eq("True").sum()),
        "linux_games": int(games["platform_linux"].eq("True").sum()),
        "missing_developer": int(games["developer"].eq("").sum()),
        "missing_publisher": int(games["publisher"].eq("").sum()),
    }
    assert market == EXPECTED_MARKET
    prices = mysql_rows["price_snapshots"]
    assert all(row[1] is None or row[1] >= 0 for row in prices)
    assert all(row[2] is None or row[2] >= 0 for row in prices)
    assert all(row[3] is None or 0 <= row[3] <= 100 for row in prices)
    assert EXPECTED_PRICE == {
        "priced_rows": 2_597,
        "missing_price_rows": 403,
        "usd_rows": 2_597,
        "negative_price_rows": 0,
        "current_above_list_rows": 0,
    }


def test_null_and_type_conversion_contract():
    assert _as_int("", nullable=True) is None
    assert _as_bool("", nullable=True) is None
    assert _as_decimal("") is None
    assert _as_decimal("0.125") == Decimal("0.125")
    assert _as_json_array("", nullable=True) is None
    assert _as_json_array('["A", "B"]') == '["A","B"]'
    assert _as_datetime("2026-01-01T08:00:00+08:00") == datetime(2026, 1, 1)
    with pytest.raises(DatabaseBuildError):
        _as_int("1.5")


def test_env_parsing_and_secret_repr(monkeypatch):
    values = {
        "MYSQL_HOST": "localhost",
        "MYSQL_PORT": "3306",
        "MYSQL_DATABASE": "steam_game_analysis",
        "MYSQL_USER": "steam_analyst",
        "MYSQL_PASSWORD": "unit-test-secret",
    }
    for name, value in values.items():
        monkeypatch.setenv(name, value)
    config = DatabaseConfig.from_environment(load_env_file=False)
    assert config.port == 3306
    assert config.user == "steam_analyst"
    assert "unit-test-secret" not in repr(config)
    assert config.connect_kwargs()["charset"] == "utf8mb4"


def test_missing_env_is_safely_rejected(monkeypatch):
    for name in [
        "MYSQL_HOST", "MYSQL_PORT", "MYSQL_DATABASE", "MYSQL_USER", "MYSQL_PASSWORD"
    ]:
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(DatabaseBuildError, match="Missing required"):
        DatabaseConfig.from_environment(load_env_file=False)


def test_sql_files_fix_schema_constraints_indexes_and_views():
    schema = Path("sql/01_create_schema.sql").read_text(encoding="utf-8")
    indexes = Path("sql/02_create_indexes.sql").read_text(encoding="utf-8")
    validation = Path("sql/03_validation_queries.sql").read_text(encoding="utf-8")
    assert all(f"CREATE TABLE IF NOT EXISTS {name}" in schema for name in CORE_TABLES)
    assert schema.count("FOREIGN KEY") == 4
    assert "positive_reviews + negative_reviews = total_reviews" in schema
    assert all(f"VIEW {name}" in indexes for name in VIEWS)
    for fragment in [
        "games (release_month)", "games (is_free)",
        "review_snapshots (total_reviews)", "review_snapshots (positive_rate)",
        "review_snapshots (review_score)", "price_snapshots (current_price_cents)",
        "game_genres (genre_id)",
    ]:
        assert fragment in indexes
    assert "games_without_genres" in validation


def test_database_acceptance_constants_are_frozen():
    assert EXPECTED_COUNTS == {
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


def test_sql_splitter_and_explicit_rebuild_contract():
    assert split_sql_statements("-- comment\nSELECT 1;\nSELECT 2;") == [
        "SELECT 1", "SELECT 2"
    ]
    script = Path("scripts/build_mysql_database.py").read_text(encoding="utf-8")
    assert "args.rebuild and not args.yes" in script
    assert "build_database(config, rebuild=args.rebuild)" in script


def test_no_committed_real_credentials():
    example = Path(".env.example").read_text(encoding="utf-8")
    assert "MYSQL_PASSWORD=\n" in example
    admin = Path("sql/00_admin_setup.sql").read_text(encoding="utf-8")
    assert "<SET_PASSWORD_MANUALLY>" in admin
    assert os.path.basename(".env") not in [path.name for path in Path(".").glob("*.example")]


def test_r_and_quarto_use_root_discovery_and_scoped_connections():
    helper = Path("R/db_connect.R").read_text(encoding="utf-8")
    smoke = Path("R/00_db_smoke_test.R").read_text(encoding="utf-8")
    quarto = Path("reports/00_environment_check.qmd").read_text(encoding="utf-8")
    assert "find_project_root <- function()" in helper
    assert 'file.path(find_project_root(), ".env")' in helper
    assert 'file.path(current, "R", "db_connect.R")' in helper
    assert 'file.path(current, "sql", "01_create_schema.sql")' in helper
    assert "with_steam_db <- function(code)" in helper
    assert "on.exit({" in helper
    assert "DBI::dbDisconnect(con)" in helper
    assert "with_steam_db(function(con)" in smoke
    assert "with_steam_db(function(con)" in quarto
    assert "(SELECT COUNT(*) FROM games)" in quarto
    assert "(SELECT COUNT(*) FROM review_snapshots)" in quarto
    assert "(SELECT COUNT(*) FROM vw_model_sample_20)" in quarto
    combined = helper + smoke + quarto
    assert "C:\\Users\\TOMZOU" not in combined
    assert "MYSQL_PASSWORD=" not in combined
