# Step 6A market-population and predictor audit.

if (!exists("games_market_wide") || !exists("genre_indicator_mapping")) {
  stop("Run the frozen Step 5A data preparation before Step 6A.", call. = FALSE)
}

attention_primary_genres <- c(
  "genre_action", "genre_adventure", "genre_casual", "genre_indie",
  "genre_rpg", "genre_simulation", "genre_strategy"
)
attention_expanded_genres <- c("genre_early_access", "genre_sports", "genre_racing")
attention_all_genres <- genre_indicator_mapping$indicator
required_genres_6a <- c(attention_primary_genres, attention_expanded_genres)
if (!all(required_genres_6a %in% names(games_market_wide))) {
  stop("Required Step 6A genre indicators are missing.", call. = FALSE)
}

paid_price_population_6a <- games_market_wide |>
  dplyr::filter(is_free == 0L, !is.na(current_price_usd)) |>
  dplyr::mutate(log1p_paid_price = log1p(current_price_usd))
paid_price_missing_6a <- games_market_wide |>
  dplyr::filter(is_free == 0L, is.na(current_price_usd)) |>
  dplyr::select(appid, name, is_free, current_price_usd, total_reviews)

paid_price_mean_log_6a <- mean(paid_price_population_6a$log1p_paid_price)
paid_price_sd_log_6a <- stats::sd(paid_price_population_6a$log1p_paid_price)
if (!is.finite(paid_price_sd_log_6a) || paid_price_sd_log_6a <= 0) {
  stop("Invalid paid-market log-price scaling.", call. = FALSE)
}

days_population_6a <- games_market_wide |>
  dplyr::filter(!is.na(days_since_release))
days_mean_6a <- mean(days_population_6a$days_since_release)
days_sd_6a <- stats::sd(days_population_6a$days_since_release)

market_attention_6a <- games_market_wide |>
  dplyr::mutate(
    has_review = as.integer(total_reviews > 0L),
    log1p_current_price_paid = dplyr::if_else(
      is_free == 0L, log1p(current_price_usd), NA_real_
    ),
    z_log1p_paid_price_component = dplyr::case_when(
      is_free == 1L ~ 0,
      !is.na(current_price_usd) ~
        (log1p(current_price_usd) - paid_price_mean_log_6a) / paid_price_sd_log_6a,
      TRUE ~ NA_real_
    ),
    z_days_since_release = (days_since_release - days_mean_6a) / days_sd_6a
  ) |>
  dplyr::arrange(appid)

primary_complete_fields_6a <- c(
  "has_review", "is_free", "z_log1p_paid_price_component",
  "z_days_since_release", "platform_segment", "release_month",
  attention_primary_genres, attention_expanded_genres
)
market_model_data_6a <- market_attention_6a[
  stats::complete.cases(market_attention_6a[, primary_complete_fields_6a]),
] |>
  dplyr::filter(as.character(platform_segment) != "Other") |>
  dplyr::mutate(
    platform_segment = stats::relevel(droplevels(platform_segment), ref = "Windows only"),
    release_month = stats::relevel(release_month, ref = "2025-07")
  )

if (nrow(market_attention_6a) != 3000L ||
    sum(market_attention_6a$has_review) != 2241L ||
    sum(market_attention_6a$has_review == 0L) != 759L ||
    anyDuplicated(market_attention_6a$appid) ||
    any(market_attention_6a$has_review != as.integer(market_attention_6a$total_reviews > 0L)) ||
    any(market_model_data_6a$z_log1p_paid_price_component[market_model_data_6a$is_free == 1L] != 0)) {
  stop("Step 6A market or free-price parameterization audit failed.", call. = FALSE)
}

market_outcome_summary_6a <- data.frame(
  market_n = nrow(market_attention_6a),
  has_review_n = sum(market_attention_6a$has_review),
  zero_review_n = sum(market_attention_6a$has_review == 0L),
  has_review_rate = mean(market_attention_6a$has_review),
  unique_appids = dplyr::n_distinct(market_attention_6a$appid),
  stringsAsFactors = FALSE
)

free_paid_summary_6a <- market_attention_6a |>
  dplyr::mutate(game_type = ifelse(is_free == 1L, "Free", "Paid")) |>
  dplyr::group_by(game_type) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    has_review_n = sum(has_review),
    zero_review_n = sum(has_review == 0L),
    has_review_rate = mean(has_review),
    has_review_percent = 100 * has_review_rate,
    .groups = "drop"
  )
free_rate_6a <- free_paid_summary_6a$has_review_rate[free_paid_summary_6a$game_type == "Free"]
paid_rate_6a <- free_paid_summary_6a$has_review_rate[free_paid_summary_6a$game_type == "Paid"]
free_paid_summary_6a$raw_risk_difference_free_minus_paid <- free_rate_6a - paid_rate_6a
free_paid_summary_6a$raw_odds_ratio_free_vs_paid <-
  (free_rate_6a / (1 - free_rate_6a)) / (paid_rate_6a / (1 - paid_rate_6a))

