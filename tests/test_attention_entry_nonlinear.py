import importlib.util
from pathlib import Path


CHECKS_PATH = Path(__file__).with_name("_attention_entry_nonlinear_checks.py")
SPEC = importlib.util.spec_from_file_location("step6a1_checks", CHECKS_PATH)
assert SPEC is not None and SPEC.loader is not None
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


def test_step6a1_required_outputs_scripts_reports_and_figures_exist() -> None:
    checks.test_step6a1_required_outputs_scripts_reports_and_figures_exist()


def test_step6a1_primary_population_and_free_rows_are_frozen() -> None:
    checks.test_step6a1_primary_population_and_free_rows_are_frozen()


def test_step6a1_paid_basis_is_finite_and_definition_is_deterministic() -> None:
    checks.test_step6a1_paid_basis_is_finite_and_definition_is_deterministic()


def test_step6a1_prediction_code_reuses_frozen_knots_and_centering() -> None:
    checks.test_step6a1_prediction_code_reuses_frozen_knots_and_centering()


def test_step6a1_price_support_and_tail_counts_are_exact() -> None:
    support = checks.read_csv("step6a1_price_support.csv")[0]
    assert int(support["paid_price_n"]) == 2597
    assert [checks.num(support, field) for field in (
        "p01_usd", "p05_usd", "p25_usd", "p50_usd", "p75_usd", "p95_usd", "p99_usd"
    )] == [0.99, 0.99, 2.99, 4.99, 9.99, 19.99, 39.99]
    assert {field: int(support[field]) for field in (
        "n_ge_20_usd", "n_ge_30_usd", "n_ge_50_usd", "n_ge_100_usd"
    )} == {
        "n_ge_20_usd": 126,
        "n_ge_30_usd": 46,
        "n_ge_50_usd": 18,
        "n_ge_100_usd": 6,
    }


def test_step6a1_formula_rows_and_nesting_lrt_are_valid() -> None:
    checks.test_step6a1_formula_rows_and_nesting_lrt_are_valid()


def test_step6a1_peak_representative_points_and_contrasts_are_coherent() -> None:
    checks.test_step6a1_peak_representative_points_and_contrasts_are_coherent()


def test_step6a1_nonprice_results_and_free_contrast_remain_coherent() -> None:
    coefficients = {
        row["term"]: row
        for row in checks.read_csv("step6a1_primary_non_spline_coefficients.csv")
    }
    assert checks.num(coefficients["is_free"], "odds_ratio") < 0.02
    assert checks.num(coefficients["genre_adventure"], "estimate_log_odds") > 0
    assert checks.num(coefficients["genre_casual"], "or_ci95_upper") < 1
    assert checks.num(coefficients["genre_simulation"], "or_ci95_lower") > 1
    free = checks.read_csv("step6a1_free_contrast.csv")[0]
    assert checks.num(free, "free_probability") < 0.1
    assert checks.num(free, "free_minus_paid_percentage_point_difference") < -70


def test_step6a1_diagnostics_calibration_and_scores_pass() -> None:
    checks.test_step6a1_diagnostics_calibration_and_scores_pass()


def test_step6a1_release_genre_and_curve_sensitivities_are_stable() -> None:
    checks.test_step6a1_release_genre_and_curve_sensitivities_are_stable()


def test_step6a1_df4_and_optional_gam_are_limited_diagnostics() -> None:
    checks.test_step6a1_df4_and_optional_gam_are_limited_diagnostics()


def test_step6a1_freeze_database_unicode_and_credentials_pass() -> None:
    criteria = checks.read_csv("step6a1_freeze_criteria.csv")
    assert len(criteria) == 8
    assert all(row["passed"] == "TRUE" for row in criteria)
    decision = checks.read_csv("step6a1_stage_decision.csv")[0]
    assert decision["step6a1_status"] == "PASS"
    assert decision["price_functional_form"] == "SPLINE ADEQUATE"
    assert decision["review_entry_model_frozen"] == "TRUE"
    assert decision["ready_for_step6b"] == "TRUE"
    db = checks.read_csv("step6a1_database_preservation.csv")
    expected = {
        "games": 3000,
        "review_snapshots": 3000,
        "game_genres": 8796,
        "genres": 13,
        "model20": 844,
    }
    assert {row["object_name"]: int(float(row["count_before"])) for row in db} == expected
    assert {row["object_name"]: int(float(row["count_after"])) for row in db} == expected
    assert all(row["unchanged"] == "TRUE" for row in db)

    reports = [
        checks.REPORTS / "09_attention_entry_nonlinear_visual_audit.qmd",
        checks.REPORTS / "09_attention_entry_nonlinear_visual_audit.html",
        checks.REPORTS / "08_attention_modeling.qmd",
        checks.REPORTS / "08_attention_modeling.html",
        checks.REPORTS / "step6a1_nonlinear_attention_report.md",
    ]
    notation = "<" + "U+"
    escaped = "&lt;" + "U+"
    for path in reports:
        content = path.read_text(encoding="utf-8")
        assert notation not in content and escaped not in content

    credential_files = list(checks.OUTPUT.glob("step6a1_*.csv")) + reports
    for path in credential_files:
        lower = path.read_text(encoding="utf-8").lower()
        for unsafe in ("mysql_password", "password=", "dsn=", ".env"):
            assert unsafe not in lower

    visual_html = (
        checks.REPORTS / "09_attention_entry_nonlinear_visual_audit.html"
    ).read_text(encoding="utf-8")
    assert '<meta charset="utf-8">' in visual_html
    for expected_text in (
        "为什么 Step 6A 不能冻结",
        "Price Data Support",
        "人工审计清单",
        "Freeze Decision",
    ):
        assert expected_text in visual_html
