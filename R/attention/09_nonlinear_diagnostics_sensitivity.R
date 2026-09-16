# Step 6A.1 diagnostics, sensitivities, df=4 audit, and optional GAM diagnostic.

if (!exists("nonlinear_entry_fit_6a1") || !exists("price_curve_6a1")) {
  stop("Run 08_nonlinear_entry_model.R before diagnostics.", call. = FALSE)
}

nonlinear_fitted_6a1 <- stats::fitted(nonlinear_entry_fit_6a1)
nonlinear_deviance_6a1 <- stats::residuals(nonlinear_entry_fit_6a1, type = "deviance")
nonlinear_std_deviance_6a1 <- stats::rstandard(nonlinear_entry_fit_6a1, type = "deviance")
nonlinear_leverage_6a1 <- stats::hatvalues(nonlinear_entry_fit_6a1)
nonlinear_cooks_6a1 <- stats::cooks.distance(nonlinear_entry_fit_6a1)
n_6a1 <- nrow(market_model_data_6a1)
p_6a1 <- length(stats::coef(nonlinear_entry_fit_6a1))
diagnostic_defined_6a1 <- is.finite(nonlinear_std_deviance_6a1) & is.finite(nonlinear_cooks_6a1)

if (any(!is.finite(nonlinear_fitted_6a1)) || any(!is.finite(nonlinear_leverage_6a1))) {
  stop("Non-finite Step 6A.1 fitted probabilities or leverage.", call. = FALSE)
}
nonlinear_std_deviance_6a1[!is.finite(nonlinear_std_deviance_6a1)] <- NA_real_
nonlinear_cooks_6a1[!is.finite(nonlinear_cooks_6a1)] <- NA_real_

nonlinear_influence_summary_6a1 <- data.frame(
  n_games = n_6a1,
  parameter_count = p_6a1,
  n_influence_diagnostics_not_defined = sum(!diagnostic_defined_6a1),
  max_absolute_deviance_residual = max(abs(nonlinear_deviance_6a1)),
  max_absolute_standardized_deviance_residual = max(abs(nonlinear_std_deviance_6a1), na.rm = TRUE),
  n_absolute_standardized_residual_gt_2 = sum(abs(nonlinear_std_deviance_6a1) > 2, na.rm = TRUE),
  n_absolute_standardized_residual_gt_3 = sum(abs(nonlinear_std_deviance_6a1) > 3, na.rm = TRUE),
  max_leverage = max(nonlinear_leverage_6a1),
  threshold_2p_over_n = 2 * p_6a1 / n_6a1,
  n_leverage_above_2p_over_n = sum(nonlinear_leverage_6a1 > 2 * p_6a1 / n_6a1),
  threshold_3p_over_n = 3 * p_6a1 / n_6a1,
  n_leverage_above_3p_over_n = sum(nonlinear_leverage_6a1 > 3 * p_6a1 / n_6a1),
  max_cooks_distance = max(nonlinear_cooks_6a1, na.rm = TRUE),
  threshold_4_over_n = 4 / n_6a1,
  n_cooks_above_4_over_n = sum(nonlinear_cooks_6a1 > 4 / n_6a1, na.rm = TRUE),
  n_cooks_above_0_5 = sum(nonlinear_cooks_6a1 > 0.5, na.rm = TRUE),
  n_cooks_above_1 = sum(nonlinear_cooks_6a1 > 1, na.rm = TRUE),
  stringsAsFactors = FALSE
)

nonlinear_diagnostic_games_6a1 <- market_model_data_6a1 |>
  dplyr::select(
    appid, name, is_free, current_price_usd, days_since_release,
    release_month, platform_segment, has_review, total_reviews
  ) |>
  dplyr::left_join(genre_labels_6a, by = "appid") |>
  dplyr::mutate(
    fitted_probability = nonlinear_fitted_6a1,
    deviance_residual = nonlinear_deviance_6a1,
    standardized_deviance_residual = nonlinear_std_deviance_6a1,
    leverage = nonlinear_leverage_6a1,
    cooks_distance = nonlinear_cooks_6a1,
    influence_diagnostic_defined = diagnostic_defined_6a1
  )
nonlinear_top_influence_6a1 <- nonlinear_diagnostic_games_6a1 |>
  dplyr::arrange(influence_diagnostic_defined, dplyr::desc(cooks_distance), appid) |>
  dplyr::slice_head(n = 20L)

