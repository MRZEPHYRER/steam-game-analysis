import csv
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data" / "analysis" / "modeling"
FIGURES = ROOT / "figures" / "modeling"
REPORTS = ROOT / "reports"

REQUIRED_OUTPUTS = {
    "step5f_rating_estimates.csv",
    "step5f_wilson_examples.csv",
    "step5f_wilson_validation.csv",
    "step5f_eb_prior_parameters.csv",
    "step5f_eb_prior_sensitivity.csv",
    "step5f_review_count_bin_summary.csv",
    "step5f_extreme_rate_summary.csv",
    "step5f_rank_correlations.csv",
    "step5f_topk_overlap.csv",
    "step5f_rank_movers_up.csv",
    "step5f_rank_movers_down.csv",
    "step5f_high_raw_low_confidence.csv",
    "step5f_high_raw_strong_shrinkage.csv",
    "step5f_top_shrinkage.csv",
    "step5f_high_n_preservation.csv",
    "step5f_fit_warnings.csv",
}
REQUIRED_FIGURES = {
    "25_wilson_denominator_geometry.png",
    "26_raw_rate_vs_review_count.png",
    "27_wilson_width_vs_review_count.png",
    "28_raw_vs_eb_rating.png",
    "29_eb_shrinkage_vs_review_count.png",
    "30_raw_vs_eb_distribution.png",
    "31_raw_wilson_eb_rank_comparison.png",
    "32_eb_prior_sensitivity.png",
    "33_top_adjusted_games.png",
    "34_most_shrunk_games.png",
}


