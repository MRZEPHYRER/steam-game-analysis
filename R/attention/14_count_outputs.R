# Model fit records and inferential audit.
fit_record_6b <- function(fit, model_id, distribution, warning_id) {
  ll <- stats::logLik(fit)
  data.frame(model_id = model_id, distribution = distribution,
    n_games = stats::nobs(fit), log_likelihood = as.numeric(ll),
    aic = stats::AIC(fit), bic = stats::BIC(fit),
    parameter_count = attr(ll, "df"), residual_df = stats::nobs(fit) - attr(ll, "df"),
    converged = if (inherits(fit, "glmmTMB")) fit_ok_6b(fit) else isTRUE(fit$converged),
    warning_count = length(fit_warnings_6b[[warning_id]]),
    formula = paste(deparse(stats::formula(fit)), collapse = " "),
    weights_used = FALSE, zero_inflation_used = FALSE,
    offset_used = selected_exposure_6b == "OFFSET", stringsAsFactors = FALSE)
}
poisson_record_6b <- fit_record_6b(poisson_fit_6b, "M1_POISSON", "Poisson", "POISSON")
nb_record_6b <- fit_record_6b(nb_fit_6b, "M2_NB2_ORDINARY", "NB2 ordinary", "NB2_ORDINARY")
nb_record_6b$theta <- nb_fit_6b$theta
truncated_record_6b <- fit_record_6b(primary_truncated_6b, "M3_TRUNCATED_NB2",
  "NB2 zero-truncated", paste0("TNB_", switch(selected_exposure_6b,
    LOG_DAYS_COVARIATE = "LOG_DAYS", OFFSET = "OFFSET", NONLINEAR_LOG_DAYS = "NONLINEAR")))
truncated_record_6b$theta <- theta_6b
model_comparison_6b <- dplyr::bind_rows(poisson_record_6b, nb_record_6b, truncated_record_6b)
model_comparison_6b$same_observed_rows <- all(model_comparison_6b$n_games == nrow(positive_model_6b))
model_comparison_6b$full_likelihood_constants_verified <- likelihood_constant_ok_6b
model_comparison_6b$delta_aic_from_best <- model_comparison_6b$aic - min(model_comparison_6b$aic)
stopifnot(model_comparison_6b$same_observed_rows, likelihood_constant_ok_6b,
  fit_ok_6b(primary_truncated_6b), isTRUE(nb_fit_6b$converged),
  all(is.finite(mean_positive_6b)), all(mean_positive_6b > 0))

poisson_diagnostics_6b <- data.frame(n_games = stats::nobs(poisson_fit_6b),
  deviance = poisson_fit_6b$deviance, residual_df = poisson_fit_6b$df.residual,
  deviance_per_df = poisson_fit_6b$deviance / poisson_fit_6b$df.residual,
  pearson_dispersion = sum(stats::residuals(poisson_fit_6b,
    type = "pearson")^2) / poisson_fit_6b$df.residual)
poisson_diagnostics_6b$inference_valid <- poisson_diagnostics_6b$pearson_dispersion < 2

coef_matrix_6b <- summary(primary_truncated_6b)$coefficients$cond
coefficients_6b <- data.frame(term = rownames(coef_matrix_6b),
  estimate_log_latent_mean = coef_matrix_6b[, 1], std_error = coef_matrix_6b[, 2],
  z_value = coef_matrix_6b[, 3], p_value = coef_matrix_6b[, 4],
  latent_mean_ratio = exp(coef_matrix_6b[, 1]),
  ci95_lower = exp(coef_matrix_6b[, 1] - 1.96 * coef_matrix_6b[, 2]),
  ci95_upper = exp(coef_matrix_6b[, 1] + 1.96 * coef_matrix_6b[, 2]),
  interpretation = ifelse(grepl("price_spline_|ns\\(", rownames(coef_matrix_6b)),
    "Basis term: interpret predictions, not individual coefficient",
    "Latent NB mean ratio; positive-count ratio varies after truncation"),
  row.names = NULL)
fit_warning_table_6b <- do.call(rbind, lapply(names(fit_warnings_6b), function(id) {
  messages <- fit_warnings_6b[[id]]
  if (!length(messages)) return(data.frame(model_id = id, warning = "NONE"))
  data.frame(model_id = id, warning = messages)
}))
write_attention_audit(poisson_record_6b, "step6b_poisson_fit.csv")
write_attention_audit(poisson_diagnostics_6b, "step6b_poisson_diagnostics.csv")
write_attention_audit(nb_record_6b, "step6b_nb_fit.csv")
write_attention_audit(truncated_record_6b, "step6b_truncated_nb_fit.csv")
write_attention_audit(model_comparison_6b, "step6b_model_comparison.csv")
write_attention_audit(exposure_audit_6b, "step6b_exposure_audit.csv")
write_attention_audit(coefficients_6b, "step6b_final_coefficients.csv")
write_attention_audit(fit_warning_table_6b, "step6b_fit_warnings.csv")
