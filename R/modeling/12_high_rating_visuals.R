# Generate Step 5E figures from the fitted models and frozen audit outputs.

if (!exists("auc_5e")) {
  stop("Run 11_high_rating_diagnostics.R before 12_high_rating_visuals.R.", call. = FALSE)
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing R package: ggplot2", call. = FALSE)
}

high_rating_term_labels <- c(
  "z_log1p_price" = "当前价格（log1p，+1 SD）",
  "z_days_since_release" = "上市至快照天数（+1 SD）",
  "platform_segmentWindows + macOS" = "Windows + macOS",
  "platform_segmentWindows + Linux" = "Windows + Linux",
  "platform_segmentWindows + macOS + Linux" = "三平台支持",
  "genre_action" = "Action",
  "genre_adventure" = "Adventure",
  "genre_casual" = "Casual",
  "genre_indie" = "Indie",
  "genre_rpg" = "RPG",
  "genre_simulation" = "Simulation",
  "genre_strategy" = "Strategy"
)
high_rating_term_order <- rev(names(high_rating_term_labels))
high_rating_font <- if (.Platform$OS.type == "windows") "Microsoft YaHei" else "sans"
plot_theme_5e <- ggplot2::theme_minimal(base_size = 12, base_family = high_rating_font) +
  ggplot2::theme(
    plot.title.position = "plot",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    axis.title = ggplot2::element_text(face = "bold")
  )

calibration_plot_5e <- ggplot2::ggplot(
  calibration_deciles_5e,
  ggplot2::aes(mean_predicted_probability, observed_high_rating_proportion)
) +
  ggplot2::geom_abline(
    intercept = 0, slope = 1, linewidth = 0.7, colour = "grey45",
    linetype = "dashed"
  ) +
  ggplot2::geom_line(linewidth = 0.8, colour = "#2C7FB8") +
  ggplot2::geom_point(size = 2.8, colour = "#2C7FB8") +
  ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  ggplot2::labs(
    title = "HIGH85 主模型的样本内校准",
    subtitle = "按预测概率十分位汇总；虚线为理想 45° 参考线",
    x = "平均预测概率",
    y = "观察到的高评分比例",
    caption = "描述性样本内校准，不是外部验证。"
  ) +
  plot_theme_5e
ggplot2::ggsave(
  file.path(model_figure_dir, "19_high_rating_calibration.png"),
  calibration_plot_5e, width = 7.2, height = 6.0, dpi = 180
)

roc_plot_5e <- ggplot2::ggplot(
  roc_points_5e,
  ggplot2::aes(false_positive_rate, true_positive_rate)
) +
  ggplot2::geom_abline(
    intercept = 0, slope = 1, linewidth = 0.7, colour = "grey45",
    linetype = "dashed"
  ) +
  ggplot2::geom_path(linewidth = 1, colour = "#2C7FB8") +
  ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  ggplot2::labs(
    title = sprintf("HIGH85 主模型 ROC（AUC = %.3f）", auc_5e$auc),
    subtitle = "仅作样本内描述性区分能力诊断，不优化分类阈值",
    x = "假阳性率",
    y = "真阳性率",
    caption = "研究目标是解释条件关联，而不是训练部署型分类器。"
  ) +
  plot_theme_5e
ggplot2::ggsave(
  file.path(model_figure_dir, "20_high_rating_roc.png"),
  roc_plot_5e, width = 7.2, height = 6.0, dpi = 180
)

primary_or_plot_data <- primary_high_rating_coefficients |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::mutate(
    predictor = factor(
      high_rating_term_labels[term], levels = high_rating_term_labels[high_rating_term_order]
    )
  )
primary_or_plot_5e <- ggplot2::ggplot(
  primary_or_plot_data,
  ggplot2::aes(odds_ratio, predictor)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey45", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    width = 0.18, orientation = "y", colour = "#6C757D"
  ) +
  ggplot2::geom_point(size = 2.8, colour = "#2C7FB8") +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "HIGH85 主 Logistic 模型 OR 与 95% 置信区间",
    subtitle = "付费游戏、评论数不少于 20；每个游戏权重相同",
    x = "比值比（OR，对数刻度）",
    y = NULL,
    caption = "方向与幅度均为条件关联，不作因果解释。"
  ) +
  plot_theme_5e
ggplot2::ggsave(
  file.path(model_figure_dir, "21_high_rating_primary_or.png"),
  primary_or_plot_5e, width = 9.5, height = 7.2, dpi = 180
)

threshold_or_plot_data <- rating_threshold_coefficients |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::mutate(
    predictor = factor(
      high_rating_term_labels[term], levels = high_rating_term_labels[high_rating_term_order]
    ),
    rating_cutoff = factor(
      model_id,
      levels = c("HIGH80", "HIGH85", "HIGH90"),
      labels = c("80%", "85%（主模型）", "90%")
    )
  )
