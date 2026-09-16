# Diagnose the Step 5E primary HIGH85 game-level logistic model.

if (!exists("primary_high_rating_fit")) {
  stop("Run 10_high_rating_logistic.R before 11_high_rating_diagnostics.R.", call. = FALSE)
}

primary_fitted <- stats::fitted(primary_high_rating_fit)
primary_std_deviance <- stats::rstandard(primary_high_rating_fit, type = "deviance")
primary_leverage <- stats::hatvalues(primary_high_rating_fit)
primary_cooks_d <- stats::cooks.distance(primary_high_rating_fit)

stopifnot(
  length(primary_fitted) == 836,
  all(is.finite(primary_fitted)),
  all(primary_fitted > 0 & primary_fitted < 1),
  all(is.finite(primary_std_deviance)),
  all(is.finite(primary_leverage)),
  all(primary_leverage >= 0 & primary_leverage <= 1),
  all(is.finite(primary_cooks_d)),
  all(primary_cooks_d >= 0)
)

genre_labels_5e <- genre_long_model |>
  dplyr::group_by(appid) |>
  dplyr::summarise(
    genres = paste(sort(unique(genre_name)), collapse = "; "),
    .groups = "drop"
  )

high_rating_diagnostic_games <- primary_high_rating_data |>
  dplyr::select(
    appid, name, positive_rate, total_reviews, high_rating,
    current_price_usd, platform_segment
  ) |>
  dplyr::left_join(genre_labels_5e, by = "appid") |>
  dplyr::mutate(
    high_rating_85 = as.integer(high_rating),
    fitted_probability = primary_fitted,
    standardized_residual = primary_std_deviance,
    leverage = primary_leverage,
    cooks_distance = primary_cooks_d,
    price = current_price_usd,
    platform = as.character(platform_segment)
  )

parameter_count_5e <- length(stats::coef(primary_high_rating_fit))
n_games_5e <- nrow(high_rating_diagnostic_games)
leverage_2pn_5e <- 2 * parameter_count_5e / n_games_5e
leverage_3pn_5e <- 3 * parameter_count_5e / n_games_5e
cooks_4n_5e <- 4 / n_games_5e

influence_summary <- data.frame(
  n_games = n_games_5e,
  parameter_count = parameter_count_5e,
  max_absolute_standardized_deviance_residual = max(abs(primary_std_deviance)),
  n_absolute_standardized_residual_gt_2 = sum(abs(primary_std_deviance) > 2),
  n_absolute_standardized_residual_gt_3 = sum(abs(primary_std_deviance) > 3),
  max_leverage = max(primary_leverage),
  threshold_2p_over_n = leverage_2pn_5e,
  n_leverage_above_2p_over_n = sum(primary_leverage > leverage_2pn_5e),
  threshold_3p_over_n = leverage_3pn_5e,
  n_leverage_above_3p_over_n = sum(primary_leverage > leverage_3pn_5e),
  max_cooks_distance = max(primary_cooks_d),
  threshold_4_over_n = cooks_4n_5e,
  n_cooks_above_4_over_n = sum(primary_cooks_d > cooks_4n_5e),
  n_cooks_above_0_5 = sum(primary_cooks_d > 0.5),
  n_cooks_above_1 = sum(primary_cooks_d > 1),
  stringsAsFactors = FALSE
)
write_model_audit(influence_summary, "step5e_influence_summary.csv")

top_influence_5e <- high_rating_diagnostic_games |>
  dplyr::arrange(dplyr::desc(cooks_distance), appid) |>
  dplyr::slice_head(n = 20) |>
  dplyr::select(
    appid, name, positive_rate, total_reviews, high_rating_85,
    fitted_probability, standardized_residual, leverage, cooks_distance,
    price, platform, genres
  )
write_model_audit(top_influence_5e, "step5e_top_influence.csv")

residual_diagnostics_5e <- data.frame(
  min = min(primary_std_deviance),
  p01 = as.numeric(stats::quantile(primary_std_deviance, 0.01)),
  p05 = as.numeric(stats::quantile(primary_std_deviance, 0.05)),
  median = stats::median(primary_std_deviance),
  p95 = as.numeric(stats::quantile(primary_std_deviance, 0.95)),
  p99 = as.numeric(stats::quantile(primary_std_deviance, 0.99)),
  max = max(primary_std_deviance),
  stringsAsFactors = FALSE
)
write_model_audit(residual_diagnostics_5e, "step5e_residual_diagnostics.csv")

summarise_binary_level <- function(variable, display_name) {
  primary_high_rating_data |>
    dplyr::mutate(
      level = ifelse(.data[[variable]] == 1L, "present", "absent")
    ) |>
    dplyr::group_by(level) |>
    dplyr::summarise(
      n_games = dplyr::n(),
      high_rated_n = sum(high_rating == 1L),
      high_rated_percent = mean(high_rating == 1L) * 100,
      not_high_rated_n = sum(high_rating == 0L),
      not_high_rated_percent = mean(high_rating == 0L) * 100,
      .groups = "drop"
    ) |>
    dplyr::mutate(predictor = display_name, .before = 1)
}

platform_level_outcomes <- primary_high_rating_data |>
  dplyr::mutate(level = as.character(platform_segment)) |>
  dplyr::group_by(level) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    high_rated_n = sum(high_rating == 1L),
    high_rated_percent = mean(high_rating == 1L) * 100,
    not_high_rated_n = sum(high_rating == 0L),
    not_high_rated_percent = mean(high_rating == 0L) * 100,
    .groups = "drop"
  ) |>
  dplyr::mutate(predictor = "platform_segment", .before = 1)

