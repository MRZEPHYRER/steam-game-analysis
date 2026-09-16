# Positive-count attention tiers and deterministic paid-price basis.
if (!exists("games_market_wide") || !exists("write_attention_audit")) {
  stop("Load Step 5A data and attention helpers first.", call. = FALSE)
}

primary_genres_6b1 <- c("genre_action", "genre_adventure", "genre_casual",
  "genre_indie", "genre_rpg", "genre_simulation", "genre_strategy")
platform_levels_6b1 <- c("Windows only", "Windows + macOS", "Windows + Linux",
  "Windows + macOS + Linux")
tier_levels_6b1 <- c("Tier1", "Tier2", "Tier3", "Tier4")
assign_tier_6b1 <- function(x) factor(cut(x,
  breaks = c(1, 10, 100, 1000, Inf), right = FALSE,
  labels = tier_levels_6b1, include.lowest = TRUE),
  levels = tier_levels_6b1, ordered = TRUE)

positive_all_6b1 <- games_market_wide |>
  dplyr::filter(total_reviews > 0L) |>
  dplyr::mutate(
    review_count = as.integer(total_reviews),
    attention_tier = assign_tier_6b1(total_reviews),
    high_attention_100 = as.integer(total_reviews >= 100L),
    platform_segment = factor(as.character(platform_segment),
      levels = platform_levels_6b1)
  ) |>
  dplyr::arrange(appid)
stopifnot(nrow(games_market_wide) == 3000L,
  sum(games_market_wide$total_reviews == 0L) == 759L,
  nrow(positive_all_6b1) == 2241L,
  all(positive_all_6b1$review_count > 0L),
  identical(levels(positive_all_6b1$attention_tier), tier_levels_6b1),
  is.ordered(positive_all_6b1$attention_tier), !anyDuplicated(positive_all_6b1$appid))

tier_distribution_6b1 <- positive_all_6b1 |>
  dplyr::group_by(attention_tier, .drop = FALSE) |>
  dplyr::summarise(
    n_games = dplyr::n(), percent = 100 * dplyr::n() / nrow(positive_all_6b1),
    free_n = sum(is_free == 1L), paid_n = sum(is_free == 0L),
    median_review_count = stats::median(review_count), .groups = "drop")
tier_composition_6b1 <- positive_all_6b1 |>
  dplyr::mutate(game_type = ifelse(is_free == 1L, "Free", "Paid")) |>
  dplyr::count(attention_tier, game_type, name = "n_games") |>
  dplyr::group_by(attention_tier) |>
  dplyr::mutate(percent_within_tier = 100 * n_games / sum(n_games)) |>
  dplyr::ungroup()
tier_platform_6b1 <- positive_all_6b1 |>
  dplyr::filter(!is.na(platform_segment)) |>
  dplyr::count(platform_segment, attention_tier, name = "n_games") |>
  dplyr::group_by(platform_segment) |>
  dplyr::mutate(percent_within_platform = 100 * n_games / sum(n_games)) |>
  dplyr::ungroup()
tier_genre_6b1 <- dplyr::bind_rows(lapply(primary_genres_6b1, function(indicator) {
  positive_all_6b1 |>
    dplyr::filter(.data[[indicator]] == 1L) |>
    dplyr::count(attention_tier, name = "n_games") |>
    dplyr::mutate(indicator = indicator, total_genre_n = sum(n_games),
      percent_within_genre = 100 * n_games / total_genre_n)
}))

model_fields_6b1 <- c("review_count", "attention_tier", "high_attention_100",
  "is_free", "days_since_release", "platform_segment", primary_genres_6b1)
model_data_6b1 <- positive_all_6b1[
  stats::complete.cases(positive_all_6b1[, model_fields_6b1]) &
    (positive_all_6b1$is_free == 1L | !is.na(positive_all_6b1$current_price_usd)) &
    positive_all_6b1$days_since_release > 0L, ]
model_data_6b1$current_price_usd[model_data_6b1$is_free == 1L &
  is.na(model_data_6b1$current_price_usd)] <- 0
model_data_6b1$platform_segment <- stats::relevel(
  droplevels(model_data_6b1$platform_segment), ref = "Windows only")
