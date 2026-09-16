from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
R_MODELING = ROOT / "R" / "modeling"
OUTPUT = ROOT / "data" / "analysis" / "modeling"

REQUIRED_OUTPUTS = {
    "sample_flow.csv",
    "sample_threshold_summary.csv",
    "model20_population_audit.csv",
    "price_audit.csv",
    "release_timing_audit.csv",
    "platform_frequency.csv",
    "genre_frequency.csv",
    "genre_cooccurrence.csv",
    "genre_correlation.csv",
    "design_matrix_diagnostics.csv",
    "reception_distribution.csv",
    "review_concentration.csv",
    "top_review_contributors.csv",
    "missingness_model_fields.csv",
    "sparse_cells.csv",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def test_step5a_scripts_and_required_outputs_exist() -> None:
    assert (ROOT / "R" / "run_model_specification.R").is_file()
    assert {
        "00_model_helpers.R",
        "01_prepare_model_data.R",
        "02_model_specification_audit.R",
        "03_genre_design_audit.R",
        "04_baseline_binomial.R",
        "05_baseline_diagnostics.R",
        "06_robust_models.R",
        "07_influence_sensitivity.R",
        "08_sensitivity_analysis.R",
        "09_sensitivity_visuals.R",
    } <= {path.name for path in R_MODELING.glob("*.R")}
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("*.csv")}


def test_sample_flow_and_threshold_counts_are_frozen() -> None:
    flow = {row["stage"]: int(row["n"]) for row in read_csv("sample_flow.csv")}
    assert flow == {
        "Market sample": 3000,
        "At least 1 review": 2241,
        "At least 10 reviews": 1139,
        "At least 20 reviews": 844,
        "At least 50 reviews": 551,
        "Model20 paid": 836,
        "Model20 paid complete-case": 836,
    }
    thresholds = read_csv("sample_threshold_summary.csv")
    assert [int(row["n_games"]) for row in thresholds] == [2241, 1139, 844, 551]
    assert all(int(row["n_games"]) == int(row["unique_appids"]) for row in thresholds)


def test_denominator_identity_and_nonnegative_counts() -> None:
    for row in read_csv("sample_threshold_summary.csv"):
        positive = int(row["positive_reviews"])
        negative = int(row["negative_reviews"])
        total = int(row["total_reviews"])
        assert positive >= 0
        assert negative >= 0
        assert positive + negative == total
        assert int(row["minimum_reviews"]) > 0


def test_population_price_and_release_audits() -> None:
    population = read_csv("model20_population_audit.csv")[0]
    assert int(population["n_games"]) == 844
    assert int(population["unique_appids"]) == 844
    assert int(population["free_games"]) == 8
    assert int(population["paid_games"]) == 836

    price = read_csv("price_audit.csv")[0]
    assert int(price["n_games"]) == 836
    assert int(price["missing_current_price"]) == 0
    assert int(price["missing_list_price"]) == 0

    timing = read_csv("release_timing_audit.csv")[0]
    assert int(timing["days_since_release_missing"]) == 0
    assert int(timing["non_positive_days"]) == 0
    assert int(timing["min_days"]) > 0


def test_genre_outputs_are_complete_and_game_level_encoding_is_asserted() -> None:
    mapping = read_csv("genre_indicator_mapping.csv")
    assert len(mapping) == 13
    assert len({row["indicator"] for row in mapping}) == 13
    assert len(read_csv("genre_cooccurrence.csv")) == 13 * 13
    assert len(read_csv("genre_correlation.csv")) == 13 * 12 // 2

    source = (R_MODELING / "01_prepare_model_data.R").read_text(encoding="utf-8")
    assert "nrow(genre_wide) == 3000" in source
    assert "dplyr::n_distinct(genre_wide$appid) == 3000" in source
    assert "reception_50$appid %in% reception_20$appid" in source
    assert "reception_20$appid %in% reception_10$appid" in source
    assert "reception_10$appid %in% reception_gt0$appid" in source


def test_predictor_only_design_matrix_is_full_rank() -> None:
    audit = read_csv("design_matrix_diagnostics.csv")[0]
    assert int(audit["n_rows"]) == 836
    assert int(audit["n_columns"]) == 17
    assert int(audit["matrix_rank"]) == 17
    assert int(audit["exact_linear_dependencies"]) == 0
    assert audit["reference_release_month"] == "2025-07"
    assert audit["reference_platform"] == "Windows only"


def test_no_outcome_model_or_database_mutation_is_present() -> None:
    source = "\n".join(
        (R_MODELING / name).read_text(encoding="utf-8")
        for name in (
            "00_model_helpers.R",
            "01_prepare_model_data.R",
            "02_model_specification_audit.R",
            "03_genre_design_audit.R",
        )
    )
    lowered = source.lower()
    for forbidden_model in ("glm(", "lm(", "glm.nb(", "stepaic(", "glmnet("):
        assert forbidden_model not in lowered
    for mutation in ('"INSERT ', '"UPDATE ', '"DELETE ', '"CREATE ', '"DROP ', '"ALTER '):
        assert mutation not in source.upper()
    assert "identical(loaded_model_data$counts_before, loaded_model_data$counts_after)" in source


def test_report_and_outputs_do_not_expose_credentials() -> None:
    report = (ROOT / "reports" / "step5a_model_specification.md").read_text(encoding="utf-8")
    assert "cbind(positive_reviews, negative_reviews)" in report
    assert "UNRESOLVED BEFORE STEP 5B" in report
    for unsafe in ("MYSQL_PASSWORD=", "MYSQL_USER=", "MYSQL_HOST=", "password="):
        assert unsafe not in report
        for path in OUTPUT.glob("*.csv"):
            assert unsafe not in path.read_text(encoding="utf-8")
