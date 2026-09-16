# Step 6A.1 Nonlinear Review-Entry Specification Freeze

## 目标与边界

本轮只修复 Step 6A 已识别的 paid-price functional-form misspecification。Logistic link/framework 保持有效；没有进入 Step 6B，也没有拟合 count model、机器学习模型或未经预设的 interaction。

## Frozen sample 与 spline parameterization

Market N = 3000；nonlinear primary N = 2998。继续排除 1 个缺失 paid price 游戏和 1 个 Other platform 游戏；402 个 free games 全部保留。

Paid price 使用 natural spline df=3。Knots 与 Boundary.knots 从 2597 个有效 paid-market prices 一次性估计并冻结；prediction 复用相同定义。Spline basis 在 mean log-price 对应的 $6.00 处中心化，free rows 的三个 basis columns 全为 0。

Spline basis coefficients 只用于构造 nonlinear price-response curve，不解释为业务效应或独立 OR。

## Linear benchmark 与 nonlinear primary

Linear benchmark AIC/BIC = 2387.87/2471.95；nonlinear primary AIC/BIC = 2373.03/2469.12；delta AIC/BIC = -14.84/-2.83。

Nesting audit: strictly nested = TRUE；formal LRT valid = TRUE；p = 8.103e-05

对 Step 6A paid-only auxiliary comparison 的回溯审计同样确认 strictly nested = TRUE，因此原 formal LRT 使用合法。

## Price curve 与 support

Observed paid price support 为 $0.49–$199.99；主要解释区间固定为 empirical 5th–95th percentile：$0.99–$19.99。

在该模型和观测数据支持范围内，predicted review-entry probability 的拟合曲线在约 $14.92 达到最高值 88.15%（pointwise 95% CI 84.11%–91.27%）。

以距拟合峰值 0.5 percentage points 内定义局部 plateau，范围约为 $11.07–$20.30。该峰值是描述性拟合最大值，不是最优价格。

高价尾部很稀疏：N≥$20/30/50/100 分别为 126/46/18/6。尾部下降不作稳健规律或因果解释。

## Other predictors

is_free OR = 1.1123（95% CI 0.8843–1.3990）；centered paid reference probability = 83.35%；free probability = 6.78%。

days OR = 1.248（95% CI 0.993–1.568）。Platform 与七类 genre 继续解释为 conditional associations。

## Diagnostics 与 sensitivity

Nonlinear model converged = TRUE；separation flags = 0；max Cook's D = 0.0093；maximum calibration gap = 4.42 percentage points。

Linear/nonlinear AUC = 0.7990/0.8044；Brier = 0.11798/0.11692；log loss = 0.39357/0.39043。

Release-month 与 expanded-genre sensitivities 在 central support 相对 primary 的最大绝对概率差分别为 1.59 和 0.25 percentage points。

df=4 sensitivity AIC = 2373.94；peak = $16.23；central-support df4-vs-df3 最大概率差 = 1.17 percentage points。

Optional GAM diagnostic status = RUN；edf = 3.280；central-support GAM-vs-df3 最大概率差 = 1.05 percentage points。

## Freeze decision

PRICE FORM = SPLINE ADEQUATE；Step 6A.1 = PASS；Review Entry model frozen = TRUE；Ready for Step 6B = TRUE。

Final entry model 是 logistic regression，其中 paid collection-time price 使用 frozen、centered natural spline df=3，days 保持线性，并保留 is_free、platform 与七个 genre。Linear model 仅保留为 benchmark。

## Interpretation boundary 与 future work

Review entry 表示 review attention，不是 sales、owners、reception 或因果效果。未来可将 GAM、Random Forest、Gradient Boosting/XGBoost 用于 predictive benchmark、nonlinear pattern validation 或 interaction discovery，但它们不自动替代当前 inferential model。
