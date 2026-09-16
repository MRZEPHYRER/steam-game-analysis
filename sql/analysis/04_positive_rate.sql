-- result: positive_rate_by_review_volume
-- purpose: Observed positivity by review-volume band, excluding zero-review games.
WITH banded AS (
  SELECT
    appid,
    CASE
      WHEN total_reviews < 10 THEN '1-9'
      WHEN total_reviews < 20 THEN '10-19'
      WHEN total_reviews < 50 THEN '20-49'
      WHEN total_reviews < 100 THEN '50-99'
      WHEN total_reviews < 500 THEN '100-499'
      WHEN total_reviews < 1000 THEN '500-999'
      ELSE '1000+'
    END AS review_band,
    CASE
      WHEN total_reviews < 10 THEN 1 WHEN total_reviews < 20 THEN 2
      WHEN total_reviews < 50 THEN 3 WHEN total_reviews < 100 THEN 4
      WHEN total_reviews < 500 THEN 5 WHEN total_reviews < 1000 THEN 6 ELSE 7
    END AS band_order,
    positive_rate
  FROM vw_game_analysis
  WHERE total_reviews > 0
), ranked AS (
  SELECT
         appid,
         review_band,
         band_order,
         positive_rate,
         ROW_NUMBER() OVER (PARTITION BY review_band ORDER BY positive_rate, appid) AS rate_row,
         COUNT(*) OVER (PARTITION BY review_band) AS group_count
  FROM banded
)
SELECT
  review_band,
  COUNT(*) AS games,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate,
  ROUND(AVG(CASE WHEN rate_row IN ((group_count + 1) DIV 2, (group_count + 2) DIV 2)
                 THEN positive_rate END), 4) AS median_positive_rate,
  ROUND(100 * AVG(positive_rate = 1), 2) AS perfect_positive_share_pct
FROM ranked
GROUP BY review_band, band_order
ORDER BY band_order;

-- result: positive_rate_by_payment
-- purpose: Observed positivity among reviewed free and paid games.
WITH ranked AS (
  SELECT
    CASE WHEN is_free = 1 THEN 'Free' ELSE 'Paid' END AS payment_segment,
    appid,
    positive_rate,
    ROW_NUMBER() OVER (PARTITION BY is_free ORDER BY positive_rate, appid) AS rate_row,
    COUNT(*) OVER (PARTITION BY is_free) AS group_count
  FROM vw_game_analysis
  WHERE total_reviews > 0
)
SELECT
  payment_segment,
  COUNT(*) AS games,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate,
  ROUND(AVG(CASE WHEN rate_row IN ((group_count + 1) DIV 2, (group_count + 2) DIV 2)
                 THEN positive_rate END), 4) AS median_positive_rate,
  ROUND(100 * AVG(positive_rate = 1), 2) AS perfect_positive_share_pct
FROM ranked
GROUP BY payment_segment
ORDER BY payment_segment;
