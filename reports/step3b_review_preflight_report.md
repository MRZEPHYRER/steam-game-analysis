# Step 3B Steam Review Snapshot Preflight

This is a 30-AppID endpoint and data-quality preflight, not substantive EDA.

## Scope and query contract

- Source population: 3,000
- Preflight sample: 30
- Endpoint: https://store.steampowered.com/appreviews/<appid>
- Parameters: {'json': 1, 'language': 'all', 'purchase_type': 'steam', 'review_type': 'all', 'filter': 'summary', 'filter_offtopic_activity': 1, 'num_per_page': 0}
- Summary-only attempt: num_per_page=0 was sent and query_summary was retained.
- Observed endpoint behavior: Steam still attached 150 individual review objects in total (maximum 10 per response).
- The collector ignores individual review objects and performs no review pagination.
- Collection mode: conservative synchronous requests through SteamClient.

## Collection status

- HTTP 2xx Raw responses: 30
- Successful review summaries: 30
- Request failures: 0
- Schema invalid: 0
- Steam unavailable responses: 0
- Existing successful/schema-valid Raw reused: 30
- Newly requested: 0
- Failed Raw retried this execution: 0
- HTTP retry attempts represented in Raw: 0
- HTTP 429 responses represented in Raw: 0
- Request latency: min=0.454s, median=2.094s, max=3.078s
- Schema drift: NONE

## Review-count validation

- total_reviews minimum: 0
- total_reviews median: 2.5
- total_reviews maximum: 24,602
- Zero-review games: 9
- 1-9 review games: 9
- 10-19 review games: 1
- 20-49 review games: 2
- 50+ review games: 9
- Main-threshold preview (total_reviews >= 20): 11
- positive_rate available: 21
- positive_rate NULL: 9
- positive + negative = total identity failures: 0

Zero reviews remain a successful snapshot with positive_rate=NULL; they are not converted to 0% positive.

## Review score values observed

| review_score | Count |
|---|---:|
| 0 | 18 |
| 8 | 6 |
| 6 | 2 |
| 7 | 2 |
| 5 | 2 |

## Review score descriptions observed

| review_score_desc | Count |
|---|---:|
| No user reviews | 9 |
| Very Positive | 6 |
| 2 user reviews | 4 |
| Mostly Positive | 2 |
| Mixed | 2 |
| Positive | 2 |
| 1 user reviews | 2 |
| 8 user reviews | 1 |
| 9 user reviews | 1 |
| 3 user reviews | 1 |

## Monthly preflight distribution

| Release month | Games |
|---|---:|
| 2025-07 | 5 |
| 2025-08 | 5 |
| 2025-09 | 4 |
| 2025-10 | 5 |
| 2025-11 | 6 |
| 2025-12 | 5 |
| **Total** | **30** |

## Raw preservation and resume

- Raw review wrappers present: 30
- Raw wrappers with query_summary: 30
- Incidental individual review objects preserved: 150
- Successful Raw is reused.
- request_error Raw is retried on the next execution.
- Schema-invalid Raw is preserved and blocks readiness.
- Each completed request is atomically saved before the next AppID.

## PASS / FAIL summary

- Review parser: PASS
- Zero-review semantics: PASS
- Review-count identity: PASS
- Resume/retry implementation: PASS
- Frozen sample preservation: PASS
- Schema drift: NONE
- Step 3B Preflight: PASS
- Ready for full 3000 review collection: YES
