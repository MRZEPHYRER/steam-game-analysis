import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "attention"
FIGURES = ROOT / "figures" / "attention"
REPORTS = ROOT / "reports"

REQUIRED_OUTPUTS = {
    "step6a_market_outcome_summary.csv", "step6a_free_paid_summary.csv",
    "step6a_month_summary.csv", "step6a_platform_summary.csv",
    "step6a_genre_summary.csv", "step6a_primary_fit.csv",
    "step6a_primary_coefficients.csv", "step6a_primary_profile_ci.csv",
    "step6a_outcome_cells.csv", "step6a_influence_summary.csv",
    "step6a_top_influence.csv", "step6a_calibration.csv", "step6a_auc.csv",
    "step6a_probability_contrasts.csv", "step6a_price_functional_form.csv",
    "step6a_days_functional_form.csv", "step6a_release_sensitivity.csv",
    "step6a_genre_sensitivity.csv", "step6a_fit_warnings.csv",
}
REQUIRED_FIGURES = {
    "35_days_review_entry_curve.png", "36_paid_price_review_entry_curve.png",
    "37_attention_entry_calibration.png", "38_attention_entry_roc.png",
    "39_attention_entry_primary_or.png", "40_free_paid_attention.png",
    "41_platform_attention.png", "42_genre_attention.png",
    "43_release_attention.png", "44_functional_form_comparison.png",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def num(row: dict[str, str], field: str) -> float:
    return float(row[field])


def test_step6a_required_outputs_scripts_reports_and_figures_exist() -> None:
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("step6a_*.csv")}
    assert REQUIRED_FIGURES <= {path.name for path in FIGURES.glob("*.png")}
    assert all((FIGURES / name).stat().st_size > 20_000 for name in REQUIRED_FIGURES)
    for name in (
        "00_attention_helpers.R", "01_attention_data_audit.R", "02_entry_logistic.R",
        "03_functional_form_audit.R", "04_entry_diagnostics.R",
        "05_entry_visuals.R", "06_entry_report.R",
    ):
        assert (ROOT / "R" / "attention" / name).exists()
    assert (ROOT / "R" / "run_attention_entry.R").exists()
    for name in (
        "07_attention_entry_visual_audit.qmd", "07_attention_entry_visual_audit.html",
        "08_attention_modeling.qmd", "08_attention_modeling.html",
        "step6a_attention_entry_report.md",
    ):
        assert (REPORTS / name).exists()


def test_step6a_market_outcome_identity_and_unique_appids() -> None:
    summary = read_csv("step6a_market_outcome_summary.csv")[0]
    assert int(summary["market_n"]) == int(summary["unique_appids"]) == 3000
    assert int(summary["has_review_n"]) == 2241
    assert int(summary["zero_review_n"]) == 759
    assert math.isclose(num(summary, "has_review_rate"), 2241 / 3000, abs_tol=1e-15)
    rows = read_csv("step6a_market_data.csv")
    assert len(rows) == 3000
    assert len({row["appid"] for row in rows}) == 3000
    assert sum(int(row["has_review"]) for row in rows) == 2241
    for row in rows:
        assert int(row["has_review"]) == int(int(row["total_reviews"]) > 0)


def test_step6a_free_games_retained_and_price_component_is_coherent() -> None:
    market = read_csv("step6a_market_data.csv")
    free = [row for row in market if row["is_free"] == "1"]
    paid = [row for row in market if row["is_free"] == "0"]
    assert len(free) == 402
    assert len(paid) == 2598
    assert all(num(row, "z_log1p_paid_price_component") == 0 for row in free)
    summary = {row["game_type"]: row for row in read_csv("step6a_free_paid_summary.csv")}
    assert int(summary["Free"]["n_games"]) == 402
    assert int(summary["Paid"]["n_games"]) == 2598
    assert int(summary["Free"]["has_review_n"]) == 34
    assert int(summary["Paid"]["has_review_n"]) == 2207
    assert num(summary["Free"], "has_review_rate") < num(summary["Paid"], "has_review_rate")
    assert num(summary["Free"], "raw_risk_difference_free_minus_paid") < -0.7
    assert num(summary["Free"], "raw_odds_ratio_free_vs_paid") < 0.02


def test_step6a_paid_price_scaling_and_missingness_are_auditable() -> None:
    scaling = read_csv("step6a_paid_price_scaling.csv")[0]
    assert scaling["scaling_population"] == "All paid market games with non-missing current price"
    assert int(scaling["paid_price_n"]) == 2597
    assert int(scaling["missing_paid_price_n"]) == 1
    assert num(scaling, "log1p_price_sd") > 0
    missing = read_csv("step6a_missing_paid_price.csv")
    assert len(missing) == 1
    assert missing[0]["appid"] == "3797390"
    exclusions = {row["reason"]: int(row["n_games"]) for row in read_csv("step6a_sample_exclusions.csv")}
    assert exclusions == {
        "paid_current_price_missing": 1,
        "days_since_release_missing": 0,
        "platform_segment_outside_prespecified_four": 1,
        "primary_model_total_excluded": 2,
    }


