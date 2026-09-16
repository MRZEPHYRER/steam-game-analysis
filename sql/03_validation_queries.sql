-- Core table and view row counts.
SELECT 'games' AS metric, COUNT(*) AS value FROM games
UNION ALL SELECT 'genres', COUNT(*) FROM genres
UNION ALL SELECT 'game_genres', COUNT(*) FROM game_genres
UNION ALL SELECT 'review_snapshots', COUNT(*) FROM review_snapshots
UNION ALL SELECT 'price_snapshots', COUNT(*) FROM price_snapshots
UNION ALL SELECT 'collection_runs', COUNT(*) FROM collection_runs
UNION ALL SELECT 'vw_game_analysis', COUNT(*) FROM vw_game_analysis
UNION ALL SELECT 'vw_game_genres', COUNT(*) FROM vw_game_genres
UNION ALL SELECT 'vw_model_sample_20', COUNT(*) FROM vw_model_sample_20;

-- Foreign-key coverage; all values must be zero.
SELECT 'orphan_game_genres_appid' AS metric, COUNT(*) AS value
FROM game_genres gg LEFT JOIN games g ON g.appid = gg.appid
WHERE g.appid IS NULL
UNION ALL
SELECT 'orphan_game_genres_genre_id', COUNT(*)
FROM game_genres gg LEFT JOIN genres ge ON ge.genre_id = gg.genre_id
WHERE ge.genre_id IS NULL
UNION ALL
SELECT 'orphan_review_appid', COUNT(*)
FROM review_snapshots r LEFT JOIN games g ON g.appid = r.appid
WHERE g.appid IS NULL
UNION ALL
SELECT 'orphan_price_appid', COUNT(*)
FROM price_snapshots p LEFT JOIN games g ON g.appid = p.appid
WHERE g.appid IS NULL;

-- Review integrity; all failure values must be zero.
SELECT
  SUM(total_reviews < 0 OR positive_reviews < 0 OR negative_reviews < 0)
    AS negative_count_failures,
  SUM(positive_reviews + negative_reviews <> total_reviews)
    AS count_identity_failures,
  SUM(
    total_reviews = 0
    AND (
      positive_reviews <> 0
      OR negative_reviews <> 0
      OR positive_rate IS NOT NULL
      OR review_status <> 'success'
    )
  ) AS zero_review_semantic_failures,
  SUM(positive_rate IS NOT NULL AND positive_rate NOT BETWEEN 0 AND 1)
    AS positive_rate_range_failures
FROM review_snapshots;

-- Expected thresholds: 1,139; 844; 551.
SELECT
  SUM(total_reviews >= 10) AS reviews_ge_10,
  SUM(total_reviews >= 20) AS reviews_ge_20,
  SUM(total_reviews >= 50) AS reviews_ge_50
FROM review_snapshots;

-- Expected market and platform counts.
SELECT
  SUM(is_free = 1) AS free_games,
  SUM(is_free = 0) AS paid_games,
  SUM(platform_windows = 1) AS windows_games,
  SUM(platform_mac = 1) AS mac_games,
  SUM(platform_linux = 1) AS linux_games,
  SUM(developer IS NULL) AS missing_developer,
  SUM(publisher IS NULL) AS missing_publisher
FROM games;

-- Expected price metrics: 2,597 priced; 403 missing; all priced currency USD.
SELECT
  SUM(list_price_cents IS NOT NULL) AS priced_rows,
  SUM(list_price_cents IS NULL) AS missing_price_rows,
  SUM(price_currency = 'USD') AS usd_rows,
  SUM(list_price_cents < 0 OR current_price_cents < 0)
    AS negative_price_rows,
  SUM(current_price_cents > list_price_cents)
    AS current_above_list_rows
FROM price_snapshots;

-- Expected genre relations=8,796, genres=13, games without genres=0.
SELECT
  (SELECT COUNT(*) FROM game_genres) AS genre_relation_rows,
  (SELECT COUNT(*) FROM genres) AS unique_genres,
  (
    SELECT COUNT(*)
    FROM games g
    LEFT JOIN game_genres gg ON gg.appid = g.appid
    WHERE gg.appid IS NULL
  ) AS games_without_genres;
