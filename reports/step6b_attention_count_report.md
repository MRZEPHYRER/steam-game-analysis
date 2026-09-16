# Step 6B Positive Review-Count Intensity: Technical Audit

Audit status: **FAIL**. Positive-count model frozen: **FALSE**.

## Population and estimand
Market N=3000; zero-review N=759; positive-count N=2241; model N=2240.
Free positive N=34; paid positive N=2207; missing paid price excluded N=1.
The estimand is E(review count | at least one review), not sales, owners, revenue, or the market-wide count. Step 6A separately estimates P(any review).
All effects are conditional associations, not causal effects.

## Distribution and concentration
Median=10.00; mean=481.69; variance/mean=43265.34; max=136842.
Top game=0.1268; top 1%=0.6544; top 5%=0.8901; top 10%=0.9452; Gini=0.9530.

## Models and likelihood
Poisson Pearson dispersion=16773.71; deviance/df=2439.66. Poisson inference is invalid.
Ordinary NB2 theta=0.272942; truncated NB2 theta=1.31592e-09.
AIC: Poisson 5438448.07; ordinary NB2 23330.82; truncated NB2 21297.11.
Same positive rows and full likelihood constants independently verified: TRUE.
The truncated NB2 has the best AIC, but theta is near the zero boundary and the fit remains diagnostic-only, not frozen.

## Exposure and price
Selected exposure candidate: OFFSET. Log-days beta 0.8894 (SE 0.4668), z vs one -0.237.
Exposure AIC: log-days 21299.05; offset 21297.11; spline log-days 21299.66.
Paid-positive spline N=2206; full price support USD 0.49-199.99; central support USD 0.99-20.00.
Price df4 AIC change from df3: -30.33; this challenges df3 stability.
Free spline basis is zero; is_free is retained. Interpret price predictions, not spline coefficients.

## Diagnostics, sensitivity, and decision
Observed mean 481.90; fitted conditional mean 472.07; max relative bin error 0.796.
Largest nonspline ratio drift 5211014.786; central price-curve drift 0.893.
Top games stay in the main model. Their removal is sensitivity analysis only.
DHARMa is absent; no new package was installed. No zero-inflated model or ML benchmark was run.
- positive_count_population: PASS
- poisson_overdispersion_audited: PASS
- nb_convergence: PASS
- zero_truncation_addressed: PASS
- exposure_specification_justified: PASS
- price_nonlinear_basis_valid: PASS
- no_single_observation_dominates: FAIL
- tail_sensitivity_acceptable: FAIL
- diagnostics_acceptable: FAIL
- database_unchanged: PASS
A zero-truncated NB coefficient exponentiates to a latent-mean ratio; the positive-conditional count ratio also depends on the baseline mean.
No causal interpretation. Review count is not sales, owners, or revenue.
Database row counts unchanged: TRUE. Credentials remain in .env.

