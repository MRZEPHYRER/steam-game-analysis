# Population, response, price, timing, platform, concentration, and missingness audits.
# This script deliberately fits no outcome model.

if (!exists("games_market_wide")) {
  .prepare_candidates <- c(
    file.path("R", "modeling", "01_prepare_model_data.R"),
    file.path("modeling", "01_prepare_model_data.R"),
    "01_prepare_model_data.R"
  )
  .prepare_path <- .prepare_candidates[file.exists(.prepare_candidates)][1]
  if (is.na(.prepare_path)) stop("Could not locate 01_prepare_model_data.R.", call. = FALSE)
  source(.prepare_path)
}

sample_flow <- data.frame(
  stage = c(
    "Market sample", "At least 1 review", "At least 10 reviews",
    "At least 20 reviews", "At least 50 reviews", "Model20 paid",
    "Model20 paid complete-case"
  ),
  n = c(
    nrow(games_market_wide), nrow(reception_gt0), nrow(reception_10),
    nrow(reception_20), nrow(reception_50), nrow(model20_paid),
    nrow(model20_paid_complete)
  ),
  exclusion_reason = c(
    "None", "Zero review denominator", "Fewer than 10 reviews",
    "Fewer than 20 reviews", "Fewer than 50 reviews",
    "Free-game exclusion", "Missing required model field"
  ),
  stringsAsFactors = FALSE
)
sample_flow$removed_from_previous <- c(0L, 759L, 1102L, 295L, 293L, 8L, 0L)

threshold_sets <- list(
  reception_gt0 = reception_gt0,
  reception_10 = reception_10,
  reception_20 = reception_20,
  reception_50 = reception_50
)
sample_threshold_summary <- do.call(
  rbind,
  lapply(names(threshold_sets), function(label) {
    data <- threshold_sets[[label]]
    data.frame(
      sample = label,
      n_games = nrow(data),
      unique_appids = dplyr::n_distinct(data$appid),
      positive_reviews = sum(data$positive_reviews),
      negative_reviews = sum(data$negative_reviews),
      total_reviews = sum(data$total_reviews),
      minimum_reviews = min(data$total_reviews),
      stringsAsFactors = FALSE
    )
  })
)

model20_population_audit <- model20_all |>
  dplyr::summarise(
    n_games = dplyr::n(),
    unique_appids = dplyr::n_distinct(appid),
    median_total_reviews = stats::median(total_reviews),
    mean_total_reviews = mean(total_reviews),
    q1_total_reviews = stats::quantile(total_reviews, 0.25),
    q3_total_reviews = stats::quantile(total_reviews, 0.75),
    min_total_reviews = min(total_reviews),
    max_total_reviews = max(total_reviews),
    positive_reviews_total = sum(positive_reviews),
    negative_reviews_total = sum(negative_reviews),
    total_reviews = sum(total_reviews),
    free_games = sum(is_free == 1),
    paid_games = sum(is_free == 0),
    free_share = mean(is_free == 1),
    paid_share = mean(is_free == 0)
  )

genre_summary_by_game <- genre_long_model |>
  dplyr::group_by(appid) |>
  dplyr::summarise(
    genre_summary = paste(sort(genre_name), collapse = " | "),
    .groups = "drop"
  )
free_game_audit <- model20_all |>
  dplyr::filter(is_free == 1) |>
  dplyr::left_join(genre_summary_by_game, by = "appid") |>
  dplyr::select(
    appid, name, total_reviews, positive_reviews, negative_reviews,
    positive_rate, release_month, platform_segment, genre_summary
  ) |>
  dplyr::arrange(appid)

price_audit <- model20_paid |>
  dplyr::summarise(
    n_games = dplyr::n(),
    missing_current_price = sum(is.na(current_price_usd)),
    missing_list_price = sum(is.na(list_price_usd)),
    min_current_price = min(current_price_usd, na.rm = TRUE),
    q1_current_price = stats::quantile(current_price_usd, 0.25, na.rm = TRUE),
    median_current_price = stats::median(current_price_usd, na.rm = TRUE),
    mean_current_price = mean(current_price_usd, na.rm = TRUE),
    q3_current_price = stats::quantile(current_price_usd, 0.75, na.rm = TRUE),
    max_current_price = max(current_price_usd, na.rm = TRUE),
    sd_current_price = stats::sd(current_price_usd, na.rm = TRUE),
    skewness_current_price = skewness_value(current_price_usd),
    skewness_log1p_price = skewness_value(log1p_current_price)
  )

