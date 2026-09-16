# Run the pre-defined review-volume influence sensitivity analyses for Step 5C.

if (!exists("beta_fit") || !exists("quasi_fit")) {
  stop("Run 06_robust_models.R before 07_influence_sensitivity.R.", call. = FALSE)
}

ranked_primary <- model20_paid_baseline |>
  dplyr::arrange(dplyr::desc(total_reviews), appid) |>
  dplyr::mutate(review_volume_rank = dplyr::row_number())

removal_counts <- c(
  full = 0L,
  minus_top1 = 1L,
  minus_top1pct = as.integer(ceiling(0.01 * nrow(ranked_primary))),
  minus_top5pct = as.integer(ceiling(0.05 * nrow(ranked_primary)))
)
population_labels <- c(
  full = "Full",
  minus_top1 = "Minus top 1",
  minus_top1pct = "Minus top 1%",
  minus_top5pct = "Minus top 5%"
)
population_order <- names(removal_counts)
primary_total_reviews <- sum(ranked_primary$total_reviews)

sensitivity_populations <- lapply(removal_counts, function(remove_n) {
  ranked_primary |>
    dplyr::filter(review_volume_rank > remove_n)
})
stopifnot(
  identical(unname(vapply(sensitivity_populations, nrow, integer(1))), c(836L, 835L, 827L, 794L)),
  all(vapply(sensitivity_populations, function(x) {
    isTRUE(all.equal(
      x$z_log1p_price,
      (x$log1p_current_price - price_log_mean) / price_log_sd,
      tolerance = 1e-14
    )) && isTRUE(all.equal(
      x$z_days_since_release,
      (x$days_since_release - days_mean) / days_sd,
      tolerance = 1e-14
    ))
  }, logical(1)))
)

influence_population_rows <- lapply(population_order, function(population_id) {
  remove_n <- removal_counts[[population_id]]
  population <- sensitivity_populations[[population_id]]
  cutoff <- if (remove_n == 0) NA_integer_ else ranked_primary$total_reviews[remove_n]
  data.frame(
    population = population_id,
    population_label = population_labels[[population_id]],
    n_games = nrow(population),
    games_removed = remove_n,
    share_games_removed = remove_n / nrow(ranked_primary),
    cutoff_review_count = cutoff,
    ties_at_cutoff_in_primary = if (is.na(cutoff)) NA_integer_ else sum(ranked_primary$total_reviews == cutoff),
    total_reviews_retained = sum(population$total_reviews),
    fraction_reviews_retained = sum(population$total_reviews) / primary_total_reviews,
    reviews_removed = primary_total_reviews - sum(population$total_reviews),
    share_reviews_removed = 1 - sum(population$total_reviews) / primary_total_reviews,
    pooled_positive_rate = sum(population$positive_reviews) / sum(population$total_reviews),
    ranking_rule = "total_reviews descending, appid ascending; remove exactly the pre-specified count",
    scaling_rule = "frozen full-sample Step 5B mean and SD; no re-scaling after exclusion",
    stringsAsFactors = FALSE
  )
})
influence_populations <- dplyr::bind_rows(influence_population_rows)
write_model_audit(influence_populations, "step5c_influence_populations.csv")
write_model_audit(
  influence_populations |>
    dplyr::select(
      population, population_label, games_removed, share_games_removed,
      reviews_removed, share_reviews_removed, cutoff_review_count,
      ties_at_cutoff_in_primary
    ),
  "step5c_review_mass_removed.csv"
)
write_model_audit(
  ranked_primary |>
    dplyr::filter(review_volume_rank <= max(removal_counts)) |>
    dplyr::mutate(
      removed_minus_top1 = review_volume_rank <= removal_counts[["minus_top1"]],
      removed_minus_top1pct = review_volume_rank <= removal_counts[["minus_top1pct"]],
      removed_minus_top5pct = review_volume_rank <= removal_counts[["minus_top5pct"]]
    ) |>
    dplyr::select(
      review_volume_rank, appid, name, total_reviews,
      removed_minus_top1, removed_minus_top1pct, removed_minus_top5pct
    ),
  "step5c_influence_removed_games.csv"
)

