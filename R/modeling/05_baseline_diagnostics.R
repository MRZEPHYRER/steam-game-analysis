# Produce the frozen Step 5B diagnostics, figures, and human-readable report.

if (!exists("baseline_fit")) {
  stop("Run 04_baseline_binomial.R before 05_baseline_diagnostics.R.", call. = FALSE)
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing R package: ggplot2", call. = FALSE)
}
if (!requireNamespace("car", quietly = TRUE)) {
  stop("Missing R package: car", call. = FALSE)
}

quantile_row <- function(type, values) {
  probs <- c(0, 0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99, 1)
  q <- stats::quantile(values, probs = probs, na.rm = TRUE, names = FALSE)
  data.frame(
    residual_type = type,
    min = q[1], p01 = q[2], p05 = q[3], p25 = q[4], median = q[5],
    p75 = q[6], p95 = q[7], p99 = q[8], max = q[9],
    stringsAsFactors = FALSE
  )
}

genre_labels <- genre_long_model |>
  dplyr::group_by(appid) |>
  dplyr::summarise(genres = paste(sort(unique(genre_name)), collapse = "; "), .groups = "drop")

fitted_probability <- stats::fitted(baseline_fit)
linear_predictor <- stats::predict(baseline_fit, type = "link")
pearson_residual <- stats::residuals(baseline_fit, type = "pearson")
deviance_residual <- stats::residuals(baseline_fit, type = "deviance")
standardized_pearson <- stats::rstandard(baseline_fit, type = "pearson")
standardized_deviance <- stats::rstandard(baseline_fit, type = "deviance")
hat_value <- stats::hatvalues(baseline_fit)
cooks_d <- stats::cooks.distance(baseline_fit)

stopifnot(
  all(is.finite(fitted_probability)),
  all(fitted_probability > 0 & fitted_probability < 1),
  all(is.finite(pearson_residual)),
  all(is.finite(deviance_residual)),
  all(is.finite(standardized_pearson)),
  all(is.finite(standardized_deviance)),
  all(is.finite(hat_value)),
  all(hat_value >= 0 & hat_value <= 1),
  all(is.finite(cooks_d)),
  all(cooks_d >= 0)
)

diagnostic_games <- model20_paid_baseline |>
  dplyr::select(
    appid, name, total_reviews, positive_reviews, negative_reviews,
    positive_rate, current_price_usd, days_since_release, platform_segment
  ) |>
  dplyr::left_join(genre_labels, by = "appid") |>
  dplyr::mutate(
    fitted_probability = fitted_probability,
    linear_predictor = linear_predictor,
    pearson_residual = pearson_residual,
    deviance_residual = deviance_residual,
    standardized_pearson_residual = standardized_pearson,
    standardized_deviance_residual = standardized_deviance,
    hat_value = hat_value,
    cooks_distance = cooks_d,
    platform = as.character(platform_segment)
  )

pearson_chisq <- sum(pearson_residual^2)
residual_df <- stats::df.residual(baseline_fit)
dispersion_diagnostics <- data.frame(
  pearson_chi_square = pearson_chisq,
  residual_df = residual_df,
  pearson_dispersion_ratio = pearson_chisq / residual_df,
  residual_deviance = baseline_fit$deviance,
  deviance_dispersion_ratio = baseline_fit$deviance / residual_df,
  overdispersion_flag = (pearson_chisq / residual_df) > 1.5 ||
    (baseline_fit$deviance / residual_df) > 1.5,
  flag_reference = "ratio > 1.5 used as a material diagnostic flag; ratio > 1 indicates overdispersion",
  stringsAsFactors = FALSE
)
write_model_audit(dispersion_diagnostics, "step5b_dispersion_diagnostics.csv")

residual_summary <- dplyr::bind_rows(
  quantile_row("Pearson", pearson_residual),
  quantile_row("Deviance", deviance_residual),
  quantile_row("Standardized Pearson", standardized_pearson),
  quantile_row("Standardized deviance", standardized_deviance)
)
write_model_audit(residual_summary, "step5b_residual_summary.csv")

