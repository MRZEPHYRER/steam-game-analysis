# Step 5F-B: deterministic empirical-Bayes Beta-Binomial rating adjustment.

if (!exists("rating_population_5f")) {
  stop("Run 14_wilson_rating.R before 15_empirical_bayes_rating.R.", call. = FALSE)
}

beta_binomial_nll_5f <- function(log_par, y, n) {
  alpha <- exp(log_par[1])
  beta <- exp(log_par[2])
  -sum(lchoose(n, y) + lbeta(y + alpha, n - y + beta) - lbeta(alpha, beta))
}

beta_binomial_gradient_5f <- function(log_par, y, n) {
  alpha <- exp(log_par[1])
  beta <- exp(log_par[2])
  d_alpha <- sum(
    digamma(y + alpha) - digamma(n + alpha + beta) -
      digamma(alpha) + digamma(alpha + beta)
  )
  d_beta <- sum(
    digamma(n - y + beta) - digamma(n + alpha + beta) -
      digamma(beta) + digamma(alpha + beta)
  )
  -c(alpha * d_alpha, beta * d_beta)
}

fit_eb_prior_5f <- function(data, prior_id, min_reviews) {
  y <- data$positive_reviews
  n <- data$total_reviews
  game_rates <- y / n
  initial_mean <- min(max(mean(game_rates), 1e-4), 1 - 1e-4)
  observed_variance <- stats::var(game_rates)
  moment_precision <- initial_mean * (1 - initial_mean) / observed_variance - 1
  if (!is.finite(moment_precision)) moment_precision <- 10
  moment_precision <- min(max(moment_precision, 0.2), 1000)
  starts <- data.frame(
    start_id = c("moment_precision", "low_precision", "high_precision"),
    prior_mean_start = initial_mean,
    precision_start = c(moment_precision, 2, 100)
  ) |>
    dplyr::mutate(
      alpha_start = prior_mean_start * precision_start,
      beta_start = (1 - prior_mean_start) * precision_start
    )

  fits <- lapply(seq_len(nrow(starts)), function(i) {
    bounded_fit <- stats::optim(
      par = log(c(starts$alpha_start[i], starts$beta_start[i])),
      fn = beta_binomial_nll_5f,
      gr = beta_binomial_gradient_5f,
      y = y,
      n = n,
      method = "L-BFGS-B",
      lower = log(c(1e-4, 1e-4)),
      upper = log(c(1e3, 1e3)),
      control = list(maxit = 5000, factr = 1e7, pgtol = 1e-8)
    )
    stats::optim(
      par = bounded_fit$par,
      fn = beta_binomial_nll_5f,
      gr = beta_binomial_gradient_5f,
      y = y,
      n = n,
      method = "BFGS",
      hessian = TRUE,
      control = list(maxit = 5000, reltol = 1e-12)
    )
  })
  start_audit <- dplyr::bind_rows(lapply(seq_along(fits), function(i) {
    fit <- fits[[i]]
    hessian_eigen <- eigen(fit$hessian, symmetric = TRUE, only.values = TRUE)$values
    data.frame(
      prior_id = prior_id,
      start_id = starts$start_id[i],
      alpha_start = starts$alpha_start[i],
      beta_start = starts$beta_start[i],
      alpha = exp(fit$par[1]),
      beta = exp(fit$par[2]),
      negative_log_likelihood = fit$value,
      convergence_code = fit$convergence,
      gradient_max_abs = max(abs(beta_binomial_gradient_5f(fit$par, y, n))),
      hessian_min_eigenvalue = min(hessian_eigen),
      stringsAsFactors = FALSE
    )
  }))
  best_i <- which.min(start_audit$negative_log_likelihood)
  best_fit <- fits[[best_i]]
  alpha <- exp(best_fit$par[1])
  beta <- exp(best_fit$par[2])
  precision <- alpha + beta
  relative_alpha_range <- diff(range(start_audit$alpha)) / alpha
  relative_beta_range <- diff(range(start_audit$beta)) / beta
  starts_agree <- all(start_audit$convergence_code == 0L) &&
    relative_alpha_range < 1e-4 && relative_beta_range < 1e-4
  stable <- best_fit$convergence == 0L && is.finite(best_fit$value) &&
    alpha > 0 && beta > 0 &&
    max(abs(beta_binomial_gradient_5f(best_fit$par, y, n))) < 1e-3 &&
    min(eigen(best_fit$hessian, symmetric = TRUE, only.values = TRUE)$values) > 0 &&
    starts_agree
  if (!stable) {
    diagnostic <- paste(
      apply(start_audit[, c(
        "start_id", "alpha", "beta", "negative_log_likelihood",
        "convergence_code", "gradient_max_abs", "hessian_min_eigenvalue"
      )], 1, function(row) paste(row, collapse = "|")),
      collapse = "; "
    )
    stop(paste("Unstable EB optimization for", prior_id, diagnostic), call. = FALSE)
  }
  prior_mode <- if (alpha > 1 && beta > 1) (alpha - 1) / (precision - 2) else NA_real_
  prior <- data.frame(
    prior_id = prior_id,
    minimum_reviews_for_prior_fit = min_reviews,
    n_games = nrow(data),
    alpha = alpha,
    beta = beta,
    prior_mean = alpha / precision,
    prior_precision_ess = precision,
    prior_variance = alpha * beta / (precision^2 * (precision + 1)),
    prior_mode = prior_mode,
    log_likelihood = -best_fit$value,
    optimizer = "bounded L-BFGS-B location plus BFGS refinement on log(alpha), log(beta)",
    convergence_code = best_fit$convergence,
    gradient_max_abs = max(abs(beta_binomial_gradient_5f(best_fit$par, y, n))),
    hessian_min_eigenvalue = min(eigen(best_fit$hessian, symmetric = TRUE, only.values = TRUE)$values),
    deterministic_starts = nrow(starts),
    starts_agree = starts_agree,
    relative_alpha_range = relative_alpha_range,
    relative_beta_range = relative_beta_range,
    stringsAsFactors = FALSE
  )
  list(prior = prior, starts = start_audit)
}

