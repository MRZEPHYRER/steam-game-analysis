# Step 5F figures 25-34.

if (!exists("rating_estimates_5f") || !exists("eb_prior_sensitivity_5f")) {
  stop("Run 15_empirical_bayes_rating.R before 16_rating_adjustment_visuals.R.", call. = FALSE)
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing R package: ggplot2", call. = FALSE)
}

font_5f <- if (.Platform$OS.type == "windows") "Microsoft YaHei" else "sans"
theme_5f <- ggplot2::theme_minimal(base_size = 12, base_family = font_5f) +
  ggplot2::theme(
    plot.title.position = "plot",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    axis.title = ggplot2::element_text(face = "bold")
  )
save_5f <- function(name, plot, width = 8.2, height = 6.2) {
  ggplot2::ggsave(
    file.path(model_figure_dir, name), plot,
    width = width, height = height, dpi = 180
  )
}

geometry_plot_data_5f <- wilson_examples_5f |>
  dplyr::mutate(
    denominator_label = factor(
      paste0(positive_reviews, "/", total_reviews),
      levels = unique(paste0(positive_reviews, "/", total_reviews))
    ),
    group_label = factor(
      example_group,
      levels = c("raw_100_percent", "raw_50_percent"),
      labels = c("Raw = 100%", "Raw = 50%")
    )
  )
p25 <- ggplot2::ggplot(
  geometry_plot_data_5f,
  ggplot2::aes(wilson_center, denominator_label)
) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = wilson_lower_95, xmax = wilson_upper_95),
    orientation = "y", width = 0.18, colour = "#6C757D"
  ) +
  ggplot2::geom_point(
    ggplot2::aes(x = raw_positive_rate), size = 2.7, colour = "#2C7FB8"
  ) +
  ggplot2::facet_wrap(~group_label, scales = "free_y") +
  ggplot2::scale_x_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  ggplot2::labs(
    title = "相同 Raw Rate，不同评论数的 Wilson 95% 区间",
    subtitle = "蓝点为观察比例；灰线为 Wilson score interval",
    x = "正面率", y = "正面评论 / 总评论",
    caption = "Wilson 描述抽样不确定性，不是收缩后的评分。"
  ) + theme_5f
save_5f("25_wilson_denominator_geometry.png", p25, 9.2, 6.8)

p26 <- ggplot2::ggplot(
  rating_estimates_5f,
  ggplot2::aes(total_reviews, raw_positive_rate)
) +
  ggplot2::geom_point(alpha = 0.28, size = 1.2, colour = "#2C7FB8") +
  ggplot2::scale_x_log10(labels = scales::label_number(big.mark = ",")) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Raw Positive Rate 与评论数量",
    subtitle = "低评论数区域出现明显离散带与 0%/100% 极端值",
    x = "总评论数（log10）", y = "Raw positive rate",
    caption = "N = 2,241；free 与 paid games 均保留。"
  ) + theme_5f
save_5f("26_raw_rate_vs_review_count.png", p26)

p27 <- ggplot2::ggplot(
  rating_estimates_5f,
  ggplot2::aes(total_reviews, wilson_width)
) +
  ggplot2::geom_point(alpha = 0.28, size = 1.2, colour = "#2C7FB8") +
  ggplot2::scale_x_log10(labels = scales::label_number(big.mark = ",")) +
  ggplot2::scale_y_continuous(labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Wilson 区间宽度随评论数收窄",
    subtitle = "相同样本量下宽度仍随观察比例略有变化",
    x = "总评论数（log10）", y = "Wilson 95% 区间宽度",
    caption = "区间宽度衡量不确定性，不改变 Raw point estimate。"
  ) + theme_5f
save_5f("27_wilson_width_vs_review_count.png", p27)

