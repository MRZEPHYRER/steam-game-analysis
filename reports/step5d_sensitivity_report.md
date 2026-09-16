# Step 5D Pre-specified Sensitivity Analysis

## 1. Frozen primary

The primary candidate remains the grouped beta-binomial on 836 paid games with >=20 reviews. The independently refitted primary coefficients agree with the frozen Step 5C values within 1e-5. No primary formula, reference level, or scaling parameter was changed.

## 2. Threshold sensitivity

Modeling sample sizes for >0 / >=10 / >=20 / >=50 are 2206 / 1127 / 836 / 548. The >0 source contained 2,207 paid games; one game with two reviews lacked the frozen price predictor and was explicitly audited before fitting. All four populations are nested and use the primary scaling.
The largest non-intercept threshold OR drift is `platform_segmentWindows + Linux` at 22.32% in `TH_50`; direction change = FALSE. Threshold AIC values are not compared because rows differ.

## 3. Release sensitivity

Replacing standardized days with categorical release month produced AIC 6,822.202 versus primary 6,818.306 (delta 3.896). The largest shared-term OR drift is `platform_segmentWindows + macOS + Linux` at 0.80%.

| Month vs July | OR | 95% CI |
|---|---:|---:|
| 2025-07 | 1.0000 | [1.0000, 1.0000] |
| 2025-08 | 1.1090 | [0.9053, 1.3587] |
| 2025-09 | 1.2066 | [0.9834, 1.4804] |
| 2025-10 | 1.1707 | [0.9549, 1.4352] |
| 2025-11 | 1.1370 | [0.9364, 1.3804] |
| 2025-12 | 1.0415 | [0.8367, 1.2963] |

## 4. Price sensitivity

Primary raw-price mean/SD are $11.57 / $9.67. The +1 SD log-price OR is 0.9296; the +1 SD raw-price OR is 0.9350. Their predicted probability contrasts are -0.01013 and -0.00925.
The largest shared non-intercept OR drift under raw price is `genre_indie` at 1.26%.

## 5. Genre sensitivity

Early Access here is the Steam genre/category label from the frozen genre mapping; it is not historical or launch-state status. Sports and Racing are sparse, so interval width and coefficient stability take priority over p-values.

| Added Steam label | Games | OR | 95% CI |
|---|---:|---:|---:|
| Early Access label | 93 | 0.9746 | [0.8094, 1.1735] |
| Sports | 31 | 1.2384 | [0.8881, 1.7269] |
| Racing | 20 | 1.0611 | [0.7059, 1.5950] |

The largest OR drift among the original seven genre coefficients is `genre_simulation` at 1.61%.

## 6. Core predictor stability

| Predictor | OR range | Same direction | CI excludes 1 | Max drift | Class |
|---|---:|---:|---:|---:|---|
| Indie | 1.0795-1.1785 | 7/7 | 3/7 | 5.69% | ROBUST |
| RPG | 0.9118-0.9590 | 7/7 | 0/7 | 4.64% | ROBUST |
| Simulation | 0.7138-0.8397 | 7/7 | 7/7 | 9.17% | ROBUST |
| Strategy | 0.8066-0.9104 | 7/7 | 6/7 | 10.26% | PARTIAL |
| Windows + Linux | 1.2674-1.7575 | 7/7 | 6/7 | 22.32% | PARTIAL |
| Windows + macOS | 1.2585-1.4759 | 7/7 | 7/7 | 12.77% | PARTIAL |
| Windows + macOS + Linux | 1.3586-1.7006 | 7/7 | 7/7 | 11.94% | PARTIAL |
| Days since release (+1 SD) | 0.9523-0.9830 | 6/6 | 0/6 | 3.09% | ROBUST |
| Price (+1 SD) | 0.9256-0.9554 | 7/7 | 5/7 | 2.78% | ROBUST |

Price is ROBUST across 7 specifications (OR range 0.9256-0.9554, max drift 2.78%). Simulation is ROBUST (OR range 0.7138-0.8397, max drift 9.17%). Strategy is PARTIAL because its maximum OR drift is 10.26%.

## 7. Diagnostics

All seven fits have convergence code 0 and positive-definite Hessians. Maximum absolute gradients range from 0.001595 to 0.006996; captured fit warnings = 0. Phi ranges from 6.5356 to 9.4018, and rho from 0.0961 to 0.1327.

## 8. Remaining uncertainty

Threshold changes alter the analysis rows, so their AIC values are descriptive fit records rather than model-ranking evidence. Release-month, raw-price, and expanded-genre AIC comparisons use identical rows but do not automatically replace the frozen primary specification. All intervals in this sensitivity audit are model-based Wald intervals.

## 9. Recommendation

Retain the frozen primary beta-binomial for human review. Interpret each predictor separately using the exported direction, magnitude, interval, and stability evidence; do not revise the primary automatically. Database access remained read-only, and no sensitive values are written to outputs.