month_summary_6a <- market_attention_6a |>
  dplyr::group_by(release_month) |>
  dplyr::summarise(
    n_games = dplyr::n(), has_review_n = sum(has_review),
    zero_review_n = sum(has_review == 0L),
    has_review_rate = mean(has_review), has_review_percent = 100 * has_review_rate,
    .groups = "drop"
  )
platform_summary_6a <- market_attention_6a |>
  dplyr::group_by(platform_segment) |>
  dplyr::summarise(
    n_games = dplyr::n(), has_review_n = sum(has_review),
    zero_review_n = sum(has_review == 0L),
    has_review_rate = mean(has_review), has_review_percent = 100 * has_review_rate,
    .groups = "drop"
  )
genre_summary_6a <- dplyr::bind_rows(lapply(seq_len(nrow(genre_indicator_mapping)), function(i) {
  indicator <- genre_indicator_mapping$indicator[i]
  label <- genre_indicator_mapping$genre_name[i]
  present <- market_attention_6a[[indicator]] == 1L
  data.frame(
    genre = label, indicator = indicator,
    n_games = sum(present),
    has_review_n = sum(market_attention_6a$has_review[present]),
    zero_review_n = sum(market_attention_6a$has_review[present] == 0L),
    has_review_rate = mean(market_attention_6a$has_review[present]),
    has_review_percent = 100 * mean(market_attention_6a$has_review[present]),
    stringsAsFactors = FALSE
  )
})) |>
  dplyr::arrange(dplyr::desc(n_games), genre)

paid_price_scaling_6a <- data.frame(
  scaling_population = "All paid market games with non-missing current price",
  paid_price_n = nrow(paid_price_population_6a),
  current_price_mean_usd = mean(paid_price_population_6a$current_price_usd),
  current_price_sd_usd = stats::sd(paid_price_population_6a$current_price_usd),
  current_price_median_usd = stats::median(paid_price_population_6a$current_price_usd),
  current_price_min_usd = min(paid_price_population_6a$current_price_usd),
  current_price_max_usd = max(paid_price_population_6a$current_price_usd),
  log1p_price_mean = paid_price_mean_log_6a,
  log1p_price_sd = paid_price_sd_log_6a,
  missing_paid_price_n = nrow(paid_price_missing_6a),
  stringsAsFactors = FALSE
)
days_scaling_6a <- data.frame(
  scaling_population = "All market games with non-missing days_since_release",
  n_games = nrow(days_population_6a),
  mean_days = days_mean_6a,
  sd_days = days_sd_6a,
  min_days = min(days_population_6a$days_since_release),
  max_days = max(days_population_6a$days_since_release),
  stringsAsFactors = FALSE
)
sample_exclusions_6a <- data.frame(
  reason = c(
    "paid_current_price_missing", "days_since_release_missing",
    "platform_segment_outside_prespecified_four", "primary_model_total_excluded"
  ),
  n_games = c(
    nrow(paid_price_missing_6a),
    sum(is.na(market_attention_6a$days_since_release)),
    sum(as.character(market_attention_6a$platform_segment) == "Other"),
    nrow(market_attention_6a) - nrow(market_model_data_6a)
  ),
  handling = c(
    "Retained in market descriptive denominator; excluded from price-containing models",
    "Retained in market descriptive denominator; excluded from primary model",
    "Retained in market descriptive denominator; excluded rather than creating a sparse fifth platform level",
    "Complete-case exclusions only for pre-specified primary fields"
  ),
  stringsAsFactors = FALSE
)

db_before_6a <- vapply(loaded_model_data$counts_before, function(x) as.numeric(x[[1]]), numeric(1))
db_after_6a <- vapply(loaded_model_data$counts_after, function(x) as.numeric(x[[1]]), numeric(1))
database_preservation_6a <- data.frame(
  object_name = names(db_before_6a), count_before = db_before_6a,
  count_after = db_after_6a, unchanged = db_before_6a == db_after_6a
)
if (!all(database_preservation_6a$unchanged)) stop("Database changed during Step 6A load.", call. = FALSE)

write_attention_audit(market_outcome_summary_6a, "step6a_market_outcome_summary.csv")
write_attention_audit(free_paid_summary_6a, "step6a_free_paid_summary.csv")
write_attention_audit(month_summary_6a, "step6a_month_summary.csv")
write_attention_audit(platform_summary_6a, "step6a_platform_summary.csv")
write_attention_audit(genre_summary_6a, "step6a_genre_summary.csv")
write_attention_audit(paid_price_scaling_6a, "step6a_paid_price_scaling.csv")
write_attention_audit(paid_price_missing_6a, "step6a_missing_paid_price.csv")
write_attention_audit(days_scaling_6a, "step6a_days_scaling.csv")
write_attention_audit(sample_exclusions_6a, "step6a_sample_exclusions.csv")
write_attention_audit(market_attention_6a, "step6a_market_data.csv")
write_attention_audit(database_preservation_6a, "step6a_database_preservation.csv")

message(sprintf(
  "Step 6A data audit: PASS (market=%d, events=%d, zero=%d, model=%d)",
  nrow(market_attention_6a), sum(market_attention_6a$has_review),
  sum(market_attention_6a$has_review == 0L), nrow(market_model_data_6a)
))
