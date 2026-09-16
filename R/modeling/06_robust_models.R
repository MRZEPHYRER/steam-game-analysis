# Fit the pre-specified Step 5C quasibinomial and beta-binomial models.

if (!exists("baseline_fit") || !exists("model20_paid_baseline")) {
  stop("Run Step 5B baseline scripts before 06_robust_models.R.", call. = FALSE)
}
if (!requireNamespace("glmmTMB", quietly = TRUE)) {
  stop("Missing required package glmmTMB; install a stable CRAN release.", call. = FALSE)
}

step5c_package <- "glmmTMB"
step5c_package_version <- as.character(utils::packageVersion(step5c_package))
step5c_tmb_version <- as.character(utils::packageVersion("TMB"))

capture_fit <- function(expression, label) {
  captured <- character()
  value <- withCallingHandlers(
    expression,
    warning = function(w) captured <<- c(captured, conditionMessage(w))
  )
  list(value = value, warnings = unique(captured), label = label)
}

stopifnot(
  nrow(model20_paid_baseline) == 836,
  dplyr::n_distinct(model20_paid_baseline$appid) == 836,
  !anyDuplicated(model20_paid_baseline$appid),
  all(model20_paid_baseline$positive_reviews + model20_paid_baseline$negative_reviews ==
        model20_paid_baseline$total_reviews),
  all(stats::complete.cases(model20_paid_baseline[, c(
    "z_log1p_price", "z_days_since_release", "platform_segment", baseline_genres
  )]))
)

frozen_step5b_coefficients <- utils::read.csv(
  file.path(model_audit_dir, "step5b_coefficients.csv"), check.names = FALSE
)
frozen_step5b_scaling <- utils::read.csv(
  file.path(model_audit_dir, "step5b_scaling_parameters.csv"), check.names = FALSE
)
stopifnot(
  identical(frozen_step5b_coefficients$term, names(stats::coef(baseline_fit))),
  isTRUE(all.equal(
    frozen_step5b_coefficients$estimate_log_odds,
    unname(stats::coef(baseline_fit)),
    tolerance = 1e-12
  )),
  isTRUE(all.equal(
    frozen_step5b_scaling$scaling_mean,
    c(price_log_mean, days_mean),
    tolerance = 1e-12
  )),
  isTRUE(all.equal(
    frozen_step5b_scaling$scaling_sd,
    c(price_log_sd, days_sd),
    tolerance = 1e-12
  ))
)

quasi_capture <- capture_fit(
  stats::glm(
    formula = frozen_baseline_formula,
    family = stats::quasibinomial(link = "logit"),
    data = model20_paid_baseline
  ),
  "quasibinomial full"
)
quasi_fit <- quasi_capture$value
quasi_summary <- summary(quasi_fit)
quasi_coef_matrix <- quasi_summary$coefficients
quasi_df <- stats::df.residual(quasi_fit)
quasi_critical <- stats::qt(0.975, df = quasi_df)
quasi_lower <- quasi_coef_matrix[, "Estimate"] - quasi_critical * quasi_coef_matrix[, "Std. Error"]
quasi_upper <- quasi_coef_matrix[, "Estimate"] + quasi_critical * quasi_coef_matrix[, "Std. Error"]
quasi_coefficients <- data.frame(
  term = rownames(quasi_coef_matrix),
  estimate_log_odds = quasi_coef_matrix[, "Estimate"],
  std_error = quasi_coef_matrix[, "Std. Error"],
  t_value = quasi_coef_matrix[, "t value"],
  p_value = quasi_coef_matrix[, "Pr(>|t|)"],
  ci95_lower_logit = quasi_lower,
  ci95_upper_logit = quasi_upper,
  odds_ratio = exp(quasi_coef_matrix[, "Estimate"]),
  or_ci95_lower = exp(quasi_lower),
  or_ci95_upper = exp(quasi_upper),
  ci_method = sprintf("Wald t, df=%d", quasi_df),
  stringsAsFactors = FALSE,
  row.names = NULL
)
write_model_audit(quasi_coefficients, "step5c_quasi_coefficients.csv")

