# Step 5C Overdispersion-Robust Modeling & Influence Sensitivity

## 1. Why Step 5C was required

The frozen Step 5B Binomial converged, but Pearson dispersion was 73.516 and deviance/df was 61.816. Binomial p-values and CIs are retained only as a benchmark because their nominal precision is not credible under this extra-binomial variation.

## 2. Frozen specification

All models use the same 836 paid games, grouped response, 13 fixed coefficients, reference levels, predictors, and Step 5B scaling. Formula: `cbind(positive_reviews, negative_reviews) ~ z_log1p_price + z_days_since_release + platform_segment + genre_action + genre_adventure + genre_casual + genre_indie + genre_rpg + genre_simulation + genre_strategy`.

## 3. Quasibinomial results and uncertainty inflation

Quasibinomial converged in 5 iterations with estimated dispersion 73.5159. Its coefficients equal the Binomial mean coefficients as expected. SE inflation min/median/max = 8.5741 / 8.5741 / 8.5741, versus sqrt(phi) = 8.5741. CI-width inflation min/median/max = 8.5868 / 8.5868 / 8.5868.
Terms whose CI-crosses-1 status changed from Binomial to Quasi: z_log1p_price, genre_action, genre_casual, genre_strategy. Quasi logLik/AIC/BIC are NA because quasi-likelihood is not likelihood-comparable.

## 4. Beta-binomial implementation and heterogeneity

Implementation: glmmTMB 1.1.14 (TMB dependency 1.9.25) with `betabinomial(link=logit)`. Convergence code = 0, positive-definite Hessian = TRUE, max absolute fixed gradient = 0.0025056, warnings = 0. logLik = -3,395.153, AIC = 6,818.306, BIC = 6,884.507.
glmmTMB beta-binomial precision phi = 8.74673 under Var(Y)=n*p*(1-p)*(phi+n)/(phi+1). Larger phi means less extra-binomial heterogeneity and phi -> infinity is the Binomial limit. The derived latent within-game ICC is rho=1/(phi+1)=0.10260; larger rho means greater within-game dependence/heterogeneity.
All 13 fixed-effect profile-likelihood intervals completed with 0 warnings. The maximum absolute OR-endpoint difference from the Wald intervals was 0.0399. Tables retain both methods; the robust comparison figure uses profile intervals for beta-binomial.

## 5. Model comparison and coefficient stability

On the identical response/sample, beta-binomial minus Binomial delta AIC = -47,667.825 and logLik improvement = 23,834.912. This is strong fit evidence but is not the sole selection rule.
The largest non-intercept beta-vs-binomial OR change is `genre_simulation` at 41.98%.

| Term | Binomial OR [95% CI] | Quasi OR [95% CI] | Beta-binomial OR [95% CI] | Beta OR change |
|---|---:|---:|---:|---:|
| `z_log1p_price` | 0.9591 [0.9499, 0.9684] | 0.9591 [0.8831, 1.0417] | 0.9296 [0.8725, 0.9899] | 3.08% |
| `z_days_since_release` | 1.2984 [1.2875, 1.3094] | 1.2984 [1.2075, 1.3962] | 0.9827 [0.9255, 1.0436] | 24.32% |
| `platform_segmentWindows + macOS` | 1.2129 [1.1903, 1.2359] | 1.2129 [1.0319, 1.4256] | 1.4427 [1.1724, 1.7946] | 18.95% |
| `platform_segmentWindows + Linux` | 2.0431 [1.9823, 2.1057] | 2.0431 [1.5764, 2.6479] | 1.6315 [1.1960, 2.2978] | 20.14% |
| `platform_segmentWindows + macOS + Linux` | 1.4523 [1.3935, 1.5136] | 1.4523 [1.0183, 2.0712] | 1.5192 [1.2250, 1.9089] | 4.61% |
| `genre_action` | 1.0200 [1.0058, 1.0343] | 1.0200 [0.9045, 1.1501] | 0.8828 [0.7766, 1.0043] | 13.45% |
| `genre_adventure` | 1.0016 [0.9868, 1.0167] | 1.0016 [0.8813, 1.1384] | 0.9923 [0.8776, 1.1220] | 0.93% |
| `genre_casual` | 1.0352 [1.0175, 1.0531] | 1.0352 [0.8932, 1.1997] | 1.1065 [0.9706, 1.2625] | 6.89% |
| `genre_indie` | 1.2402 [1.2193, 1.2615] | 1.2402 [1.0714, 1.4357] | 1.1446 [0.9979, 1.3100] | 7.71% |
| `genre_rpg` | 0.7943 [0.7822, 0.8065] | 0.7943 [0.6964, 0.9059] | 0.9165 [0.8011, 1.0512] | 15.39% |
| `genre_simulation` | 1.3544 [1.3326, 1.3766] | 1.3544 [1.1784, 1.5568] | 0.7859 [0.6920, 0.8938] | 41.98% |
| `genre_strategy` | 0.8832 [0.8683, 0.8983] | 0.8832 [0.7635, 1.0216] | 0.8257 [0.7142, 0.9573] | 6.51% |

