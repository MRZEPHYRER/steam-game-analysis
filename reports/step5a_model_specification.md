# Step 5A — Model Specification & Data Audit

## 1. Research question

在至少拥有 20 条符合研究定义的 Steam 购买者评论的游戏中，采集时点价格、
发布时点、平台支持和多标签 genre 与玩家正面评价概率之间存在怎样的统计
关联？所有后续解释均限定为 association，不作因果解释。

本阶段只冻结候选规格并审计数据；没有拟合 Binomial、Quasibinomial、
Beta-binomial、Logistic、Poisson、Negative Binomial、Hurdle、
Zero-inflated 或机器学习模型。

## 2. Primary response

候选正式响应固定为：

```r
cbind(positive_reviews, negative_reviews)
```

理论规格为 (Y_i sim Binomial(n_i, p_i))，其中
(Y_i=positive_reviews)，(n_i=total_reviews)，且
(negative_reviews=n_i-Y_i)。不把 `positive_rate` 当作普通同方差连续
响应，也不额外设置 `total_reviews`、`log(total_reviews)` 或
`sqrt(total_reviews)` 权重。不同分母的信息由二项计数自然进入似然。

844 个 model20 游戏全部满足：

- positive 和 negative 计数非负；
- `total_reviews > 0`；
- `positive_reviews + negative_reviews == total_reviews`。

## 3. Primary and sensitivity samples

| Stage | N | 本阶段排除理由/数量 |
|---|---:|---|
| Market sample | 3,000 | 无 |
| At least 1 review | 2,241 | 零评论 759 |
| At least 10 reviews | 1,139 | 1–9 条评论 1,102 |
| At least 20 reviews | 844 | 10–19 条评论 295 |
| At least 50 reviews | 551 | 20–49 条评论 293 |
| model20 paid | 836 | 免费游戏 8 |
| model20 paid complete-case | 836 | 必需字段缺失 0 |

`reception_50 ⊂ reception_20 ⊂ reception_10 ⊂ reception_gt0` 已用 AppID
逐级验证。市场对象始终保持 3,000 行，759 个零评论游戏没有被全局过滤、
赋值为负面评价或施加人工零权重。

## 4. Model20 population audit

model20_all 有 844 个唯一 AppID、944,954 条正面评论、126,810 条负面评论，
合计 1,071,764 条评论。每游戏评论量最小 20、Q1 38、中位数 90、均值
1,269.86、Q3 353、最大值 136,842。

免费游戏 8 个（0.95%），付费游戏 836 个（99.05%）。8 个免费游戏合计
1,660 条正面和 1,080 条负面评论。其数量过少，且 genre、月份和平台组合
分散，不适合在主 model20 中作为普通、稳定的二元价格状态系数。

**Recommendation：**以 `model20_paid` 作为候选主分析 population；
`model20_all` 保留为明确的 sensitivity population。该建议需人工确认，
本阶段不自行冻结最终选择。

## 5. Price specification

`model20_paid` 的 836 个游戏全部具有 current price 与 list price：

- current price：$0.59–$69.99；
- Q1 $4.99、中位数 $9.99、均值 $11.57、Q3 $14.99；
- 标准差 $9.67；
- 原始价格偏度 2.164；
- `log1p_current_price` 偏度 -0.108。

候选主规格使用 `scale(log1p_current_price)`，原始
`current_price_usd` 作为预注册替代规格。免费游戏的货币字段保留原始
NULL 语义，没有把免费价格人工填成普通付费价格 0。

`current_price_usd` 是 2026-09-13 前后采集的美国 Steam storefront
快照，不是 launch price、历史均价、评论者实际支付价格或全球价格。
后续系数只能解释为当前观察商店价格与 reception 的关联。

## 6. Release timing

`release_date` 与 `review_collected_at` 均完整可用。
`days_since_release = review snapshot collection date - release date`，
单位为天。model20_paid 的结果为：

