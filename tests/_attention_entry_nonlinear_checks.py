import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "attention"
FIGURES = ROOT / "figures" / "attention"
REPORTS = ROOT / "reports"

REQUIRED_OUTPUTS = {
    "step6a1_primary_fit.csv",
    "step6a1_primary_non_spline_coefficients.csv",
    "step6a1_spline_basis_definition.csv",
    "step6a1_price_support.csv",
    "step6a1_price_curve.csv",
    "step6a1_price_contrasts.csv",
    "step6a1_linear_vs_nonlinear.csv",
    "step6a1_calibration.csv",
    "step6a1_auc_brier.csv",
    "step6a1_influence_summary.csv",
    "step6a1_top_influence.csv",
    "step6a1_release_sensitivity.csv",
    "step6a1_genre_sensitivity.csv",
    "step6a1_price_curve_sensitivity.csv",
    "step6a1_df4_sensitivity.csv",
    "step6a1_gam_diagnostic.csv",
    "step6a1_fit_warnings.csv",
}
REQUIRED_FIGURES = {
    "45_price_nonlinear_primary_curve.png",
    "46_price_curve_support_density.png",
    "47_linear_vs_spline_price_curve.png",
    "48_nonlinear_primary_or.png",
    "49_nonlinear_calibration.png",
    "50_nonlinear_price_sensitivity.png",
    "51_price_df3_vs_df4.png",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def num(row: dict[str, str], field: str) -> float:
    return float(row[field])


def test_step6a1_required_outputs_scripts_reports_and_figures_exist() -> None:
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("step6a1_*.csv")}
    assert REQUIRED_FIGURES <= {path.name for path in FIGURES.glob("*.png")}
    assert all((FIGURES / name).stat().st_size > 20_000 for name in REQUIRED_FIGURES)
    for name in (
        "06z_nonlinear_alias.R",
        "07_nonlinear_price_basis.R",
        "08_nonlinear_entry_model.R",
        "09_nonlinear_diagnostics_sensitivity.R",
        "10_nonlinear_visuals.R",
        "11_nonlinear_report.R",
    ):
        assert (ROOT / "R" / "attention" / name).exists()
    assert (ROOT / "R" / "run_attention_entry_nonlinear.R").exists()
    for name in (
        "09_attention_entry_nonlinear_visual_audit.qmd",
        "09_attention_entry_nonlinear_visual_audit.html",
        "08_attention_modeling.qmd",
        "08_attention_modeling.html",
        "step6a1_nonlinear_attention_report.md",
    ):
        assert (REPORTS / name).exists()


def test_step6a1_primary_population_and_free_rows_are_frozen() -> None:
    fit = read_csv("step6a1_primary_fit.csv")[0]
    assert int(fit["n_games"]) == 2998
    assert int(fit["event_n"]) == 2240
    assert int(fit["non_event_n"]) == 758
    assert int(fit["parameter_count"]) == 16
    assert fit["converged"] == "TRUE"
    assert fit["matrix_rank"] == fit["matrix_columns"] == "16"
    rows = read_csv("step6a1_model_data.csv")
    assert len(rows) == 2998
    assert len({row["appid"] for row in rows}) == 2998
    free = [row for row in rows if row["is_free"] == "1"]
    assert len(free) == 402
    assert all(
        num(row, term) == 0
        for row in free
        for term in ("price_spline_1", "price_spline_2", "price_spline_3")
    )


