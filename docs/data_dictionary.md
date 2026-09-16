# Data Dictionary

## Step 3A processed outputs

The formal Step 3A outputs are data/processed/games.csv (one row per frozen
sample AppID) and data/processed/game_genres.csv (one row per game/genre
relationship). Store prices are snapshots at metadata_collected_at and must not
be interpreted as historical launch prices.

### games.csv

| Field | Type | Unit | Nullable | Source | Meaning |
|---|---|---|---|---|---|
| sample_id | integer | Stable row number | No | Locally derived | Deterministic 1..3000 index after sorting by release_date and appid; not the business key |
| appid | integer | Steam AppID | No | Frozen sample authority | Business primary key copied from sample_games.csv |
| name | string | None | No | Store appdetails, Search fallback | Store name when present; candidate Search name is used only as a non-null fallback |
| release_date | date | YYYY-MM-DD | No | Validated Store appdetails | Final release date used by the analytical layer |
| release_month | string | YYYY-MM | No | Locally derived | Sampling month derived from final release_date |
| developer | JSON array string | None | No | Step 2 eligible frame | All displayed developers; not reduced to the first value |
| publisher | JSON array string | None | Yes | Step 2 eligible frame | All displayed publishers; source absence remains null |
| is_free | boolean | None | No | Store appdetails | Authoritative free-game flag; never inferred from price absence |
| platform_windows | boolean | None | No | Store appdetails | Store-declared Windows support |
| platform_mac | boolean | None | No | Store appdetails | Store-declared macOS support |
| platform_linux | boolean | None | No | Store appdetails | Store-declared Linux support |
| appdetails_status | string | Status code | No | Step 2 pipeline | Final appdetails collection status; all Step 3A rows must be success |
| app_type | string | Type code | No | Store appdetails | Application type; all Step 3A rows must be game |
| list_price_cents | nullable integer | Integer cents | Yes | Store appdetails snapshot | Undiscounted storefront price at metadata collection time |
| current_price_cents | nullable integer | Integer cents | Yes | Store appdetails snapshot | Current storefront price after displayed discount |
| discount_percent | nullable integer | Percentage points | Yes | Store appdetails snapshot | Displayed discount constrained to 0..100 |
| price_currency | string | ISO currency code | Yes | Store appdetails snapshot | Currency returned for cc=us; retained without conversion |
| price_overview_present | boolean | None | No | Store appdetails | Whether the source response included a price overview |
| list_price_usd | nullable decimal | USD | Yes | Locally derived | list_price_cents divided by 100; null when source cents are null |
| current_price_usd | nullable decimal | USD | Yes | Locally derived | current_price_cents divided by 100; null when source cents are null |
| metadata_collected_at | datetime | UTC timestamp | No | Step 2 pipeline | Collection time for dynamic storefront metadata |
| search_release_date | date | YYYY-MM-DD | No | Steam Search | Parsed candidate-discovery date retained for reconciliation |
| store_release_date | date | YYYY-MM-DD | No | Store appdetails | Parsed Store date retained for reconciliation |
| release_date_conflict | boolean | None | No | Locally derived in Step 2 | Whether exact Search and Store dates differ |
| is_early_access | nullable boolean | None | Yes | Current source limitation | Always unknown in Step 3A because appdetails has no reliable explicit field |
| sample_seed | integer | PRNG seed | No | Frozen research design | Reproducibility seed 20250911 |
| sampling_stratum | string | YYYY-MM | No | Frozen sampling design | Row's release-month stratum |
| sampling_source | string | Provenance label | No | Frozen sampling design | proportional_stratified_random_sample |

### game_genres.csv

| Field | Type | Unit | Nullable | Source | Meaning |
|---|---|---|---|---|---|
| appid | integer | Steam AppID | No | Frozen sample plus Store metadata | Foreign key to games.csv; cannot reference an out-of-sample AppID |
| genre_id | string | Steam genre ID | Yes | Store appdetails snapshot | Source genre identifier; uniqueness is audited when available |
| genre_name | string | English label | No | Store appdetails snapshot | Full displayed genre name; no main genre is inferred |

## Step 3B review preflight outputs

The preflight uses 30 deterministic AppIDs from games.csv. It saves one Raw
wrapper per AppID and parses query_summary only; no review pagination is performed.

### review_preflight_sample.csv