- missing 0；非正值 0；
- min 256、Q1 304、中位数 347、均值 347.30、Q3 391、max 439；
- review snapshot 日期唯一值为 2026-09-13。

按月份的中位暴露天数从 2025-07 的 423 天单调降至 2025-12 的 277 天。
月份序号与 days_since_release 的相关为 -0.986，说明二者高度结构相关。

**Recommendation：**不要在默认主规格中同时放入二者。候选 Model A 使用
`release_month`（reference 2025-07），Model B 用标准化
`days_since_release` 替换它；在 Step 5B 比较预先声明的规格，而不是
基于 p-value 自动选择。

## 7. Platform specification

model20_paid 中实际存在四个水平：

| Platform segment | N | Share |
|---|---:|---:|
| Windows only | 643 | 76.91% |
| Windows + macOS | 78 | 9.33% |
| Windows + Linux | 40 | 4.78% |
| Windows + macOS + Linux | 75 | 8.97% |
| Other | 0 | 0% |

四个观察水平均至少有 40 个游戏，建议保留；`Other` 在候选样本中为空，
应仅删除未使用的 factor level，不删除任何游戏，也无需构造虚假的合并组。
reference 为 `Windows only`。

交叉单元仍可能稀疏：release month × platform 的 24 个单元没有空单元，
但 7 个单元 N<10；platform × genre 的 52 个单元中 12 个为空、17 个
N<5、23 个 N<10。正式模型后必须审查系数稳定性。

## 8. Genre encoding and frequency

8,796 条 genre 关系已转为 3,000 行、每个 AppID 一行的 13 个 0/1 指示
变量；同一游戏可以有多个 1。genre absent = 0 为 reference。没有把
genre relation 行误当作独立游戏观测。

model20_paid 的主要频数为：Indie 614、Adventure 405、Casual 324、
Action 319、Simulation 255、RPG 207、Strategy 178、Early Access 93、
Sports 31、Racing 20、Massively Multiplayer 6、Free To Play 2、
Game Development 0。

### Candidate genre sets

- main：Action、Adventure、Casual、Indie、RPG、Simulation、Strategy
  （均 N≥100）；
- sensitivity：在 main 基础上加入 Early Access、Sports、Racing
  （均 N≥20）；
- 暂不进入 main：Massively Multiplayer、Free To Play、
  Game Development。

筛选依据仅为频数、稀疏性、可解释性与结构冗余，不涉及 outcome p-value。

## 9. Genre co-occurrence and structural collinearity

最大共现对包括：

- Adventure + Indie：310，较小 genre 的 76.54%；
- Casual + Indie：275，覆盖 84.88%；
- Action + Indie：237，覆盖 74.29%；
- Indie + Simulation：200，覆盖 78.43%；
- Action + Adventure：185，覆盖 57.99%。

绝对 phi correlation 最高的主要对为 Racing + Sports 0.342、
Action + Casual -0.210、Casual + Indie 0.206、
Action + Strategy -0.186、Adventure + Strategy -0.183。
这些值未显示近乎重复的 main genre，但高覆盖与多标签共现仍要求在 Step 5B
结合 VIF/GVIF 和系数稳定性继续检查。Game Development 在 model20_paid
为全零，因此其 phi correlation 按定义为 NULL。

release month × genre 的 78 个单元中 13 个为空、26 个 N<5、29 个 N<10。
稀疏结构主要集中在未进入 main 的 genre。

## 10. Predictor-only design matrix

候选 paid/main 设计矩阵只使用 predictor：

- 836 行、17 列；
- rank 17；
- exact linear dependencies 0；
- condition number 10.804；
- reference：2025-07、Windows only、genre absent=0。

没有使用 response 做变量选择，也没有拟合 outcome model。当前结构不存在
精确秩缺失；condition number 不高，但不能替代 Step 5B 的正式 VIF/GVIF、
影响点和过度离散诊断。

## 11. Reception distribution and denominator concentration

model20_all pooled positive rate 为 88.168%，game-level median 为 87.650%；
model20_paid 分别为 88.239% 和 87.650%。这两个统计量含义不同：前者按
评论条数汇总，后者给予每个游戏相同位置权重，不能混用。

