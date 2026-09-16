# Step 3A Metadata Materialization Report

This report covers local joins and normalization only. No network source was accessed.

## Sample and join integrity

- Input final sample rows: 3,000
- Input unique AppIDs: 3,000
- Output games rows: 3,000
- Output unique AppIDs: 3,000
- Join coverage: 3,000/3,000 (100.00%)
- Final sample AppID set preserved: PASS

## Monthly counts

| Release month | Games |
|---|---:|
| 2025-07 | 497 |
| 2025-08 | 470 |
| 2025-09 | 427 |
| 2025-10 | 544 |
| 2025-11 | 580 |
| 2025-12 | 482 |
| **Total** | **3,000** |

## Free, paid, and platform counts

- Free games: 402
- Paid games: 2,598
- Windows-supported: 2,999
- macOS-supported: 439
- Linux-supported: 363

## Paid-game price currency distribution

- USD: 2,597
- <missing>: 1
- Paid games without a Store price overview: 1

Prices are storefront snapshots at metadata_collected_at; they are not historical launch prices.
Source *_cents columns remain nullable integers. Derived *_usd columns equal cents divided by 100 and remain null when cents are null.

## Price missingness

| Field | Missing | Expected | Unexpected |
|---|---:|---:|---:|
| list_price_cents | 403 | 403 | 0 |
| current_price_cents | 403 | 403 | 0 |
| discount_percent | 403 | 403 | 0 |
| price_currency | 403 | 403 | 0 |

## Developer and publisher missingness

- Missing developer: 0
- Missing publisher: 3 (allowed source missingness)

## Genre integrity

- Games with at least one genre: 3,000
- Games without genres: 0
- Total genre relation rows: 8,796
- Unique genre IDs: 13
- Unique genre names: 13
- Mean genres per game (including zero-genre games): 2.932

## Duplicate and release-date checks

- Duplicate games AppIDs: 0
- Duplicate (appid, genre_id) keys where ID is available: 0
- Release-date conflicts: 0
- All release dates within the frozen study window: PASS
- Release month derived from final Store release date: PASS
- Frozen monthly allocation preserved: PASS

## Missing-value audit

| Field | Missing | Expected | Unexpected | Interpretation |
|---|---:|---:|---:|---|
| name | 0 | 0 | 0 | Required final metadata field |
| release_date | 0 | 0 | 0 | Required final metadata field |
| developer | 0 | 0 | 0 | Required final metadata field |
| publisher | 3 | 3 | 0 | Source publisher can be absent; retained as null |
| is_free | 0 | 0 | 0 | Required final metadata field |
| platform_windows | 0 | 0 | 0 | Required final metadata field |
| platform_mac | 0 | 0 | 0 | Required final metadata field |
| platform_linux | 0 | 0 | 0 | Required final metadata field |
| list_price_cents | 403 | 403 | 0 | Expected for free games or paid games without a Store price overview |
| current_price_cents | 403 | 403 | 0 | Expected for free games or paid games without a Store price overview |
| discount_percent | 403 | 403 | 0 | Expected for free games or paid games without a Store price overview |
| price_currency | 403 | 403 | 0 | Expected for free games or paid games without a Store price overview |
| metadata_collected_at | 0 | 0 | 0 | Required final metadata field |
| is_early_access | 3,000 | 3,000 | 0 | Unknown because appdetails has no reliable explicit field |

Total unexpected missing values across audited fields: 0

## Files generated

- data/processed/games.csv
- data/processed/game_genres.csv
- reports/step3a_metadata_report.md

## PASS / FAIL summary

- Final sample preservation: PASS
- Metadata join integrity: PASS
- Price schema: PASS
- Genre normalization: PASS
- Missing-value audit: PASS
- Step 3A: PASS
