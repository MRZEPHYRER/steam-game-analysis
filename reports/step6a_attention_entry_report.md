# Step 6A Review Attention Entry Analysis

## 研究范围

完整市场样本 N = 3000；has-review = 2241；zero-review = 759。Zero-review 在本阶段是 outcome 的非事件，必须保留。Review count 只表示 review attention / engagement / volume，不是 sales 或 owners。

Step 6A 只建模是否获得至少一条评论；不拟合 Poisson、Negative Binomial、zero-inflated 或 count hurdle 第二部分。

## Free 与 Paid 参数化

Free N = 402，raw entry rate = 8.46%；Paid N = 2598，raw entry rate = 84.95%。Raw risk difference（free - paid）= -76.49 percentage points。

Primary 同时包含 is_free 与 paid price component。Free rows 的 price component 固定为 0；paid price coefficient 只解释付费游戏内部、collection-time price 增加 1 SD 的条件关联。缺失 paid price 的游戏保留在市场描述分母，但排除于含 price 模型。

## Primary Logistic

Primary N = 2998；events/non-events = 2240/758；converged = TRUE；AIC = 2387.87。模型无权重、无 count offset、无 interactions。

所有系数均为条件关联。Free status 可能反映 game composition、discoverability、质量、开发成熟度、受众与发行策略，不能解释为免费导致无人评论。

## Functional-form audit

days_since_release MODEST_NONLINEARITY delta AIC 0.66 max probability gap 0.033; paid_log1p_price SUBSTANTIVE_NONLINEARITY delta AIC -14.94 max probability gap 0.525

Linear 是预设 primary；natural spline df=3 是固定 sensitivity。只有明显、实质的非线性才会触发 Step 6A.1，不能仅因 AIC 略低自动替换 primary。

最终 linear predictor adequacy = INADEQUATE。Step 6A audit status = PASS；current specification ready to freeze = FALSE；ready for Step 6B = FALSE。

## Diagnostics

In-sample AUC = 0.7990（95% CI 0.7784–0.8195）。Calibration 与 AUC 都是描述性诊断，不是模型选择或部署目标。

Influence diagnostics 不构成自动删点规则。Release-month 和 expanded-genre 模型均为预设 sensitivity。

## 解释边界

Attention 与 reception 是不同 outcome。Review entry 不等于销量、owners 或商业成功；所有模型都基于单次 Steam 快照，不能作因果推断。