def read_csv(name: str) -> list[dict[str, str]]:
    with (OUTPUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def number(row: dict[str, str], field: str) -> float:
    return float(row[field])


def test_step5f_required_outputs_scripts_reports_and_figures_exist() -> None:
    assert REQUIRED_OUTPUTS <= {path.name for path in OUTPUT.glob("step5f_*.csv")}
    assert REQUIRED_FIGURES <= {path.name for path in FIGURES.glob("*.png")}
    assert all((FIGURES / name).stat().st_size > 20_000 for name in REQUIRED_FIGURES)
    for name in (
        "14_wilson_rating.R",
        "15_empirical_bayes_rating.R",
        "16_rating_adjustment_visuals.R",
        "17_rating_adjustment_report.R",
    ):
        assert (ROOT / "R" / "modeling" / name).exists()
    assert (ROOT / "R" / "run_rating_adjustment.R").exists()
    assert (REPORTS / "step5f_rating_adjustment_report.md").exists()
    assert (REPORTS / "06_rating_adjustment_visual_audit.qmd").exists()
    assert (REPORTS / "06_rating_adjustment_visual_audit.html").exists()


def test_step5f_rating_population_integrity_and_required_fields() -> None:
    rows = read_csv("step5f_rating_estimates.csv")
    assert len(rows) == 2241
    appids = [int(row["appid"]) for row in rows]
    assert appids == sorted(appids)
    assert len(set(appids)) == 2241
    required = {
        "appid", "name", "positive_reviews", "negative_reviews", "total_reviews",
        "raw_positive_rate", "wilson_lower_95", "wilson_center",
        "wilson_upper_95", "wilson_width", "eb_posterior_mean",
        "eb_ci95_lower", "eb_ci95_upper", "eb_ci95_width", "eb_shrinkage",
        "eb_shrinkage_pp", "data_weight", "prior_weight", "raw_rank",
        "wilson_rank", "eb_rank",
    }
    assert required <= set(rows[0])
    for row in rows:
        positive = int(row["positive_reviews"])
        negative = int(row["negative_reviews"])
        total = int(row["total_reviews"])
        assert total > 0
        assert positive + negative == total
        assert math.isclose(number(row, "raw_positive_rate"), positive / total, abs_tol=1e-14)
    assert {int(row["is_free"]) for row in rows} == {0, 1}
    assert len(rows) + 759 == 3000


def test_step5f_wilson_bounds_formula_validation_and_geometry() -> None:
    rows = read_csv("step5f_rating_estimates.csv")
    for row in rows:
        raw = number(row, "raw_positive_rate")
        lower = number(row, "wilson_lower_95")
        center = number(row, "wilson_center")
        upper = number(row, "wilson_upper_95")
        width = number(row, "wilson_width")
        assert 0 <= lower <= raw <= upper <= 1
        assert lower <= center <= upper
        assert math.isclose(width, upper - lower, abs_tol=1e-13)

    validation = read_csv("step5f_wilson_validation.csv")
    assert len(validation) >= 9
    assert all(row["validation_pass"] == "TRUE" for row in validation)
    assert {
        (int(row["positive_reviews"]), int(row["total_reviews"]))
        for row in validation
    } >= {(0, 1), (1, 1), (1, 2), (2, 2), (10, 10), (20, 20), (100, 100), (1000, 1000)}
    assert all(number(row, "lower_absolute_difference") <= 1e-9 for row in validation)
    assert all(number(row, "upper_absolute_difference") <= 1e-9 for row in validation)

    examples = read_csv("step5f_wilson_examples.csv")
    for group in ("raw_100_percent", "raw_50_percent"):
        widths = [number(row, "wilson_width") for row in examples if row["example_group"] == group]
        assert all(a > b for a, b in zip(widths, widths[1:]))
    one_of_one = next(row for row in examples if row["positive_reviews"] == row["total_reviews"] == "1")
    assert math.isclose(number(one_of_one, "wilson_lower_95"), 0.206549314377237, abs_tol=1e-12)


def test_step5f_eb_priors_converge_and_are_start_robust() -> None:
    priors = read_csv("step5f_eb_prior_parameters.csv")
    assert [row["prior_id"] for row in priors] == [
        "EB_ALL_POSITIVE_N", "EB_N_GE_10", "EB_N_GE_20"
    ]
    assert [int(row["n_games"]) for row in priors] == [2241, 1139, 844]
    for row in priors:
        alpha = number(row, "alpha")
        beta = number(row, "beta")
        precision = number(row, "prior_precision_ess")
        assert alpha > 0 and beta > 0 and precision > 0
        assert math.isclose(precision, alpha + beta, rel_tol=1e-12)
        assert math.isclose(number(row, "prior_mean"), alpha / precision, rel_tol=1e-12)
        assert number(row, "prior_variance") > 0
        assert int(row["convergence_code"]) == 0
        assert number(row, "gradient_max_abs") < 1e-3
        assert number(row, "hessian_min_eigenvalue") > 0
        assert row["starts_agree"] == "TRUE"
    starts = read_csv("step5f_eb_starting_value_audit.csv")
    assert len(starts) == 9
    assert {row["start_id"] for row in starts} == {
        "moment_precision", "low_precision", "high_precision"
    }
    assert all(int(row["convergence_code"]) == 0 for row in starts)
    assert all(int(row["warning_count"]) == 0 for row in read_csv("step5f_fit_warnings.csv"))


def test_step5f_posterior_identities_and_synthetic_low_n_shrinkage() -> None:
    rows = read_csv("step5f_rating_estimates.csv")
    primary = read_csv("step5f_eb_prior_parameters.csv")[0]
    alpha = number(primary, "alpha")
    beta = number(primary, "beta")
    for row in rows:
        positive = int(row["positive_reviews"])
        negative = int(row["negative_reviews"])
        expected = (positive + alpha) / (positive + negative + alpha + beta)
        eb = number(row, "eb_posterior_mean")
        assert 0 < eb < 1
        assert math.isclose(eb, expected, rel_tol=1e-12)
        assert number(row, "eb_ci95_lower") < eb < number(row, "eb_ci95_upper")
        assert math.isclose(number(row, "data_weight") + number(row, "prior_weight"), 1, abs_tol=1e-12)
        assert math.isclose(number(row, "eb_shrinkage"), eb - number(row, "raw_positive_rate"), abs_tol=1e-13)

    # Controlled Beta(8,2) example: 1/1 is shrunk more than 10/10, then 100/100.
    adjusted = [(n + 8) / (n + 10) for n in (1, 10, 100)]
    shrinkage = [1 - value for value in adjusted]
    assert adjusted[0] < adjusted[1] < adjusted[2] < 1
    assert shrinkage[0] > shrinkage[1] > shrinkage[2]


def test_step5f_rankings_are_deterministic_and_complete() -> None:
    rows = read_csv("step5f_rating_estimates.csv")
    expected_raw = sorted(rows, key=lambda row: (
        -number(row, "raw_positive_rate"), -int(row["total_reviews"]), int(row["appid"])
    ))
    expected_wilson = sorted(rows, key=lambda row: (
        -number(row, "wilson_lower_95"), -int(row["total_reviews"]), int(row["appid"])
    ))
    expected_eb = sorted(rows, key=lambda row: (
        -number(row, "eb_posterior_mean"), int(row["appid"])
    ))
    assert [int(row["raw_rank"]) for row in expected_raw] == list(range(1, 2242))
    assert [int(row["wilson_rank"]) for row in expected_wilson] == list(range(1, 2242))
    assert [int(row["eb_rank"]) for row in expected_eb] == list(range(1, 2242))
    correlations = read_csv("step5f_rank_correlations.csv")
    assert {row["comparison"] for row in correlations} == {
        "RAW_VS_WILSON", "RAW_VS_EB", "WILSON_VS_EB"
    }
    assert all(-1 <= number(row, "spearman") <= 1 for row in correlations)
    assert all(-1 <= number(row, "kendall_tau_b") <= 1 for row in correlations)


def test_step5f_topk_overlap_and_rank_mover_exports_are_consistent() -> None:
    topk = read_csv("step5f_topk_overlap.csv")
    assert len(topk) == 12
    assert {int(row["top_k"]) for row in topk} == {10, 25, 50, 100}
    for row in topk:
        intersection = int(row["intersection_n"])
        union = int(row["union_n"])
        k = int(row["top_k"])
        assert 0 <= intersection <= k
        assert union == 2 * k - intersection
        assert math.isclose(number(row, "jaccard"), intersection / union, rel_tol=1e-12)
    up = read_csv("step5f_rank_movers_up.csv")
    down = read_csv("step5f_rank_movers_down.csv")
    assert len(up) == len(down) == 30
    assert all(int(row["rank_change"]) == int(row["raw_rank"]) - int(row["eb_rank"]) for row in up + down)
    assert [int(row["rank_change"]) for row in up] == sorted(
        (int(row["rank_change"]) for row in up), reverse=True
    )
    assert [int(row["rank_change"]) for row in down] == sorted(
        int(row["rank_change"]) for row in down
    )


def test_step5f_extreme_flags_and_shrinkage_relationships() -> None:
    ratings = read_csv("step5f_rating_estimates.csv")
    assert sum(number(row, "raw_positive_rate") == 1 for row in ratings) == 832
    assert sum(number(row, "raw_positive_rate") == 0 for row in ratings) == 96
    low_confidence = read_csv("step5f_high_raw_low_confidence.csv")
    strong = read_csv("step5f_high_raw_strong_shrinkage.csv")
    assert all(number(row, "raw_positive_rate") >= 0.95 and number(row, "wilson_lower_95") < 0.80 for row in low_confidence)
    assert all(number(row, "raw_positive_rate") >= 0.95 and number(row, "eb_shrinkage_pp") <= -5 for row in strong)
    top = read_csv("step5f_top_shrinkage.csv")
    assert len(top) == 30
    assert [number(row, "absolute_shrinkage") for row in top] == sorted(
        (number(row, "absolute_shrinkage") for row in top), reverse=True
    )
    relationship = read_csv("step5f_shrinkage_relationship.csv")[0]
    assert number(relationship, "spearman") < -0.8


def test_step5f_review_bins_high_n_and_prior_sensitivity() -> None:
    bins = read_csv("step5f_review_count_bin_summary.csv")
    assert [row["review_count_bin"] for row in bins] == [
        "1-9", "10-19", "20-49", "50-99", "100-499", "500-999", "1000+"
    ]
    assert sum(int(row["n_games"]) for row in bins) == 2241
    assert number(bins[0], "median_absolute_shrinkage") > number(bins[-1], "median_absolute_shrinkage")
    assert number(bins[0], "median_wilson_width") > number(bins[-1], "median_wilson_width")
    high_n = read_csv("step5f_high_n_preservation.csv")[0]
    assert int(high_n["n_games"]) > 0
    assert number(high_n, "median_absolute_shrinkage") <= number(high_n, "p95_absolute_shrinkage")
    assert number(high_n, "p95_absolute_shrinkage") <= number(high_n, "max_absolute_shrinkage")
    assert number(high_n, "max_absolute_shrinkage") < 0.002
    sensitivity = read_csv("step5f_eb_prior_sensitivity.csv")
    assert {row["comparison"] for row in sensitivity} == {"PRIOR10_VS_ALL", "PRIOR20_VS_ALL"}
    assert all(int(row["evaluation_n"]) == 2241 for row in sensitivity)
    assert all(number(row, "mean_absolute_difference") >= 0 for row in sensitivity)
    assert all(number(row, "spearman_rank_correlation") > 0.99 for row in sensitivity)


def test_step5f_database_preservation_and_credential_safety() -> None:
    rows = read_csv("step5f_database_preservation.csv")
    expected = {
        "games": 3000,
        "review_snapshots": 3000,
        "game_genres": 8796,
        "genres": 13,
        "model20": 844,
    }
    assert {row["object_name"]: int(float(row["count_before"])) for row in rows} == expected
    assert {row["object_name"]: int(float(row["count_after"])) for row in rows} == expected
    assert all(row["unchanged"] == "TRUE" for row in rows)
    reviewed = list(OUTPUT.glob("step5f_*.csv")) + [
        REPORTS / "step5f_rating_adjustment_report.md",
        REPORTS / "06_rating_adjustment_visual_audit.qmd",
        REPORTS / "06_rating_adjustment_visual_audit.html",
        REPORTS / "03_statistical_modeling.qmd",
        REPORTS / "03_statistical_modeling.html",
    ]
    for path in reviewed:
        content = path.read_bytes().lower()
        for unsafe in (b"mysql_password", b"password=", b"dsn=", b".env"):
            assert unsafe not in content


def test_step5f_chinese_html_unicode_and_scientific_roles() -> None:
    qmd = (REPORTS / "06_rating_adjustment_visual_audit.qmd").read_text(encoding="utf-8")
    html = (REPORTS / "06_rating_adjustment_visual_audit.html").read_text(encoding="utf-8")
    technical = (REPORTS / "step5f_rating_adjustment_report.md").read_text(encoding="utf-8")
    notation = "<" + "U+"
    escaped_notation = "&lt;" + "U+"
    assert notation not in qmd and notation not in html and notation not in technical
    assert escaped_notation not in html
    assert '<meta charset="utf-8">' in html
    for expected in (
        "Wilson", "Empirical Bayes", "人工审计重点", "Prior Sensitivity",
        "高评论数游戏稳定性", "阶段性结论",
    ):
        assert expected in html
    for expected in (
        "Beta-binomial：主要推断回归",
        "High-rating Logistic：次要门槛分析",
        "Wilson：uncertainty-aware descriptive interval",
        "Empirical Bayes：population-informed shrinkage rating",
    ):
        assert expected in technical


def test_step5f_source_has_no_predictor_regression_or_database_writes() -> None:
    source = "\n".join(
        (ROOT / "R" / "modeling" / name).read_text(encoding="utf-8")
        for name in (
            "14_wilson_rating.R", "15_empirical_bayes_rating.R",
            "16_rating_adjustment_visuals.R", "17_rating_adjustment_report.R",
        )
    ).lower()
    for forbidden in ("glm(", "betareg(", "dbexecute", "dbsendstatement", "insert into", "update games", "delete from"):
        assert forbidden not in source
    assert "price" not in (ROOT / "R" / "modeling" / "15_empirical_bayes_rating.R").read_text(encoding="utf-8").lower()
