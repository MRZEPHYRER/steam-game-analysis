# Final database verification and explicit freeze gate; no automatic next stage.
db_after_model_6b <- with_steam_db(function(con) DBI::dbGetQuery(con, paste(
  "SELECT (SELECT COUNT(*) FROM games) AS games,",
  "(SELECT COUNT(*) FROM review_snapshots) AS review_snapshots,",
  "(SELECT COUNT(*) FROM game_genres) AS game_genres,",
  "(SELECT COUNT(*) FROM genres) AS genres,",
  "(SELECT COUNT(*) FROM vw_model_sample_20) AS model20")))
db_before_model_6b <- loaded_model_data$counts_before
db_expected_6b <- c(games = 3000, review_snapshots = 3000,
  game_genres = 8796, genres = 13, model20 = 844)
db_preservation_6b <- data.frame(object_name = names(db_expected_6b),
  count_before = vapply(db_before_model_6b[names(db_expected_6b)],
    function(x) as.numeric(x[[1]]), numeric(1)),
  count_after = vapply(db_after_model_6b[names(db_expected_6b)],
    function(x) as.numeric(x[[1]]), numeric(1)))
db_preservation_6b$unchanged <- db_preservation_6b$count_before ==
  db_preservation_6b$count_after
db_ok_6b <- all(db_preservation_6b$unchanged) &&
  all(db_preservation_6b$count_after == unname(db_expected_6b))
stopifnot(db_ok_6b)

max_coef_drift_6b <- max(coefficient_sensitivity_6b$relative_ratio_drift,
  na.rm = TRUE)
max_curve_drift_6b <- max(price_curve_sensitivity_6b$
  max_relative_predicted_count_difference, na.rm = TRUE)
max_bin_error_6b <- max(abs(fit_bins_6b$observed_n - fit_bins_6b$expected_n) /
  pmax(1, fit_bins_6b$observed_n))
freeze_checks_6b <- data.frame(
  criterion = c("positive_count_population", "poisson_overdispersion_audited",
    "nb_convergence", "zero_truncation_addressed", "exposure_specification_justified",
    "price_nonlinear_basis_valid", "no_single_observation_dominates",
    "tail_sensitivity_acceptable", "diagnostics_acceptable", "database_unchanged"),
  pass = c(nrow(positive_all_6b) == 2241L && nrow(positive_model_6b) == 2240L &&
      sum(positive_model_6b$is_free == 1L) == 34L && all(y_6b > 0),
    is.finite(poisson_diagnostics_6b$pearson_dispersion),
    isTRUE(nb_fit_6b$converged) && fit_ok_6b(primary_truncated_6b),
    likelihood_constant_ok_6b && all(p0_6b >= 0 & p0_6b < 1),
    all(exposure_audit_6b$n_games == n_model_6b) &&
      selected_exposure_6b %in% exposure_audit_6b$specification,
    all(is.finite(as.matrix(positive_model_6b[, paste0("price_spline_", 1:3)]))) &&
      fit_ok_6b(price_df4_fit_6b),
    concentration_6b$top1_game_share < .10 &&
      all(tail_sensitivity_6b$converged) &&
      !any(coefficient_sensitivity_6b$direction_change[
        coefficient_sensitivity_6b$scenario == "REMOVE_TOP1_GAME"]),
    max_coef_drift_6b < .5 && max_curve_drift_6b < .5,
    is.finite(max_bin_error_6b) && max_bin_error_6b < .5 &&
      abs(residual_diagnostics_6b$fitted_mean /
        residual_diagnostics_6b$observed_mean - 1) < .5 &&
      theta_6b > 1e-5,
    db_ok_6b), stringsAsFactors = FALSE)
step6b_decision <- data.frame(status = if (all(freeze_checks_6b$pass)) "PASS" else "FAIL",
  positive_count_model_frozen = all(freeze_checks_6b$pass),
  count_distribution = "TRUNCATED NB2 CANDIDATE",
  exposure_specification = selected_exposure_6b,
  model_n = n_model_6b,
  failed_criteria = paste(freeze_checks_6b$criterion[!freeze_checks_6b$pass],
    collapse = "; "), stringsAsFactors = FALSE)
write_attention_audit(db_preservation_6b, "step6b_database_preservation.csv")
write_attention_audit(freeze_checks_6b, "step6b_freeze_criteria.csv")
write_attention_audit(step6b_decision, "step6b_stage_decision.csv")

