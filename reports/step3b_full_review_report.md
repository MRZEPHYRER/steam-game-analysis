# Step 3B.2 Full Steam Review Snapshot Collection

This report contains collection QA and descriptive volume summaries only. It does not perform substantive EDA or modeling.

## Coverage

- Source games: 3,000
- Snapshot rows: 3,000
- Unique snapshot AppIDs: 3,000
- Coverage: 100.00%
- Full Raw wrappers present: 3,000

## Frozen query contract

- Parameters: `{'json': 1, 'filter': 'all', 'cursor': '*', 'num_per_page': 1, 'language': 'all', 'purchase_type': 'steam', 'review_type': 'all', 'filter_offtopic_activity': 1, 'day_range': 365}`
- Only query_summary and technical/source metadata are materialized.
- No review pagination or individual-review corpus collection is performed.

## Technical status

- Success: 3,000
- Steam unavailable: 0
- request_failed: 0
- schema_invalid: 0

## Review-count distribution

- zero: 759
- 1-9: 1,102
- 10-19: 295
- 20-49: 293
- 50-99: 145
- 100-499: 239
- 500-999: 54
- 1000+: 113
- Summary: min=0, median=4.0, mean=359.82, max=136,842
- Mean is descriptive only; review volume may be strongly right-skewed.

## Model-threshold counts (not a model-table filter)

- total_reviews >= 10: 1,139
- total_reviews >= 20: 844
- total_reviews >= 50: 551

## Positive rate

- Available count: 2,241
- NULL count: 759
- Distribution for total_reviews > 0 only: min=0.000000, median=0.915663, mean=0.817958, max=1.000000

## Review score frequency

| review_score | Count |
|---|---:|
| 0 | 1,861 |
| 7 | 407 |
| 8 | 352 |
| 6 | 173 |
| 5 | 166 |
| 9 | 27 |
| 4 | 13 |
| 3 | 1 |

## Review score description frequency

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

## Integrity

- Count-identity failures: 0
- Positive-rate semantic failures: 0
- Duplicate AppIDs: 0
- Missing AppIDs: 0
- Sample-external AppIDs: 0

## Collection telemetry

- New: 2,973
- Reused: 27
- Retried failed Raw: 0
- Unresolved failures: 0
- HTTP retries: 0
- HTTP 429 responses: 0
- Transient HTTP 5xx responses: 0
- Timeout/connection failures: 0
- Elapsed seconds: 6344.547

## Frozen inputs

- Before/after hashes identical: PASS
- `C:\Users\TOMZOU\anaconda_projects\steam-game-analysis\data\processed\sample_games.csv`: `320A52FC8F4B8D5B71C2AA113B8B675D6B721C209A6EDB9C055658535395CB4F`
- `C:\Users\TOMZOU\anaconda_projects\steam-game-analysis\data\processed\games.csv`: `11D102600A178A9772BFD763CA2BF64A32534C338709E8E86CE013B4A17BBCE0`
- `C:\Users\TOMZOU\anaconda_projects\steam-game-analysis\data\processed\game_genres.csv`: `A718A498F0244D5FBD2A3862CDF49B0987C8DD5708F1A8C0826C14FDF6E17659`
- `C:\Users\TOMZOU\anaconda_projects\steam-game-analysis\data\interim\eligible_sampling_frame.csv`: `B989B8CB249FF52851996E416481FDA8AEAF3C853D2A580757BD63DAF704BF1B`

## Finalization

- Technical finalization gate: PASS
- Formal review_snapshots.csv written: YES
