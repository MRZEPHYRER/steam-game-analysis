# Fit the frozen Step 5B grouped-binomial baseline model.

if (!exists("model20_paid_complete")) {
  stop("Run 01_prepare_model_data.R before 04_baseline_binomial.R.", call. = FALSE)
}

baseline_genres <- c(
  "genre_action", "genre_adventure", "genre_casual", "genre_indie",
  "genre_rpg", "genre_simulation", "genre_strategy"
)
baseline_platform_levels <- c(
  "Windows only", "Windows + macOS", "Windows + Linux",
  "Windows + macOS + Linux"
)

model20_paid_baseline <- model20_paid_complete |>
  dplyr::mutate(
    platform_segment = droplevels(factor(
      as.character(platform_segment), levels = baseline_platform_levels
    ))
  )

stopifnot(
  nrow(model20_paid_baseline) == 836,
  dplyr::n_distinct(model20_paid_baseline$appid) == 836,
  !anyDuplicated(model20_paid_baseline$appid),
  all(model20_paid_baseline$positive_reviews >= 0),
  all(model20_paid_baseline$negative_reviews >= 0),
  all(
    model20_paid_baseline$positive_reviews +
      model20_paid_baseline$negative_reviews ==
      model20_paid_baseline$total_reviews
  ),
  all(!is.na(model20_paid_baseline$current_price_usd)),
  all(model20_paid_baseline$days_since_release > 0),
  identical(levels(model20_paid_baseline$platform_segment), baseline_platform_levels),
  all(vapply(
    model20_paid_baseline[baseline_genres],
    function(x) all(x %in% c(0L, 1L)),
    logical(1)
  ))
)

price_log_mean <- mean(model20_paid_baseline$log1p_current_price)
price_log_sd <- stats::sd(model20_paid_baseline$log1p_current_price)
days_mean <- mean(model20_paid_baseline$days_since_release)
days_sd <- stats::sd(model20_paid_baseline$days_since_release)
stopifnot(
  is.finite(price_log_mean), is.finite(price_log_sd), price_log_sd > 0,
  is.finite(days_mean), is.finite(days_sd), days_sd > 0
)

model20_paid_baseline <- model20_paid_baseline |>
  dplyr::mutate(
    z_log1p_price = (log1p_current_price - price_log_mean) / price_log_sd,
    z_days_since_release = (days_since_release - days_mean) / days_sd
  )

scaling_parameters <- data.frame(
  predictor = c("log1p_current_price", "days_since_release"),
  scaling_mean = c(price_log_mean, days_mean),
  scaling_sd = c(price_log_sd, days_sd),
  minus_1sd_original = c(expm1(price_log_mean - price_log_sd), days_mean - days_sd),
  mean_original = c(expm1(price_log_mean), days_mean),
  plus_1sd_original = c(expm1(price_log_mean + price_log_sd), days_mean + days_sd),
  original_unit = c("USD (back-transformed from log1p)", "days"),
  stringsAsFactors = FALSE
)
write_model_audit(scaling_parameters, "step5b_scaling_parameters.csv")

frozen_baseline_formula <- stats::as.formula(
  paste(
    "cbind(positive_reviews, negative_reviews) ~",
    "z_log1p_price + z_days_since_release + platform_segment +",
    paste(baseline_genres, collapse = " + ")
  )
)
expected_formula_text <- paste(
  "cbind(positive_reviews, negative_reviews) ~",
  "z_log1p_price + z_days_since_release + platform_segment +",
  paste(baseline_genres, collapse = " + ")
)
normalized_formula_text <- gsub(
  "[[:space:]]+", " ", paste(deparse(frozen_baseline_formula), collapse = " ")
)
stopifnot(identical(normalized_formula_text, expected_formula_text))

