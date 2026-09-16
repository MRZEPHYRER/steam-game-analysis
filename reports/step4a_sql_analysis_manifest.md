# Step 4A SQL Analysis Manifest

All statements were executed inside a MySQL read-only transaction. CSV files
were written only after every query and the post-query database audit passed.

| Query file | Purpose | Output CSV | Rows | Status |
|---|---|---|---:|---|
| `sql/analysis/01_market_overview.sql` | Full 3,000-game market structure and review availability. | `data/analysis/sql/market_overview.csv` | 1 | PASS |
| `sql/analysis/01_market_overview.sql` | Platform support counts and shares in the market sample. | `data/analysis/sql/platform_support.csv` | 3 | PASS |
| `sql/analysis/02_price_analysis.sql` | Collection-time storefront price summary for paid games with observed prices. | `data/analysis/sql/price_summary.csv` | 1 | PASS |
| `sql/analysis/02_price_analysis.sql` | Price bands with robust review-volume and observed-positivity summaries. | `data/analysis/sql/price_bands.csv` | 7 | PASS |
| `sql/analysis/02_price_analysis.sql` | Paid observed-price quartiles using NTILE and review-profile summaries. | `data/analysis/sql/price_quantiles.csv` | 4 | PASS |
| `sql/analysis/03_review_volume.sql` | Frozen review-volume bands across the complete market sample. | `data/analysis/sql/review_volume_distribution.csv` | 8 | PASS |
| `sql/analysis/03_review_volume.sql` | Free-versus-paid review attention profile with a window median. | `data/analysis/sql/review_volume_by_payment.csv` | 2 | PASS |
| `sql/analysis/03_review_volume.sql` | Concentration of observed 100-percent positivity by review count. | `data/analysis/sql/perfect_positive_rate.csv` | 6 | PASS |
| `sql/analysis/03_review_volume.sql` | Steam categorical review-score descriptions versus volume and positivity. | `data/analysis/sql/review_score_summary.csv` | 17 | PASS |
| `sql/analysis/04_positive_rate.sql` | Observed positivity by review-volume band, excluding zero-review games. | `data/analysis/sql/positive_rate_by_review_volume.csv` | 7 | PASS |
| `sql/analysis/04_positive_rate.sql` | Observed positivity among reviewed free and paid games. | `data/analysis/sql/positive_rate_by_payment.csv` | 2 | PASS |
| `sql/analysis/05_genre_analysis.sql` | Genre membership, free share, review coverage, and attention profile. | `data/analysis/sql/genre_summary.csv` | 13 | PASS |
| `sql/analysis/05_genre_analysis.sql` | Genre positivity for reviewed games and the >=20-review candidate subset. | `data/analysis/sql/genre_positive_rate.csv` | 12 | PASS |
| `sql/analysis/05_genre_analysis.sql` | Dense genre rankings by attention and candidate-sample positivity. | `data/analysis/sql/genre_rankings.csv` | 10 | PASS |
| `sql/analysis/06_release_month.sql` | Observed market, price, review, and positivity differences by sampled release month. | `data/analysis/sql/release_month_summary.csv` | 6 | PASS |
| `sql/analysis/06_release_month.sql` | Mutually exclusive platform-support segments based on observed combinations. | `data/analysis/sql/platform_segments.csv` | 5 | PASS |
| `sql/analysis/07_rankings.sql` | Top 20 observed high-review-volume games (attention proxy, not sales). | `data/analysis/sql/top_review_volume_games.csv` | 20 | PASS |
| `sql/analysis/07_rankings.sql` | Top 20 observed positivity among games with at least 20 reviews. | `data/analysis/sql/top_positive_rate_games.csv` | 20 | PASS |
| `sql/analysis/07_rankings.sql` | Descriptive profile of the top review-volume ventile (top 5 percent). | `data/analysis/sql/high_attention_profile.csv` | 1 | PASS |
| `sql/analysis/07_rankings.sql` | Genre composition of the top review-volume ventile. | `data/analysis/sql/high_attention_genres.csv` | 12 | PASS |
| `sql/analysis/07_rankings.sql` | Release-month composition of the top review-volume ventile. | `data/analysis/sql/high_attention_release_month.csv` | 6 | PASS |
| `sql/analysis/08_cross_segment_analysis.sql` | Cross-tabulation of collection-time price band and review-volume band. | `data/analysis/sql/price_by_review_band.csv` | 47 | PASS |
| `sql/analysis/08_cross_segment_analysis.sql` | Cross-tabulation of genre membership and free/paid status. | `data/analysis/sql/genre_by_payment.csv` | 13 | PASS |
| `sql/analysis/08_cross_segment_analysis.sql` | Release month crossed with membership in the >=20-review candidate sample. | `data/analysis/sql/release_month_candidate_share.csv` | 6 | PASS |
| `sql/analysis/09_model_sample_profile.sql` | Full-market versus >=20-review candidate sample composition. | `data/analysis/sql/model_sample_comparison.csv` | 2 | PASS |
| `sql/analysis/09_model_sample_profile.sql` | Genre composition differences between the market and candidate samples. | `data/analysis/sql/model_sample_genre_comparison.csv` | 13 | PASS |
| `sql/analysis/09_model_sample_profile.sql` | Release-month composition differences between full and candidate samples. | `data/analysis/sql/model_sample_release_month_comparison.csv` | 6 | PASS |

Queries executed: **27**

Database mutation guard: **PASS**