def test_step6a1_paid_basis_is_finite_and_definition_is_deterministic() -> None:
    rows = read_csv("step6a1_model_data.csv")
    paid = [row for row in rows if row["is_free"] == "0"]
    assert len(paid) == 2596
    assert all(
        math.isfinite(num(row, term))
        for row in paid
        for term in ("price_spline_1", "price_spline_2", "price_spline_3")
    )
    basis = read_csv("step6a1_spline_basis_definition.csv")[0]
    assert basis["spline_df"] == "3"
    assert basis["intercept_in_basis"] == "FALSE"
    assert basis["centered_basis"] == "TRUE"
    assert int(basis["training_n"]) == 2597
    assert math.isclose(num(basis, "training_price_min_usd"), 0.49, abs_tol=1e-12)
    assert math.isclose(num(basis, "training_price_max_usd"), 199.99, abs_tol=1e-12)
    assert math.isclose(num(basis, "internal_knot_1_log1p"), 1.60743590976343, abs_tol=1e-12)
    assert math.isclose(num(basis, "internal_knot_2_log1p"), 2.30158459266046, abs_tol=1e-12)
    assert basis["internal_knot_3_log1p"] == ""
    assert math.isclose(num(basis, "boundary_knot_lower_log1p"), math.log1p(0.49), abs_tol=1e-12)
    assert math.isclose(num(basis, "boundary_knot_upper_log1p"), math.log1p(199.99), abs_tol=1e-12)


def test_step6a1_prediction_code_reuses_frozen_knots_and_centering() -> None:
    source = (ROOT / "R" / "attention" / "07_nonlinear_price_basis.R").read_text(encoding="utf-8")
    assert "knots = definition$knots" in source
    assert "Boundary.knots = definition$boundary_knots" in source
    assert "sweep(raw_basis, 2, definition$center_basis" in source
    assert "result[free_rows, ] <- 0" in source
    curve = read_csv("step6a1_price_curve.csv")
    assert len(curve) == 200
    assert [int(row["price_grid_index"]) for row in curve] == list(range(1, 201))
    for row in curve:
        probability = num(row, "predicted_probability")
        lower = num(row, "ci95_lower")
        upper = num(row, "ci95_upper")
        assert 0 <= lower <= probability <= upper <= 1


def test_step6a1_price_support_and_tail_counts_are_exact() -> None:
    support = read_csv("step6a1_price_support.csv")[0]
    assert int(support["paid_price_n"]) == 2597
    assert [num(support, field) for field in ("p01_usd", "p05_usd", "p25_usd", "p50_usd", "p75_usd", "p95_usd", "p99_usd")] == [
        0.99, 0.99, 2.99, 4.99, 9.99, 19.99, 39.99
    ]
    assert {field: int(support[field]) for field in ("n_ge_20_usd", "n_ge_30_usd", "n_ge_50_usd", "n_ge_100_usd")} == {
        "n_ge_20_usd": 126,
        "n_ge_30_usd": 48,
        "n_ge_50_usd": 18,
        "n_ge_100_usd": 6,
    }


def test_step6a1_formula_rows_and_nesting_lrt_are_valid() -> None:
    fit = read_csv("step6a1_primary_fit.csv")[0]
    formula = fit["formula"]
    for term in ("price_spline_1", "price_spline_2", "price_spline_3", "z_days_since_release"):
        assert term in formula
    assert "z_log1p_paid_price_component" not in formula
    assert "offset" not in formula.lower()
    assert ":" not in formula and "*" not in formula
    comparison = read_csv("step6a1_linear_vs_nonlinear.csv")
    assert {row["n_games"] for row in comparison} == {"2998"}
    assert num(comparison[1], "aic") < num(comparison[0], "aic") - 10
    nesting = read_csv("step6a1_nesting_audit.csv")
    assert len(nesting) == 2
    assert all(row["same_rows"] == row["strictly_nested"] == row["formal_lrt_valid"] == "TRUE" for row in nesting)
    assert all(num(row, "max_reduced_projection_residual") < 1e-8 for row in nesting)
    assert all(num(row, "lrt_p_value") < 0.001 for row in nesting)


