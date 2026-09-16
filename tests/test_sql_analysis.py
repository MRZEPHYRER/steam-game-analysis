from __future__ import annotations

import re
from pathlib import Path

import pandas as pd
import pytest

from src.sql_analysis import (
    ANALYSIS_OUTPUT_DIR,
    ANALYSIS_SQL_DIR,
    MANIFEST_PATH,
    SqlAnalysisError,
    assert_read_only,
    discover_queries,
)


EXPECTED_SQL_FILES = [
    "01_market_overview.sql",
    "02_price_analysis.sql",
    "03_review_volume.sql",
    "04_positive_rate.sql",
    "05_genre_analysis.sql",
    "06_release_month.sql",
    "07_rankings.sql",
    "08_cross_segment_analysis.sql",
    "09_model_sample_profile.sql",
]


def read_result(name: str) -> pd.DataFrame:
    return pd.read_csv(ANALYSIS_OUTPUT_DIR / f"{name}.csv")


def test_analysis_files_exist_and_all_queries_are_read_only():
    assert [path.name for path in sorted(ANALYSIS_SQL_DIR.glob("*.sql"))] == EXPECTED_SQL_FILES
    queries = discover_queries()
    assert len(queries) == 27
    assert len({query.name for query in queries}) == 27
    for query in queries:
        assert_read_only(query.sql)
        assert re.match(r"^(SELECT|WITH)\b", query.sql, flags=re.IGNORECASE)
        assert not re.search(r"\bSELECT\s+(?:[a-z_]+\.)?\*", query.sql, flags=re.IGNORECASE)


@pytest.mark.parametrize(
    "statement",
    [
        "INSERT INTO games VALUES (1)",
        "WITH x AS (SELECT 1) DELETE FROM games",
        "DROP TABLE games",
        "ALTER TABLE games ADD COLUMN bad INT",
    ],
)
def test_mutation_guard_blocks_non_read_only_sql(statement):
    with pytest.raises(SqlAnalysisError):
        assert_read_only(statement)


def test_required_outputs_exist_with_expected_columns():
    required = {
        "market_overview": {"total_games", "free_games", "zero_review_games"},
        "price_bands": {"price_band", "games", "median_total_reviews", "median_positive_rate"},
        "review_volume_distribution": {"review_band", "games", "share_pct"},
        "genre_summary": {"genre_name", "games", "reviews_ge_20_share_pct"},
        "release_month_summary": {
            "release_month", "games", "reviews_ge_20_games", "median_positive_rate"
        },
        "model_sample_comparison": {"sample_name", "games", "median_current_price_usd"},
        "top_review_volume_games": {
            "appid", "name", "total_reviews", "positive_rate",
            "review_volume_percentile",
        },
    }
    for name, columns in required.items():
        path = ANALYSIS_OUTPUT_DIR / f"{name}.csv"
        assert path.exists()
        assert columns.issubset(read_result(name).columns)


def test_market_model_and_review_band_counts_match_frozen_database():
    market = read_result("market_overview").iloc[0]
    assert market["total_games"] == 3_000
    assert market["zero_review_games"] == 759
    model = read_result("model_sample_comparison").set_index("sample_name")
    assert model.loc["Market sample", "games"] == 3_000
    assert model.loc["Model candidate (reviews >=20)", "games"] == 844
    bands = read_result("review_volume_distribution")
    assert bands["games"].sum() == 3_000
    assert bands.loc[bands["review_band"] == "0", "games"].iloc[0] == 759


def test_genre_relation_logic_and_positive_rate_null_handling():
    genres = read_result("genre_summary")
    assert len(genres) == 13
    assert genres["games"].sum() == 8_796
    positive = read_result("positive_rate_by_review_volume")
    assert "0" not in set(positive["review_band"].astype(str))
    assert positive["games"].sum() == 2_241
    assert positive[["avg_positive_rate", "median_positive_rate"]].notna().all().all()


def test_ranked_output_is_deterministically_ordered():
    top = read_result("top_review_volume_games")
    pairs = list(zip(top["total_reviews"], top["appid"]))
    assert pairs == sorted(pairs, key=lambda pair: (-pair[0], pair[1]))
    assert len(top) == 20


def test_manifest_records_every_named_query_and_pass_status():
    manifest = MANIFEST_PATH.read_text(encoding="utf-8")
    assert "Queries executed: **27**" in manifest
    assert "Database mutation guard: **PASS**" in manifest
    assert manifest.count("| PASS |") == 27
