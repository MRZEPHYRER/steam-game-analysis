# Step 3C MySQL Analytical Database Report

Generated from an actual successful database audit. Build action: `built`.

## Row counts

| Object | Rows |
|---|---:|
| `games` | 3,000 |
| `genres` | 13 |
| `game_genres` | 8,796 |
| `review_snapshots` | 3,000 |
| `price_snapshots` | 3,000 |
| `collection_runs` | 2 |
| `vw_game_analysis` | 3,000 |
| `vw_game_genres` | 8,796 |
| `vw_model_sample_20` | 844 |

## Acceptance metrics

- Reviews >= 10: 1,139
- Reviews >= 20: 844
- Reviews >= 50: 551
- Free / paid: 402 / 2,598
- Windows / macOS / Linux: 2,999 / 439 / 363
- Missing developer / publisher: 0 / 3
- Priced / missing-price snapshots: 2,597 / 403
- USD price snapshots: 2,597
- Negative-price / current-above-list failures: 0 / 0

## Integrity

All foreign-key orphan, review identity, zero-review, positive-rate, duplicate-key,
and game-without-genre checks returned zero failures.

## Result

`Step 3C database audit: PASS`