residual_threshold_counts <- data.frame(
  threshold = c(2, 3, 4),
  n_games = vapply(c(2, 3, 4), function(x) sum(abs(standardized_deviance) > x), integer(1)),
  stringsAsFactors = FALSE
) |>
  dplyr::mutate(share_games = n_games / nrow(diagnostic_games))
write_model_audit(residual_threshold_counts, "step5b_large_residual_counts.csv")

top_residuals <- diagnostic_games |>
  dplyr::mutate(
    residual = deviance_residual,
    standardized_residual = standardized_deviance,
    absolute_standardized_residual = abs(standardized_deviance)
  ) |>
  dplyr::arrange(dplyr::desc(absolute_standardized_residual), appid) |>
  dplyr::slice_head(n = 20) |>
  dplyr::select(
    appid, name, total_reviews, positive_reviews, negative_reviews,
    positive_rate, fitted_probability, residual, standardized_residual,
    current_price_usd, days_since_release, platform, genres
  )
write_model_audit(top_residuals, "step5b_top_residuals.csv")

p_count <- length(stats::coef(baseline_fit))
n_games <- nrow(diagnostic_games)
leverage_2pn <- 2 * p_count / n_games
leverage_3pn <- 3 * p_count / n_games
leverage_summary <- data.frame(
  min = min(hat_value),
  median = stats::median(hat_value),
  mean = mean(hat_value),
  p95 = as.numeric(stats::quantile(hat_value, 0.95)),
  p99 = as.numeric(stats::quantile(hat_value, 0.99)),
  max = max(hat_value),
  parameter_count = p_count,
  n_games = n_games,
  threshold_2p_over_n = leverage_2pn,
  n_above_2p_over_n = sum(hat_value > leverage_2pn),
  share_above_2p_over_n = mean(hat_value > leverage_2pn),
  threshold_3p_over_n = leverage_3pn,
  n_above_3p_over_n = sum(hat_value > leverage_3pn),
  share_above_3p_over_n = mean(hat_value > leverage_3pn),
  stringsAsFactors = FALSE
)
write_model_audit(leverage_summary, "step5b_leverage_summary.csv")

top_leverage <- diagnostic_games |>
  dplyr::arrange(dplyr::desc(hat_value), appid) |>
  dplyr::slice_head(n = 20) |>
  dplyr::select(
    appid, name, total_reviews, positive_reviews, negative_reviews,
    positive_rate, fitted_probability, standardized_deviance_residual,
    current_price_usd, days_since_release, platform, genres, hat_value
  )
names(top_leverage)[names(top_leverage) == "standardized_deviance_residual"] <- "standardized_residual"
write_model_audit(top_leverage, "step5b_top_leverage.csv")

cooks_threshold <- 4 / n_games
cooks_summary <- data.frame(
  min = min(cooks_d),
  median = stats::median(cooks_d),
  p95 = as.numeric(stats::quantile(cooks_d, 0.95)),
  p99 = as.numeric(stats::quantile(cooks_d, 0.99)),
  max = max(cooks_d),
  threshold_4_over_n = cooks_threshold,
  n_above_4_over_n = sum(cooks_d > cooks_threshold),
  share_above_4_over_n = mean(cooks_d > cooks_threshold),
  n_above_0_5 = sum(cooks_d > 0.5),
  share_above_0_5 = mean(cooks_d > 0.5),
  n_above_1 = sum(cooks_d > 1),
  share_above_1 = mean(cooks_d > 1),
  stringsAsFactors = FALSE
)
write_model_audit(cooks_summary, "step5b_cooks_summary.csv")

top_influence <- diagnostic_games |>
  dplyr::arrange(dplyr::desc(cooks_distance), appid) |>
  dplyr::slice_head(n = 20) |>
  dplyr::select(
    appid, name, total_reviews, positive_rate, fitted_probability,
    cooks_distance, hat_value, standardized_deviance_residual,
    current_price_usd, days_since_release, platform, genres
  )
