# Load the three analytical datasets directly from frozen MySQL views.

if (!exists("theme_steam_analysis", mode = "function")) {
  .candidates <- c(
    file.path("R", "analysis", "00_helpers.R"),
    file.path("analysis", "00_helpers.R"),
    "00_helpers.R"
  )
  .path <- .candidates[file.exists(.candidates)][1]
  if (is.na(.path)) stop("Could not locate 00_helpers.R.", call. = FALSE)
  source(.path)
}

loaded <- with_steam_db(function(con) {
  counts_before <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "(SELECT COUNT(*) FROM games) AS games,",
      "(SELECT COUNT(*) FROM review_snapshots) AS reviews,",
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
      "review_score, review_score_desc",
      "FROM vw_game_analysis ORDER BY appid"
    )
  )
  model20 <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT appid, name, release_date, release_month, is_free,",
      "platform_windows, platform_mac, platform_linux,",
      "list_price_usd, current_price_usd, discount_percent, price_currency,",
      "total_reviews, positive_reviews, negative_reviews, positive_rate,",
      "review_score, review_score_desc",
      "FROM vw_model_sample_20 ORDER BY appid"
    )
  )
  genre <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT vg.appid, vg.genre_id, vg.genre_name, v.is_free,",
      "v.release_month, v.current_price_usd, v.total_reviews, v.positive_rate",
      "FROM vw_game_genres vg",
      "JOIN vw_game_analysis v ON v.appid = vg.appid",
      "ORDER BY vg.genre_id, vg.appid"
    )
  )
  missingness <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "SUM(publisher IS NULL) AS publisher_missing",
      "FROM games"
    )
  )
  counts_after <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "(SELECT COUNT(*) FROM games) AS games,",
      "(SELECT COUNT(*) FROM review_snapshots) AS reviews,",
      "(SELECT COUNT(*) FROM game_genres) AS game_genres,",
      "(SELECT COUNT(*) FROM genres) AS genres,",
      "(SELECT COUNT(*) FROM vw_model_sample_20) AS model20"
    )
  )
  list(
    market = market,
    model20 = model20,
    genre = genre,
    missingness = missingness,
    counts_before = counts_before,
    counts_after = counts_after
  )
})

games_market <- loaded$market |>
  dplyr::mutate(
    dplyr::across(
      c(appid, is_free, platform_windows, platform_mac, platform_linux,
        total_reviews, positive_reviews, negative_reviews, review_score),
      as.integer
    ),
    dplyr::across(
      c(list_price_usd, current_price_usd, discount_percent, positive_rate),
      as.numeric
    ),
    release_month = factor(release_month, levels = sprintf("2025-%02d", 7:12)),
    payment_segment = factor(ifelse(is_free == 1, "Free", "Paid"), levels = c("Free", "Paid")),
    price_band = derive_price_band(is_free, current_price_usd),
    platform_segment = derive_platform_segment(platform_windows, platform_mac, platform_linux),
    log10_reviews = log10(1 + total_reviews),
    model20 = total_reviews >= 20
  )
games_model20 <- loaded$model20 |>
  dplyr::mutate(
    dplyr::across(
      c(appid, is_free, platform_windows, platform_mac, platform_linux,
        total_reviews, positive_reviews, negative_reviews, review_score),
      as.integer
    ),
    dplyr::across(
      c(list_price_usd, current_price_usd, discount_percent, positive_rate),
      as.numeric
    ),
    release_month = factor(release_month, levels = levels(games_market$release_month)),
    payment_segment = factor(ifelse(is_free == 1, "Free", "Paid"), levels = c("Free", "Paid")),
    price_band = derive_price_band(is_free, current_price_usd),
    platform_segment = derive_platform_segment(platform_windows, platform_mac, platform_linux),
    log10_reviews = log10(1 + total_reviews),
    model20 = TRUE
  )
games_genres <- loaded$genre |>
  dplyr::mutate(
    dplyr::across(c(appid, genre_id, is_free, total_reviews), as.integer),
    dplyr::across(c(current_price_usd, positive_rate), as.numeric),
    release_month = factor(release_month, levels = levels(games_market$release_month)),
    payment_segment = factor(ifelse(is_free == 1, "Free", "Paid"), levels = c("Free", "Paid"))
  )

stopifnot(
  nrow(games_market) == 3000,
  dplyr::n_distinct(games_market$appid) == 3000,
  nrow(games_model20) == 844,
  dplyr::n_distinct(games_model20$appid) == 844,
  nrow(games_genres) == 8796,
  sum(games_market$total_reviews == 0) == 759,
  all(is.na(games_market$positive_rate[games_market$total_reviews == 0])),
  all(!is.na(games_market$positive_rate[games_market$total_reviews > 0])),
  identical(loaded$counts_before, loaded$counts_after)
)

missingness_summary <- data.frame(
  field = c("current_price_usd", "publisher", "positive_rate"),
  missing_n = c(
    sum(is.na(games_market$current_price_usd)),
    as.integer(loaded$missingness$publisher_missing[[1]]),
    sum(is.na(games_market$positive_rate))
  ),
  denominator = 3000L,
  stringsAsFactors = FALSE
) |>
  dplyr::mutate(missing_pct = 100 * missing_n / denominator)

message("R EDA data load: PASS (market=3000, model20=844, genres=8796)")
