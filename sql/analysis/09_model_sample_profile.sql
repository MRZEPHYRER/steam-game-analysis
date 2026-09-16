-- result: model_sample_comparison
-- purpose: Full-market versus >=20-review candidate sample composition.
WITH samples AS (
  SELECT
    'Market sample' AS sample_name,
    1 AS sample_order,
    v.appid,
    v.is_free,
    v.current_price_usd,
    v.platform_windows,
    v.platform_mac,
    v.platform_linux,
    v.total_reviews,
    v.positive_rate
  FROM vw_game_analysis v
  UNION ALL
  SELECT
    'Model candidate (reviews >=20)',
    2,
    v.appid,
    v.is_free,
    v.current_price_usd,
    v.platform_windows,
    v.platform_mac,
    v.platform_linux,
    v.total_reviews,
    v.positive_rate
  FROM vw_game_analysis v
  WHERE total_reviews >= 20
), price_ranked AS (
  SELECT
    sample_name,
    appid,
    current_price_usd,
    ROW_NUMBER() OVER (
      PARTITION BY sample_name ORDER BY current_price_usd, appid
    ) AS price_row,
    COUNT(*) OVER (PARTITION BY sample_name) AS price_count
  FROM samples
  WHERE is_free = 0 AND current_price_usd IS NOT NULL
), price_medians AS (
  SELECT sample_name,
         AVG(CASE WHEN price_row IN ((price_count + 1) DIV 2, (price_count + 2) DIV 2)
                  THEN current_price_usd END) AS median_current_price_usd
  FROM price_ranked
  GROUP BY sample_name
)
SELECT
  s.sample_name,
  COUNT(*) AS games,
  ROUND(100 * AVG(s.is_free = 1), 2) AS free_share_pct,
  ROUND(MAX(p.median_current_price_usd), 2) AS median_current_price_usd,
  ROUND(100 * AVG(s.platform_windows = 1), 2) AS windows_share_pct,
  ROUND(100 * AVG(s.platform_mac = 1), 2) AS mac_share_pct,
  ROUND(100 * AVG(s.platform_linux = 1), 2) AS linux_share_pct,
  ROUND(AVG(s.total_reviews), 2) AS avg_total_reviews,
  ROUND(AVG(LN(1 + s.total_reviews)), 4) AS avg_log1p_total_reviews,
  ROUND(AVG(s.positive_rate), 4) AS avg_positive_rate
FROM samples s
LEFT JOIN price_medians p ON p.sample_name = s.sample_name
GROUP BY s.sample_name, s.sample_order
ORDER BY s.sample_order;

-- result: model_sample_genre_comparison
-- purpose: Genre composition differences between the market and candidate samples.
WITH sample_sizes AS (
  SELECT 3000 AS market_n, COUNT(*) AS model_n FROM vw_model_sample_20
)
SELECT
  ge.genre_name,
  COUNT(*) AS market_genre_games,
  ROUND(100 * COUNT(*) / MAX(ss.market_n), 2) AS market_membership_pct,
  SUM(r.total_reviews >= 20) AS model_genre_games,
  ROUND(100 * SUM(r.total_reviews >= 20) / MAX(ss.model_n), 2) AS model_membership_pct,
  ROUND(100 * SUM(r.total_reviews >= 20) / MAX(ss.model_n)
        - 100 * COUNT(*) / MAX(ss.market_n), 2) AS percentage_point_difference
FROM genres ge
JOIN game_genres gg ON gg.genre_id = ge.genre_id
JOIN review_snapshots r ON r.appid = gg.appid
CROSS JOIN sample_sizes ss
GROUP BY ge.genre_id, ge.genre_name
ORDER BY percentage_point_difference DESC, ge.genre_name;

-- result: model_sample_release_month_comparison
-- purpose: Release-month composition differences between full and candidate samples.
SELECT
  release_month,
  COUNT(*) AS market_games,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS market_share_pct,
  SUM(total_reviews >= 20) AS model_games,
  ROUND(100 * SUM(total_reviews >= 20) / SUM(SUM(total_reviews >= 20)) OVER (), 2)
    AS model_share_pct
FROM vw_game_analysis
GROUP BY release_month
ORDER BY release_month;