names(top_influence)[names(top_influence) == "standardized_deviance_residual"] <- "standardized_residual"
write_model_audit(top_influence, "step5b_top_influence.csv")

review_leverage_cor <- stats::cor(
  diagnostic_games$total_reviews, diagnostic_games$hat_value,
  method = "spearman"
)
review_cooks_cor <- stats::cor(
  diagnostic_games$total_reviews, diagnostic_games$cooks_distance,
  method = "spearman"
)
top_review_games <- diagnostic_games |>
  dplyr::arrange(dplyr::desc(total_reviews), appid) |>
  dplyr::slice_head(n = 20)
overlap_games <- dplyr::inner_join(
  top_review_games |>
    dplyr::select(appid, name, total_reviews),
  top_influence |>
    dplyr::select(appid, cooks_distance),
  by = "appid"
)
review_influence_association <- data.frame(
  metric = c(
    "Spearman total_reviews vs leverage",
    "Spearman total_reviews vs Cook's D",
    "Top-20 review volume and top-20 Cook's D overlap count",
    "Top-20 review volume and top-20 Cook's D overlap share"
  ),
  value = c(
    review_leverage_cor, review_cooks_cor, nrow(overlap_games), nrow(overlap_games) / 20
  ),
  reference = c("Spearman rho", "Spearman rho", "games", "share of top 20"),
  stringsAsFactors = FALSE
)
write_model_audit(
  review_influence_association,
  "step5b_review_influence_association.csv"
)
write_model_audit(overlap_games, "step5b_review_influence_overlap.csv")

vif_raw <- car::vif(baseline_fit)
if (is.matrix(vif_raw)) {
  collinearity <- data.frame(
    term = rownames(vif_raw),
    vif_or_gvif = vif_raw[, "GVIF"],
    df = vif_raw[, "Df"],
    adjusted_gvif = vif_raw[, "GVIF^(1/(2*Df))"],
    stringsAsFactors = FALSE,
    row.names = NULL
  )
} else {
  collinearity <- data.frame(
    term = names(vif_raw),
    vif_or_gvif = as.numeric(vif_raw),
    df = 1,
    adjusted_gvif = sqrt(as.numeric(vif_raw)),
    stringsAsFactors = FALSE
  )
}
write_model_audit(collinearity, "step5b_collinearity.csv")

fitted_probs <- fitted_probability
fitted_probability_summary <- data.frame(
  min = min(fitted_probs),
  p01 = as.numeric(stats::quantile(fitted_probs, 0.01)),
  p05 = as.numeric(stats::quantile(fitted_probs, 0.05)),
  p25 = as.numeric(stats::quantile(fitted_probs, 0.25)),
  median = stats::median(fitted_probs),
  p75 = as.numeric(stats::quantile(fitted_probs, 0.75)),
  p95 = as.numeric(stats::quantile(fitted_probs, 0.95)),
  p99 = as.numeric(stats::quantile(fitted_probs, 0.99)),
  max = max(fitted_probs),
  mean = mean(fitted_probs),
  n_below_0_001 = sum(fitted_probs < 0.001),
  n_above_0_999 = sum(fitted_probs > 0.999),
  stringsAsFactors = FALSE
)
write_model_audit(
  fitted_probability_summary,
  "step5b_fitted_probability_summary.csv"
)

calibration_deciles <- diagnostic_games |>
  dplyr::arrange(fitted_probability, appid) |>
  dplyr::mutate(decile = dplyr::ntile(fitted_probability, 10)) |>
  dplyr::group_by(decile) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    total_reviews = sum(total_reviews),
    mean_fitted_probability = mean(fitted_probability),
    pooled_observed_positive_rate = sum(positive_reviews) / sum(total_reviews),
    median_game_positive_rate = stats::median(positive_rate),
    .groups = "drop"
  )
