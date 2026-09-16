# Primary proportional-odds model and one pre-specified High-100 robustness model.
tier_formula_6b1 <- stats::as.formula(paste(
  "attention_tier ~ is_free +", paste(price_terms_6b1, collapse = " + "),
  "+ log_days + platform_segment +", paste(primary_genres_6b1, collapse = " + ")))
high100_formula_6b1 <- stats::update(tier_formula_6b1,
  high_attention_100 ~ .)
fit_warnings_6b1 <- list()
capture_fit_6b1 <- function(id, expr) {
  warnings <- character()
  fit <- withCallingHandlers(expr, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  })
  fit_warnings_6b1[[id]] <<- unique(warnings)
  fit
}
ordinal_fit_6b1 <- capture_fit_6b1("ORDINAL_POLR", MASS::polr(
  tier_formula_6b1, data = model_data_6b1, method = "logistic",
  Hess = TRUE, model = TRUE))
high100_fit_6b1 <- capture_fit_6b1("HIGH100_LOGISTIC", stats::glm(
  high100_formula_6b1, data = model_data_6b1,
  family = stats::binomial(link = "logit")))

ordinal_beta_6b1 <- stats::coef(ordinal_fit_6b1)
ordinal_vcov_6b1 <- stats::vcov(ordinal_fit_6b1)
ordinal_se_6b1 <- sqrt(diag(ordinal_vcov_6b1))[names(ordinal_beta_6b1)]
ordinal_coefficients_6b1 <- data.frame(
  term = names(ordinal_beta_6b1), estimate_log_odds = as.numeric(ordinal_beta_6b1),
  std_error = as.numeric(ordinal_se_6b1),
  z_value = as.numeric(ordinal_beta_6b1 / ordinal_se_6b1),
  odds_ratio_higher_tier = exp(as.numeric(ordinal_beta_6b1)),
  ci95_lower = exp(as.numeric(ordinal_beta_6b1 - 1.96 * ordinal_se_6b1)),
  ci95_upper = exp(as.numeric(ordinal_beta_6b1 + 1.96 * ordinal_se_6b1)),
  interpretation = ifelse(names(ordinal_beta_6b1) %in% price_terms_6b1,
    "Spline basis term: interpret tier probabilities, not this coefficient",
    "Odds ratio for being in a higher attention tier"),
  stringsAsFactors = FALSE)
ordinal_thresholds_6b1 <- data.frame(
  threshold = names(ordinal_fit_6b1$zeta),
  estimate = as.numeric(ordinal_fit_6b1$zeta), stringsAsFactors = FALSE)

x_ordinal_6b1 <- stats::model.matrix(
  stats::delete.response(stats::terms(ordinal_fit_6b1)), model_data_6b1)
ordinal_rank_6b1 <- qr(x_ordinal_6b1)$rank
ordinal_probs_fitted_6b1 <- stats::predict(ordinal_fit_6b1, type = "probs")
ordinal_numerical_ok_6b1 <- ordinal_fit_6b1$convergence == 0L &&
  ordinal_rank_6b1 == ncol(x_ordinal_6b1) &&
  all(is.finite(ordinal_vcov_6b1)) && max(ordinal_se_6b1) < 5 &&
  all(is.finite(ordinal_probs_fitted_6b1)) &&
  max(abs(rowSums(ordinal_probs_fitted_6b1) - 1)) < 1e-10
ordinal_fit_table_6b1 <- data.frame(
  model_id = "ORDINAL_PROPORTIONAL_ODDS", n_games = stats::nobs(ordinal_fit_6b1),
  tier1_n = sum(model_data_6b1$attention_tier == "Tier1"),
  tier2_n = sum(model_data_6b1$attention_tier == "Tier2"),
  tier3_n = sum(model_data_6b1$attention_tier == "Tier3"),
  tier4_n = sum(model_data_6b1$attention_tier == "Tier4"),
  log_likelihood = as.numeric(stats::logLik(ordinal_fit_6b1)),
  aic = stats::AIC(ordinal_fit_6b1), parameter_count = attr(stats::logLik(ordinal_fit_6b1), "df"),
  convergence_code = ordinal_fit_6b1$convergence,
  design_rank = ordinal_rank_6b1, design_columns = ncol(x_ordinal_6b1),
  max_coefficient_se = max(ordinal_se_6b1), numerical_stability = ordinal_numerical_ok_6b1,
  warning_count = length(fit_warnings_6b1$ORDINAL_POLR),
  formula = paste(deparse(tier_formula_6b1), collapse = " "),
  weights_used = FALSE, offset_used = FALSE, interactions_used = FALSE,
  stringsAsFactors = FALSE)

high100_matrix_6b1 <- summary(high100_fit_6b1)$coefficients
high100_coefficients_6b1 <- data.frame(
  term = rownames(high100_matrix_6b1),
  estimate_log_odds = high100_matrix_6b1[, 1], std_error = high100_matrix_6b1[, 2],
  z_value = high100_matrix_6b1[, 3], p_value = high100_matrix_6b1[, 4],
  odds_ratio_high100 = exp(high100_matrix_6b1[, 1]),
  ci95_lower = exp(high100_matrix_6b1[, 1] - 1.96 * high100_matrix_6b1[, 2]),
  ci95_upper = exp(high100_matrix_6b1[, 1] + 1.96 * high100_matrix_6b1[, 2]),
  row.names = NULL, stringsAsFactors = FALSE)