extract_glm_coefficients <- function(fit, model_name, population_id) {
  matrix <- summary(fit)$coefficients
  critical <- stats::qt(0.975, df = stats::df.residual(fit))
  lower <- matrix[, "Estimate"] - critical * matrix[, "Std. Error"]
  upper <- matrix[, "Estimate"] + critical * matrix[, "Std. Error"]
  data.frame(
    model = model_name,
    population = population_id,
    term = rownames(matrix),
    estimate_log_odds = matrix[, "Estimate"],
    std_error = matrix[, "Std. Error"],
    statistic = matrix[, "t value"],
    p_value = matrix[, "Pr(>|t|)"],
    ci95_lower_logit = lower,
    ci95_upper_logit = upper,
    odds_ratio = exp(matrix[, "Estimate"]),
    or_ci95_lower = exp(lower),
    or_ci95_upper = exp(upper),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

extract_beta_coefficients <- function(fit, population_id) {
  matrix <- summary(fit)$coefficients$cond
  lower <- matrix[, "Estimate"] - stats::qnorm(0.975) * matrix[, "Std. Error"]
  upper <- matrix[, "Estimate"] + stats::qnorm(0.975) * matrix[, "Std. Error"]
  data.frame(
    model = "Beta-binomial",
    population = population_id,
    term = rownames(matrix),
    estimate_log_odds = matrix[, "Estimate"],
    std_error = matrix[, "Std. Error"],
    statistic = matrix[, "z value"],
    p_value = matrix[, "Pr(>|z|)"],
    ci95_lower_logit = lower,
    ci95_upper_logit = upper,
    odds_ratio = exp(matrix[, "Estimate"]),
    or_ci95_lower = exp(lower),
    or_ci95_upper = exp(upper),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

sensitivity_fits <- list()
influence_coefficient_rows <- list()
influence_fit_rows <- list()
for (population_id in population_order) {
  population <- sensitivity_populations[[population_id]]
  if (population_id == "full") {
    quasi_capture_i <- quasi_capture
    beta_capture_i <- beta_capture
  } else {
    quasi_capture_i <- capture_fit(
      stats::glm(
        formula = frozen_baseline_formula,
        family = stats::quasibinomial(link = "logit"),
        data = population
      ),
      paste("quasibinomial", population_id)
    )
    beta_capture_i <- capture_fit(
      glmmTMB::glmmTMB(
        formula = frozen_baseline_formula,
        family = glmmTMB::betabinomial(link = "logit"),
        data = population
      ),
      paste("beta-binomial", population_id)
    )
  }
  quasi_i <- quasi_capture_i$value
  beta_i <- beta_capture_i$value
  beta_matrix_i <- summary(beta_i)$coefficients$cond
  beta_ok_i <- beta_i$fit$convergence == 0 && isTRUE(beta_i$sdr$pdHess)
  stopifnot(
    isTRUE(quasi_i$converged), beta_ok_i,
    identical(names(stats::coef(quasi_i)), names(stats::coef(baseline_fit))),
    identical(rownames(beta_matrix_i), names(stats::coef(baseline_fit))),
    stats::nobs(quasi_i) == nrow(population), stats::nobs(beta_i) == nrow(population)
  )
  sensitivity_fits[[population_id]] <- list(quasi = quasi_i, beta = beta_i)
  influence_coefficient_rows[[length(influence_coefficient_rows) + 1]] <-
    extract_glm_coefficients(quasi_i, "Quasibinomial", population_id)
  influence_coefficient_rows[[length(influence_coefficient_rows) + 1]] <-
    extract_beta_coefficients(beta_i, population_id)
  pop_summary <- influence_populations[influence_populations$population == population_id, ]
  influence_fit_rows[[length(influence_fit_rows) + 1]] <- data.frame(
    model = "Quasibinomial", population = population_id,
    n_games = nrow(population), total_reviews = sum(population$total_reviews),
    fraction_reviews_retained = pop_summary$fraction_reviews_retained,
    pooled_positive_rate = pop_summary$pooled_positive_rate,
    dispersion = summary(quasi_i)$dispersion,
    dispersion_definition = "estimated quasi variance multiplier",
    log_likelihood = NA_real_, aic = NA_real_, bic = NA_real_,
    convergence_code = NA_integer_, positive_definite_hessian = NA,
    converged = quasi_i$converged,
    warning_count = length(quasi_capture_i$warnings),
    stringsAsFactors = FALSE
  )
  influence_fit_rows[[length(influence_fit_rows) + 1]] <- data.frame(
    model = "Beta-binomial", population = population_id,
    n_games = nrow(population), total_reviews = sum(population$total_reviews),
    fraction_reviews_retained = pop_summary$fraction_reviews_retained,
    pooled_positive_rate = pop_summary$pooled_positive_rate,
    dispersion = as.numeric(stats::sigma(beta_i)),
    dispersion_definition = "beta precision phi",
    log_likelihood = as.numeric(stats::logLik(beta_i)),
    aic = stats::AIC(beta_i), bic = stats::BIC(beta_i),
    convergence_code = beta_i$fit$convergence,
    positive_definite_hessian = beta_i$sdr$pdHess,
    converged = beta_ok_i,
    warning_count = length(beta_capture_i$warnings),
    stringsAsFactors = FALSE
  )
  if (population_id != "full") {
    step5c_fit_warning_rows[[length(step5c_fit_warning_rows) + 1]] <- data.frame(
      model = "Quasibinomial", population = population_id,
      status = if (length(quasi_capture_i$warnings) == 0) "NO WARNING" else "WARNING",
      warning_text = if (length(quasi_capture_i$warnings) == 0) "" else paste(quasi_capture_i$warnings, collapse = " | "),
      stringsAsFactors = FALSE
    )
    step5c_fit_warning_rows[[length(step5c_fit_warning_rows) + 1]] <- data.frame(
      model = "Beta-binomial", population = population_id,
      status = if (length(beta_capture_i$warnings) == 0) "NO WARNING" else "WARNING",
      warning_text = if (length(beta_capture_i$warnings) == 0) "" else paste(beta_capture_i$warnings, collapse = " | "),
      stringsAsFactors = FALSE
    )
  }
}

influence_coefficients <- dplyr::bind_rows(influence_coefficient_rows)
influence_fit_summary <- dplyr::bind_rows(influence_fit_rows)
write_model_audit(influence_coefficients, "step5c_influence_coefficients.csv")
write_model_audit(influence_fit_summary, "step5c_influence_fit_summary.csv")
write_model_audit(dplyr::bind_rows(step5c_fit_warning_rows), "step5c_fit_warnings.csv")

primary_beta <- influence_coefficients |>
  dplyr::filter(model == "Beta-binomial", population == "full") |>
  dplyr::select(
    term,
    primary_estimate = estimate_log_odds,
    primary_or = odds_ratio
  )
stopifnot(isTRUE(all.equal(
  primary_beta$primary_estimate,
  beta_coefficients$estimate_log_odds,
  tolerance = 1e-12
)))
coefficient_drift <- influence_coefficients |>
  dplyr::filter(model == "Beta-binomial") |>
  dplyr::left_join(primary_beta, by = "term") |>
  dplyr::mutate(
    absolute_estimate_change = abs(estimate_log_odds - primary_estimate),
    estimate_change_pct = 100 * absolute_estimate_change /
      pmax(abs(primary_estimate), .Machine$double.eps),
    or_change_pct = 100 * abs(odds_ratio / primary_or - 1),
    sign_change = sign(estimate_log_odds) != sign(primary_estimate)
  ) |>
  dplyr::select(
    term, population, primary_estimate, estimate_log_odds,
    absolute_estimate_change, estimate_change_pct,
    primary_or, odds_ratio, or_change_pct, sign_change
  )
write_model_audit(coefficient_drift, "step5c_coefficient_drift.csv")

influence_robustness <- coefficient_drift |>
  dplyr::filter(population != "full") |>
  dplyr::group_by(term) |>
  dplyr::summarise(
    max_absolute_estimate_change = max(absolute_estimate_change),
    max_estimate_change_pct = max(estimate_change_pct),
    max_or_change_pct = max(or_change_pct),
    any_sign_change = any(sign_change),
    most_sensitive_population = population[which.max(or_change_pct)],
    .groups = "drop"
  ) |>
  dplyr::mutate(
    headline_flag = dplyr::case_when(
      any_sign_change | max_or_change_pct > 25 ~ "Highly sensitive",
      max_or_change_pct > 10 ~ "Moderately sensitive",
      TRUE ~ "Stable"
    ),
    descriptive_rule = "Stable: same sign and max OR change <=10%; Moderate: same sign and >10%-25%; High: sign reversal or >25%"
  )
write_model_audit(influence_robustness, "step5c_influence_robustness.csv")

term_labels <- c(
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
)
model_levels <- c("Binomial", "Quasibinomial", "Beta-binomial")
plot_theme_5c <- ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.title.position = "plot",
    legend.position = "top"
  )

robust_or_plot_data <- dplyr::bind_rows(
  coefficient_comparison |>
    dplyr::transmute(
      term, model = "Binomial", odds_ratio = binomial_or,
      lower = binomial_or_ci_lower, upper = binomial_or_ci_upper
    ),
  coefficient_comparison |>
    dplyr::transmute(
      term, model = "Quasibinomial", odds_ratio = quasi_or,
      lower = quasi_or_ci_lower, upper = quasi_or_ci_upper
    ),
  coefficient_comparison |>
    dplyr::transmute(
      term, model = "Beta-binomial", odds_ratio = beta_or,
      lower = beta_profile_or_ci_lower, upper = beta_profile_or_ci_upper
    )
) |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::mutate(
    term_label = factor(unname(term_labels[term]), levels = rev(unname(term_labels))),
    model = factor(model, levels = model_levels)
  )
robust_or_plot <- ggplot2::ggplot(
  robust_or_plot_data,
  ggplot2::aes(odds_ratio, term_label, colour = model)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = lower, xmax = upper),
    orientation = "y", width = 0.14,
    position = ggplot2::position_dodge(width = 0.58)
  ) +
  ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.58), size = 2) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#6C757D", "#D28E2C", "#2C6E9B")) +
  ggplot2::labs(
    title = "Binomial and overdispersion-robust odds ratios",
    subtitle = "Binomial/Quasi use Wald intervals; Beta-binomial uses profile likelihood",
    x = "Odds ratio (log scale)", y = NULL, colour = "Model"
  ) + plot_theme_5c
