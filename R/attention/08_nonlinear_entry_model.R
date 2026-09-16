# Step 6A.1 nonlinear review-entry primary model and frozen-basis predictions.

if (!exists("market_model_data_6a1") || !exists("price_basis_df3_6a1")) {
  stop("Run 07_nonlinear_price_basis.R before 08_nonlinear_entry_model.R.", call. = FALSE)
}

nonlinear_formula_6a1 <- stats::as.formula(paste(
  "has_review ~ is_free +", paste(price_spline_terms_6a1, collapse = " + "), "+",
  "z_days_since_release + platform_segment +",
  paste(attention_primary_genres, collapse = " + ")
))
nonlinear_result_6a1 <- fit_glm_with_warnings_6a(nonlinear_formula_6a1, market_model_data_6a1)
nonlinear_entry_fit_6a1 <- nonlinear_result_6a1$fit
nonlinear_warnings_6a1 <- nonlinear_result_6a1$warnings
nonlinear_primary_fit_6a1 <- fit_summary_6a(
  nonlinear_entry_fit_6a1,
  "NONLINEAR_PRICE_DF3_PRIMARY",
  length(nonlinear_warnings_6a1)
)
nonlinear_coefficients_all_6a1 <- tidy_logistic_6a(
  nonlinear_entry_fit_6a1,
  "NONLINEAR_PRICE_DF3_PRIMARY"
)
nonlinear_non_spline_coefficients_6a1 <- nonlinear_coefficients_all_6a1 |>
  dplyr::filter(!term %in% price_spline_terms_6a1) |>
  dplyr::mutate(
    interpretation = dplyr::case_when(
      term == "is_free" ~ paste0(
        "Free versus paid at the centered paid-price reference ($",
        formatC(price_center_usd_6a1, digits = 2, format = "f"), ")"
      ),
      term == "z_days_since_release" ~ "Odds ratio per one market SD of days since release",
      term == "(Intercept)" ~ "Model intercept; not a substantive effect",
      TRUE ~ "Conditional association"
    )
  )

if (!isTRUE(nonlinear_entry_fit_6a1$converged) ||
    nonlinear_primary_fit_6a1$matrix_rank != nonlinear_primary_fit_6a1$matrix_columns ||
    length(nonlinear_warnings_6a1) > 0L ||
    stats::nobs(nonlinear_entry_fit_6a1) != 2998L) {
  stop("Step 6A.1 nonlinear primary model did not converge cleanly.", call. = FALSE)
}

audit_nested_models_6a1 <- function(reduced_fit, full_fit, comparison_id) {
  x_reduced <- stats::model.matrix(reduced_fit)
  x_full <- stats::model.matrix(full_fit)
  same_rows <- identical(rownames(x_reduced), rownames(x_full))
  full_qr <- qr(x_full)
  max_projection_residual <- if (same_rows) {
    max(abs(qr.resid(full_qr, x_reduced)))
  } else {
    Inf
  }
  combined_rank <- if (same_rows) qr(cbind(x_full, x_reduced))$rank else NA_integer_
  strictly_nested <- isTRUE(same_rows) &&
    combined_rank == full_qr$rank &&
    max_projection_residual < 1e-8
  lrt <- if (strictly_nested) stats::anova(reduced_fit, full_fit, test = "Chisq") else NULL
  data.frame(
    comparison_id = comparison_id,
    same_rows = same_rows,
    reduced_rank = qr(x_reduced)$rank,
    full_rank = full_qr$rank,
    combined_rank = combined_rank,
    max_reduced_projection_residual = max_projection_residual,
    strictly_nested = strictly_nested,
    formal_lrt_valid = strictly_nested,
    lrt_deviance_difference = if (strictly_nested) lrt$Deviance[2] else NA_real_,
    lrt_df_difference = if (strictly_nested) lrt$Df[2] else NA_real_,
    lrt_p_value = if (strictly_nested) lrt$`Pr(>Chi)`[2] else NA_real_,
    conclusion = if (strictly_nested) {
      "Reduced linear column space is contained in the frozen natural-spline column space"
    } else {
      "Not strictly nested; formal LRT suppressed"
    },
    stringsAsFactors = FALSE
  )
}

