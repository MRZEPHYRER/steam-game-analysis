-- result: review_volume_distribution
-- purpose: Frozen review-volume bands across the complete market sample.
WITH banded AS (
  SELECT
    CASE
      WHEN total_reviews = 0 THEN '0'
      WHEN total_reviews < 10 THEN '1-9'
      WHEN total_reviews < 20 THEN '10-19'
      WHEN total_reviews < 50 THEN '20-49'
      WHEN total_reviews < 100 THEN '50-99'
      WHEN total_reviews < 500 THEN '100-499'
      WHEN total_reviews < 1000 THEN '500-999'
      ELSE '1000+'
    END AS review_band,
    CASE
      WHEN total_reviews = 0 THEN 1 WHEN total_reviews < 10 THEN 2
      WHEN total_reviews < 20 THEN 3 WHEN total_reviews < 50 THEN 4
      WHEN total_reviews < 100 THEN 5 WHEN total_reviews < 500 THEN 6
      WHEN total_reviews < 1000 THEN 7 ELSE 8
    END AS band_order,
    total_reviews
  FROM vw_game_analysis
)
SELECT
  review_band,
  COUNT(*) AS games,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct,
  MIN(total_reviews) AS min_total_reviews,
  MAX(total_reviews) AS max_total_reviews,
  ROUND(AVG(LN(1 + total_reviews)), 4) AS avg_log1p_total_reviews
FROM banded
GROUP BY review_band, band_order
ORDER BY band_order;

-- result: review_volume_by_payment
-- purpose: Free-versus-paid review attention profile with a window median.
WITH ranked AS (
  SELECT
    CASE WHEN is_free = 1 THEN 'Free' ELSE 'Paid' END AS payment_segment,
    appid,
    total_reviews,
    ROW_NUMBER() OVER (
      PARTITION BY is_free ORDER BY total_reviews, appid
    ) AS review_row,
    COUNT(*) OVER (PARTITION BY is_free) AS group_count
  FROM vw_game_analysis
)
SELECT
  payment_segment,
  COUNT(*) AS games,
  ROUND(100 * AVG(total_reviews = 0), 2) AS zero_review_share_pct,
  ROUND(100 * AVG(total_reviews >= 20), 2) AS reviews_ge_20_share_pct,
  ROUND(AVG(total_reviews), 2) AS avg_total_reviews,
  AVG(CASE WHEN review_row IN ((group_count + 1) DIV 2, (group_count + 2) DIV 2)
           THEN total_reviews END) AS median_total_reviews,
  ROUND(AVG(LN(1 + total_reviews)), 4) AS avg_log1p_total_reviews
FROM ranked
GROUP BY payment_segment
ORDER BY payment_segment;

-- result: perfect_positive_rate
-- purpose: Concentration of observed 100-percent positivity by review count.
WITH perfect AS (
  SELECT
    CASE
      WHEN total_reviews = 1 THEN '1 review'
      WHEN total_reviews = 2 THEN '2 reviews'
      WHEN total_reviews < 10 THEN '3-9'
      WHEN total_reviews < 20 THEN '10-19'
      WHEN total_reviews < 50 THEN '20-49'
      ELSE '50+'
    END AS review_group,
    CASE
      WHEN total_reviews = 1 THEN 1 WHEN total_reviews = 2 THEN 2
      WHEN total_reviews < 10 THEN 3 WHEN total_reviews < 20 THEN 4
      WHEN total_reviews < 50 THEN 5 ELSE 6
    END AS group_order
  FROM vw_game_analysis
  WHERE total_reviews > 0 AND positive_rate = 1
)
SELECT
  review_group,
  COUNT(*) AS perfect_positive_games,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_of_perfect_pct
FROM perfect
GROUP BY review_group, group_order
ORDER BY group_order;

-- result: review_score_summary
-- purpose: Steam categorical review-score descriptions versus volume and positivity.
WITH scored AS (
  SELECT
    review_score,
    review_score_desc,
    appid,
    total_reviews,
    positive_rate,
    ROW_NUMBER() OVER (
      PARTITION BY review_score, review_score_desc ORDER BY total_reviews, appid
    ) AS volume_row,
    COUNT(*) OVER (PARTITION BY review_score, review_score_desc) AS group_count
  FROM vw_game_analysis
  WHERE review_score_desc IS NOT NULL
), positive_ranked AS (
  SELECT
    review_score,
    review_score_desc,
    appid,
    positive_rate,
    ROW_NUMBER() OVER (
      PARTITION BY review_score, review_score_desc ORDER BY positive_rate, appid
    ) AS rate_row,
    COUNT(*) OVER (PARTITION BY review_score, review_score_desc) AS rate_count
  FROM vw_game_analysis
  WHERE review_score_desc IS NOT NULL AND total_reviews > 0
), positive_medians AS (
  SELECT
    review_score,
    review_score_desc,
    AVG(CASE WHEN rate_row IN ((rate_count + 1) DIV 2, (rate_count + 2) DIV 2)
             THEN positive_rate END) AS median_positive_rate
  FROM positive_ranked
  GROUP BY review_score, review_score_desc
)
SELECT
  s.review_score,
  s.review_score_desc,
  COUNT(*) AS games,
  AVG(CASE WHEN volume_row IN ((group_count + 1) DIV 2, (group_count + 2) DIV 2)
           THEN total_reviews END) AS median_total_reviews,
  ROUND(AVG(s.positive_rate), 4) AS avg_positive_rate,
  ROUND(MAX(p.median_positive_rate), 4) AS median_positive_rate
FROM scored s
LEFT JOIN positive_medians p
  ON p.review_score <=> s.review_score
 AND p.review_score_desc <=> s.review_score_desc
GROUP BY s.review_score, s.review_score_desc
ORDER BY s.review_score;
