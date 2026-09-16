# Threshold-specific binary logits provide a transparent parallel-lines audit.
model_data_6b1$tier_gt1 <- as.integer(model_data_6b1$review_count >= 10L)
model_data_6b1$tier_gt2 <- as.integer(model_data_6b1$review_count >= 100L)
model_data_6b1$tier_gt3 <- as.integer(model_data_6b1$review_count >= 1000L)
threshold_specs_6b1 <- c(TIER2_PLUS = "tier_gt1", TIER3_PLUS = "tier_gt2",
  TIER4 = "tier_gt3")
threshold_fits_6b1 <- lapply(names(threshold_specs_6b1), function(id) {
  lhs <- threshold_specs_6b1[[id]]
  fit <- capture_fit_6b1(paste0("THRESHOLD_", id), stats::glm(
    stats::update(tier_formula_6b1, stats::as.formula(paste(lhs, "~ ."))),
    data = model_data_6b1, family = stats::binomial(link = "logit")))
  fit
})
names(threshold_fits_6b1) <- names(threshold_specs_6b1)

threshold_coefficients_6b1 <- dplyr::bind_rows(lapply(names(threshold_fits_6b1), function(id) {
  fit <- threshold_fits_6b1[[id]]
  m <- summary(fit)$coefficients
  keep <- intersect(names(ordinal_beta_6b1), rownames(m))
  data.frame(boundary = id, term = keep,
    estimate_log_odds = m[keep, 1], std_error = m[keep, 2],
    odds_ratio = exp(m[keep, 1]),
    ci95_lower = exp(m[keep, 1] - 1.96 * m[keep, 2]),
    ci95_upper = exp(m[keep, 1] + 1.96 * m[keep, 2]),
    stringsAsFactors = FALSE)
}))
parallel_odds_audit_6b1 <- dplyr::bind_rows(lapply(names(ordinal_beta_6b1), function(term) {
  d <- threshold_coefficients_6b1[threshold_coefficients_6b1$term == term, ]
  ordinal_est <- unname(ordinal_beta_6b1[term])
  major <- abs(ordinal_est) >= log(1.25) & abs(d$estimate_log_odds) >= log(1.25)
  reversals <- major & sign(d$estimate_log_odds) != sign(ordinal_est)
  weights <- 1 / d$std_error^2
  weighted_mean <- sum(weights * d$estimate_log_odds) / sum(weights)
  q <- sum(weights * (d$estimate_log_odds - weighted_mean)^2)
  data.frame(term = term, ordinal_estimate = ordinal_est,
    tier2plus_estimate = d$estimate_log_odds[d$boundary == "TIER2_PLUS"],
    tier3plus_estimate = d$estimate_log_odds[d$boundary == "TIER3_PLUS"],
    tier4_estimate = d$estimate_log_odds[d$boundary == "TIER4"],
    threshold_min = min(d$estimate_log_odds), threshold_max = max(d$estimate_log_odds),
    max_threshold_se = max(d$std_error),
    all_exact_directions_agree = all(sign(d$estimate_log_odds) == sign(ordinal_est)),
    major_direction_reversal = any(reversals),
    independence_approx_q = q, independence_approx_df = 2L,
    independence_approx_p = stats::pchisq(q, df = 2L, lower.tail = FALSE),
    diagnostic_note = "Threshold-logit diagnostic; Q treats fits as independent and is not a formal Brant test",
    stringsAsFactors = FALSE)
}))

threshold_fit_audit_6b1 <- dplyr::bind_rows(lapply(names(threshold_fits_6b1), function(id) {
  fit <- threshold_fits_6b1[[id]]; m <- summary(fit)$coefficients
  x <- stats::model.matrix(fit)
  data.frame(boundary = id, n_games = stats::nobs(fit),
    event_n = sum(stats::model.response(stats::model.frame(fit)) == 1L),
    non_event_n = sum(stats::model.response(stats::model.frame(fit)) == 0L),
    convergence = isTRUE(fit$converged), design_rank = fit$rank,
    design_columns = ncol(x), max_coefficient_se = max(m[, 2]),
    min_fitted_probability = min(stats::fitted(fit)),
    max_fitted_probability = max(stats::fitted(fit)),
    warning_count = length(fit_warnings_6b1[[paste0("THRESHOLD_", id)]]),
    stringsAsFactors = FALSE)
}))

nonprice_terms_6b1 <- setdiff(names(ordinal_beta_6b1), price_terms_6b1)
major_po_reversals_6b1 <- sum(parallel_odds_audit_6b1$major_direction_reversal[
  parallel_odds_audit_6b1$term %in% nonprice_terms_6b1])
exact_po_agreement_rate_6b1 <- mean(parallel_odds_audit_6b1$all_exact_directions_agree[
  parallel_odds_audit_6b1$term %in% nonprice_terms_6b1])