model_data_6b1$log_days <- log(model_data_6b1$days_since_release)
model_data_6b1$log1p_price <- log1p(model_data_6b1$current_price_usd)

make_tier_basis_6b1 <- function(training_log_price, df = 3L) {
  center <- mean(training_log_price)
  basis <- splines::ns(training_log_price, df = df, intercept = FALSE)
  knots <- as.numeric(attr(basis, "knots"))
  boundary <- as.numeric(attr(basis, "Boundary.knots"))
  center_basis <- as.numeric(splines::ns(center, knots = knots,
    Boundary.knots = boundary, intercept = FALSE))
  list(df = df, center = center, knots = knots, boundary = boundary,
    center_basis = center_basis)
}
apply_tier_basis_6b1 <- function(price, is_free, definition) {
  x <- matrix(NA_real_, nrow = length(price), ncol = definition$df)
  paid <- is_free == 0L & !is.na(price)
  if (any(paid)) {
    x[paid, ] <- sweep(splines::ns(log1p(price[paid]),
      knots = definition$knots, Boundary.knots = definition$boundary,
      intercept = FALSE), 2, definition$center_basis, "-")
  }
  x[is_free == 1L, ] <- 0
  colnames(x) <- paste0("tier_price_spline_", seq_len(definition$df))
  x
}
paid_positive_6b1 <- model_data_6b1[model_data_6b1$is_free == 0L, ]
price_basis_6b1 <- make_tier_basis_6b1(paid_positive_6b1$log1p_price, 3L)
model_data_6b1 <- cbind(model_data_6b1, apply_tier_basis_6b1(
  model_data_6b1$current_price_usd, model_data_6b1$is_free, price_basis_6b1))
price_terms_6b1 <- paste0("tier_price_spline_", 1:3)
stopifnot(nrow(model_data_6b1) == 2240L,
  sum(model_data_6b1$is_free == 1L) == 34L,
  all(model_data_6b1$review_count > 0L),
  all(as.matrix(model_data_6b1[model_data_6b1$is_free == 1L,
    price_terms_6b1]) == 0),
  all(is.finite(as.matrix(model_data_6b1[, price_terms_6b1]))))

price_basis_table_6b1 <- data.frame(
  population = "Positive-count paid games with observed current price",
  training_n = nrow(paid_positive_6b1), df = 3L,
  center_price_usd = expm1(price_basis_6b1$center),
  internal_knot_1_log1p = price_basis_6b1$knots[1],
  internal_knot_2_log1p = price_basis_6b1$knots[2],
  boundary_lower_log1p = price_basis_6b1$boundary[1],
  boundary_upper_log1p = price_basis_6b1$boundary[2],
  price_min_usd = min(paid_positive_6b1$current_price_usd),
  price_max_usd = max(paid_positive_6b1$current_price_usd),
  stringsAsFactors = FALSE)
model_sample_6b1 <- data.frame(positive_population_n = nrow(positive_all_6b1),
  zero_review_excluded_n = sum(games_market_wide$total_reviews == 0L),
  model_n = nrow(model_data_6b1), model_excluded_n = nrow(positive_all_6b1) - nrow(model_data_6b1),
  free_model_n = sum(model_data_6b1$is_free == 1L),
  paid_model_n = sum(model_data_6b1$is_free == 0L),
  missing_paid_price_excluded_n = sum(positive_all_6b1$is_free == 0L &
    is.na(positive_all_6b1$current_price_usd)))

write_attention_audit(tier_distribution_6b1, "step6b1_tier_distribution.csv")
write_attention_audit(tier_composition_6b1, "step6b1_tier_composition.csv")
write_attention_audit(tier_platform_6b1, "step6b1_tier_platform_composition.csv")
write_attention_audit(tier_genre_6b1, "step6b1_tier_genre_composition.csv")
write_attention_audit(price_basis_table_6b1, "step6b1_price_basis_definition.csv")
write_attention_audit(model_sample_6b1, "step6b1_model_sample.csv")
write_attention_audit(model_data_6b1[, c("appid", "review_count", "attention_tier",
  "high_attention_100", "is_free", "current_price_usd", "days_since_release",
  "log_days", "platform_segment", primary_genres_6b1, price_terms_6b1)],
  "step6b1_model_data.csv")
