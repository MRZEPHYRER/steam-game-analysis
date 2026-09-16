# Step 6A pre-specified natural-spline df=3 functional-form audit.

if (!exists("primary_entry_fit_6a")) {
  stop("Run 02_entry_logistic.R before 03_functional_form_audit.R.", call. = FALSE)
}

days_spline_formula_6a <- stats::as.formula(paste(
  "has_review ~ is_free + z_log1p_paid_price_component +",
  "splines::ns(days_since_release, df = 3) + platform_segment +",
  paste(attention_primary_genres, collapse = " + ")
))
days_spline_result_6a <- fit_glm_with_warnings_6a(days_spline_formula_6a, market_model_data_6a)
days_spline_fit_6a <- days_spline_result_6a$fit
days_spline_warnings_6a <- days_spline_result_6a$warnings
days_lrt_6a <- stats::anova(primary_entry_fit_6a, days_spline_fit_6a, test = "Chisq")

days_grid_6a <- data.frame(days_since_release = seq(
  min(market_model_data_6a$days_since_release),
  max(market_model_data_6a$days_since_release), length.out = 200
))
days_grid_6a$z_days_since_release <-
  (days_grid_6a$days_since_release - days_mean_6a) / days_sd_6a
days_grid_6a$is_free <- 0L
days_grid_6a$z_log1p_paid_price_component <- 0
days_grid_6a$platform_segment <- factor(
  "Windows only", levels = levels(market_model_data_6a$platform_segment)
)
for (genre in attention_primary_genres) days_grid_6a[[genre]] <- 0L
days_curve_6a <- dplyr::bind_rows(
  data.frame(
    model = "Linear", days_since_release = days_grid_6a$days_since_release,
    predicted_probability = as.numeric(stats::predict(primary_entry_fit_6a, days_grid_6a, type = "response"))
  ),
  data.frame(
    model = "Natural spline df=3", days_since_release = days_grid_6a$days_since_release,
    predicted_probability = as.numeric(stats::predict(days_spline_fit_6a, days_grid_6a, type = "response"))
  )
)
days_curve_wide_6a <- tidyr::pivot_wider(
  days_curve_6a, names_from = model, values_from = predicted_probability
)
days_max_probability_gap_6a <- max(abs(
  days_curve_wide_6a$Linear - days_curve_wide_6a$`Natural spline df=3`
))

paid_model_data_6a <- market_model_data_6a |>
  dplyr::filter(is_free == 0L) |>
  dplyr::mutate(z_log1p_price_paid = z_log1p_paid_price_component)
price_linear_formula_6a <- stats::as.formula(paste(
  "has_review ~ z_log1p_price_paid + z_days_since_release + platform_segment +",
  paste(attention_primary_genres, collapse = " + ")
))
price_spline_formula_6a <- stats::as.formula(paste(
  "has_review ~ splines::ns(log1p_current_price_paid, df = 3) +",
  "z_days_since_release + platform_segment +",
  paste(attention_primary_genres, collapse = " + ")
))
price_linear_result_6a <- fit_glm_with_warnings_6a(price_linear_formula_6a, paid_model_data_6a)
price_spline_result_6a <- fit_glm_with_warnings_6a(price_spline_formula_6a, paid_model_data_6a)
price_linear_fit_6a <- price_linear_result_6a$fit
price_spline_fit_6a <- price_spline_result_6a$fit
price_linear_warnings_6a <- price_linear_result_6a$warnings
price_spline_warnings_6a <- price_spline_result_6a$warnings
price_lrt_6a <- stats::anova(price_linear_fit_6a, price_spline_fit_6a, test = "Chisq")

price_grid_6a <- data.frame(current_price_usd = seq(
  min(paid_model_data_6a$current_price_usd),
  max(paid_model_data_6a$current_price_usd), length.out = 200
))
price_grid_6a$log1p_current_price_paid <- log1p(price_grid_6a$current_price_usd)
price_grid_6a$z_log1p_price_paid <-
  (price_grid_6a$log1p_current_price_paid - paid_price_mean_log_6a) / paid_price_sd_log_6a
price_grid_6a$z_days_since_release <- 0
price_grid_6a$platform_segment <- factor(
  "Windows only", levels = levels(paid_model_data_6a$platform_segment)
)
for (genre in attention_primary_genres) price_grid_6a[[genre]] <- 0L
price_curve_6a <- dplyr::bind_rows(
  data.frame(
    model = "Linear log1p", current_price_usd = price_grid_6a$current_price_usd,
    predicted_probability = as.numeric(stats::predict(price_linear_fit_6a, price_grid_6a, type = "response"))
  ),
  data.frame(
    model = "Natural spline df=3", current_price_usd = price_grid_6a$current_price_usd,
    predicted_probability = as.numeric(stats::predict(price_spline_fit_6a, price_grid_6a, type = "response"))
  )
)
price_curve_wide_6a <- tidyr::pivot_wider(
  price_curve_6a, names_from = model, values_from = predicted_probability
)
price_max_probability_gap_6a <- max(abs(
  price_curve_wide_6a$`Linear log1p` - price_curve_wide_6a$`Natural spline df=3`
))