| Field | Type | Unit | Nullable | Source | Meaning |
|---|---|---|---|---|---|
| appid | integer | Steam AppID | No | games.csv | Frozen market-sample key |
| name | string | None | No | games.csv | Store-authoritative game name |
| release_date | date | YYYY-MM-DD | No | games.csv | Validated Store release date |
| release_month | string | YYYY-MM | No | games.csv | Monthly preflight quota |
| is_free | boolean | None | No | games.csv | Store free-game status |
| list_price_cents | nullable integer | Integer cents | Yes | games.csv | Snapshot list price used only for coverage bands |
| price_currency | string | ISO currency code | Yes | games.csv | Snapshot currency |
| price_band | string | Coverage category | No | Locally derived | Free, unavailable, or paid price interval used for preflight diversity |
| sample_seed | integer | PRNG seed | No | Frozen design | Deterministic seed 20250911 |
| selection_method | string | Provenance label | No | Local pipeline | Monthly quota plus seeded price-band round-robin method |

### review_preflight_snapshot.csv

| Field | Type | Unit | Nullable | Source | Meaning |
|---|---|---|---|---|---|
| appid | integer | Steam AppID | No | Preflight sample | One snapshot row per preflight game |
| total_reviews | nullable integer | Reviews | Yes | Steam query_summary | Steam-purchase reviews at collection time; null on technical/source failure |
| positive_reviews | nullable integer | Reviews | Yes | Steam query_summary | Positive Steam-purchase reviews |
| negative_reviews | nullable integer | Reviews | Yes | Locally derived and source-validated | total_reviews minus positive_reviews; must equal source total_negative |
| positive_rate | nullable float | Proportion 0..1 | Yes | Locally derived | positive_reviews / total_reviews; null when total_reviews is zero |
| review_score | nullable integer | Steam category code | Yes | Steam query_summary | Steam review-score category, not a percentage |
| review_score_desc | string | None | Yes | Steam query_summary | English score description |
| review_language | string | Query contract | No | Pipeline provenance | Frozen value all |
| review_purchase_type | string | Query contract | No | Pipeline provenance | Frozen value steam |
| review_type | string | Query contract | No | Pipeline provenance | Frozen value all |
| filter_offtopic_activity | integer | Query contract | No | Pipeline provenance | Frozen value 1 |
| review_collected_at | datetime | UTC timestamp | No | Request wrapper | Dynamic review snapshot timestamp |
| review_status | string | Status code | No | Local pipeline | success, request_failed, schema_invalid, or unavailable |
| schema_error | string | None | Yes | Local validation | Preserved schema failure explanation |
| http_status | nullable integer | HTTP status | Yes | Request wrapper | Final HTTP status when a response was received |
| request_retry_count | nullable integer | Attempts beyond first | Yes | SteamClient telemetry | Retry attempts represented by the Raw wrapper |
| request_latency_seconds | nullable float | Seconds | Yes | SteamClient telemetry | End-to-end request latency including retries |
| http_429_count | nullable integer | Responses | Yes | SteamClient telemetry | Rate-limit responses represented by the Raw wrapper |

## Step 3B.2 full review outputs

The production collector reads only `data/processed/games.csv`, requires
exactly 3,000 unique AppIDs, and writes Raw wrappers separately under
`data/raw/reviews/full/`. During a complete execution it writes the technical
audit to `data/interim/review_snapshot_collection_audit.csv`. The formal
`data/processed/review_snapshots.csv` is written only after exact AppID
coverage, zero unresolved request/schema failures, valid count identities, and
unchanged frozen-input hashes are confirmed.

The formal snapshot uses the preflight fields above and additionally records:

| Field | Type | Unit | Nullable | Source | Meaning |
|---|---|---|---|---|---|
| day_range | integer | Days | No | Query contract | Frozen documented value 365 |
| http_5xx_count | nullable integer | Responses | Yes | SteamClient telemetry | Retryable 5xx responses represented by the Raw wrapper |
| transport_error_count | nullable integer | Failures | Yes | SteamClient telemetry | Timeout/connection failures represented by the Raw wrapper |

The production query is fixed to `json=1`, `filter=all`, `cursor=*`,
`num_per_page=1`, `language=all`, `purchase_type=steam`,
`review_type=all`, `filter_offtopic_activity=1`, and `day_range=365`.
No review pagination or individual-review corpus materialization is performed.