genre_level_outcomes <- dplyr::bind_rows(lapply(
  high_rating_genres,
  function(genre) summarise_binary_level(genre, genre)
))
predictor_level_outcomes <- dplyr::bind_rows(
  platform_level_outcomes, genre_level_outcomes
)
write_model_audit(
  predictor_level_outcomes,
  "step5e_predictor_level_outcomes.csv"
)

sparse_outcome_cells <- predictor_level_outcomes |>
  dplyr::mutate(
    zero_event_cell = high_rated_n == 0,
    zero_non_event_cell = not_high_rated_n == 0,
    cell_n_below_10 = n_games < 10
  )
write_model_audit(sparse_outcome_cells, "step5e_sparse_outcome_cells.csv")

large_terms_5e <- primary_high_rating_coefficients |>
  dplyr::filter(abs(estimate_log_odds) > 10 | std_error > 10)
separation_diagnostics_5e <- data.frame(
  check = c(
    "glm_not_converged",
    "rank_deficient_model_matrix",
    "absolute_coefficient_gt_10_or_se_gt_10",
    "fitted_probability_below_1e_6",
    "fitted_probability_above_1_minus_1e_6",
    "platform_or_genre_zero_event_cell",
    "platform_or_genre_zero_non_event_cell",
    "glm_warning"
  ),
  n_flagged = c(
    as.integer(!isTRUE(primary_high_rating_fit$converged)),
    as.integer(primary_high_rating_fit_summary$matrix_rank !=
      primary_high_rating_fit_summary$matrix_columns),
    nrow(large_terms_5e),
    sum(primary_fitted < 1e-6),
    sum(primary_fitted > 1 - 1e-6),
    sum(sparse_outcome_cells$zero_event_cell),
    sum(sparse_outcome_cells$zero_non_event_cell),
    primary_high_rating_fit_summary$warning_count
  ),
  details = c(
    paste("converged =", primary_high_rating_fit$converged),
    paste(
      "rank =", primary_high_rating_fit_summary$matrix_rank,
      "of", primary_high_rating_fit_summary$matrix_columns
    ),
    if (nrow(large_terms_5e) == 0) "none" else paste(
      large_terms_5e$term, collapse = "; "
    ),
    "Heuristic for complete or quasi-separation",
    "Heuristic for complete or quasi-separation",
    "Categorical outcome cross-tab audit",
    "Categorical outcome cross-tab audit",
    paste("warning count =", primary_high_rating_fit_summary$warning_count)
  ),
  stringsAsFactors = FALSE
)
write_model_audit(
  separation_diagnostics_5e,
  "step5e_separation_diagnostics.csv"
)

calibration_deciles_5e <- high_rating_diagnostic_games |>
  dplyr::arrange(fitted_probability, appid) |>
  dplyr::mutate(decile = dplyr::ntile(fitted_probability, 10)) |>
  dplyr::group_by(decile) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    mean_predicted_probability = mean(fitted_probability),
    observed_high_rating_proportion = mean(high_rating_85),
    absolute_gap = abs(
      observed_high_rating_proportion - mean_predicted_probability
    ),
    .groups = "drop"
  )
write_model_audit(
  calibration_deciles_5e,
  "step5e_calibration_deciles.csv"
)

auc_delong <- function(outcome, score) {
  positive_scores <- score[outcome == 1L]
  negative_scores <- score[outcome == 0L]
  comparison <- outer(
    positive_scores, negative_scores,
    function(pos, neg) (pos > neg) + 0.5 * (pos == neg)
  )
  v_positive <- rowMeans(comparison)
  v_negative <- colMeans(comparison)
  auc <- mean(v_positive)
  standard_error <- sqrt(
    stats::var(v_positive) / length(v_positive) +
      stats::var(v_negative) / length(v_negative)
  )
  lower <- max(0, auc - stats::qnorm(0.975) * standard_error)
  upper <- min(1, auc + stats::qnorm(0.975) * standard_error)
  data.frame(
    auc = auc,
    standard_error = standard_error,
    ci95_lower = lower,
    ci95_upper = upper,
    ci_method = "DeLong placement-value normal approximation",
    diagnostic_scope = paste(
      "In-sample descriptive discrimination; no classification threshold",
      "optimization"
    ),
    stringsAsFactors = FALSE
  )
}

auc_5e <- auc_delong(
  high_rating_diagnostic_games$high_rating_85,
  high_rating_diagnostic_games$fitted_probability
)
write_model_audit(auc_5e, "step5e_auc.csv")

roc_points_grouped_5e <- high_rating_diagnostic_games |>
  dplyr::group_by(fitted_probability) |>
  dplyr::summarise(
    events = sum(high_rating_85 == 1L),
    non_events = sum(high_rating_85 == 0L),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(fitted_probability)) |>
  dplyr::mutate(
    true_positive_rate = cumsum(events) / sum(events),
    false_positive_rate = cumsum(non_events) / sum(non_events)
  ) |>
  dplyr::select(fitted_probability, false_positive_rate, true_positive_rate)
roc_points_5e <- dplyr::bind_rows(
  data.frame(
    fitted_probability = Inf,
    false_positive_rate = 0,
    true_positive_rate = 0
  ),
  roc_points_grouped_5e
) |>
  dplyr::arrange(false_positive_rate, true_positive_rate)

message(sprintf(
  "Step 5E diagnostics: PASS (max Cook's D=%.4f; AUC=%.4f)",
  influence_summary$max_cooks_distance, auc_5e$auc
))