threshold_numerical_ok_6b1 <- all(threshold_fit_audit_6b1$convergence) &&
  all(threshold_fit_audit_6b1$design_rank == threshold_fit_audit_6b1$design_columns) &&
  max(threshold_fit_audit_6b1$max_coefficient_se) < 5

direction_comparison_6b1 <- dplyr::left_join(
  ordinal_coefficients_6b1[, c("term", "estimate_log_odds", "odds_ratio_higher_tier",
    "ci95_lower", "ci95_upper")],
  high100_coefficients_6b1[high100_coefficients_6b1$term != "(Intercept)",
    c("term", "estimate_log_odds", "odds_ratio_high100", "ci95_lower", "ci95_upper")],
  by = "term", suffix = c("_ordinal", "_high100")) |>
  dplyr::mutate(
    direction_ordinal = ifelse(estimate_log_odds_ordinal > 0, "POSITIVE", "NEGATIVE"),
    direction_high100 = ifelse(estimate_log_odds_high100 > 0, "POSITIVE", "NEGATIVE"),
    direction_agreement = direction_ordinal == direction_high100,
    major_magnitude_contradiction = !direction_agreement &
      abs(estimate_log_odds_ordinal) >= log(1.25) &
      abs(estimate_log_odds_high100) >= log(1.25),
    interpretation_scope = ifelse(term %in% price_terms_6b1,
      "Spline basis; use price probability shape", "Coefficient direction comparison"))

expected_tier_score_6b1 <- as.numeric(as.matrix(
  price_tier_probabilities_6b1[, tier_levels_6b1]) %*% 1:4)
price_shape_audit_6b1 <- data.frame(
  representative_price_n = length(representative_prices_6b1),
  ordinal_expected_tier_min = min(expected_tier_score_6b1),
  ordinal_expected_tier_max = max(expected_tier_score_6b1),
  ordinal_expected_tier_monotone = all(diff(expected_tier_score_6b1) >= 0) ||
    all(diff(expected_tier_score_6b1) <= 0),
  high100_probability_monotone = all(diff(price_tier_probabilities_6b1$probability_high100_logistic) >= 0) ||
    all(diff(price_tier_probabilities_6b1$probability_high100_logistic) <= 0),
  shape_spearman_correlation = stats::cor(expected_tier_score_6b1,
    price_tier_probabilities_6b1$probability_high100_logistic, method = "spearman"),
  stringsAsFactors = FALSE)

core_direction_6b1 <- direction_comparison_6b1[
  !direction_comparison_6b1$term %in% price_terms_6b1, ]
high100_broad_agreement_6b1 <- !any(core_direction_6b1$major_magnitude_contradiction) &&
  price_shape_audit_6b1$shape_spearman_correlation >= .8
po_conclusion_6b1 <- if (!threshold_numerical_ok_6b1 ||
    major_po_reversals_6b1 > ceiling(.35 * length(nonprice_terms_6b1))) {
  "FAIL"
} else if (major_po_reversals_6b1 == 0L && exact_po_agreement_rate_6b1 >= .75) {
  "PASS"
} else {
  "APPROXIMATE"
}

sparse_cells_6b1 <- dplyr::bind_rows(
  as.data.frame(table(group = ifelse(model_data_6b1$is_free == 1L, "Free", "Paid"),
    tier = model_data_6b1$attention_tier), stringsAsFactors = FALSE),
  as.data.frame(table(group = model_data_6b1$platform_segment,
    tier = model_data_6b1$attention_tier), stringsAsFactors = FALSE)) |>
  dplyr::rename(n_games = Freq) |>
  dplyr::mutate(sparse_lt5 = n_games < 5L)
fit_warnings_table_6b1 <- dplyr::bind_rows(lapply(names(fit_warnings_6b1), function(id) {
  w <- fit_warnings_6b1[[id]]
  if (!length(w)) return(data.frame(model_id = id, warning = "NONE"))
  data.frame(model_id = id, warning = w)
}))

stopifnot(all(threshold_fit_audit_6b1$n_games == 2240L),
  all(is.finite(threshold_coefficients_6b1$estimate_log_odds)),
  stats::nobs(high100_fit_6b1) == stats::nobs(ordinal_fit_6b1),
  all(is.finite(direction_comparison_6b1$estimate_log_odds_high100)))
write_attention_audit(parallel_odds_audit_6b1, "step6b1_parallel_odds_audit.csv")
write_attention_audit(threshold_coefficients_6b1, "step6b1_threshold_coefficients.csv")
write_attention_audit(threshold_fit_audit_6b1, "step6b1_threshold_fit_audit.csv")
write_attention_audit(direction_comparison_6b1, "step6b1_direction_comparison.csv")
write_attention_audit(price_shape_audit_6b1, "step6b1_price_shape_audit.csv")
write_attention_audit(sparse_cells_6b1, "step6b1_sparse_cell_audit.csv")
write_attention_audit(fit_warnings_table_6b1, "step6b1_fit_warnings.csv")