nonlinear_large_terms_6a1 <- nonlinear_coefficients_all_6a1 |>
  dplyr::filter(abs(estimate_log_odds) > 10 | std_error > 10)
nonlinear_separation_diagnostics_6a1 <- data.frame(
  check = c(
    "glm_not_converged", "rank_deficient_model_matrix",
    "absolute_coefficient_gt_10_or_se_gt_10",
    "fitted_probability_below_1e_6", "fitted_probability_above_1_minus_1e_6",
    "categorical_zero_event_cell", "categorical_zero_non_event_cell", "glm_warning"
  ),
  n_flagged = c(
    as.integer(!nonlinear_entry_fit_6a1$converged),
    as.integer(nonlinear_primary_fit_6a1$matrix_rank != nonlinear_primary_fit_6a1$matrix_columns),
    nrow(nonlinear_large_terms_6a1),
    sum(nonlinear_fitted_6a1 < 1e-6),
    sum(nonlinear_fitted_6a1 > 1 - 1e-6),
    sum(outcome_cells_6a$zero_event_cell),
    sum(outcome_cells_6a$zero_non_event_cell),
    length(nonlinear_warnings_6a1)
  ),
  details = c(
    paste("converged =", nonlinear_entry_fit_6a1$converged),
    paste("rank =", nonlinear_primary_fit_6a1$matrix_rank, "of", nonlinear_primary_fit_6a1$matrix_columns),
    if (nrow(nonlinear_large_terms_6a1) == 0L) "none" else paste(nonlinear_large_terms_6a1$term, collapse = "; "),
    "Complete/quasi-separation heuristic", "Complete/quasi-separation heuristic",
    "Raw categorical outcome cells", "Raw categorical outcome cells",
    paste("warning count =", length(nonlinear_warnings_6a1))
  ),
  stringsAsFactors = FALSE
)

calibrate_fit_6a1 <- function(model_id, outcome, fitted_probability, appid) {
  data.frame(
    model_id = model_id,
    outcome = outcome,
    fitted_probability = fitted_probability,
    appid = appid
  ) |>
    dplyr::arrange(fitted_probability, appid) |>
    dplyr::mutate(decile = dplyr::ntile(fitted_probability, 10L)) |>
    dplyr::group_by(model_id, decile) |>
    dplyr::summarise(
      n_games = dplyr::n(),
      mean_predicted_probability = mean(fitted_probability),
      observed_has_review_rate = mean(outcome),
      absolute_gap = abs(observed_has_review_rate - mean_predicted_probability),
      .groups = "drop"
    )
}
calibration_comparison_6a1 <- dplyr::bind_rows(
  calibrate_fit_6a1("LINEAR_BENCHMARK", market_model_data_6a1$has_review,
                    stats::fitted(primary_entry_fit_6a), market_model_data_6a1$appid),
  calibrate_fit_6a1("NONLINEAR_PRICE_DF3_PRIMARY", market_model_data_6a1$has_review,
                    nonlinear_fitted_6a1, market_model_data_6a1$appid)
)

score_fit_6a1 <- function(model_id, outcome, fitted_probability) {
  epsilon <- 1e-15
  clipped <- pmin(pmax(fitted_probability, epsilon), 1 - epsilon)
  auc <- auc_delong_6a(outcome, fitted_probability)
  data.frame(
    model_id = model_id,
    auc = auc$auc,
    auc_standard_error = auc$standard_error,
    auc_ci95_lower = auc$ci95_lower,
    auc_ci95_upper = auc$ci95_upper,
    brier_score = mean((outcome - fitted_probability)^2),
    binary_log_loss = -mean(outcome * log(clipped) + (1 - outcome) * log(1 - clipped)),
    diagnostic_scope = "In-sample descriptive fit; not a model-selection contest",
    stringsAsFactors = FALSE
  )
}
auc_brier_6a1 <- dplyr::bind_rows(
  score_fit_6a1("LINEAR_BENCHMARK", market_model_data_6a1$has_review, stats::fitted(primary_entry_fit_6a)),
  score_fit_6a1("NONLINEAR_PRICE_DF3_PRIMARY", market_model_data_6a1$has_review, nonlinear_fitted_6a1)
)

