from __future__ import annotations

import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "modeling"
FIGURES = ROOT / "figures" / "modeling"
REPORTS = ROOT / "reports"

SPECIFICATIONS = {
    "PRIMARY", "TH_GT0", "TH_10", "TH_50",
    "RELEASE_MONTH", "PRICE_RAW", "GENRE_EXPANDED",
}
REQUIRED_OUTPUTS = {
    "step5d_threshold_samples.csv", "step5d_threshold_exclusions.csv",
    "step5d_threshold_appids.csv", "step5d_threshold_fit.csv",
    "step5d_threshold_coefficients.csv", "step5d_threshold_stability.csv",
    "step5d_release_fit.csv", "step5d_release_coefficients.csv",
    "step5d_release_comparison.csv", "step5d_price_fit.csv",
    "step5d_price_coefficients.csv", "step5d_price_comparison.csv",
    "step5d_price_predicted_contrasts.csv", "step5d_genre_fit.csv",
    "step5d_genre_coefficients.csv", "step5d_genre_comparison.csv",
    "step5d_master_specification_table.csv", "step5d_core_predictor_stability.csv",
    "step5d_direction_matrix.csv", "step5d_diagnostics.csv",
    "step5d_fit_warnings.csv", "step5d_formula_audit.csv",
    "step5d_database_preservation.csv",
}
REQUIRED_FIGURES = {
    "09_threshold_or_comparison.png", "10_threshold_coefficient_drift.png",
    "11_release_specification_comparison.png", "12_release_month_effects.png",
    "13_price_specification_comparison.png", "14_genre_specification_comparison.png",
    "15_robustness_heatmap.png", "16_or_range_summary.png",
    "17_simulation_sensitivity.png", "18_price_sensitivity.png",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def number(row: dict[str, str], key: str) -> float:
    return float(row[key])


def test_step5d_scripts_outputs_reports_and_figures_exist() -> None:
    for path in (
        ROOT / "R" / "run_sensitivity_analysis.R",
        ROOT / "R" / "modeling" / "08_sensitivity_analysis.R",
        ROOT / "R" / "modeling" / "09_sensitivity_visuals.R",
        REPORTS / "step5d_sensitivity_report.md",
        REPORTS / "04_sensitivity_visual_audit.qmd",
        REPORTS / "04_sensitivity_visual_audit.html",
    ):
        assert path.is_file()
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("step5d_*.csv")}
    assert REQUIRED_FIGURES == {path.name for path in FIGURES.glob("1[0-8]_*.png")} | {
        "09_threshold_or_comparison.png"
    }
    assert all((FIGURES / name).stat().st_size > 20_000 for name in REQUIRED_FIGURES)


def test_primary_model_is_numerically_and_structurally_preserved() -> None:
    current = {
        row["term"]: row for row in read_csv("step5d_threshold_coefficients.csv")
        if row["specification_id"] == "PRIMARY"
    }
    frozen = {row["term"]: row for row in read_csv("step5c_beta_binomial_coefficients.csv")}
    assert current.keys() == frozen.keys()
    assert len(current) == 13
    for term in current:
        assert math.isclose(
            number(current[term], "estimate_log_odds"),
            number(frozen[term], "estimate_log_odds"),
            abs_tol=1e-5,
        )
    primary = next(row for row in read_csv("step5d_diagnostics.csv") if row["specification_id"] == "PRIMARY")
    assert int(primary["n_games"]) == int(primary["unique_appids"]) == 836
    assert primary["response"] == "cbind(positive_reviews, negative_reviews)"
    assert primary["family"] == "glmmTMB::betabinomial(link = logit)"


def test_threshold_populations_are_paid_nested_and_count_valid() -> None:
    samples = read_csv("step5d_threshold_samples.csv")
    assert [row["specification_id"] for row in samples] == ["TH_GT0", "TH_10", "PRIMARY", "TH_50"]
    assert [int(row["n_games"]) for row in samples] == [2206, 1127, 836, 548]
    assert all(row["paid_only"] == "TRUE" for row in samples)
    for row in samples:
        assert int(row["unique_appids"]) == int(row["n_games"])
        assert int(row["positive_reviews"]) + int(row["negative_reviews"]) == int(row["total_reviews"])
    by_spec: dict[str, set[int]] = {}
    for row in read_csv("step5d_threshold_appids.csv"):
        assert row["is_free"] == "0"
        assert int(row["positive_reviews"]) + int(row["negative_reviews"]) == int(row["total_reviews"])
        by_spec.setdefault(row["specification_id"], set()).add(int(row["appid"]))
    assert by_spec["TH_50"] < by_spec["PRIMARY"] < by_spec["TH_10"] < by_spec["TH_GT0"]


