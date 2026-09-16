from __future__ import annotations

import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "modeling"
FIGURES = ROOT / "figures" / "modeling"

REQUIRED_OUTPUTS = {
    "step5c_quasi_coefficients.csv",
    "step5c_quasi_fit.csv",
    "step5c_quasi_inflation.csv",
    "step5c_beta_binomial_fit.csv",
    "step5c_beta_binomial_coefficients.csv",
    "step5c_beta_dispersion.csv",
    "step5c_beta_diagnostics.csv",
    "step5c_specification_audit.csv",
    "step5c_database_preservation.csv",
    "step5c_model_comparison.csv",
    "step5c_coefficient_comparison.csv",
    "step5c_direction_stability.csv",
    "step5c_influence_populations.csv",
    "step5c_influence_coefficients.csv",
    "step5c_coefficient_drift.csv",
    "step5c_review_mass_removed.csv",
    "step5c_predicted_effect_comparison.csv",
    "step5c_fit_warnings.csv",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def f(row: dict[str, str], key: str) -> float:
    return float(row[key])


def test_step5c_scripts_outputs_report_and_figures_exist() -> None:
    assert (ROOT / "R" / "run_robust_modeling.R").is_file()
    assert (ROOT / "R" / "modeling" / "06_robust_models.R").is_file()
    assert (ROOT / "R" / "modeling" / "07_influence_sensitivity.R").is_file()
    assert REQUIRED_OUTPUTS <= {p.name for p in OUTPUT.glob("step5c_*.csv")}
    assert (ROOT / "reports" / "step5c_robust_reception_report.md").is_file()
    assert {p.name for p in FIGURES.glob("0[5-8]_*.png")} == {
        "05_robust_or_comparison.png",
        "06_ci_width_comparison.png",
        "07_influence_sensitivity_coefficients.png",
        "08_review_mass_removed.png",
    }


def test_primary_population_formula_and_scaling_remain_frozen() -> None:
    comparison = read_csv("step5c_model_comparison.csv")
    assert {int(row["n_games"]) for row in comparison} == {836}
    assert {int(row["n_coefficients"]) for row in comparison} == {13}
    step5b_fit = read_csv("step5b_model_fit_summary.csv")[0]
    assert step5b_fit["formula"] == (
        "cbind(positive_reviews, negative_reviews) ~ z_log1p_price + "
        "z_days_since_release + platform_segment + genre_action + genre_adventure + "
        "genre_casual + genre_indie + genre_rpg + genre_simulation + genre_strategy"
    )
    source = (ROOT / "R" / "modeling" / "07_influence_sensitivity.R").read_text(encoding="utf-8")
    assert "no re-scaling after exclusion" in source
    assert "scale(" not in source
    audit = read_csv("step5c_specification_audit.csv")[0]
    assert int(audit["primary_n"]) == int(audit["unique_appids"]) == 836
    assert int(audit["quasi_n"]) == int(audit["beta_binomial_n"]) == 836
    assert audit["same_model_frame_rows"] == "TRUE"
    assert audit["response_identity_valid"] == "TRUE"
    assert audit["formula"] == step5b_fit["formula"]
    frozen_scaling = {row["predictor"]: row for row in read_csv("step5b_scaling_parameters.csv")}
    assert math.isclose(f(audit, "price_scaling_mean"), f(frozen_scaling["log1p_current_price"], "scaling_mean"), abs_tol=1e-12)
    assert math.isclose(f(audit, "price_scaling_sd"), f(frozen_scaling["log1p_current_price"], "scaling_sd"), abs_tol=1e-12)
    assert math.isclose(f(audit, "days_scaling_mean"), f(frozen_scaling["days_since_release"], "scaling_mean"), abs_tol=1e-12)
    assert math.isclose(f(audit, "days_scaling_sd"), f(frozen_scaling["days_since_release"], "scaling_sd"), abs_tol=1e-12)


def test_quasi_matches_binomial_means_and_inflates_uncertainty() -> None:
    baseline = read_csv("step5b_coefficients.csv")
    quasi = read_csv("step5c_quasi_coefficients.csv")
    assert [r["term"] for r in quasi] == [r["term"] for r in baseline]
    for left, right in zip(quasi, baseline, strict=True):
        assert math.isclose(f(left, "estimate_log_odds"), f(right, "estimate_log_odds"), abs_tol=1e-12)
    fit = read_csv("step5c_quasi_fit.csv")[0]
    assert fit["converged"] == "TRUE"
    assert fit["aic"] == fit["bic"] == fit["log_likelihood"] == ""
    assert math.isclose(f(fit, "estimated_dispersion"), f(fit, "pearson_dispersion"), rel_tol=1e-7)
    inflation = read_csv("step5c_quasi_inflation.csv")
    expected = math.sqrt(f(fit, "estimated_dispersion"))
    assert all(math.isclose(f(row, "se_inflation_ratio"), expected, rel_tol=1e-10) for row in inflation)


def test_beta_binomial_converges_and_exports_parameterization_and_profile_ci() -> None:
    fit = read_csv("step5c_beta_binomial_fit.csv")[0]
    assert fit["package"] == "glmmTMB"
    assert fit["package_version"]
    assert int(fit["n_games"]) == 836
    assert int(fit["total_positive_reviews"]) == 943294
    assert int(fit["total_negative_reviews"]) == 125730
    assert int(fit["convergence_code"]) == 0
    assert fit["positive_definite_hessian"] == "TRUE"
    assert fit["converged"] == "TRUE"
    assert fit["profile_ci_status"] == "PASS"
    assert int(fit["profile_ci_warning_count"]) == 0
    coefficients = read_csv("step5c_beta_binomial_coefficients.csv")
    assert len(coefficients) == 13
    assert all(row["profile_ci_status"] == "PASS" for row in coefficients)
    assert all(math.isfinite(f(row, key)) for row in coefficients for key in (
        "estimate_log_odds", "std_error", "odds_ratio", "or_ci95_lower", "or_ci95_upper",
        "profile_or_ci95_lower", "profile_or_ci95_upper",
    ))
    dispersion = read_csv("step5c_beta_dispersion.csv")[0]
    phi = f(dispersion, "parameter_value")
    rho = f(dispersion, "derived_rho")
    assert phi > 0
    assert math.isclose(rho, 1 / (phi + 1), rel_tol=1e-12)
    assert dispersion["boundary_flag"] == "FALSE"


def test_model_comparison_and_direction_tables_are_complete() -> None:
    rows = {row["model"]: row for row in read_csv("step5c_model_comparison.csv")}
    assert set(rows) == {"Binomial", "Quasibinomial", "Beta-binomial"}
    assert rows["Quasibinomial"]["likelihood_comparable_to_binomial"] == "FALSE"
    assert rows["Beta-binomial"]["likelihood_comparable_to_binomial"] == "TRUE"
    assert f(rows["Beta-binomial"], "delta_aic_vs_binomial") < 0
    assert f(rows["Beta-binomial"], "loglik_difference_vs_binomial") > 0
    direction = read_csv("step5c_direction_stability.csv")
    assert len(direction) == 13
    assert {row["practical_stability"] for row in direction} <= {
        "Stable", "Moderately sensitive", "Highly sensitive"
    }


def test_influence_populations_ranking_and_review_mass_are_exact() -> None:
    rows = {row["population"]: row for row in read_csv("step5c_influence_populations.csv")}
    assert {key: int(row["n_games"]) for key, row in rows.items()} == {
        "full": 836,
        "minus_top1": 835,
        "minus_top1pct": 827,
        "minus_top5pct": 794,
    }
    assert {key: int(row["games_removed"]) for key, row in rows.items()} == {
        "full": 0,
        "minus_top1": 1,
        "minus_top1pct": 9,
        "minus_top5pct": 42,
    }
    primary_reviews = int(rows["full"]["total_reviews_retained"])
    for row in rows.values():
        assert int(row["total_reviews_retained"]) + int(row["reviews_removed"]) == primary_reviews
        assert math.isclose(
            f(row, "fraction_reviews_retained") + f(row, "share_reviews_removed"), 1, abs_tol=1e-12
        )
    removed = read_csv("step5c_influence_removed_games.csv")
    assert len(removed) == 42
    assert [int(row["review_volume_rank"]) for row in removed] == list(range(1, 43))
    counts = [int(row["total_reviews"]) for row in removed]
    assert counts == sorted(counts, reverse=True)
    ranking_keys = [(-int(row["total_reviews"]), int(row["appid"])) for row in removed]
    assert ranking_keys == sorted(ranking_keys)


def test_every_model_population_has_same_terms_and_converges() -> None:
    coefficients = read_csv("step5c_influence_coefficients.csv")
    assert len(coefficients) == 2 * 4 * 13
    groups: dict[tuple[str, str], set[str]] = {}
    for row in coefficients:
        groups.setdefault((row["model"], row["population"]), set()).add(row["term"])
    assert len(groups) == 8
    assert all(len(terms) == 13 for terms in groups.values())
    fits = read_csv("step5c_influence_fit_summary.csv")
    assert len(fits) == 8
    assert all(row["converged"] == "TRUE" for row in fits)
    drift = read_csv("step5c_coefficient_drift.csv")
    assert len(drift) == 4 * 13
    assert all(row["sign_change"] == "FALSE" for row in drift)


def test_database_and_credential_safety() -> None:
    db = read_csv("step5c_database_preservation.csv")
    assert {row["object"]: int(row["after"]) for row in db} == {
        "games": 3000, "review_snapshots": 3000, "game_genres": 8796,
        "genres": 13, "model20": 844,
    }
    files = list(OUTPUT.glob("step5c_*.csv")) + [
        ROOT / "reports" / "step5c_robust_reception_report.md",
        ROOT / "reports" / "03_statistical_modeling.qmd",
    ]
    for path in files:
        text = path.read_text(encoding="utf-8")
        for unsafe in ("MYSQL_PASSWORD=", "MYSQL_USER=", "MYSQL_HOST=", "password=", "DSN="):
            assert unsafe not in text
