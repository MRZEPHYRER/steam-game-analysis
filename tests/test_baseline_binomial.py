from __future__ import annotations

import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "modeling"
FIGURES = ROOT / "figures" / "modeling"

REQUIRED_OUTPUTS = {
    "step5b_model_fit_summary.csv",
    "step5b_coefficients.csv",
    "step5b_profile_ci.csv",
    "step5b_scaling_parameters.csv",
    "step5b_predicted_effects.csv",
    "step5b_dispersion_diagnostics.csv",
    "step5b_residual_summary.csv",
    "step5b_top_residuals.csv",
    "step5b_leverage_summary.csv",
    "step5b_top_leverage.csv",
    "step5b_cooks_summary.csv",
    "step5b_top_influence.csv",
    "step5b_collinearity.csv",
    "step5b_matrix_diagnostics.csv",
    "step5b_fitted_probability_summary.csv",
    "step5b_calibration_deciles.csv",
    "step5b_review_influence_association.csv",
    "step5b_fit_warnings.csv",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def number(row: dict[str, str], key: str) -> float:
    return float(row[key])


def test_step5b_scripts_outputs_reports_and_figures_exist() -> None:
    assert (ROOT / "R" / "run_baseline_model.R").is_file()
    assert (ROOT / "R" / "modeling" / "04_baseline_binomial.R").is_file()
    assert (ROOT / "R" / "modeling" / "05_baseline_diagnostics.R").is_file()
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("step5b_*.csv")}
    assert (ROOT / "reports" / "step5b_baseline_binomial_report.md").is_file()
    assert (ROOT / "reports" / "03_statistical_modeling.qmd").is_file()
    assert {path.name for path in FIGURES.glob("0[1-4]_*.png")} == {
        "01_baseline_calibration.png",
        "02_residuals_vs_fitted.png",
        "03_influence_review_volume.png",
        "04_baseline_odds_ratios.png",
    }


def test_primary_sample_response_and_formula_are_frozen() -> None:
    fit = read_csv("step5b_model_fit_summary.csv")[0]
    assert int(fit["n_games"]) == 836
    assert int(fit["unique_appids"]) == 836
    assert int(fit["total_positive_reviews"]) == 943294
    assert int(fit["total_negative_reviews"]) == 125730
    assert int(fit["response_trials"]) == 1069024
    assert int(fit["total_positive_reviews"]) + int(fit["total_negative_reviews"]) == int(fit["response_trials"])
    assert fit["formula"] == (
        "cbind(positive_reviews, negative_reviews) ~ z_log1p_price + "
        "z_days_since_release + platform_segment + genre_action + genre_adventure + "
        "genre_casual + genre_indie + genre_rpg + genre_simulation + genre_strategy"
    )


def test_scaling_references_design_matrix_and_fit_are_valid() -> None:
    scaling = {row["predictor"]: row for row in read_csv("step5b_scaling_parameters.csv")}
    assert set(scaling) == {"log1p_current_price", "days_since_release"}
    assert all(number(row, "scaling_sd") > 0 for row in scaling.values())
    matrix = read_csv("step5b_matrix_diagnostics.csv")[0]
    assert int(matrix["matrix_rows"]) == 836
    assert int(matrix["matrix_columns"]) == 13
    assert int(matrix["matrix_rank"]) == 13
    assert int(matrix["exact_dependencies"]) == 0
    assert matrix["platform_reference"] == "Windows only"
    assert matrix["genre_reference"] == "absent (0)"
    fit = read_csv("step5b_model_fit_summary.csv")[0]
    assert fit["converged"] == "TRUE"
    assert int(fit["number_of_coefficients"]) == 13
    assert int(fit["residual_df"]) == 823


def test_coefficient_and_profile_tables_are_complete() -> None:
    coefficients = read_csv("step5b_coefficients.csv")
    assert len(coefficients) == 13
    assert {row["term"] for row in coefficients} == {
        "(Intercept)", "z_log1p_price", "z_days_since_release",
        "platform_segmentWindows + macOS", "platform_segmentWindows + Linux",
        "platform_segmentWindows + macOS + Linux", "genre_action", "genre_adventure",
        "genre_casual", "genre_indie", "genre_rpg", "genre_simulation", "genre_strategy",
    }
    numeric_columns = set(coefficients[0]) - {"term"}
    assert all(math.isfinite(float(row[column])) for row in coefficients for column in numeric_columns)
    profile = read_csv("step5b_profile_ci.csv")
    assert len(profile) == 13
    assert all(row["status"] == "PASS" for row in profile)


def test_diagnostics_are_finite_and_within_valid_ranges() -> None:
    dispersion = read_csv("step5b_dispersion_diagnostics.csv")[0]
    for key in ("pearson_chi_square", "pearson_dispersion_ratio", "residual_deviance", "deviance_dispersion_ratio"):
        assert math.isfinite(number(dispersion, key))
    assert int(float(dispersion["residual_df"])) == 823
    leverage = read_csv("step5b_leverage_summary.csv")[0]
    assert 0 <= number(leverage, "min") <= number(leverage, "max") <= 1
    assert int(float(leverage["parameter_count"])) == 13
    cooks = read_csv("step5b_cooks_summary.csv")[0]
    assert all(math.isfinite(number(cooks, key)) for key in ("min", "median", "p95", "p99", "max"))
    assert number(cooks, "min") >= 0
    probability = read_csv("step5b_fitted_probability_summary.csv")[0]
    assert 0 < number(probability, "min") <= number(probability, "max") < 1


def test_calibration_references_and_database_preservation() -> None:
    calibration = read_csv("step5b_calibration_deciles.csv")
    assert len(calibration) == 10
    assert sum(int(row["n_games"]) for row in calibration) == 836
    assert all(int(row["total_reviews"]) > 0 for row in calibration)
    db = read_csv("step5b_database_preservation.csv")
    assert db
    assert all(row["unchanged"] == "TRUE" for row in db)
    assert all(int(row["before"]) == int(row["after"]) for row in db)
    assert {row["object"]: int(row["before"]) for row in db} == {
        "games": 3000,
        "review_snapshots": 3000,
        "game_genres": 8796,
        "genres": 13,
        "model20": 844,
    }


def test_no_forbidden_model_search_reweighting_or_row_deletion() -> None:
    sources = "\n".join(
        (ROOT / "R" / "modeling" / name).read_text(encoding="utf-8")
        for name in ("04_baseline_binomial.R", "05_baseline_diagnostics.R")
    ).lower()
    for forbidden in (
        "quasibinomial(", "betabinomial", "stepaic(", "glmnet(", "weights =",
        "poly(", "splines::ns(", "splines::bs(",
    ):
        assert forbidden not in sources
    assert "slice_head(n = 20)" in sources
    assert "filter(abs(estimate_log_odds)" in sources


def test_step5b_outputs_do_not_expose_credentials() -> None:
    files = list(OUTPUT.glob("step5b_*.csv")) + [
        ROOT / "reports" / "step5b_baseline_binomial_report.md",
        ROOT / "reports" / "03_statistical_modeling.qmd",
    ]
    for path in files:
        text = path.read_text(encoding="utf-8")
        for unsafe in ("MYSQL_PASSWORD=", "MYSQL_USER=", "MYSQL_HOST=", "password=", "DSN="):
            assert unsafe not in text