p28 <- ggplot2::ggplot(
  rating_estimates_5f,
  ggplot2::aes(raw_positive_rate, eb_posterior_mean, alpha = log10(total_reviews + 1))
) +
  ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed", colour = "grey45") +
  ggplot2::geom_point(size = 1.4, colour = "#2C7FB8") +
  ggplot2::scale_alpha_continuous(range = c(0.18, 0.75), guide = "none") +
  ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  ggplot2::scale_x_continuous(labels = scales::percent_format()) +
  ggplot2::scale_y_continuous(labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Raw Rating 与 Empirical Bayes Posterior Mean",
    subtitle = "偏离 45° 线表示向总体 prior mean 收缩",
    x = "Raw positive rate", y = "EB posterior mean",
    caption = "高评论数游戏通常更靠近 45° 线。"
  ) + theme_5f
save_5f("28_raw_vs_eb_rating.png", p28, 7.4, 6.6)

p29 <- ggplot2::ggplot(
  rating_estimates_5f,
  ggplot2::aes(total_reviews, eb_shrinkage_pp)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45") +
  ggplot2::geom_point(alpha = 0.30, size = 1.2, colour = "#2C7FB8") +
  ggplot2::scale_x_log10(labels = scales::label_number(big.mark = ",")) +
  ggplot2::labs(
    title = "EB 收缩幅度与评论数量",
    subtitle = "正值为上调，负值为下调",
    x = "总评论数（log10）", y = "EB - Raw（百分点）",
    caption = "低 n 极端值收缩最明显；方向由 Raw rate 相对 prior mean 决定。"
  ) + theme_5f
save_5f("29_eb_shrinkage_vs_review_count.png", p29)

distribution_plot_data_5f <- rating_estimates_5f |>
  dplyr::select(raw_positive_rate, eb_posterior_mean) |>
  tidyr::pivot_longer(dplyr::everything(), names_to = "metric", values_to = "rating") |>
  dplyr::mutate(metric = factor(
    metric,
    levels = c("raw_positive_rate", "eb_posterior_mean"),
    labels = c("Raw positive rate", "EB posterior mean")
  ))
p30 <- ggplot2::ggplot(distribution_plot_data_5f, ggplot2::aes(rating)) +
  ggplot2::geom_histogram(binwidth = 0.025, boundary = 0, colour = "white", fill = "#2C7FB8") +
  ggplot2::facet_wrap(~metric, ncol = 1, scales = "free_y") +
  ggplot2::scale_x_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Raw 与 EB Rating 分布",
    subtitle = "固定 2.5 个百分点直方箱，不用平滑密度隐藏极端值",
    x = "游戏正面率", y = "游戏数",
    caption = "EB 收缩减少了由低 n 产生的 0%/100% 堆积。"
  ) + theme_5f
save_5f("30_raw_vs_eb_distribution.png", p30, 8.4, 8.0)

rank_plot_data_5f <- rating_estimates_5f |>
  dplyr::filter(raw_rank <= 50) |>
  dplyr::select(appid, raw_rank, Wilson = wilson_rank, `Empirical Bayes` = eb_rank) |>
  tidyr::pivot_longer(c(Wilson, `Empirical Bayes`), names_to = "adjustment", values_to = "adjusted_rank")
p31 <- ggplot2::ggplot(rank_plot_data_5f, ggplot2::aes(raw_rank, adjusted_rank, colour = adjustment)) +
  ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed", colour = "grey45") +
  ggplot2::geom_point(alpha = 0.8, size = 2.1) +
  ggplot2::scale_colour_manual(values = c("Wilson" = "#D9901A", "Empirical Bayes" = "#2C7FB8")) +
  ggplot2::labs(
    title = "Raw Top 50 在 Wilson / EB 排名中的位置",
    subtitle = "Raw ties 以评论数降序、AppID 升序作确定性 tie-break",
    x = "Raw rank", y = "调整方法中的 rank", colour = "方法",
    caption = "排名移动受 Raw 100% ties 影响，需结合评分与评论数解释。"
  ) + theme_5f
save_5f("31_raw_wilson_eb_rank_comparison.png", p31)