release_formula_6a1 <- stats::as.formula(paste(
  "has_review ~ is_free +", paste(price_spline_terms_6a1, collapse = " + "), "+",
  "release_month + platform_segment +", paste(attention_primary_genres, collapse = " + ")
))
release_result_6a1 <- fit_glm_with_warnings_6a(release_formula_6a1, market_model_data_6a1)
release_fit_6a1 <- release_result_6a1$fit
release_warnings_6a1 <- release_result_6a1$warnings

expanded_formula_6a1 <- stats::as.formula(paste(
  "has_review ~ is_free +", paste(price_spline_terms_6a1, collapse = " + "), "+",
  "z_days_since_release + platform_segment +",
  paste(c(attention_primary_genres, attention_expanded_genres), collapse = " + ")
))
expanded_result_6a1 <- fit_glm_with_warnings_6a(expanded_formula_6a1, market_model_data_6a1)
expanded_fit_6a1 <- expanded_result_6a1$fit
expanded_warnings_6a1 <- expanded_result_6a1$warnings

nonprice_terms_6a1 <- nonlinear_non_spline_coefficients_6a1$term
release_sensitivity_6a1 <- dplyr::bind_rows(
  nonlinear_coefficients_all_6a1 |>
    dplyr::filter(term %in% nonprice_terms_6a1),
  tidy_logistic_6a(release_fit_6a1, "RELEASE_MONTH_SENSITIVITY") |>
    dplyr::filter(!term %in% price_spline_terms_6a1)
)
genre_sensitivity_6a1 <- dplyr::bind_rows(
  nonlinear_coefficients_all_6a1 |>
    dplyr::filter(term %in% nonprice_terms_6a1),
  tidy_logistic_6a(expanded_fit_6a1, "EXPANDED_GENRE_SENSITIVITY") |>
    dplyr::filter(!term %in% price_spline_terms_6a1)
)

release_curve_prediction_6a1 <- predict_link_ci_6a1(release_fit_6a1, price_grid_data_6a1)
expanded_curve_prediction_6a1 <- predict_link_ci_6a1(expanded_fit_6a1, price_grid_data_6a1)
price_curve_sensitivity_6a1 <- dplyr::bind_rows(
  data.frame(model_id = "NONLINEAR_PRICE_DF3_PRIMARY", price_curve_6a1),
  data.frame(model_id = "RELEASE_MONTH_SENSITIVITY", price_usd = price_grid_values_6a1,
             price_grid_index = seq_along(price_grid_values_6a1),
             price_support_region = price_curve_6a1$price_support_region,
             release_curve_prediction_6a1),
  data.frame(model_id = "EXPANDED_GENRE_SENSITIVITY", price_usd = price_grid_values_6a1,
             price_grid_index = seq_along(price_grid_values_6a1),
             price_support_region = price_curve_6a1$price_support_region,
             expanded_curve_prediction_6a1)
)
curve_difference_summary_6a1 <- dplyr::bind_rows(lapply(
  c("RELEASE_MONTH_SENSITIVITY", "EXPANDED_GENRE_SENSITIVITY"),
  function(model_id) {
    comparison <- price_curve_sensitivity_6a1 |>
      dplyr::filter(model_id == !!model_id)
    differences <- abs(comparison$predicted_probability - price_curve_6a1$predicted_probability)
    data.frame(
      model_id = model_id,
      max_absolute_probability_difference_full_support = max(differences),
      max_absolute_probability_difference_central_5_95 = max(
        differences[price_curve_6a1$price_support_region == "CENTRAL_5_95"]
      ),
      stringsAsFactors = FALSE
    )
  }
))

