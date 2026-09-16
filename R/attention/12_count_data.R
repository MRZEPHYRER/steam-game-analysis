# Positive-count population, frozen paid-price basis, and descriptive audit.
if (!exists("games_market_wide") || !exists("write_attention_audit")) {
  stop("Load Step 5A data and Step 6A helpers first.", call. = FALSE)
}

primary_genres_6b <- c("genre_action", "genre_adventure", "genre_casual",
  "genre_indie", "genre_rpg", "genre_simulation", "genre_strategy")
market_n_6b <- nrow(games_market_wide)
zero_n_6b <- sum(games_market_wide$total_reviews == 0L)
positive_all_6b <- games_market_wide[games_market_wide$total_reviews > 0L, ]
positive_all_6b$review_count <- as.integer(positive_all_6b$total_reviews)
stopifnot(market_n_6b == 3000L, zero_n_6b == 759L,
  nrow(positive_all_6b) == 2241L, all(positive_all_6b$review_count >= 1L),
  !anyDuplicated(positive_all_6b$appid))

quant_6b <- function(x, p) as.numeric(stats::quantile(x, p, names = FALSE))
y_all_6b <- positive_all_6b$review_count
distribution_6b <- data.frame(
  n = length(y_all_6b), min = min(y_all_6b), p01 = quant_6b(y_all_6b, .01),
  p05 = quant_6b(y_all_6b, .05), p25 = quant_6b(y_all_6b, .25),
  median = stats::median(y_all_6b), mean = mean(y_all_6b),
  p75 = quant_6b(y_all_6b, .75), p90 = quant_6b(y_all_6b, .90),
  p95 = quant_6b(y_all_6b, .95), p99 = quant_6b(y_all_6b, .99),
  max = max(y_all_6b), variance = stats::var(y_all_6b),
  variance_mean_ratio = stats::var(y_all_6b) / mean(y_all_6b))
count_breaks_6b <- c(1, 2, 5, 10, 20, 50, 100, 500, 1000, Inf)
count_labels_6b <- c("1", "2-4", "5-9", "10-19", "20-49", "50-99",
                     "100-499", "500-999", "1000+")
count_bin_6b <- function(y) factor(cut(y, count_breaks_6b, right = FALSE,
  labels = count_labels_6b, include.lowest = TRUE), levels = count_labels_6b)
bin_n_6b <- as.integer(table(count_bin_6b(y_all_6b)))
bins_6b <- data.frame(bin = count_labels_6b, n_games = bin_n_6b,
  percent = 100 * bin_n_6b / length(y_all_6b))
sorted_6b <- sort(y_all_6b, decreasing = TRUE)
gini_6b <- function(x) {
  x <- sort(as.numeric(x)); n <- length(x)
  (2 * sum(seq_len(n) * x) / (n * sum(x))) - (n + 1) / n
}
concentration_6b <- data.frame(
  n_positive_games = length(y_all_6b), total_review_volume = sum(y_all_6b),
  top1_game_share = sorted_6b[1] / sum(sorted_6b),
  top1_percent_n = ceiling(.01 * length(sorted_6b)),
  top1_percent_share = sum(head(sorted_6b, ceiling(.01 * length(sorted_6b)))) / sum(sorted_6b),
  top5_percent_n = ceiling(.05 * length(sorted_6b)),
  top5_percent_share = sum(head(sorted_6b, ceiling(.05 * length(sorted_6b)))) / sum(sorted_6b),
  top10_percent_n = ceiling(.10 * length(sorted_6b)),
  top10_percent_share = sum(head(sorted_6b, ceiling(.10 * length(sorted_6b)))) / sum(sorted_6b),
  gini = gini_6b(sorted_6b))

summarize_count_6b <- function(data) data.frame(
  n_games = nrow(data), median_count = stats::median(data$review_count),
  mean_count = mean(data$review_count), p95_count = quant_6b(data$review_count, .95),
  max_count = max(data$review_count))
free_summary_6b <- do.call(rbind, lapply(c(0L, 1L), function(free) {
  d <- positive_all_6b[positive_all_6b$is_free == free, ]
  cbind(game_type = if (free == 1L) "Free" else "Paid", summarize_count_6b(d))
}))
platform_summary_6b <- do.call(rbind, lapply(split(positive_all_6b,
  positive_all_6b$platform_segment), function(d) {
  cbind(platform_segment = as.character(d$platform_segment[1]), summarize_count_6b(d))
}))
genre_summary_6b <- do.call(rbind, lapply(seq_len(nrow(genre_indicator_mapping)), function(i) {
  indicator <- genre_indicator_mapping$indicator[i]
  d <- positive_all_6b[positive_all_6b[[indicator]] == 1L, ]
  if (!nrow(d)) return(NULL)
  cbind(genre = genre_indicator_mapping$genre_name[i], indicator = indicator,
        summarize_count_6b(d))
}))

model_fields_6b <- c("review_count", "is_free", "current_price_usd",
  "days_since_release", "platform_segment", "release_month", primary_genres_6b)
positive_model_6b <- positive_all_6b[
  stats::complete.cases(positive_all_6b[, model_fields_6b]) &
    as.character(positive_all_6b$platform_segment) != "Other" &
    positive_all_6b$days_since_release > 0, ]