def test_step6a1_peak_representative_points_and_contrasts_are_coherent() -> None:
    peak = read_csv("step6a1_peak_audit.csv")[0]
    assert 14 <= num(peak, "peak_price_usd") <= 16
    assert 0 < num(peak, "peak_ci95_lower") < num(peak, "peak_predicted_probability") < num(peak, "peak_ci95_upper") < 1
    assert peak["peak_within_central_5_95_support"] == "TRUE"
    assert num(peak, "plateau_lower_price_usd") < num(peak, "peak_price_usd") < num(peak, "plateau_upper_price_usd")
    representative = read_csv("step6a1_representative_price_predictions.csv")
    assert [num(row, "price_usd") for row in representative] == [0.99, 2.99, 4.99, 9.99, 14.99, 19.99, 29.99, 49.99]
    contrasts = {row["contrast_id"]: row for row in read_csv("step6a1_price_contrasts.csv")}
    assert num(contrasts["4.99_TO_9.99"], "percentage_point_difference") > 5
    assert 0 < num(contrasts["9.99_TO_14.99"], "percentage_point_difference") < 2
    assert num(contrasts["14.99_TO_29.99"], "percentage_point_difference") < 0


def test_step6a1_nonprice_results_and_free_contrast_remain_coherent() -> None:
    coefficients = {row["term"]: row for row in read_csv("step6a1_primary_non_spline_coefficients.csv")}
    assert num(coefficients["is_free"], "odds_ratio") < 0.02
    assert num(coefficients["genre_adventure"], "or_ci95_lower") > 1
    assert num(coefficients["genre_casual"], "or_ci95_upper") < 1
    assert num(coefficients["genre_simulation"], "or_ci95_lower") > 1
    free = read_csv("step6a1_free_contrast.csv")[0]
    assert num(free, "free_probability") < 0.1
    assert num(free, "free_minus_paid_percentage_point_difference") < -70


def test_step6a1_diagnostics_calibration_and_scores_pass() -> None:
    separation = read_csv("step6a1_separation_diagnostics.csv")
    assert len(separation) == 8
    assert all(row["n_flagged"] == "0" for row in separation)
    influence = read_csv("step6a1_influence_summary.csv")[0]
    assert int(influence["n_influence_diagnostics_not_defined"]) == 0
    assert num(influence, "max_cooks_distance") < 0.5
    assert influence["n_cooks_above_0_5"] == influence["n_cooks_above_1"] == "0"
    assert len(read_csv("step6a1_top_influence.csv")) == 20
    calibration = read_csv("step6a1_calibration.csv")
    assert {row["model_id"] for row in calibration} == {"LINEAR_BENCHMARK", "NONLINEAR_PRICE_DF3_PRIMARY"}
    nonlinear = [row for row in calibration if row["model_id"] == "NONLINEAR_PRICE_DF3_PRIMARY"]
    assert len(nonlinear) == 10
    assert sum(int(row["n_games"]) for row in nonlinear) == 2998
    assert max(num(row, "absolute_gap") for row in nonlinear) <= 0.05
    scores = {row["model_id"]: row for row in read_csv("step6a1_auc_brier.csv")}
    assert num(scores["NONLINEAR_PRICE_DF3_PRIMARY"], "auc") >= num(scores["LINEAR_BENCHMARK"], "auc")
    assert num(scores["NONLINEAR_PRICE_DF3_PRIMARY"], "brier_score") < num(scores["LINEAR_BENCHMARK"], "brier_score")
    assert num(scores["NONLINEAR_PRICE_DF3_PRIMARY"], "binary_log_loss") < num(scores["LINEAR_BENCHMARK"], "binary_log_loss")


