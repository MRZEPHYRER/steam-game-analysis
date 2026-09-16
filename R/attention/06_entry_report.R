# Step 6A Chinese technical report.

if (!exists("auc_6a") || !exists("functional_form_decision_6a")) {
  stop("Run Step 6A diagnostics before the technical report.", call. = FALSE)
}
fmt6a <- function(x, digits = 4) formatC(x, digits = digits, format = "f")
coef6a <- setNames(split(primary_coefficients_6a, primary_coefficients_6a$term), primary_coefficients_6a$term)
free_row_6a <- free_paid_summary_6a[free_paid_summary_6a$game_type == "Free", ]
paid_row_6a <- free_paid_summary_6a[free_paid_summary_6a$game_type == "Paid", ]
functional_text_6a <- paste(
  functional_form_decision_6a$predictor,
  functional_form_decision_6a$assessment,
  "delta AIC", fmt6a(functional_form_decision_6a$delta_aic_spline_minus_linear, 2),
  "max probability gap", fmt6a(functional_form_decision_6a$max_absolute_probability_gap, 3),
  collapse = "; "
)
linear_predictor_adequacy_6a <- if (
  any(functional_form_decision_6a$assessment == "SUBSTANTIVE_NONLINEARITY")
) {
  "INADEQUATE"
} else if (any(functional_form_decision_6a$assessment == "MODEST_NONLINEARITY")) {
  "PARTIALLY_ADEQUATE"
} else {
  "ADEQUATE"
}
stage_decision_6a <- data.frame(
  step6a_audit_status = "PASS",
  linear_predictor_adequacy = linear_predictor_adequacy_6a,
  step6a_ready_to_freeze = linear_predictor_adequacy_6a == "ADEQUATE",
  ready_for_step6b = linear_predictor_adequacy_6a == "ADEQUATE",
  required_next_gate = if (linear_predictor_adequacy_6a == "ADEQUATE") {
    "Human audit approval"
  } else {
    "Step 6A.1 nonlinear specification freeze before Step 6B"
  },
  stringsAsFactors = FALSE
)
technical_6a <- c(
  "# Step 6A Review Attention Entry Analysis",
  "",
  "## 研究范围",
  "",
  paste0("完整市场样本 N = 3000；has-review = 2241；zero-review = 759。Zero-review 在本阶段是 outcome 的非事件，必须保留。Review count 只表示 review attention / engagement / volume，不是 sales 或 owners。"),
  "",
  "Step 6A 只建模是否获得至少一条评论；不拟合 Poisson、Negative Binomial、zero-inflated 或 count hurdle 第二部分。",
  "",
  "## Free 与 Paid 参数化",
  "",
  paste0("Free N = ", free_row_6a$n_games, "，raw entry rate = ", fmt6a(free_row_6a$has_review_percent, 2), "%；Paid N = ", paid_row_6a$n_games, "，raw entry rate = ", fmt6a(paid_row_6a$has_review_percent, 2), "%。Raw risk difference（free - paid）= ", fmt6a(100 * free_row_6a$raw_risk_difference_free_minus_paid, 2), " percentage points。"),
  "",
  "Primary 同时包含 is_free 与 paid price component。Free rows 的 price component 固定为 0；paid price coefficient 只解释付费游戏内部、collection-time price 增加 1 SD 的条件关联。缺失 paid price 的游戏保留在市场描述分母，但排除于含 price 模型。",
  "",
  "## Primary Logistic",
  "",
  paste0("Primary N = ", primary_fit_6a$n_games, "；events/non-events = ", primary_fit_6a$event_n, "/", primary_fit_6a$non_event_n, "；converged = ", primary_fit_6a$converged, "；AIC = ", fmt6a(primary_fit_6a$aic, 2), "。模型无权重、无 count offset、无 interactions。"),
  "",
  "所有系数均为条件关联。Free status 可能反映 game composition、discoverability、质量、开发成熟度、受众与发行策略，不能解释为免费导致无人评论。",
  "",
  "## Functional-form audit",
  "",
  functional_text_6a,
  "",
  "Linear 是预设 primary；natural spline df=3 是固定 sensitivity。只有明显、实质的非线性才会触发 Step 6A.1，不能仅因 AIC 略低自动替换 primary。",
  "",
  paste0(
    "最终 linear predictor adequacy = ", linear_predictor_adequacy_6a,
    "。Step 6A audit status = PASS；current specification ready to freeze = ",
    stage_decision_6a$step6a_ready_to_freeze,
    "；ready for Step 6B = ", stage_decision_6a$ready_for_step6b, "。"
  ),
  "",
  "## Diagnostics",
  "",
  paste0("In-sample AUC = ", fmt6a(auc_6a$auc, 4), "（95% CI ", fmt6a(auc_6a$ci95_lower, 4), "–", fmt6a(auc_6a$ci95_upper, 4), "）。Calibration 与 AUC 都是描述性诊断，不是模型选择或部署目标。"),
  "",
  "Influence diagnostics 不构成自动删点规则。Release-month 和 expanded-genre 模型均为预设 sensitivity。",
  "",
  "## 解释边界",
  "",
  "Attention 与 reception 是不同 outcome。Review entry 不等于销量、owners 或商业成功；所有模型都基于单次 Steam 快照，不能作因果推断。"
)
writeLines(enc2utf8(technical_6a), file.path(project_root, "reports", "step6a_attention_entry_report.md"), useBytes = TRUE)
write_attention_audit(stage_decision_6a, "step6a_stage_decision.csv")

message("Step 6A technical report: PASS")