write_model_audit(calibration_deciles, "step5b_calibration_deciles.csv")

large_terms <- coefficient_table |>
  dplyr::filter(abs(estimate_log_odds) > 10 | std_error > 10)
separation_diagnostics <- data.frame(
  check = c(
    "fitted_probability_below_1e-6",
    "fitted_probability_above_1_minus_1e-6",
    "coefficient_abs_gt_10_or_se_gt_10",
    "glm_converged"
  ),
  n_flagged = c(
    sum(fitted_probs < 1e-6),
    sum(fitted_probs > 1 - 1e-6),
    nrow(large_terms),
    as.integer(!isTRUE(baseline_fit$converged))
  ),
  details = c(
    "Potential separation/extreme fit heuristic",
    "Potential separation/extreme fit heuristic",
    if (nrow(large_terms) == 0) "none" else paste(large_terms$term, collapse = "; "),
    paste("converged =", baseline_fit$converged)
  ),
  stringsAsFactors = FALSE
)
write_model_audit(separation_diagnostics, "step5b_separation_diagnostics.csv")

warning_rows <- list()
if (length(fit_warnings) > 0) {
  warning_rows[[length(warning_rows) + 1]] <- data.frame(
    stage = "glm fit", status = "WARNING", warning_text = unique(fit_warnings)
  )
} else {
  warning_rows[[length(warning_rows) + 1]] <- data.frame(
    stage = "glm fit", status = "NO WARNING", warning_text = ""
  )
}
if (length(profile_warnings) > 0) {
  warning_rows[[length(warning_rows) + 1]] <- data.frame(
    stage = "profile likelihood CI", status = "WARNING",
    warning_text = unique(profile_warnings)
  )
} else if (nzchar(profile_error)) {
  warning_rows[[length(warning_rows) + 1]] <- data.frame(
    stage = "profile likelihood CI", status = "FAILED", warning_text = profile_error
  )
} else {
  warning_rows[[length(warning_rows) + 1]] <- data.frame(
    stage = "profile likelihood CI", status = "NO WARNING", warning_text = ""
  )
}
fit_warning_table <- dplyr::bind_rows(warning_rows)
write_model_audit(fit_warning_table, "step5b_fit_warnings.csv")

plot_theme <- ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.title.position = "plot",
    plot.caption.position = "plot"
  )

calibration_plot <- ggplot2::ggplot(
  calibration_deciles,
  ggplot2::aes(mean_fitted_probability, pooled_observed_positive_rate)
) +
  ggplot2::geom_abline(slope = 1, intercept = 0, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_line(colour = "#2C6E9B", linewidth = 0.8) +
  ggplot2::geom_point(colour = "#2C6E9B", size = 2.4) +
  ggplot2::coord_equal() +
  ggplot2::labs(
    title = "Baseline binomial calibration by fitted-probability decile",
    subtitle = "Descriptive check only; observed rates pool review counts within each decile",
    x = "Mean fitted positive probability",
    y = "Pooled observed positive rate"
  ) + plot_theme
ggplot2::ggsave(
  file.path(model_figure_dir, "01_baseline_calibration.png"),
  calibration_plot, width = 7.2, height = 5.8, dpi = 180
)

residual_plot <- ggplot2::ggplot(
  diagnostic_games,
  ggplot2::aes(fitted_probability, standardized_deviance_residual)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.6) +
  ggplot2::geom_point(alpha = 0.48, size = 1.4, colour = "#2C6E9B") +
  ggplot2::geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
                       colour = "#B04A3A", linewidth = 0.8) +
  ggplot2::labs(
    title = "Standardized deviance residuals versus fitted probability",
    x = "Fitted positive probability",
    y = "Standardized deviance residual"
  ) + plot_theme
ggplot2::ggsave(
  file.path(model_figure_dir, "02_residuals_vs_fitted.png"),
  residual_plot, width = 7.8, height = 5.8, dpi = 180
)

