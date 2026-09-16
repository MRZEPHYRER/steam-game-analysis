# Fit the pre-specified Step 5E game-level high-rating logistic models.

if (!exists("model20_paid_complete")) {
  stop("Run 01_prepare_model_data.R before 10_high_rating_logistic.R.", call. = FALSE)
}

high_rating_genres <- c(
  "genre_action", "genre_adventure", "genre_casual", "genre_indie",
  "genre_rpg", "genre_simulation", "genre_strategy"
)
high_rating_platform_levels <- c(
  "Windows only", "Windows + macOS", "Windows + Linux",
  "Windows + macOS + Linux"
)
high_rating_predictors <- c(
  "z_log1p_price", "z_days_since_release", "platform_segment",
  high_rating_genres
)

frozen_scaling <- utils::read.csv(
  file.path(model_audit_dir, "step5b_scaling_parameters.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)
price_scaling <- frozen_scaling[frozen_scaling$predictor == "log1p_current_price", ]
days_scaling <- frozen_scaling[frozen_scaling$predictor == "days_since_release", ]
stopifnot(nrow(price_scaling) == 1, nrow(days_scaling) == 1)

frozen_price_mean <- price_scaling$scaling_mean[[1]]
frozen_price_sd <- price_scaling$scaling_sd[[1]]
frozen_days_mean <- days_scaling$scaling_mean[[1]]
frozen_days_sd <- days_scaling$scaling_sd[[1]]

high_rating_data <- model20_paid_complete |>
  dplyr::mutate(
    platform_segment = droplevels(factor(
      as.character(platform_segment), levels = high_rating_platform_levels
    )),
    computed_positive_rate = positive_reviews / total_reviews,
    z_log1p_price = (log1p_current_price - frozen_price_mean) / frozen_price_sd,
    z_days_since_release = (days_since_release - frozen_days_mean) / frozen_days_sd,
    high_rating_80 = as.integer(positive_reviews * 100 >= total_reviews * 80),
    high_rating_85 = as.integer(positive_reviews * 100 >= total_reviews * 85),
    high_rating_90 = as.integer(positive_reviews * 100 >= total_reviews * 90)
  )

stopifnot(
  nrow(high_rating_data) == 836,
  dplyr::n_distinct(high_rating_data$appid) == 836,
  !anyDuplicated(high_rating_data$appid),
  all(high_rating_data$is_free == 0),
  all(high_rating_data$total_reviews >= 20),
  all(high_rating_data$total_reviews > 0),
  all(high_rating_data$positive_reviews + high_rating_data$negative_reviews ==
    high_rating_data$total_reviews),
  isTRUE(all.equal(
    high_rating_data$computed_positive_rate,
    high_rating_data$positive_rate,
    tolerance = 1e-10
  )),
  isTRUE(all.equal(mean(high_rating_data$log1p_current_price), frozen_price_mean)),
  isTRUE(all.equal(stats::sd(high_rating_data$log1p_current_price), frozen_price_sd)),
  isTRUE(all.equal(mean(high_rating_data$days_since_release), frozen_days_mean)),
  isTRUE(all.equal(stats::sd(high_rating_data$days_since_release), frozen_days_sd)),
  identical(levels(high_rating_data$platform_segment), high_rating_platform_levels),
  all(vapply(
    high_rating_data[high_rating_genres],
    function(x) all(x %in% c(0L, 1L)),
    logical(1)
  ))
)

rating_thresholds <- data.frame(
  model_id = c("HIGH80", "HIGH85", "HIGH90"),
  rating_threshold = c(0.80, 0.85, 0.90),
  threshold_percent = c(80L, 85L, 90L),
  outcome_column = c("high_rating_80", "high_rating_85", "high_rating_90"),
  stringsAsFactors = FALSE
)

outcome_distribution <- dplyr::bind_rows(lapply(
  seq_len(nrow(rating_thresholds)),
  function(i) {
    threshold <- rating_thresholds[i, ]
    outcome <- high_rating_data[[threshold$outcome_column]]
    exact_boundary <- high_rating_data$positive_reviews * 100 ==
      high_rating_data$total_reviews * threshold$threshold_percent
    data.frame(
      model_id = threshold$model_id,
      rating_threshold = threshold$rating_threshold,
      comparator = ">=",
      n_total = length(outcome),
      high_rated_n = sum(outcome == 1L),
      high_rated_percent = mean(outcome == 1L) * 100,
      not_high_rated_n = sum(outcome == 0L),
      not_high_rated_percent = mean(outcome == 0L) * 100,
      exact_boundary_n = sum(exact_boundary),
      outcome_definition = "positive_reviews / total_reviews >= rating_threshold",
      stringsAsFactors = FALSE
    )
  }
))
write_model_audit(outcome_distribution, "step5e_outcome_distribution.csv")

step5e_sample_audit <- high_rating_data |>
  dplyr::select(
    appid, is_free, total_reviews, positive_reviews, negative_reviews,
    computed_positive_rate, current_price_usd, log1p_current_price,
    days_since_release, z_log1p_price, z_days_since_release,
    platform_segment, dplyr::all_of(high_rating_genres),
    high_rating_80, high_rating_85, high_rating_90
  ) |>
  dplyr::arrange(appid)
write_model_audit(step5e_sample_audit, "step5e_sample_audit.csv")

high_rating_formula <- stats::as.formula(paste(
  "high_rating ~",
  "z_log1p_price + z_days_since_release + platform_segment +",
  paste(high_rating_genres, collapse = " + ")
))
expected_high_rating_formula <- paste(
  "high_rating ~",
  "z_log1p_price + z_days_since_release + platform_segment +",
  paste(high_rating_genres, collapse = " + ")
)
stopifnot(identical(
  gsub("[[:space:]]+", " ", paste(deparse(high_rating_formula), collapse = " ")),
  expected_high_rating_formula
))

fit_one_high_rating <- function(model_id, threshold, outcome_column) {
  fit_data <- high_rating_data
  fit_data$high_rating <- fit_data[[outcome_column]]
  fit_warnings <- character()
  fit <- withCallingHandlers(
    stats::glm(
      formula = high_rating_formula,
      family = stats::binomial(link = "logit"),
      data = fit_data
    ),
    warning = function(w) {
      fit_warnings <<- c(fit_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  coef_matrix <- summary(fit)$coefficients
  wald_lower <- coef_matrix[, "Estimate"] - stats::qnorm(0.975) * coef_matrix[, "Std. Error"]
  wald_upper <- coef_matrix[, "Estimate"] + stats::qnorm(0.975) * coef_matrix[, "Std. Error"]
  coefficients <- data.frame(
    model_id = model_id,
    rating_threshold = threshold,
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
    direction = ifelse(coef_matrix[, "Estimate"] > 0, "POSITIVE", "NEGATIVE"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  model_matrix <- stats::model.matrix(fit)
  outcome <- stats::model.response(stats::model.frame(fit))
  fit_summary <- data.frame(
    model_id = model_id,
    rating_threshold = threshold,
    n_games = stats::nobs(fit),
    event_n = sum(outcome == 1L),
    non_event_n = sum(outcome == 0L),
    event_rate = mean(outcome == 1L),
    number_of_coefficients = length(stats::coef(fit)),
    residual_df = stats::df.residual(fit),
    matrix_columns = ncol(model_matrix),
    matrix_rank = qr(model_matrix)$rank,
    converged = isTRUE(fit$converged),
    iterations = fit$iter,
    log_likelihood = as.numeric(stats::logLik(fit)),
    aic = stats::AIC(fit),
    bic = stats::BIC(fit),
    null_deviance = fit$null.deviance,
    residual_deviance = fit$deviance,
    warning_count = length(unique(fit_warnings)),
    weights_used = FALSE,
    all_prior_weights_one = all(fit$prior.weights == 1),
    review_count_covariate_included = FALSE,
    formula = expected_high_rating_formula,
    stringsAsFactors = FALSE
  )
  list(
    fit = fit,
    data = fit_data,
    coefficients = coefficients,
    fit_summary = fit_summary,
    warnings = unique(fit_warnings)
  )
}

high_rating_fits <- setNames(lapply(
  seq_len(nrow(rating_thresholds)),
  function(i) fit_one_high_rating(
    rating_thresholds$model_id[[i]],
    rating_thresholds$rating_threshold[[i]],
    rating_thresholds$outcome_column[[i]]
  )
), rating_thresholds$model_id)

rating_threshold_fit <- dplyr::bind_rows(lapply(
  high_rating_fits, function(x) x$fit_summary
))
rating_threshold_coefficients <- dplyr::bind_rows(lapply(
  high_rating_fits, function(x) x$coefficients
))
primary_high_rating_fit <- high_rating_fits$HIGH85$fit
primary_high_rating_data <- high_rating_fits$HIGH85$data
primary_high_rating_fit_summary <- high_rating_fits$HIGH85$fit_summary
primary_high_rating_coefficients <- high_rating_fits$HIGH85$coefficients

stopifnot(
  all(rating_threshold_fit$n_games == 836),
  all(rating_threshold_fit$converged),
  all(rating_threshold_fit$matrix_rank == rating_threshold_fit$matrix_columns),
  all(!rating_threshold_fit$weights_used),
  all(rating_threshold_fit$all_prior_weights_one),
  all(!rating_threshold_fit$review_count_covariate_included),
  all(vapply(high_rating_fits, function(x) {
    identical(as.integer(x$data$appid), as.integer(high_rating_data$appid))
  }, logical(1)))
)

write_model_audit(primary_high_rating_fit_summary, "step5e_primary_fit.csv")
write_model_audit(primary_high_rating_coefficients, "step5e_primary_coefficients.csv")
write_model_audit(rating_threshold_fit, "step5e_rating_threshold_fit.csv")
write_model_audit(
  rating_threshold_coefficients,
  "step5e_rating_threshold_coefficients.csv"
)

profile_warnings <- character()
profile_error <- ""
profile_ci_matrix <- tryCatch(
  withCallingHandlers(
    suppressMessages(stats::confint(primary_high_rating_fit, level = 0.95)),
    warning = function(w) {
      profile_warnings <<- c(profile_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  ),
  error = function(e) {
    profile_error <<- conditionMessage(e)
    NULL
  }
)
if (is.null(profile_ci_matrix)) {
  primary_profile_ci <- data.frame(
    term = primary_high_rating_coefficients$term,
    profile_ci95_logit_lower = NA_real_,
    profile_ci95_logit_upper = NA_real_,
    profile_or_ci95_lower = NA_real_,
    profile_or_ci95_upper = NA_real_,
    status = "FAILED",
    failure_reason = profile_error,
    stringsAsFactors = FALSE
  )
} else {
  primary_profile_ci <- data.frame(
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
write_model_audit(primary_profile_ci, "step5e_primary_profile_ci.csv")

reference_scenario <- data.frame(
  z_log1p_price = 0,
  z_days_since_release = 0,
  platform_segment = factor("Windows only", levels = high_rating_platform_levels),
  genre_action = 0L,
  genre_adventure = 0L,
  genre_casual = 0L,
  genre_indie = 0L,
  genre_rpg = 0L,
  genre_simulation = 0L,
  genre_strategy = 0L
)
probability_scenarios <- list(
  "REFERENCE" = reference_scenario,
  "PRICE_PLUS_1SD" = transform(reference_scenario, z_log1p_price = 1),
  "DAYS_PLUS_1SD" = transform(reference_scenario, z_days_since_release = 1),
  "PLATFORM_WINDOWS_MACOS" = transform(
    reference_scenario,
    platform_segment = factor("Windows + macOS", levels = high_rating_platform_levels)
  ),
  "PLATFORM_WINDOWS_LINUX" = transform(
    reference_scenario,
    platform_segment = factor("Windows + Linux", levels = high_rating_platform_levels)
  ),
  "PLATFORM_ALL_THREE" = transform(
    reference_scenario,
    platform_segment = factor(
      "Windows + macOS + Linux", levels = high_rating_platform_levels
    )
  )
)
for (genre in high_rating_genres) {
  scenario <- reference_scenario
  scenario[[genre]] <- 1L
  probability_scenarios[[toupper(genre)]] <- scenario
}
reference_probability <- as.numeric(stats::predict(
  primary_high_rating_fit, newdata = reference_scenario, type = "response"
))
predicted_probability_contrasts <- data.frame(
  scenario = names(probability_scenarios),
  reference_probability = reference_probability,
  modified_probability = vapply(
    probability_scenarios,
    function(newdata) as.numeric(stats::predict(
      primary_high_rating_fit, newdata = newdata, type = "response"
    )),
    numeric(1)
  ),
  stringsAsFactors = FALSE
) |>
  dplyr::mutate(
    absolute_probability_point_change = modified_probability - reference_probability,
    percentage_point_change = 100 * absolute_probability_point_change,
    interpretation = "Model-based predicted probability contrast; not a causal effect"
  )
write_model_audit(
  predicted_probability_contrasts,
  "step5e_predicted_probability_contrasts.csv"
)

rating_threshold_stability <- rating_threshold_coefficients |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::select(
    model_id, rating_threshold, term, odds_ratio, or_ci95_lower,
    or_ci95_upper, direction
  ) |>
  tidyr::pivot_wider(
    names_from = model_id,
    values_from = c(
      rating_threshold, odds_ratio, or_ci95_lower, or_ci95_upper, direction
    ),
    names_glue = "{.value}_{model_id}"
  ) |>
  dplyr::mutate(
    direction_agreement = direction_HIGH80 == direction_HIGH85 &
      direction_HIGH85 == direction_HIGH90,
    max_or_drift_from_high85 = pmax(
      abs(odds_ratio_HIGH80 / odds_ratio_HIGH85 - 1),
      abs(odds_ratio_HIGH90 / odds_ratio_HIGH85 - 1)
    ),
    stability_class = dplyr::case_when(
      !direction_agreement | max_or_drift_from_high85 > 0.25 ~ "SENSITIVE",
      max_or_drift_from_high85 > 0.10 ~ "PARTIAL",
      TRUE ~ "ROBUST"
    ),
    classification_note = paste(
      "Descriptive audit only; drift is the maximum absolute relative OR",
      "change from the pre-specified HIGH85 model"
    )
  )
write_model_audit(
  rating_threshold_stability,
  "step5e_rating_threshold_stability.csv"
)

beta_primary <- utils::read.csv(
  file.path(model_audit_dir, "step5c_beta_binomial_coefficients.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE
) |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::select(
    term,
    beta_binomial_estimate_log_odds = estimate_log_odds,
    beta_binomial_odds_ratio = odds_ratio
  )
beta_logistic_direction_comparison <- beta_primary |>
  dplyr::inner_join(
    primary_high_rating_coefficients |>
      dplyr::filter(term != "(Intercept)") |>
      dplyr::select(
        term,
        high85_logistic_estimate_log_odds = estimate_log_odds,
        high85_logistic_odds_ratio = odds_ratio
      ),
    by = "term"
  ) |>
  dplyr::mutate(
    beta_binomial_direction = ifelse(
      beta_binomial_estimate_log_odds > 0, "POSITIVE", "NEGATIVE"
    ),
    high85_logistic_direction = ifelse(
      high85_logistic_estimate_log_odds > 0, "POSITIVE", "NEGATIVE"
    ),
    direction_agreement = beta_binomial_direction == high85_logistic_direction,
    comparison_scope = paste(
      "Direction and qualitative consistency only; outcomes differ and OR",
      "magnitudes are not directly comparable"
    )
  )
write_model_audit(
  beta_logistic_direction_comparison,
  "step5e_beta_logistic_direction_comparison.csv"
)

warning_rows <- list()
for (model_id in names(high_rating_fits)) {
  warnings <- high_rating_fits[[model_id]]$warnings
  warning_rows[[length(warning_rows) + 1L]] <- data.frame(
    stage = paste(model_id, "glm fit"),
    status = if (length(warnings) == 0) "NO WARNING" else "WARNING",
    warning_text = if (length(warnings) == 0) "" else paste(warnings, collapse = " | "),
    stringsAsFactors = FALSE
  )
}
warning_rows[[length(warning_rows) + 1L]] <- data.frame(
  stage = "HIGH85 profile likelihood CI",
  status = if (is.null(profile_ci_matrix)) "FAILED" else if (
    length(profile_warnings) > 0
  ) "WARNING" else "NO WARNING",
  warning_text = if (is.null(profile_ci_matrix)) profile_error else paste(
    profile_warnings, collapse = " | "
  ),
  stringsAsFactors = FALSE
)
high_rating_fit_warnings <- dplyr::bind_rows(warning_rows)
write_model_audit(high_rating_fit_warnings, "step5e_fit_warnings.csv")

database_counts_before_5e <- vapply(
  loaded_model_data$counts_before, function(x) as.numeric(x[[1]]), numeric(1)
)
database_counts_after_5e <- vapply(
  loaded_model_data$counts_after, function(x) as.numeric(x[[1]]), numeric(1)
)
step5e_database_preservation <- data.frame(
  object = names(database_counts_before_5e),
  before = database_counts_before_5e,
  after = database_counts_after_5e,
  unchanged = database_counts_before_5e == database_counts_after_5e,
  stringsAsFactors = FALSE
)
stopifnot(all(step5e_database_preservation$unchanged))
write_model_audit(
  step5e_database_preservation,
  "step5e_database_preservation.csv"
)

message(sprintf(
  "Step 5E logistic fits: PASS (N=%d; events 80/85/90=%s)",
  nrow(high_rating_data), paste(rating_threshold_fit$event_n, collapse = "/")
))