functional_row_6a <- function(model_id, fit, sample_scope, comparison, lrt_p, gap, warnings) {
  data.frame(
    model_id = model_id,
    sample_scope = sample_scope,
    n_games = stats::nobs(fit),
    parameter_count = length(stats::coef(fit)),
    log_likelihood = as.numeric(stats::logLik(fit)),
    aic = stats::AIC(fit), bic = stats::BIC(fit),
    comparison = comparison,
    lrt_p_value_linear_vs_spline = lrt_p,
    max_absolute_probability_gap = gap,
    converged = fit$converged,
    warning_count = length(warnings),
    same_rows_within_comparison = TRUE,
    spline_df = ifelse(grepl("SPLINE", model_id), 3L, NA_integer_),
    stringsAsFactors = FALSE
  )
}
days_lrt_p_6a <- days_lrt_6a$`Pr(>Chi)`[2]
price_lrt_p_6a <- price_lrt_6a$`Pr(>Chi)`[2]
days_functional_form_6a <- dplyr::bind_rows(
  functional_row_6a("LINEAR_DAYS", primary_entry_fit_6a, "Primary complete market sample", "DAYS", days_lrt_p_6a, days_max_probability_gap_6a, primary_entry_warnings_6a),
  functional_row_6a("SPLINE_DAYS_DF3", days_spline_fit_6a, "Primary complete market sample", "DAYS", days_lrt_p_6a, days_max_probability_gap_6a, days_spline_warnings_6a)
)
price_functional_form_6a <- dplyr::bind_rows(
  functional_row_6a("LINEAR_PRICE", price_linear_fit_6a, "Paid primary-model games only", "PAID_PRICE", price_lrt_p_6a, price_max_probability_gap_6a, price_linear_warnings_6a),
  functional_row_6a("SPLINE_PRICE_DF3", price_spline_fit_6a, "Paid primary-model games only", "PAID_PRICE", price_lrt_p_6a, price_max_probability_gap_6a, price_spline_warnings_6a)
)

classify_form_6a <- function(linear_aic, spline_aic, max_gap) {
  delta <- spline_aic - linear_aic
  if (delta <= -10 && max_gap >= 0.05) return("SUBSTANTIVE_NONLINEARITY")
  if (delta <= -2 || max_gap >= 0.03) return("MODEST_NONLINEARITY")
  "APPROXIMATELY_LINEAR"
}
functional_form_decision_6a <- data.frame(
  predictor = c("days_since_release", "paid_log1p_price"),
  linear_aic = c(primary_fit_6a$aic, stats::AIC(price_linear_fit_6a)),
  spline_aic = c(stats::AIC(days_spline_fit_6a), stats::AIC(price_spline_fit_6a)),
  delta_aic_spline_minus_linear = c(
    stats::AIC(days_spline_fit_6a) - primary_fit_6a$aic,
    stats::AIC(price_spline_fit_6a) - stats::AIC(price_linear_fit_6a)
  ),
  max_absolute_probability_gap = c(days_max_probability_gap_6a, price_max_probability_gap_6a),
  lrt_p_value = c(days_lrt_p_6a, price_lrt_p_6a),
  assessment = c(
    classify_form_6a(primary_fit_6a$aic, stats::AIC(days_spline_fit_6a), days_max_probability_gap_6a),
    classify_form_6a(stats::AIC(price_linear_fit_6a), stats::AIC(price_spline_fit_6a), price_max_probability_gap_6a)
  ),
  pre_specified_rule = "Spline df=3; substantive if delta AIC <= -10 and max probability gap >= 0.05",
  stringsAsFactors = FALSE
)

all_functional_fits_6a <- dplyr::bind_rows(days_functional_form_6a, price_functional_form_6a)
if (any(!all_functional_fits_6a$converged) || any(all_functional_fits_6a$warning_count > 0L)) {
  stop("Step 6A functional-form fit failed.", call. = FALSE)
}

write_attention_audit(price_functional_form_6a, "step6a_price_functional_form.csv")
write_attention_audit(days_functional_form_6a, "step6a_days_functional_form.csv")
write_attention_audit(price_curve_6a, "step6a_paid_price_curve.csv")
write_attention_audit(days_curve_6a, "step6a_days_curve.csv")
write_attention_audit(functional_form_decision_6a, "step6a_functional_form_decision.csv")

message("Step 6A functional-form audit: PASS")
