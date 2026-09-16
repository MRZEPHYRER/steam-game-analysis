-- result: market_overview
-- purpose: Full 3,000-game market structure and review availability.
SELECT
  COUNT(*) AS total_games,
  SUM(is_free = 1) AS free_games,
  ROUND(100 * AVG(is_free = 1), 2) AS free_share_pct,
  SUM(is_free = 0) AS paid_games,
  ROUND(100 * AVG(is_free = 0), 2) AS paid_share_pct,
  SUM(total_reviews > 0) AS games_with_reviews,
  ROUND(100 * AVG(total_reviews > 0), 2) AS reviewed_share_pct,
  SUM(total_reviews = 0) AS zero_review_games,
  ROUND(100 * AVG(total_reviews = 0), 2) AS zero_review_share_pct,
  SUM(platform_windows = 1) AS windows_games,
  SUM(platform_mac = 1) AS mac_games,
  SUM(platform_linux = 1) AS linux_games
FROM vw_game_analysis;

-- result: platform_support
-- purpose: Platform support counts and shares in the market sample.
SELECT 'Windows' AS platform, SUM(platform_windows = 1) AS games,
       ROUND(100 * AVG(platform_windows = 1), 2) AS share_pct
FROM vw_game_analysis
UNION ALL
SELECT 'macOS', SUM(platform_mac = 1), ROUND(100 * AVG(platform_mac = 1), 2)
FROM vw_game_analysis
UNION ALL
SELECT 'Linux', SUM(platform_linux = 1), ROUND(100 * AVG(platform_linux = 1), 2)
FROM vw_game_analysis;