ggplot2::ggsave(
  file.path(model_figure_dir, "05_robust_or_comparison.png"),
  robust_or_plot, width = 10.4, height = 7.8, dpi = 180
)

ci_width_plot_data <- coefficient_comparison |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::transmute(
    term,
    `Quasi / Binomial` = (quasi_or_ci_upper - quasi_or_ci_lower) /
      (binomial_or_ci_upper - binomial_or_ci_lower),
    `Beta-binomial profile / Binomial` = (beta_profile_or_ci_upper - beta_profile_or_ci_lower) /
      (binomial_or_ci_upper - binomial_or_ci_lower)
  ) |>
  tidyr::pivot_longer(-term, names_to = "comparison", values_to = "width_ratio") |>
  dplyr::mutate(
    term_label = factor(unname(term_labels[term]), levels = rev(unname(term_labels)))
  )
ci_width_plot <- ggplot2::ggplot(
  ci_width_plot_data,
  ggplot2::aes(width_ratio, term_label, colour = comparison)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.45), size = 2.2) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#2C6E9B", "#D28E2C")) +
  ggplot2::labs(
    title = "Confidence-interval width inflation versus Binomial",
    subtitle = "Quasi Wald and Beta profile OR-scale widths; vertical line marks equal width",
    x = "CI width ratio (log scale)", y = NULL, colour = "Comparison"
  ) + plot_theme_5c