def test_step6a1_release_genre_and_curve_sensitivities_are_stable() -> None:
    release = read_csv("step6a1_release_sensitivity.csv")
    genre = read_csv("step6a1_genre_sensitivity.csv")
    assert {row["model_id"] for row in release} == {"NONLINEAR_PRICE_DF3_PRIMARY", "RELEASE_MONTH_SENSITIVITY"}
    assert {row["model_id"] for row in genre} == {"NONLINEAR_PRICE_DF3_PRIMARY", "EXPANDED_GENRE_SENSITIVITY"}
    expanded_terms = {row["term"] for row in genre if row["model_id"] == "EXPANDED_GENRE_SENSITIVITY"}
    assert {"genre_early_access", "genre_sports", "genre_racing"} <= expanded_terms
    curve = read_csv("step6a1_price_curve_sensitivity.csv")
    assert len(curve) == 600
    assert {row["model_id"] for row in curve} == {
        "NONLINEAR_PRICE_DF3_PRIMARY", "RELEASE_MONTH_SENSITIVITY", "EXPANDED_GENRE_SENSITIVITY"
    }
    summary = read_csv("step6a1_price_curve_sensitivity_summary.csv")
    assert all(num(row, "max_absolute_probability_difference_central_5_95") <= 0.03 for row in summary)


def test_step6a1_df4_and_optional_gam_are_limited_diagnostics() -> None:
    df4 = read_csv("step6a1_df4_sensitivity.csv")
    assert [row["spline_df"] for row in df4] == ["3", "4"]
    assert all(row["n_games"] == "2998" and row["converged"] == "TRUE" for row in df4)
    assert num(df4[1], "max_abs_probability_difference_vs_df3_central_5_95") <= 0.05
    source = (ROOT / "R" / "attention" / "09_nonlinear_diagnostics_sensitivity.R").read_text(encoding="utf-8")
    assert "df = 4L" in source
    assert "df = 5L" not in source and "df = 6L" not in source
    gam = read_csv("step6a1_gam_diagnostic.csv")[0]
    assert gam["status"] in {"RUN", "NOT_RUN"}
    if gam["status"] == "RUN":
        assert gam["package_available"] == "TRUE"
        assert num(gam, "edf") > 1
        assert num(gam, "max_abs_probability_difference_vs_df3_central_5_95") <= 0.05
        assert (FIGURES / "52_price_spline_vs_gam.png").stat().st_size > 20_000


def test_step6a1_freeze_database_unicode_and_credentials_pass() -> None:
    criteria = read_csv("step6a1_freeze_criteria.csv")
    assert len(criteria) == 8
    assert all(row["passed"] == "TRUE" for row in criteria)
    decision = read_csv("step6a1_stage_decision.csv")[0]
    assert decision["step6a1_status"] == "PASS"
    assert decision["price_functional_form"] == "SPLINE ADEQUATE"
    assert decision["review_entry_model_frozen"] == "TRUE"
    assert decision["ready_for_step6b"] == "TRUE"
    db = read_csv("step6a1_database_preservation.csv")
    expected = {"games": 3000, "review_snapshots": 3000, "game_genres": 8796, "genres": 13, "model20": 844}
    assert {row["object_name"]: int(float(row["count_before"])) for row in db} == expected
    assert {row["object_name"]: int(float(row["count_after"])) for row in db} == expected
    assert all(row["unchanged"] == "TRUE" for row in db)
    checked = list(OUTPUT.glob("step6a1_*.csv")) + [
        REPORTS / "09_attention_entry_nonlinear_visual_audit.qmd",
        REPORTS / "09_attention_entry_nonlinear_visual_audit.html",
        REPORTS / "08_attention_modeling.qmd",
        REPORTS / "08_attention_modeling.html",
        REPORTS / "step6a1_nonlinear_attention_report.md",
    ]
    notation = "<" + "U+"
    escaped = "&lt;" + "U+"
    for path in checked:
        content = path.read_text(encoding="utf-8")
        assert notation not in content and escaped not in content
        lower = content.lower()
        for unsafe in ("mysql_password", "password=", "dsn=", ".env"):
            assert unsafe not in lower
    visual_html = (REPORTS / "09_attention_entry_nonlinear_visual_audit.html").read_text(encoding="utf-8")
    assert '<meta charset="utf-8">' in visual_html
    for expected_text in ("为什么 Step 6A 不能冻结", "Price Data Support", "人工审计清单", "Freeze Decision"):
        assert expected_text in visual_html
