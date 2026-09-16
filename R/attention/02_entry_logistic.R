# Step 6A primary review-entry logistic model and pre-specified sensitivities.

if (!exists("market_model_data_6a")) {
  stop("Run 01_attention_data_audit.R before 02_entry_logistic.R.", call. = FALSE)
}

primary_formula_6a <- stats::as.formula(paste(
  "has_review ~ is_free + z_log1p_paid_price_component + z_days_since_release +",
  "platform_segment +",
  paste(attention_primary_genres, collapse = " + ")
))
primary_result_6a <- fit_glm_with_warnings_6a(primary_formula_6a, market_model_data_6a)
primary_entry_fit_6a <- primary_result_6a$fit
primary_entry_warnings_6a <- primary_result_6a$warnings
primary_fit_6a <- fit_summary_6a(
  primary_entry_fit_6a, "PRIMARY_LINEAR",
  length(primary_entry_warnings_6a)
)
primary_coefficients_6a <- tidy_logistic_6a(primary_entry_fit_6a, "PRIMARY_LINEAR")

if (!isTRUE(primary_entry_fit_6a$converged) ||
    primary_fit_6a$matrix_rank != primary_fit_6a$matrix_columns ||
    length(primary_entry_warnings_6a) > 0L) {
  stop("Step 6A primary logistic model did not converge cleanly.", call. = FALSE)
}

