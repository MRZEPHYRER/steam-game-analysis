import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "analysis" / "attention"
FIG = ROOT / "figures" / "attention"
REPORTS = ROOT / "reports"

def read_csv(name: str) -> list[dict[str, str]]:
    with (OUT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))

def truth(value: str) -> bool:
    return value.upper() == "TRUE"

def normalize_rhs(formula: str) -> str:
    return re.sub(r"\s+", "", formula.split("~", 1)[1])

def test_step6b1_required_outputs_reports_and_figures_exist() -> None:
    required = {
        "step6b1_tier_distribution.csv", "step6b1_ordinal_fit.csv",
        "step6b1_ordinal_coefficients.csv", "step6b1_parallel_odds_audit.csv",
        "step6b1_price_tier_probabilities.csv", "step6b1_high100_fit.csv",
        "step6b1_direction_comparison.csv", "step6b1_fit_warnings.csv",
        "step6b1_stage_decision.csv", "step6b1_database_preservation.csv"}
    assert required <= {p.name for p in OUT.glob("step6b1_*.csv")}
    figures = {f"{n}_{name}" for n, name in (
        (64, "attention_tier_distribution.png"),
        (65, "attention_tier_price_probabilities.png"),
        (66, "attention_tier_or.png"), (67, "high100_logistic_or.png"),
        (68, "ordinal_vs_high100_direction.png"))}
    assert figures <= {p.name for p in FIG.glob("*.png")}
    assert all((FIG / name).stat().st_size > 10_000 for name in figures)
    for name in ("11_attention_tier_visual_audit.qmd",
                 "11_attention_tier_visual_audit.html",
                 "08_attention_modeling.qmd", "08_attention_modeling.html",
                 "step6b1_attention_tier_report.md"):
        assert (REPORTS / name).exists()

def test_step6b1_positive_population_and_tier_assignment_are_exact() -> None:
    sample = read_csv("step6b1_model_sample.csv")[0]
    assert int(sample["positive_population_n"]) == 2241
    assert int(sample["zero_review_excluded_n"]) == 759
    assert int(sample["model_n"]) == 2240
    assert int(sample["model_excluded_n"]) == 1
    rows = read_csv("step6b1_model_data.csv")
    assert len(rows) == 2240 and len({r["appid"] for r in rows}) == 2240
    assert all(int(r["review_count"]) > 0 for r in rows)
    for row in rows:
        count, tier = int(row["review_count"]), row["attention_tier"]
        expected = "Tier1" if count < 10 else "Tier2" if count < 100 else "Tier3" if count < 1000 else "Tier4"
        assert tier == expected
        assert int(row["high_attention_100"]) == int(count >= 100)

def test_step6b1_tier_order_and_full_population_distribution_are_exact() -> None:
    rows = read_csv("step6b1_tier_distribution.csv")
    assert [r["attention_tier"] for r in rows] == ["Tier1", "Tier2", "Tier3", "Tier4"]
    assert [int(r["n_games"]) for r in rows] == [1102, 733, 293, 113]
    assert sum(int(r["n_games"]) for r in rows) == 2241
    assert [int(r["free_n"]) for r in rows] == [22, 9, 2, 1]

def test_step6b1_price_basis_is_deterministic_and_zero_for_free_rows() -> None:
    basis = read_csv("step6b1_price_basis_definition.csv")[0]
    assert int(basis["training_n"]) == 2206 and int(basis["df"]) == 3
    rows = read_csv("step6b1_model_data.csv")
    free = [r for r in rows if r["is_free"] == "1"]
    assert len(free) == 34
    assert all(float(r[f"tier_price_spline_{i}"]) == 0 for r in free for i in range(1, 4))

def test_step6b1_ordinal_and_high100_use_same_predictors_without_offset() -> None:
    ordinal = read_csv("step6b1_ordinal_fit.csv")[0]
    high100 = read_csv("step6b1_high100_fit.csv")[0]
    assert int(ordinal["n_games"]) == int(high100["n_games"]) == 2240
    assert normalize_rhs(ordinal["formula"]) == normalize_rhs(high100["formula"])
    assert "log_days" in ordinal["formula"] and "offset(" not in ordinal["formula"]
    assert ordinal["weights_used"] == ordinal["offset_used"] == "FALSE"
    assert high100["weights_used"] == high100["offset_used"] == "FALSE"
    assert int(high100["event_n"]) == 406

def test_step6b1_fit_assumptions_and_robustness_support_freeze() -> None:
    ordinal = read_csv("step6b1_ordinal_fit.csv")[0]
    assert int(ordinal["convergence_code"]) == 0
    assert ordinal["design_rank"] == ordinal["design_columns"]
    assert truth(ordinal["numerical_stability"])
    audit = read_csv("step6b1_parallel_odds_audit.csv")
    assert not any(truth(r["major_direction_reversal"]) for r in audit)
    direction = read_csv("step6b1_direction_comparison.csv")
    assert not any(truth(r["major_magnitude_contradiction"]) for r in direction)
    decision = read_csv("step6b1_stage_decision.csv")[0]
    assert decision["status"] == "PASS"
    assert decision["proportional_odds_assumption"] == "APPROXIMATE"
    assert decision["high100_robustness"] == "PASS"
    assert truth(decision["attention_intensity_model_frozen"])

def test_step6b1_probabilities_are_valid_and_price_shape_moves_upward() -> None:
    rows = read_csv("step6b1_price_tier_probabilities.csv")
    for row in rows:
        probabilities = [float(row[t]) for t in ("Tier1", "Tier2", "Tier3", "Tier4")]
        assert all(0 <= p <= 1 for p in probabilities)
        assert abs(sum(probabilities) - 1) < 1e-10
    assert float(rows[-1]["Tier1"]) < float(rows[0]["Tier1"])
    assert float(rows[-1]["Tier3"]) > float(rows[0]["Tier3"])
    assert float(rows[-1]["Tier4"]) > float(rows[0]["Tier4"])

def test_step6b1_database_unicode_and_credentials_are_preserved() -> None:
    expected = {"games": 3000, "review_snapshots": 3000,
                "game_genres": 8796, "genres": 13, "model20": 844}
    db = read_csv("step6b1_database_preservation.csv")
    assert {r["object_name"]: int(float(r["count_before"])) for r in db} == expected
    assert {r["object_name"]: int(float(r["count_after"])) for r in db} == expected
    assert all(truth(r["unchanged"]) for r in db)
    paths = [REPORTS / "11_attention_tier_visual_audit.qmd",
             REPORTS / "11_attention_tier_visual_audit.html",
             REPORTS / "08_attention_modeling.qmd",
             REPORTS / "08_attention_modeling.html",
             REPORTS / "step6b1_attention_tier_report.md"]
    notation = "<" + "U+"
    for path in paths:
        text = path.read_text(encoding="utf-8")
        assert notation not in text and "&lt;U+" not in text
        lower = text.lower()
        assert "mysql_password" not in lower and "password=" not in lower and "dsn=" not in lower