prior_sensitivity_plot_5f <- all_posterior_sensitivity_5f |>
  dplyr::filter(total_reviews < 20) |>
  dplyr::transmute(
    total_reviews,
    `Prior n>=10 - Primary` = 100 * (eb_prior10 - eb_all),
    `Prior n>=20 - Primary` = 100 * (eb_prior20 - eb_all)
  ) |>
  tidyr::pivot_longer(-total_reviews, names_to = "comparison", values_to = "difference_pp")
p32 <- ggplot2::ggplot(
  prior_sensitivity_plot_5f,
  ggplot2::aes(total_reviews, difference_pp, colour = comparison)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45") +
  ggplot2::geom_jitter(width = 0.12, height = 0, alpha = 0.35, size = 1.2) +
  ggplot2::scale_colour_manual(values = c("Prior n>=10 - Primary" = "#D9901A", "Prior n>=20 - Primary" = "#2C7FB8")) +
  ggplot2::labs(
    title = "低评论数游戏的 EB Prior 敏感性",
    subtitle = "同一 n>0 评价总体；只改变 prior 的估计样本",
    x = "总评论数（n < 20）", y = "相对 Primary EB 的差异（百分点）", colour = NULL,
    caption = "Primary prior 使用全部 n>0 游戏；替代 prior 仅作敏感性审计。"
  ) + theme_5f
save_5f("32_eb_prior_sensitivity.png", p32, 9.2, 6.4)

top_eb_plot_data_5f <- top_eb_games_5f |>
  dplyr::mutate(
    display_name = paste0(substr(name, 1, 30), "  raw=", sprintf("%.1f%%", 100 * raw_positive_rate), ", n=", total_reviews),
    display_name = stats::reorder(display_name, eb_posterior_mean)
  )
p33 <- ggplot2::ggplot(top_eb_plot_data_5f, ggplot2::aes(eb_posterior_mean, display_name)) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = eb_ci95_lower, xmax = eb_ci95_upper),
    orientation = "y", width = 0.16, colour = "#6C757D"
  ) +
  ggplot2::geom_point(size = 2.5, colour = "#2C7FB8") +
  ggplot2::scale_x_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  ggplot2::labs(
    title = "EB Posterior Mean 排名前 20 的游戏",
    subtitle = "点为 posterior mean；线为 95% equal-tailed credible interval",
    x = "EB posterior rating", y = NULL,
    caption = "EB ranking 是 population-informed estimate，不是真实质量排名。"
  ) + theme_5f
save_5f("33_top_adjusted_games.png", p33, 11.5, 8.2)

top_shrink_plot_data_5f <- top_shrinkage_5f |>
  dplyr::slice_head(n = 20) |>
  dplyr::mutate(
    display_name = paste0(substr(name, 1, 30), " (n=", total_reviews, ")"),
    display_name = stats::reorder(display_name, absolute_shrinkage)
  )
p34 <- ggplot2::ggplot(top_shrink_plot_data_5f, ggplot2::aes(y = display_name)) +
  ggplot2::geom_segment(
    ggplot2::aes(x = raw_positive_rate, xend = eb_posterior_mean, yend = display_name),
    linewidth = 1, colour = "#6C757D"
  ) +
  ggplot2::geom_point(ggplot2::aes(x = raw_positive_rate, colour = "Raw"), size = 2.7) +
  ggplot2::geom_point(ggplot2::aes(x = eb_posterior_mean, colour = "EB"), size = 2.7) +
  ggplot2::scale_colour_manual(values = c("Raw" = "#D9901A", "EB" = "#2C7FB8")) +
  ggplot2::scale_x_continuous(labels = scales::percent_format()) +
  ggplot2::labs(
    title = "绝对收缩最大的 20 个游戏",
    subtitle = "线段连接 Raw rate 与 EB posterior mean",
    x = "正面率", y = NULL, colour = "指标",
    caption = "大幅收缩主要来自低评论数的极端观察比例。"
  ) + theme_5f
save_5f("34_most_shrunk_games.png", p34, 11.2, 8.2)

message("Step 5F figures: PASS (25-34 generated)")