baseline_matrix <- stats::model.matrix(frozen_baseline_formula, model20_paid_baseline)
baseline_qr <- qr(baseline_matrix)
baseline_matrix_diagnostics <- data.frame(
  matrix_rows = nrow(baseline_matrix),
  matrix_columns = ncol(baseline_matrix),
  matrix_rank = baseline_qr$rank,
  condition_number = kappa(baseline_matrix),
  exact_dependencies = ncol(baseline_matrix) - baseline_qr$rank,
  formula = expected_formula_text,
  response = "cbind(positive_reviews, negative_reviews)",
  family = "binomial(link = logit)",
  platform_reference = levels(model20_paid_baseline$platform_segment)[1],
  genre_reference = "absent (0)",
  stringsAsFactors = FALSE
)
write_model_audit(baseline_matrix_diagnostics, "step5b_matrix_diagnostics.csv")

fit_warnings <- character()
baseline_fit <- withCallingHandlers(
  stats::glm(
    formula = frozen_baseline_formula,
    family = stats::binomial(link = "logit"),
    data = model20_paid_baseline
  ),
  warning = function(w) {
    fit_warnings <<- c(fit_warnings, conditionMessage(w))
  }
)

baseline_summary <- summary(baseline_fit)
coef_matrix <- baseline_summary$coefficients
wald_lower <- coef_matrix[, "Estimate"] - stats::qnorm(0.975) * coef_matrix[, "Std. Error"]
wald_upper <- coef_matrix[, "Estimate"] + stats::qnorm(0.975) * coef_matrix[, "Std. Error"]
coefficient_table <- data.frame(
  term = rownames(coef_matrix),
  estimate_log_odds = coef_matrix[, "Estimate"],
  std_error = coef_matrix[, "Std. Error"],
  z_value = coef_matrix[, "z value"],
  p_value = coef_matrix[, "Pr(>|z|)"],
  ci95_logit_lower = wald_lower,
  ci95_logit_upper = wald_upper,
  odds_ratio = exp(coef_matrix[, "Estimate"]),
  or_ci95_lower = exp(wald_lower),
  or_ci95_upper = exp(wald_upper),
  stringsAsFactors = FALSE,
  row.names = NULL
)
write_model_audit(coefficient_table, "step5b_coefficients.csv")

