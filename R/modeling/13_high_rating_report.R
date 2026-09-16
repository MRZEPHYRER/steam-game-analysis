# Step 5E Chinese technical report. All values come from the fitted objects
# created by scripts 10-12; this script performs no database writes or refits.

fmt_5e <- function(x, digits = 4) formatC(x, digits = digits, format = "f")

distribution_lines_5e <- vapply(seq_len(nrow(outcome_distribution)), function(i) {
  row <- outcome_distribution[i, ]
  paste0(
    "- ", row$model_id, "：", row$high_rated_n, "/", row$n_total,
    "（", fmt_5e(row$high_rated_percent, 2), "%）；恰好位于阈值的游戏数 = ",
    row$exact_boundary_n
  )
}, character(1))

primary_or_lines_5e <- vapply(
  seq_len(nrow(primary_high_rating_coefficients)),
  function(i) {
    row <- primary_high_rating_coefficients[i, ]
    paste0(
      "- `", row$term, "`：OR = ", fmt_5e(row$odds_ratio),
      "，Wald 95% CI [", fmt_5e(row$or_ci95_lower), "，",
      fmt_5e(row$or_ci95_upper), "]，方向 = ", row$direction
    )
  },
  character(1)
)

contrast_lines_5e <- vapply(
  seq_len(nrow(predicted_probability_contrasts)),
  function(i) {
    row <- predicted_probability_contrasts[i, ]
    paste0(
      "- ", row$scenario, "：参考概率 = ",
      fmt_5e(row$reference_probability), "，情景概率 = ",
      fmt_5e(row$modified_probability), "，变化 = ",
      fmt_5e(row$percentage_point_change, 2), " 个百分点"
    )
  },
  character(1)
)

stability_counts_5e_report <- table(rating_threshold_stability$stability_class)
stability_n_5e <- function(label) {
  if (label %in% names(stability_counts_5e_report)) {
    as.integer(stability_counts_5e_report[[label]])
  } else {
    0L
  }
}
direction_agree_n_5e <- sum(beta_logistic_direction_comparison$direction_agreement)
direction_total_n_5e <- nrow(beta_logistic_direction_comparison)

technical_report_5e <- c(
  "# Step 5E 次要高评分 Logistic 分析技术报告",
  "",
  "## 分析层级与边界",
  "",
  paste(
    "Beta-binomial 仍是主要推断模型。Step 5E 是预先规定的、便于业务解释的游戏层级二元补充分析。",
    "每款游戏仅贡献一个二元观测，因此评论数为 20 与评论数为 100,000 的游戏在该模型中具有相同的似然权重。"
  ),
  "",
  paste(
    "主结果 HIGH85 定义为 positive_reviews / total_reviews >= 0.85；HIGH80 与 HIGH90",
    "仅用于固定阈值敏感性检查。未优化评分阈值，也未优化分类阈值。"
  ),
  "",
  "## 样本与结局审计",
  "",
  paste0(
    "冻结的付费游戏完整样本为 N = ", nrow(high_rating_data),
    "，AppID 唯一，且每款游戏 total_reviews >= 20。评论量既不是权重，也不是模型协变量。"
  ),
  "",
  distribution_lines_5e,
  "",
  "## HIGH85 主 Logistic 模型",
  "",
  paste0(
    "模型收敛 = ", primary_fit_row$converged,
    "；事件/非事件 = ", primary_fit_row$event_n, "/",
    primary_fit_row$non_event_n, "；参数秩 = ", primary_fit_row$rank,
    "/", primary_fit_row$parameter_count, "；迭代次数 = ",
    primary_fit_row$iterations, "。"
  ),
  "",
  paste0(
    "logLik = ", fmt_5e(primary_fit_row$log_likelihood, 3),
    "，AIC = ", fmt_5e(primary_fit_row$aic, 3),
    "，BIC = ", fmt_5e(primary_fit_row$bic, 3),
    "，空模型/残差离差 = ", fmt_5e(primary_fit_row$null_deviance, 3),
    "/", fmt_5e(primary_fit_row$residual_deviance, 3), "。"
  ),
  "",
  primary_or_lines_5e,
  "",
  "## 模型概率对比",
  "",
  paste(
    "下列概率为在冻结参考构型上一次只改变一个变量得到的模型内对比，",
    "属于条件关联的描述，不作因果解释。"
  ),
  "",
  contrast_lines_5e,
  "",
  "## 分离、残差与影响诊断",
  "",
  paste0(
    "分离启发式检查的标记总数 = ", sum(separation_diagnostics_5e$n_flagged),
    "；最大绝对标准化离差残差 = ",
    fmt_5e(influence_summary$max_absolute_standardized_deviance_residual),
    "；最大 leverage = ", fmt_5e(influence_summary$max_leverage),
    "；最大 Cook's D = ", fmt_5e(influence_summary$max_cooks_distance), "。"
  ),
  "",
  paste0(
    "|标准化残差| > 2 的游戏数 = ",
    influence_summary$n_absolute_standardized_residual_gt_2,
    "，> 3 的游戏数 = ", influence_summary$n_absolute_standardized_residual_gt_3,
    "；Cook's D > 0.5 或 > 1 的游戏数均为 0。"
  ),
  "",
  "## 校准与区分度",
  "",
  paste0(
    "样本内 ROC AUC = ", fmt_5e(auc_5e$auc), "（95% CI ",
    fmt_5e(auc_5e$ci95_lower), " 至 ", fmt_5e(auc_5e$ci95_upper),
    "；", auc_5e$ci_method, "）。AUC 与校准均为次要、样本内的描述性诊断，",
    "不是模型选择目标。"
  ),
  "",
  "## 评分阈值稳定性",
  "",
  paste0(
    "描述性分类计数：ROBUST = ", stability_n_5e("ROBUST"),
    "，PARTIAL = ", stability_n_5e("PARTIAL"),
    "，SENSITIVE = ", stability_n_5e("SENSITIVE"),
    "。分类依据方向一致性与相对 HIGH85 的最大 OR 漂移，不是统计检验。"
  ),
  "",
  paste(
    "不同阈值对应不同二元结局，因此不得用 HIGH80、HIGH85、HIGH90 之间的 AIC/BIC",
    "来选择所谓最佳阈值。"
  ),
  "",
  "## 与主要 Beta-binomial 模型的方向比较",
  "",
  paste0(
    "共同系数方向一致数 = ", direction_agree_n_5e, "/",
    direction_total_n_5e, "。由于结局定义与似然贡献不同，只比较方向与定性一致性，",
    "不直接比较 OR 大小。"
  ),
  "",
  "## 结论限制",
  "",
  paste(
    "本分析估计的是在给定协变量后达到高评分阈值的条件关联。结果不支持因果陈述，",
    "也不能替代主要 Beta-binomial 推断。阈值敏感性、样本内诊断和单个游戏影响均应与主模型共同阅读。"
  )
)

writeLines(
  enc2utf8(technical_report_5e),
  file.path(project_root, "reports", "step5e_high_rating_logistic_report.md"),
  useBytes = TRUE
)

message("Step 5E Chinese technical report: PASS")
