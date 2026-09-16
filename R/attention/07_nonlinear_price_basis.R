# Step 6A.1 frozen paid-price spline basis and support audit.

if (!exists("market_model_data_6a") || !exists("paid_price_population_6a")) {
  stop("Run the Step 6A data audit before Step 6A.1.", call. = FALSE)
}

make_price_basis_definition_6a1 <- function(training_log_price, df, center_log_price) {
  training_basis <- splines::ns(training_log_price, df = df, intercept = FALSE)
  knots <- as.numeric(attr(training_basis, "knots"))
  boundary_knots <- as.numeric(attr(training_basis, "Boundary.knots"))
  center_basis <- as.numeric(splines::ns(
    center_log_price,
    knots = knots,
    Boundary.knots = boundary_knots,
    intercept = FALSE
  ))
  list(
    df = df,
    knots = knots,
    boundary_knots = boundary_knots,
    center_log_price = center_log_price,
    center_basis = center_basis
  )
}

apply_price_basis_6a1 <- function(price_usd, is_free, definition, prefix = "price_spline_") {
  result <- matrix(NA_real_, nrow = length(price_usd), ncol = definition$df)
  paid_valid <- is_free == 0L & !is.na(price_usd)
  free_rows <- is_free == 1L
  if (any(paid_valid)) {
    raw_basis <- splines::ns(
      log1p(price_usd[paid_valid]),
      knots = definition$knots,
      Boundary.knots = definition$boundary_knots,
      intercept = FALSE
    )
    result[paid_valid, ] <- sweep(raw_basis, 2, definition$center_basis, "-")
  }
  result[free_rows, ] <- 0
  colnames(result) <- paste0(prefix, seq_len(definition$df))
  result
}

paid_log_price_training_6a1 <- paid_price_population_6a$log1p_paid_price
price_center_log_6a1 <- mean(paid_log_price_training_6a1)
price_center_usd_6a1 <- expm1(price_center_log_6a1)
price_basis_df3_6a1 <- make_price_basis_definition_6a1(
  paid_log_price_training_6a1,
  df = 3L,
  center_log_price = price_center_log_6a1
)

market_model_data_6a1 <- market_model_data_6a
price_basis_matrix_6a1 <- apply_price_basis_6a1(
  market_model_data_6a1$current_price_usd,
  market_model_data_6a1$is_free,
  price_basis_df3_6a1
)
market_model_data_6a1 <- dplyr::bind_cols(
  market_model_data_6a1,
  as.data.frame(price_basis_matrix_6a1, check.names = FALSE)
)

price_spline_terms_6a1 <- colnames(price_basis_matrix_6a1)
if (nrow(market_model_data_6a1) != 2998L ||
    sum(market_model_data_6a1$is_free == 1L) != 402L ||
    anyDuplicated(market_model_data_6a1$appid) ||
    any(!is.finite(as.matrix(market_model_data_6a1[, price_spline_terms_6a1]))) ||
    any(as.matrix(market_model_data_6a1[
      market_model_data_6a1$is_free == 1L, price_spline_terms_6a1
    ]) != 0)) {
  stop("Step 6A.1 paid-price spline parameterization audit failed.", call. = FALSE)
}

internal_knots_6a1 <- rep(NA_real_, 3L)
internal_knots_6a1[seq_along(price_basis_df3_6a1$knots)] <- price_basis_df3_6a1$knots
center_basis_6a1 <- rep(NA_real_, 4L)
center_basis_6a1[seq_along(price_basis_df3_6a1$center_basis)] <- price_basis_df3_6a1$center_basis
price_basis_definition_table_6a1 <- data.frame(
  spline_df = price_basis_df3_6a1$df,
  intercept_in_basis = FALSE,
  centered_basis = TRUE,
  center_price_usd = price_center_usd_6a1,
  center_log1p_price = price_center_log_6a1,
  center_basis_1_raw = center_basis_6a1[1],
  center_basis_2_raw = center_basis_6a1[2],
  center_basis_3_raw = center_basis_6a1[3],
  internal_knot_1_log1p = internal_knots_6a1[1],
  internal_knot_2_log1p = internal_knots_6a1[2],
  internal_knot_3_log1p = internal_knots_6a1[3],
  boundary_knot_lower_log1p = price_basis_df3_6a1$boundary_knots[1],
  boundary_knot_upper_log1p = price_basis_df3_6a1$boundary_knots[2],
  training_n = length(paid_log_price_training_6a1),
  training_price_min_usd = min(paid_price_population_6a1$current_price_usd),
  training_price_max_usd = max(paid_price_population_6a1$current_price_usd),
  prediction_rule = "Reuse saved knots, Boundary.knots, and centering basis; free rows equal zero",
  stringsAsFactors = FALSE
)

price_quantiles_6a1 <- stats::quantile(
  paid_price_population_6a1$current_price_usd,
  probs = c(0.01, 0.05, 0.25, 0.50, 0.75, 0.95, 0.99),
  names = FALSE,
  type = 7
)
price_support_6a1 <- data.frame(
  paid_price_n = nrow(paid_price_population_6a1),
  min_usd = min(paid_price_population_6a1$current_price_usd),
  p01_usd = price_quantiles_6a1[1],
  p05_usd = price_quantiles_6a1[2],
  p25_usd = price_quantiles_6a1[3],
  p50_usd = price_quantiles_6a1[4],
  p75_usd = price_quantiles_6a1[5],
  p95_usd = price_quantiles_6a1[6],
  p99_usd = price_quantiles_6a1[7],
  max_usd = max(paid_price_population_6a1$current_price_usd),
  n_ge_20_usd = sum(paid_price_population_6a1$current_price_usd >= 20),
  n_ge_30_usd = sum(paid_price_population_6a1$current_price_usd >= 30),
  n_ge_50_usd = sum(paid_price_population_6a1$current_price_usd >= 50),
  n_ge_100_usd = sum(paid_price_population_6a1$current_price_usd >= 100),
  central_support_definition = "Paid-market empirical 5th to 95th percentile",
  stringsAsFactors = FALSE
)

write_attention_audit(price_basis_definition_table_6a1, "step6a1_spline_basis_definition.csv")
write_attention_audit(price_support_6a1, "step6a1_price_support.csv")
write_attention_audit(market_model_data_6a1, "step6a1_model_data.csv")

message("Step 6A.1 frozen price basis and support audit: PASS")
