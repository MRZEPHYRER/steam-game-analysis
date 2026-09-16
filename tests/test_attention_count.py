import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "analysis" / "attention"
FIG = ROOT / "figures" / "attention"
REPORTS = ROOT / "reports"

def read_csv(name: str) -> list[dict[str, str]]:
    with (OUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))

def test_step6b_required_outputs_figures_scripts_and_reports_exist() -> None:
    required_csv = {
        "step6b_count_distribution.csv", "step6b_review_count_bins.csv",
        "step6b_concentration.csv", "step6b_poisson_fit.csv",
        "step6b_poisson_diagnostics.csv", "step6b_nb_fit.csv",
        "step6b_truncated_nb_fit.csv", "step6b_model_comparison.csv",
        "step6b_final_coefficients.csv", "step6b_exposure_audit.csv",
        "step6b_price_basis_definition.csv", "step6b_price_curve.csv",
        "step6b_exposure_curve.csv", "step6b_probability_count_contrasts.csv",
        "step6b_tail_sensitivity.csv", "step6b_coefficient_sensitivity.csv",
        "step6b_price_curve_sensitivity.csv", "step6b_platform_summary.csv",
        "step6b_genre_summary.csv", "step6b_free_summary.csv",
        "step6b_residual_diagnostics.csv", "step6b_fit_warnings.csv",
        "step6b_freeze_criteria.csv", "step6b_stage_decision.csv"}
    assert required_csv <= {p.name for p in OUT.glob("step6b_*.csv")}
    required_fig = {f"{n:02d}_{suffix}" for n, suffix in (
        (53, "review_count_price_curve.png"), (54, "review_count_exposure_curve.png"),
        (55, "count_rootogram.png"), (56, "poisson_vs_nb_fit.png"),
        (57, "nb_residual_diagnostics.png"), (58, "tail_concentration.png"),
        (59, "tail_sensitivity_coefficients.png"),
        (60, "price_curve_tail_sensitivity.png"),
        (61, "platform_review_volume.png"), (62, "genre_review_volume.png"),
        (63, "hurdle_decomposition.png"))}
    assert required_fig <= {p.name for p in FIG.glob("*.png")}
    assert all((FIG / name).stat().st_size > 10_000 for name in required_fig)
    for name in ("10_attention_count_visual_audit.qmd",
                 "10_attention_count_visual_audit.html",
                 "08_attention_modeling.qmd", "08_attention_modeling.html",
                 "step6b_attention_count_report.md"):
        assert (REPORTS / name).exists()

def test_step6b_positive_population_and_free_price_contract() -> None:
    sample = read_csv("step6b_model_sample_audit.csv")[0]
    assert {k: int(sample[k]) for k in ("market_n", "zero_review_n", "positive_n",
      "positive_free_n", "positive_paid_n", "model_n", "excluded_n")} == {
      "market_n": 3000, "zero_review_n": 759, "positive_n": 2241,
      "positive_free_n": 34, "positive_paid_n": 2207,
      "model_n": 2240, "excluded_n": 1}
    distribution = read_csv("step6b_count_distribution.csv")[0]
    assert int(distribution["n"]) == 2241 and float(distribution["min"]) >= 1

def test_step6b_models_same_sample_no_weights_or_zero_inflation() -> None:
    rows = read_csv("step6b_model_comparison.csv")
    assert [r["model_id"] for r in rows] == [
        "M1_POISSON", "M2_NB2_ORDINARY", "M3_TRUNCATED_NB2"]
    assert {int(r["n_games"]) for r in rows} == {2240}
    assert all(r["converged"] == r["same_observed_rows"] ==
               r["full_likelihood_constants_verified"] == "TRUE" for r in rows)
    assert all(r["weights_used"] == r["zero_inflation_used"] == "FALSE" for r in rows)
    assert all("is_free" in r["formula"] and "price_spline_1" in r["formula"] for r in rows)

def test_step6b_exposure_and_price_basis_are_deterministic() -> None:
    exposure = read_csv("step6b_exposure_audit.csv")
    assert {r["specification"] for r in exposure} == {
        "LOG_DAYS_COVARIATE", "OFFSET", "NONLINEAR_LOG_DAYS"}
    assert all(int(r["n_games"]) == 2240 for r in exposure)
    assert float(next(r for r in exposure if r["specification"] == "OFFSET")
                 ["delta_aic_from_best"]) == 0
    basis = read_csv("step6b_price_basis_definition.csv")[0]
    assert int(basis["training_n"]) == 2206 and int(basis["df"]) == 3
    assert float(basis["price_min_usd"]) == .49 and float(basis["price_max_usd"]) == 199.99
    for field in ("internal_knot_1_log1p", "internal_knot_2_log1p",
                  "boundary_lower_log1p", "boundary_upper_log1p"):
        assert math.isfinite(float(basis[field]))
    assert all(float(r["predicted_positive_count"]) > 0
               for r in read_csv("step6b_price_curve.csv"))

def test_step6b_diagnostics_fail_freeze_honestly() -> None:
    poisson = read_csv("step6b_poisson_diagnostics.csv")[0]
    assert float(poisson["pearson_dispersion"]) > 1000
    assert poisson["inference_valid"] == "FALSE"
    decision = read_csv("step6b_stage_decision.csv")[0]
    assert decision["status"] == "FAIL"
    assert decision["positive_count_model_frozen"] == "FALSE"
    failed = set(decision["failed_criteria"].split("; "))
    assert {"no_single_observation_dominates", "tail_sensitivity_acceptable",
            "diagnostics_acceptable"} <= failed
    assert max(float(r["max_relative_predicted_count_difference"])
               for r in read_csv("step6b_price_curve_sensitivity.csv")) > .5

def test_step6b_database_unicode_and_credential_safety() -> None:
    expected = {"games": 3000, "review_snapshots": 3000,
                "game_genres": 8796, "genres": 13, "model20": 844}
    db = read_csv("step6b_database_preservation.csv")
    assert {r["object_name"]: int(float(r["count_before"])) for r in db} == expected
    assert {r["object_name"]: int(float(r["count_after"])) for r in db} == expected
    assert all(r["unchanged"] == "TRUE" for r in db)
    paths = [REPORTS / "10_attention_count_visual_audit.qmd",
             REPORTS / "10_attention_count_visual_audit.html",
             REPORTS / "08_attention_modeling.qmd",
             REPORTS / "08_attention_modeling.html",
             REPORTS / "step6b_attention_count_report.md"]
    notation = "<" + "U+"
    for path in paths:
        content = path.read_text(encoding="utf-8")
        assert notation not in content and "&lt;U+" not in content
        lower = content.lower()
        assert "mysql_password" not in lower and "password=" not in lower and "dsn=" not in lower