def test_threshold_missing_predictor_exclusion_is_explicit_not_silent() -> None:
    exclusions = read_csv("step5d_threshold_exclusions.csv")
    assert len(exclusions) == 1
    assert int(exclusions[0]["total_reviews"]) == 2
    assert exclusions[0]["is_free"] == "0"
    assert "missing current_price_usd" in exclusions[0]["exclusion_reason"]
    samples = {row["specification_id"]: row for row in read_csv("step5d_threshold_samples.csv")}
    assert int(samples["TH_GT0"]["source_paid_games"]) == 2207
    assert int(samples["TH_GT0"]["excluded_missing_predictors"]) == 1
    assert all(int(samples[key]["excluded_missing_predictors"]) == 0 for key in ("TH_10", "PRIMARY", "TH_50"))


def test_frozen_scaling_is_reused_across_all_thresholds() -> None:
    frozen = {row["predictor"]: row for row in read_csv("step5b_scaling_parameters.csv")}
    for row in read_csv("step5d_threshold_samples.csv"):
        assert math.isclose(number(row, "frozen_log_price_mean"), number(frozen["log1p_current_price"], "scaling_mean"), abs_tol=1e-12)
        assert math.isclose(number(row, "frozen_log_price_sd"), number(frozen["log1p_current_price"], "scaling_sd"), abs_tol=1e-12)
        assert math.isclose(number(row, "frozen_days_mean"), number(frozen["days_since_release"], "scaling_mean"), abs_tol=1e-12)
        assert math.isclose(number(row, "frozen_days_sd"), number(frozen["days_since_release"], "scaling_sd"), abs_tol=1e-12)


def test_one_at_a_time_formula_contract_and_no_silent_row_deletion() -> None:
    rows = {row["specification_id"]: row for row in read_csv("step5d_formula_audit.csv")}
    assert set(rows) == SPECIFICATIONS
    assert all(row["response_is_grouped_counts"] == "TRUE" for row in rows.values())
    assert all(row["no_silent_row_deletion"] == "TRUE" for row in rows.values())
    assert all(int(row["n_input_rows"]) == int(row["n_model_rows"]) for row in rows.values())
    assert rows["RELEASE_MONTH"]["includes_days"] == "FALSE"
    assert rows["RELEASE_MONTH"]["includes_release_month"] == "TRUE"
    assert rows["PRICE_RAW"]["includes_log_price"] == "FALSE"
    assert rows["PRICE_RAW"]["includes_raw_price"] == "TRUE"
    assert rows["GENRE_EXPANDED"]["added_genres"] == "genre_early_access;genre_sports;genre_racing"
    assert all(rows[key]["added_genres"] == "" for key in SPECIFICATIONS - {"GENRE_EXPANDED"})
    for key in SPECIFICATIONS - {"RELEASE_MONTH"}:
        assert rows[key]["includes_days"] == "TRUE"
        assert rows[key]["includes_release_month"] == "FALSE"


def test_all_expected_coefficients_and_release_reference_are_exported() -> None:
    assert len(read_csv("step5d_threshold_coefficients.csv")) == 52
    release = read_csv("step5d_release_coefficients.csv")
    assert len(release) == 18
    reference = next(row for row in release if row["term"] == "release_month2025-07")
    assert reference["direction"] == "reference"
    assert number(reference, "odds_ratio") == number(reference, "or_ci95_lower") == number(reference, "or_ci95_upper") == 1
    assert len(read_csv("step5d_price_coefficients.csv")) == 13
    assert len(read_csv("step5d_genre_coefficients.csv")) == 16
    master = read_csv("step5d_master_specification_table.csv")
    assert len(master) == 98
    assert {row["specification_id"] for row in master} == SPECIFICATIONS


def test_all_beta_binomial_fits_have_usable_diagnostics() -> None:
    rows = read_csv("step5d_diagnostics.csv")
    assert len(rows) == 7
    assert {row["specification_id"] for row in rows} == SPECIFICATIONS
    for row in rows:
        assert int(row["convergence_code"]) == 0
        assert row["converged"] == row["positive_definite_hessian"] == "TRUE"
        assert int(row["warning_count"]) == 0
        assert row["dispersion_boundary_flag"] == "FALSE"
        assert int(row["extreme_fixed_estimate_or_se_count"]) == 0
        assert math.isfinite(number(row, "max_abs_fixed_gradient"))
        phi = number(row, "beta_precision_phi")
        assert phi > 0
        assert math.isclose(number(row, "intra_game_rho"), 1 / (phi + 1), rel_tol=1e-12)
    warnings = read_csv("step5d_fit_warnings.csv")
    assert len(warnings) == 7
    assert all(row["status"] == "NO WARNING" and row["warning_text"] == "" for row in warnings)