ggplot2::ggsave(
  file.path(model_figure_dir, "06_ci_width_comparison.png"),
  ci_width_plot, width = 9.4, height = 7.3, dpi = 180
)

influence_plot_data <- influence_coefficients |>
  dplyr::filter(model == "Beta-binomial", term != "(Intercept)") |>
  dplyr::mutate(
    term_label = factor(unname(term_labels[term]), levels = rev(unname(term_labels))),
    population_label = factor(population_labels[population], levels = unname(population_labels))
  )
influence_sensitivity_plot <- ggplot2::ggplot(
  influence_plot_data,
  ggplot2::aes(odds_ratio, term_label, colour = population_label)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.12,
    position = ggplot2::position_dodge(width = 0.68)
  ) +
  ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.68), size = 1.9) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#2C6E9B", "#6C757D", "#D28E2C", "#B04A3A")) +
  ggplot2::labs(
    title = "Beta-binomial sensitivity to review-volume exclusions",
    subtitle = "Exclusions follow total reviews descending, AppID ascending; scaling remains frozen",
    x = "Odds ratio (log scale)", y = NULL, colour = "Population"
  ) + plot_theme_5c
ggplot2::ggsave(
  file.path(model_figure_dir, "07_influence_sensitivity_coefficients.png"),
  influence_sensitivity_plot, width = 10.8, height = 8.2, dpi = 180
)