nesting_primary_6a1 <- audit_nested_models_6a1(
  primary_entry_fit_6a,
  nonlinear_entry_fit_6a1,
  "FULL_MARKET_LINEAR_VS_DF3_SPLINE"
)
nesting_paid_aux_6a1 <- audit_nested_models_6a1(
  price_linear_fit_6a,
  price_spline_fit_6a,
  "STEP6A_PAID_ONLY_LINEAR_VS_DF3_SPLINE"
)
nesting_audit_6a1 <- dplyr::bind_rows(nesting_primary_6a1, nesting_paid_aux_6a1)

linear_vs_nonlinear_6a1 <- dplyr::bind_rows(
  fit_summary_6a(primary_entry_fit_6a, "LINEAR_BENCHMARK", length(primary_entry_warnings_6a)),
  nonlinear_primary_fit_6a1
) |>
  dplyr::mutate(
    same_rows = length(unique(n_games)) == 1L,
    delta_aic_from_linear = aic - aic[model_id == "LINEAR_BENCHMARK"],
    delta_bic_from_linear = bic - bic[model_id == "LINEAR_BENCHMARK"],
    formal_lrt_valid = nesting_primary_6a1$formal_lrt_valid,
    lrt_p_value = nesting_primary_6a1$lrt_p_value
  )

predict_link_ci_6a1 <- function(fit, newdata, level = 0.95) {
  x <- stats::model.matrix(
    stats::delete.response(stats::terms(fit)),
    newdata,
    contrasts.arg = fit$contrasts,
    xlev = fit$xlevels
  )
  beta <- stats::coef(fit)
  x <- x[, names(beta), drop = FALSE]
  eta <- as.numeric(x %*% beta)
  covariance <- stats::vcov(fit)
  se_eta <- sqrt(rowSums((x %*% covariance) * x))
  critical <- stats::qnorm(1 - (1 - level) / 2)
  data.frame(
    predicted_probability = stats::plogis(eta),
    ci95_lower = stats::plogis(eta - critical * se_eta),
    ci95_upper = stats::plogis(eta + critical * se_eta),
    link_estimate = eta,
    link_standard_error = se_eta,
    stringsAsFactors = FALSE
  )
}

make_reference_data_6a1 <- function(price_usd, is_free = 0L, definition = price_basis_df3_6a1,
                                    prefix = "price_spline_") {
  n <- length(price_usd)
  template <- market_model_data_6a1[rep(1L, n), , drop = FALSE]
  template$is_free <- as.integer(rep(is_free, length.out = n))
  template$current_price_usd <- price_usd
  template$z_days_since_release <- 0
  template$platform_segment <- factor(
    rep("Windows only", n), levels = levels(market_model_data_6a1$platform_segment)
  )
  template$release_month <- factor(
    rep("2025-07", n), levels = levels(market_model_data_6a1$release_month)
  )
  for (genre in c(attention_primary_genres, attention_expanded_genres)) {
    template[[genre]] <- 0L
  }
  basis <- apply_price_basis_6a1(
    template$current_price_usd,
    template$is_free,
    definition,
    prefix = prefix
  )
  for (column in colnames(basis)) template[[column]] <- basis[, column]
  template
}

price_grid_values_6a1 <- seq(
  price_support_6a1$min_usd,
  price_support_6a1$max_usd,
  length.out = 200L
)
price_grid_data_6a1 <- make_reference_data_6a1(price_grid_values_6a1)
price_grid_prediction_6a1 <- predict_link_ci_6a1(nonlinear_entry_fit_6a1, price_grid_data_6a1)
price_curve_6a1 <- data.frame(
  price_usd = price_grid_values_6a1,
  price_grid_index = seq_along(price_grid_values_6a1),
  price_support_region = ifelse(
    price_grid_values_6a1 >= price_support_6a1$p05_usd &
      price_grid_values_6a1 <= price_support_6a1$p95_usd,
    "CENTRAL_5_95", "SPARSE_TAIL"
  ),
  price_grid_prediction_6a1,
  stringsAsFactors = FALSE
)

