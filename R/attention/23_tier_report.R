# Database preservation, freeze gate, and concise technical report.
db_after_6b1 <- with_steam_db(function(con) DBI::dbGetQuery(con, paste(
  "SELECT (SELECT COUNT(*) FROM games) AS games,",
  "(SELECT COUNT(*) FROM review_snapshots) AS review_snapshots,",
  "(SELECT COUNT(*) FROM game_genres) AS game_genres,",
  "(SELECT COUNT(*) FROM genres) AS genres,",
  "(SELECT COUNT(*) FROM vw_model_sample_20) AS model20")))
db_expected_6b1 <- c(games = 3000, review_snapshots = 3000,
  game_genres = 8796, genres = 13, model20 = 844)
db_before_6b1 <- loaded_model_data$counts_before
db_preservation_6b1 <- data.frame(object_name = names(db_expected_6b1),
  count_before = vapply(db_before_6b1[names(db_expected_6b1)],
    function(x) as.numeric(x[[1]]), numeric(1)),
  count_after = vapply(db_after_6b1[names(db_expected_6b1)],
    function(x) as.numeric(x[[1]]), numeric(1)))
db_preservation_6b1$unchanged <- db_preservation_6b1$count_before ==
  db_preservation_6b1$count_after
db_ok_6b1 <- all(db_preservation_6b1$unchanged) &&
  all(db_preservation_6b1$count_after == unname(db_expected_6b1))

reports_render_6b1 <- all(file.exists(file.path(project_root, "reports", c(
  "11_attention_tier_visual_audit.html", "08_attention_modeling.html"))))
numerical_stability_6b1 <- ordinal_numerical_ok_6b1 &&
  threshold_numerical_ok_6b1 && isTRUE(high100_fit_6b1$converged) &&
  high100_fit_6b1$rank == ncol(x_high100_6b1) &&
  max(high100_matrix_6b1[, 2]) < 5
freeze_criteria_6b1 <- data.frame(
  criterion = c("population_valid", "ordinal_model_converged",
    "no_major_numerical_problem", "proportional_odds_acceptable_or_approximate",
    "high100_robustness_broadly_agrees", "no_major_direction_contradictions",
    "reports_render", "database_unchanged"),
  pass = c(nrow(positive_all_6b1) == 2241L && nrow(model_data_6b1) == 2240L &&
      all(model_data_6b1$review_count > 0L),
    ordinal_fit_6b1$convergence == 0L,
    numerical_stability_6b1,
    po_conclusion_6b1 %in% c("PASS", "APPROXIMATE"),
    high100_broad_agreement_6b1,
    !any(direction_comparison_6b1$major_magnitude_contradiction),
    reports_render_6b1, db_ok_6b1), stringsAsFactors = FALSE)
step6b1_pass_6b1 <- all(freeze_criteria_6b1$pass)
step6b1_decision <- data.frame(
  status = ifelse(step6b1_pass_6b1, "PASS", "PENDING_REPORT_RENDER"),
  proportional_odds_assumption = po_conclusion_6b1,
  high100_robustness = ifelse(high100_broad_agreement_6b1, "PASS", "FAIL"),
  numerical_stability = ifelse(numerical_stability_6b1, "PASS", "FAIL"),
  attention_intensity_model_frozen = step6b1_pass_6b1,
  attention_analysis_closed = step6b1_pass_6b1,
  ready_for_portfolio_packaging = step6b1_pass_6b1,
  final_model = "Cumulative ordinal logistic (proportional odds; approximate assumption)",
  model_n = nrow(model_data_6b1), stringsAsFactors = FALSE)

portfolio_summary_6b1 <- data.frame(
  item = 1:5,
  summary = c(
    sprintf("%.1f%% of sampled games received zero Steam reviews.",
      100 * sum(games_market_wide$total_reviews == 0L) / nrow(games_market_wide)),
    sprintf("Among reviewed games, %.1f%% were Tier 1 and %.1f%% were Tier 4.",
      tier_distribution_6b1$percent[1], tier_distribution_6b1$percent[4]),
    "Review attention was extremely concentrated; the raw count model was not stable under the heavy tail.",
    "Attention intensity was therefore summarized with four ordered tiers and an ordinal logistic model.",
    "The proportional-odds assumption was approximate, while the pre-specified High-100 logistic check broadly agreed."
  ), stringsAsFactors = FALSE)

write_attention_audit(db_preservation_6b1, "step6b1_database_preservation.csv")
write_attention_audit(freeze_criteria_6b1, "step6b1_freeze_criteria.csv")
write_attention_audit(step6b1_decision, "step6b1_stage_decision.csv")
write_attention_audit(portfolio_summary_6b1, "step6b1_portfolio_summary.csv")

