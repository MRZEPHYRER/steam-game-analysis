import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "modeling"
FIGURES = ROOT / "figures" / "modeling"
REPORTS = ROOT / "reports"

REQUIRED_OUTPUTS = {
    "step5e_outcome_distribution.csv",
    "step5e_sample_audit.csv",
    "step5e_primary_fit.csv",
    "step5e_primary_coefficients.csv",
    "step5e_primary_profile_ci.csv",
    "step5e_influence_summary.csv",
    "step5e_top_influence.csv",
    "step5e_calibration_deciles.csv",
    "step5e_auc.csv",
    "step5e_rating_threshold_fit.csv",
    "step5e_rating_threshold_coefficients.csv",
    "step5e_rating_threshold_stability.csv",
    "step5e_predicted_probability_contrasts.csv",
    "step5e_beta_logistic_direction_comparison.csv",
    "step5e_fit_warnings.csv",
    "step5e_predictor_level_outcomes.csv",
    "step5e_sparse_outcome_cells.csv",
    "step5e_separation_diagnostics.csv",
    "step5e_residual_diagnostics.csv",
    "step5e_database_preservation.csv",
}
REQUIRED_FIGURES = {
    "19_high_rating_calibration.png",
    "20_high_rating_roc.png",
    "21_high_rating_primary_or.png",
    "22_rating_threshold_or_comparison.png",
    "23_rating_threshold_drift.png",
    "24_beta_vs_high_rating_direction.png",
}
GENRES = {
    "genre_action",
    "genre_adventure",
    "genre_casual",
    "genre_indie",
    "genre_rpg",
    "genre_simulation",
    "genre_strategy",
}
PLATFORMS = {
    "Windows only",
    "Windows + macOS",
    "Windows + Linux",
    "Windows + macOS + Linux",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def test_step5e_required_outputs_scripts_reports_and_figures_exist() -> None:
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("step5e_*.csv")}
    assert REQUIRED_FIGURES <= {path.name for path in FIGURES.glob("*.png")}
    assert all((FIGURES / name).stat().st_size > 20_000 for name in REQUIRED_FIGURES)
    for name in (
        "10_high_rating_logistic.R",
        "11_high_rating_diagnostics.R",
        "12_high_rating_visuals.R",
        "13_high_rating_report.R",
    ):
        assert (ROOT / "R" / "modeling" / name).exists()
    assert (ROOT / "R" / "run_high_rating_analysis.R").exists()
    assert (REPORTS / "step5e_high_rating_logistic_report.md").exists()
    assert (REPORTS / "05_high_rating_visual_audit.qmd").exists()
    assert (REPORTS / "05_high_rating_visual_audit.html").exists()


def test_step5e_sample_integrity_and_exact_outcomes() -> None:
    rows = read_csv("step5e_sample_audit.csv")
    assert len(rows) == 836
    appids = [int(row["appid"]) for row in rows]
    assert len(set(appids)) == 836
    assert appids == sorted(appids)
    assert all(int(row["is_free"]) == 0 for row in rows)
    assert all(int(row["total_reviews"]) >= 20 for row in rows)
    assert {row["platform_segment"] for row in rows} == PLATFORMS
    for row in rows:
        positive = int(row["positive_reviews"])
        negative = int(row["negative_reviews"])
        total = int(row["total_reviews"])
        assert positive + negative == total
        assert math.isclose(
            float(row["computed_positive_rate"]), positive / total,
            rel_tol=0, abs_tol=1e-14,
        )
        assert int(row["high_rating_80"]) == int(positive * 100 >= total * 80)
        assert int(row["high_rating_85"]) == int(positive * 100 >= total * 85)
        assert int(row["high_rating_90"]) == int(positive * 100 >= total * 90)
        assert all(int(row[genre]) in {0, 1} for genre in GENRES)


