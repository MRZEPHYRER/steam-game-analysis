# Run the seven pre-specified one-at-a-time Step 5D beta-binomial specifications.

if (!exists("games_market_wide") || !exists("loaded_model_data")) {
  stop("Run 01_prepare_model_data.R before 08_sensitivity_analysis.R.", call. = FALSE)
}
if (!requireNamespace("glmmTMB", quietly = TRUE)) {
  stop("Missing required package glmmTMB.", call. = FALSE)
}

primary_genres_5d <- c(
  "genre_action", "genre_adventure", "genre_casual", "genre_indie",
  "genre_rpg", "genre_simulation", "genre_strategy"
)
added_genres_5d <- c("genre_early_access", "genre_sports", "genre_racing")
expanded_genres_5d <- c(primary_genres_5d, added_genres_5d)
platform_levels_5d <- c(
  "Windows only", "Windows + macOS", "Windows + Linux",
  "Windows + macOS + Linux"
)

frozen_scaling_5d <- utils::read.csv(
  file.path(model_audit_dir, "step5b_scaling_parameters.csv"),
  check.names = FALSE
)
frozen_primary_coefficients_5d <- utils::read.csv(
  file.path(model_audit_dir, "step5c_beta_binomial_coefficients.csv"),
  check.names = FALSE
)
frozen_primary_fit_5d <- utils::read.csv(
  file.path(model_audit_dir, "step5c_beta_binomial_fit.csv"),
  check.names = FALSE
)

scaling_value_5d <- function(predictor, column) {
  frozen_scaling_5d[frozen_scaling_5d$predictor == predictor, column][[1]]
}
price_log_mean_5d <- scaling_value_5d("log1p_current_price", "scaling_mean")
price_log_sd_5d <- scaling_value_5d("log1p_current_price", "scaling_sd")
days_mean_5d <- scaling_value_5d("days_since_release", "scaling_mean")
days_sd_5d <- scaling_value_5d("days_since_release", "scaling_sd")

paid_positive_source_5d <- games_market_wide |>
  dplyr::filter(is_free == 0, total_reviews > 0) |>
  dplyr::mutate(
    platform_segment = droplevels(factor(
      as.character(platform_segment), levels = platform_levels_5d
    )),
    z_log1p_price = (log1p_current_price - price_log_mean_5d) / price_log_sd_5d,
    z_days_since_release = (days_since_release - days_mean_5d) / days_sd_5d
  )

primary_data_5d <- paid_positive_source_5d |>
  dplyr::filter(total_reviews >= 20)
raw_price_mean_5d <- mean(primary_data_5d$current_price_usd)
raw_price_sd_5d <- stats::sd(primary_data_5d$current_price_usd)
paid_positive_source_5d <- paid_positive_source_5d |>
  dplyr::mutate(
    z_raw_price = (current_price_usd - raw_price_mean_5d) / raw_price_sd_5d
  )
required_fields_5d <- c(
  "appid", "positive_reviews", "negative_reviews", "total_reviews",
  "current_price_usd", "release_month", "z_log1p_price",
  "z_days_since_release", "z_raw_price", "platform_segment",
  expanded_genres_5d
)
threshold_exclusions_5d <- paid_positive_source_5d |>
  dplyr::filter(!stats::complete.cases(dplyr::pick(dplyr::all_of(required_fields_5d)))) |>
  dplyr::transmute(
    appid, total_reviews, is_free,
    exclusion_reason = "missing current_price_usd required by frozen price specification"
  )
paid_positive_5d <- paid_positive_source_5d |>
  dplyr::filter(stats::complete.cases(dplyr::pick(dplyr::all_of(required_fields_5d))))
primary_data_5d <- paid_positive_5d |>
  dplyr::filter(total_reviews >= 20)
