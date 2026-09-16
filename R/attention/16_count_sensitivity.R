# Frozen-basis head-tail, df4 price, and release-month checks.
ranked_6b <- order(positive_model_6b$review_count, decreasing = TRUE)
n_model_6b <- nrow(positive_model_6b)
tail_sets_6b <- list(FULL = positive_model_6b,
  REMOVE_TOP1_GAME = positive_model_6b[-ranked_6b[1], ],
  REMOVE_TOP1_PERCENT_BY_REVIEW_COUNT = positive_model_6b[-head(ranked_6b,
    ceiling(.01 * n_model_6b)), ],
  REMOVE_TOP5_PERCENT_BY_REVIEW_COUNT = positive_model_6b[-head(ranked_6b,
    ceiling(.05 * n_model_6b)), ])
tail_fits_6b <- list(FULL = primary_truncated_6b)
for (id in setdiff(names(tail_sets_6b), "FULL")) {
  tail_fits_6b[[id]] <- fit_truncated_6b(primary_formula_6b,
    tail_sets_6b[[id]], paste0("TAIL_", id))
}
tail_sensitivity_6b <- do.call(rbind, lapply(names(tail_fits_6b), function(id) {
  fit <- tail_fits_6b[[id]]; d <- tail_sets_6b[[id]]
  data.frame(scenario = id, n_games = nrow(d),
    removed_n = n_model_6b - nrow(d),
    retained_review_share = sum(d$review_count) / sum(positive_model_6b$review_count),
    theta = as.numeric(stats::sigma(fit)),
    converged = fit_ok_6b(fit), aic = stats::AIC(fit),
    warning_count = length(fit_warnings_6b[[paste0("TAIL_", id)]]))
}))
coef_full_6b <- glmmTMB::fixef(primary_truncated_6b)$cond
non_spline_terms_6b <- names(coef_full_6b)[!grepl("price_spline_|ns\\(", names(coef_full_6b))]
coefficient_sensitivity_6b <- do.call(rbind, lapply(setdiff(names(tail_fits_6b), "FULL"),
  function(id) {
    new_coef <- glmmTMB::fixef(tail_fits_6b[[id]])$cond[non_spline_terms_6b]
    full_coef <- coef_full_6b[non_spline_terms_6b]
    data.frame(scenario = id, term = non_spline_terms_6b,
      latent_ratio_full = exp(full_coef), latent_ratio_sensitivity = exp(new_coef),
      relative_ratio_drift = abs(exp(new_coef) / exp(full_coef) - 1),
      direction_change = sign(full_coef) != sign(new_coef), row.names = NULL)
  }))
central_grid_6b <- price_grid_data_6b[price_curve_6b$central_support, ]
price_curve_sensitivity_6b <- do.call(rbind, lapply(c("REMOVE_TOP1_PERCENT_BY_REVIEW_COUNT",
  "REMOVE_TOP5_PERCENT_BY_REVIEW_COUNT"), function(id) {
  full_pred <- predict_positive_6b(primary_truncated_6b, central_grid_6b)
  tail_pred <- predict_positive_6b(tail_fits_6b[[id]], central_grid_6b)
  data.frame(scenario = id,
    central_price_min_usd = min(central_grid_6b$current_price_usd),
    central_price_max_usd = max(central_grid_6b$current_price_usd),
    max_abs_log_mean_difference = max(abs(log(tail_pred) - log(full_pred))),
    max_relative_predicted_count_difference = max(abs(tail_pred / full_pred - 1)))
}))
price_curve_tail_points_6b <- data.frame(price_usd = central_grid_6b$current_price_usd,
  full = predict_positive_6b(primary_truncated_6b, central_grid_6b),
  remove_top1_percent = predict_positive_6b(
    tail_fits_6b$REMOVE_TOP1_PERCENT_BY_REVIEW_COUNT, central_grid_6b),
  remove_top5_percent = predict_positive_6b(
    tail_fits_6b$REMOVE_TOP5_PERCENT_BY_REVIEW_COUNT, central_grid_6b))
price_df4_fit_6b <- fit_truncated_6b(formula_count_6b(selected_formula_key_6b,
  price_df = 4L), positive_model_6b, "PRICE_DF4")
release_month_fit_6b <- fit_truncated_6b(formula_count_6b(selected_formula_key_6b,
  release_month = TRUE), positive_model_6b, "RELEASE_MONTH")
functional_sensitivity_6b <- data.frame(
  candidate = c("PRIMARY_DF3", "PRICE_DF4", "RELEASE_MONTH"),
  n_games = n_model_6b,
  aic = c(stats::AIC(primary_truncated_6b), stats::AIC(price_df4_fit_6b),
    stats::AIC(release_month_fit_6b)),
  converged = c(fit_ok_6b(primary_truncated_6b), fit_ok_6b(price_df4_fit_6b),
    fit_ok_6b(release_month_fit_6b)))
functional_sensitivity_6b$delta_aic_from_primary <-
  functional_sensitivity_6b$aic - functional_sensitivity_6b$aic[1]
fit_warning_table_6b <- do.call(rbind, lapply(names(fit_warnings_6b), function(id) {
  messages <- fit_warnings_6b[[id]]
  if (!length(messages)) return(data.frame(model_id = id, warning = "NONE"))
  data.frame(model_id = id, warning = messages)
}))
write_attention_audit(tail_sensitivity_6b, "step6b_tail_sensitivity.csv")
write_attention_audit(coefficient_sensitivity_6b, "step6b_coefficient_sensitivity.csv")
write_attention_audit(price_curve_sensitivity_6b, "step6b_price_curve_sensitivity.csv")
write_attention_audit(price_curve_tail_points_6b, "step6b_price_curve_tail_points.csv")
write_attention_audit(functional_sensitivity_6b, "step6b_functional_sensitivity.csv")
write_attention_audit(fit_warning_table_6b, "step6b_fit_warnings.csv")