def test_step5e_uses_frozen_scaling_and_predictors_without_weights() -> None:
    sample = read_csv("step5e_sample_audit.csv")
    scaling = {row["predictor"]: row for row in read_csv("step5b_scaling_parameters.csv")}
    price_mean = float(scaling["log1p_current_price"]["scaling_mean"])
    price_sd = float(scaling["log1p_current_price"]["scaling_sd"])
    days_mean = float(scaling["days_since_release"]["scaling_mean"])
    days_sd = float(scaling["days_since_release"]["scaling_sd"])
    for row in (sample[0], sample[len(sample) // 2], sample[-1]):
        assert math.isclose(
            float(row["z_log1p_price"]),
            (float(row["log1p_current_price"]) - price_mean) / price_sd,
            rel_tol=0, abs_tol=1e-12,
        )
        assert math.isclose(
            float(row["z_days_since_release"]),
            (float(row["days_since_release"]) - days_mean) / days_sd,
            rel_tol=0, abs_tol=1e-12,
        )
    fit = read_csv("step5e_rating_threshold_fit.csv")
    assert len(fit) == 3
    assert all(row["n_games"] == "836" for row in fit)
    assert all(row["weights_used"] == "FALSE" for row in fit)
    assert all(row["all_prior_weights_one"] == "TRUE" for row in fit)
    assert all(row["review_count_covariate_included"] == "FALSE" for row in fit)
    expected_terms = {
        "z_log1p_price", "z_days_since_release", "platform_segment", *GENRES
    }
    for row in fit:
        formula = row["formula"]
        assert "total_reviews" not in formula
        assert expected_terms <= {term.strip() for term in formula.split("~", 1)[1].split("+")}


def test_step5e_distribution_boundaries_and_same_model_population() -> None:
    rows = read_csv("step5e_outcome_distribution.csv")
    assert [row["model_id"] for row in rows] == ["HIGH80", "HIGH85", "HIGH90"]
    assert [float(row["rating_threshold"]) for row in rows] == [0.80, 0.85, 0.90]
    assert [int(row["n_total"]) for row in rows] == [836, 836, 836]
    assert [int(row["high_rated_n"]) for row in rows] == [574, 471, 359]
    assert [int(row["exact_boundary_n"]) for row in rows] == [5, 1, 7]
    assert all(row["comparator"] == ">=" for row in rows)
    assert all(
        int(row["high_rated_n"]) + int(row["not_high_rated_n"]) == 836
        for row in rows
    )


def test_step5e_models_converge_and_export_complete_coefficients() -> None:
    fits = read_csv("step5e_rating_threshold_fit.csv")
    assert all(row["converged"] == "TRUE" for row in fits)
    assert all(row["warning_count"] == "0" for row in fits)
    assert all(row["matrix_rank"] == row["matrix_columns"] == "13" for row in fits)
    coefficients = read_csv("step5e_rating_threshold_coefficients.csv")
    assert len(coefficients) == 39
    expected_terms = {"(Intercept)", "z_log1p_price", "z_days_since_release", *GENRES}
    expected_terms |= {
        "platform_segmentWindows + macOS",
        "platform_segmentWindows + Linux",
        "platform_segmentWindows + macOS + Linux",
    }
    for model_id in ("HIGH80", "HIGH85", "HIGH90"):
        model_rows = [row for row in coefficients if row["model_id"] == model_id]
        assert len(model_rows) == 13
        assert {row["term"] for row in model_rows} == expected_terms
        assert all(float(row["or_ci95_lower"]) > 0 for row in model_rows)
        assert all(float(row["or_ci95_upper"]) > 0 for row in model_rows)
    profile = read_csv("step5e_primary_profile_ci.csv")
    assert len(profile) == 13
    assert all(row["status"] == "PASS" for row in profile)


def test_step5e_separation_influence_calibration_and_auc() -> None:
    separation = read_csv("step5e_separation_diagnostics.csv")
    assert all(int(row["n_flagged"]) == 0 for row in separation)
    sparse = read_csv("step5e_sparse_outcome_cells.csv")
    assert len(sparse) == 18
    assert all(row["zero_event_cell"] == "FALSE" for row in sparse)
    assert all(row["zero_non_event_cell"] == "FALSE" for row in sparse)
    influence = read_csv("step5e_influence_summary.csv")[0]
    assert int(influence["n_games"]) == 836
    assert int(influence["parameter_count"]) == 13
    assert float(influence["max_leverage"]) < 1
    assert float(influence["max_cooks_distance"]) < 0.5
    assert int(influence["n_cooks_above_0_5"]) == 0
    assert int(influence["n_cooks_above_1"]) == 0
    top = read_csv("step5e_top_influence.csv")
    assert len(top) == 20
    assert len({row["appid"] for row in top}) == 20
    calibration = read_csv("step5e_calibration_deciles.csv")
    assert len(calibration) == 10
    assert sum(int(row["n_games"]) for row in calibration) == 836
    assert all(0 <= float(row["mean_predicted_probability"]) <= 1 for row in calibration)
    assert all(0 <= float(row["observed_high_rating_proportion"]) <= 1 for row in calibration)
    auc = read_csv("step5e_auc.csv")[0]
    assert 0.5 < float(auc["auc"]) < 1
    assert 0 <= float(auc["ci95_lower"]) < float(auc["auc"])
    assert float(auc["auc"]) < float(auc["ci95_upper"]) <= 1


def test_step5e_sensitivity_probability_and_beta_comparison() -> None:
    stability = read_csv("step5e_rating_threshold_stability.csv")
    assert len(stability) == 12
    assert {row["stability_class"] for row in stability} <= {
        "ROBUST", "PARTIAL", "SENSITIVE"
    }
    probability = read_csv("step5e_predicted_probability_contrasts.csv")
    assert len(probability) == 13
    reference = next(row for row in probability if row["scenario"] == "REFERENCE")
    assert math.isclose(
        float(reference["reference_probability"]),
        float(reference["modified_probability"]),
    )
    comparison = read_csv("step5e_beta_logistic_direction_comparison.csv")
    assert len(comparison) == 12
    assert all(
        "outcomes differ" in row["comparison_scope"]
        and "not directly comparable" in row["comparison_scope"]
        for row in comparison
    )


def test_step5e_database_preservation_utf8_and_interpretation_safety() -> None:
    db = read_csv("step5e_database_preservation.csv")
    expected = {
        "games": 3000,
        "review_snapshots": 3000,
        "game_genres": 8796,
        "genres": 13,
        "model20": 844,
    }
    assert {row["object"]: int(row["before"]) for row in db} == expected
    assert {row["object"]: int(row["after"]) for row in db} == expected
    assert all(row["unchanged"] == "TRUE" for row in db)
    for path in OUTPUT.glob("step5e_*.csv"):
        path.read_text(encoding="utf-8")
    reviewed = [
        REPORTS / "05_high_rating_visual_audit.qmd",
        REPORTS / "step5e_high_rating_logistic_report.md",
        REPORTS / "03_statistical_modeling.qmd",
    ]
    forbidden_claims = ("导致", "提高评分", "降低评分", "平台支持使游戏更受欢迎")
    for path in reviewed:
        text = path.read_text(encoding="utf-8")
        assert not any(claim in text for claim in forbidden_claims)


def test_step5e_chinese_html_unicode_and_required_content() -> None:
    qmd = (REPORTS / "05_high_rating_visual_audit.qmd").read_text(encoding="utf-8")
    html = (REPORTS / "05_high_rating_visual_audit.html").read_text(encoding="utf-8")
    notation = "<" + "U+"
    escaped_notation = "&lt;" + "U+"
    assert notation not in qmd
    assert notation not in html
    assert escaped_notation not in html
    assert '<meta charset="utf-8">' in html
    for expected in ("高评分", "敏感性", "主模型", "预测变量", "置信区间", "人工审计"):
        assert expected in html
    for expected_number in (
        "836", "574", "471", "359", "0.6605", "1106.4705", "1167.9427"
    ):
        assert expected_number in html


def test_step5e_main_report_retains_primary_hierarchy() -> None:
    qmd = (REPORTS / "03_statistical_modeling.qmd").read_text(encoding="utf-8")
    assert "Step 5E: Secondary high-rating logistic analysis" in qmd
    assert "Beta-binomial remains the primary inferential analysis" in qmd
    assert "Step 5D: Pre-specified sensitivity analysis" in qmd
    assert "Step 5C" in qmd