x_high100_6b1 <- stats::model.matrix(high100_fit_6b1)
high100_fit_table_6b1 <- data.frame(
  model_id = "HIGH_ATTENTION_100_LOGISTIC", n_games = stats::nobs(high100_fit_6b1),
  event_n = sum(model_data_6b1$high_attention_100 == 1L),
  non_event_n = sum(model_data_6b1$high_attention_100 == 0L),
  log_likelihood = as.numeric(stats::logLik(high100_fit_6b1)),
  aic = stats::AIC(high100_fit_6b1), parameter_count = length(stats::coef(high100_fit_6b1)),
  convergence = isTRUE(high100_fit_6b1$converged),
  design_rank = high100_fit_6b1$rank, design_columns = ncol(x_high100_6b1),
  max_coefficient_se = max(high100_matrix_6b1[, 2]),
  warning_count = length(fit_warnings_6b1$HIGH100_LOGISTIC),
  formula = paste(deparse(high100_formula_6b1), collapse = " "),
  weights_used = FALSE, offset_used = FALSE, interactions_used = FALSE,
  threshold_searched = FALSE, stringsAsFactors = FALSE)

make_reference_6b1 <- function(price_usd, is_free = 0L,
                                days = stats::median(model_data_6b1$days_since_release)) {
  n <- length(price_usd)
  d <- as.data.frame(model_data_6b1[rep(1L, n), , drop = FALSE])
  d$is_free <- rep(as.integer(is_free), length.out = n)
  d$current_price_usd <- ifelse(d$is_free == 1L, 0, price_usd)
  d$log1p_price <- log1p(d$current_price_usd)
  d$days_since_release <- days; d$log_days <- log(days)
  d$platform_segment <- factor("Windows only", levels = levels(model_data_6b1$platform_segment))
  for (term in primary_genres_6b1) d[[term]] <- 0L
  basis <- apply_tier_basis_6b1(d$current_price_usd, d$is_free, price_basis_6b1)
  for (j in seq_along(price_terms_6b1)) d[[price_terms_6b1[j]]] <- basis[, j]
  d
}
representative_prices_6b1 <- c(.99, 2.99, 4.99, 9.99, 14.99, 19.99)
price_newdata_6b1 <- make_reference_6b1(representative_prices_6b1)
price_probs_6b1 <- as.data.frame(stats::predict(ordinal_fit_6b1,
  newdata = price_newdata_6b1, type = "probs"))
price_tier_probabilities_6b1 <- data.frame(price_usd = representative_prices_6b1,
  days_since_release = price_newdata_6b1$days_since_release, price_probs_6b1,
  probability_high100_logistic = as.numeric(stats::predict(high100_fit_6b1,
    newdata = price_newdata_6b1, type = "response")), check.names = FALSE)
free_paid_newdata_6b1 <- dplyr::bind_rows(
  make_reference_6b1(expm1(price_basis_6b1$center), 0L),
  make_reference_6b1(0, 1L))
free_paid_probs_6b1 <- as.data.frame(stats::predict(ordinal_fit_6b1,
  newdata = free_paid_newdata_6b1, type = "probs"))
free_paid_probabilities_6b1 <- data.frame(
  game_type = c("Paid reference", "Free"),
  reference_price_usd = c(expm1(price_basis_6b1$center), NA_real_),
  days_since_release = free_paid_newdata_6b1$days_since_release,
  free_paid_probs_6b1,
  probability_high100_logistic = as.numeric(stats::predict(high100_fit_6b1,
    newdata = free_paid_newdata_6b1, type = "response")), check.names = FALSE)
stopifnot(stats::nobs(ordinal_fit_6b1) == 2240L,
  stats::nobs(high100_fit_6b1) == 2240L,
  ordinal_numerical_ok_6b1, isTRUE(high100_fit_6b1$converged),
  high100_fit_6b1$rank == ncol(x_high100_6b1),
  all(price_tier_probabilities_6b1[, tier_levels_6b1] >= 0),
  max(abs(rowSums(price_tier_probabilities_6b1[, tier_levels_6b1]) - 1)) < 1e-10)

write_attention_audit(ordinal_fit_table_6b1, "step6b1_ordinal_fit.csv")
write_attention_audit(ordinal_coefficients_6b1, "step6b1_ordinal_coefficients.csv")
write_attention_audit(ordinal_thresholds_6b1, "step6b1_ordinal_thresholds.csv")
write_attention_audit(price_tier_probabilities_6b1, "step6b1_price_tier_probabilities.csv")
write_attention_audit(free_paid_probabilities_6b1, "step6b1_free_paid_probabilities.csv")
write_attention_audit(high100_fit_table_6b1, "step6b1_high100_fit.csv")
write_attention_audit(high100_coefficients_6b1, "step6b1_high100_coefficients.csv")