prior_specs_5f <- list(
  EB_ALL_POSITIVE_N = list(min_reviews = 1L, data = rating_population_5f),
  EB_N_GE_10 = list(
    min_reviews = 10L,
    data = dplyr::filter(rating_population_5f, total_reviews >= 10)
  ),
  EB_N_GE_20 = list(
    min_reviews = 20L,
    data = dplyr::filter(rating_population_5f, total_reviews >= 20)
  )
)
prior_fits_5f <- lapply(names(prior_specs_5f), function(id) {
  spec <- prior_specs_5f[[id]]
  fit_eb_prior_5f(spec$data, id, spec$min_reviews)
})
eb_prior_parameters_5f <- dplyr::bind_rows(lapply(prior_fits_5f, `[[`, "prior"))
eb_starting_value_audit_5f <- dplyr::bind_rows(lapply(prior_fits_5f, `[[`, "starts"))
primary_prior_5f <- eb_prior_parameters_5f |>
  dplyr::filter(prior_id == "EB_ALL_POSITIVE_N")

posterior_for_prior_5f <- function(data, alpha, beta, suffix) {
  posterior_alpha <- alpha + data$positive_reviews
  posterior_beta <- beta + data$negative_reviews
  precision <- alpha + beta
  result <- data.frame(
    mean = posterior_alpha / (posterior_alpha + posterior_beta),
    lower = stats::qbeta(0.025, posterior_alpha, posterior_beta),
    upper = stats::qbeta(0.975, posterior_alpha, posterior_beta),
    data_weight = data$total_reviews / (data$total_reviews + precision),
    prior_weight = precision / (data$total_reviews + precision)
  )
  result$width <- result$upper - result$lower
  names(result) <- paste0(
    c("eb_posterior_mean", "eb_ci95_lower", "eb_ci95_upper", "data_weight", "prior_weight", "eb_ci95_width"),
    suffix
  )
  result
}

primary_posterior_5f <- posterior_for_prior_5f(
  rating_population_5f, primary_prior_5f$alpha, primary_prior_5f$beta, ""
)
rating_estimates_5f <- dplyr::bind_cols(rating_population_5f, primary_posterior_5f) |>
  dplyr::mutate(
    eb_shrinkage = eb_posterior_mean - raw_positive_rate,
    absolute_shrinkage = abs(eb_shrinkage),
    eb_shrinkage_pp = 100 * eb_shrinkage
  )

rank_vector_5f <- function(data, metric, secondary_reviews = FALSE) {
  order_args <- list(-data[[metric]])
  if (secondary_reviews) order_args <- c(order_args, list(-data$total_reviews))
  order_args <- c(order_args, list(data$appid))
  idx <- do.call(order, order_args)
  result <- integer(nrow(data))
  result[idx] <- seq_along(idx)
  result
}
rating_estimates_5f$raw_rank <- rank_vector_5f(
  rating_estimates_5f, "raw_positive_rate", secondary_reviews = TRUE
)
rating_estimates_5f$wilson_rank <- rank_vector_5f(
  rating_estimates_5f, "wilson_lower_95", secondary_reviews = TRUE
)
rating_estimates_5f$eb_rank <- rank_vector_5f(
  rating_estimates_5f, "eb_posterior_mean", secondary_reviews = FALSE
)
rating_estimates_5f$rank_change <- rating_estimates_5f$raw_rank - rating_estimates_5f$eb_rank