quasi_pearson <- sum(stats::residuals(quasi_fit, type = "pearson")^2) / quasi_df
quasi_dispersion <- as.numeric(quasi_summary$dispersion)
stopifnot(
  isTRUE(quasi_fit$converged),
  identical(names(stats::coef(quasi_fit)), names(stats::coef(baseline_fit))),
  isTRUE(all.equal(
    unname(stats::coef(quasi_fit)), unname(stats::coef(baseline_fit)),
    tolerance = 1e-10
  )),
  is.finite(quasi_dispersion),
  abs(quasi_dispersion - quasi_pearson) / quasi_pearson < 1e-7
)
quasi_fit_table <- data.frame(
  model = "Quasibinomial",
  n_games = stats::nobs(quasi_fit),
  n_coefficients = length(stats::coef(quasi_fit)),
  residual_df = quasi_df,
  converged = isTRUE(quasi_fit$converged),
  iterations = quasi_fit$iter,
  estimated_dispersion = quasi_dispersion,
  pearson_dispersion = quasi_pearson,
  baseline_pearson_dispersion = sum(stats::residuals(baseline_fit, type = "pearson")^2) /
    stats::df.residual(baseline_fit),
  log_likelihood = NA_real_,
  aic = NA_real_,
  bic = NA_real_,
  likelihood_note = "Not defined/comparable: quasi-likelihood",
  warning_count = length(quasi_capture$warnings),
  stringsAsFactors = FALSE
)
write_model_audit(quasi_fit_table, "step5c_quasi_fit.csv")

binomial_ci_width <- frozen_step5b_coefficients$ci95_logit_upper -
  frozen_step5b_coefficients$ci95_logit_lower
quasi_ci_width <- quasi_coefficients$ci95_upper_logit - quasi_coefficients$ci95_lower_logit
quasi_inflation <- data.frame(
  term = quasi_coefficients$term,
  binomial_std_error = frozen_step5b_coefficients$std_error,
  quasi_std_error = quasi_coefficients$std_error,
  se_inflation_ratio = quasi_coefficients$std_error /
    frozen_step5b_coefficients$std_error,
  sqrt_estimated_dispersion = sqrt(quasi_dispersion),
  binomial_ci_width = binomial_ci_width,
  quasi_ci_width = quasi_ci_width,
  ci_width_inflation_ratio = quasi_ci_width / binomial_ci_width,
  binomial_ci_crosses_or_1 = frozen_step5b_coefficients$or_ci95_lower <= 1 &
    frozen_step5b_coefficients$or_ci95_upper >= 1,
  quasi_ci_crosses_or_1 = quasi_coefficients$or_ci95_lower <= 1 &
    quasi_coefficients$or_ci95_upper >= 1,
  ci_crossing_status_changed =
    (frozen_step5b_coefficients$or_ci95_lower <= 1 &
       frozen_step5b_coefficients$or_ci95_upper >= 1) !=
    (quasi_coefficients$or_ci95_lower <= 1 & quasi_coefficients$or_ci95_upper >= 1),
  stringsAsFactors = FALSE
)
write_model_audit(quasi_inflation, "step5c_quasi_inflation.csv")