make_linear_reference_data_6a1 <- function(price_usd) {
  data <- make_reference_data_6a1(price_usd)
  data$z_log1p_paid_price_component <-
    (log1p(price_usd) - paid_price_mean_log_6a) / paid_price_sd_log_6a
  data
}
linear_curve_prediction_6a1 <- predict_link_ci_6a1(
  primary_entry_fit_6a,
  make_linear_reference_data_6a1(price_grid_values_6a1)
)
linear_price_curve_6a1 <- data.frame(
  price_usd = price_grid_values_6a1,
  model_id = "LINEAR_BENCHMARK",
  linear_curve_prediction_6a1,
  stringsAsFactors = FALSE
)

peak_objective_6a1 <- function(price) {
  predict_link_ci_6a1(
    nonlinear_entry_fit_6a1,
    make_reference_data_6a1(price)
  )$predicted_probability
}
peak_optim_6a1 <- stats::optimize(
  peak_objective_6a1,
  interval = c(price_support_6a1$min_usd, price_support_6a1$max_usd),
  maximum = TRUE,
  tol = 1e-10
)
peak_price_6a1 <- peak_optim_6a1$maximum
peak_prediction_6a1 <- predict_link_ci_6a1(
  nonlinear_entry_fit_6a1,
  make_reference_data_6a1(peak_price_6a1)
)
dense_prices_6a1 <- seq(price_support_6a1$min_usd, price_support_6a1$max_usd, length.out = 4000L)
dense_probabilities_6a1 <- predict_link_ci_6a1(
  nonlinear_entry_fit_6a1,
  make_reference_data_6a1(dense_prices_6a1)
)$predicted_probability
peak_index_6a1 <- which.max(dense_probabilities_6a1)
plateau_mask_6a1 <- dense_probabilities_6a1 >= peak_prediction_6a1$predicted_probability - 0.005
plateau_left_6a1 <- peak_index_6a1
while (plateau_left_6a1 > 1L && plateau_mask_6a1[plateau_left_6a1 - 1L]) {
  plateau_left_6a1 <- plateau_left_6a1 - 1L
}
plateau_right_6a1 <- peak_index_6a1
while (plateau_right_6a1 < length(plateau_mask_6a1) && plateau_mask_6a1[plateau_right_6a1 + 1L]) {
  plateau_right_6a1 <- plateau_right_6a1 + 1L
}
peak_audit_6a1 <- data.frame(
  peak_price_usd = peak_price_6a1,
  peak_predicted_probability = peak_prediction_6a1$predicted_probability,
  peak_ci95_lower = peak_prediction_6a1$ci95_lower,
  peak_ci95_upper = peak_prediction_6a1$ci95_upper,
  local_plateau_definition = "Contiguous prices within 0.5 percentage points of fitted peak",
  plateau_lower_price_usd = dense_prices_6a1[plateau_left_6a1],
  plateau_upper_price_usd = dense_prices_6a1[plateau_right_6a1],
  plateau_width_usd = dense_prices_6a1[plateau_right_6a1] - dense_prices_6a1[plateau_left_6a1],
  peak_within_central_5_95_support = peak_price_6a1 >= price_support_6a1$p05_usd &
    peak_price_6a1 <= price_support_6a1$p95_usd,
  interpretation = "Descriptive fitted maximum; not an optimal or causal price",
  stringsAsFactors = FALSE
)