def test_fit_comparison_flags_only_same_row_likelihood_models() -> None:
    rows = {row["specification_id"]: row for row in read_csv("step5d_diagnostics.csv")}
    for key in ("PRIMARY", "RELEASE_MONTH", "PRICE_RAW", "GENRE_EXPANDED"):
        assert rows[key]["same_rows_as_primary"] == "TRUE"
        assert rows[key]["aic_comparable_to_primary"] == "TRUE"
    for key in ("TH_GT0", "TH_10", "TH_50"):
        assert rows[key]["same_rows_as_primary"] == "FALSE"
        assert rows[key]["aic_comparable_to_primary"] == "FALSE"
        assert rows[key]["delta_aic_vs_primary"] == ""


def test_price_and_genre_alternatives_keep_the_prespecified_scope() -> None:
    raw_fit = read_csv("step5d_price_fit.csv")[0]
    assert int(raw_fit["n_games"]) == 836
    assert math.isclose(number(raw_fit, "raw_price_mean_usd"), 11.5725956937799, abs_tol=1e-12)
    assert math.isclose(number(raw_fit, "raw_price_sd_usd"), 9.67158648983468, abs_tol=1e-12)
    prices = read_csv("step5d_price_predicted_contrasts.csv")
    assert {row["price_term"] for row in prices} == {"z_log1p_price", "z_raw_price"}
    assert all(number(row, "absolute_probability_contrast") < 0 for row in prices)

    added = {
        row["term"]: row for row in read_csv("step5d_genre_comparison.csv")
        if row["term"] in {"genre_early_access", "genre_sports", "genre_racing"}
    }
    assert {key: int(row["n_games_with_genre"]) for key, row in added.items()} == {
        "genre_early_access": 93, "genre_sports": 31, "genre_racing": 20,
    }
    for row in added.values():
        assert int(row["positive_reviews_with_genre"]) + int(row["negative_reviews_with_genre"]) == int(row["total_reviews_with_genre"])
        assert row["ci_crosses_1"] == "TRUE"
    assert "not historical launch-state status" in added["genre_early_access"]["source_semantics"]


def test_direction_and_core_stability_tables_cover_focus_predictors() -> None:
    direction = read_csv("step5d_direction_matrix.csv")
    stability = read_csv("step5d_core_predictor_stability.csv")
    assert len(direction) == len(stability) == 9
    assert {row["conceptual_term"] for row in direction} == {row["conceptual_term"] for row in stability}
    assert all(row["any_direction_change"] == "FALSE" for row in stability)
    assert {row["robustness_class"] for row in stability} <= {"ROBUST", "PARTIAL", "SENSITIVE"}
    simulation = next(row for row in stability if row["conceptual_term"] == "genre_simulation")
    price = next(row for row in stability if row["conceptual_term"] == "z_log1p_price")
    assert simulation["same_direction_specs"] == price["same_direction_specs"] == "7"
    assert simulation["primary_direction"] == price["primary_direction"] == "-"


def test_chinese_visual_audit_uses_real_utf8_without_uplus_notation() -> None:
    qmd = (REPORTS / "04_sensitivity_visual_audit.qmd").read_text(encoding="utf-8")
    html = (REPORTS / "04_sensitivity_visual_audit.html").read_text(encoding="utf-8")
    notation = "<" + "U+"
    escaped_notation = "&lt;" + "U+"
    assert notation not in qmd
    assert notation not in html
    assert escaped_notation not in html
    assert '<meta charset="utf-8">' in html
    for expected in (
        "主模型", "评论数量阈值", "价格", "上市天数", "稳健性",
        "敏感性分析", "预测变量", "置信区间", "模拟", "平台",
        "是", "否",
    ):
        assert expected in html
    for expected_number in (
        "8.7467", "0.1026", "0.9296", "0.7859", "0.8257",
        "2,206", "1,127", "836", "548",
    ):
        assert expected_number in html
    decoder = (ROOT / "R" / "unicode_utils.R").read_text(encoding="utf-8")
    assert "{4,6}" in decoder
    assert "intToUtf8" in decoder


def test_database_preservation_and_credential_safety() -> None:
    db = read_csv("step5d_database_preservation.csv")
    expected = {
        "games": 3000, "review_snapshots": 3000, "game_genres": 8796,
        "genres": 13, "model20": 844,
    }
    assert {row["object"]: int(row["before"]) for row in db} == expected
    assert {row["object"]: int(row["after"]) for row in db} == expected
    assert all(row["unchanged"] == "TRUE" for row in db)

    files = list(OUTPUT.glob("step5d_*.csv")) + [
        REPORTS / "step5d_sensitivity_report.md",
        REPORTS / "04_sensitivity_visual_audit.qmd",
        REPORTS / "04_sensitivity_visual_audit.html",
        REPORTS / "03_statistical_modeling.qmd",
        REPORTS / "03_statistical_modeling.html",
    ] + [FIGURES / name for name in REQUIRED_FIGURES]
    for path in files:
        content = path.read_bytes().lower()
        for unsafe in (b"mysql_password", b"password=", b"dsn=", b".env"):
            assert unsafe not in content
