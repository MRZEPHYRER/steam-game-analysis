-- result: price_summary
-- purpose: Collection-time storefront price summary for paid games with observed prices.
WITH priced_paid AS (
  SELECT
    appid,
    current_price_usd,
    list_price_usd,
    discount_percent,
    ROW_NUMBER() OVER (ORDER BY current_price_usd, appid) AS price_row,
    COUNT(*) OVER () AS price_count
  FROM vw_game_analysis
  WHERE is_free = 0 AND current_price_usd IS NOT NULL
)
SELECT
  COUNT(*) AS games,
  MIN(current_price_usd) AS min_current_price_usd,
  ROUND(AVG(current_price_usd), 2) AS avg_current_price_usd,
  ROUND(AVG(CASE WHEN price_row IN ((price_count + 1) DIV 2, (price_count + 2) DIV 2)
                 THEN current_price_usd END), 2) AS median_current_price_usd,
  MAX(current_price_usd) AS max_current_price_usd,
  ROUND(AVG(list_price_usd), 2) AS avg_list_price_usd,
  ROUND(AVG(discount_percent), 2) AS avg_discount_percent,
  SUM(discount_percent > 0) AS discounted_games
FROM priced_paid;

-- result: price_bands
-- purpose: Price bands with robust review-volume and observed-positivity summaries.
WITH segmented AS (
  SELECT
    appid,
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
    END AS band_order,
    total_reviews,
    positive_rate
  FROM vw_game_analysis
), ranked_reviews AS (
  SELECT
         price_band,
         band_order,
         appid,
         total_reviews,
         positive_rate,
         ROW_NUMBER() OVER (PARTITION BY price_band ORDER BY total_reviews, appid) AS review_row,
         COUNT(*) OVER (PARTITION BY price_band) AS review_count
  FROM segmented
), ranked_positive AS (
  SELECT price_band, appid, positive_rate,
         ROW_NUMBER() OVER (PARTITION BY price_band ORDER BY positive_rate, appid) AS positive_row,
         COUNT(*) OVER (PARTITION BY price_band) AS positive_count
  FROM segmented
  WHERE total_reviews > 0
), positive_medians AS (
  SELECT price_band,
         AVG(CASE WHEN positive_row IN ((positive_count + 1) DIV 2, (positive_count + 2) DIV 2)
                  THEN positive_rate END) AS median_positive_rate
  FROM ranked_positive
  GROUP BY price_band
)
SELECT
  r.price_band,
  COUNT(*) AS games,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS market_share_pct,
  ROUND(100 * AVG(r.total_reviews = 0), 2) AS zero_review_share_pct,
  ROUND(AVG(r.total_reviews), 2) AS avg_total_reviews,
  AVG(CASE WHEN r.review_row IN ((r.review_count + 1) DIV 2, (r.review_count + 2) DIV 2)
           THEN r.total_reviews END) AS median_total_reviews,
  SUM(r.total_reviews > 0) AS positive_rate_n,
  ROUND(AVG(r.positive_rate), 4) AS avg_positive_rate,
  ROUND(MAX(p.median_positive_rate), 4) AS median_positive_rate
FROM ranked_reviews r
LEFT JOIN positive_medians p ON p.price_band = r.price_band
GROUP BY r.price_band, r.band_order
ORDER BY r.band_order;

-- result: price_quantiles
-- purpose: Paid observed-price quartiles using NTILE and review-profile summaries.
WITH quantiled AS (
  SELECT
    appid,
    current_price_usd,
    total_reviews,
    positive_rate,
    NTILE(4) OVER (ORDER BY current_price_usd, appid) AS price_quartile
  FROM vw_game_analysis
  WHERE is_free = 0 AND current_price_usd IS NOT NULL
), ranked AS (
  SELECT
         appid,
         current_price_usd,
         total_reviews,
         positive_rate,
         price_quartile,
         ROW_NUMBER() OVER (PARTITION BY price_quartile ORDER BY current_price_usd, appid) AS price_row,
         ROW_NUMBER() OVER (PARTITION BY price_quartile ORDER BY total_reviews, appid) AS review_row,
         COUNT(*) OVER (PARTITION BY price_quartile) AS group_count
  FROM quantiled
)
SELECT
  price_quartile,
  COUNT(*) AS games,
  MIN(current_price_usd) AS min_price_usd,
  ROUND(AVG(current_price_usd), 2) AS avg_price_usd,
  ROUND(AVG(CASE WHEN price_row IN ((group_count + 1) DIV 2, (group_count + 2) DIV 2)
                 THEN current_price_usd END), 2) AS median_price_usd,
  MAX(current_price_usd) AS max_price_usd,
  ROUND(100 * AVG(total_reviews = 0), 2) AS zero_review_share_pct,
  ROUND(AVG(total_reviews), 2) AS avg_total_reviews,
  AVG(CASE WHEN review_row IN ((group_count + 1) DIV 2, (group_count + 2) DIV 2)
           THEN total_reviews END) AS median_total_reviews,
  ROUND(AVG(positive_rate), 4) AS avg_positive_rate
FROM ranked
GROUP BY price_quartile
ORDER BY price_quartile;