if (any(!is.finite(rating_estimates_5f$eb_posterior_mean)) ||
    any(rating_estimates_5f$eb_posterior_mean <= 0 | rating_estimates_5f$eb_posterior_mean >= 1) ||
    any(abs(rating_estimates_5f$data_weight + rating_estimates_5f$prior_weight - 1) > 1e-12)) {
  stop("EB posterior or shrinkage-weight identity failed.", call. = FALSE)
}

all_posterior_sensitivity_5f <- rating_estimates_5f |>
  dplyr::select(appid, name, total_reviews, raw_positive_rate, eb_all = eb_posterior_mean)
for (id in c("EB_N_GE_10", "EB_N_GE_20")) {
  prior <- dplyr::filter(eb_prior_parameters_5f, prior_id == id)
  suffix <- if (id == "EB_N_GE_10") "_prior10" else "_prior20"
  post <- posterior_for_prior_5f(rating_population_5f, prior$alpha, prior$beta, suffix)
  all_posterior_sensitivity_5f[[paste0("eb", suffix)]] <- post[[paste0("eb_posterior_mean", suffix)]]
}

sensitivity_pairs_5f <- list(
  PRIOR10_VS_ALL = c("eb_prior10", "eb_all"),
  PRIOR20_VS_ALL = c("eb_prior20", "eb_all")
)
eb_prior_sensitivity_5f <- dplyr::bind_rows(lapply(names(sensitivity_pairs_5f), function(id) {
  pair <- sensitivity_pairs_5f[[id]]
  difference <- abs(all_posterior_sensitivity_5f[[pair[1]]] - all_posterior_sensitivity_5f[[pair[2]]])
  data.frame(
    comparison = id,
    evaluation_n = nrow(all_posterior_sensitivity_5f),
    mean_absolute_difference = mean(difference),
    median_absolute_difference = stats::median(difference),
    p95_absolute_difference = unname(stats::quantile(difference, 0.95)),
    max_absolute_difference = max(difference),
    spearman_rank_correlation = stats::cor(
      all_posterior_sensitivity_5f[[pair[1]]],
      all_posterior_sensitivity_5f[[pair[2]]],
      method = "spearman"
    )
  )
}))

review_bin_5f <- function(n) {
  cut(
    n,
    breaks = c(0, 9, 19, 49, 99, 499, 999, Inf),
    labels = c("1-9", "10-19", "20-49", "50-99", "100-499", "500-999", "1000+"),
    right = TRUE
  )
}
extreme_bin_5f <- function(n) {
  cut(
    n,
    breaks = c(0, 1, 4, 9, 19, 49, 99, Inf),
    labels = c("1", "2-4", "5-9", "10-19", "20-49", "50-99", "100+"),
    right = TRUE
  )
}

review_count_bin_summary_5f <- rating_estimates_5f |>
  dplyr::mutate(review_count_bin = review_bin_5f(total_reviews)) |>
  dplyr::group_by(review_count_bin) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    median_raw_positive_rate = stats::median(raw_positive_rate),
    median_eb_posterior_mean = stats::median(eb_posterior_mean),
    median_absolute_shrinkage = stats::median(absolute_shrinkage),
    median_shrinkage_pp = stats::median(eb_shrinkage_pp),
    median_wilson_width = stats::median(wilson_width),
    median_eb_ci95_width = stats::median(eb_ci95_width),
    .groups = "drop"
  )

extreme_rate_summary_5f <- rating_estimates_5f |>
  dplyr::filter(raw_positive_rate %in% c(0, 1)) |>
  dplyr::mutate(
    raw_rate_group = ifelse(raw_positive_rate == 1, "raw_100_percent", "raw_0_percent"),
    review_count_bin = extreme_bin_5f(total_reviews)
  ) |>
  dplyr::group_by(raw_rate_group, review_count_bin) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    median_eb_posterior_mean = stats::median(eb_posterior_mean),
    median_wilson_lower = stats::median(wilson_lower_95),
    median_wilson_upper = stats::median(wilson_upper_95),
    median_shrinkage_pp = stats::median(eb_shrinkage_pp),
    .groups = "drop"
  ) |>
  dplyr::arrange(raw_rate_group, review_count_bin)

