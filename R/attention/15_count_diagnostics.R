# Predictions, calibration, exposure, price, and representative contrasts.
predict_positive_6b <- function(fit, newdata) {
  mu <- as.numeric(stats::predict(fit, newdata = newdata, type = "conditional",
    allow.new.levels = FALSE))
  conditional_mean_6b(mu, as.numeric(stats::sigma(fit)))
}
make_reference_6b <- function(price = expm1(center_log_6b), days =
  stats::median(positive_model_6b$days_since_release), free = 0L) {
  d <- positive_model_6b[1, , drop = FALSE]
  d$is_free <- as.integer(free)
  d$current_price_usd <- if (free == 1L) 0 else price
  d$log1p_price <- log1p(d$current_price_usd)
  d$days_since_release <- days; d$log_days <- log(days)
  d$platform_segment <- factor("Windows only", levels = levels(positive_model_6b$platform_segment))
  d$release_month <- factor("2025-07", levels = levels(positive_model_6b$release_month))
  for (term in primary_genres_6b) d[[term]] <- 0L
  d[, paste0("price_spline_", 1:3)] <- apply_basis_6b(
    d$current_price_usd, d$is_free, basis_df3_6b)
  d[, paste0("price_df4_", 1:4)] <- apply_basis_6b(
    d$current_price_usd, d$is_free, basis_df4_6b, "price_df4_")
  d
}
ref_days_6b <- if (selected_exposure_6b == "OFFSET") 365 else
  stats::median(positive_model_6b$days_since_release)
price_grid_6b <- seq(min(paid_positive_6b$current_price_usd),
  max(paid_positive_6b$current_price_usd), length.out = 150L)
price_grid_data_6b <- dplyr::bind_rows(lapply(price_grid_6b,
  function(p) make_reference_6b(p, ref_days_6b)))
price_curve_6b <- data.frame(price_usd = price_grid_6b,
  days = ref_days_6b, predicted_positive_count =
    predict_positive_6b(primary_truncated_6b, price_grid_data_6b),
  central_support = price_grid_6b >= basis_definition_6b$price_p05_usd &
    price_grid_6b <= basis_definition_6b$price_p95_usd)

days_support_6b <- range(positive_model_6b$days_since_release)
days_grid_6b <- sort(unique(c(seq(days_support_6b[1], days_support_6b[2],
  length.out = 120L), 270, 300, 330, 365, 400, 430)))
days_grid_6b <- days_grid_6b[days_grid_6b >= days_support_6b[1] &
  days_grid_6b <= days_support_6b[2]]
exposure_grid_data_6b <- dplyr::bind_rows(lapply(days_grid_6b,
  function(days) make_reference_6b(days = days)))
exposure_curve_6b <- data.frame(days = days_grid_6b,
  log_days_covariate = predict_positive_6b(
    exposure_fits_6b$LOG_DAYS_COVARIATE, exposure_grid_data_6b),
  offset = predict_positive_6b(exposure_fits_6b$OFFSET, exposure_grid_data_6b),
  nonlinear_log_days = predict_positive_6b(
    exposure_fits_6b$NONLINEAR_LOG_DAYS, exposure_grid_data_6b))

contrast_values_6b <- function(label, x0, x1) data.frame(
  contrast = label, predicted_count_from = predict_positive_6b(primary_truncated_6b, x0),
  predicted_count_to = predict_positive_6b(primary_truncated_6b, x1),
  positive_count_ratio = predict_positive_6b(primary_truncated_6b, x1) /
    predict_positive_6b(primary_truncated_6b, x0))
contrast_list_6b <- list()
for (pair in list(c(4.99, 9.99), c(9.99, 14.99), c(14.99, 29.99))) {
  contrast_list_6b[[length(contrast_list_6b) + 1L]] <- contrast_values_6b(
    paste0("PRICE_", pair[1], "_TO_", pair[2]),
    make_reference_6b(pair[1], ref_days_6b), make_reference_6b(pair[2], ref_days_6b))
}
for (pair in list(c(300, 365), c(365, 430))) {
  if (all(pair >= days_support_6b[1] & pair <= days_support_6b[2])) {
    contrast_list_6b[[length(contrast_list_6b) + 1L]] <- contrast_values_6b(
      paste0("DAYS_", pair[1], "_TO_", pair[2]),
      make_reference_6b(days = pair[1]), make_reference_6b(days = pair[2]))
  }
}
ref_6b <- make_reference_6b(days = ref_days_6b)
free_6b <- make_reference_6b(days = ref_days_6b, free = 1L)
contrast_list_6b[[length(contrast_list_6b) + 1L]] <- contrast_values_6b(
  "FREE_VS_PAID_REFERENCE", ref_6b, free_6b)