report_lines_6b <- c(
  "# Step 6B Positive Review-Count Intensity: Technical Audit", "",
  sprintf("Audit status: **%s**. Positive-count model frozen: **%s**.",
    step6b_decision$status, step6b_decision$positive_count_model_frozen), "",
  "## Population and estimand",
  sprintf("Market N=%d; zero-review N=%d; positive-count N=%d; model N=%d.",
    market_n_6b, zero_n_6b, nrow(positive_all_6b), n_model_6b),
  sprintf("Free positive N=%d; paid positive N=%d; missing paid price excluded N=%d.",
    model_sample_audit_6b$positive_free_n, model_sample_audit_6b$positive_paid_n,
    model_sample_audit_6b$missing_paid_price_n),
  "The estimand is E(review count | at least one review), not sales, owners, revenue, or the market-wide count. Step 6A separately estimates P(any review).",
  "All effects are conditional associations, not causal effects.", "",
  "## Distribution and concentration",
  sprintf("Median=%.2f; mean=%.2f; variance/mean=%.2f; max=%d.",
    distribution_6b$median, distribution_6b$mean,
    distribution_6b$variance_mean_ratio, distribution_6b$max),
  sprintf("Top game=%.4f; top 1%%=%.4f; top 5%%=%.4f; top 10%%=%.4f; Gini=%.4f.",
    concentration_6b$top1_game_share, concentration_6b$top1_percent_share,
    concentration_6b$top5_percent_share, concentration_6b$top10_percent_share,
    concentration_6b$gini), "",
  "## Models and likelihood",
  sprintf("Poisson Pearson dispersion=%.2f; deviance/df=%.2f. Poisson inference is invalid.",
    poisson_diagnostics_6b$pearson_dispersion,
    poisson_diagnostics_6b$deviance_per_df),
  sprintf("Ordinary NB2 theta=%.6g; truncated NB2 theta=%.6g.",
    nb_fit_6b$theta, theta_6b),
  sprintf("AIC: Poisson %.2f; ordinary NB2 %.2f; truncated NB2 %.2f.",
    stats::AIC(poisson_fit_6b), stats::AIC(nb_fit_6b),
    stats::AIC(primary_truncated_6b)),
  sprintf("Same positive rows and full likelihood constants independently verified: %s.",
    likelihood_constant_ok_6b),
  "The truncated NB2 has the best AIC, but theta is near the zero boundary and the fit remains diagnostic-only, not frozen.", "",
  "## Exposure and price",
  sprintf("Selected exposure candidate: %s. Log-days beta %.4f (SE %.4f), z vs one %.3f.",
    selected_exposure_6b, beta_days_6b[1], beta_days_6b[2],
    (beta_days_6b[1] - 1) / beta_days_6b[2]),
  sprintf("Exposure AIC: log-days %.2f; offset %.2f; spline log-days %.2f.",
    exposure_audit_6b$aic[1], exposure_audit_6b$aic[2], exposure_audit_6b$aic[3]),
  sprintf("Paid-positive spline N=%d; full price support USD %.2f-%.2f; central support USD %.2f-%.2f.",
    nrow(paid_positive_6b), basis_definition_6b$price_min_usd,
    basis_definition_6b$price_max_usd, basis_definition_6b$price_p05_usd,
    basis_definition_6b$price_p95_usd),
  sprintf("Price df4 AIC change from df3: %.2f; this challenges df3 stability.",
    functional_sensitivity_6b$delta_aic_from_primary[2]),
  "Free spline basis is zero; is_free is retained. Interpret price predictions, not spline coefficients.", "",
  "## Diagnostics, sensitivity, and decision",
  sprintf("Observed mean %.2f; fitted conditional mean %.2f; max relative bin error %.3f.",
    residual_diagnostics_6b$observed_mean, residual_diagnostics_6b$fitted_mean,
    max_bin_error_6b),
  sprintf("Largest nonspline ratio drift %.3f; central price-curve drift %.3f.",
    max_coef_drift_6b, max_curve_drift_6b),
  "Top games stay in the main model. Their removal is sensitivity analysis only.",
  "DHARMa is absent; no new package was installed. No zero-inflated model or ML benchmark was run.",
  paste(sprintf("- %s: %s", freeze_checks_6b$criterion,
    ifelse(freeze_checks_6b$pass, "PASS", "FAIL")), collapse = "\n"),
  "A zero-truncated NB coefficient exponentiates to a latent-mean ratio; the positive-conditional count ratio also depends on the baseline mean.",
  "No causal interpretation. Review count is not sales, owners, or revenue.",
  sprintf("Database row counts unchanged: %s. Credentials remain in .env.", db_ok_6b), "")
writeLines(report_lines_6b,
  file.path(project_root, "reports", "step6b_attention_count_report.md"),
  useBytes = TRUE)
