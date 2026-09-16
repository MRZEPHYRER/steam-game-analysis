# Step 3B Final Audit — Full Review Snapshot Validation

This was a purely local, read-only validation of the completed review collection. HTTP requests made by this audit: **0**.

## Final sample coverage

- games rows / unique AppIDs: 3,000 / 3,000
- review snapshot rows / unique AppIDs: 3,000 / 3,000
- Missing review AppIDs: 0
- Sample-external review AppIDs: 0
- Duplicate review AppIDs: 0

## Review status

- success: 3,000
- unavailable: 0
- request_failed: 0
- schema_invalid: 0

## Count and zero-review integrity

- Invalid/non-integer count values: 0
- Negative-count failures: 0
- Count-identity failures: 0
- Zero-review games: 759
- Zero-review semantic failures: 0

## Review volume distribution

- zero: 759
- 1-9: 1,102
- 10-19: 295
- 20-49: 293
- 50-99: 145
- 100-499: 239
- 500-999: 54
- 1000+: 113
- Six-number summary: min=0.00, q1=0.00, median=4.00, mean=359.82, q3=26.00, max=136,842.00
- Mean is descriptive only; review volume is strongly right-skewed.

## Model-threshold counts

- total_reviews >= 10: 1,139 (37.97% of 3,000)
- total_reviews >= 20: 844 (28.13% of 3,000)
- total_reviews >= 50: 551 (18.37% of 3,000)

## Positive-rate integrity and distribution

- Available: 2,241
- NULL: 759
- NULL among total_reviews > 0: 0
- Calculation failures: 0
- Zero-review positive_rate failures: 0
- Range failures outside [0, 1]: 0
- Nonzero-review six-number summary: min=0.000000, q1=0.740741, median=0.915663, mean=0.817958, q3=1.000000, max=1.000000

## Review score audit

- Missing review_score: 0
- Missing/blank review_score_desc: 0

| review_score | Count |
|---|---:|
| 0 | 1,861 |
| 3 | 1 |
| 4 | 13 |
| 5 | 166 |
| 6 | 173 |
| 7 | 407 |
| 8 | 352 |
| 9 | 27 |

| review_score_desc | Count |
|---|---:|
| No user reviews | 759 |
| Positive | 407 |
| Very Positive | 352 |
| 1 user reviews | 317 |
| 2 user reviews | 216 |
| Mostly Positive | 173 |
| Mixed | 166 |
| 3 user reviews | 155 |
| 4 user reviews | 101 |
| 5 user reviews | 94 |
| 6 user reviews | 73 |
| 7 user reviews | 59 |
| 9 user reviews | 44 |
| 8 user reviews | 43 |
| Overwhelmingly Positive | 27 |
| Mostly Negative | 13 |
| Negative | 1 |

## Query contract audit

- Frozen full-run contract: `{'json': 1, 'filter': 'all', 'cursor': '*', 'num_per_page': 1, 'language': 'all', 'purchase_type': 'steam', 'review_type': 'all', 'filter_offtopic_activity': 1, 'day_range': 365}`
- Snapshot parameter drift total: 0
- review_language drift: 0
- review_purchase_type drift: 0
- review_type drift: 0
- filter_offtopic_activity drift: 0
- day_range drift: 0
- Raw contract-drift files: 0

## Timestamp audit

- Missing timestamps: 0
- Unparseable timestamps: 0
- Minimum collection timestamp: 2026-09-13T18:40:37.268199+00:00
- Maximum collection timestamp: 2026-09-13T20:27:34.043403+00:00
- Collection window duration: 6,416.775 seconds
- These timestamps describe collection time, not release-time review state.

## Raw coverage

- Raw files: 3,000
- Unique Raw AppIDs: 3,000
- Duplicate Raw AppIDs: 0
- Missing Raw AppIDs: 0
- Extra Raw AppIDs: 0
- Malformed Raw: 0
- request_error Raw: 0
- Invalid HTTP/payload Raw: 0

## Deterministic Raw-to-snapshot spot check

- Seed: 20250911
- Sample size: 30
- Exact matches: 30/30
- Mismatches: 0
- Fields checked: total_positive, total_negative, total_reviews, review_score, review_score_desc, and derived positive_rate.
- AppIDs: 1410450, 1639710, 1711790, 2717150, 2779730, 3047510, 3119050, 3202370, 3220170, 3356250, 3374340, 3415580, 3494660, 3500750, 3533400, 3540680, 3612610, 3820330, 3923690, 3929110, 3938040, 3998910, 4003520, 4022880, 4036810, 4041900, 4105120, 4162300, 4174530, 4212070

## Frozen input hashes

- Before/after preservation: PASS
- `data\processed\sample_games.csv`: `320A52FC8F4B8D5B71C2AA113B8B675D6B721C209A6EDB9C055658535395CB4F`
- `data\processed\games.csv`: `11D102600A178A9772BFD763CA2BF64A32534C338709E8E86CE013B4A17BBCE0`
- `data\processed\game_genres.csv`: `A718A498F0244D5FBD2A3862CDF49B0987C8DD5708F1A8C0826C14FDF6E17659`
- `data\interim\eligible_sampling_frame.csv`: `B989B8CB249FF52851996E416481FDA8AEAF3C853D2A580757BD63DAF704BF1B`

## Review snapshot fingerprint

- `data/processed/review_snapshots.csv`: `D219D3DBBD9CE1502122E78D1B8E7CC8958A5EE645311D3B30E382F75CF5D3BB`

## Final freeze decision

- Step 3B Final Audit: PASS
- Review dataset: FROZEN
- Ready for Step 3C MySQL: YES
