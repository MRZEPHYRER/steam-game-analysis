# Same-row Poisson, ordinary NB2, and zero-truncated NB2 comparison.
formula_count_6b <- function(exposure = c("log_days", "offset", "nonlinear"),
                             price_df = 3L, release_month = FALSE) {
  exposure <- match.arg(exposure)
  price_terms <- if (price_df == 3L) paste0("price_spline_", 1:3) else paste0("price_df4_", 1:4)
  terms <- c("is_free", price_terms,
    switch(exposure, log_days = "log_days", offset = "offset(log_days)",
      nonlinear = "splines::ns(log_days, df = 3)"),
    "platform_segment", primary_genres_6b,
    if (release_month) "release_month" else character())
  stats::as.formula(paste("review_count ~", paste(terms, collapse = " + ")))
}
fit_warnings_6b <- list()
capture_fit_6b <- function(model_id, expr) {
  warnings <- character()
  fit <- withCallingHandlers(expr, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  })
  fit_warnings_6b[[model_id]] <<- unique(warnings)
  fit
}
fit_truncated_6b <- function(formula, data, model_id) capture_fit_6b(model_id,
  glmmTMB::glmmTMB(formula, data = data,
    family = glmmTMB::truncated_nbinom2(link = "log"),
    ziformula = ~0, dispformula = ~1))
fit_ok_6b <- function(fit) isTRUE(fit$fit$convergence == 0L) &&
  isTRUE(fit$sdr$pdHess) && is.finite(as.numeric(stats::logLik(fit)))

exposure_fits_6b <- list(
  LOG_DAYS_COVARIATE = fit_truncated_6b(formula_count_6b("log_days"),
    positive_model_6b, "TNB_LOG_DAYS"),
  OFFSET = fit_truncated_6b(formula_count_6b("offset"),
    positive_model_6b, "TNB_OFFSET"),
  NONLINEAR_LOG_DAYS = fit_truncated_6b(formula_count_6b("nonlinear"),
    positive_model_6b, "TNB_NONLINEAR"))
exposure_audit_6b <- do.call(rbind, lapply(names(exposure_fits_6b), function(id) {
  fit <- exposure_fits_6b[[id]]
  data.frame(specification = id, n_games = stats::nobs(fit),
    log_likelihood = as.numeric(stats::logLik(fit)), aic = stats::AIC(fit),
    bic = stats::BIC(fit), parameter_count = attr(stats::logLik(fit), "df"),
    converged = fit_ok_6b(fit), theta = as.numeric(stats::sigma(fit)),
    stringsAsFactors = FALSE)
}))
beta_days_6b <- summary(exposure_fits_6b$LOG_DAYS_COVARIATE)$coefficients$cond["log_days", ]
exposure_audit_6b$beta_log_days <- ifelse(exposure_audit_6b$specification ==
  "LOG_DAYS_COVARIATE", beta_days_6b[1], NA_real_)
exposure_audit_6b$beta_log_days_se <- ifelse(exposure_audit_6b$specification ==
  "LOG_DAYS_COVARIATE", beta_days_6b[2], NA_real_)
exposure_audit_6b$beta_vs_one_z <- ifelse(exposure_audit_6b$specification ==
  "LOG_DAYS_COVARIATE", (beta_days_6b[1] - 1) / beta_days_6b[2], NA_real_)
exposure_audit_6b$delta_aic_from_best <- exposure_audit_6b$aic -
  min(exposure_audit_6b$aic[exposure_audit_6b$converged])
stopifnot(all(exposure_audit_6b$n_games == nrow(positive_model_6b)),
  any(exposure_audit_6b$converged))
selected_exposure_6b <- exposure_audit_6b$specification[which.min(ifelse(
  exposure_audit_6b$converged, exposure_audit_6b$aic, Inf))]
selected_formula_key_6b <- switch(selected_exposure_6b,
  LOG_DAYS_COVARIATE = "log_days", OFFSET = "offset", NONLINEAR_LOG_DAYS = "nonlinear")
primary_truncated_6b <- exposure_fits_6b[[selected_exposure_6b]]
primary_formula_6b <- formula_count_6b(selected_formula_key_6b)
poisson_fit_6b <- capture_fit_6b("POISSON", stats::glm(primary_formula_6b,
  family = stats::poisson(link = "log"), data = positive_model_6b))
nb_fit_6b <- capture_fit_6b("NB2_ORDINARY", MASS::glm.nb(primary_formula_6b,
  data = positive_model_6b, control = stats::glm.control(maxit = 100)))

theta_6b <- as.numeric(stats::sigma(primary_truncated_6b))
mu_latent_6b <- as.numeric(stats::predict(primary_truncated_6b,
  newdata = positive_model_6b, type = "conditional"))
p0_6b <- stats::dnbinom(0, mu = mu_latent_6b, size = theta_6b)
conditional_mean_6b <- function(mu, theta) {
  p0 <- stats::dnbinom(0, mu = mu, size = theta)
  mu / (1 - p0)
}
mean_positive_6b <- conditional_mean_6b(mu_latent_6b, theta_6b)
likelihood_manual_6b <- c(
  poisson = sum(stats::dpois(positive_model_6b$review_count,
    lambda = stats::fitted(poisson_fit_6b), log = TRUE)),
  nb = sum(stats::dnbinom(positive_model_6b$review_count,
    mu = stats::fitted(nb_fit_6b), size = nb_fit_6b$theta, log = TRUE)),
  truncated_nb = sum(stats::dnbinom(positive_model_6b$review_count,
    mu = mu_latent_6b, size = theta_6b, log = TRUE) - log1p(-p0_6b)))
likelihood_package_6b <- c(as.numeric(stats::logLik(poisson_fit_6b)),
  as.numeric(stats::logLik(nb_fit_6b)), as.numeric(stats::logLik(primary_truncated_6b)))
likelihood_constant_ok_6b <- all(abs(likelihood_manual_6b - likelihood_package_6b) < 1e-3)
