# Market-level descriptive summaries used throughout Step 4B.

review_band_levels <- c(
  "0", "1-9", "10-19", "20-49", "50-99",
  "100-499", "500-999", "1000+"
)

games_market <- games_market |>
  dplyr::mutate(
    review_band = factor(
      dplyr::case_when(
        total_reviews == 0 ~ "0",
        total_reviews < 10 ~ "1-9",
        total_reviews < 20 ~ "10-19",
        total_reviews < 50 ~ "20-49",
        total_reviews < 100 ~ "50-99",
        total_reviews < 500 ~ "100-499",
        total_reviews < 1000 ~ "500-999",
        TRUE ~ "1000+"
      ),
      levels = review_band_levels
    )
  )

market_overview <- data.frame(
  metric = c(
    "market_games", "model20_games", "zero_review_games",
    "reviewed_games", "free_games", "paid_games"
  ),
  value = c(
    nrow(games_market),
    nrow(games_model20),
    sum(games_market$total_reviews == 0),
    sum(games_market$total_reviews > 0),
    sum(games_market$is_free == 1),
    sum(games_market$is_free == 0)
  )
)

review_band_summary <- games_market |>
  dplyr::count(review_band, name = "games", .drop = FALSE) |>
  dplyr::mutate(share_pct = 100 * games / sum(games))

payment_summary <- games_market |>
  dplyr::group_by(payment_segment) |>
  dplyr::summarise(
    games = dplyr::n(),
    zero_review_games = sum(total_reviews == 0),
    zero_review_pct = 100 * mean(total_reviews == 0),
    model20_games = sum(total_reviews >= 20),
    model20_pct = 100 * mean(total_reviews >= 20),
    median_reviews = stats::median(total_reviews),
    .groups = "drop"
  )

utils::write.csv(
  market_overview,
  file.path(r_analysis_dir, "market_overview.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  review_band_summary,
  file.path(r_analysis_dir, "review_band_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  payment_summary,
  file.path(r_analysis_dir, "payment_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  missingness_summary,
  file.path(r_analysis_dir, "missingness_summary.csv"),
  row.names = FALSE,
  na = ""
)

stopifnot(
  sum(review_band_summary$games) == 3000,
  market_overview$value[market_overview$metric == "zero_review_games"] == 759
)