representative_prices_6a1 <- c(0.99, 2.99, 4.99, 9.99, 14.99, 19.99, 29.99, 49.99)
representative_prices_6a1 <- representative_prices_6a1[
  representative_prices_6a1 >= price_support_6a1$min_usd &
    representative_prices_6a1 <= price_support_6a1$max_usd
]
representative_prediction_6a1 <- predict_link_ci_6a1(
  nonlinear_entry_fit_6a1,
  make_reference_data_6a1(representative_prices_6a1)
)
representative_price_predictions_6a1 <- data.frame(
  price_usd = representative_prices_6a1,
  representative_prediction_6a1,
  support_region = ifelse(
    representative_prices_6a1 >= price_support_6a1$p05_usd &
      representative_prices_6a1 <= price_support_6a1$p95_usd,
    "CENTRAL_5_95", "OUTSIDE_CENTRAL_5_95"
  ),
  stringsAsFactors = FALSE
)

contrast_pairs_6a1 <- data.frame(
  contrast_id = c("4.99_TO_9.99", "9.99_TO_14.99", "14.99_TO_29.99"),
  price_1_usd = c(4.99, 9.99, 14.99),
  price_2_usd = c(9.99, 14.99, 29.99),
  stringsAsFactors = FALSE
)
price_contrasts_6a1 <- dplyr::bind_rows(lapply(seq_len(nrow(contrast_pairs_6a1)), function(i) {
  pair <- contrast_pairs_6a1[i, ]
  probabilities <- predict_link_ci_6a1(
    nonlinear_entry_fit_6a1,
    make_reference_data_6a1(c(pair$price_1_usd, pair$price_2_usd))
  )$predicted_probability
  data.frame(
    contrast_id = pair$contrast_id,
    price_1_usd = pair$price_1_usd,
    price_2_usd = pair$price_2_usd,
    probability_1 = probabilities[1],
    probability_2 = probabilities[2],
    probability_difference = probabilities[2] - probabilities[1],
    percentage_point_difference = 100 * (probabilities[2] - probabilities[1]),
    stringsAsFactors = FALSE
  )
}))

paid_reference_6a1 <- make_reference_data_6a1(price_center_usd_6a1, is_free = 0L)
free_reference_6a1 <- make_reference_data_6a1(NA_real_, is_free = 1L)
free_paid_probabilities_6a1 <- c(
  predict_link_ci_6a1(nonlinear_entry_fit_6a1, paid_reference_6a1)$predicted_probability,
  predict_link_ci_6a1(nonlinear_entry_fit_6a1, free_reference_6a1)$predicted_probability
)
free_contrast_6a1 <- data.frame(
  paid_reference_price_usd = price_center_usd_6a1,
  paid_reference_probability = free_paid_probabilities_6a1[1],
  free_probability = free_paid_probabilities_6a1[2],
  free_minus_paid_probability_difference = free_paid_probabilities_6a1[2] - free_paid_probabilities_6a1[1],
  free_minus_paid_percentage_point_difference = 100 * (free_paid_probabilities_6a1[2] - free_paid_probabilities_6a1[1]),
  scope = "One-at-a-time conditional contrast at centered paid-price reference",
  stringsAsFactors = FALSE
)

write_attention_audit(nonlinear_primary_fit_6a1, "step6a1_primary_fit.csv")
write_attention_audit(nonlinear_non_spline_coefficients_6a1, "step6a1_primary_non_spline_coefficients.csv")
write_attention_audit(linear_vs_nonlinear_6a1, "step6a1_linear_vs_nonlinear.csv")
write_attention_audit(nesting_audit_6a1, "step6a1_nesting_audit.csv")
write_attention_audit(price_curve_6a1, "step6a1_price_curve.csv")
write_attention_audit(linear_price_curve_6a1, "step6a1_linear_price_curve.csv")
write_attention_audit(peak_audit_6a1, "step6a1_peak_audit.csv")
write_attention_audit(representative_price_predictions_6a1, "step6a1_representative_price_predictions.csv")
write_attention_audit(price_contrasts_6a1, "step6a1_price_contrasts.csv")
write_attention_audit(free_contrast_6a1, "step6a1_free_contrast.csv")

message("Step 6A.1 nonlinear primary model and price curve: PASS")