influence_plot <- ggplot2::ggplot(
  diagnostic_games,
  ggplot2::aes(total_reviews, cooks_distance)
) +
  ggplot2::geom_hline(
    yintercept = cooks_threshold, colour = "#B04A3A", linetype = "dashed", linewidth = 0.7
  ) +
  ggplot2::geom_point(alpha = 0.52, size = 1.5, colour = "#2C6E9B") +
  ggplot2::scale_x_log10(labels = scales::label_comma()) +
  ggplot2::scale_y_log10(labels = scales::label_scientific(digits = 2)) +
  ggplot2::labs(
    title = "Review volume and Cook's distance",
    subtitle = sprintf("Dashed line marks 4/n = %.5f; all games retained", cooks_threshold),
    x = "Total reviews (log10 scale)",
    y = "Cook's distance (log10 scale)"
  ) + plot_theme
ggplot2::ggsave(
  file.path(model_figure_dir, "03_influence_review_volume.png"),
  influence_plot, width = 7.8, height = 5.8, dpi = 180
)

or_plot_data <- coefficient_table |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::mutate(
    term_label = dplyr::recode(
      term,
      z_log1p_price = "+1 SD log1p price",
      z_days_since_release = "+1 SD days since release",
      `platform_segmentWindows + macOS` = "Windows + macOS vs Windows only",
      `platform_segmentWindows + Linux` = "Windows + Linux vs Windows only",
      `platform_segmentWindows + macOS + Linux` = "All three vs Windows only",
      genre_action = "Action present vs absent",
      genre_adventure = "Adventure present vs absent",
      genre_casual = "Casual present vs absent",
      genre_indie = "Indie present vs absent",
      genre_rpg = "RPG present vs absent",
      genre_simulation = "Simulation present vs absent",
      genre_strategy = "Strategy present vs absent"
    ),
    term_label = factor(term_label, levels = rev(term_label))
  )
or_plot <- ggplot2::ggplot(
  or_plot_data,
  ggplot2::aes(odds_ratio, term_label)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.18, colour = "#2C6E9B"
  ) +
  ggplot2::geom_point(size = 2.2, colour = "#2C6E9B") +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "Baseline binomial odds ratios",
    subtitle = "Wald 95% confidence intervals; standardized numeric predictors represent +1 SD",
    x = "Odds ratio (log scale)",
    y = NULL
  ) + plot_theme
ggplot2::ggsave(
  file.path(model_figure_dir, "04_baseline_odds_ratios.png"),
  or_plot, width = 8.4, height = 6.4, dpi = 180
)

fmt <- function(x, digits = 4) formatC(x, digits = digits, format = "f", big.mark = ",")
fit_row <- model_fit_summary[1, ]
disp_row <- dispersion_diagnostics[1, ]
lev_row <- leverage_summary[1, ]
cook_row <- cooks_summary[1, ]
prob_row <- fitted_probability_summary[1, ]
profile_max_difference <- if (all(profile_ci$status == "PASS")) {
  merged_ci <- dplyr::left_join(coefficient_table, profile_ci, by = "term")
  max(abs(c(
    merged_ci$or_ci95_lower - merged_ci$profile_or_ci95_lower,
    merged_ci$or_ci95_upper - merged_ci$profile_or_ci95_upper
  )), na.rm = TRUE)
} else {
  NA_real_
}
coefficient_report_rows <- coefficient_table |>
  dplyr::filter(term != "(Intercept)")