for (platform in setdiff(levels(positive_model_6b$platform_segment), "Windows only")) {
  other <- ref_6b; other$platform_segment <- factor(platform,
    levels = levels(positive_model_6b$platform_segment))
  contrast_list_6b[[length(contrast_list_6b) + 1L]] <- contrast_values_6b(
    paste0("PLATFORM_", platform), ref_6b, other)
}
for (term in primary_genres_6b) {
  other <- ref_6b; other[[term]] <- 1L
  contrast_list_6b[[length(contrast_list_6b) + 1L]] <- contrast_values_6b(
    paste0("GENRE_", term), ref_6b, other)
}
contrasts_6b <- dplyr::bind_rows(contrast_list_6b)

y_6b <- positive_model_6b$review_count
v_untrunc_6b <- mu_latent_6b + mu_latent_6b^2 / theta_6b
v_positive_6b <- v_untrunc_6b / (1 - p0_6b) -
  mu_latent_6b^2 * p0_6b / (1 - p0_6b)^2
pearson_6b <- (y_6b - mean_positive_6b) / sqrt(v_positive_6b)
residual_diagnostics_6b <- data.frame(n_games = length(y_6b),
  observed_mean = mean(y_6b), fitted_mean = mean(mean_positive_6b),
  observed_variance = stats::var(y_6b), fitted_mean_variance =
    mean(v_positive_6b) + stats::var(mean_positive_6b),
  pearson_mean = mean(pearson_6b), pearson_sd = stats::sd(pearson_6b),
  pearson_p95_abs = quant_6b(abs(pearson_6b), .95),
  pearson_max_abs = max(abs(pearson_6b)),
  deviance_residual_available = FALSE,
  standardized_residual_available = FALSE,
  dharma_available = requireNamespace("DHARMa", quietly = TRUE))
residual_points_6b <- data.frame(appid = positive_model_6b$appid,
  observed = y_6b, fitted = mean_positive_6b,
  pearson_residual = pearson_6b)

bin_upper_6b <- c(1, 4, 9, 19, 49, 99, 499, 999, Inf)
bin_lower_6b <- c(1, 2, 5, 10, 20, 50, 100, 500, 1000)
expected_bins_6b <- vapply(seq_along(bin_lower_6b), function(i) {
  upper <- if (is.infinite(bin_upper_6b[i])) rep(1, length(mu_latent_6b)) else
    stats::pnbinom(bin_upper_6b[i], mu = mu_latent_6b, size = theta_6b)
  lower <- stats::pnbinom(bin_lower_6b[i] - 1L, mu = mu_latent_6b, size = theta_6b)
  sum((upper - lower) / (1 - p0_6b))
}, numeric(1))
fit_bins_6b <- data.frame(bin = count_labels_6b,
  observed_n = as.integer(table(count_bin_6b(y_6b))),
  expected_n = expected_bins_6b)
fit_bins_6b$sqrt_observed <- sqrt(fit_bins_6b$observed_n)
fit_bins_6b$sqrt_expected <- sqrt(fit_bins_6b$expected_n)
stopifnot(all(is.finite(pearson_6b)), all(v_positive_6b > 0),
  abs(sum(expected_bins_6b) - nrow(positive_model_6b)) < 1e-5,
  all(price_curve_6b$predicted_positive_count > 0),
  all(exposure_curve_6b[, -1] > 0))

write_attention_audit(price_curve_6b, "step6b_price_curve.csv")
write_attention_audit(exposure_curve_6b, "step6b_exposure_curve.csv")
write_attention_audit(contrasts_6b, "step6b_probability_count_contrasts.csv")
write_attention_audit(residual_diagnostics_6b, "step6b_residual_diagnostics.csv")
write_attention_audit(residual_points_6b, "step6b_residual_points.csv")
write_attention_audit(fit_bins_6b, "step6b_observed_expected_bins.csv")