beta_capture <- capture_fit(
  glmmTMB::glmmTMB(
    formula = frozen_baseline_formula,
    family = glmmTMB::betabinomial(link = "logit"),
    data = model20_paid_baseline
  ),
  "beta-binomial full"
)
beta_fit <- beta_capture$value
beta_summary <- summary(beta_fit)
beta_coef_matrix <- beta_summary$coefficients$cond
beta_lower <- beta_coef_matrix[, "Estimate"] - stats::qnorm(0.975) * beta_coef_matrix[, "Std. Error"]
beta_upper <- beta_coef_matrix[, "Estimate"] + stats::qnorm(0.975) * beta_coef_matrix[, "Std. Error"]
beta_coefficients <- data.frame(
  term = rownames(beta_coef_matrix),
  estimate_log_odds = beta_coef_matrix[, "Estimate"],
  std_error = beta_coef_matrix[, "Std. Error"],
  z_value = beta_coef_matrix[, "z value"],
  p_value = beta_coef_matrix[, "Pr(>|z|)"],
  ci95_lower_logit = beta_lower,
  ci95_upper_logit = beta_upper,
  odds_ratio = exp(beta_coef_matrix[, "Estimate"]),
  or_ci95_lower = exp(beta_lower),
  or_ci95_upper = exp(beta_upper),
  ci_method = "Wald normal",
  stringsAsFactors = FALSE,
  row.names = NULL
)
beta_profile_warnings <- character()
beta_profile_error <- ""
beta_profile_ci_matrix <- tryCatch(
  withCallingHandlers(
    stats::confint(beta_fit, parm = "beta_", method = "profile", level = 0.95),
    warning = function(w) {
      beta_profile_warnings <<- c(beta_profile_warnings, conditionMessage(w))
    }
  ),
  error = function(e) {
    beta_profile_error <<- conditionMessage(e)
    NULL
  }
)
if (is.null(beta_profile_ci_matrix)) {
  beta_coefficients$profile_ci95_lower_logit <- NA_real_
  beta_coefficients$profile_ci95_upper_logit <- NA_real_
  beta_coefficients$profile_or_ci95_lower <- NA_real_
  beta_coefficients$profile_or_ci95_upper <- NA_real_
  beta_coefficients$profile_ci_status <- "FAILED"
  beta_coefficients$profile_ci_failure_reason <- beta_profile_error
} else {
  beta_profile_ci_matrix <- beta_profile_ci_matrix[
    match(beta_coefficients$term, rownames(beta_profile_ci_matrix)), , drop = FALSE
  ]
  beta_coefficients$profile_ci95_lower_logit <- beta_profile_ci_matrix[, 1]
  beta_coefficients$profile_ci95_upper_logit <- beta_profile_ci_matrix[, 2]
  beta_coefficients$profile_or_ci95_lower <- exp(beta_profile_ci_matrix[, 1])
  beta_coefficients$profile_or_ci95_upper <- exp(beta_profile_ci_matrix[, 2])
  beta_coefficients$profile_ci_status <- "PASS"
  beta_coefficients$profile_ci_failure_reason <- ""
}
write_model_audit(beta_coefficients, "step5c_beta_binomial_coefficients.csv")

beta_convergence_code <- beta_fit$fit$convergence
beta_pd_hessian <- isTRUE(beta_fit$sdr$pdHess)
beta_gradient_max <- if (!is.null(beta_fit$sdr$gradient.fixed)) {
  max(abs(beta_fit$sdr$gradient.fixed))
} else {
  NA_real_
}
beta_dispersion_phi <- as.numeric(stats::sigma(beta_fit))
beta_rho <- 1 / (beta_dispersion_phi + 1)
beta_loglik <- as.numeric(stats::logLik(beta_fit))
beta_aic <- stats::AIC(beta_fit)
beta_bic <- stats::BIC(beta_fit)
stopifnot(
  beta_convergence_code == 0,
  beta_pd_hessian,
  identical(rownames(stats::model.frame(quasi_fit)), rownames(beta_fit$frame)),
  stats::nobs(quasi_fit) == nrow(model20_paid_baseline),
  stats::nobs(beta_fit) == nrow(model20_paid_baseline),
  identical(rownames(beta_coef_matrix), names(stats::coef(baseline_fit))),
  all(is.finite(beta_coef_matrix)),
  is.finite(beta_dispersion_phi), beta_dispersion_phi > 0,
  is.finite(beta_rho), beta_rho > 0, beta_rho < 1
)

beta_fit_table <- data.frame(
  model = "Beta-binomial",
  package = step5c_package,
  package_version = step5c_package_version,
  tmb_dependency_version = step5c_tmb_version,
  n_games = stats::nobs(beta_fit),
  total_positive_reviews = sum(model20_paid_baseline$positive_reviews),
  total_negative_reviews = sum(model20_paid_baseline$negative_reviews),
  n_coefficients = nrow(beta_coef_matrix),
  residual_df = stats::df.residual(beta_fit),
  convergence_code = beta_convergence_code,
  converged = beta_convergence_code == 0 && beta_pd_hessian,
  positive_definite_hessian = beta_pd_hessian,
  max_abs_fixed_gradient = beta_gradient_max,
  optimizer = "nlminb (glmmTMB default)",
  iterations = if (!is.null(beta_fit$fit$iterations)) beta_fit$fit$iterations else NA_integer_,
  optimizer_message = if (!is.null(beta_fit$fit$message)) beta_fit$fit$message else "",
  warning_count = length(beta_capture$warnings),
  profile_ci_status = if (is.null(beta_profile_ci_matrix)) "FAILED" else "PASS",
  profile_ci_warning_count = length(beta_profile_warnings),
  log_likelihood = beta_loglik,
  aic = beta_aic,
  bic = beta_bic,
  dispersion_phi = beta_dispersion_phi,
  intra_game_rho = beta_rho,
  stringsAsFactors = FALSE
)
write_model_audit(beta_fit_table, "step5c_beta_binomial_fit.csv")