coef_lookup_6b1 <- function(term) ordinal_coefficients_6b1[
  ordinal_coefficients_6b1$term == term, ][1, ]
report_lines_6b1 <- c(
  "# Step 6B.1 Fast Attention Tier Model Freeze", "",
  sprintf("Status: **%s**. Final model: cumulative ordinal logistic.", step6b1_decision$status),
  sprintf("Proportional-odds assumption: **%s**. High-100 robustness: **%s**.",
    po_conclusion_6b1, step6b1_decision$high100_robustness), "",
  "## Population and tiers",
  sprintf("Positive-count population N=%d; model N=%d; zero-review games excluded N=%d.",
    nrow(positive_all_6b1), nrow(model_data_6b1),
    sum(games_market_wide$total_reviews == 0L)),
  paste(sprintf("- %s: N=%d (%.2f%%), median reviews=%.0f, free=%d, paid=%d",
    tier_distribution_6b1$attention_tier, tier_distribution_6b1$n_games,
    tier_distribution_6b1$percent, tier_distribution_6b1$median_review_count,
    tier_distribution_6b1$free_n, tier_distribution_6b1$paid_n), collapse = "\n"), "",
  "## Primary ordinal model",
  sprintf("Convergence code=%d; design rank=%d/%d; maximum coefficient SE=%.3f; AIC=%.2f.",
    ordinal_fit_6b1$convergence, ordinal_rank_6b1, ncol(x_ordinal_6b1),
    max(ordinal_se_6b1), stats::AIC(ordinal_fit_6b1)),
  "An OR above 1 denotes higher odds of being in a higher attention tier; it is not a review-count multiplier.",
  sprintf("Free OR=%.3f (95%% CI %.3f-%.3f); this subgroup has only 34 games.",
    coef_lookup_6b1("is_free")$odds_ratio_higher_tier,
    coef_lookup_6b1("is_free")$ci95_lower, coef_lookup_6b1("is_free")$ci95_upper),
  sprintf("Log-days OR=%.3f (95%% CI %.3f-%.3f).",
    coef_lookup_6b1("log_days")$odds_ratio_higher_tier,
    coef_lookup_6b1("log_days")$ci95_lower, coef_lookup_6b1("log_days")$ci95_upper), "",
  "## Proportional-odds and High-100 audit",
  sprintf("Exact threshold-direction agreement among non-price terms=%.1f%%; major direction reversals=%d.",
    100 * exact_po_agreement_rate_6b1, major_po_reversals_6b1),
  "Several weak coefficients change sign across boundaries, so proportional odds holds approximately rather than exactly.",
  sprintf("High-100 model events=%d; major ordinal/High-100 contradictions=%d; price-shape Spearman correlation=%.2f.",
    high100_fit_table_6b1$event_n,
    sum(direction_comparison_6b1$major_magnitude_contradiction),
    price_shape_audit_6b1$shape_spearman_correlation), "",
  "## Price probabilities",
  "The paid-price spline is re-estimated on 2,206 reviewed paid games. Free rows have a zero spline basis and retain is_free.",
  paste(sprintf("- $%.2f: Tier1 %.1f%%, Tier2 %.1f%%, Tier3 %.1f%%, Tier4 %.1f%%",
    price_tier_probabilities_6b1$price_usd,
    100 * price_tier_probabilities_6b1$Tier1,
    100 * price_tier_probabilities_6b1$Tier2,
    100 * price_tier_probabilities_6b1$Tier3,
    100 * price_tier_probabilities_6b1$Tier4), collapse = "\n"),
  "Spline coefficients are not interpreted separately. Price associations are not causal.", "",
  "## Portfolio Summary",
  paste(sprintf("- %s", portfolio_summary_6b1$summary), collapse = "\n"), "",
  "## Freeze decision and limitations",
  paste(sprintf("- %s: %s", freeze_criteria_6b1$criterion,
    ifelse(freeze_criteria_6b1$pass, "PASS", "FAIL")), collapse = "\n"),
  "The model compresses a severe heavy tail into portfolio-friendly tiers, sacrificing within-tier count detail.",
  "The proportional-odds assumption is approximate, the free subgroup is sparse, and all coefficients are conditional associations.",
  "The raw Step 6B count-model failure remains part of the methodological record.",
  sprintf("Database counts unchanged: %s. No credentials are written to outputs.", db_ok_6b1), "")
writeLines(report_lines_6b1,
  file.path(project_root, "reports", "step6b1_attention_tier_report.md"), useBytes = TRUE)