profile_warnings <- character()
profile_error <- ""
profile_ci_matrix <- tryCatch(
  withCallingHandlers(
    stats::confint(baseline_fit, level = 0.95),
    warning = function(w) {
      profile_warnings <<- c(profile_warnings, conditionMessage(w))
    }
  ),
  error = function(e) {
    profile_error <<- conditionMessage(e)
    NULL
  }
)
if (is.null(profile_ci_matrix)) {
  profile_ci <- data.frame(
    term = rownames(coef_matrix),
    profile_ci95_logit_lower = NA_real_,
    profile_ci95_logit_upper = NA_real_,
    profile_or_ci95_lower = NA_real_,
    profile_or_ci95_upper = NA_real_,
    status = "FAILED",
    failure_reason = profile_error,
    stringsAsFactors = FALSE
  )
} else {
  profile_ci <- data.frame(
    term = rownames(profile_ci_matrix),
    profile_ci95_logit_lower = profile_ci_matrix[, 1],
    profile_ci95_logit_upper = profile_ci_matrix[, 2],
    profile_or_ci95_lower = exp(profile_ci_matrix[, 1]),
    profile_or_ci95_upper = exp(profile_ci_matrix[, 2]),
    status = "PASS",
    failure_reason = "",
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
write_model_audit(profile_ci, "step5b_profile_ci.csv")

baseline_reference <- data.frame(
  z_log1p_price = 0,
  z_days_since_release = 0,
  platform_segment = factor("Windows only", levels = baseline_platform_levels),
  genre_action = 0L,
  genre_adventure = 0L,
  genre_casual = 0L,
  genre_indie = 0L,
  genre_rpg = 0L,
  genre_simulation = 0L,
  genre_strategy = 0L
)
effect_scenarios <- list(
  "Baseline: means, Windows only, genres absent" = baseline_reference,
  "+1 SD log1p price" = transform(baseline_reference, z_log1p_price = 1),
  "+1 SD days since release" = transform(baseline_reference, z_days_since_release = 1),
  "Platform: Windows + macOS" = transform(
    baseline_reference,
    platform_segment = factor("Windows + macOS", levels = baseline_platform_levels)
  ),
  "Platform: Windows + Linux" = transform(
    baseline_reference,
    platform_segment = factor("Windows + Linux", levels = baseline_platform_levels)
  ),
  "Platform: Windows + macOS + Linux" = transform(
    baseline_reference,
    platform_segment = factor("Windows + macOS + Linux", levels = baseline_platform_levels)
  )
)
for (genre in baseline_genres) {
  scenario <- baseline_reference
  scenario[[genre]] <- 1L
  effect_scenarios[[paste0("Genre present: ", sub("genre_", "", genre))]] <- scenario
}
baseline_probability <- as.numeric(stats::predict(
  baseline_fit, newdata = baseline_reference, type = "response"
))
predicted_effects <- data.frame(
  scenario = names(effect_scenarios),
  predicted_probability = vapply(
    effect_scenarios,
    function(newdata) as.numeric(stats::predict(
      baseline_fit, newdata = newdata, type = "response"
    )),
    numeric(1)
  ),
  stringsAsFactors = FALSE
) |>
  dplyr::mutate(
    absolute_probability_difference = predicted_probability - baseline_probability,
    interpretation = "Descriptive model contrast; not a causal effect"
  )
write_model_audit(predicted_effects, "step5b_predicted_effects.csv")

total_positive <- sum(model20_paid_baseline$positive_reviews)
total_negative <- sum(model20_paid_baseline$negative_reviews)
total_trials <- sum(model20_paid_baseline$total_reviews)
model_fit_summary <- data.frame(
  n_games = nrow(model20_paid_baseline),
  unique_appids = dplyr::n_distinct(model20_paid_baseline$appid),
  response_trials = total_trials,
  total_positive_reviews = total_positive,
  total_negative_reviews = total_negative,
  pooled_positive_rate = total_positive / total_trials,
  number_of_coefficients = length(stats::coef(baseline_fit)),
  residual_df = stats::df.residual(baseline_fit),
  log_likelihood = as.numeric(stats::logLik(baseline_fit)),
  deviance = stats::deviance(baseline_fit),
  null_deviance = baseline_fit$null.deviance,
  residual_deviance = baseline_fit$deviance,
  aic = stats::AIC(baseline_fit),
  bic = stats::BIC(baseline_fit),
  converged = isTRUE(baseline_fit$converged),
  iterations = baseline_fit$iter,
  fit_warning_count = length(fit_warnings),
  profile_ci_status = if (is.null(profile_ci_matrix)) "FAILED" else "PASS",
  formula = expected_formula_text,
  stringsAsFactors = FALSE
)
write_model_audit(model_fit_summary, "step5b_model_fit_summary.csv")

database_counts_before <- vapply(
  loaded_model_data$counts_before,
  function(x) as.numeric(x[[1]]),
  numeric(1)
)
database_counts_after <- vapply(
  loaded_model_data$counts_after,
  function(x) as.numeric(x[[1]]),
  numeric(1)
)
database_preservation <- data.frame(
  object = names(loaded_model_data$counts_before),
  before = database_counts_before,
  after = database_counts_after,
  unchanged = database_counts_before == database_counts_after,
  stringsAsFactors = FALSE
)
stopifnot(all(database_preservation$unchanged))
write_model_audit(database_preservation, "step5b_database_preservation.csv")

message(sprintf(
  "Step 5B baseline fit: PASS (N=%d, coefficients=%d, converged=%s)",
  nrow(model20_paid_baseline), length(stats::coef(baseline_fit)),
  baseline_fit$converged
))