Step 3B final audit passed. The 3,000-game
`data/processed/review_snapshots.csv` is frozen with SHA-256
`D219D3DBBD9CE1502122E78D1B8E7CC8958A5EE645311D3B30E382F75CF5D3BB`;
its AppID set exactly matches `games.csv`, and the audit report is
`reports/step3b_final_audit.md`.

## Project-wide fields

`Source field` means a value copied or normalized from a source response. `Derived field` is calculated locally. `Snapshot field` is a source value that can change and therefore requires a collection timestamp.

| Field | Table | Type | Source | Definition | Nullable | Dynamic | Notes |
|---|---|---|---|---|---|---|---|
| appid | candidate_games | integer | Steam Search, source field | Steam application identifier | No | No | Candidate-frame key |
| name | candidate_games | string | Steam Search, source field | Name shown during candidate discovery | No | Yes | May change after discovery |
| release_date_raw | candidate_games | string | Steam Search, raw field | Unmodified release-date text | Yes | Yes | Retained when parsing fails |
| release_date | candidate_games | date | Derived field | Parsed calendar release date | Yes | Yes | Required before sampling |
| source | candidate_games | string | Pipeline metadata | Candidate discovery source | No | No | Supports provenance |
| candidate_collected_at | candidate_games | datetime UTC | Pipeline metadata | Candidate discovery timestamp | No | No | Snapshot timestamp |
| search_page | candidate_games | integer | Steam Search provenance | Zero- or one-based result page, as defined by the collector | Yes | No | Collector must document its convention |
| search_position | candidate_games | integer | Steam Search provenance | Position within the returned search page | Yes | No | Supports deterministic auditing |
| search_rank | candidate_games | integer | Derived provenance | Overall search-result rank at discovery time | Yes | Yes | Optional because result ordering can change |
| exclusion_reason | candidate_games | string | Derived field | Auditable reason an application was excluded | Yes | No | Null means not excluded at that stage |
| is_eligible | eligibility_decisions | boolean | Derived field | Whether reliable metadata identifies a base game | No | No | False requires an exclusion reason |
| evaluated_at | eligibility_decisions | datetime UTC | Pipeline metadata | Eligibility evaluation timestamp | No | No | Supports audit and reruns |
| in_official_game_catalog | candidate_catalog_match | boolean | Derived join field | Whether AppID appears in the documented game-only catalog | No | Yes | Does not by itself imply final eligibility |
| release_month | sample_games | string | Derived field | Calendar month in `YYYY-MM` format | No | No | Sampling stratum |
| appid | games | integer | Steam metadata, source field | Steam application identifier | No | No | Primary key |
| name | games | string | Steam metadata, source field | Current application name | No | Yes | Can differ from candidate name |
| release_date_raw | games | string | Steam metadata, raw field | Unmodified store release-date text | Yes | Yes | Preserve alongside parsed value |
| release_date | games | date | Derived field | Parsed store release date | Yes | Yes | Parse failures are logged |
| coming_soon | games | boolean | Steam metadata, source field | Store reports the app as not yet released | No | Yes | Used to reject unresolved future releases |
| appdetails_status | games | string | Pipeline metadata | Finite appdetails collection outcome | No | Yes | `success`, `unsuccessful`, `request_failed`, or `schema_invalid` |
| app_type | games | string | Steam metadata, source field | Application type returned by appdetails | Yes | Yes | Final base-game rule requires `game` |
| search_release_date | games | date | Steam Search, source field | Exact date parsed from the discovery result | Yes | Yes | Retained during reconciliation |
| store_release_date | games | date | Steam appdetails, source field | Exact date parsed from store metadata | Yes | Yes | Preferred for final eligibility |
| release_date_conflict | games | boolean | Derived field | Exact Search and store dates disagree | No | Yes | Never silently overwrite a disagreement |
| release_date_status | eligibility_decisions | string | Derived field | Finite Search/Store date reconciliation result | No | Yes | `exact_match`, `different_date`, `store_unparseable`, or `store_missing` |
| developer | games | array/string relation | Steam metadata, source field | One or more displayed developers | Yes | Yes | Normalize if multiple |
| publisher | games | array/string relation | Steam metadata, source field | One or more displayed publishers | Yes | Yes | Normalize if multiple |
| platform_windows | games | boolean | Steam metadata, source field | Windows support displayed in store metadata | No | Yes | Store-declared support |
| platform_mac | games | boolean | Steam metadata, source field | macOS support displayed in store metadata | No | Yes | Store-declared support |
| platform_linux | games | boolean | Steam metadata, source field | Linux support displayed in store metadata | No | Yes | Store-declared support |
| is_free | games | boolean | Steam metadata, source field | Store identifies the application as free | No | Yes | Never inferred only from price |
| is_early_access | games | boolean | Steam metadata, source field | Reliable Early Access indicator | Yes | Yes | Null means unknown |
| appid | game_genres | integer | Steam metadata, source field | Related game identifier | No | No | Composite relationship key |
| genre_id | game_genres | string | Steam metadata, source field | Steam genre identifier | Yes | Yes | Do not force one main genre |
| genre_name | game_genres | string | Steam metadata, source field | Displayed genre name | No | Yes | Localized using `l=english` |
| source | game_genres | string | Pipeline metadata | Genre source endpoint | No | No | Provenance field |
| collected_at | game_genres | datetime UTC | Pipeline metadata | Genre observation timestamp | No | No | Snapshot timestamp |
| appid | price_snapshots | integer | Steam metadata, source field | Related game identifier | No | No | One-to-many over collection runs |
| list_price_cents | price_snapshots | integer | Steam metadata, snapshot field | Undiscounted US store price in Steam source units | Yes | Yes | 100 cents = 1 USD; null for free or unavailable games |
| current_price_cents | price_snapshots | integer | Steam metadata, snapshot field | Current US store price after discount in Steam source units | Yes | Yes | 100 cents = 1 USD; null for free or unavailable games |
| discount_percent | price_snapshots | integer | Steam metadata, snapshot field | Displayed percentage discount | Yes | Yes | Usually 0 when not discounted |
| price_currency | price_snapshots | string | Steam metadata, snapshot field | Currency returned under `cc=us` | Yes | Yes | Expected `USD`; validate rather than assume |
| collected_at | price_snapshots | datetime UTC | Pipeline metadata | Price observation timestamp | No | No | Required for every price row |
| list_price_usd | analytical_games | decimal | Derived field | `list_price_cents / 100` | Yes | Yes | Generated during analytical processing, not stored in the raw snapshot |
| current_price_usd | analytical_games | decimal | Derived field | `current_price_cents / 100` | Yes | Yes | Generated during analytical processing, not stored in the raw snapshot |
| appid | review_snapshots | integer | Steam appreviews, source field | Related game identifier | No | No | Exactly one row per frozen sample AppID |
| positive_reviews | review_snapshots | integer | Steam appreviews, snapshot field | Eligible positive Steam-purchase reviews | No | Yes | Query uses all languages |
| negative_reviews | review_snapshots | integer | Steam appreviews, snapshot field | Eligible negative Steam-purchase reviews | No | Yes | Query uses all languages |
| total_reviews | review_snapshots | integer | Steam appreviews, snapshot field | Positive plus negative eligible reviews | No | Yes | Zero is valid |
| review_score | review_snapshots | integer | Steam appreviews, snapshot field | Steam review-score category code | Yes | Yes | Not a percentage |
| review_score_desc | review_snapshots | string | Steam appreviews, snapshot field | English review-score description | Yes | Yes | May be absent for no-review games |
| positive_rate | review_snapshots | float | Derived field | `positive_reviews / total_reviews` | Yes | Yes | Null when total is zero |
| review_collected_at | review_snapshots | datetime UTC | Pipeline metadata | Review observation timestamp | No | No | Required for every review row |
| appid | game_tags | integer | Optional future source | Related game identifier | No | No | Outside MVP collection |
| tag_id | game_tags | integer | Optional future source field | Steam tag identifier | Yes | Yes | Source availability varies |
| tag_name | game_tags | string | Optional future source field | English tag label | No | Yes | Tags can change over time |
| tag_rank | game_tags | integer | Optional future source field | Relative displayed tag position | Yes | Yes | Lower number means higher rank |
| source | game_tags | string | Pipeline metadata | Tag source | No | No | Required for provenance |
| collected_at | game_tags | datetime UTC | Pipeline metadata | Tag observation timestamp | No | No | Required if tags are added |