model20 分母分布：P5 21、P10 25、P25 38、中位数 90、P75 353、
P90 1,544.5、P95 4,047.1、P99 26,024.6、最大 136,842，标准差
7,374.20。高评论量游戏的二项信息权重将非常大。

总计 1,071,764 条 eligible reviews 中：

- top 1 游戏占 12.77%；
- top 5 占 38.23%；
- top 10 占 52.27%；
- top 20 占 63.31%；
- top 1%（9 个游戏）占 49.98%；
- top 5%（43 个游戏）占 77.24%；
- top 10%（85 个游戏）占 86.42%。

最大贡献者依次包括 Escape the Backrooms（136,842）、Megabonk（99,706）、
Escape From Duckov（83,387）、Deep Rock Galactic: Survivor（46,306）
和 Slime Rancher 2（43,483）。Step 5B 必须执行 influence、leverage、
Cook's D 类诊断及 overdispersion 检查。

## 12. Missingness and sample flow

model20_all 的 current/list price 与 discount 各缺失 8 行，全部对应免费
游戏；outcome、日期、月份、暴露天数和平台均无缺失。model20_paid 在所有
候选主字段上缺失为 0，因此 complete-case N=836，没有静默删行。

任何未来样本变化都必须在 sample flow 中记录理由和数量，不允许依赖模型
函数自动删除行。

## 13. Proposed formulas — do not fit

候选主公式：

```r
cbind(positive_reviews, negative_reviews) ~
  scale(log1p_current_price) +
  release_month +
  platform_segment +
  genre_action + genre_adventure + genre_casual + genre_indie +
  genre_rpg + genre_simulation + genre_strategy
```

预注册替代规格：

```r
# Alternative price scale
... ~ scale(current_price_usd) + release_month + platform_segment + main_genres

# Alternative exposure-time specification
... ~ scale(log1p_current_price) + scale(days_since_release) +
      platform_segment + main_genres

# Genre sensitivity
... ~ scale(log1p_current_price) + release_month + platform_segment +
      main_genres + genre_early_access + genre_sports + genre_racing
```

model20_all 仅作为 population sensitivity；在免费状态和结构性缺失价格的
编码方案经人工确认前，不提出会把免费价格伪装成普通数值 0 的公式。

## 14. Step 5B diagnostics required

- 二项 dispersion / overdispersion；
- predictor VIF/GVIF、condition diagnostics；
- leverage、Cook's D、DFBETAs 或等价影响诊断；
- 对 top review contributors 的剔除/降影响敏感性；
- model20_all、model20_paid、>=10、>=50 的阈值敏感性；
- raw price 与 log1p price；
- release_month 与 days_since_release 替代规格；
- main 与 sensitivity genre 集；
- 稀疏交叉单元和平台/genre 系数稳定性；
- 必要时再评估 quasibinomial 或 beta-binomial，但本阶段不拟合。

## 15. UNRESOLVED BEFORE STEP 5B

1. Primary population 最终选择 model20_all 还是 model20_paid？
2. 主价格项最终使用 raw 还是 log1p？
3. 使用 release_month 还是 days_since_release？
4. main genre 七项是否全部保留？
5. 三个 sensitivity genre 是否只进入敏感性规格？
6. 是否接受 paid-only 主分析对免费游戏外推范围的限制？
7. 评论集中度是否需要预先冻结 leave-top-N-out 影响敏感性？
8. model20_all 中免费状态与结构性缺失价格如何编码？

## 16. Recommendation

Step 5A 数据完整性与 predictor-only 设计矩阵均通过。建议提交人工 Review：
候选主分析使用 model20_paid、二项正负计数响应、log1p current price、
release_month、四个实际平台水平和七个高频 main genre；所有替代规格必须
在看到正式模型结果前冻结。

Future extension：零评论状态/评论关注度 hurdle analysis。本阶段不实现。