threshold_or_plot_5e <- ggplot2::ggplot(
  threshold_or_plot_data,
  ggplot2::aes(odds_ratio, predictor, colour = rating_cutoff)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey45", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    width = 0.18,
    orientation = "y",
    position = ggplot2::position_dodge(width = 0.55)
  ) +
  ggplot2::geom_point(
    size = 2.4, position = ggplot2::position_dodge(width = 0.55)
  ) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#6C757D", "#2C7FB8", "#D9901A")) +
  ggplot2::labs(
    title = "80% / 85% / 90% 高评分阈值下的 OR 对比",
    subtitle = "样本、预测变量、缩放与 reference level 完全相同",
    x = "比值比（OR，对数刻度）",
    y = NULL,
    colour = "高评分阈值",
    caption = "仅改变二元 outcome；阈值为预先指定，不按结果优化。"
  ) +
  plot_theme_5e
ggplot2::ggsave(
  file.path(model_figure_dir, "22_rating_threshold_or_comparison.png"),
  threshold_or_plot_5e, width = 10.5, height = 7.5, dpi = 180
)

drift_terms_5e <- c(
  "z_log1p_price",
  "platform_segmentWindows + macOS",
  "platform_segmentWindows + Linux",
  "platform_segmentWindows + macOS + Linux",
  "genre_indie", "genre_rpg", "genre_simulation", "genre_strategy"
)
drift_plot_data_5e <- rating_threshold_coefficients |>
  dplyr::filter(term %in% drift_terms_5e) |>
  dplyr::mutate(
    predictor = factor(
      high_rating_term_labels[term],
      levels = high_rating_term_labels[drift_terms_5e]
    ),
    cutoff_percent = rating_threshold * 100
  )
drift_plot_5e <- ggplot2::ggplot(
  drift_plot_data_5e,
  ggplot2::aes(cutoff_percent, odds_ratio, group = predictor)
) +
  ggplot2::geom_hline(yintercept = 1, colour = "grey45") +
  ggplot2::geom_line(linewidth = 0.8, colour = "#6C757D") +
  ggplot2::geom_point(size = 2.5, colour = "#2C7FB8") +
  ggplot2::facet_wrap(~ predictor, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = c(80, 85, 90), labels = c("80%", "85%", "90%")) +
  ggplot2::labs(
    title = "核心预测变量随高评分阈值变化的 OR 漂移",
    subtitle = "每个面板独立纵轴；水平参考线为 OR = 1",
    x = "高评分 cutoff",
    y = "比值比（OR）",
    caption = "漂移分类是描述性审计，不是统计检验。"
  ) +
  plot_theme_5e +
  ggplot2::theme(legend.position = "none")
ggplot2::ggsave(
  file.path(model_figure_dir, "23_rating_threshold_drift.png"),
  drift_plot_5e, width = 9.5, height = 9.0, dpi = 180
)

direction_plot_data_5e <- beta_logistic_direction_comparison |>
  dplyr::select(
    term, beta_binomial_direction, high85_logistic_direction,
    direction_agreement
  ) |>
  tidyr::pivot_longer(
    cols = c(beta_binomial_direction, high85_logistic_direction),
    names_to = "model",
    values_to = "direction"
  ) |>
  dplyr::mutate(
    predictor = factor(
      high_rating_term_labels[term],
      levels = high_rating_term_labels[high_rating_term_order]
    ),
    model = factor(
      model,
      levels = c("beta_binomial_direction", "high85_logistic_direction"),
      labels = c("Beta-binomial 主模型", "HIGH85 Logistic")
    ),
    direction_label = ifelse(direction == "POSITIVE", "↑ 正向", "↓ 负向")
  )
direction_plot_5e <- ggplot2::ggplot(
  direction_plot_data_5e,
  ggplot2::aes(model, predictor, fill = direction)
) +
  ggplot2::geom_tile(colour = "white", linewidth = 1) +
  ggplot2::geom_text(ggplot2::aes(label = direction_label), colour = "white") +
  ggplot2::scale_fill_manual(
    values = c("NEGATIVE" = "#C75B4B", "POSITIVE" = "#2C7FB8")
  ) +
  ggplot2::labs(
    title = "Beta-binomial 与 HIGH85 Logistic 的方向一致性",
    subtitle = "颜色与箭头仅表示 log(OR) 方向，不比较 OR 数值大小",
    x = NULL,
    y = NULL,
    fill = "方向",
    caption = "两种模型 outcome 不同；这里只审计方向和定性一致性。"
  ) +
  plot_theme_5e +
  ggplot2::theme(legend.position = "none")
ggplot2::ggsave(
  file.path(model_figure_dir, "24_beta_vs_high_rating_direction.png"),
  direction_plot_5e, width = 8.0, height = 7.5, dpi = 180
)

message("Step 5E figures: PASS (19-24 generated)")
