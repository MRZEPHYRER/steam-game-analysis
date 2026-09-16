# Step 5F Wilson + Empirical Bayes Rating Adjustment

## 范围与样本

市场样本 N = 3000；零评论游戏 N = 759，保留在市场总体但不进入 rating estimation；n > 0 的 rating population N = 2241，同时保留 free 与 paid games。

本阶段不拟合 price、genre、platform 或 release predictor regression，也不作因果解释。

## Wilson score interval

使用 z = 1.959963984540054 的非连续性校正 95% Wilson score interval。闭式公式与 Base R `uniroot` 的 score-test 反演在 11 个预先指定案例中全部通过 1e-9 容差。

Wilson interval 是频率学派抽样不确定性区间，不改变 Raw point estimate。Wilson lower 只用于 conservative uncertainty-aware ranking，不是 posterior mean，也不称为调整后评分。

## Empirical Bayes prior

Primary prior 由全部 n > 0 游戏通过 Beta-Binomial marginal likelihood 确定性估计：alpha = 5.022109，beta = 1.044820，prior mean = 0.827784，precision / ESS = 6.066930，variance = 0.02017247。

有界 L-BFGS-B 定位并经 BFGS 精修；最终 convergence code = 0；maximum absolute analytic gradient = 3.489818e-07；minimum Hessian eigenvalue = 2.013623e+02；three deterministic starts agree = TRUE。

Primary prior 让大量低 n 游戏参与总体分布估计，因此另以 n>=10 和 n>=20 估计 prior，并将三套 prior 都应用到同一个 2,241-game evaluation population。替代 prior 仅作敏感性分析。

## Shrinkage 与排名

评论数与绝对收缩的 Spearman 相关为 -0.9121。n>=1000 游戏的 median / p95 / max absolute shrinkage 分别为 0.017 / 0.087 / 0.159 个百分点。

Raw-Wilson、Raw-EB、Wilson-EB 的 Spearman 相关分别为 0.2395、0.7761、0.6725。Raw ranking 以 rate 降序、review count 降序、AppID 升序作 deterministic tie-break；review count 只解决 ties，不是 Raw rating 权重。

由于 Raw 100% 存在大量 ties，rank movement 不是纯连续指标，必须和 Raw rate、review count、Wilson lower 与 EB mean 一并解释。EB posterior mean 是 population-informed shrinkage estimate，不是真实评分。

## 科学角色边界

- Beta-binomial：主要推断回归。
- High-rating Logistic：次要门槛分析。
- Wilson：uncertainty-aware descriptive interval。
- Empirical Bayes：population-informed shrinkage rating。

四者解决的问题不同，结果不可互相替代；Step 5F 不进行 causal interpretation。
