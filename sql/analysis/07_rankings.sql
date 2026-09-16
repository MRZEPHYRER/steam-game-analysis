-- result: top_review_volume_games
-- purpose: Top 20 observed high-review-volume games (attention proxy, not sales).
WITH ranked AS (
  SELECT
    appid,
    name,
    release_month,
    is_free,
    current_price_usd,
    total_reviews,
    positive_rate,
    review_score_desc,
    PERCENT_RANK() OVER (ORDER BY total_reviews, appid) AS review_volume_percentile
  FROM vw_game_analysis
)
SELECT
  appid,
  name,
  release_month,
  is_free,
  current_price_usd,
  total_reviews,
  positive_rate,
  review_score_desc,
  ROUND(review_volume_percentile, 6) AS review_volume_percentile
FROM ranked
ORDER BY total_reviews DESC, appid
LIMIT 20;

-- result: top_positive_rate_games
-- purpose: Top 20 observed positivity among games with at least 20 reviews.
SELECT
  appid,
  name,
  release_month,
  is_free,
  current_price_usd,
  total_reviews,
  positive_rate,
  review_score_desc
FROM vw_game_analysis
WHERE total_reviews >= 20
ORDER BY positive_rate DESC, total_reviews DESC, appid
LIMIT 20;

-- result: high_attention_profile
-- purpose: Descriptive profile of the top review-volume ventile (top 5 percent).
WITH ventiles AS (
  SELECT
    appid,
    is_free,
    current_price_usd,
    total_reviews,
    positive_rate,
    release_month,
    NTILE(20) OVER (ORDER BY total_reviews DESC, appid) AS attention_ventile
  FROM vw_game_analysis
)
SELECT
  COUNT(*) AS games,
  MIN(total_reviews) AS minimum_total_reviews,
  ROUND(AVG(total_reviews), 2) AS avg_total_reviews,
  ROUND(AVG(LN(1 + total_reviews)), 4) AS avg_log1p_total_reviews,
  ROUND(100 * AVG(is_free = 1), 2) AS free_share_pct,
  ROUND(AVG(current_price_usd), 2) AS avg_current_price_usd,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate
FROM ventiles
WHERE attention_ventile = 1;

-- result: high_attention_genres
-- purpose: Genre composition of the top review-volume ventile.
WITH ventiles AS (
  SELECT appid, NTILE(20) OVER (ORDER BY total_reviews DESC, appid) AS attention_ventile
  FROM vw_game_analysis
)
SELECT
  ge.genre_name,
  COUNT(*) AS high_attention_games,
  ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM ventiles WHERE attention_ventile = 1), 2)
    AS high_attention_membership_pct
FROM ventiles v
JOIN game_genres gg ON gg.appid = v.appid
JOIN genres ge ON ge.genre_id = gg.genre_id
WHERE v.attention_ventile = 1
GROUP BY ge.genre_id, ge.genre_name
ORDER BY high_attention_games DESC, ge.genre_name;

-- result: high_attention_release_month
-- purpose: Release-month composition of the top review-volume ventile.
WITH ventiles AS (
  SELECT appid, release_month,
         NTILE(20) OVER (ORDER BY total_reviews DESC, appid) AS attention_ventile
  FROM vw_game_analysis
)
SELECT
  release_month,
  COUNT(*) AS high_attention_games,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM ventiles
WHERE attention_ventile = 1
GROUP BY release_month
ORDER BY release_month;