review_mass_plot_data <- influence_populations |>
  dplyr::filter(population != "full") |>
  dplyr::mutate(
    games_removed_pct = 100 * share_games_removed,
    reviews_removed_pct = 100 * share_reviews_removed
  )
review_mass_plot <- ggplot2::ggplot(
  review_mass_plot_data,
  ggplot2::aes(games_removed_pct, reviews_removed_pct)
) +
  ggplot2::geom_line(colour = "#6C757D", linewidth = 0.8) +
  ggplot2::geom_point(colour = "#2C6E9B", size = 2.8) +
  ggplot2::geom_text(
    ggplot2::aes(label = population_label),
    nudge_y = 2.4, colour = "#2C6E9B", size = 3.6
  ) +
  ggplot2::scale_x_continuous(
    labels = function(x) paste0(x, "%"),
    expand = ggplot2::expansion(mult = c(0.08, 0.20))
  ) +
  ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%")) +
  ggplot2::labs(
    title = "Small game exclusions remove disproportionate review mass",
    subtitle = "Pre-defined review-volume sensitivities; exact counts retained in the audit table",
    x = "Games removed", y = "Reviews removed"
  ) + plot_theme_5c + ggplot2::theme(legend.position = "none")
ggplot2::ggsave(
  file.path(model_figure_dir, "08_review_mass_removed.png"),
  review_mass_plot, width = 7.4, height = 5.8, dpi = 180
)

fmt5c <- function(x, digits = 4) formatC(x, digits = digits, format = "f", big.mark = ",")
quasi_inflation_summary <- data.frame(
  metric = c("minimum", "median", "maximum", "sqrt(phi)"),
  se_inflation = c(
    min(quasi_inflation$se_inflation_ratio),
    stats::median(quasi_inflation$se_inflation_ratio),
    max(quasi_inflation$se_inflation_ratio),
    sqrt(quasi_dispersion)
  ),
  ci_width_inflation = c(
    min(quasi_inflation$ci_width_inflation_ratio),
    stats::median(quasi_inflation$ci_width_inflation_ratio),
    max(quasi_inflation$ci_width_inflation_ratio),
    NA_real_
  ),
  stringsAsFactors = FALSE
)
write_model_audit(quasi_inflation_summary, "step5c_quasi_inflation_summary.csv")

report_comparison_rows <- coefficient_comparison |>
  dplyr::filter(term != "(Intercept)")
comparison_table_lines <- c(
  "| Term | Binomial OR [95% CI] | Quasi OR [95% CI] | Beta-binomial OR [95% CI] | Beta OR change |",
  "|---|---:|---:|---:|---:|",
  vapply(seq_len(nrow(report_comparison_rows)), function(i) {
    row <- report_comparison_rows[i, ]
    paste0(
      "| `", row$term, "` | ", fmt5c(row$binomial_or), " [", fmt5c(row$binomial_or_ci_lower), ", ", fmt5c(row$binomial_or_ci_upper), "] | ",
      fmt5c(row$quasi_or), " [", fmt5c(row$quasi_or_ci_lower), ", ", fmt5c(row$quasi_or_ci_upper), "] | ",
      fmt5c(row$beta_or), " [", fmt5c(row$beta_profile_or_ci_lower), ", ", fmt5c(row$beta_profile_or_ci_upper), "] | ",
      fmt5c(row$beta_or_change_vs_binomial_pct, 2), "% |"
    )
  }, character(1))
)

changed_ci_terms <- quasi_inflation$term[quasi_inflation$ci_crossing_status_changed]
max_beta_change_row <- coefficient_comparison |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::slice_max(beta_or_change_vs_binomial_pct, n = 1, with_ties = FALSE)
most_sensitive <- influence_robustness |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::arrange(dplyr::desc(max_or_change_pct), term)