distribution_summary_5f <- dplyr::bind_rows(lapply(
  c("raw_positive_rate", "eb_posterior_mean"),
  function(metric) {
    values <- rating_estimates_5f[[metric]]
    data.frame(
      metric = metric,
      minimum = min(values),
      p01 = unname(stats::quantile(values, 0.01)),
      p05 = unname(stats::quantile(values, 0.05)),
      p25 = unname(stats::quantile(values, 0.25)),
      median = stats::median(values),
      mean = mean(values),
      p75 = unname(stats::quantile(values, 0.75)),
      p95 = unname(stats::quantile(values, 0.95)),
      p99 = unname(stats::quantile(values, 0.99)),
      maximum = max(values)
    )
  }
))

rank_pairs_5f <- list(
  RAW_VS_WILSON = c("raw_positive_rate", "wilson_lower_95"),
  RAW_VS_EB = c("raw_positive_rate", "eb_posterior_mean"),
  WILSON_VS_EB = c("wilson_lower_95", "eb_posterior_mean")
)
rank_correlations_5f <- dplyr::bind_rows(lapply(names(rank_pairs_5f), function(id) {
  pair <- rank_pairs_5f[[id]]
  data.frame(
    comparison = id,
    spearman = stats::cor(rating_estimates_5f[[pair[1]]], rating_estimates_5f[[pair[2]]], method = "spearman"),
    kendall_tau_b = stats::cor(rating_estimates_5f[[pair[1]]], rating_estimates_5f[[pair[2]]], method = "kendall")
  )
}))

ranking_columns_5f <- c(raw = "raw_rank", wilson = "wilson_rank", eb = "eb_rank")
topk_pairs_5f <- list(RAW_VS_WILSON = c("raw", "wilson"), RAW_VS_EB = c("raw", "eb"), WILSON_VS_EB = c("wilson", "eb"))
topk_overlap_5f <- dplyr::bind_rows(lapply(c(10L, 25L, 50L, 100L), function(k) {
  dplyr::bind_rows(lapply(names(topk_pairs_5f), function(id) {
    pair <- topk_pairs_5f[[id]]
    a <- rating_estimates_5f$appid[rating_estimates_5f[[ranking_columns_5f[[pair[1]]]]] <= k]
    b <- rating_estimates_5f$appid[rating_estimates_5f[[ranking_columns_5f[[pair[2]]]]] <= k]
    intersection_n <- length(intersect(a, b))
    data.frame(
      top_k = k,
      comparison = id,
      intersection_n = intersection_n,
      union_n = length(union(a, b)),
      jaccard = intersection_n / length(union(a, b))
    )
  }))
}))

mover_fields_5f <- c(
  "appid", "name", "total_reviews", "positive_reviews", "negative_reviews",
  "raw_positive_rate", "wilson_lower_95", "eb_posterior_mean",
  "raw_rank", "wilson_rank", "eb_rank", "rank_change"
)
rank_movers_up_5f <- rating_estimates_5f |>
  dplyr::arrange(dplyr::desc(rank_change), appid) |>
  dplyr::slice_head(n = 30) |>
  dplyr::select(dplyr::all_of(mover_fields_5f))
rank_movers_down_5f <- rating_estimates_5f |>
  dplyr::arrange(rank_change, appid) |>
  dplyr::slice_head(n = 30) |>
  dplyr::select(dplyr::all_of(mover_fields_5f))

high_raw_low_confidence_5f <- rating_estimates_5f |>
  dplyr::filter(raw_positive_rate >= 0.95, wilson_lower_95 < 0.80) |>
  dplyr::arrange(wilson_lower_95, appid)
high_raw_strong_shrinkage_5f <- rating_estimates_5f |>
  dplyr::filter(raw_positive_rate >= 0.95, eb_shrinkage_pp <= -5) |>
  dplyr::arrange(eb_shrinkage_pp, appid)
top_shrinkage_5f <- rating_estimates_5f |>
  dplyr::arrange(dplyr::desc(absolute_shrinkage), appid) |>
  dplyr::slice_head(n = 30)

