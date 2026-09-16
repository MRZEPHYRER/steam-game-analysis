# Step 5E 次要高评分 Logistic 分析技术报告

## 分析层级与边界

Beta-binomial 仍是主要推断模型。Step 5E 是预先规定的、便于业务解释的游戏层级二元补充分析。 每款游戏仅贡献一个二元观测，因此评论数为 20 与评论数为 100,000 的游戏在该模型中具有相同的似然权重。

主结果 HIGH85 定义为 positive_reviews / total_reviews >= 0.85；HIGH80 与 HIGH90 仅用于固定阈值敏感性检查。未优化评分阈值，也未优化分类阈值。

## 样本与结局审计

冻结的付费游戏完整样本为 N = 836，AppID 唯一，且每款游戏 total_reviews >= 20。评论量既不是权重，也不是模型协变量。

- HIGH80：574/836（68.66%）；恰好位于阈值的游戏数 = 5
- HIGH85：471/836（56.34%）；恰好位于阈值的游戏数 = 1
- HIGH90：359/836（42.94%）；恰好位于阈值的游戏数 = 7

## HIGH85 主 Logistic 模型

模型收敛 = TRUE；事件/非事件 = 471/365；参数秩 = /；迭代次数 = 4。

logLik = -540.235，AIC = 1106.471，BIC = 1167.943，空模型/残差离差 = 1145.466/1080.471。

- `(Intercept)`：OR = 1.2861，Wald 95% CI [0.8794，1.8809]，方向 = POSITIVE
- `z_log1p_price`：OR = 0.8623，Wald 95% CI [0.7388，1.0064]，方向 = NEGATIVE
- `z_days_since_release`：OR = 1.0064，Wald 95% CI [0.8720，1.1615]，方向 = POSITIVE
- `platform_segmentWindows + macOS`：OR = 2.4619，Wald 95% CI [1.4363，4.2200]，方向 = POSITIVE
- `platform_segmentWindows + Linux`：OR = 3.0554，Wald 95% CI [1.4086，6.6277]，方向 = POSITIVE
- `platform_segmentWindows + macOS + Linux`：OR = 2.6292，Wald 95% CI [1.5199，4.5481]，方向 = POSITIVE
- `genre_action`：OR = 0.7236，Wald 95% CI [0.5291，0.9895]，方向 = NEGATIVE
- `genre_adventure`：OR = 0.8419，Wald 95% CI [0.6239，1.1361]，方向 = NEGATIVE
- `genre_casual`：OR = 1.2737，Wald 95% CI [0.9246，1.7545]，方向 = POSITIVE
- `genre_indie`：OR = 1.2530，Wald 95% CI [0.8916，1.7607]，方向 = POSITIVE
- `genre_rpg`：OR = 0.9743，Wald 95% CI [0.6979，1.3603]，方向 = NEGATIVE
- `genre_simulation`：OR = 0.6472，Wald 95% CI [0.4705，0.8903]，方向 = NEGATIVE
- `genre_strategy`：OR = 0.6076，Wald 95% CI [0.4204，0.8784]，方向 = NEGATIVE

## 模型概率对比

下列概率为在冻结参考构型上一次只改变一个变量得到的模型内对比， 属于条件关联的描述，不作因果解释。

- REFERENCE：参考概率 = 0.5626，情景概率 = 0.5626，变化 = 0.00 个百分点
- PRICE_PLUS_1SD：参考概率 = 0.5626，情景概率 = 0.5258，变化 = -3.67 个百分点
- DAYS_PLUS_1SD：参考概率 = 0.5626，情景概率 = 0.5641，变化 = 0.16 个百分点
- PLATFORM_WINDOWS_MACOS：参考概率 = 0.5626，情景概率 = 0.7600，变化 = 19.74 个百分点
- PLATFORM_WINDOWS_LINUX：参考概率 = 0.5626，情景概率 = 0.7971，变化 = 23.46 个百分点
- PLATFORM_ALL_THREE：参考概率 = 0.5626，情景概率 = 0.7718，变化 = 20.92 个百分点
- GENRE_ACTION：参考概率 = 0.5626，情景概率 = 0.4820，变化 = -8.05 个百分点
- GENRE_ADVENTURE：参考概率 = 0.5626，情景概率 = 0.5199，变化 = -4.27 个百分点
- GENRE_CASUAL：参考概率 = 0.5626，情景概率 = 0.6209，变化 = 5.84 个百分点
- GENRE_INDIE：参考概率 = 0.5626，情景概率 = 0.6171，变化 = 5.45 个百分点
- GENRE_RPG：参考概率 = 0.5626，情景概率 = 0.5562，变化 = -0.64 个百分点
- GENRE_SIMULATION：参考概率 = 0.5626，情景概率 = 0.4543，变化 = -10.83 个百分点
- GENRE_STRATEGY：参考概率 = 0.5626，情景概率 = 0.4387，变化 = -12.39 个百分点

## 分离、残差与影响诊断

分离启发式检查的标记总数 = 0；最大绝对标准化离差残差 = 2.1474；最大 leverage = 0.0484；最大 Cook's D = 0.0129。

|标准化残差| > 2 的游戏数 = 2，> 3 的游戏数 = 0；Cook's D > 0.5 或 > 1 的游戏数均为 0。

## 校准与区分度

样本内 ROC AUC = 0.6605（95% CI 0.6238 至 0.6973；DeLong placement-value normal approximation）。AUC 与校准均为次要、样本内的描述性诊断，不是模型选择目标。

## 评分阈值稳定性

描述性分类计数：ROBUST = 3，PARTIAL = 7，SENSITIVE = 2。分类依据方向一致性与相对 HIGH85 的最大 OR 漂移，不是统计检验。

不同阈值对应不同二元结局，因此不得用 HIGH80、HIGH85、HIGH90 之间的 AIC/BIC 来选择所谓最佳阈值。

## 与主要 Beta-binomial 模型的方向比较

共同系数方向一致数 = 11/12。由于结局定义与似然贡献不同，只比较方向与定性一致性，不直接比较 OR 大小。

## 结论限制

本分析估计的是在给定协变量后达到高评分阈值的条件关联。结果不支持因果陈述， 也不能替代主要 Beta-binomial 推断。阈值敏感性、样本内诊断和单个游戏影响均应与主模型共同阅读。
