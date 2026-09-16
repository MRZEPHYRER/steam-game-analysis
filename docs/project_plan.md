# Project Plan

## Project Objective

Build a clear, reproducible portfolio project that demonstrates public-data collection, ETL, SQL, exploratory analysis, statistical modeling, visualization, and evidence-based interpretation using recently released Steam games.

The MVP prioritizes a complete analytical pipeline over exhaustive catalog coverage or complex machine learning.

## Research Questions

1. What is the market structure of recently released Steam games?
2. How are prices, genres, platforms, release timing, free-to-play status, and review volume associated with player review outcomes?
3. Which observable attributes are statistically associated with highly rated games?

The project measures associations and does not claim causal effects.

## Scope

- Release dates: 2025-07-01 through 2025-12-31, inclusive.
- Target sample: 3,000 games.
- Unit: a base video game application available through the Steam store.
- Store locale: United States (`cc=us`) and English (`l=english`).
- Early Access: included and flagged when the source supports a reliable classification.
- Data are timestamped snapshots and may change after collection.

## Sampling Framework

1. Construct and preserve the full candidate frame for the release window.
2. Canonicalize duplicate AppIDs deterministically: prefer an in-window valid date, then the earliest candidate collection timestamp, then stable metadata fields. Warn when duplicates conflict.
3. Reject canonical records with invalid dates or dates outside the inclusive study window.
4. Collect the metadata needed to determine base-game eligibility.
5. Exclude ineligible application types and record `exclusion_reason`.
6. Derive `release_month` for the six monthly strata.
7. Allocate 3,000 seats proportionally with the largest remainder method.
8. Draw without replacement using random seed `20250911`.
9. Save the reproducible result as `data/processed/sample_games.csv`.

If fewer than 3,000 unique eligible candidates exist, the full pool is retained and a warning is recorded.

## Inclusion Criteria

- A valid Steam AppID.
- A valid release date inside the study window.
- Store metadata identifies the application as a base video game.
- The application was discoverable through the recorded candidate source at collection time.

## Exclusion Criteria

- DLC, demos, playtests, soundtracks, software, videos, tools, mods, or dedicated servers.
- Other applications that reliable type metadata identifies as non-base-game content.
- Records outside the study window or without a parseable final release date.

Name keywords alone are not sufficient evidence for type exclusion. Every excluded record must retain an auditable reason.

## Data Sources

- Steam Search public response: candidate discovery and release-ordered traversal. This is an undocumented dependency and its raw response structure must be monitored.
- Steam Store `appdetails`: application type, store metadata, platforms, release fields, and a US price snapshot. This public JSON endpoint is also undocumented.
- Steam `appreviews`: documented source for review aggregates.
- Documented Steam Web API: preferred where it supplies an equivalent field. Any API key is read only from `STEAM_API_KEY` in the environment.

Tags are optional because no stable documented bulk source is available. Estimated owners and single-point concurrent-player counts are outside the MVP.

Search collection is synchronous and resumable. Each page is stored atomically before its checkpoint advances. Following live Step 2A validation, the default request delay is 2.0 seconds plus up to 0.25 seconds of jitter because the original 1.0-second setting repeatedly triggered short connection cooldowns after roughly 30 requests.

## Review Definition

The primary review snapshot uses:

```text
language=all
purchase_type=steam
review_type=all
filter_offtopic_activity=1
```

`positive_rate` is `positive_reviews / total_reviews` when the denominator is positive. It is null when `total_reviews == 0`.

Two analytical samples are maintained:

- Market sample: all sampled eligible games, including zero-review games.
- Review sample: games with at least 20 eligible reviews.

Review thresholds of 10, 20, and 50 will be compared during sensitivity analysis.

## Price Definition

Price is a US Steam store snapshot, not a global price. It is represented by:

- `is_free`
- `list_price_cents`
- `current_price_cents`
- `discount_percent`
- `price_currency`
- `price_collected_at`

The snapshot preserves Steam's integer source units, where 100 cents equals 1 USD. `list_price_usd` and `current_price_usd` are derived later during analytical processing and are not duplicated in the raw snapshot. Free games retain null monetary fields. Free status is taken from source metadata and is not inferred from a numeric zero.

## Dataset Layers

- Raw: immutable source responses and the complete candidate frame.
- Interim: parsed metadata, eligibility decisions, exclusions, and quality checks.
- Processed: sampled games and analysis-ready relational tables.

Multi-value genres and optional tags use separate relationship tables rather than comma-separated permanent fields. Prices, reviews, and future tags include collection timestamps.

## Statistical Plan

The primary explanatory model is a binomial GLM using positive and negative review counts. Candidate predictors include free status, paid price, review volume, genre, and days since release. Review count will be reconsidered carefully because it represents both information volume and a potentially endogenous game outcome.

A secondary high-rating logistic model may use an 85% threshold with 80%, 85%, and 90% sensitivity checks. Wilson intervals or empirical Bayes smoothing will be used to communicate uncertainty in raw positive rates.

No modeling is implemented in Step 1.

## Known Limitations

- Candidate discovery and store metadata rely partly on undocumented public endpoints.
- Removed, region-restricted, age-gated, or temporarily unavailable games may be undercovered.
- Publisher-supplied dates, genres, platform support, and prices can change.
- Early Access status may be missing when it cannot be determined reliably.
- Prices describe the US storefront at one collection time and may include discounts.
- Reviews accumulate at unequal rates and do not represent every player.
- Filtering to games with enough reviews creates a selected review-analysis population.
- The design supports association, not causal inference.
