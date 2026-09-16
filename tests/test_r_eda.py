from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
R_ANALYSIS = ROOT / "R" / "analysis"
FIGURE_DIR = ROOT / "figures" / "eda"
SUMMARY_DIR = ROOT / "data" / "analysis" / "r"


EXPECTED_SCRIPTS = [
    "00_helpers.R",
    "01_load_data.R",
    "02_market_eda.R",
    "03_review_eda.R",
    "04_price_eda.R",
    "05_genre_eda.R",
    "06_sample_selection.R",
    "07_model_preparation.R",
]

EXPECTED_FIGURES = [
    "01_review_count_hist_raw.png",
    "02_review_count_hist_log.png",
    "03_review_count_ecdf.png",
    "04_free_paid_review_volume.png",
    "05_positive_rate_distribution.png",
    "06_positive_rate_vs_reviews.png",
    "07_perfect_rate_by_count_group.png",
    "08_price_distribution.png",
    "09_price_vs_review_volume.png",
    "10_full_model_free_share.png",
    "11_model_selection_by_genre.png",
    "12_genre_frequency.png",
    "13_genre_review_coverage.png",
    "14_release_month_coverage.png",
    "15_full_model_price_distribution.png",
    "16_price_positive_rate_all_vs_model20.png",
    "17_genre_positive_rate_all_vs_model20.png",
    "18_platform_support_and_selection.png",
    "19_wilson_interval_examples.png",
    "20_high_attention_games.png",
]


def read_csv(name: str) -> list[dict[str, str]]:
    with (SUMMARY_DIR / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def test_r_eda_scripts_and_orchestrator_exist() -> None:
    assert [path.name for path in sorted(R_ANALYSIS.glob("*.R"))] == EXPECTED_SCRIPTS
    runner = (ROOT / "R" / "run_eda.R").read_text(encoding="utf-8")
    for script in EXPECTED_SCRIPTS:
        if script != "00_helpers.R":
            assert script in runner
    assert "1:20" in runner


def test_mysql_views_and_read_only_connection_contract_are_fixed() -> None:
    source = (R_ANALYSIS / "01_load_data.R").read_text(encoding="utf-8")
    assert "with_steam_db(function(con)" in source
    assert "FROM vw_game_analysis" in source
    assert "FROM vw_model_sample_20" in source
    assert "FROM vw_game_genres" in source
    assert "nrow(games_market) == 3000" in source
    assert "nrow(games_model20) == 844" in source
    assert "nrow(games_genres) == 8796" in source

    all_r = "\n".join(path.read_text(encoding="utf-8") for path in R_ANALYSIS.glob("*.R"))
    for mutation in ("INSERT ", "UPDATE ", "DELETE ", "CREATE TABLE", "ALTER TABLE", "DROP TABLE"):
        assert mutation not in all_r.upper()


def test_zero_review_and_positive_rate_semantics_are_explicit() -> None:
    load_source = (R_ANALYSIS / "01_load_data.R").read_text(encoding="utf-8")
    review_source = (R_ANALYSIS / "03_review_eda.R").read_text(encoding="utf-8")
    assert "sum(games_market$total_reviews == 0) == 759" in load_source
    assert "is.na(games_market$positive_rate[games_market$total_reviews == 0])" in load_source
    assert "dplyr::filter(total_reviews > 0)" in review_source
    assert "nrow(reviewed_games) == 2241" in review_source


def test_dataset_and_market_counts() -> None:
    audit = {row["dataset"]: row for row in read_csv("dataset_audit.csv")}
    assert int(audit["games_market"]["rows"]) == 3000
    assert int(audit["games_market"]["distinct_appids"]) == 3000
    assert int(audit["games_model20"]["rows"]) == 844
    assert int(audit["games_model20"]["distinct_appids"]) == 844
    assert int(audit["games_genres"]["rows"]) == 8796

    market = {row["metric"]: int(row["value"]) for row in read_csv("market_overview.csv")}
    assert market == {
        "market_games": 3000,
        "model20_games": 844,
        "zero_review_games": 759,
        "reviewed_games": 2241,
        "free_games": 402,
        "paid_games": 2598,
    }


def test_missingness_and_sample_selection_outputs() -> None:
    missing = {row["field"]: int(row["missing_n"]) for row in read_csv("missingness_summary.csv")}
    assert missing == {
        "current_price_usd": 403,
        "publisher": 3,
        "positive_rate": 759,
    }

    selection = read_csv("sample_selection_summary.csv")
    model_rows = [row for row in selection if row["sample"] == "At least 20 reviews"]
    assert sum(int(row["games"]) for row in model_rows) == 844
    assert int(next(row["games"] for row in model_rows if row["payment_segment"] == "Free")) == 8


def test_all_high_resolution_figures_exist() -> None:
    assert sorted(path.name for path in FIGURE_DIR.glob("*.png")) == EXPECTED_FIGURES
    for name in EXPECTED_FIGURES:
        path = FIGURE_DIR / name
        assert path.stat().st_size > 50_000
        assert path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")


def test_quarto_and_written_report_cover_required_topics() -> None:
    qmd = (ROOT / "reports" / "02_r_eda.qmd").read_text(encoding="utf-8")
    report = (ROOT / "reports" / "step4b_r_eda_report.md").read_text(encoding="utf-8")
    assert "01_load_data.R" in qmd
    assert "dataset_audit" in qmd
    for figure in EXPECTED_FIGURES:
        assert figure in qmd
    for topic in ("Wilson", "多标签", "选择", "相关", "因果"):
        assert topic in report
    for unsafe in ("MYSQL_PASSWORD=", "MYSQL_USER=", "MYSQL_HOST="):
        assert unsafe not in qmd
        assert unsafe not in report
