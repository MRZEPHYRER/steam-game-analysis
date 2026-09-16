CREATE INDEX idx_games_release_month ON games (release_month);
CREATE INDEX idx_games_is_free ON games (is_free);
CREATE INDEX idx_review_total_reviews ON review_snapshots (total_reviews);
CREATE INDEX idx_review_positive_rate ON review_snapshots (positive_rate);
CREATE INDEX idx_review_score ON review_snapshots (review_score);
CREATE INDEX idx_price_current_cents ON price_snapshots (current_price_cents);
CREATE INDEX idx_game_genres_genre ON game_genres (genre_id);

CREATE OR REPLACE VIEW vw_game_analysis AS
SELECT
  g.appid,
  g.name,
  g.release_date,
  g.release_month,
  g.is_free,
  g.platform_windows,
  g.platform_mac,
  g.platform_linux,
  p.list_price_cents,
  p.current_price_cents,
  CAST(p.list_price_cents / 100.0 AS DECIMAL(12,2)) AS list_price_usd,
  CAST(p.current_price_cents / 100.0 AS DECIMAL(12,2)) AS current_price_usd,
  p.discount_percent,
  p.price_currency,
  r.total_reviews,
  r.positive_reviews,
  r.negative_reviews,
  r.positive_rate,
  r.review_score,
  r.review_score_desc,
  g.metadata_collected_at,
  r.review_collected_at
FROM games AS g
LEFT JOIN price_snapshots AS p
  ON p.price_snapshot_id = (
    SELECT p2.price_snapshot_id
    FROM price_snapshots AS p2
    WHERE p2.appid = g.appid
    ORDER BY p2.price_collected_at DESC, p2.price_snapshot_id DESC
    LIMIT 1
  )
LEFT JOIN review_snapshots AS r ON r.appid = g.appid;

CREATE OR REPLACE VIEW vw_game_genres AS
SELECT
  g.appid,
  g.name,
  gg.genre_id,
  ge.genre_name
FROM games AS g
JOIN game_genres AS gg ON gg.appid = g.appid
JOIN genres AS ge ON ge.genre_id = gg.genre_id;

CREATE OR REPLACE VIEW vw_model_sample_20 AS
SELECT *
FROM vw_game_analysis
WHERE total_reviews >= 20;
