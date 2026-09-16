# A free game has no paid-price value; it must not be excluded as missing paid price.
# Keep the source value NA in the descriptive population, but use zero for its
# irrelevant paid-price component in the model matrix.
free_positive_6b <- positive_all_6b[positive_all_6b$is_free == 1L &
  stats::complete.cases(positive_all_6b[, c("review_count", "is_free",
    "days_since_release", "platform_segment", "release_month", primary_genres_6b)]) &
  as.character(positive_all_6b$platform_segment) != "Other" &
  positive_all_6b$days_since_release > 0, ]
free_positive_6b$current_price_usd <- 0
free_positive_6b$platform_segment <- factor(as.character(free_positive_6b$platform_segment),
  levels = levels(positive_model_6b$platform_segment))
free_positive_6b$release_month <- factor(as.character(free_positive_6b$release_month),
  levels = levels(positive_model_6b$release_month))
free_positive_6b$log_days <- log(free_positive_6b$days_since_release)
free_positive_6b$log1p_price <- 0
free_positive_6b <- cbind(free_positive_6b, apply_basis_6b(
  free_positive_6b$current_price_usd, free_positive_6b$is_free, basis_df3_6b))
free_positive_6b <- cbind(free_positive_6b, apply_basis_6b(
  free_positive_6b$current_price_usd, free_positive_6b$is_free,
  basis_df4_6b, "price_df4_"))
positive_model_6b <- dplyr::bind_rows(positive_model_6b, free_positive_6b) |>
  dplyr::arrange(appid)
model_sample_audit_6b$model_n <- nrow(positive_model_6b)
model_sample_audit_6b$excluded_n <- nrow(positive_all_6b) - nrow(positive_model_6b)
stopifnot(nrow(free_positive_6b) == 34L, nrow(positive_model_6b) == 2240L,
  model_sample_audit_6b$excluded_n == 1L,
  sum(positive_model_6b$is_free == 1L) == 34L,
  all(as.matrix(positive_model_6b[positive_model_6b$is_free == 1L,
    paste0("price_spline_", 1:3)]) == 0))
write_attention_audit(model_sample_audit_6b, "step6b_model_sample_audit.csv")
