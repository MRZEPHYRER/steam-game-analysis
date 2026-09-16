-- result: release_month_summary
-- purpose: Observed market, price, review, and positivity differences by sampled release month.
WITH positive_ranked AS (
  SELECT
    release_month,
    appid,
    positive_rate,
    ROW_NUMBER() OVER (
      PARTITION BY release_month ORDER BY positive_rate, appid
    ) AS rate_row,
    COUNT(*) OVER (PARTITION BY release_month) AS rate_count
  FROM vw_game_analysis
  WHERE total_reviews > 0
), positive_medians AS (
  SELECT
    release_month,
    AVG(CASE WHEN rate_row IN ((rate_count + 1) DIV 2, (rate_count + 2) DIV 2)
             THEN positive_rate END) AS median_positive_rate
  FROM positive_ranked
  GROUP BY release_month
)
SELECT
  v.release_month,
  COUNT(*) AS games,
  SUM(is_free = 1) AS free_games,
  ROUND(100 * AVG(is_free = 1), 2) AS free_share_pct,
  SUM(total_reviews = 0) AS zero_review_games,
  ROUND(100 * AVG(total_reviews = 0), 2) AS zero_review_share_pct,
  SUM(total_reviews >= 20) AS reviews_ge_20_games,
  ROUND(100 * AVG(total_reviews >= 20), 2) AS reviews_ge_20_share_pct,
  SUM(is_free = 0 AND current_price_usd IS NOT NULL) AS priced_paid_games,
  ROUND(AVG(CASE WHEN is_free = 0 THEN current_price_usd END), 2) AS avg_current_price_usd,
  ROUND(AVG(total_reviews), 2) AS avg_total_reviews,
  ROUND(AVG(LN(1 + total_reviews)), 4) AS avg_log1p_total_reviews,
  SUM(total_reviews > 0) AS positive_rate_n,
  ROUND(AVG(v.positive_rate), 4) AS avg_positive_rate,
  ROUND(MAX(p.median_positive_rate), 4) AS median_positive_rate
FROM vw_game_analysis v
LEFT JOIN positive_medians p ON p.release_month = v.release_month
GROUP BY v.release_month
ORDER BY v.release_month;

-- result: platform_segments
-- purpose: Mutually exclusive platform-support segments based on observed combinations.
WITH segmented AS (
  SELECT
    CASE
      WHEN platform_windows = 1 AND platform_mac = 0 AND platform_linux = 0
        THEN 'Windows only'
      WHEN platform_windows = 1 AND platform_mac = 1 AND platform_linux = 0
        THEN 'Windows + macOS'
      WHEN platform_windows = 1 AND platform_mac = 0 AND platform_linux = 1
        THEN 'Windows + Linux'
      WHEN platform_windows = 1 AND platform_mac = 1 AND platform_linux = 1
        THEN 'Windows + macOS + Linux'
      ELSE 'Other rare patterns'
    END AS platform_segment,
    CASE
      WHEN platform_windows = 1 AND platform_mac = 0 AND platform_linux = 0 THEN 1
      WHEN platform_windows = 1 AND platform_mac = 1 AND platform_linux = 0 THEN 2
      WHEN platform_windows = 1 AND platform_mac = 0 AND platform_linux = 1 THEN 3
      WHEN platform_windows = 1 AND platform_mac = 1 AND platform_linux = 1 THEN 4
      ELSE 5
    END AS segment_order,
    total_reviews,
    positive_rate
  FROM vw_game_analysis
)
SELECT
  platform_segment,
  COUNT(*) AS games,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct,
  ROUND(100 * AVG(total_reviews = 0), 2) AS zero_review_share_pct,
  ROUND(100 * AVG(total_reviews >= 20), 2) AS reviews_ge_20_share_pct,
  ROUND(AVG(total_reviews), 2) AS avg_total_reviews,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate
FROM segmented
GROUP BY platform_segment, segment_order
ORDER BY segment_order;
