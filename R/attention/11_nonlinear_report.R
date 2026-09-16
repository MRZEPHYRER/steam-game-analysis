# Step 6A.1 Chinese technical report and freeze record.

if (!exists("step6a1_stage_decision_6a1") || !exists("gam_diagnostic_6a1")) {
  stop("Run Step 6A.1 diagnostics before the technical report.", call. = FALSE)
}

fmt6a1 <- function(x, digits = 4) formatC(x, digits = digits, format = "f")
coef_rows_6a1 <- setNames(
  split(nonlinear_non_spline_coefficients_6a1, nonlinear_non_spline_coefficients_6a1$term),
  nonlinear_non_spline_coefficients_6a1$term
)
free_coef_6a1 <- coef_rows_6a1[["is_free"]]
days_coef_6a1 <- coef_rows_6a1[["z_days_since_release"]]
nonlinear_metrics_6a1 <- auc_brier_6a1 |>
  dplyr::filter(model_id == "NONLINEAR_PRICE_DF3_PRIMARY")
linear_metrics_6a1 <- auc_brier_6a1 |>
  dplyr::filter(model_id == "LINEAR_BENCHMARK")
df4_row_6a1 <- df4_sensitivity_6a1 |>
  dplyr::filter(model_id == "PRICE_SPLINE_DF4_SENSITIVITY")
release_curve_row_6a1 <- curve_difference_summary_6a1 |>
  dplyr::filter(model_id == "RELEASE_MONTH_SENSITIVITY")
genre_curve_row_6a1 <- curve_difference_summary_6a1 |>
  dplyr::filter(model_id == "EXPANDED_GENRE_SENSITIVITY")

