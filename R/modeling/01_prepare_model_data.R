# Load frozen MySQL views and construct audited game-level modeling candidates.

if (!exists("write_model_audit", mode = "function")) {
  .helper_candidates <- c(
    file.path("R", "modeling", "00_model_helpers.R"),
    file.path("modeling", "00_model_helpers.R"),
    "00_model_helpers.R"
  )
  .helper_path <- .helper_candidates[file.exists(.helper_candidates)][1]
  if (is.na(.helper_path)) stop("Could not locate 00_model_helpers.R.", call. = FALSE)
  source(.helper_path)
}

loaded_model_data <- with_steam_db(function(con) {
  counts_before <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "(SELECT COUNT(*) FROM games) AS games,",
      "(SELECT COUNT(*) FROM review_snapshots) AS review_snapshots,",
      "(SELECT COUNT(*) FROM game_genres) AS game_genres,",
      "(SELECT COUNT(*) FROM genres) AS genres,",
      "(SELECT COUNT(*) FROM vw_model_sample_20) AS model20"
    )
  )
  market <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT appid, name, release_date, release_month, is_free,",
      "platform_windows, platform_mac, platform_linux,",
      "list_price_usd, current_price_usd, discount_percent, price_currency,",
      "total_reviews, positive_reviews, negative_reviews, positive_rate,",
      "review_score, review_score_desc, metadata_collected_at, review_collected_at",
      "FROM vw_game_analysis ORDER BY appid"
    )
  )
  genre <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT appid, genre_id, genre_name",
      "FROM vw_game_genres ORDER BY appid, genre_id"
    )
  )
  counts_after <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "(SELECT COUNT(*) FROM games) AS games,",
      "(SELECT COUNT(*) FROM review_snapshots) AS review_snapshots,",
      "(SELECT COUNT(*) FROM game_genres) AS game_genres,",
      "(SELECT COUNT(*) FROM genres) AS genres,",
      "(SELECT COUNT(*) FROM vw_model_sample_20) AS model20"
    )
  )
  list(
    market = market,
    genre = genre,
    counts_before = counts_before,
    counts_after = counts_after
  )
})

games_market_model <- loaded_model_data$market |>
  dplyr::mutate(
    dplyr::across(
      c(
        appid, is_free, platform_windows, platform_mac, platform_linux,
        total_reviews, positive_reviews, negative_reviews, review_score
      ),
      as.integer
    ),
    dplyr::across(
      c(list_price_usd, current_price_usd, discount_percent, positive_rate),
      as.numeric
    ),
    release_date = as.Date(release_date),
    review_collection_date = as.Date(substr(as.character(review_collected_at), 1, 10)),
    metadata_collection_date = as.Date(substr(as.character(metadata_collected_at), 1, 10)),
    days_since_release = as.integer(review_collection_date - release_date),
    release_month = factor(release_month, levels = sprintf("2025-%02d", 7:12)),
    platform_segment = derive_platform_segment(
      platform_windows, platform_mac, platform_linux
    ),
    price_band = derive_price_band(is_free, current_price_usd),
    log1p_current_price = log1p(current_price_usd)
  )

genre_long_model <- loaded_model_data$genre |>
  dplyr::mutate(
    appid = as.integer(appid),
    genre_id = as.integer(genre_id)
  )

genre_names <- sort(unique(genre_long_model$genre_name))
genre_indicator_names <- paste0(
  "genre_",
  gsub(
    "(^_+|_+$)",
    "",
    gsub("[^a-z0-9]+", "_", tolower(genre_names))
  )
)
genre_indicator_mapping <- data.frame(
  genre_name = genre_names,
  indicator = genre_indicator_names,
  stringsAsFactors = FALSE
)

genre_matrix <- xtabs(
  ~ factor(appid, levels = games_market_model$appid) +
    factor(genre_name, levels = genre_names),
  data = genre_long_model
)
genre_wide <- data.frame(
  appid = games_market_model$appid,
  (genre_matrix > 0) * 1L,
  check.names = FALSE
)
names(genre_wide)[-1] <- genre_indicator_names

games_market_wide <- games_market_model |>
  dplyr::left_join(genre_wide, by = "appid")

reception_gt0 <- games_market_wide |>
  dplyr::filter(total_reviews > 0)
reception_10 <- games_market_wide |>
  dplyr::filter(total_reviews >= 10)
reception_20 <- games_market_wide |>
  dplyr::filter(total_reviews >= 20)
reception_50 <- games_market_wide |>
  dplyr::filter(total_reviews >= 50)

model20_all <- reception_20
model20_paid <- model20_all |>
  dplyr::filter(is_free == 0)

complete_case_fields <- c(
  "positive_reviews", "negative_reviews", "total_reviews",
  "current_price_usd", "release_date", "release_month",
  "days_since_release", "platform_segment", genre_indicator_names
)
model20_paid_complete <- model20_paid[
  stats::complete.cases(model20_paid[, complete_case_fields]),
]

write_model_audit(genre_indicator_mapping, "genre_indicator_mapping.csv")

stopifnot(
  nrow(games_market_model) == 3000,
  dplyr::n_distinct(games_market_model$appid) == 3000,
  sum(games_market_model$total_reviews == 0) == 759,
  nrow(reception_gt0) == 2241,
  nrow(reception_10) == 1139,
  nrow(reception_20) == 844,
  nrow(reception_50) == 551,
  all(reception_50$appid %in% reception_20$appid),
  all(reception_20$appid %in% reception_10$appid),
  all(reception_10$appid %in% reception_gt0$appid),
  nrow(genre_wide) == 3000,
  dplyr::n_distinct(genre_wide$appid) == 3000,
  all(unlist(genre_wide[-1]) %in% c(0L, 1L)),
  all(games_market_model$positive_reviews >= 0),
  all(games_market_model$negative_reviews >= 0),
  all(
    games_market_model$positive_reviews + games_market_model$negative_reviews ==
      games_market_model$total_reviews
  ),
  all(model20_all$total_reviews > 0),
  identical(loaded_model_data$counts_before, loaded_model_data$counts_after)
)

message(
  sprintf(
    "Step 5A data preparation: PASS (market=%d, model20=%d, paid=%d, complete=%d)",
    nrow(games_market_model), nrow(model20_all), nrow(model20_paid),
    nrow(model20_paid_complete)
  )
)