## 6. Influence sensitivity and review mass

Population sizes are Full=836, Minus top 1=835, Minus top 1%=827, Minus top 5%=794. Ranking is total_reviews descending then AppID ascending; exactly 1, 9, and 42 games are removed. All sensitivity fits reuse the full-sample price/day scaling.
Reviews removed for top 1 / top 1% / top 5% are 136,842 (12.80%), 535,657 (50.11%), 823,808 (77.06%).
The most influence-sensitive non-intercept term is `genre_simulation`, with maximum beta-binomial OR change 4.80% under `minus_top5pct`; headline class = Stable.
The descriptive robustness rule is: Stable when sign is unchanged and maximum OR change <=10%; Moderate for unchanged sign with >10%-25%; High for sign reversal or >25%.

## 7. Robust predicted effects

At z-price=0, z-days=0, Windows only, and all seven genres absent, predicted probabilities are Binomial 0.85457, Quasi 0.85457, and Beta-binomial 0.83869. All one-at-a-time contrasts are exported; they are associative, not causal.

## 8. Convergence, warnings, and diagnostics

All eight population-by-model fits converged; all four beta-binomial Hessians were positive definite. Total captured fit-warning rows with WARNING status = 0. No unvalidated Cook's D or leverage formula was constructed for glmmTMB; coefficient sensitivity is the primary influence diagnostic.
glmmTMB `diagnose()` returned a flag only for large z-statistics on the conditional intercept (20.74) and dispersion intercept (37.47). It reported no bad-parameter, gradient, or Hessian issue; extreme fixed estimate/SE count = 0, dispersion boundary flag = FALSE. Profile intervals address the stated Wald-approximation caution.
DHARMa was not installed and was optional, so no simulated-residual diagnostics were added.

## 9. Candidate final inferential model

The beta-binomial is the recommended candidate final inferential model: it directly models game-level extra-binomial heterogeneity, supplies a comparable likelihood, converged with a positive-definite Hessian, and supports the pre-defined review-volume coefficient sensitivity. Quasibinomial remains an important variance-only cross-check.

## 10. Limitations and Step 5D recommendation

These are observational associations in a review-qualified paid-game sample. Step 5D may examine the separately pre-specified threshold, release-month, raw-price, or free-game sensitivities. None was run in Step 5C.

## 11. Figures

- `figures/modeling/05_robust_or_comparison.png`
- `figures/modeling/06_ci_width_comparison.png`
- `figures/modeling/07_influence_sensitivity_coefficients.png`
- `figures/modeling/08_review_mass_removed.png`

Database access remained SELECT-only; before/after frozen object counts are unchanged. No credentials are written to outputs.