release_timing_audit <- model20_paid |>
  dplyr::summarise(
    n_games = dplyr::n(),
    release_date_missing = sum(is.na(release_date)),
    review_collected_at_missing = sum(is.na(review_collected_at)),
    days_since_release_missing = sum(is.na(days_since_release)),
    non_positive_days = sum(days_since_release <= 0, na.rm = TRUE),
    min_days = min(days_since_release, na.rm = TRUE),
    q1_days = stats::quantile(days_since_release, 0.25, na.rm = TRUE),
    median_days = stats::median(days_since_release, na.rm = TRUE),
    mean_days = mean(days_since_release, na.rm = TRUE),
    q3_days = stats::quantile(days_since_release, 0.75, na.rm = TRUE),
    max_days = max(days_since_release, na.rm = TRUE),
    unique_review_collection_dates = dplyr::n_distinct(review_collection_date),
    min_review_collection_date = min(review_collection_date),
    max_review_collection_date = max(review_collection_date),
    month_index_days_correlation = stats::cor(
      as.integer(release_month), days_since_release
    )
  )

release_month_audit <- dplyr::bind_rows(
  model20_all |>
    dplyr::group_by(release_month) |>
    dplyr::summarise(
      sample = "model20_all", n_games = dplyr::n(),
      median_total_reviews = stats::median(total_reviews),
      median_positive_rate = stats::median(positive_rate), .groups = "drop"
    ),
  model20_paid |>
    dplyr::group_by(release_month) |>
    dplyr::summarise(
      sample = "model20_paid", n_games = dplyr::n(),
      median_total_reviews = stats::median(total_reviews),
      median_positive_rate = stats::median(positive_rate), .groups = "drop"
    )
) |>
  dplyr::group_by(sample) |>
  dplyr::mutate(share = n_games / sum(n_games)) |>
  dplyr::ungroup()

days_by_release_month <- model20_paid |>
  dplyr::group_by(release_month) |>
  dplyr::summarise(
    n_games = dplyr::n(),
    min_days = min(days_since_release),
    q1_days = stats::quantile(days_since_release, 0.25),
    median_days = stats::median(days_since_release),
    mean_days = mean(days_since_release),
    q3_days = stats::quantile(days_since_release, 0.75),
    max_days = max(days_since_release),
    .groups = "drop"
  )

platform_frequency_for <- function(data, label) {
  data |>
    dplyr::count(platform_segment, name = "n_games", .drop = FALSE) |>
    dplyr::mutate(
      sample = label,
      share = n_games / sum(n_games),
      sparse_lt20 = n_games < 20,
      sparse_lt10 = n_games < 10,
      sparse_lt5 = n_games < 5
    ) |>
    dplyr::select(sample, platform_segment, n_games, share, dplyr::starts_with("sparse_"))
}
platform_frequency <- dplyr::bind_rows(
  platform_frequency_for(games_market_wide, "market"),
  platform_frequency_for(model20_all, "model20_all"),
  platform_frequency_for(model20_paid, "model20_paid")
)

reception_summary_for <- function(data, label) {
  rates <- data$positive_reviews / data$total_reviews
  data.frame(
    sample = label,
    n_games = nrow(data),
    positive_reviews = sum(data$positive_reviews),
    negative_reviews = sum(data$negative_reviews),
    total_reviews = sum(data$total_reviews),
    pooled_positive_rate = sum(data$positive_reviews) / sum(data$total_reviews),
    median_game_positive_rate = stats::median(rates),
    q1_game_positive_rate = stats::quantile(rates, 0.25),
    q3_game_positive_rate = stats::quantile(rates, 0.75),
    perfect_rate_games = sum(rates == 1),
    zero_rate_games = sum(rates == 0),
    stringsAsFactors = FALSE
  )
}
reception_distribution <- dplyr::bind_rows(
  reception_summary_for(reception_gt0, "reception_gt0"),
  reception_summary_for(reception_10, "reception_10"),
  reception_summary_for(reception_20, "reception_20"),
  reception_summary_for(reception_50, "reception_50"),
  reception_summary_for(model20_paid, "model20_paid")
)

denominator_distribution <- data.frame(
  statistic = c("min", "p05", "p10", "p25", "median", "p75", "p90", "p95", "p99", "max", "mean", "sd"),
  value = c(
    min(model20_all$total_reviews),
    stats::quantile(model20_all$total_reviews, 0.05),
    stats::quantile(model20_all$total_reviews, 0.10),
    stats::quantile(model20_all$total_reviews, 0.25),
    stats::median(model20_all$total_reviews),
    stats::quantile(model20_all$total_reviews, 0.75),
    stats::quantile(model20_all$total_reviews, 0.90),
    stats::quantile(model20_all$total_reviews, 0.95),
    stats::quantile(model20_all$total_reviews, 0.99),
    max(model20_all$total_reviews),
    mean(model20_all$total_reviews),
    stats::sd(model20_all$total_reviews)
  )
)