price_basis_df4_6a1 <- make_price_basis_definition_6a1(
  paid_log_price_training_6a1,
  df = 4L,
  center_log_price = price_center_log_6a1
)
df4_basis_matrix_6a1 <- apply_price_basis_6a1(
  market_model_data_6a1$current_price_usd,
  market_model_data_6a1$is_free,
  price_basis_df4_6a1,
  prefix = "price_spline_df4_"
)
market_model_data_df4_6a1 <- market_model_data_6a1
for (column in colnames(df4_basis_matrix_6a1)) {
  market_model_data_df4_6a1[[column]] <- df4_basis_matrix_6a1[, column]
}
df4_terms_6a1 <- colnames(df4_basis_matrix_6a1)
df4_formula_6a1 <- stats::as.formula(paste(
  "has_review ~ is_free +", paste(df4_terms_6a1, collapse = " + "), "+",
  "z_days_since_release + platform_segment +", paste(attention_primary_genres, collapse = " + ")
))
df4_result_6a1 <- fit_glm_with_warnings_6a(df4_formula_6a1, market_model_data_df4_6a1)
df4_fit_6a1 <- df4_result_6a1$fit
df4_warnings_6a1 <- df4_result_6a1$warnings
df4_grid_data_6a1 <- make_reference_data_6a1(
  price_grid_values_6a1,
  definition = price_basis_df4_6a1,
  prefix = "price_spline_df4_"
)
df4_curve_prediction_6a1 <- predict_link_ci_6a1(df4_fit_6a1, df4_grid_data_6a1)
df4_curve_6a1 <- data.frame(
  model_id = "PRICE_SPLINE_DF4_SENSITIVITY",
  price_usd = price_grid_values_6a1,
  price_support_region = price_curve_6a1$price_support_region,
  df4_curve_prediction_6a1,
  stringsAsFactors = FALSE
)
df4_peak_optim_6a1 <- stats::optimize(
  function(price) {
    predict_link_ci_6a1(
      df4_fit_6a1,
      make_reference_data_6a1(price, definition = price_basis_df4_6a1, prefix = "price_spline_df4_")
    )$predicted_probability
  },
  interval = c(price_support_6a1$min_usd, price_support_6a1$max_usd),
  maximum = TRUE,
  tol = 1e-10
)
df4_difference_6a1 <- abs(df4_curve_6a1$predicted_probability - price_curve_6a1$predicted_probability)
df4_sensitivity_6a1 <- dplyr::bind_rows(
  data.frame(
    model_id = "NONLINEAR_PRICE_DF3_PRIMARY", spline_df = 3L,
    n_games = stats::nobs(nonlinear_entry_fit_6a1), aic = stats::AIC(nonlinear_entry_fit_6a1),
    bic = stats::BIC(nonlinear_entry_fit_6a1), peak_price_usd = peak_price_6a1,
    max_abs_probability_difference_vs_df3_full = 0,
    max_abs_probability_difference_vs_df3_central_5_95 = 0,
    converged = nonlinear_entry_fit_6a1$converged, warning_count = length(nonlinear_warnings_6a1)
  ),
  data.frame(
    model_id = "PRICE_SPLINE_DF4_SENSITIVITY", spline_df = 4L,
    n_games = stats::nobs(df4_fit_6a1), aic = stats::AIC(df4_fit_6a1), bic = stats::BIC(df4_fit_6a1),
    peak_price_usd = df4_peak_optim_6a1$maximum,
    max_abs_probability_difference_vs_df3_full = max(df4_difference_6a1),
    max_abs_probability_difference_vs_df3_central_5_95 = max(
      df4_difference_6a1[price_curve_6a1$price_support_region == "CENTRAL_5_95"]
    ),
    converged = df4_fit_6a1$converged, warning_count = length(df4_warnings_6a1)
  )
)