positive_model_6b$platform_segment <- stats::relevel(
  droplevels(positive_model_6b$platform_segment), ref = "Windows only")
positive_model_6b$release_month <- stats::relevel(
  droplevels(positive_model_6b$release_month), ref = "2025-07")
positive_model_6b$log_days <- log(positive_model_6b$days_since_release)
positive_model_6b$log1p_price <- log1p(positive_model_6b$current_price_usd)
stopifnot(nrow(positive_model_6b) <= 2241L,
  all(positive_model_6b$review_count > 0), all(is.finite(positive_model_6b$log_days)),
  all(positive_model_6b$days_since_release > 0),
  all(positive_model_6b$appid %in% positive_all_6b$appid))

make_basis_6b <- function(training_log_price, df, center_log_price) {
  basis <- splines::ns(training_log_price, df = df, intercept = FALSE)
  knots <- as.numeric(attr(basis, "knots"))
  boundary <- as.numeric(attr(basis, "Boundary.knots"))
  center_basis <- as.numeric(splines::ns(center_log_price,
    knots = knots, Boundary.knots = boundary, intercept = FALSE))
  list(df = df, knots = knots, boundary = boundary,
       center_log_price = center_log_price, center_basis = center_basis)
}
apply_basis_6b <- function(price, is_free, definition, prefix = "price_spline_") {
  x <- matrix(NA_real_, length(price), definition$df)
  paid <- is_free == 0L & !is.na(price)
  if (any(paid)) x[paid, ] <- sweep(splines::ns(log1p(price[paid]),
    knots = definition$knots, Boundary.knots = definition$boundary,
    intercept = FALSE), 2, definition$center_basis, "-")
  x[is_free == 1L, ] <- 0
  colnames(x) <- paste0(prefix, seq_len(definition$df))
  x
}
paid_positive_6b <- positive_model_6b[positive_model_6b$is_free == 0L, ]
center_log_6b <- mean(paid_positive_6b$log1p_price)
basis_df3_6b <- make_basis_6b(paid_positive_6b$log1p_price, 3L, center_log_6b)
basis_df4_6b <- make_basis_6b(paid_positive_6b$log1p_price, 4L, center_log_6b)
positive_model_6b <- cbind(positive_model_6b, apply_basis_6b(
  positive_model_6b$current_price_usd, positive_model_6b$is_free, basis_df3_6b))
positive_model_6b <- cbind(positive_model_6b, apply_basis_6b(
  positive_model_6b$current_price_usd, positive_model_6b$is_free,
  basis_df4_6b, "price_df4_"))
stopifnot(all(as.matrix(positive_model_6b[positive_model_6b$is_free == 1L,
  paste0("price_spline_", 1:3)]) == 0),
  all(is.finite(as.matrix(positive_model_6b[, paste0("price_spline_", 1:3)]))))

basis_definition_6b <- data.frame(
  population = "Positive-count paid games with observed price",
  training_n = nrow(paid_positive_6b), df = 3L,
  center_price_usd = expm1(center_log_6b),
  internal_knot_1_log1p = basis_df3_6b$knots[1],
  internal_knot_2_log1p = basis_df3_6b$knots[2],
  boundary_lower_log1p = basis_df3_6b$boundary[1],
  boundary_upper_log1p = basis_df3_6b$boundary[2],
  price_min_usd = min(paid_positive_6b$current_price_usd),
  price_p05_usd = quant_6b(paid_positive_6b$current_price_usd, .05),
  price_median_usd = stats::median(paid_positive_6b$current_price_usd),
  price_p95_usd = quant_6b(paid_positive_6b$current_price_usd, .95),
  price_max_usd = max(paid_positive_6b$current_price_usd),
  step6a1_paid_n = as.integer(utils::read.csv(file.path(attention_audit_dir,
    "step6a1_price_support.csv"))$paid_price_n[1]))
model_sample_audit_6b <- data.frame(market_n = market_n_6b,
  zero_review_n = zero_n_6b, positive_n = nrow(positive_all_6b),
  positive_free_n = sum(positive_all_6b$is_free == 1L),
  positive_paid_n = sum(positive_all_6b$is_free == 0L),
  missing_paid_price_n = sum(positive_all_6b$is_free == 0L &
    is.na(positive_all_6b$current_price_usd)), model_n = nrow(positive_model_6b),
  excluded_n = nrow(positive_all_6b) - nrow(positive_model_6b))

write_attention_audit(distribution_6b, "step6b_count_distribution.csv")
write_attention_audit(bins_6b, "step6b_review_count_bins.csv")
write_attention_audit(concentration_6b, "step6b_concentration.csv")
write_attention_audit(free_summary_6b, "step6b_free_summary.csv")
write_attention_audit(platform_summary_6b, "step6b_platform_summary.csv")
write_attention_audit(genre_summary_6b, "step6b_genre_summary.csv")
write_attention_audit(basis_definition_6b, "step6b_price_basis_definition.csv")
write_attention_audit(model_sample_audit_6b, "step6b_model_sample_audit.csv")