write_model_audit(sample_flow, "sample_flow.csv")
write_model_audit(sample_threshold_summary, "sample_threshold_summary.csv")
write_model_audit(model20_population_audit, "model20_population_audit.csv")
write_model_audit(free_game_audit, "free_game_audit.csv")
write_model_audit(price_audit, "price_audit.csv")
write_model_audit(release_timing_audit, "release_timing_audit.csv")
write_model_audit(release_month_audit, "release_month_audit.csv")
write_model_audit(days_by_release_month, "days_by_release_month.csv")
write_model_audit(platform_frequency, "platform_frequency.csv")
write_model_audit(reception_distribution, "reception_distribution.csv")
write_model_audit(denominator_distribution, "denominator_distribution.csv")

ranked_reviews <- model20_all |>
  dplyr::arrange(dplyr::desc(total_reviews), appid)
total_eligible_reviews <- sum(ranked_reviews$total_reviews)
concentration_cutoffs <- c(
  1L, 5L, 10L, 20L,
  ceiling(0.01 * nrow(ranked_reviews)),
  ceiling(0.05 * nrow(ranked_reviews)),
  ceiling(0.10 * nrow(ranked_reviews))
)
review_concentration <- data.frame(
  group = c("top_1", "top_5", "top_10", "top_20", "top_1pct", "top_5pct", "top_10pct"),
  n_games = concentration_cutoffs,
  review_count = vapply(
    concentration_cutoffs,
    function(n) sum(ranked_reviews$total_reviews[seq_len(n)]),
    numeric(1)
  ),
  stringsAsFactors = FALSE
)
review_concentration$total_eligible_reviews <- total_eligible_reviews
review_concentration$review_share <- (
  review_concentration$review_count / total_eligible_reviews
)

top_review_contributors <- ranked_reviews |>
  dplyr::slice_head(n = 20) |>
  dplyr::left_join(genre_summary_by_game, by = "appid") |>
  dplyr::select(
    appid, name, total_reviews, positive_reviews, negative_reviews,
    positive_rate, current_price_usd, release_date, genre_summary,
    platform_segment
  )

missingness_for <- function(data, label) {
  fields <- c(
    "positive_reviews", "negative_reviews", "total_reviews",
    "current_price_usd", "list_price_usd", "discount_percent",
    "release_date", "release_month", "days_since_release", "platform_segment"
  )
  data.frame(
    sample = label,
    field = fields,
    missing_n = vapply(fields, function(field) sum(is.na(data[[field]])), integer(1)),
    denominator = nrow(data),
    stringsAsFactors = FALSE
  ) |>
    dplyr::mutate(missing_pct = 100 * missing_n / denominator)
}
missingness_model_fields <- dplyr::bind_rows(
  missingness_for(model20_all, "model20_all"),
  missingness_for(model20_paid, "model20_paid")
)

group_outcome <- function(data, group_column, group_label) {
  data |>
    dplyr::group_by(segment = .data[[group_column]]) |>
    dplyr::summarise(
      n_games = dplyr::n(),
      positive_reviews = sum(positive_reviews),
      negative_reviews = sum(negative_reviews),
      total_reviews = sum(total_reviews),
      pooled_positive_rate = positive_reviews / total_reviews,
      median_game_positive_rate = stats::median(positive_rate),
      .groups = "drop"
    ) |>
    dplyr::mutate(segment_type = group_label, .before = 1)
}
outcome_heterogeneity <- dplyr::bind_rows(
  group_outcome(model20_paid, "price_band", "price_band"),
  group_outcome(model20_paid, "release_month", "release_month"),
  group_outcome(model20_paid, "platform_segment", "platform_segment")
)

write_model_audit(review_concentration, "review_concentration.csv")
write_model_audit(top_review_contributors, "top_review_contributors.csv")
write_model_audit(missingness_model_fields, "missingness_model_fields.csv")
write_model_audit(outcome_heterogeneity, "outcome_heterogeneity.csv")

stopifnot(
  model20_population_audit$n_games == 844,
  model20_population_audit$free_games == 8,
  model20_population_audit$paid_games == 836,
  nrow(model20_paid_complete) == 836,
  release_timing_audit$days_since_release_missing == 0,
  release_timing_audit$non_positive_days == 0,
  nrow(top_review_contributors) == 20,
  all(sample_threshold_summary$n_games == sample_threshold_summary$unique_appids),
  identical(loaded_model_data$counts_before, loaded_model_data$counts_after)
)
