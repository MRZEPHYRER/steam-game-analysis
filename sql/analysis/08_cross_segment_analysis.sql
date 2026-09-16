-- result: price_by_review_band
-- purpose: Cross-tabulation of collection-time price band and review-volume band.
WITH segmented AS (
  SELECT
    CASE
      WHEN is_free = 1 THEN 'Free'
      WHEN current_price_usd IS NULL THEN 'Paid price missing'
      WHEN current_price_usd < 5 THEN '$0.01-$4.99'
      WHEN current_price_usd < 10 THEN '$5.00-$9.99'
      WHEN current_price_usd < 20 THEN '$10.00-$19.99'
      WHEN current_price_usd < 30 THEN '$20.00-$29.99'
      ELSE '$30.00+'
    END AS price_band,
    CASE
      WHEN is_free = 1 THEN 1 WHEN current_price_usd IS NULL THEN 7
      WHEN current_price_usd < 5 THEN 2 WHEN current_price_usd < 10 THEN 3
      WHEN current_price_usd < 20 THEN 4 WHEN current_price_usd < 30 THEN 5 ELSE 6
    END AS price_order,
    CASE
      WHEN total_reviews = 0 THEN '0' WHEN total_reviews < 10 THEN '1-9'
      WHEN total_reviews < 20 THEN '10-19' WHEN total_reviews < 50 THEN '20-49'
      WHEN total_reviews < 100 THEN '50-99' WHEN total_reviews < 500 THEN '100-499'
      WHEN total_reviews < 1000 THEN '500-999' ELSE '1000+'
    END AS review_band,
    CASE
      WHEN total_reviews = 0 THEN 1 WHEN total_reviews < 10 THEN 2
      WHEN total_reviews < 20 THEN 3 WHEN total_reviews < 50 THEN 4
      WHEN total_reviews < 100 THEN 5 WHEN total_reviews < 500 THEN 6
      WHEN total_reviews < 1000 THEN 7 ELSE 8
    END AS review_order,
    positive_rate
  FROM vw_game_analysis
)
SELECT
  price_band,
  review_band,
  COUNT(*) AS games,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate
FROM segmented
GROUP BY price_band, price_order, review_band, review_order
ORDER BY price_order, review_order;

-- result: genre_by_payment
-- purpose: Cross-tabulation of genre membership and free/paid status.
SELECT
  ge.genre_name,
  SUM(g.is_free = 1) AS free_games,
  SUM(g.is_free = 0) AS paid_games,
  COUNT(*) AS genre_games,
  ROUND(100 * AVG(g.is_free = 1), 2) AS free_share_pct
FROM genres ge
JOIN game_genres gg ON gg.genre_id = ge.genre_id
JOIN games g ON g.appid = gg.appid
GROUP BY ge.genre_id, ge.genre_name
ORDER BY genre_games DESC, ge.genre_name;

-- result: release_month_candidate_share
-- purpose: Release month crossed with membership in the >=20-review candidate sample.
SELECT
  release_month,
  COUNT(*) AS games,
  SUM(total_reviews >= 20) AS reviews_ge_20_games,
  ROUND(100 * AVG(total_reviews >= 20), 2) AS reviews_ge_20_share_pct
FROM vw_game_analysis
GROUP BY release_month
ORDER BY release_month;