technical_6a1 <- c(
  "# Step 6A.1 Nonlinear Review-Entry Specification Freeze",
  "",
  "## 目标与边界",
  "",
  "本轮只修复 Step 6A 已识别的 paid-price functional-form misspecification。Logistic link/framework 保持有效；没有进入 Step 6B，也没有拟合 count model、机器学习模型或未经预设的 interaction。",
  "",
  "## Frozen sample 与 spline parameterization",
  "",
  paste0(
    "Market N = 3000；nonlinear primary N = ", nonlinear_primary_fit_6a1$n_games,
    "。继续排除 1 个缺失 paid price 游戏和 1 个 Other platform 游戏；402 个 free games 全部保留。"
  ),
  "",
  paste0(
    "Paid price 使用 natural spline df=3。Knots 与 Boundary.knots 从 ",
    price_basis_definition_table_6a1$training_n,
    " 个有效 paid-market prices 一次性估计并冻结；prediction 复用相同定义。",
    "Spline basis 在 mean log-price 对应的 $", fmt6a1(price_center_usd_6a1, 2),
    " 处中心化，free rows 的三个 basis columns 全为 0。"
  ),
  "",
  "Spline basis coefficients 只用于构造 nonlinear price-response curve，不解释为业务效应或独立 OR。",
  "",
  "## Linear benchmark 与 nonlinear primary",
  "",
  paste0(
    "Linear benchmark AIC/BIC = ", fmt6a1(primary_fit_6a$aic, 2), "/", fmt6a1(primary_fit_6a$bic, 2),
    "；nonlinear primary AIC/BIC = ", fmt6a1(nonlinear_primary_fit_6a1$aic, 2), "/", fmt6a1(nonlinear_primary_fit_6a1$bic, 2),
    "；delta AIC/BIC = ", fmt6a1(nonlinear_primary_fit_6a1$aic - primary_fit_6a$aic, 2), "/",
    fmt6a1(nonlinear_primary_fit_6a1$bic - primary_fit_6a$bic, 2), "。"
  ),
  "",
  paste0(
    "Nesting audit: strictly nested = ", nesting_primary_6a1$strictly_nested,
    "；formal LRT valid = ", nesting_primary_6a1$formal_lrt_valid,
    if (nesting_primary_6a1$formal_lrt_valid) paste0("；p = ", format(nesting_primary_6a1$lrt_p_value, scientific = TRUE, digits = 4)) else "。"
  ),
  "",
  paste0(
    "对 Step 6A paid-only auxiliary comparison 的回溯审计同样确认 strictly nested = ",
    nesting_paid_aux_6a1$strictly_nested, "，因此原 formal LRT 使用合法。"
  ),
  "",
  "## Price curve 与 support",
  "",
  paste0(
    "Observed paid price support 为 $", fmt6a1(price_support_6a1$min_usd, 2), "–$",
    fmt6a1(price_support_6a1$max_usd, 2), "；主要解释区间固定为 empirical 5th–95th percentile：$",
    fmt6a1(price_support_6a1$p05_usd, 2), "–$", fmt6a1(price_support_6a1$p95_usd, 2), "。"
  ),
  "",
  paste0(
    "在该模型和观测数据支持范围内，predicted review-entry probability 的拟合曲线在约 $",
    fmt6a1(peak_audit_6a1$peak_price_usd, 2), " 达到最高值 ",
    fmt6a1(100 * peak_audit_6a1$peak_predicted_probability, 2), "%（pointwise 95% CI ",
    fmt6a1(100 * peak_audit_6a1$peak_ci95_lower, 2), "%–",
    fmt6a1(100 * peak_audit_6a1$peak_ci95_upper, 2), "%）。"
  ),
  "",
  paste0(
    "以距拟合峰值 0.5 percentage points 内定义局部 plateau，范围约为 $",
    fmt6a1(peak_audit_6a1$plateau_lower_price_usd, 2), "–$",
    fmt6a1(peak_audit_6a1$plateau_upper_price_usd, 2), "。该峰值是描述性拟合最大值，不是最优价格。"
  ),
  "",
  paste0(
    "高价尾部很稀疏：N≥$20/30/50/100 分别为 ", price_support_6a1$n_ge_20_usd, "/",
    price_support_6a1$n_ge_30_usd, "/", price_support_6a1$n_ge_50_usd, "/",
    price_support_6a1$n_ge_100_usd, "。尾部下降不作稳健规律或因果解释。"
  ),
  "",
  "## Other predictors",
  "",
  paste0(
    "is_free OR = ", fmt6a1(free_coef_6a1$odds_ratio, 4), "（95% CI ",
    fmt6a1(free_coef_6a1$or_ci95_lower, 4), "–", fmt6a1(free_coef_6a1$or_ci95_upper, 4),
    "）；centered paid reference probability = ", fmt6a1(100 * free_contrast_6a1$paid_reference_probability, 2),
    "%；free probability = ", fmt6a1(100 * free_contrast_6a1$free_probability, 2), "%。"
  ),
  "",
  paste0(
    "days OR = ", fmt6a1(days_coef_6a1$odds_ratio, 3), "（95% CI ",
    fmt6a1(days_coef_6a1$or_ci95_lower, 3), "–", fmt6a1(days_coef_6a1$or_ci95_upper, 3),
    "）。Platform 与七类 genre 继续解释为 conditional associations。"
  ),
  "",
  "## Diagnostics 与 sensitivity",
  "",
  paste0(
    "Nonlinear model converged = ", nonlinear_entry_fit_6a1$converged,
    "；separation flags = ", sum(nonlinear_separation_diagnostics_6a1$n_flagged),
    "；max Cook's D = ", fmt6a1(nonlinear_influence_summary_6a1$max_cooks_distance, 4),
    "；maximum calibration gap = ",
    fmt6a1(100 * max(calibration_comparison_6a1$absolute_gap[
      calibration_comparison_6a1$model_id == "NONLINEAR_PRICE_DF3_PRIMARY"
    ]), 2), " percentage points。"
  ),
  "",
  paste0(
    "Linear/nonlinear AUC = ", fmt6a1(linear_metrics_6a1$auc, 4), "/", fmt6a1(nonlinear_metrics_6a1$auc, 4),
    "；Brier = ", fmt6a1(linear_metrics_6a1$brier_score, 5), "/", fmt6a1(nonlinear_metrics_6a1$brier_score, 5),
    "；log loss = ", fmt6a1(linear_metrics_6a1$binary_log_loss, 5), "/", fmt6a1(nonlinear_metrics_6a1$binary_log_loss, 5), "。"
  ),
  "",
  paste0(
    "Release-month 与 expanded-genre sensitivities 在 central support 相对 primary 的最大绝对概率差分别为 ",
    fmt6a1(100 * release_curve_row_6a1$max_absolute_probability_difference_central_5_95, 2), " 和 ",
    fmt6a1(100 * genre_curve_row_6a1$max_absolute_probability_difference_central_5_95, 2), " percentage points。"
  ),
  "",
  paste0(
    "df=4 sensitivity AIC = ", fmt6a1(df4_row_6a1$aic, 2),
    "；peak = $", fmt6a1(df4_row_6a1$peak_price_usd, 2),
    "；central-support df4-vs-df3 最大概率差 = ",
    fmt6a1(100 * df4_row_6a1$max_abs_probability_difference_vs_df3_central_5_95, 2), " percentage points。"
  ),
  "",
  paste0(
    "Optional GAM diagnostic status = ", gam_diagnostic_6a1$status,
    if (gam_diagnostic_6a1$status == "RUN") paste0(
      "；edf = ", fmt6a1(gam_diagnostic_6a1$edf, 3),
      "；central-support GAM-vs-df3 最大概率差 = ",
      fmt6a1(100 * gam_diagnostic_6a1$max_abs_probability_difference_vs_df3_central_5_95, 2),
      " percentage points。"
    ) else paste0("；", gam_diagnostic_6a1$note)
  ),
  "",
  "## Freeze decision",
  "",
  paste0(
    "PRICE FORM = ", step6a1_stage_decision_6a1$price_functional_form,
    "；Step 6A.1 = ", step6a1_stage_decision_6a1$step6a1_status,
    "；Review Entry model frozen = ", step6a1_stage_decision_6a1$review_entry_model_frozen,
    "；Ready for Step 6B = ", step6a1_stage_decision_6a1$ready_for_step6b, "。"
  ),
  "",
  "Final entry model 是 logistic regression，其中 paid collection-time price 使用 frozen、centered natural spline df=3，days 保持线性，并保留 is_free、platform 与七个 genre。Linear model 仅保留为 benchmark。",
  "",
  "## Interpretation boundary 与 future work",
  "",
  "Review entry 表示 review attention，不是 sales、owners、reception 或因果效果。未来可将 GAM、Random Forest、Gradient Boosting/XGBoost 用于 predictive benchmark、nonlinear pattern validation 或 interaction discovery，但它们不自动替代当前 inferential model。"
)

writeLines(
  enc2utf8(technical_6a1),
  file.path(project_root, "reports", "step6a1_nonlinear_attention_report.md"),
  useBytes = TRUE
)

message(sprintf(
  "Step 6A.1 technical report: %s",
  step6a1_stage_decision_6a1$step6a1_status
))
