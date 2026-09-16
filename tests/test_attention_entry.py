import importlib.util
from pathlib import Path


CHECKS_PATH = Path(__file__).with_name("_attention_entry_checks.py")
SPEC = importlib.util.spec_from_file_location("step6a_checks", CHECKS_PATH)
assert SPEC is not None and SPEC.loader is not None
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


def test_step6a_required_outputs_scripts_reports_and_figures_exist() -> None:
    checks.test_step6a_required_outputs_scripts_reports_and_figures_exist()


def test_step6a_market_outcome_identity_and_unique_appids() -> None:
    checks.test_step6a_market_outcome_identity_and_unique_appids()


def test_step6a_free_games_retained_and_price_component_is_coherent() -> None:
    checks.test_step6a_free_games_retained_and_price_component_is_coherent()


def test_step6a_paid_price_scaling_and_missingness_are_auditable() -> None:
    checks.test_step6a_paid_price_scaling_and_missingness_are_auditable()


def test_step6a_primary_formula_population_and_fit_are_frozen() -> None:
    checks.test_step6a_primary_formula_population_and_fit_are_frozen()


def test_step6a_coefficients_profile_ci_and_separation_diagnostics() -> None:
    checks.test_step6a_coefficients_profile_ci_and_separation_diagnostics()


def test_step6a_probability_contrasts_use_one_reference_and_paid_price_scope() -> None:
    checks.test_step6a_probability_contrasts_use_one_reference_and_paid_price_scope()


def test_step6a_functional_form_audit_is_same_sample_and_df3_only() -> None:
    checks.test_step6a_functional_form_audit_is_same_sample_and_df3_only()


def test_step6a_calibration_auc_and_influence_are_complete() -> None:
    checks.test_step6a_calibration_auc_and_influence_are_complete()


def test_step6a_release_and_genre_sensitivities_are_prespecified() -> None:
    checks.test_step6a_release_and_genre_sensitivities_are_prespecified()


def test_step6a_database_preservation_stage_gate_and_credential_safety() -> None:
    checks.test_step6a_database_preservation_stage_gate_and_credential_safety()


def test_step6a_utf8_reports_and_attention_reception_boundaries() -> None:
    checks.test_step6a_utf8_reports_and_attention_reception_boundaries()


def test_step6a_source_has_no_count_model_offset_interaction_or_machine_learning() -> None:
    root = Path(__file__).resolve().parents[1]
    sources = "\n".join(
        path.read_text(encoding="utf-8").lower()
        for path in (root / "R" / "attention").glob("*.R")
    )
    for forbidden_execution in (
        "family = poisson(",
        "family=poisson(",
        "negative.binomial(",
        "zeroinfl(",
        "xgboost::",
        "xgb.train(",
        "randomforest::",
        "lightgbm::",
        "keras::",
        "torch::",
    ):
        assert forbidden_execution not in sources
    primary = (root / "R" / "attention" / "02_entry_logistic.R").read_text(encoding="utf-8")
    assert "offset(" not in primary
    assert "is_free *" not in primary and "is_free:" not in primary
