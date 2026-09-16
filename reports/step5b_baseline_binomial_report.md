# Step 5B Baseline Binomial Modeling & Diagnostics

## 1. Frozen specification

Primary population: `model20_paid` (total_reviews >= 20, paid games), N = 836.
Response: `cbind(positive_reviews, negative_reviews)`; family: `binomial(link = logit)`.
Formula: `cbind(positive_reviews, negative_reviews) ~ z_log1p_price + z_days_since_release + platform_segment + genre_action + genre_adventure + genre_casual + genre_indie + genre_rpg + genre_simulation + genre_strategy`. No rows were removed after the frozen sample was formed.

## 2. Analysis population and response totals

The sample has 836 unique games and 1,069,024 review trials: 943,294 positive and 125,730 negative. The pooled positive rate is 88.24%. All response identities and required non-missingness checks passed.

## 3. Scaling parameters

`log1p(current_price_usd)` mean = 2.2793, SD = 0.7226; back-transformed -1 SD / mean / +1 SD prices are $3.74 / $8.77 / $19.12.
Days since release mean = 347.30, SD = 49.98; mean -1 SD / mean / mean +1 SD are 297.32 / 347.30 / 397.29 days.

## 4. Model fit

Converged = TRUE in 5 iterations; coefficients = 13; residual df = 823.
logLik = -27,230.065; AIC = 54,486.131; BIC = 54,547.603; null deviance = 66,451.405; residual deviance = 50,874.434. AIC/BIC describe the frozen likelihood fit and are not used for variable selection.

## 5. Coefficients, odds ratios, and intervals

The complete log-odds, standard-error, z, p-value, Wald CI, OR, and OR-CI audit is in `step5b_coefficients.csv`. Numeric ORs are per +1 SD, not per $1 or per day. Platform contrasts use Windows only; genre contrasts use genre absent.
Profile-likelihood CI status = PASS; maximum absolute endpoint difference from the Wald OR CI = 0.0003.
Terms whose Wald OR interval crosses 1: genre_adventure.

| Term | OR | Wald 95% CI | Estimate (log odds) | SE | p-value |
|---|---:|---:|---:|---:|---:|
| `z_log1p_price` | 0.9591 | 0.9499 to 0.9684 | -0.0417 | 0.0049 | 1.878e-17 |
| `z_days_since_release` | 1.2984 | 1.2875 to 1.3094 | 0.2611 | 0.0043 | 0e+00 |
| `platform_segmentWindows + macOS` | 1.2129 | 1.1903 to 1.2359 | 0.1930 | 0.0096 | 7.555e-90 |
| `platform_segmentWindows + Linux` | 2.0431 | 1.9823 to 2.1057 | 0.7145 | 0.0154 | 0e+00 |
| `platform_segmentWindows + macOS + Linux` | 1.4523 | 1.3935 to 1.5136 | 0.3732 | 0.0211 | 4.86e-70 |
| `genre_action` | 1.0200 | 1.0058 to 1.0343 | 0.0198 | 0.0071 | 5.63e-03 |
| `genre_adventure` | 1.0016 | 0.9868 to 1.0167 | 0.0016 | 0.0076 | 8.3e-01 |
| `genre_casual` | 1.0352 | 1.0175 to 1.0531 | 0.0346 | 0.0088 | 7.981e-05 |
| `genre_indie` | 1.2402 | 1.2193 to 1.2615 | 0.2153 | 0.0087 | 2.243e-135 |
| `genre_rpg` | 0.7943 | 0.7822 to 0.8065 | -0.2303 | 0.0078 | 4.497e-191 |
| `genre_simulation` | 1.3544 | 1.3326 to 1.3766 | 0.3034 | 0.0083 | 2.601e-294 |
| `genre_strategy` | 0.8832 | 0.8683 to 0.8983 | -0.1242 | 0.0087 | 9.303e-47 |

## 6. Predicted-probability interpretation

At both standardized numeric predictors = 0, Windows only, and all seven genre indicators absent, the fitted positive probability is 0.8546. Each one-at-a-time contrast is exported in `step5b_predicted_effects.csv`; these are descriptive model contrasts, not causal effects.

## 7. Overdispersion diagnostics