beta_dispersion_table <- data.frame(
  package = step5c_package,
  package_version = step5c_package_version,
  family = "glmmTMB::betabinomial(link = logit)",
  parameter_name = "phi = exp(dispersion linear predictor)",
  parameter_value = beta_dispersion_phi,
  variance_definition = "Var(Y)=n*p*(1-p)*(phi+n)/(phi+1)",
  interpretation = "phi is beta precision; larger phi means less extra-binomial heterogeneity and phi -> infinity is the binomial limit",
  derived_rho_name = "rho = 1/(phi+1)",
  derived_rho = beta_rho,
  rho_interpretation = "latent within-game Bernoulli intraclass correlation; larger rho means more within-game dependence/heterogeneity",
  boundary_flag = beta_dispersion_phi < 1e-6 || beta_dispersion_phi > 1e8,
  extreme_fixed_parameter_count = sum(abs(beta_coef_matrix[, "Estimate"]) > 10 |
                                        beta_coef_matrix[, "Std. Error"] > 10),
  stringsAsFactors = FALSE
)
write_model_audit(beta_dispersion_table, "step5c_beta_dispersion.csv")

beta_full_vcov <- stats::vcov(beta_fit, full = TRUE)
beta_full_variances <- diag(beta_full_vcov)
dispersion_log_estimate <- unname(beta_fit$fit$parfull[names(beta_fit$fit$parfull) == "betadisp"])
dispersion_log_se <- sqrt(unname(beta_full_variances[rownames(beta_full_vcov) == "disp~(Intercept)"]))
dispersion_log_z <- dispersion_log_estimate / dispersion_log_se
beta_diagnose_output <- capture.output(
  beta_diagnose_ok <- glmmTMB::diagnose(beta_fit)
)
beta_fitted_probability <- as.numeric(stats::predict(beta_fit, type = "response", re.form = NA))
beta_diagnostics <- data.frame(
  convergence_code = beta_convergence_code,
  positive_definite_hessian = beta_pd_hessian,
  max_abs_fixed_gradient = beta_gradient_max,
  optimizer_message = beta_fit$fit$message,
  diagnose_return = beta_diagnose_ok,
  diagnose_flag_reason = "Unusually large |z|>5 only for conditional intercept and dispersion intercept; no bad parameter, gradient, or Hessian flag",
  conditional_intercept_z = unname(beta_coef_matrix["(Intercept)", "z value"]),
  dispersion_log_estimate = dispersion_log_estimate,
  dispersion_log_se = dispersion_log_se,
  dispersion_log_z = dispersion_log_z,
  extreme_fixed_estimate_or_se_count = sum(
    abs(beta_coef_matrix[, "Estimate"]) > 10 | beta_coef_matrix[, "Std. Error"] > 10
  ),
  fitted_probability_min = min(beta_fitted_probability),
  fitted_probability_max = max(beta_fitted_probability),
  dispersion_boundary_flag = beta_dispersion_table$boundary_flag,
  profile_ci_status = if (is.null(beta_profile_ci_matrix)) "FAILED" else "PASS",
  profile_ci_warning_count = length(beta_profile_warnings),
  stringsAsFactors = FALSE
)
write_model_audit(beta_diagnostics, "step5c_beta_diagnostics.csv")