stopifnot(
  nrow(primary_data_5d) == 836,
  dplyr::n_distinct(primary_data_5d$appid) == 836,
  !anyDuplicated(primary_data_5d$appid),
  all(primary_data_5d$is_free == 0),
  all(stats::complete.cases(paid_positive_5d[, required_fields_5d])),
  nrow(threshold_exclusions_5d) == 1,
  threshold_exclusions_5d$total_reviews == 2,
  all(paid_positive_5d$positive_reviews + paid_positive_5d$negative_reviews ==
        paid_positive_5d$total_reviews),
  identical(levels(primary_data_5d$platform_segment), platform_levels_5d),
  identical(levels(primary_data_5d$release_month), sprintf("2025-%02d", 7:12)),
  is.finite(raw_price_mean_5d), is.finite(raw_price_sd_5d), raw_price_sd_5d > 0
)

threshold_data_5d <- list(
  TH_GT0 = paid_positive_5d,
  TH_10 = dplyr::filter(paid_positive_5d, total_reviews >= 10),
  PRIMARY = primary_data_5d,
  TH_50 = dplyr::filter(paid_positive_5d, total_reviews >= 50)
)
threshold_source_data_5d <- list(
  TH_GT0 = paid_positive_source_5d,
  TH_10 = dplyr::filter(paid_positive_source_5d, total_reviews >= 10),
  PRIMARY = dplyr::filter(paid_positive_source_5d, total_reviews >= 20),
  TH_50 = dplyr::filter(paid_positive_source_5d, total_reviews >= 50)
)
stopifnot(
  all(threshold_data_5d$TH_50$appid %in% threshold_data_5d$PRIMARY$appid),
  all(threshold_data_5d$PRIMARY$appid %in% threshold_data_5d$TH_10$appid),
  all(threshold_data_5d$TH_10$appid %in% threshold_data_5d$TH_GT0$appid),
  all(vapply(threshold_data_5d, function(x) all(x$is_free == 0), logical(1)))
)

primary_formula_5d <- stats::as.formula(paste(
  "cbind(positive_reviews, negative_reviews) ~",
  "z_log1p_price + z_days_since_release + platform_segment +",
  paste(primary_genres_5d, collapse = " + ")
))
release_formula_5d <- stats::as.formula(paste(
  "cbind(positive_reviews, negative_reviews) ~",
  "z_log1p_price + release_month + platform_segment +",
  paste(primary_genres_5d, collapse = " + ")
))
price_formula_5d <- stats::as.formula(paste(
  "cbind(positive_reviews, negative_reviews) ~",
  "z_raw_price + z_days_since_release + platform_segment +",
  paste(primary_genres_5d, collapse = " + ")
))
genre_formula_5d <- stats::as.formula(paste(
  "cbind(positive_reviews, negative_reviews) ~",
  "z_log1p_price + z_days_since_release + platform_segment +",
  paste(expanded_genres_5d, collapse = " + ")
))

formula_text_5d <- function(formula) {
  gsub("[[:space:]]+", " ", paste(deparse(formula), collapse = " "))
}

specification_meta_5d <- data.frame(
  specification_id = c(
    "PRIMARY", "TH_GT0", "TH_10", "TH_50",
    "RELEASE_MONTH", "PRICE_RAW", "GENRE_EXPANDED"
  ),
  population = c(
    "paid; total_reviews >= 20", "paid; total_reviews > 0",
    "paid; total_reviews >= 10", "paid; total_reviews >= 50",
    rep("paid; total_reviews >= 20", 3)
  ),
  threshold = c(">=20", ">0", ">=10", ">=50", rep(">=20", 3)),
  release_spec = c(rep("z_days_since_release", 4), "release_month", rep("z_days_since_release", 2)),
  price_spec = c(rep("z_log1p_price", 5), "z_raw_price", "z_log1p_price"),
  genre_spec = c(rep("primary_7", 6), "expanded_10"),
  stringsAsFactors = FALSE
)

specification_data_5d <- list(
  PRIMARY = primary_data_5d,
  TH_GT0 = threshold_data_5d$TH_GT0,
  TH_10 = threshold_data_5d$TH_10,
  TH_50 = threshold_data_5d$TH_50,
  RELEASE_MONTH = primary_data_5d,
  PRICE_RAW = primary_data_5d,
  GENRE_EXPANDED = primary_data_5d
)
specification_formula_5d <- list(
  PRIMARY = primary_formula_5d,
  TH_GT0 = primary_formula_5d,
  TH_10 = primary_formula_5d,
  TH_50 = primary_formula_5d,
  RELEASE_MONTH = release_formula_5d,
  PRICE_RAW = price_formula_5d,
  GENRE_EXPANDED = genre_formula_5d
)

