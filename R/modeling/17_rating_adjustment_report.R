# Step 5F Chinese technical report.

if (!exists("eb_prior_parameters_5f") || !exists("rank_correlations_5f")) {
  stop("Run Step 5F estimation before 17_rating_adjustment_report.R.", call. = FALSE)
}

fmt5f <- function(x, digits = 6) formatC(x, digits = digits, format = "f")
primary5f <- dplyr::filter(eb_prior_parameters_5f, prior_id == "EB_ALL_POSITIVE_N")
cor5f <- setNames(rank_correlations_5f$spearman, rank_correlations_5f$comparison)
technical_report_5f <- c(
  "# Step 5F Wilson + Empirical Bayes Rating Adjustment",
  "",
  "## 范围与样本",
  "",
  paste0("市场样本 N = ", market_n_5f, "；零评论游戏 N = ", zero_review_n_5f,
         "，保留在市场总体但不进入 rating estimation；n > 0 的 rating population N = ",
         rating_population_n_5f, "，同时保留 free 与 paid games。"),
  "",
  "本阶段不拟合 price、genre、platform 或 release predictor regression，也不作因果解释。",
  "",
  "## Wilson score interval",
  "",
  paste0("使用 z = ", format(wilson_z_5f, digits = 16),
         " 的非连续性校正 95% Wilson score interval。闭式公式与 Base R `uniroot` 的 score-test 反演在 ",
         nrow(wilson_validation_5f), " 个预先指定案例中全部通过 1e-9 容差。"),
  "",
  "Wilson interval 是频率学派抽样不确定性区间，不改变 Raw point estimate。Wilson lower 只用于 conservative uncertainty-aware ranking，不是 posterior mean，也不称为调整后评分。",
  "",
  "## Empirical Bayes prior",
  "",
  paste0("Primary prior 由全部 n > 0 游戏通过 Beta-Binomial marginal likelihood 确定性估计：alpha = ",
         fmt5f(primary5f$alpha), "，beta = ", fmt5f(primary5f$beta),
         "，prior mean = ", fmt5f(primary5f$prior_mean),
         "，precision / ESS = ", fmt5f(primary5f$prior_precision_ess),
         "，variance = ", fmt5f(primary5f$prior_variance, 8), "。"),
  "",
  paste0("有界 L-BFGS-B 定位并经 BFGS 精修；最终 convergence code = ", primary5f$convergence_code,
         "；maximum absolute analytic gradient = ", format(primary5f$gradient_max_abs, scientific = TRUE),
         "；minimum Hessian eigenvalue = ", format(primary5f$hessian_min_eigenvalue, scientific = TRUE),
         "；three deterministic starts agree = ", primary5f$starts_agree, "。"),
  "",
  "Primary prior 让大量低 n 游戏参与总体分布估计，因此另以 n>=10 和 n>=20 估计 prior，并将三套 prior 都应用到同一个 2,241-game evaluation population。替代 prior 仅作敏感性分析。",
  "",
  "## Shrinkage 与排名",
  "",
  paste0("评论数与绝对收缩的 Spearman 相关为 ", fmt5f(shrinkage_relationship_5f$spearman, 4),
         "。n>=1000 游戏的 median / p95 / max absolute shrinkage 分别为 ",
         fmt5f(100 * high_n_preservation_5f$median_absolute_shrinkage, 3), " / ",
         fmt5f(100 * high_n_preservation_5f$p95_absolute_shrinkage, 3), " / ",
         fmt5f(100 * high_n_preservation_5f$max_absolute_shrinkage, 3), " 个百分点。"),
  "",
  paste0("Raw-Wilson、Raw-EB、Wilson-EB 的 Spearman 相关分别为 ",
         fmt5f(cor5f[["RAW_VS_WILSON"]], 4), "、",
         fmt5f(cor5f[["RAW_VS_EB"]], 4), "、",
         fmt5f(cor5f[["WILSON_VS_EB"]], 4), "。Raw ranking 以 rate 降序、review count 降序、AppID 升序作 deterministic tie-break；review count 只解决 ties，不是 Raw rating 权重。"),
  "",
  "由于 Raw 100% 存在大量 ties，rank movement 不是纯连续指标，必须和 Raw rate、review count、Wilson lower 与 EB mean 一并解释。EB posterior mean 是 population-informed shrinkage estimate，不是真实评分。",
  "",
  "## 科学角色边界",
  "",
  "- Beta-binomial：主要推断回归。",
  "- High-rating Logistic：次要门槛分析。",
  "- Wilson：uncertainty-aware descriptive interval。",
  "- Empirical Bayes：population-informed shrinkage rating。",
  "",
  "四者解决的问题不同，结果不可互相替代；Step 5F 不进行 causal interpretation。"
)
writeLines(
  enc2utf8(technical_report_5f),
  file.path(project_root, "reports", "step5f_rating_adjustment_report.md"),
  useBytes = TRUE
)

message("Step 5F technical report: PASS")
