# Step 6A primary-model influence, calibration, ROC/AUC, and warning audit.

if (!exists("days_spline_fit_6a")) {
  stop("Run 03_functional_form_audit.R before 04_entry_diagnostics.R.", call. = FALSE)
}

fitted_6a <- stats::fitted(primary_entry_fit_6a)
std_deviance_6a <- stats::rstandard(primary_entry_fit_6a, type = "deviance")
deviance_6a <- stats::residuals(primary_entry_fit_6a, type = "deviance")
leverage_6a <- stats::hatvalues(primary_entry_fit_6a)
cooks_6a <- stats::cooks.distance(primary_entry_fit_6a)
n_6a <- nrow(market_model_data_6a)
p_6a <- length(stats::coef(primary_entry_fit_6a))

if (any(!is.finite(fitted_6a)) || any(!is.finite(leverage_6a))) {
  stop(
    paste0(
      "Non-finite Step 6A diagnostics: fitted=", sum(!is.finite(fitted_6a)),
      ", leverage=", sum(!is.finite(leverage_6a))
    ),
    call. = FALSE
  )
}
diagnostic_defined_6a <- is.finite(std_deviance_6a) & is.finite(cooks_6a)
std_deviance_6a[!is.finite(std_deviance_6a)] <- NA_real_
cooks_6a[!is.finite(cooks_6a)] <- NA_real_

influence_summary_6a <- data.frame(
  n_games = n_6a,
  parameter_count = p_6a,
  n_influence_diagnostics_not_defined = sum(!diagnostic_defined_6a),
  max_absolute_deviance_residual = max(abs(deviance_6a)),
  max_absolute_standardized_deviance_residual = max(abs(std_deviance_6a), na.rm = TRUE),
  n_absolute_standardized_residual_gt_2 = sum(abs(std_deviance_6a) > 2, na.rm = TRUE),
  n_absolute_standardized_residual_gt_3 = sum(abs(std_deviance_6a) > 3, na.rm = TRUE),
  max_leverage = max(leverage_6a),
  threshold_2p_over_n = 2 * p_6a / n_6a,
  n_leverage_above_2p_over_n = sum(leverage_6a > 2 * p_6a / n_6a),
  threshold_3p_over_n = 3 * p_6a / n_6a,
  n_leverage_above_3p_over_n = sum(leverage_6a > 3 * p_6a / n_6a),
  max_cooks_distance = max(cooks_6a, na.rm = TRUE),
  threshold_4_over_n = 4 / n_6a,
  n_cooks_above_4_over_n = sum(cooks_6a > 4 / n_6a, na.rm = TRUE),
  n_cooks_above_0_5 = sum(cooks_6a > 0.5, na.rm = TRUE),
  n_cooks_above_1 = sum(cooks_6a > 1, na.rm = TRUE),
  stringsAsFactors = FALSE
)

genre_labels_6a <- genre_long_model |>
  dplyr::group_by(appid) |>
  dplyr::summarise(genres = paste(sort(unique(genre_name)), collapse = "; "), .groups = "drop")
diagnostic_games_6a <- market_model_data_6a |>
  dplyr::select(
    appid, name, is_free, current_price_usd, days_since_release,
    release_month, platform_segment, has_review, total_reviews
  ) |>
  dplyr::left_join(genre_labels_6a, by = "appid") |>
  dplyr::mutate(
    fitted_probability = fitted_6a,
    deviance_residual = deviance_6a,
    standardized_deviance_residual = std_deviance_6a,
    leverage = leverage_6a,
    cooks_distance = cooks_6a,
    influence_diagnostic_defined = diagnostic_defined_6a
  )
top_influence_6a <- diagnostic_games_6a |>
  dplyr::arrange(influence_diagnostic_defined, dplyr::desc(cooks_distance), appid) |>
  dplyr::slice_head(n = 20)

calibration_6a <- diagnostic_games_6a |>
  dplyr::arrange(fitted_probability, appid) |>
  dplyr::mutate(decile = dplyr::ntile(fitted_probability, 10)) |>
  dplyr::group_by(decile) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    mean_predicted_probability = mean(fitted_probability),
    observed_has_review_rate = mean(has_review),
    absolute_gap = abs(observed_has_review_rate - mean_predicted_probability),
    .groups = "drop"
  )

auc_6a <- auc_delong_6a(diagnostic_games_6a$has_review, diagnostic_games_6a$fitted_probability)
roc_grouped_6a <- diagnostic_games_6a |>
  dplyr::group_by(fitted_probability) |>
  dplyr::summarise(
    events = sum(has_review == 1L), non_events = sum(has_review == 0L),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(fitted_probability)) |>
  dplyr::mutate(
    true_positive_rate = cumsum(events) / sum(events),
    false_positive_rate = cumsum(non_events) / sum(non_events)
  ) |>
  dplyr::select(fitted_probability, false_positive_rate, true_positive_rate)
roc_points_6a <- dplyr::bind_rows(
  data.frame(fitted_probability = Inf, false_positive_rate = 0, true_positive_rate = 0),
  roc_grouped_6a,
  data.frame(fitted_probability = -Inf, false_positive_rate = 1, true_positive_rate = 1)
)

warning_row_6a <- function(stage, warnings, failure = "") {
  text <- paste(unique(c(warnings, failure[nzchar(failure)])), collapse = " | ")
  data.frame(
    stage = stage,
    status = if (length(warnings) == 0L && !nzchar(failure)) "NO WARNING" else if (nzchar(failure)) "FAILED" else "WARNING",
    warning_count = length(warnings) + as.integer(nzchar(failure)),
    warning_text = text,
    stringsAsFactors = FALSE
  )
}
fit_warnings_6a <- dplyr::bind_rows(
  warning_row_6a("Primary logistic", primary_entry_warnings_6a),
  warning_row_6a("Primary profile likelihood CI", profile_warnings_6a, profile_error_6a),
  warning_row_6a("Release-month sensitivity", release_warnings_6a),
  warning_row_6a("Expanded-genre sensitivity", expanded_warnings_6a),
  warning_row_6a("Days spline df=3", days_spline_warnings_6a),
  warning_row_6a("Paid-price linear auxiliary", price_linear_warnings_6a),
  warning_row_6a("Paid-price spline df=3 auxiliary", price_spline_warnings_6a)
)

write_attention_audit(influence_summary_6a, "step6a_influence_summary.csv")
write_attention_audit(top_influence_6a, "step6a_top_influence.csv")
write_attention_audit(calibration_6a, "step6a_calibration.csv")
write_attention_audit(auc_6a, "step6a_auc.csv")
write_attention_audit(roc_points_6a, "step6a_roc_points.csv")
write_attention_audit(fit_warnings_6a, "step6a_fit_warnings.csv")

message("Step 6A diagnostics: PASS")
