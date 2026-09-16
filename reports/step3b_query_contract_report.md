# Step 3B.1 Steam Review Query Contract Validation

This was an isolated 10-AppID A/B request-contract check. It did not run the 3,000-AppID review collection.

## Contracts

- Current preflight contract: `{'json': 1, 'language': 'all', 'purchase_type': 'steam', 'review_type': 'all', 'filter': 'summary', 'filter_offtopic_activity': 1, 'num_per_page': 0}`
- Candidate documented contract: `{'json': 1, 'filter': 'all', 'cursor': '*', 'num_per_page': 1, 'language': 'all', 'purchase_type': 'steam', 'review_type': 'all', 'filter_offtopic_activity': 1, 'day_range': 365}`
- Added candidate parameter: `day_range=365`. Steam's documented `filter=all` table marks day_range as required and allows at most 365.
- Research population remained language=all, purchase_type=steam, review_type=all, filter_offtopic_activity=1.
- Official contract reference: https://partner.steamgames.com/doc/store/getreviews?language=english

## A/B sample

- A/B sample size: 10
- AppIDs tested: 10
- Free games: 2
- Paid games: 8
- Review-count bin counts: zero=2, 1-9=2, 10-19=1, 20-49=2, 50+=3

## Validation results

- query_summary exact matches: 10/10
- query_summary mismatches: 0/10
- Candidate count identities: 10/10
- Zero-review semantics: 2/2
- Request failures: 0
- Schema-invalid comparisons: 0
- Candidate Raw requested this execution: 10
- Candidate Raw reused this execution: 0
- Required field exact-match counts:
  - total_positive: 10/10
  - total_negative: 10/10
  - total_reviews: 10/10
  - review_score: 10/10
  - review_score_desc: 10/10

## Payload comparison

- Current individual review objects: 65
- Candidate individual review objects: 8
- Current response payload bytes: 103415
- Candidate response payload bytes: 23075
- Candidate minus current bytes: -80340
- Response payload reduction: 77.69%
- Byte counts use the same canonical UTF-8 JSON serialization of each preserved response payload; Raw wrapper metadata is excluded.

## Field-level comparison

| AppID | Bin | Free | Summary match | Count identity | Zero semantics | Current objects | Candidate objects | Current bytes | Candidate bytes |
|---:|---|:---:|:---:|:---:|:---:|---:|---:|---:|---:|
| 1239360 | 50+ | NO | PASS | PASS | PASS | 10 | 1 | 10981 | 1130 |
| 1476400 | 50+ | NO | PASS | PASS | PASS | 10 | 1 | 24940 | 5264 |
| 1951060 | 10-19 | NO | PASS | PASS | PASS | 10 | 1 | 16212 | 1519 |
| 3400380 | 50+ | NO | PASS | PASS | PASS | 10 | 1 | 11943 | 3533 |
| 3601300 | 1-9 | NO | PASS | PASS | PASS | 2 | 1 | 5472 | 4613 |
| 3733300 | zero | YES | PASS | PASS | PASS | 0 | 0 | 184 | 184 |
| 3874490 | 20-49 | NO | PASS | PASS | PASS | 10 | 1 | 14018 | 1468 |
| 3921530 | 20-49 | NO | PASS | PASS | PASS | 10 | 1 | 14599 | 3141 |
| 3966170 | 1-9 | NO | PASS | PASS | PASS | 3 | 1 | 4882 | 2039 |
| 4178160 | zero | YES | PASS | PASS | PASS | 0 | 0 | 184 | 184 |

The comparison covers total_positive, total_negative, total_reviews, review_score, and review_score_desc individually. No review text was analyzed or included in this report.

## Decision

- Final selected contract: `{'json': 1, 'filter': 'all', 'cursor': '*', 'num_per_page': 1, 'language': 'all', 'purchase_type': 'steam', 'review_type': 'all', 'filter_offtopic_activity': 1, 'day_range': 365}`
- Reason: All 10 query_summary comparisons were exact, all count identities held, and all zero-review semantics checks passed.
- Query-summary equivalence: PASS
- Zero-review semantics: PASS
- Research definition preserved: PASS
- Minimal payload contract: PASS
- Step 3B.1: PASS
- Ready for 3,000-review full collection: YES
