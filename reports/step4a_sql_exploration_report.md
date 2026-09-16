# Step 4A SQL Exploration Report

## Database status and execution

The frozen `steam_game_analysis` database passed the standard Step 3C audit
before and after all analysis queries. Twenty-seven named result sets from nine
SQL files were executed inside a read-only MySQL transaction. Only after every
query succeeded were 27 deterministic CSV outputs and the manifest written.

Market and model samples remain distinct:

- Market sample: all 3,000 games, including zero- and low-review games.
- Model candidate sample: 844 games with `total_reviews >= 20`.

`total_reviews` is treated only as a player-attention/market-engagement proxy.
`positive_rate` is observed positivity among available Steam-purchase reviews,
not objective game quality. Price is a collection-time storefront snapshot.

## Market structure

- The sample contains 3,000 games: 402 free (13.40%) and 2,598 paid (86.60%).
- 2,241 games have at least one review; 759 (25.30%) have zero reviews.
- Platform support is Windows 2,999, macOS 439, and Linux 363. Mutually exclusive
  platform segments are dominated by Windows-only games (2,398; 79.93%).
- These are properties observed in the sampled July-December 2025 release frame,
  not estimates of all Steam history.

## Collection-time price findings

- Among 2,597 paid games with observed prices, current price ranges from $0.49
  to $199.99; mean is $8.52 and window-derived median is $4.99.
- The largest price band is $0.01-$4.99 (1,301 games; 43.37% of the full sample),
  followed by $5.00-$9.99 (744; 24.80%). One paid game has missing price.
- Review-volume means rise across several higher price bands, but medians are far
  lower than means. For example, the $10-$19.99 band has mean 951.23 reviews and
  median 30; the $30+ band has mean 2,397.61 and median 125.5.
- Price quartile review medians increase from 3 to 27 across quartiles, while
  average observed positivity is not monotonic (0.8033-0.8300). This is an
  associated pattern only; selection and confounding are unaddressed.

## Review-volume findings

- Review volume is strongly right-skewed: 759 games (25.30%) have zero reviews,
  and 1,102 (36.73%) have 1-9. Only 113 games (3.77%) have 1,000+, with a maximum
  of 136,842.
- Free games in this release cohort are mostly zero-review (91.54%), compared
  with 15.05% of paid games. The >=20 shares are 1.99% and 32.18%, respectively.
- Mean review counts (free 7.11; paid 414.40) are dominated by the upper tail;
  medians (0 and 6) and `AVG(LN(1 + total_reviews))` are more stable descriptors.
- These counts describe observed attention, not owners, revenue, sales, or copies sold.

## Positive-rate findings

- Positive-rate analysis excludes all zero-review games and never replaces NULL
  with zero.
- Among games with 1-9 reviews, median positivity is 1.0000 and 60.98% have a
  perfect observed rate. The perfect-rate share falls to 15.70% at 20-49 reviews,
  4.83% at 50-99, and zero in both 500-999 and 1,000+ bands.
- Of 832 perfect-rate games, 672 (80.77%) have fewer than 10 reviews. This shows
  why raw rates for small review counts are unstable and motivates interval or
  shrinkage methods later.
- Reviewed free games have mean 0.8374 and median 1.0000, but only 34 free games
  have reviews; this descriptive comparison is especially sample-sensitive.

## Genre findings

- Genre memberships are multi-label and total 8,796, so genre counts can exceed
  3,000 when summed. Indie is most common (2,218; 73.93%), followed by Casual
  (1,370), Adventure (1,187), and Action (1,135).
- Simulation has the highest >=20 coverage among larger genres (38.31%), followed
  by RPG (36.54%) and Adventure (34.29%). Free To Play has 2.27% coverage and a
  91.41% zero-review share in this sample.
- With minimum 30 genre games and 20 candidate games, Action ranks first on mean
  review volume, while Casual ranks first on >=20-sample mean positivity. These
  ranks remain descriptive and do not adjust for overlapping genres.

## Release-month findings

- Model-candidate coverage ranges from 23.03% in December to 33.72% in September.
  November has the lowest zero-review share (19.83%); July has the highest (27.77%).
- Average review volume is highest for September (785.98) and October (659.77),
  but their log summaries are much closer to other months, again showing outlier
  sensitivity.
- December has the highest mean observed positivity (0.8362), while July has the
  lowest (0.8048). These are observed month differences, not seasonality or causal effects.

## Platform and high-attention findings

- Windows-only games form 79.93% of the sample. The all-three-platform segment
  has the highest >=20 share (39.20%), but platform groups differ in size and mix.
- The top review-volume ventile contains 150 games and begins at 604 reviews.
  Its mean is 6,589.24 reviews, free share 0.67%, mean observed price $18.17, and
  mean positivity 0.8429.
- Indie (64.00%), Adventure (48.00%), and Action (45.33%) are the largest genre
  memberships in this high-attention subset. Multi-label shares need not sum to 100%.
- “High attention” means high observed review volume only, not best or successful games.

## Full versus model candidate sample

- The >=20 sample contains 844 games (28.13% of the market sample).
- Free share falls from 13.40% to 0.95%; paid observed-price median rises from
  $4.99 to $9.99. macOS support rises from 14.63% to 18.48%, and Linux from
  12.10% to 13.98%.
- Adventure (+8.66 percentage points), Simulation (+8.15), and RPG (+5.70) are
  more prevalent by membership in the model sample. Free To Play (-12.13) and
  Casual (-7.04) are less prevalent.
- Consequently, later model results cannot be presented as composition-neutral
  summaries of all 3,000 sampled games.

## SQL techniques used

The analysis uses CTEs, conditional aggregation, explicit joins, robust middle-
position medians, `NTILE(4)`, `NTILE(20)`, `ROW_NUMBER()`, `DENSE_RANK()`,
and `PERCENT_RANK()`.
Every formal analysis statement starts with `SELECT` or `WITH`; the runner blocks
DDL, DML, privilege, load, call, and session-setting keywords in analysis files.

## Limitations and candidate questions

- Review volume is an incomplete, highly skewed attention proxy.
- Raw positive rate is unstable for small counts; Step 4B should visualize this
  and Step 5 may consider Wilson intervals or empirical-Bayes shrinkage.
- Price is cross-sectional at collection time and cannot recover launch or price history.
- Genre overlap prevents interpreting genre rows as mutually exclusive groups.
- Month, platform, price, and genre patterns are associations and do not prove causes.
- Step 4B should examine skew, composition, and missingness visually while retaining
  the market/model distinction; no hypothesis testing or modeling is warranted yet.