def test_step6a_primary_formula_population_and_fit_are_frozen() -> None:
    fit = read_csv("step6a_primary_fit.csv")[0]
    assert int(fit["n_games"]) == 2998
    assert int(fit["event_n"]) == 2240
    assert int(fit["non_event_n"]) == 758
    assert int(fit["parameter_count"]) == 14
    assert fit["converged"] == "TRUE"
    assert fit["matrix_rank"] == fit["matrix_columns"] == "14"
    assert fit["weights_used"] == "FALSE"
    assert fit["count_offset_used"] == "FALSE"
    assert fit["interactions_used"] == "FALSE"
    formula = fit["formula"]
    expected = {
        "is_free", "z_log1p_paid_price_component", "z_days_since_release",
        "platform_segment", "genre_action", "genre_adventure", "genre_casual",
        "genre_indie", "genre_rpg", "genre_simulation", "genre_strategy",
    }
    assert expected <= {term.strip() for term in formula.split("~", 1)[1].split("+")}
    assert "offset" not in formula.lower()
    assert ":" not in formula and "*" not in formula


def test_step6a_coefficients_profile_ci_and_separation_diagnostics() -> None:
    coefficients = read_csv("step6a_primary_coefficients.csv")
    assert len(coefficients) == 14
    assert all(math.isfinite(num(row, "estimate_log_odds")) for row in coefficients)
    assert all(num(row, "std_error") > 0 for row in coefficients)
    assert all(num(row, "odds_ratio") > 0 for row in coefficients)
    assert all(num(row, "or_ci95_lower") < num(row, "odds_ratio") < num(row, "or_ci95_upper") for row in coefficients)
    profile = read_csv("step6a_primary_profile_ci.csv")
    assert len(profile) == 14
    assert all(row["status"] in {"PASS", "PASS_WITH_WARNING"} for row in profile)
    separation = read_csv("step6a_separation_diagnostics.csv")
    assert len(separation) == 8
    assert all(int(row["n_flagged"]) == 0 for row in separation)
    cells = read_csv("step6a_outcome_cells.csv")
    assert all(row["zero_event_cell"] == "FALSE" for row in cells)
    assert all(row["zero_non_event_cell"] == "FALSE" for row in cells)


def test_step6a_probability_contrasts_use_one_reference_and_paid_price_scope() -> None:
    rows = read_csv("step6a_probability_contrasts.csv")
    assert len(rows) == 14
    reference = next(row for row in rows if row["scenario"] == "REFERENCE")
    reference_probability = num(reference, "reference_probability")
    assert 0 < reference_probability < 1
    assert num(reference, "modified_probability") == reference_probability
    price = next(row for row in rows if row["scenario"] == "PAID_PRICE_PLUS_1_SD")
    assert price["interpretation_scope"] == "Paid games only price gradient"
    free = next(row for row in rows if row["scenario"] == "FREE_VS_PAID")
    assert num(free, "percentage_point_difference") < -70
    assert all(math.isclose(num(row, "reference_probability"), reference_probability, abs_tol=1e-15) for row in rows)


def test_step6a_functional_form_audit_is_same_sample_and_df3_only() -> None:
    days = read_csv("step6a_days_functional_form.csv")
    price = read_csv("step6a_price_functional_form.csv")
    assert [row["model_id"] for row in days] == ["LINEAR_DAYS", "SPLINE_DAYS_DF3"]
    assert [row["model_id"] for row in price] == ["LINEAR_PRICE", "SPLINE_PRICE_DF3"]
    assert len({row["n_games"] for row in days}) == 1
    assert len({row["n_games"] for row in price}) == 1
    assert all(row["same_rows_within_comparison"] == "TRUE" for row in days + price)
    assert all(row["converged"] == "TRUE" and row["warning_count"] == "0" for row in days + price)
    assert {row["spline_df"] for row in days + price if "SPLINE" in row["model_id"]} == {"3"}
    decisions = {row["predictor"]: row for row in read_csv("step6a_functional_form_decision.csv")}
    assert decisions["days_since_release"]["assessment"] == "MODEST_NONLINEARITY"
    assert num(decisions["days_since_release"], "delta_aic_spline_minus_linear") > 0
    assert decisions["paid_log1p_price"]["assessment"] == "SUBSTANTIVE_NONLINEARITY"
    assert num(decisions["paid_log1p_price"], "delta_aic_spline_minus_linear") < -10
    assert num(decisions["paid_log1p_price"], "lrt_p_value") < 0.001