shrinkage_relationship_5f <- data.frame(
  comparison = "total_reviews_vs_absolute_shrinkage",
  n_games = nrow(rating_estimates_5f),
  spearman = stats::cor(
    rating_estimates_5f$total_reviews,
    rating_estimates_5f$absolute_shrinkage,
    method = "spearman"
  )
)
high_n_values_5f <- dplyr::filter(rating_estimates_5f, total_reviews >= 1000)$absolute_shrinkage
high_n_preservation_5f <- data.frame(
  threshold = "total_reviews >= 1000",
  n_games = length(high_n_values_5f),
  median_absolute_shrinkage = stats::median(high_n_values_5f),
  p95_absolute_shrinkage = unname(stats::quantile(high_n_values_5f, 0.95)),
  max_absolute_shrinkage = max(high_n_values_5f)
)
weight_demonstration_5f <- data.frame(total_reviews = c(1, 2, 5, 10, 20, 50, 100, 500, 1000, 10000)) |>
  dplyr::mutate(
    prior_precision_ess = primary_prior_5f$prior_precision_ess,
    data_weight = total_reviews / (total_reviews + prior_precision_ess),
    prior_weight = 1 - data_weight
  )

top_eb_games_5f <- rating_estimates_5f |>
  dplyr::arrange(eb_rank) |>
  dplyr::slice_head(n = 20)
top_wilson_games_5f <- rating_estimates_5f |>
  dplyr::arrange(wilson_rank) |>
  dplyr::slice_head(n = 20)

fit_warnings_5f <- eb_prior_parameters_5f |>
  dplyr::transmute(
    prior_id,
    warning_type = "optimization_audit",
    warning_count = as.integer(
      convergence_code != 0L | gradient_max_abs >= 1e-3 |
        hessian_min_eigenvalue <= 0 | !starts_agree
    ),
    detail = paste0(
      "convergence=", convergence_code,
      "; gradient_max_abs=", format(gradient_max_abs, scientific = TRUE),
      "; hessian_min_eigenvalue=", format(hessian_min_eigenvalue, scientific = TRUE),
      "; starts_agree=", starts_agree
    )
  )

database_counts_before_5f <- vapply(
  loaded_model_data$counts_before,
  function(value) as.numeric(value[[1]]),
  numeric(1)
)
database_counts_after_5f <- vapply(
  loaded_model_data$counts_after,
  function(value) as.numeric(value[[1]]),
  numeric(1)
)
database_preservation_5f <- data.frame(
  object_name = names(database_counts_before_5f),
  count_before = database_counts_before_5f,
  count_after = database_counts_after_5f,
  unchanged = database_counts_before_5f == database_counts_after_5f
)
if (!all(database_preservation_5f$unchanged)) {
  stop("Database preservation audit failed.", call. = FALSE)
}

write_model_audit(rating_estimates_5f, "step5f_rating_estimates.csv")
write_model_audit(eb_prior_parameters_5f, "step5f_eb_prior_parameters.csv")
write_model_audit(eb_starting_value_audit_5f, "step5f_eb_starting_value_audit.csv")
write_model_audit(eb_prior_sensitivity_5f, "step5f_eb_prior_sensitivity.csv")
write_model_audit(all_posterior_sensitivity_5f, "step5f_eb_prior_sensitivity_game_level.csv")
write_model_audit(review_count_bin_summary_5f, "step5f_review_count_bin_summary.csv")
write_model_audit(extreme_rate_summary_5f, "step5f_extreme_rate_summary.csv")
write_model_audit(distribution_summary_5f, "step5f_rating_distribution_summary.csv")
write_model_audit(rank_correlations_5f, "step5f_rank_correlations.csv")
write_model_audit(topk_overlap_5f, "step5f_topk_overlap.csv")
write_model_audit(rank_movers_up_5f, "step5f_rank_movers_up.csv")
write_model_audit(rank_movers_down_5f, "step5f_rank_movers_down.csv")
write_model_audit(high_raw_low_confidence_5f, "step5f_high_raw_low_confidence.csv")
write_model_audit(high_raw_strong_shrinkage_5f, "step5f_high_raw_strong_shrinkage.csv")
write_model_audit(top_shrinkage_5f, "step5f_top_shrinkage.csv")
write_model_audit(shrinkage_relationship_5f, "step5f_shrinkage_relationship.csv")
write_model_audit(high_n_preservation_5f, "step5f_high_n_preservation.csv")
write_model_audit(weight_demonstration_5f, "step5f_weight_demonstration.csv")
write_model_audit(top_eb_games_5f, "step5f_top_eb_games.csv")
write_model_audit(top_wilson_games_5f, "step5f_top_wilson_games.csv")
write_model_audit(fit_warnings_5f, "step5f_fit_warnings.csv")
write_model_audit(database_preservation_5f, "step5f_database_preservation.csv")

message("Step 5F empirical-Bayes adjustment: PASS")
