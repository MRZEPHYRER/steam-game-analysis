# Step 2C appdetails Preflight Report

## Population and sample

- Source study-window population: 10,115
- Preflight sample size: 20
- Random seed: 20250911

### Monthly preflight distribution

| Month | Count |
|---|---:|
| 2025-07 | 3 |
| 2025-08 | 3 |
| 2025-09 | 3 |
| 2025-10 | 4 |
| 2025-11 | 4 |
| 2025-12 | 3 |

## Response and eligibility validation

- Successful appdetails responses: 20
- Failed appdetails responses: 0
- AppID identity errors: 0
- Eligible: 20
- Ineligible: 0

### App type distribution

- `game`: 20

### Exclusion reasons

No exclusions.

## Release-date reconciliation

- Exact matches: 20
- Different dates: 0
- Store unparseable: 0
- Store missing: 0

## Price validation

- Free games: 2
- Paid games: 18
- Returned paid-game currencies: ['USD']
- Unexpected currencies: None
- Integer cents validation: PASS

## Multi-value and platform fields

- Games with genres: 20
- Games without genres: 0
- Total genre relation rows: 61
- Mean genres per game with genres: 3.05
- Windows supported: 20
- macOS supported: 0
- Linux supported: 2
- Missing developer fields: 0
- Missing publisher fields: 0

## Early Access

- True: 0
- False: 0
- Unknown: 20
- Early Access reliable classification unavailable from current source.

## Schema and problems

- Schema-invalid responses: 0
- Schema drift status: NONE

### Problems discovered

- Early Access reliable classification unavailable from current source.

## Recommendation

Do not expand automatically. Review this preflight, then authorize the full 10,115-AppID collection only if the observed schema and quality results are acceptable.