coefficient_report_lines <- c(
  "| Term | OR | Wald 95% CI | Estimate (log odds) | SE | p-value |",
  "|---|---:|---:|---:|---:|---:|",
  vapply(seq_len(nrow(coefficient_report_rows)), function(i) {
    row <- coefficient_report_rows[i, ]
    paste0(
      "| `", row$term, "` | ", fmt(row$odds_ratio, 4), " | ",
      fmt(row$or_ci95_lower, 4), " to ", fmt(row$or_ci95_upper, 4), " | ",
      fmt(row$estimate_log_odds, 4), " | ", fmt(row$std_error, 4), " | ",
      format(row$p_value, digits = 4, scientific = TRUE), " |"
    )
  }, character(1))
)
ci_crossing_terms <- coefficient_report_rows$term[
  coefficient_report_rows$or_ci95_lower <= 1 & coefficient_report_rows$or_ci95_upper >= 1
]
top_influence_report_lines <- c(
  "| AppID | Game | Total reviews | Cook's D | Leverage | Std. deviance residual |",
  "|---:|---|---:|---:|---:|---:|",
  vapply(seq_len(min(10, nrow(top_influence))), function(i) {
    row <- top_influence[i, ]
    paste0(
      "| ", row$appid, " | ", gsub("\\|", "\\\\|", row$name), " | ",
      format(row$total_reviews, big.mark = ","), " | ", fmt(row$cooks_distance, 4),
      " | ", fmt(row$hat_value, 4), " | ", fmt(row$standardized_residual, 3), " |"
    )
  }, character(1))
)
calibration_gap <- calibration_deciles$pooled_observed_positive_rate -
  calibration_deciles$mean_fitted_probability
max_calibration_gap_index <- which.max(abs(calibration_gap))