profile_warnings_6a <- character()
profile_error_6a <- ""
profile_matrix_6a <- tryCatch(
  withCallingHandlers(
    suppressMessages(stats::confint(primary_entry_fit_6a)),
    warning = function(w) {
      profile_warnings_6a <<- c(profile_warnings_6a, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  ),
  error = function(e) {
    profile_error_6a <<- conditionMessage(e)
    NULL
  }
)
if (is.null(profile_matrix_6a)) {
  primary_profile_ci_6a <- primary_coefficients_6a |>
    dplyr::transmute(
      term, profile_ci95_logit_lower = NA_real_, profile_ci95_logit_upper = NA_real_,
      profile_or_ci95_lower = NA_real_, profile_or_ci95_upper = NA_real_,
      status = "FAILED", failure_reason = profile_error_6a
    )
} else {
  primary_profile_ci_6a <- data.frame(
    term = rownames(profile_matrix_6a),
    profile_ci95_logit_lower = profile_matrix_6a[, 1],
    profile_ci95_logit_upper = profile_matrix_6a[, 2],
    profile_or_ci95_lower = exp(profile_matrix_6a[, 1]),
    profile_or_ci95_upper = exp(profile_matrix_6a[, 2]),
    status = if (length(profile_warnings_6a) == 0L) "PASS" else "PASS_WITH_WARNING",
    failure_reason = if (length(profile_warnings_6a) == 0L) "" else paste(unique(profile_warnings_6a), collapse = " | "),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

summarise_binary_cell_6a <- function(variable, predictor_label) {
  market_model_data_6a |>
    dplyr::mutate(level = ifelse(.data[[variable]] == 1L, "present", "absent")) |>
    dplyr::group_by(level) |>
    dplyr::summarise(
      n_games = dplyr::n(), has_review_n = sum(has_review),
      zero_review_n = sum(has_review == 0L),
      has_review_rate = mean(has_review), has_review_percent = 100 * mean(has_review),
      .groups = "drop"
    ) |>
    dplyr::mutate(predictor = predictor_label, .before = 1)
}
free_cells_6a <- market_model_data_6a |>
  dplyr::mutate(level = ifelse(is_free == 1L, "Free", "Paid")) |>
  dplyr::group_by(level) |>
  dplyr::summarise(
    n_games = dplyr::n(), has_review_n = sum(has_review),
    zero_review_n = sum(has_review == 0L),
    has_review_rate = mean(has_review), has_review_percent = 100 * mean(has_review),
    .groups = "drop"
  ) |>
  dplyr::mutate(predictor = "is_free", .before = 1)
platform_cells_6a <- market_model_data_6a |>
  dplyr::mutate(level = as.character(platform_segment)) |>
  dplyr::group_by(level) |>
  dplyr::summarise(
    n_games = dplyr::n(), has_review_n = sum(has_review),
    zero_review_n = sum(has_review == 0L),
    has_review_rate = mean(has_review), has_review_percent = 100 * mean(has_review),
    .groups = "drop"
  ) |>
  dplyr::mutate(predictor = "platform_segment", .before = 1)
genre_cells_6a <- dplyr::bind_rows(lapply(
  attention_primary_genres,
  function(variable) summarise_binary_cell_6a(variable, variable)
))
outcome_cells_6a <- dplyr::bind_rows(free_cells_6a, platform_cells_6a, genre_cells_6a) |>
  dplyr::mutate(
    zero_event_cell = has_review_n == 0L,
    zero_non_event_cell = zero_review_n == 0L,
    cell_n_below_10 = n_games < 10L
  )

primary_fitted_6a <- stats::fitted(primary_entry_fit_6a)
large_terms_6a <- primary_coefficients_6a |>
  dplyr::filter(abs(estimate_log_odds) > 10 | std_error > 10)
separation_diagnostics_6a <- data.frame(
  check = c(
    "glm_not_converged", "rank_deficient_model_matrix",
    "absolute_coefficient_gt_10_or_se_gt_10",
    "fitted_probability_below_1e_6", "fitted_probability_above_1_minus_1e_6",
    "categorical_zero_event_cell", "categorical_zero_non_event_cell", "glm_warning"
  ),
  n_flagged = c(
    as.integer(!primary_entry_fit_6a$converged),
    as.integer(primary_fit_6a$matrix_rank != primary_fit_6a$matrix_columns),
    nrow(large_terms_6a), sum(primary_fitted_6a < 1e-6),
    sum(primary_fitted_6a > 1 - 1e-6),
    sum(outcome_cells_6a$zero_event_cell), sum(outcome_cells_6a$zero_non_event_cell),
    length(primary_entry_warnings_6a)
  ),
  details = c(
    paste("converged =", primary_entry_fit_6a$converged),
    paste("rank =", primary_fit_6a$matrix_rank, "of", primary_fit_6a$matrix_columns),
    if (nrow(large_terms_6a) == 0L) "none" else paste(large_terms_6a$term, collapse = "; "),
    "Complete/quasi-separation heuristic", "Complete/quasi-separation heuristic",
    "Raw categorical outcome cells", "Raw categorical outcome cells",
    paste("warning count =", length(primary_entry_warnings_6a))
  ),
  stringsAsFactors = FALSE
)

reference_6a <- market_model_data_6a[1, , drop = FALSE]
reference_6a$is_free <- 0L
reference_6a$z_log1p_paid_price_component <- 0
reference_6a$z_days_since_release <- 0
reference_6a$platform_segment <- factor(
  "Windows only", levels = levels(market_model_data_6a$platform_segment)
)
for (genre in attention_primary_genres) reference_6a[[genre]] <- 0L
scenario_rows_6a <- list(REFERENCE = reference_6a)
free_scenario_6a <- reference_6a
free_scenario_6a$is_free <- 1L
scenario_rows_6a$FREE_VS_PAID <- free_scenario_6a
price_scenario_6a <- reference_6a
price_scenario_6a$z_log1p_paid_price_component <- 1
scenario_rows_6a$PAID_PRICE_PLUS_1_SD <- price_scenario_6a
days_scenario_6a <- reference_6a
days_scenario_6a$z_days_since_release <- 1
scenario_rows_6a$DAYS_PLUS_1_SD <- days_scenario_6a
for (platform in levels(market_model_data_6a$platform_segment)[-1]) {
  row <- reference_6a
  row$platform_segment <- factor(platform, levels = levels(market_model_data_6a$platform_segment))
  scenario_rows_6a[[paste0("PLATFORM_", gsub("[^A-Za-z]+", "_", toupper(platform)))]] <- row
}
for (genre in attention_primary_genres) {
  row <- reference_6a
  row[[genre]] <- 1L
  scenario_rows_6a[[toupper(genre)]] <- row
}
reference_probability_6a <- as.numeric(stats::predict(
  primary_entry_fit_6a, newdata = reference_6a, type = "response"
))
probability_contrasts_6a <- dplyr::bind_rows(lapply(names(scenario_rows_6a), function(id) {
  probability <- as.numeric(stats::predict(
    primary_entry_fit_6a, newdata = scenario_rows_6a[[id]], type = "response"
  ))
  data.frame(
    scenario = id,
    reference_probability = reference_probability_6a,
    modified_probability = probability,
    probability_point_difference = probability - reference_probability_6a,
    percentage_point_difference = 100 * (probability - reference_probability_6a),
    interpretation_scope = if (id == "PAID_PRICE_PLUS_1_SD")
      "Paid games only price gradient" else "One-at-a-time conditional contrast",
    stringsAsFactors = FALSE
  )
}))

release_formula_6a <- stats::as.formula(paste(
  "has_review ~ is_free + z_log1p_paid_price_component + release_month + platform_segment +",
  paste(attention_primary_genres, collapse = " + ")
))
release_result_6a <- fit_glm_with_warnings_6a(release_formula_6a, market_model_data_6a)
release_entry_fit_6a <- release_result_6a$fit
release_warnings_6a <- release_result_6a$warnings
release_sensitivity_6a <- dplyr::bind_rows(
  primary_coefficients_6a,
  tidy_logistic_6a(release_entry_fit_6a, "RELEASE_MONTH_ALTERNATIVE")
)

expanded_formula_6a <- stats::as.formula(paste(
  "has_review ~ is_free + z_log1p_paid_price_component + z_days_since_release + platform_segment +",
  paste(c(attention_primary_genres, attention_expanded_genres), collapse = " + ")
))
expanded_result_6a <- fit_glm_with_warnings_6a(expanded_formula_6a, market_model_data_6a)
expanded_genre_fit_6a <- expanded_result_6a$fit
expanded_warnings_6a <- expanded_result_6a$warnings
genre_sensitivity_6a <- dplyr::bind_rows(
  primary_coefficients_6a,
  tidy_logistic_6a(expanded_genre_fit_6a, "EXPANDED_GENRES")
)
sensitivity_fit_summary_6a <- dplyr::bind_rows(
  primary_fit_6a,
  fit_summary_6a(release_entry_fit_6a, "RELEASE_MONTH_ALTERNATIVE", length(release_warnings_6a)),
  fit_summary_6a(expanded_genre_fit_6a, "EXPANDED_GENRES", length(expanded_warnings_6a))
)
if (any(!sensitivity_fit_summary_6a$converged) || any(sensitivity_fit_summary_6a$warning_count > 0L)) {
  stop("Step 6A pre-specified sensitivity model did not converge cleanly.", call. = FALSE)
}

write_attention_audit(primary_fit_6a, "step6a_primary_fit.csv")
write_attention_audit(primary_coefficients_6a, "step6a_primary_coefficients.csv")
write_attention_audit(primary_profile_ci_6a, "step6a_primary_profile_ci.csv")
write_attention_audit(outcome_cells_6a, "step6a_outcome_cells.csv")
write_attention_audit(separation_diagnostics_6a, "step6a_separation_diagnostics.csv")
write_attention_audit(probability_contrasts_6a, "step6a_probability_contrasts.csv")
write_attention_audit(release_sensitivity_6a, "step6a_release_sensitivity.csv")
write_attention_audit(genre_sensitivity_6a, "step6a_genre_sensitivity.csv")
write_attention_audit(sensitivity_fit_summary_6a, "step6a_sensitivity_fit_summary.csv")

message("Step 6A primary logistic and sensitivities: PASS")