Pearson chi-square = 60,503.565, residual df = 823, Pearson dispersion = 73.516. Residual deviance/df = 61.816. Material overdispersion flag = TRUE using ratio > 1.5 as the reporting threshold. The family was not changed.

## 8. Residual diagnostics

Absolute standardized deviance residual counts: >2 = 519 (62.08%), >3 = 372 (44.50%), >4 = 273 (32.66%). Full quantiles and the top 20 games are exported.

## 9. Leverage

Hat values: mean = 0.01555, 95th = 0.06619, 99th = 0.32661, max = 0.90027. The 2p/n threshold is 0.03110 with 73 games (8.73%) above it; 3p/n is 0.04665 with 51 games (6.10%) above it.

## 10. Influence and review-volume concentration

Cook's D: 95th = 1.050402, 99th = 12.899701, max = 376.069240. The 4/n threshold is 0.004785; 255 games (30.50%) exceed it; >0.5 = 60; >1 = 44.
Spearman rho(total reviews, leverage) = 0.9247; rho(total reviews, Cook's D) = 0.7762. The top-20 volume and top-20 Cook's D lists overlap by 10 games.
Step 5A established that the top 1%, 5%, and 10% of games contribute about 49.98%, 77.24%, and 86.42% of all reviews. Grouped binomial likelihood naturally gives high-volume games more Bernoulli information; the dispersion and influence results show whether that nominal information leads to overconfident or concentrated inference.

The ten largest Cook's distances are:

| AppID | Game | Total reviews | Cook's D | Leverage | Std. deviance residual |
|---:|---|---:|---:|---:|---:|
| 1943950 | Escape the Backrooms | 136,842 | 376.0692 | 0.5948 | 60.062 |
| 427410 | Abiotic Factor | 41,961 | 188.5039 | 0.4371 | 63.253 |
| 2285150 | The Front | 9,557 | 45.3807 | 0.0964 | -61.753 |
| 1657630 | Slime Rancher 2 | 43,483 | 31.4102 | 0.3293 | 30.749 |
| 3167020 | Escape From Duckov | 83,387 | 22.2286 | 0.7033 | -10.961 |
| 2958130 | Jurassic World Evolution 3 | 11,304 | 18.4352 | 0.2252 | 31.811 |
| 1963370 | No One Survived | 6,960 | 14.0705 | 0.1778 | -27.483 |
| 2486820 | Sonic Racing: CrossWorlds | 11,445 | 13.5304 | 0.1747 | 31.971 |
| 3101040 | Magical Girl Witch Trials | 29,730 | 13.0461 | 0.2882 | 22.070 |
| 1421250 | Tiny Bunny | 27,145 | 12.6278 | 0.3852 | -15.786 |

## 11. Collinearity and model matrix

Maximum adjusted GVIF = 1.3383. The actual model matrix has 836 rows, 13 columns, rank 13, exact dependencies = 0, and condition number = 5.4424.

## 12. Separation, convergence, and warnings

Fitted probabilities range from 0.722345 to 0.960995; below 0.001 = 0, above 0.999 = 0. Extreme-fit heuristic coefficient count = 0. GLM warning count = 0; profile-CI warning count = 0. Warning text is preserved in `step5b_fit_warnings.csv`.

## 13. Calibration-style descriptive check

Ten fitted-probability groups contain 84/84/84/84/84/84/83/83/83/83 games. The largest absolute pooled observed-minus-fitted gap is 0.0926 in decile 6 (signed gap = -0.0926). Their pooled observed rates are exported with mean fitted probabilities and median game rates. This is a descriptive in-sample check, not formal validation.

## 14. Baseline limitations and Step 5C recommendation

The baseline binomial shows meaningful overdispersion/influence concerns: Pearson dispersion = 73.516 and deviance/df = 61.816. Standard binomial standard errors therefore appear overconfident. Step 5C should compare quasi-binomial and beta-binomial inference and perform influence sensitivity; it should also assess the pre-specified alternative release-month and review-threshold specifications. No robustness model is fit here.

## 15. Figures

- `figures/modeling/01_baseline_calibration.png`
- `figures/modeling/02_residuals_vs_fitted.png`
- `figures/modeling/03_influence_review_volume.png`
- `figures/modeling/04_baseline_odds_ratios.png`

All database access used the existing read-only SELECT path. Before/after object counts are identical in `step5b_database_preservation.csv`. No credentials are written to outputs.