model_comparison <- data.frame(
  model = c("Binomial", "Quasibinomial", "Beta-binomial"),
  n_games = c(stats::nobs(baseline_fit), stats::nobs(quasi_fit), stats::nobs(beta_fit)),
  n_coefficients = c(length(stats::coef(baseline_fit)), length(stats::coef(quasi_fit)), nrow(beta_coef_matrix)),
  log_likelihood = c(as.numeric(stats::logLik(baseline_fit)), NA_real_, beta_loglik),
  aic = c(stats::AIC(baseline_fit), NA_real_, beta_aic),
  bic = c(stats::BIC(baseline_fit), NA_real_, beta_bic),
  dispersion = c(
    quasi_fit_table$baseline_pearson_dispersion,
    quasi_dispersion,
    beta_dispersion_phi
  ),
  dispersion_definition = c(
    "Pearson chi-square/residual df",
    "estimated quasi variance multiplier",
    "beta precision phi (not a variance multiplier)"
  ),
  convergence = c(
    isTRUE(baseline_fit$converged), isTRUE(quasi_fit$converged),
    beta_convergence_code == 0 && beta_pd_hessian
  ),
  likelihood_comparable_to_binomial = c(TRUE, FALSE, TRUE),
  delta_aic_vs_binomial = c(0, NA_real_, beta_aic - stats::AIC(baseline_fit)),
  loglik_difference_vs_binomial = c(0, NA_real_, beta_loglik - as.numeric(stats::logLik(baseline_fit))),
  stringsAsFactors = FALSE
)
write_model_audit(model_comparison, "step5c_model_comparison.csv")

step5c_specification_audit <- data.frame(
  primary_n = nrow(model20_paid_baseline),
  unique_appids = dplyr::n_distinct(model20_paid_baseline$appid),
  quasi_n = stats::nobs(quasi_fit),
  beta_binomial_n = stats::nobs(beta_fit),
  same_model_frame_rows = identical(
    rownames(stats::model.frame(quasi_fit)), rownames(beta_fit$frame)
  ),
  formula = expected_formula_text,
  price_scaling_mean = price_log_mean,
  price_scaling_sd = price_log_sd,
  days_scaling_mean = days_mean,
  days_scaling_sd = days_sd,
  response_identity_valid = all(
    model20_paid_baseline$positive_reviews + model20_paid_baseline$negative_reviews ==
      model20_paid_baseline$total_reviews
  ),
  stringsAsFactors = FALSE
)
write_model_audit(step5c_specification_audit, "step5c_specification_audit.csv")

step5c_database_preservation <- database_preservation
step5c_database_preservation$audit_step <- "Step 5C"
write_model_audit(step5c_database_preservation, "step5c_database_preservation.csv")

coefficient_comparison <- data.frame(
  term = frozen_step5b_coefficients$term,
  binomial_estimate = frozen_step5b_coefficients$estimate_log_odds,
  binomial_se = frozen_step5b_coefficients$std_error,
  binomial_or = frozen_step5b_coefficients$odds_ratio,
  binomial_or_ci_lower = frozen_step5b_coefficients$or_ci95_lower,
  binomial_or_ci_upper = frozen_step5b_coefficients$or_ci95_upper,
  quasi_estimate = quasi_coefficients$estimate_log_odds,
  quasi_se = quasi_coefficients$std_error,
  quasi_or = quasi_coefficients$odds_ratio,
  quasi_or_ci_lower = quasi_coefficients$or_ci95_lower,
  quasi_or_ci_upper = quasi_coefficients$or_ci95_upper,
  beta_estimate = beta_coefficients$estimate_log_odds,
  beta_se = beta_coefficients$std_error,
  beta_or = beta_coefficients$odds_ratio,
  beta_or_ci_lower = beta_coefficients$or_ci95_lower,
  beta_or_ci_upper = beta_coefficients$or_ci95_upper,
  beta_profile_or_ci_lower = beta_coefficients$profile_or_ci95_lower,
  beta_profile_or_ci_upper = beta_coefficients$profile_or_ci95_upper,
  quasi_minus_binomial = quasi_coefficients$estimate_log_odds -
    frozen_step5b_coefficients$estimate_log_odds,
  beta_minus_binomial = beta_coefficients$estimate_log_odds -
    frozen_step5b_coefficients$estimate_log_odds,
  beta_minus_quasi = beta_coefficients$estimate_log_odds - quasi_coefficients$estimate_log_odds,
  quasi_relative_abs_estimate_change_pct = 100 * abs(
    quasi_coefficients$estimate_log_odds - frozen_step5b_coefficients$estimate_log_odds
  ) / pmax(abs(frozen_step5b_coefficients$estimate_log_odds), .Machine$double.eps),
  beta_relative_abs_estimate_change_pct = 100 * abs(
    beta_coefficients$estimate_log_odds - frozen_step5b_coefficients$estimate_log_odds
  ) / pmax(abs(frozen_step5b_coefficients$estimate_log_odds), .Machine$double.eps),
  beta_or_change_vs_binomial_pct = 100 * abs(
    beta_coefficients$odds_ratio / frozen_step5b_coefficients$odds_ratio - 1
  ),
  stringsAsFactors = FALSE
)
write_model_audit(coefficient_comparison, "step5c_coefficient_comparison.csv")

