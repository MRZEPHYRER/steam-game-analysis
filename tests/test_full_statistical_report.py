from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports" / "12_full_statistical_analysis.html"
QMD = ROOT / "reports" / "12_full_statistical_analysis.qmd"


def test_step7a_report_and_assets_exist() -> None:
    assert QMD.exists() and REPORT.exists()
    for name in (
        "69_analysis_pipeline.png",
        "70_attention_vs_reception_summary.png",
        "71_model_decision_map.png",
    ):
        path = ROOT / "figures" / "report" / name
        assert path.exists() and path.stat().st_size > 1000


def test_step7a_html_contains_integrated_narrative() -> None:
    html = REPORT.read_text(encoding="utf-8")
    for phrase in (
        "执行摘要",
        "数据语义与解释边界",
        "Beta-binomial",
        "Wilson",
        "Empirical Bayes",
        "Attention vs Reception",
        "DIAGNOSTIC FAIL / RETAINED",
        "270 passed",
    ):
        assert phrase in html
    assert not re.search(r"(?i)(mysql_password|password=|dsn=)", html)


def test_step7a_all_embedded_pngs_are_present() -> None:
    html = REPORT.read_text(encoding="utf-8")
    refs = sorted(set(re.findall(r'src="(\.\./figures/[^\"]+\.png)"', html)))
    assert len(refs) >= 20
    for ref in refs:
        assert (ROOT / ref.replace("../", "")).exists(), ref
