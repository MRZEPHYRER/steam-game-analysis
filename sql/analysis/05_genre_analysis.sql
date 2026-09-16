-- result: genre_summary
-- purpose: Genre membership, free share, review coverage, and attention profile.
SELECT
  ge.genre_name,
  COUNT(*) AS games,
  ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM games), 2) AS market_membership_pct,
  ROUND(100 * AVG(g.is_free = 1), 2) AS free_share_pct,
  ROUND(100 * AVG(r.total_reviews = 0), 2) AS zero_review_share_pct,
  ROUND(100 * AVG(r.total_reviews >= 20), 2) AS reviews_ge_20_share_pct,
  ROUND(AVG(r.total_reviews), 2) AS avg_total_reviews,
  ROUND(AVG(LN(1 + r.total_reviews)), 4) AS avg_log1p_total_reviews
FROM genres ge
JOIN game_genres gg ON gg.genre_id = ge.genre_id
JOIN games g ON g.appid = gg.appid
JOIN review_snapshots r ON r.appid = g.appid
GROUP BY ge.genre_id, ge.genre_name
ORDER BY games DESC, ge.genre_name;

-- result: genre_positive_rate
-- purpose: Genre positivity for reviewed games and the >=20-review candidate subset.
WITH observed AS (
  SELECT
    ge.genre_id,
    ge.genre_name,
    g.appid,
    r.total_reviews,
    r.positive_rate,
    ROW_NUMBER() OVER (
      PARTITION BY ge.genre_id ORDER BY r.positive_rate, g.appid
    ) AS rate_row,
    COUNT(*) OVER (PARTITION BY ge.genre_id) AS observed_count
  FROM genres ge
  JOIN game_genres gg ON gg.genre_id = ge.genre_id
  JOIN games g ON g.appid = gg.appid
  JOIN review_snapshots r ON r.appid = g.appid
  WHERE r.total_reviews > 0
)
SELECT
  genre_name,
  COUNT(*) AS positive_rate_n,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate,
  ROUND(AVG(CASE WHEN rate_row IN ((observed_count + 1) DIV 2, (observed_count + 2) DIV 2)
                 THEN positive_rate END), 4) AS median_positive_rate,
  SUM(total_reviews >= 20) AS reviews_ge_20_games,
  ROUND(AVG(CASE WHEN total_reviews >= 20 THEN positive_rate END), 4)
    AS reviews_ge_20_avg_positive_rate
FROM observed
GROUP BY genre_id, genre_name
ORDER BY reviews_ge_20_avg_positive_rate DESC, genre_name;

-- result: genre_rankings
-- purpose: Dense genre rankings by attention and candidate-sample positivity.
WITH genre_metrics AS (
  SELECT
    ge.genre_name,
    COUNT(*) AS games,
    AVG(r.total_reviews) AS avg_total_reviews,
    SUM(r.total_reviews >= 20) AS candidate_games,
    AVG(CASE WHEN r.total_reviews >= 20 THEN r.positive_rate END)
      AS candidate_avg_positive_rate
  FROM genres ge
  JOIN game_genres gg ON gg.genre_id = ge.genre_id
  JOIN review_snapshots r ON r.appid = gg.appid
  GROUP BY ge.genre_id, ge.genre_name
)
SELECT
  genre_name,
  games,
  ROUND(avg_total_reviews, 2) AS avg_total_reviews,
  DENSE_RANK() OVER (ORDER BY avg_total_reviews DESC) AS attention_rank,
  candidate_games,
  ROUND(candidate_avg_positive_rate, 4) AS candidate_avg_positive_rate,
  DENSE_RANK() OVER (ORDER BY candidate_avg_positive_rate DESC) AS candidate_positivity_rank
FROM genre_metrics
WHERE games >= 30 AND candidate_games >= 20
ORDER BY attention_rank, genre_name;