report_lines_5c <- c(
  "# Step 5C Overdispersion-Robust Modeling & Influence Sensitivity",
  "",
  "## 1. Why Step 5C was required",
  "",
  paste0("The frozen Step 5B Binomial converged, but Pearson dispersion was ",
         fmt5c(quasi_fit_table$baseline_pearson_dispersion, 3), " and deviance/df was 61.816. Binomial p-values and CIs are retained only as a benchmark because their nominal precision is not credible under this extra-binomial variation."),
  "",
  "## 2. Frozen specification",
  "",
  paste0("All models use the same 836 paid games, grouped response, 13 fixed coefficients, reference levels, predictors, and Step 5B scaling. Formula: `", expected_formula_text, "`."),
  "",
  "## 3. Quasibinomial results and uncertainty inflation",
  "",
  paste0("Quasibinomial converged in ", quasi_fit$iter, " iterations with estimated dispersion ", fmt5c(quasi_dispersion, 4), ". Its coefficients equal the Binomial mean coefficients as expected. SE inflation min/median/max = ",
         fmt5c(min(quasi_inflation$se_inflation_ratio), 4), " / ",
         fmt5c(stats::median(quasi_inflation$se_inflation_ratio), 4), " / ",
         fmt5c(max(quasi_inflation$se_inflation_ratio), 4), ", versus sqrt(phi) = ",
         fmt5c(sqrt(quasi_dispersion), 4), ". CI-width inflation min/median/max = ",
         fmt5c(min(quasi_inflation$ci_width_inflation_ratio), 4), " / ",
         fmt5c(stats::median(quasi_inflation$ci_width_inflation_ratio), 4), " / ",
         fmt5c(max(quasi_inflation$ci_width_inflation_ratio), 4), "."),
  paste0("Terms whose CI-crosses-1 status changed from Binomial to Quasi: ",
         if (length(changed_ci_terms) == 0) "none" else paste(changed_ci_terms, collapse = ", "), ". Quasi logLik/AIC/BIC are NA because quasi-likelihood is not likelihood-comparable."),
  "",
  "## 4. Beta-binomial implementation and heterogeneity",
  "",
  paste0("Implementation: glmmTMB ", step5c_package_version, " (TMB dependency ", step5c_tmb_version,
         ") with `betabinomial(link=logit)`. Convergence code = ", beta_convergence_code,
         ", positive-definite Hessian = ", beta_pd_hessian, ", max absolute fixed gradient = ", fmt5c(beta_gradient_max, 7),
         ", warnings = ", length(beta_capture$warnings), ". logLik = ", fmt5c(beta_loglik, 3),
         ", AIC = ", fmt5c(beta_aic, 3), ", BIC = ", fmt5c(beta_bic, 3), "."),
  paste0("glmmTMB beta-binomial precision phi = ", fmt5c(beta_dispersion_phi, 5),
         " under Var(Y)=n*p*(1-p)*(phi+n)/(phi+1). Larger phi means less extra-binomial heterogeneity and phi -> infinity is the Binomial limit. The derived latent within-game ICC is rho=1/(phi+1)=",
         fmt5c(beta_rho, 5), "; larger rho means greater within-game dependence/heterogeneity."),
  paste0("All 13 fixed-effect profile-likelihood intervals completed with ", length(beta_profile_warnings),
         " warnings. The maximum absolute OR-endpoint difference from the Wald intervals was ",
         fmt5c(max(abs(c(
           beta_coefficients$profile_or_ci95_lower - beta_coefficients$or_ci95_lower,
           beta_coefficients$profile_or_ci95_upper - beta_coefficients$or_ci95_upper
         ))), 4), ". Tables retain both methods; the robust comparison figure uses profile intervals for beta-binomial."),
  "",
  "## 5. Model comparison and coefficient stability",
  "",
  paste0("On the identical response/sample, beta-binomial minus Binomial delta AIC = ",
         fmt5c(beta_aic - stats::AIC(baseline_fit), 3), " and logLik improvement = ",
         fmt5c(beta_loglik - as.numeric(stats::logLik(baseline_fit)), 3), ". This is strong fit evidence but is not the sole selection rule."),
  paste0("The largest non-intercept beta-vs-binomial OR change is `", max_beta_change_row$term,
         "` at ", fmt5c(max_beta_change_row$beta_or_change_vs_binomial_pct, 2), "%."),
  "",
  comparison_table_lines,
  "",
  "## 6. Influence sensitivity and review mass",
  "",
  paste0("Population sizes are ", paste0(influence_populations$population_label, "=", influence_populations$n_games, collapse = ", "), ". Ranking is total_reviews descending then AppID ascending; exactly 1, 9, and 42 games are removed. All sensitivity fits reuse the full-sample price/day scaling."),
  paste0("Reviews removed for top 1 / top 1% / top 5% are ",
         paste0(format(influence_populations$reviews_removed[-1], big.mark = ","), " (", fmt5c(100 * influence_populations$share_reviews_removed[-1], 2), "%)", collapse = ", "), "."),
  paste0("The most influence-sensitive non-intercept term is `", most_sensitive$term[1],
         "`, with maximum beta-binomial OR change ", fmt5c(most_sensitive$max_or_change_pct[1], 2),
         "% under `", most_sensitive$most_sensitive_population[1], "`; headline class = ", most_sensitive$headline_flag[1], "."),
  "The descriptive robustness rule is: Stable when sign is unchanged and maximum OR change <=10%; Moderate for unchanged sign with >10%-25%; High for sign reversal or >25%.",
  "",
  "## 7. Robust predicted effects",
  "",
  paste0("At z-price=0, z-days=0, Windows only, and all seven genres absent, predicted probabilities are Binomial ",
         fmt5c(predicted_effect_comparison$binomial_probability[1], 5), ", Quasi ",
         fmt5c(predicted_effect_comparison$quasi_probability[1], 5), ", and Beta-binomial ",
         fmt5c(predicted_effect_comparison$beta_binomial_probability[1], 5), ". All one-at-a-time contrasts are exported; they are associative, not causal."),
  "",
  "## 8. Convergence, warnings, and diagnostics",
  "",
  paste0("All eight population-by-model fits converged; all four beta-binomial Hessians were positive definite. Total captured fit-warning rows with WARNING status = ",
         sum(dplyr::bind_rows(step5c_fit_warning_rows)$status == "WARNING"), ". No unvalidated Cook's D or leverage formula was constructed for glmmTMB; coefficient sensitivity is the primary influence diagnostic."),
  paste0("glmmTMB `diagnose()` returned a flag only for large z-statistics on the conditional intercept (",
         fmt5c(beta_diagnostics$conditional_intercept_z, 2), ") and dispersion intercept (",
         fmt5c(beta_diagnostics$dispersion_log_z, 2), "). It reported no bad-parameter, gradient, or Hessian issue; extreme fixed estimate/SE count = ",
         beta_diagnostics$extreme_fixed_estimate_or_se_count, ", dispersion boundary flag = ",
         beta_diagnostics$dispersion_boundary_flag, ". Profile intervals address the stated Wald-approximation caution."),
  "DHARMa was not installed and was optional, so no simulated-residual diagnostics were added.",
  "",
  "## 9. Candidate final inferential model",
  "",
  "The beta-binomial is the recommended candidate final inferential model: it directly models game-level extra-binomial heterogeneity, supplies a comparable likelihood, converged with a positive-definite Hessian, and supports the pre-defined review-volume coefficient sensitivity. Quasibinomial remains an important variance-only cross-check.",
  "",
  "## 10. Limitations and Step 5D recommendation",
  "",
  "These are observational associations in a review-qualified paid-game sample. Step 5D may examine the separately pre-specified threshold, release-month, raw-price, or free-game sensitivities. None was run in Step 5C.",
  "",
  "## 11. Figures",
  "",
  "- `figures/modeling/05_robust_or_comparison.png`",
  "- `figures/modeling/06_ci_width_comparison.png`",
  "- `figures/modeling/07_influence_sensitivity_coefficients.png`",
  "- `figures/modeling/08_review_mass_removed.png`",
  "",
  "Database access remained SELECT-only; before/after frozen object counts are unchanged. No credentials are written to outputs."
)
writeLines(
  report_lines_5c,
  file.path(project_root, "reports", "step5c_robust_reception_report.md"),
  useBytes = TRUE
)

message(sprintf(
  "Step 5C influence sensitivity: PASS (populations=%s, max review mass removed=%.2f%%)",
  paste(vapply(sensitivity_populations, nrow, integer(1)), collapse = "/"),
  100 * max(influence_populations$share_reviews_removed)
))