gam_available_6a1 <- requireNamespace("mgcv", quietly = TRUE)
gam_warnings_6a1 <- character()
gam_error_6a1 <- ""
gam_fit_6a1 <- NULL
gam_curve_6a1 <- data.frame()
if (gam_available_6a1) {
  gam_data_6a1 <- market_model_data_6a1 |>
    dplyr::mutate(
      paid_indicator = as.numeric(is_free == 0L),
      gam_log1p_price = dplyr::if_else(
        is_free == 0L,
        log1p(current_price_usd),
        price_center_log_6a1
      )
    )
  gam_formula_6a1 <- stats::as.formula(paste(
    "has_review ~ is_free + s(gam_log1p_price, by = paid_indicator, k = 5, bs = 'cr') +",
    "z_days_since_release + platform_segment +", paste(attention_primary_genres, collapse = " + ")
  ))
  environment(gam_formula_6a1) <- asNamespace("mgcv")
  gam_fit_6a1 <- tryCatch(
    withCallingHandlers(
      mgcv::gam(gam_formula_6a1, family = stats::binomial(), data = gam_data_6a1, method = "REML"),
      warning = function(w) {
        gam_warnings_6a1 <<- c(gam_warnings_6a1, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      gam_error_6a1 <<- conditionMessage(e)
      NULL
    }
  )
}
if (!is.null(gam_fit_6a1)) {
  gam_newdata_6a1 <- price_grid_data_6a1
  gam_newdata_6a1$paid_indicator <- 1
  gam_newdata_6a1$gam_log1p_price <- log1p(price_grid_values_6a1)
  gam_prediction_6a1 <- stats::predict(gam_fit_6a1, gam_newdata_6a1, type = "link", se.fit = TRUE)
  gam_curve_6a1 <- data.frame(
    model_id = "OPTIONAL_GAM_K5",
    price_usd = price_grid_values_6a1,
    price_support_region = price_curve_6a1$price_support_region,
    predicted_probability = stats::plogis(gam_prediction_6a1$fit),
    ci95_lower = stats::plogis(gam_prediction_6a1$fit - 1.96 * gam_prediction_6a1$se.fit),
    ci95_upper = stats::plogis(gam_prediction_6a1$fit + 1.96 * gam_prediction_6a1$se.fit),
    stringsAsFactors = FALSE
  )
  smooth_table_6a1 <- summary(gam_fit_6a1)$s.table
  gam_difference_6a1 <- abs(gam_curve_6a1$predicted_probability - price_curve_6a1$predicted_probability)
  gam_diagnostic_6a1 <- data.frame(
    status = "RUN",
    package_available = TRUE,
    k = 5L,
    edf = smooth_table_6a1[1, "edf"],
    reference_df = smooth_table_6a1[1, "Ref.df"],
    smooth_test_statistic = smooth_table_6a1[1, ncol(smooth_table_6a1) - 1L],
    smooth_p_value = smooth_table_6a1[1, ncol(smooth_table_6a1)],
    aic = stats::AIC(gam_fit_6a1),
    max_abs_probability_difference_vs_df3_full = max(gam_difference_6a1),
    max_abs_probability_difference_vs_df3_central_5_95 = max(
      gam_difference_6a1[price_curve_6a1$price_support_region == "CENTRAL_5_95"]
    ),
    warning_count = length(gam_warnings_6a1),
    note = "Diagnostic only; not eligible to replace the inferential primary model automatically",
    stringsAsFactors = FALSE
  )
} else {
  gam_diagnostic_6a1 <- data.frame(
    status = if (gam_available_6a1) "FAILED" else "NOT_RUN",
    package_available = gam_available_6a1,
    k = 5L, edf = NA_real_, reference_df = NA_real_, smooth_test_statistic = NA_real_,
    smooth_p_value = NA_real_, aic = NA_real_,
    max_abs_probability_difference_vs_df3_full = NA_real_,
    max_abs_probability_difference_vs_df3_central_5_95 = NA_real_,
    warning_count = length(gam_warnings_6a1) + as.integer(nzchar(gam_error_6a1)),
    note = if (gam_available_6a1) gam_error_6a1 else "optional GAM diagnostic not run: mgcv unavailable",
    stringsAsFactors = FALSE
  )
}

fit_warnings_6a1 <- dplyr::bind_rows(
  warning_row_6a("Nonlinear primary df=3", nonlinear_warnings_6a1),
  warning_row_6a("Release-month nonlinear sensitivity", release_warnings_6a1),
  warning_row_6a("Expanded-genre nonlinear sensitivity", expanded_warnings_6a1),
  warning_row_6a("Price spline df=4 sensitivity", df4_warnings_6a1),
  warning_row_6a("Optional GAM diagnostic", gam_warnings_6a1, gam_error_6a1)
)

release_curve_stable_6a1 <- curve_difference_summary_6a1 |>
  dplyr::filter(model_id == "RELEASE_MONTH_SENSITIVITY") |>
  dplyr::pull(max_absolute_probability_difference_central_5_95) <= 0.03
genre_curve_stable_6a1 <- curve_difference_summary_6a1 |>
  dplyr::filter(model_id == "EXPANDED_GENRE_SENSITIVITY") |>
  dplyr::pull(max_absolute_probability_difference_central_5_95) <= 0.03
df4_curve_stable_6a1 <- df4_sensitivity_6a1 |>
  dplyr::filter(model_id == "PRICE_SPLINE_DF4_SENSITIVITY") |>
  dplyr::pull(max_abs_probability_difference_vs_df3_central_5_95) <= 0.05

freeze_criteria_6a1 <- data.frame(
  criterion = c(
    "convergence", "no_separation", "influence_acceptable", "calibration_acceptable",
    "release_curve_stable", "genre_curve_stable", "df4_central_shape_stable",
    "no_numerical_instability"
  ),
  passed = c(
    isTRUE(nonlinear_entry_fit_6a1$converged),
    sum(nonlinear_separation_diagnostics_6a1$n_flagged) == 0L,
    nonlinear_influence_summary_6a1$n_influence_diagnostics_not_defined == 0L &&
      nonlinear_influence_summary_6a1$max_cooks_distance < 0.5,
    max(calibration_comparison_6a1$absolute_gap[
      calibration_comparison_6a1$model_id == "NONLINEAR_PRICE_DF3_PRIMARY"
    ]) <= 0.05,
    release_curve_stable_6a1,
    genre_curve_stable_6a1,
    df4_curve_stable_6a1,
    nonlinear_primary_fit_6a1$matrix_rank == nonlinear_primary_fit_6a1$matrix_columns &&
      length(nonlinear_warnings_6a1) == 0L &&
      all(is.finite(stats::coef(nonlinear_entry_fit_6a1)))
  ),
  threshold_or_rule = c(
    "glm converged", "all separation heuristics zero",
    "all diagnostics defined and max Cook's D < 0.5",
    "maximum decile absolute gap <= 0.05",
    "central 5-95% max probability difference <= 0.03",
    "central 5-95% max probability difference <= 0.03",
    "central 5-95% df4-vs-df3 max probability difference <= 0.05",
    "full rank, no primary warnings, finite coefficients"
  ),
  stringsAsFactors = FALSE
)
step6a1_freeze_pass_6a1 <- all(freeze_criteria_6a1$passed)
step6a1_stage_decision_6a1 <- data.frame(
  step6a1_status = if (step6a1_freeze_pass_6a1) "PASS" else "FAIL",
  price_functional_form = if (step6a1_freeze_pass_6a1) "SPLINE ADEQUATE" else "SPLINE STILL INADEQUATE",
  review_entry_model_frozen = step6a1_freeze_pass_6a1,
  ready_for_step6b = step6a1_freeze_pass_6a1,
  final_entry_model = if (step6a1_freeze_pass_6a1) {
    "Logistic regression with centered frozen natural spline df=3 for paid collection-time price"
  } else {
    "Not frozen"
  },
  next_gate = if (step6a1_freeze_pass_6a1) "Human approval before Step 6B" else "Resolve failed Step 6A.1 freeze criteria",
  stringsAsFactors = FALSE
)

write_attention_audit(nonlinear_separation_diagnostics_6a1, "step6a1_separation_diagnostics.csv")
write_attention_audit(nonlinear_influence_summary_6a1, "step6a1_influence_summary.csv")
write_attention_audit(nonlinear_top_influence_6a1, "step6a1_top_influence.csv")
write_attention_audit(calibration_comparison_6a1, "step6a1_calibration.csv")
write_attention_audit(auc_brier_6a1, "step6a1_auc_brier.csv")
write_attention_audit(release_sensitivity_6a1, "step6a1_release_sensitivity.csv")
write_attention_audit(genre_sensitivity_6a1, "step6a1_genre_sensitivity.csv")
write_attention_audit(price_curve_sensitivity_6a1, "step6a1_price_curve_sensitivity.csv")
write_attention_audit(curve_difference_summary_6a1, "step6a1_price_curve_sensitivity_summary.csv")
write_attention_audit(df4_sensitivity_6a1, "step6a1_df4_sensitivity.csv")
write_attention_audit(df4_curve_6a1, "step6a1_df4_curve.csv")
write_attention_audit(gam_diagnostic_6a1, "step6a1_gam_diagnostic.csv")
if (nrow(gam_curve_6a1) > 0L) write_attention_audit(gam_curve_6a1, "step6a1_gam_curve.csv")
write_attention_audit(fit_warnings_6a1, "step6a1_fit_warnings.csv")
write_attention_audit(freeze_criteria_6a1, "step6a1_freeze_criteria.csv")
write_attention_audit(step6a1_stage_decision_6a1, "step6a1_stage_decision.csv")
write_attention_audit(database_preservation_6a, "step6a1_database_preservation.csv")

message(sprintf(
  "Step 6A.1 diagnostics and sensitivity: %s",
  if (step6a1_freeze_pass_6a1) "PASS" else "FAIL"
))