fit_one_5d <- function(specification_id) {
  data <- specification_data_5d[[specification_id]]
  formula <- specification_formula_5d[[specification_id]]
  fit_warnings <- character()
  fit <- withCallingHandlers(
    glmmTMB::glmmTMB(
      formula = formula,
      family = glmmTMB::betabinomial(link = "logit"),
      data = data
    ),
    warning = function(w) {
      fit_warnings <<- c(fit_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  coefficient_matrix <- summary(fit)$coefficients$cond
  lower <- coefficient_matrix[, "Estimate"] -
    stats::qnorm(0.975) * coefficient_matrix[, "Std. Error"]
  upper <- coefficient_matrix[, "Estimate"] +
    stats::qnorm(0.975) * coefficient_matrix[, "Std. Error"]
  coefficients <- data.frame(
    specification_id = specification_id,
    term = rownames(coefficient_matrix),
    estimate_log_odds = coefficient_matrix[, "Estimate"],
    std_error = coefficient_matrix[, "Std. Error"],
    z_value = coefficient_matrix[, "z value"],
    p_value = coefficient_matrix[, "Pr(>|z|)"],
    ci95_lower_logit = lower,
    ci95_upper_logit = upper,
    odds_ratio = exp(coefficient_matrix[, "Estimate"]),
    or_ci95_lower = exp(lower),
    or_ci95_upper = exp(upper),
    ci_crosses_1 = exp(lower) <= 1 & exp(upper) >= 1,
    direction = ifelse(coefficient_matrix[, "Estimate"] > 0, "+", "-"),
    ci_method = "Wald normal",
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  convergence_code <- fit$fit$convergence
  pd_hessian <- isTRUE(fit$sdr$pdHess)
  max_gradient <- if (!is.null(fit$sdr$gradient.fixed)) {
    max(abs(fit$sdr$gradient.fixed))
  } else {
    NA_real_
  }
  phi <- as.numeric(stats::sigma(fit))
  diagnose_text <- capture.output(diagnose_return <- glmmTMB::diagnose(fit))
  fit_summary <- data.frame(
    specification_id = specification_id,
    n_games = nrow(data),
    unique_appids = dplyr::n_distinct(data$appid),
    total_positive_reviews = sum(data$positive_reviews),
    total_negative_reviews = sum(data$negative_reviews),
    total_reviews = sum(data$total_reviews),
    pooled_positive_rate = sum(data$positive_reviews) / sum(data$total_reviews),
    n_coefficients = nrow(coefficient_matrix),
    residual_df = stats::df.residual(fit),
    convergence_code = convergence_code,
    converged = convergence_code == 0 && pd_hessian,
    positive_definite_hessian = pd_hessian,
    max_abs_fixed_gradient = max_gradient,
    optimizer = "nlminb (glmmTMB default)",
    iterations = if (!is.null(fit$fit$iterations)) fit$fit$iterations else NA_integer_,
    optimizer_message = if (!is.null(fit$fit$message)) fit$fit$message else "",
    warning_count = length(unique(fit_warnings)),
    log_likelihood = as.numeric(stats::logLik(fit)),
    aic = stats::AIC(fit),
    bic = stats::BIC(fit),
    beta_precision_phi = phi,
    intra_game_rho = 1 / (phi + 1),
    diagnose_return = diagnose_return,
    dispersion_boundary_flag = phi < 1e-6 || phi > 1e8,
    extreme_fixed_estimate_or_se_count = sum(
      abs(coefficient_matrix[, "Estimate"]) > 10 |
        coefficient_matrix[, "Std. Error"] > 10
    ),
    formula = formula_text_5d(formula),
    response = "cbind(positive_reviews, negative_reviews)",
    family = "glmmTMB::betabinomial(link = logit)",
    stringsAsFactors = FALSE
  )
  warnings <- data.frame(
    specification_id = specification_id,
    status = if (length(fit_warnings) == 0) "NO WARNING" else "WARNING",
    warning_count = length(unique(fit_warnings)),
    warning_text = if (length(fit_warnings) == 0) "" else
      paste(unique(fit_warnings), collapse = " | "),
    stringsAsFactors = FALSE
  )
  list(
    fit = fit, coefficients = coefficients, fit_summary = fit_summary,
    warnings = warnings, diagnose_text = diagnose_text
  )
}

fit_results_5d <- lapply(specification_meta_5d$specification_id, fit_one_5d)
names(fit_results_5d) <- specification_meta_5d$specification_id
all_fit_5d <- dplyr::bind_rows(lapply(fit_results_5d, `[[`, "fit_summary")) |>
  dplyr::left_join(specification_meta_5d, by = "specification_id") |>
  dplyr::mutate(
    same_rows_as_primary = vapply(
      specification_id,
      function(id) identical(
        specification_data_5d[[id]]$appid,
        specification_data_5d$PRIMARY$appid
      ),
      logical(1)
    ),
    aic_comparable_to_primary = same_rows_as_primary,
    delta_aic_vs_primary = ifelse(
      same_rows_as_primary,
      aic - aic[specification_id == "PRIMARY"],
      NA_real_
    )
  )
all_coefficients_5d <- dplyr::bind_rows(lapply(fit_results_5d, `[[`, "coefficients"))
all_warnings_5d <- dplyr::bind_rows(lapply(fit_results_5d, `[[`, "warnings"))

primary_estimates_5d <- all_coefficients_5d |>
  dplyr::filter(specification_id == "PRIMARY") |>
  dplyr::arrange(match(term, frozen_primary_coefficients_5d$term))
stopifnot(
  identical(primary_estimates_5d$term, frozen_primary_coefficients_5d$term),
  isTRUE(all.equal(
    primary_estimates_5d$estimate_log_odds,
    frozen_primary_coefficients_5d$estimate_log_odds,
    tolerance = 1e-5
  )),
  all(all_fit_5d$converged),
  all(all_fit_5d$positive_definite_hessian),
  all(all_fit_5d$n_games == all_fit_5d$unique_appids),
  all(all_fit_5d$warning_count == 0),
  all(!all_fit_5d$dispersion_boundary_flag),
  all(all_fit_5d$extreme_fixed_estimate_or_se_count == 0)
)

threshold_ids_5d <- c("TH_GT0", "TH_10", "PRIMARY", "TH_50")
threshold_labels_5d <- c(
  TH_GT0 = ">0", TH_10 = ">=10", PRIMARY = ">=20 (Primary)", TH_50 = ">=50"
)
threshold_samples_5d <- dplyr::bind_rows(lapply(threshold_ids_5d, function(id) {
  x <- threshold_data_5d[[id]]
  data.frame(
    specification_id = id,
    threshold = unname(threshold_labels_5d[id]),
    source_paid_games = nrow(threshold_source_data_5d[[id]]),
    excluded_missing_predictors = nrow(threshold_source_data_5d[[id]]) - nrow(x),
    n_games = nrow(x),
    unique_appids = dplyr::n_distinct(x$appid),
    positive_reviews = sum(x$positive_reviews),
    negative_reviews = sum(x$negative_reviews),
    total_reviews = sum(x$total_reviews),
    pooled_positive_rate = sum(x$positive_reviews) / sum(x$total_reviews),
    median_game_positive_rate = stats::median(x$positive_reviews / x$total_reviews),
    price_mean_usd = mean(x$current_price_usd),
    price_sd_usd = stats::sd(x$current_price_usd),
    price_median_usd = stats::median(x$current_price_usd),
    price_min_usd = min(x$current_price_usd),
    price_max_usd = max(x$current_price_usd),
    days_mean = mean(x$days_since_release),
    days_sd = stats::sd(x$days_since_release),
    days_median = stats::median(x$days_since_release),
    platform_windows_only_n = sum(x$platform_segment == "Windows only"),
    platform_windows_mac_n = sum(x$platform_segment == "Windows + macOS"),
    platform_windows_linux_n = sum(x$platform_segment == "Windows + Linux"),
    platform_all_three_n = sum(x$platform_segment == "Windows + macOS + Linux"),
    genre_action_n = sum(x$genre_action),
    genre_adventure_n = sum(x$genre_adventure),
    genre_casual_n = sum(x$genre_casual),
    genre_indie_n = sum(x$genre_indie),
    genre_rpg_n = sum(x$genre_rpg),
    genre_simulation_n = sum(x$genre_simulation),
    genre_strategy_n = sum(x$genre_strategy),
    paid_only = all(x$is_free == 0),
    frozen_log_price_mean = price_log_mean_5d,
    frozen_log_price_sd = price_log_sd_5d,
    frozen_days_mean = days_mean_5d,
    frozen_days_sd = days_sd_5d,
    stringsAsFactors = FALSE
  )
}))
threshold_appids_5d <- dplyr::bind_rows(lapply(threshold_ids_5d, function(id) {
  threshold_data_5d[[id]] |>
    dplyr::transmute(
      specification_id = id, appid, is_free, total_reviews,
      positive_reviews, negative_reviews
    )
}))
threshold_fit_5d <- all_fit_5d |>
  dplyr::filter(specification_id %in% threshold_ids_5d) |>
  dplyr::mutate(threshold = unname(threshold_labels_5d[specification_id])) |>
  dplyr::arrange(match(specification_id, threshold_ids_5d))
threshold_coefficients_5d <- all_coefficients_5d |>
  dplyr::filter(specification_id %in% threshold_ids_5d) |>
  dplyr::mutate(threshold = unname(threshold_labels_5d[specification_id]))

primary_for_comparison_5d <- all_coefficients_5d |>
  dplyr::filter(specification_id == "PRIMARY") |>
  dplyr::select(
    term, primary_estimate = estimate_log_odds, primary_or = odds_ratio,
    primary_ci_crosses_1 = ci_crosses_1
  )
threshold_stability_5d <- threshold_coefficients_5d |>
  dplyr::left_join(primary_for_comparison_5d, by = "term") |>
  dplyr::mutate(
    or_difference = odds_ratio - primary_or,
    or_difference_pct = 100 * abs(odds_ratio / primary_or - 1),
    log_odds_difference = estimate_log_odds - primary_estimate,
    direction_change = sign(estimate_log_odds) != sign(primary_estimate),
    ci_crosses_1_change = ci_crosses_1 != primary_ci_crosses_1,
    robustness_class = dplyr::case_when(
      direction_change | or_difference_pct > 25 ~ "Highly sensitive",
      or_difference_pct > 10 ~ "Moderately sensitive",
      TRUE ~ "Stable"
    ),
    descriptive_rule = paste(
      "Stable: same sign and OR difference <=10%; Moderate: same sign and",
      ">10%-25%; High: sign reversal or >25%"
    )
  )

comparison_with_primary_5d <- function(target_specification_id, term_map = NULL) {
  alternative <- all_coefficients_5d |>
    dplyr::filter(.data$specification_id == .env$target_specification_id)
  if (!is.null(term_map)) {
    alternative$comparison_term <- ifelse(
      alternative$term %in% names(term_map),
      unname(term_map[alternative$term]), alternative$term
    )
  } else {
    alternative$comparison_term <- alternative$term
  }
  primary <- all_coefficients_5d |>
    dplyr::filter(.data$specification_id == "PRIMARY") |>
    dplyr::rename_with(~ paste0("primary_", .x), -term) |>
    dplyr::rename(comparison_term = term)
  alternative |>
    dplyr::left_join(primary, by = "comparison_term") |>
    dplyr::mutate(
      or_difference = odds_ratio - primary_odds_ratio,
      or_difference_pct = 100 * abs(odds_ratio / primary_odds_ratio - 1),
      log_odds_difference = estimate_log_odds - primary_estimate_log_odds,
      direction_change = sign(estimate_log_odds) != sign(primary_estimate_log_odds),
      ci_crosses_1_change = ci_crosses_1 != primary_ci_crosses_1
    )
}

release_fit_5d <- all_fit_5d |>
  dplyr::filter(specification_id == "RELEASE_MONTH")
release_coefficients_5d <- all_coefficients_5d |>
  dplyr::filter(specification_id == "RELEASE_MONTH")
release_reference_5d <- data.frame(
  specification_id = "RELEASE_MONTH",
  term = "release_month2025-07",
  estimate_log_odds = 0,
  std_error = NA_real_, z_value = NA_real_, p_value = NA_real_,
  ci95_lower_logit = 0, ci95_upper_logit = 0,
  odds_ratio = 1, or_ci95_lower = 1, or_ci95_upper = 1,
  ci_crosses_1 = TRUE, direction = "reference", ci_method = "reference level",
  stringsAsFactors = FALSE
)
release_coefficients_5d <- dplyr::bind_rows(
  release_coefficients_5d, release_reference_5d
) |>
  dplyr::arrange(match(
    term,
    c("release_month2025-07", paste0("release_month2025-", sprintf("%02d", 8:12)))
  ), term)
release_comparison_5d <- comparison_with_primary_5d("RELEASE_MONTH")

price_fit_5d <- all_fit_5d |>
  dplyr::filter(specification_id == "PRICE_RAW") |>
  dplyr::mutate(
    raw_price_mean_usd = raw_price_mean_5d,
    raw_price_sd_usd = raw_price_sd_5d,
    price_interpretation = "OR per +1 primary-sample SD of raw current price"
  )
price_coefficients_5d <- all_coefficients_5d |>
  dplyr::filter(specification_id == "PRICE_RAW")
price_comparison_5d <- comparison_with_primary_5d(
  "PRICE_RAW", c(z_raw_price = "z_log1p_price")
)

reference_5d <- data.frame(
  z_log1p_price = 0, z_raw_price = 0, z_days_since_release = 0,
  release_month = factor("2025-07", levels = sprintf("2025-%02d", 7:12)),
  platform_segment = factor("Windows only", levels = platform_levels_5d),
  genre_action = 0L, genre_adventure = 0L, genre_casual = 0L,
  genre_indie = 0L, genre_rpg = 0L, genre_simulation = 0L,
  genre_strategy = 0L, genre_early_access = 0L,
  genre_sports = 0L, genre_racing = 0L
)
price_predicted_contrasts_5d <- dplyr::bind_rows(
  data.frame(
    specification_id = "PRIMARY", price_term = "z_log1p_price",
    price_scale = "per +1 SD log1p price",
    baseline_probability = as.numeric(stats::predict(
      fit_results_5d$PRIMARY$fit, newdata = reference_5d, type = "response", re.form = NA
    )),
    plus_1sd_probability = as.numeric(stats::predict(
      fit_results_5d$PRIMARY$fit,
      newdata = transform(reference_5d, z_log1p_price = 1),
      type = "response", re.form = NA
    )),
    stringsAsFactors = FALSE
  ),
  data.frame(
    specification_id = "PRICE_RAW", price_term = "z_raw_price",
    price_scale = "per +1 primary-sample SD raw price",
    baseline_probability = as.numeric(stats::predict(
      fit_results_5d$PRICE_RAW$fit, newdata = reference_5d, type = "response", re.form = NA
    )),
    plus_1sd_probability = as.numeric(stats::predict(
      fit_results_5d$PRICE_RAW$fit,
      newdata = transform(reference_5d, z_raw_price = 1),
      type = "response", re.form = NA
    )),
    stringsAsFactors = FALSE
  )
) |>
  dplyr::mutate(
    absolute_probability_contrast = plus_1sd_probability - baseline_probability
  )

genre_fit_5d <- all_fit_5d |>
  dplyr::filter(specification_id == "GENRE_EXPANDED")
genre_coefficients_5d <- all_coefficients_5d |>
  dplyr::filter(specification_id == "GENRE_EXPANDED")
genre_counts_5d <- dplyr::bind_rows(lapply(added_genres_5d, function(term) {
  selected <- primary_data_5d[[term]] == 1
  data.frame(
    term = term,
    n_games_with_genre = sum(selected),
    positive_reviews_with_genre = sum(primary_data_5d$positive_reviews[selected]),
    negative_reviews_with_genre = sum(primary_data_5d$negative_reviews[selected]),
    total_reviews_with_genre = sum(primary_data_5d$total_reviews[selected]),
    source_semantics = if (term == "genre_early_access") {
      "Steam genre/category label in the frozen genre mapping; not historical launch-state status"
    } else {
      "Steam genre/category label in the frozen genre mapping"
    },
    stringsAsFactors = FALSE
  )
}))
genre_comparison_5d <- comparison_with_primary_5d("GENRE_EXPANDED") |>
  dplyr::left_join(genre_counts_5d, by = "term")

master_specification_table_5d <- all_coefficients_5d |>
  dplyr::left_join(
    all_fit_5d |>
      dplyr::select(
        specification_id, population, threshold, release_spec, price_spec,
        genre_spec, n_games, log_likelihood, aic, bic,
        beta_precision_phi, intra_game_rho, converged,
        positive_definite_hessian, max_abs_fixed_gradient, warning_count
      ),
    by = "specification_id"
  )

core_terms_5d <- c(
  "z_log1p_price", "z_days_since_release",
  "platform_segmentWindows + macOS", "platform_segmentWindows + Linux",
  "platform_segmentWindows + macOS + Linux", "genre_indie", "genre_rpg",
  "genre_simulation", "genre_strategy"
)
conceptual_coefficients_5d <- all_coefficients_5d |>
  dplyr::mutate(
    conceptual_term = ifelse(term == "z_raw_price", "z_log1p_price", term),
    price_parameterization = dplyr::case_when(
      term == "z_raw_price" ~ "raw price, +1 primary-sample SD",
      term == "z_log1p_price" ~ "log1p price, +1 frozen SD",
      TRUE ~ "not applicable"
    )
  ) |>
  dplyr::filter(conceptual_term %in% core_terms_5d)
primary_core_5d <- conceptual_coefficients_5d |>
  dplyr::filter(specification_id == "PRIMARY") |>
  dplyr::select(
    conceptual_term, primary_estimate = estimate_log_odds,
    primary_or = odds_ratio, primary_direction = direction
  )
core_predictor_stability_5d <- conceptual_coefficients_5d |>
  dplyr::left_join(primary_core_5d, by = "conceptual_term") |>
  dplyr::group_by(conceptual_term) |>
  dplyr::summarise(
    specifications_available = dplyr::n(),
    minimum_or = min(odds_ratio),
    maximum_or = max(odds_ratio),
    median_or = stats::median(odds_ratio),
    same_direction_specs = sum(direction == primary_direction),
    ci_excluding_1_specs = sum(!ci_crosses_1),
    ci_crossing_1_specs = sum(ci_crosses_1),
    max_or_drift_pct = max(100 * abs(odds_ratio / primary_or - 1)),
    primary_or = dplyr::first(primary_or),
    primary_direction = dplyr::first(primary_direction),
    any_direction_change = any(direction != primary_direction),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    robustness_class = dplyr::case_when(
      any_direction_change | max_or_drift_pct > 25 ~ "SENSITIVE",
      max_or_drift_pct > 10 ~ "PARTIAL",
      TRUE ~ "ROBUST"
    ),
    descriptive_rule = paste(
      "ROBUST: same sign and max OR drift <=10%; PARTIAL: same sign and",
      ">10%-25%; SENSITIVE: sign reversal or >25%"
    )
  )

direction_matrix_5d <- conceptual_coefficients_5d |>
  dplyr::select(conceptual_term, specification_id, direction) |>
  tidyr::pivot_wider(names_from = specification_id, values_from = direction) |>
  dplyr::select(
    conceptual_term, PRIMARY, TH_GT0, TH_10, TH_50,
    RELEASE_MONTH, PRICE_RAW, GENRE_EXPANDED
  )

formula_audit_5d <- dplyr::bind_rows(lapply(
  specification_meta_5d$specification_id,
  function(id) {
    formula_text <- formula_text_5d(specification_formula_5d[[id]])
    data.frame(
      specification_id = id,
      formula = formula_text,
      response_is_grouped_counts = grepl(
        "cbind\\(positive_reviews, negative_reviews\\)", formula_text
      ),
      includes_days = grepl("z_days_since_release", formula_text, fixed = TRUE),
      includes_release_month = grepl("release_month", formula_text, fixed = TRUE),
      includes_log_price = grepl("z_log1p_price", formula_text, fixed = TRUE),
      includes_raw_price = grepl("z_raw_price", formula_text, fixed = TRUE),
      added_genres = paste(
        intersect(all.vars(specification_formula_5d[[id]]), added_genres_5d),
        collapse = ";"
      ),
      n_input_rows = nrow(specification_data_5d[[id]]),
      n_model_rows = stats::nobs(fit_results_5d[[id]]$fit),
      no_silent_row_deletion = nrow(specification_data_5d[[id]]) ==
        stats::nobs(fit_results_5d[[id]]$fit),
      stringsAsFactors = FALSE
    )
  }
))
stopifnot(
  all(formula_audit_5d$response_is_grouped_counts),
  all(formula_audit_5d$no_silent_row_deletion),
  !formula_audit_5d$includes_days[formula_audit_5d$specification_id == "RELEASE_MONTH"],
  formula_audit_5d$includes_release_month[formula_audit_5d$specification_id == "RELEASE_MONTH"],
  !formula_audit_5d$includes_log_price[formula_audit_5d$specification_id == "PRICE_RAW"],
  formula_audit_5d$includes_raw_price[formula_audit_5d$specification_id == "PRICE_RAW"],
  identical(
    formula_audit_5d$added_genres[formula_audit_5d$specification_id == "GENRE_EXPANDED"],
    paste(added_genres_5d, collapse = ";")
  )
)

database_counts_before_5d <- vapply(
  loaded_model_data$counts_before, function(x) as.numeric(x[[1]]), numeric(1)
)
database_counts_after_5d <- vapply(
  loaded_model_data$counts_after, function(x) as.numeric(x[[1]]), numeric(1)
)
database_preservation_5d <- data.frame(
  object = names(loaded_model_data$counts_before),
  before = database_counts_before_5d,
  after = database_counts_after_5d,
  unchanged = database_counts_before_5d == database_counts_after_5d,
  audit_step = "Step 5D",
  stringsAsFactors = FALSE
)
stopifnot(all(database_preservation_5d$unchanged))

write_model_audit(threshold_samples_5d, "step5d_threshold_samples.csv")
write_model_audit(threshold_exclusions_5d, "step5d_threshold_exclusions.csv")
write_model_audit(threshold_appids_5d, "step5d_threshold_appids.csv")
write_model_audit(threshold_fit_5d, "step5d_threshold_fit.csv")
write_model_audit(threshold_coefficients_5d, "step5d_threshold_coefficients.csv")
write_model_audit(threshold_stability_5d, "step5d_threshold_stability.csv")
write_model_audit(release_fit_5d, "step5d_release_fit.csv")
write_model_audit(release_coefficients_5d, "step5d_release_coefficients.csv")
write_model_audit(release_comparison_5d, "step5d_release_comparison.csv")
write_model_audit(price_fit_5d, "step5d_price_fit.csv")
write_model_audit(price_coefficients_5d, "step5d_price_coefficients.csv")
write_model_audit(price_comparison_5d, "step5d_price_comparison.csv")
write_model_audit(price_predicted_contrasts_5d, "step5d_price_predicted_contrasts.csv")
write_model_audit(genre_fit_5d, "step5d_genre_fit.csv")
write_model_audit(genre_coefficients_5d, "step5d_genre_coefficients.csv")
write_model_audit(genre_comparison_5d, "step5d_genre_comparison.csv")
write_model_audit(master_specification_table_5d, "step5d_master_specification_table.csv")
write_model_audit(core_predictor_stability_5d, "step5d_core_predictor_stability.csv")
write_model_audit(direction_matrix_5d, "step5d_direction_matrix.csv")
write_model_audit(all_fit_5d, "step5d_diagnostics.csv")
write_model_audit(all_warnings_5d, "step5d_fit_warnings.csv")
write_model_audit(formula_audit_5d, "step5d_formula_audit.csv")
write_model_audit(database_preservation_5d, "step5d_database_preservation.csv")

message(sprintf(
  paste0(
    "Step 5D sensitivity fits: PASS (specifications=%d, threshold N=%s, ",
    "all converged=%s)"
  ),
  nrow(all_fit_5d), paste(threshold_samples_5d$n_games, collapse = "/"),
  all(all_fit_5d$converged)
))
