# Step 6B.1 Fast Attention Tier Model Freeze

Status: **PASS**. Final model: cumulative ordinal logistic.
Proportional-odds assumption: **APPROXIMATE**. High-100 robustness: **PASS**.

## Population and tiers
Positive-count population N=2241; model N=2240; zero-review games excluded N=759.
- Tier1: N=1102 (49.17%), median reviews=3, free=22, paid=1080
- Tier2: N=733 (32.71%), median reviews=23, free=9, paid=724
- Tier3: N=293 (13.07%), median reviews=231, free=2, paid=291
- Tier4: N=113 (5.04%), median reviews=2574, free=1, paid=112

## Primary ordinal model
Convergence code=0; design rank=16/16; maximum coefficient SE=0.886; AIC=4663.48.
An OR above 1 denotes higher odds of being in a higher attention tier; it is not a review-count multiplier.
Free OR=0.508 (95% CI 0.249-1.034); this subgroup has only 34 games.
Log-days OR=2.756 (95% CI 1.600-4.749).

## Proportional-odds and High-100 audit
Exact threshold-direction agreement among non-price terms=50.0%; major direction reversals=0.
Several weak coefficients change sign across boundaries, so proportional odds holds approximately rather than exactly.
High-100 model events=406; major ordinal/High-100 contradictions=0; price-shape Spearman correlation=1.00.

## Price probabilities
The paid-price spline is re-estimated on 2,206 reviewed paid games. Free rows have a zero spline basis and retain is_free.
- $0.99: Tier1 76.7%, Tier2 18.6%, Tier3 3.8%, Tier4 1.0%
- $2.99: Tier1 72.5%, Tier2 21.6%, Tier3 4.6%, Tier4 1.2%
- $4.99: Tier1 65.4%, Tier2 26.6%, Tier3 6.3%, Tier4 1.7%
- $9.99: Tier1 45.4%, Tier2 38.1%, Tier3 12.7%, Tier4 3.8%
- $14.99: Tier1 32.5%, Tier2 42.0%, Tier3 19.1%, Tier4 6.4%
- $19.99: Tier1 24.5%, Tier2 41.8%, Tier3 24.5%, Tier4 9.2%
Spline coefficients are not interpreted separately. Price associations are not causal.

## Portfolio Summary
- 25.3% of sampled games received zero Steam reviews.
- Among reviewed games, 49.2% were Tier 1 and 5.0% were Tier 4.
- Review attention was extremely concentrated; the raw count model was not stable under the heavy tail.
- Attention intensity was therefore summarized with four ordered tiers and an ordinal logistic model.
- The proportional-odds assumption was approximate, while the pre-specified High-100 logistic check broadly agreed.

## Freeze decision and limitations
- population_valid: PASS
- ordinal_model_converged: PASS
- no_major_numerical_problem: PASS
- proportional_odds_acceptable_or_approximate: PASS
- high100_robustness_broadly_agrees: PASS
- no_major_direction_contradictions: PASS
- reports_render: PASS
- database_unchanged: PASS
The model compresses a severe heavy tail into portfolio-friendly tiers, sacrificing within-tier count detail.
The proportional-odds assumption is approximate, the free subgroup is sparse, and all coefficients are conditional associations.
The raw Step 6B count-model failure remains part of the methodological record.
Database counts unchanged: TRUE. No credentials are written to outputs.