report_lines <- c(
  "# Step 5B Baseline Binomial Modeling & Diagnostics",
  "",
  "## 1. Frozen specification",
  "",
  paste0("Primary population: `model20_paid` (total_reviews >= 20, paid games), N = ", fit_row$n_games, "."),
  "Response: `cbind(positive_reviews, negative_reviews)`; family: `binomial(link = logit)`.",
  paste0("Formula: `", fit_row$formula, "`. No rows were removed after the frozen sample was formed."),
  "",
  "## 2. Analysis population and response totals",
  "",
  paste0("The sample has ", fit_row$n_games, " unique games and ", format(fit_row$response_trials, big.mark = ","), " review trials: ",
         format(fit_row$total_positive_reviews, big.mark = ","), " positive and ",
         format(fit_row$total_negative_reviews, big.mark = ","), " negative. The pooled positive rate is ",
         fmt(100 * fit_row$pooled_positive_rate, 2), "%. All response identities and required non-missingness checks passed."),
  "",
  "## 3. Scaling parameters",
  "",
  paste0("`log1p(current_price_usd)` mean = ", fmt(price_log_mean), ", SD = ", fmt(price_log_sd),
         "; back-transformed -1 SD / mean / +1 SD prices are $",
         fmt(scaling_parameters$minus_1sd_original[1], 2), " / $",
         fmt(scaling_parameters$mean_original[1], 2), " / $",
         fmt(scaling_parameters$plus_1sd_original[1], 2), "."),
  paste0("Days since release mean = ", fmt(days_mean, 2), ", SD = ", fmt(days_sd, 2),
         "; mean -1 SD / mean / mean +1 SD are ",
         fmt(scaling_parameters$minus_1sd_original[2], 2), " / ", fmt(days_mean, 2), " / ",
         fmt(scaling_parameters$plus_1sd_original[2], 2), " days."),
  "",
  "## 4. Model fit",
  "",
  paste0("Converged = ", fit_row$converged, " in ", fit_row$iterations, " iterations; coefficients = ",
         fit_row$number_of_coefficients, "; residual df = ", fit_row$residual_df, "."),
  paste0("logLik = ", fmt(fit_row$log_likelihood, 3), "; AIC = ", fmt(fit_row$aic, 3),
         "; BIC = ", fmt(fit_row$bic, 3), "; null deviance = ", fmt(fit_row$null_deviance, 3),
         "; residual deviance = ", fmt(fit_row$residual_deviance, 3), ". AIC/BIC describe the frozen likelihood fit and are not used for variable selection."),
  "",
  "## 5. Coefficients, odds ratios, and intervals",
  "",
  "The complete log-odds, standard-error, z, p-value, Wald CI, OR, and OR-CI audit is in `step5b_coefficients.csv`. Numeric ORs are per +1 SD, not per $1 or per day. Platform contrasts use Windows only; genre contrasts use genre absent.",
  paste0("Profile-likelihood CI status = ", fit_row$profile_ci_status,
         if (is.finite(profile_max_difference)) paste0("; maximum absolute endpoint difference from the Wald OR CI = ", fmt(profile_max_difference, 4), ".") else "."),
  paste0("Terms whose Wald OR interval crosses 1: ",
         if (length(ci_crossing_terms) == 0) "none" else paste(ci_crossing_terms, collapse = ", "), "."),
  "",
  coefficient_report_lines,
  "",
  "## 6. Predicted-probability interpretation",
  "",
  paste0("At both standardized numeric predictors = 0, Windows only, and all seven genre indicators absent, the fitted positive probability is ",
         fmt(baseline_probability, 4), ". Each one-at-a-time contrast is exported in `step5b_predicted_effects.csv`; these are descriptive model contrasts, not causal effects."),
  "",
  "## 7. Overdispersion diagnostics",
  "",
  paste0("Pearson chi-square = ", fmt(disp_row$pearson_chi_square, 3), ", residual df = ", residual_df,
         ", Pearson dispersion = ", fmt(disp_row$pearson_dispersion_ratio, 3), ". Residual deviance/df = ",
         fmt(disp_row$deviance_dispersion_ratio, 3), ". Material overdispersion flag = ", disp_row$overdispersion_flag,
         " using ratio > 1.5 as the reporting threshold. The family was not changed."),
  "",
  "## 8. Residual diagnostics",
  "",
  paste0("Absolute standardized deviance residual counts: >2 = ", residual_threshold_counts$n_games[1],
         " (", fmt(100 * residual_threshold_counts$share_games[1], 2), "%), >3 = ", residual_threshold_counts$n_games[2],
         " (", fmt(100 * residual_threshold_counts$share_games[2], 2), "%), >4 = ", residual_threshold_counts$n_games[3],
         " (", fmt(100 * residual_threshold_counts$share_games[3], 2), "%). Full quantiles and the top 20 games are exported."),
  "",
  "## 9. Leverage",
  "",
  paste0("Hat values: mean = ", fmt(lev_row$mean, 5), ", 95th = ", fmt(lev_row$p95, 5),
         ", 99th = ", fmt(lev_row$p99, 5), ", max = ", fmt(lev_row$max, 5), ". The 2p/n threshold is ",
         fmt(lev_row$threshold_2p_over_n, 5), " with ", lev_row$n_above_2p_over_n, " games (",
         fmt(100 * lev_row$share_above_2p_over_n, 2), "%) above it; 3p/n is ",
         fmt(lev_row$threshold_3p_over_n, 5), " with ", lev_row$n_above_3p_over_n, " games (",
         fmt(100 * lev_row$share_above_3p_over_n, 2), "%) above it."),
  "",
  "## 10. Influence and review-volume concentration",
  "",
  paste0("Cook's D: 95th = ", fmt(cook_row$p95, 6), ", 99th = ", fmt(cook_row$p99, 6),
         ", max = ", fmt(cook_row$max, 6), ". The 4/n threshold is ", fmt(cook_row$threshold_4_over_n, 6),
         "; ", cook_row$n_above_4_over_n, " games (", fmt(100 * cook_row$share_above_4_over_n, 2),
         "%) exceed it; >0.5 = ", cook_row$n_above_0_5, "; >1 = ", cook_row$n_above_1, "."),
  paste0("Spearman rho(total reviews, leverage) = ", fmt(review_leverage_cor, 4),
         "; rho(total reviews, Cook's D) = ", fmt(review_cooks_cor, 4), ". The top-20 volume and top-20 Cook's D lists overlap by ",
         nrow(overlap_games), " games."),
  "Step 5A established that the top 1%, 5%, and 10% of games contribute about 49.98%, 77.24%, and 86.42% of all reviews. Grouped binomial likelihood naturally gives high-volume games more Bernoulli information; the dispersion and influence results show whether that nominal information leads to overconfident or concentrated inference.",
  "",
  "The ten largest Cook's distances are:",
  "",
  top_influence_report_lines,
  "",
  "## 11. Collinearity and model matrix",
  "",
  paste0("Maximum adjusted GVIF = ", fmt(max(collinearity$adjusted_gvif), 4),
         ". The actual model matrix has ", baseline_matrix_diagnostics$matrix_rows, " rows, ",
         baseline_matrix_diagnostics$matrix_columns, " columns, rank ", baseline_matrix_diagnostics$matrix_rank,
         ", exact dependencies = ", baseline_matrix_diagnostics$exact_dependencies,
         ", and condition number = ", fmt(baseline_matrix_diagnostics$condition_number, 4), "."),
  "",
  "## 12. Separation, convergence, and warnings",
  "",
  paste0("Fitted probabilities range from ", fmt(prob_row$min, 6), " to ", fmt(prob_row$max, 6),
         "; below 0.001 = ", prob_row$n_below_0_001, ", above 0.999 = ", prob_row$n_above_0_999,
         ". Extreme-fit heuristic coefficient count = ", nrow(large_terms), ". GLM warning count = ", length(fit_warnings),
         "; profile-CI warning count = ", length(profile_warnings), ". Warning text is preserved in `step5b_fit_warnings.csv`."),
  "",
  "## 13. Calibration-style descriptive check",
  "",
  paste0("Ten fitted-probability groups contain ", paste(calibration_deciles$n_games, collapse = "/"),
         " games. The largest absolute pooled observed-minus-fitted gap is ",
         fmt(abs(calibration_gap[max_calibration_gap_index]), 4), " in decile ",
         calibration_deciles$decile[max_calibration_gap_index], " (signed gap = ",
         fmt(calibration_gap[max_calibration_gap_index], 4), "). Their pooled observed rates are exported with mean fitted probabilities and median game rates. This is a descriptive in-sample check, not formal validation."),
  "",
  "## 14. Baseline limitations and Step 5C recommendation",
  "",
  if (disp_row$overdispersion_flag) {
    paste0("The baseline binomial shows meaningful overdispersion/influence concerns: Pearson dispersion = ",
           fmt(disp_row$pearson_dispersion_ratio, 3), " and deviance/df = ",
           fmt(disp_row$deviance_dispersion_ratio, 3), ". Standard binomial standard errors therefore appear overconfident. Step 5C should compare quasi-binomial and beta-binomial inference and perform influence sensitivity; it should also assess the pre-specified alternative release-month and review-threshold specifications. No robustness model is fit here.")
  } else {
    paste0("The baseline binomial is diagnostically acceptable at this stage (Pearson dispersion = ",
           fmt(disp_row$pearson_dispersion_ratio, 3), "; deviance/df = ",
           fmt(disp_row$deviance_dispersion_ratio, 3), "). Step 5C should still perform the pre-specified robustness checks before declaring a final inferential model. No robustness model is fit here.")
  },
  "",
  "## 15. Figures",
  "",
  "- `figures/modeling/01_baseline_calibration.png`",
  "- `figures/modeling/02_residuals_vs_fitted.png`",
  "- `figures/modeling/03_influence_review_volume.png`",
  "- `figures/modeling/04_baseline_odds_ratios.png`",
  "",
  "All database access used the existing read-only SELECT path. Before/after object counts are identical in `step5b_database_preservation.csv`. No credentials are written to outputs."
)
writeLines(report_lines, file.path(project_root, "reports", "step5b_baseline_binomial_report.md"), useBytes = TRUE)

message(sprintf(
  "Step 5B diagnostics: PASS (Pearson dispersion=%.3f, Cook max=%.5f)",
  dispersion_diagnostics$pearson_dispersion_ratio,
  cooks_summary$max
))