sign_label <- function(x) ifelse(x > 0, "positive", ifelse(x < 0, "negative", "zero"))
direction_stability <- coefficient_comparison |>
  dplyr::mutate(
    binomial_sign = sign_label(binomial_estimate),
    quasi_sign = sign_label(quasi_estimate),
    beta_sign = sign_label(beta_estimate),
    same_direction_all = binomial_sign == quasi_sign & quasi_sign == beta_sign,
    practical_stability = dplyr::case_when(
      !same_direction_all | beta_or_change_vs_binomial_pct > 25 ~ "Highly sensitive",
      beta_or_change_vs_binomial_pct > 10 ~ "Moderately sensitive",
      TRUE ~ "Stable"
    ),
    descriptive_rule = "Stable: same sign and beta-vs-binomial OR change <=10%; Moderate: same sign and >10%-25%; High: sign reversal or >25%"
  ) |>
  dplyr::select(
    term, binomial_sign, quasi_sign, beta_sign, same_direction_all,
    beta_or_change_vs_binomial_pct, practical_stability, descriptive_rule
  )
write_model_audit(direction_stability, "step5c_direction_stability.csv")

quasi_reference_probability <- as.numeric(stats::predict(
  quasi_fit, newdata = baseline_reference, type = "response"
))
beta_reference_probability <- as.numeric(stats::predict(
  beta_fit, newdata = baseline_reference, type = "response", re.form = NA
))
predicted_effect_comparison <- data.frame(
  scenario = names(effect_scenarios),
  binomial_probability = vapply(effect_scenarios, function(x) as.numeric(stats::predict(
    baseline_fit, newdata = x, type = "response"
  )), numeric(1)),
  quasi_probability = vapply(effect_scenarios, function(x) as.numeric(stats::predict(
    quasi_fit, newdata = x, type = "response"
  )), numeric(1)),
  beta_binomial_probability = vapply(effect_scenarios, function(x) as.numeric(stats::predict(
    beta_fit, newdata = x, type = "response", re.form = NA
  )), numeric(1)),
  stringsAsFactors = FALSE
) |>
  dplyr::mutate(
    quasi_minus_binomial = quasi_probability - binomial_probability,
    beta_minus_binomial = beta_binomial_probability - binomial_probability,
    beta_minus_quasi = beta_binomial_probability - quasi_probability
  )
write_model_audit(
  predicted_effect_comparison,
  "step5c_predicted_effect_comparison.csv"
)

step5c_fit_warning_rows <- list(
  data.frame(
    model = "Quasibinomial", population = "full",
    status = if (length(quasi_capture$warnings) == 0) "NO WARNING" else "WARNING",
    warning_text = if (length(quasi_capture$warnings) == 0) "" else paste(quasi_capture$warnings, collapse = " | "),
    stringsAsFactors = FALSE
  ),
  data.frame(
    model = "Beta-binomial", population = "full",
    status = if (length(beta_capture$warnings) == 0) "NO WARNING" else "WARNING",
    warning_text = if (length(beta_capture$warnings) == 0) "" else paste(beta_capture$warnings, collapse = " | "),
    stringsAsFactors = FALSE
  ),
  data.frame(
    model = "Beta-binomial profile CI", population = "full",
    status = if (is.null(beta_profile_ci_matrix)) "FAILED" else if (length(beta_profile_warnings) == 0) "NO WARNING" else "WARNING",
    warning_text = if (is.null(beta_profile_ci_matrix)) beta_profile_error else if (length(beta_profile_warnings) == 0) "" else paste(beta_profile_warnings, collapse = " | "),
    stringsAsFactors = FALSE
  )
)

message(sprintf(
  "Step 5C robust fits: PASS (quasi phi=%.3f, beta phi=%.3f, rho=%.4f, beta pdHess=%s)",
  quasi_dispersion, beta_dispersion_phi, beta_rho, beta_pd_hessian
))