def test_step6a_calibration_auc_and_influence_are_complete() -> None:
    calibration = read_csv("step6a_calibration.csv")
    assert len(calibration) == 10
    assert sum(int(row["n_games"]) for row in calibration) == 2998
    assert all(0 <= num(row, "mean_predicted_probability") <= 1 for row in calibration)
    assert all(0 <= num(row, "observed_has_review_rate") <= 1 for row in calibration)
    assert max(num(row, "absolute_gap") for row in calibration) < 0.03
    auc = read_csv("step6a_auc.csv")[0]
    assert 0.75 < num(auc, "auc") < 0.85
    assert 0 < num(auc, "ci95_lower") < num(auc, "auc") < num(auc, "ci95_upper") < 1
    influence = read_csv("step6a_influence_summary.csv")[0]
    assert int(influence["n_games"]) == 2998
    assert int(influence["n_influence_diagnostics_not_defined"]) == 0
    assert num(influence, "max_leverage") < 0.1
    assert num(influence, "max_cooks_distance") < 0.5
    assert influence["n_cooks_above_0_5"] == influence["n_cooks_above_1"] == "0"
    assert len(read_csv("step6a_top_influence.csv")) == 20


def test_step6a_release_and_genre_sensitivities_are_prespecified() -> None:
    fits = read_csv("step6a_sensitivity_fit_summary.csv")
    assert {row["model_id"] for row in fits} == {
        "PRIMARY_LINEAR", "RELEASE_MONTH_ALTERNATIVE", "EXPANDED_GENRES"
    }
    assert all(row["n_games"] == "2998" for row in fits)
    assert all(row["converged"] == "TRUE" and row["warning_count"] == "0" for row in fits)
    release = read_csv("step6a_release_sensitivity.csv")
    release_formula = next(row["formula"] for row in fits if row["model_id"] == "RELEASE_MONTH_ALTERNATIVE")
    assert "release_month" in release_formula and "z_days_since_release" not in release_formula
    assert {row["model_id"] for row in release} == {"PRIMARY_LINEAR", "RELEASE_MONTH_ALTERNATIVE"}
    expanded = read_csv("step6a_genre_sensitivity.csv")
    expanded_terms = {row["term"] for row in expanded if row["model_id"] == "EXPANDED_GENRES"}
    assert {"genre_early_access", "genre_sports", "genre_racing"} <= expanded_terms
    assert "genre_free_to_play" not in expanded_terms
    assert "genre_massively_multiplayer" not in expanded_terms


def test_step6a_database_preservation_stage_gate_and_credential_safety() -> None:
    db = read_csv("step6a_database_preservation.csv")
    expected = {
        "games": 3000, "review_snapshots": 3000, "game_genres": 8796,
        "genres": 13, "model20": 844,
    }
    assert {row["object_name"]: int(float(row["count_before"])) for row in db} == expected
    assert {row["object_name"]: int(float(row["count_after"])) for row in db} == expected
    assert all(row["unchanged"] == "TRUE" for row in db)
    decision = read_csv("step6a_stage_decision.csv")[0]
    assert decision["step6a_audit_status"] == "PASS"
    assert decision["linear_predictor_adequacy"] == "INADEQUATE"
    assert decision["step6a_ready_to_freeze"] == "FALSE"
    assert decision["ready_for_step6b"] == "FALSE"
    checked = list(OUTPUT.glob("step6a_*.csv")) + [
        REPORTS / "07_attention_entry_visual_audit.qmd",
        REPORTS / "07_attention_entry_visual_audit.html",
        REPORTS / "08_attention_modeling.qmd", REPORTS / "08_attention_modeling.html",
        REPORTS / "step6a_attention_entry_report.md",
    ]
    for path in checked:
        content = path.read_bytes().lower()
        for unsafe in (b"mysql_password", b"password=", b"dsn=", b".env"):
            assert unsafe not in content


def test_step6a_utf8_reports_and_attention_reception_boundaries() -> None:
    notation = "<" + "U+"
    escaped = "&lt;" + "U+"
    for name in (
        "07_attention_entry_visual_audit.qmd", "07_attention_entry_visual_audit.html",
        "08_attention_modeling.qmd", "08_attention_modeling.html",
        "step6a_attention_entry_report.md",
    ):
        text = (REPORTS / name).read_text(encoding="utf-8")
        assert notation not in text and escaped not in text
    visual_html = (REPORTS / "07_attention_entry_visual_audit.html").read_text(encoding="utf-8")
    assert '<meta charset="utf-8">' in visual_html
    for expected in ("Attention 与 Reception", "人工审计重点", "函数形式", "Free vs Paid", "阶段性结论"):
        assert expected in visual_html
    main_reception_qmd = (REPORTS / "03_statistical_modeling.qmd").read_text(encoding="utf-8")
    assert "Step 6A" not in main_reception_qmd


def test_step6a_source_has_no_count_model_offset_interaction_or_machine_learning() -> None:
    sources = "\n".join(
        path.read_text(encoding="utf-8").lower()
        for path in (ROOT / "R" / "attention").glob("*.R")
    )
    for forbidden in (
        "family = poisson", "family=poisson", "negative.binomial", "zeroinfl",
        "xgboost", "randomforest", "lightgbm", "neural network",
    ):
        assert forbidden not in sources
    primary = (ROOT / "R" / "attention" / "02_entry_logistic.R").read_text(encoding="utf-8")
    assert "offset(" not in primary
    assert "is_free *" not in primary and "is_free:" not in primary
