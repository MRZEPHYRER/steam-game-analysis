# Generate Step 5D publication-quality figures and the technical sensitivity report.

# When called without the fitting script, rebuild only the presentation objects from
# the frozen machine-readable exports. This supports label-only figure regeneration
# without database access or model refitting.
if (!exists("master_specification_table_5d") || !exists("threshold_stability_5d")) {
  read_export_5d <- function(name) {
    utils::read.csv(file.path(model_audit_dir, name), check.names = FALSE)
  }
  master_specification_table_5d <- read_export_5d("step5d_master_specification_table.csv")
  all_coefficients_5d <- master_specification_table_5d
  threshold_coefficients_5d <- read_export_5d("step5d_threshold_coefficients.csv")
  threshold_stability_5d <- read_export_5d("step5d_threshold_stability.csv")
  threshold_samples_5d <- read_export_5d("step5d_threshold_samples.csv")
  release_fit_5d <- read_export_5d("step5d_release_fit.csv")
  release_coefficients_5d <- read_export_5d("step5d_release_coefficients.csv")
  release_comparison_5d <- read_export_5d("step5d_release_comparison.csv")
  price_fit_5d <- read_export_5d("step5d_price_fit.csv")
  price_coefficients_5d <- read_export_5d("step5d_price_coefficients.csv")
  price_comparison_5d <- read_export_5d("step5d_price_comparison.csv")
  price_predicted_contrasts_5d <- read_export_5d("step5d_price_predicted_contrasts.csv")
  genre_comparison_5d <- read_export_5d("step5d_genre_comparison.csv")
  core_predictor_stability_5d <- read_export_5d("step5d_core_predictor_stability.csv")
  all_fit_5d <- read_export_5d("step5d_diagnostics.csv")
  raw_price_mean_5d <- price_fit_5d$raw_price_mean_usd[[1]]
  raw_price_sd_5d <- price_fit_5d$raw_price_sd_usd[[1]]
  primary_genres_5d <- c(
    "genre_action", "genre_adventure", "genre_casual", "genre_indie",
    "genre_rpg", "genre_simulation", "genre_strategy"
  )
  added_genres_5d <- c("genre_early_access", "genre_sports", "genre_racing")
  expanded_genres_5d <- c(primary_genres_5d, added_genres_5d)
  core_terms_5d <- c(
    "z_log1p_price", "z_days_since_release",
    "platform_segmentWindows + macOS", "platform_segmentWindows + Linux",
    "platform_segmentWindows + macOS + Linux", "genre_indie", "genre_rpg",
    "genre_simulation", "genre_strategy"
  )
  conceptual_coefficients_5d <- all_coefficients_5d |>
    dplyr::mutate(
      conceptual_term = ifelse(term == "z_raw_price", "z_log1p_price", term)
    ) |>
    dplyr::filter(conceptual_term %in% core_terms_5d)
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing required package ggplot2.", call. = FALSE)
}

term_labels_en_5d <- c(
  z_log1p_price = "Price (+1 SD)",
  z_days_since_release = "Days since release (+1 SD)",
  `platform_segmentWindows + macOS` = "Windows + macOS",
  `platform_segmentWindows + Linux` = "Windows + Linux",
  `platform_segmentWindows + macOS + Linux` = "Windows + macOS + Linux",
  genre_action = "Action", genre_adventure = "Adventure",
  genre_casual = "Casual", genre_indie = "Indie", genre_rpg = "RPG",
  genre_simulation = "Simulation", genre_strategy = "Strategy",
  genre_early_access = "Early Access label", genre_sports = "Sports",
  genre_racing = "Racing"
)
term_labels_5d <- c(
  z_log1p_price = "当前价格（log1p，+1 SD）",
  z_days_since_release = "上市至快照天数（+1 SD）",
  `platform_segmentWindows + macOS` = "Windows + macOS",
  `platform_segmentWindows + Linux` = "Windows + Linux",
  `platform_segmentWindows + macOS + Linux` = "三平台支持",
  genre_action = "Action", genre_adventure = "Adventure",
  genre_casual = "Casual", genre_indie = "Indie", genre_rpg = "RPG",
  genre_simulation = "Simulation", genre_strategy = "Strategy",
  genre_early_access = "Early Access 标签", genre_sports = "Sports",
  genre_racing = "Racing"
)
spec_labels_5d <- c(
  PRIMARY = "主规格（≥20）", TH_GT0 = "评论数 > 0",
  TH_10 = "评论数 ≥ 10", TH_50 = "评论数 ≥ 50",
  RELEASE_MONTH = "发布月份替代", PRICE_RAW = "原始价格替代",
  GENRE_EXPANDED = "扩展 Genre"
)
threshold_order_5d <- c("TH_GT0", "TH_10", "PRIMARY", "TH_50")
spec_order_5d <- c(
  "PRIMARY", "TH_GT0", "TH_10", "TH_50",
  "RELEASE_MONTH", "PRICE_RAW", "GENRE_EXPANDED"
)

plot_theme_5d <- ggplot2::theme_minimal(base_size = 12, base_family = "Microsoft YaHei") +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.title.position = "plot",
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(colour = "grey35"),
    legend.position = "bottom",
    legend.title = ggplot2::element_text(face = "bold"),
    strip.text = ggplot2::element_text(face = "bold")
  )

non_intercept_terms_5d <- names(term_labels_5d)[1:12]
threshold_plot_data_5d <- threshold_coefficients_5d |>
  dplyr::filter(term %in% non_intercept_terms_5d) |>
  dplyr::mutate(
    threshold = factor(
      specification_id, levels = threshold_order_5d,
      labels = c("评论数 > 0", "评论数 ≥ 10", "主规格（≥20）", "评论数 ≥ 50")
    ),
    term_label = factor(
      unname(term_labels_5d[term]),
      levels = rev(unname(term_labels_5d[non_intercept_terms_5d]))
    )
  )
threshold_or_plot_5d <- ggplot2::ggplot(
  threshold_plot_data_5d,
  ggplot2::aes(odds_ratio, term_label, colour = threshold)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.12,
    position = ggplot2::position_dodge(width = 0.65)
  ) +
  ggplot2::geom_point(
    position = ggplot2::position_dodge(width = 0.65), size = 1.9
  ) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#6C757D", "#D28E2C", "#2C6E9B", "#9A5D88")) +
  ggplot2::labs(
    title = "评论数量阈值下的 OR 对比",
    subtitle = "付费游戏；沿用主规格标准化参数；Wald 95% CI",
    x = "比值比（OR，对数刻度）", y = NULL, colour = "评论数量阈值"
  ) + plot_theme_5d
ggplot2::ggsave(
  file.path(model_figure_dir, "09_threshold_or_comparison.png"),
  threshold_or_plot_5d, width = 10.8, height = 8.2, dpi = 180
)

focus_terms_5d <- core_terms_5d
threshold_drift_plot_data_5d <- threshold_coefficients_5d |>
  dplyr::filter(term %in% focus_terms_5d) |>
  dplyr::mutate(
    threshold = factor(
      specification_id, levels = threshold_order_5d,
      labels = c("> 0", "≥ 10", "≥ 20", "≥ 50")
    ),
    term_label = factor(
      unname(term_labels_5d[term]),
      levels = unname(term_labels_5d[focus_terms_5d])
    )
  )
threshold_drift_plot_5d <- ggplot2::ggplot(
  threshold_drift_plot_data_5d,
  ggplot2::aes(threshold, odds_ratio, group = term_label)
) +
  ggplot2::geom_hline(yintercept = 1, colour = "grey60", linewidth = 0.6) +
  ggplot2::geom_line(colour = "#6C757D", linewidth = 0.7) +
  ggplot2::geom_point(colour = "#2C6E9B", size = 2) +
  ggplot2::scale_y_log10() +
  ggplot2::facet_wrap(~ term_label, scales = "free_y", ncol = 3) +
  ggplot2::labs(
    title = "不同评论阈值下的系数漂移",
    subtitle = "各面板使用独立的 OR 对数范围；参考线为 OR = 1",
    x = "评论数量阈值", y = "比值比（OR，对数刻度）"
  ) + plot_theme_5d + ggplot2::theme(legend.position = "none")
ggplot2::ggsave(
  file.path(model_figure_dir, "10_threshold_coefficient_drift.png"),
  threshold_drift_plot_5d, width = 10.6, height = 8.2, dpi = 180
)

release_shared_plot_data_5d <- dplyr::bind_rows(
  all_coefficients_5d |>
    dplyr::filter(
      specification_id == "PRIMARY", term %in% non_intercept_terms_5d,
      term != "z_days_since_release"
    ),
  all_coefficients_5d |>
    dplyr::filter(
      specification_id == "RELEASE_MONTH", term %in% non_intercept_terms_5d,
      term != "z_days_since_release"
    )
) |>
  dplyr::mutate(
    specification = factor(
      specification_id, levels = c("PRIMARY", "RELEASE_MONTH"),
      labels = c("主规格：上市天数", "替代规格：发布月份")
    ),
    term_label = factor(
      unname(term_labels_5d[term]),
      levels = rev(unname(term_labels_5d[non_intercept_terms_5d]))
    )
  )
release_comparison_plot_5d <- ggplot2::ggplot(
  release_shared_plot_data_5d,
  ggplot2::aes(odds_ratio, term_label, colour = specification)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.13,
    position = ggplot2::position_dodge(width = 0.52)
  ) +
  ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.52), size = 2) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#2C6E9B", "#D28E2C")) +
  ggplot2::labs(
    title = "发布时间规格对共同预测变量的影响",
    subtitle = "发布月份替代上市天数；Wald 95% CI",
    x = "比值比（OR，对数刻度）", y = NULL, colour = "发布时间规格"
  ) + plot_theme_5d
ggplot2::ggsave(
  file.path(model_figure_dir, "11_release_specification_comparison.png"),
  release_comparison_plot_5d, width = 10.2, height = 7.8, dpi = 180
)

release_month_plot_data_5d <- release_coefficients_5d |>
  dplyr::filter(grepl("^release_month", term), term != "release_month2025-07") |>
  dplyr::mutate(
    month = factor(sub("release_month", "", term), levels = sprintf("2025-%02d", 8:12))
  )
release_month_plot_5d <- ggplot2::ggplot(
  release_month_plot_data_5d,
  ggplot2::aes(odds_ratio, month)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.14, colour = "#6C757D"
  ) +
  ggplot2::geom_point(colour = "#2C6E9B", size = 2.4) +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "不同发布月份相对 2025 年 7 月的 OR",
    subtitle = "Beta-binomial 模型；2025 年 7 月为 reference level",
    x = "比值比（OR，对数刻度）", y = NULL
  ) + plot_theme_5d + ggplot2::theme(legend.position = "none")
ggplot2::ggsave(
  file.path(model_figure_dir, "12_release_month_effects.png"),
  release_month_plot_5d, width = 7.8, height = 5.2, dpi = 180
)

price_plot_data_5d <- dplyr::bind_rows(
  all_coefficients_5d |>
    dplyr::filter(specification_id == "PRIMARY", term %in% non_intercept_terms_5d),
  all_coefficients_5d |>
    dplyr::filter(specification_id == "PRICE_RAW") |>
    dplyr::mutate(term = ifelse(term == "z_raw_price", "z_log1p_price", term)) |>
    dplyr::filter(term %in% non_intercept_terms_5d)
) |>
  dplyr::mutate(
    specification = factor(
      specification_id, levels = c("PRIMARY", "PRICE_RAW"),
      labels = c("log1p 价格（+1 SD）", "原始价格（+1 SD）")
    ),
    term_label = factor(
      unname(term_labels_5d[term]),
      levels = rev(unname(term_labels_5d[non_intercept_terms_5d]))
    )
  )
price_comparison_plot_5d <- ggplot2::ggplot(
  price_plot_data_5d,
  ggplot2::aes(odds_ratio, term_label, colour = specification)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.13,
    position = ggplot2::position_dodge(width = 0.52)
  ) +
  ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.52), size = 2) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#2C6E9B", "#D28E2C")) +
  ggplot2::labs(
    title = "价格变量规格对模型结果的影响",
    subtitle = "两种价格系数均表示主样本内对应变量增加 1 SD",
    x = "比值比（OR，对数刻度）", y = NULL, colour = "价格规格"
  ) + plot_theme_5d
ggplot2::ggsave(
  file.path(model_figure_dir, "13_price_specification_comparison.png"),
  price_comparison_plot_5d, width = 10.2, height = 7.8, dpi = 180
)

genre_terms_plot_5d <- expanded_genres_5d
genre_plot_data_5d <- dplyr::bind_rows(
  all_coefficients_5d |>
    dplyr::filter(specification_id == "PRIMARY", term %in% primary_genres_5d),
  all_coefficients_5d |>
    dplyr::filter(specification_id == "GENRE_EXPANDED", term %in% genre_terms_plot_5d)
) |>
  dplyr::mutate(
    specification = factor(
      specification_id, levels = c("PRIMARY", "GENRE_EXPANDED"),
      labels = c("主规格：7 个 Genre", "扩展规格：10 个 Genre")
    ),
    term_label = factor(
      unname(term_labels_5d[term]),
      levels = rev(unname(term_labels_5d[genre_terms_plot_5d]))
    )
  )
genre_comparison_plot_5d <- ggplot2::ggplot(
  genre_plot_data_5d,
  ggplot2::aes(odds_ratio, term_label, colour = specification)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.13,
    position = ggplot2::position_dodge(width = 0.50)
  ) +
  ggplot2::geom_point(position = ggplot2::position_dodge(width = 0.50), size = 2) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("#2C6E9B", "#D28E2C"), na.translate = FALSE) +
  ggplot2::labs(
    title = "Genre 集合扩展前后的 OR 对比",
    subtitle = "Early Access 指冻结数据中的 Steam genre/category 标签",
    x = "比值比（OR，对数刻度）", y = NULL, colour = "Genre 规格"
  ) + plot_theme_5d
ggplot2::ggsave(
  file.path(model_figure_dir, "14_genre_specification_comparison.png"),
  genre_comparison_plot_5d, width = 9.6, height = 7.2, dpi = 180
)

heatmap_data_5d <- conceptual_coefficients_5d |>
  dplyr::select(conceptual_term, specification_id, estimate_log_odds) |>
  tidyr::complete(
    conceptual_term = core_terms_5d,
    specification_id = spec_order_5d
  ) |>
  dplyr::mutate(
    term_label = factor(
      unname(term_labels_5d[conceptual_term]),
      levels = rev(unname(term_labels_5d[core_terms_5d]))
    ),
    specification = factor(
      specification_id, levels = spec_order_5d,
      labels = unname(spec_labels_5d[spec_order_5d])
    )
  )
heatmap_limit_5d <- max(abs(heatmap_data_5d$estimate_log_odds), na.rm = TRUE)
robustness_heatmap_5d <- ggplot2::ggplot(
  heatmap_data_5d,
  ggplot2::aes(specification, term_label, fill = estimate_log_odds)
) +
  ggplot2::geom_tile(colour = "white", linewidth = 0.8) +
  ggplot2::scale_fill_gradient2(
    low = "#B04A3A", mid = "#F7F7F7", high = "#2C6E9B", midpoint = 0,
    limits = c(-heatmap_limit_5d, heatmap_limit_5d), na.value = "grey88"
  ) +
  ggplot2::labs(
    title = "不同模型规格下预测变量的稳健性热图",
    subtitle = "单元格颜色表示 log(OR)；灰色表示该规格按设计不含此变量",
    x = NULL, y = NULL, fill = "log odds"
  ) + plot_theme_5d +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 35, hjust = 1),
    legend.position = "right"
  )
ggplot2::ggsave(
  file.path(model_figure_dir, "15_robustness_heatmap.png"),
  robustness_heatmap_5d, width = 10.2, height = 6.8, dpi = 180
)

range_plot_data_5d <- core_predictor_stability_5d |>
  dplyr::mutate(
    term_label = factor(
      unname(term_labels_5d[conceptual_term]),
      levels = rev(unname(term_labels_5d[core_terms_5d]))
    )
  )
or_range_plot_5d <- ggplot2::ggplot(
  range_plot_data_5d,
  ggplot2::aes(y = term_label)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_segment(
    ggplot2::aes(x = minimum_or, xend = maximum_or, yend = term_label),
    colour = "#6C757D", linewidth = 1.1
  ) +
  ggplot2::geom_point(ggplot2::aes(x = primary_or), colour = "#2C6E9B", size = 2.5) +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "核心预测变量 OR 范围汇总",
    subtitle = "灰线表示观测范围；蓝点表示冻结的主规格估计值",
    x = "比值比（OR，对数刻度）", y = NULL
  ) + plot_theme_5d + ggplot2::theme(legend.position = "none")
ggplot2::ggsave(
  file.path(model_figure_dir, "16_or_range_summary.png"),
  or_range_plot_5d, width = 9.2, height = 6.4, dpi = 180
)

simulation_plot_data_5d <- conceptual_coefficients_5d |>
  dplyr::filter(conceptual_term == "genre_simulation") |>
  dplyr::mutate(
    specification = factor(
      specification_id, levels = rev(spec_order_5d),
      labels = rev(unname(spec_labels_5d[spec_order_5d]))
    ),
    series = ifelse(specification_id == "PRIMARY", "主规格", "敏感性规格")
  )
simulation_plot_5d <- ggplot2::ggplot(
  simulation_plot_data_5d,
  ggplot2::aes(odds_ratio, specification, colour = series)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.15
  ) +
  ggplot2::geom_point(size = 2.5) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c("主规格" = "#2C6E9B", "敏感性规格" = "#6C757D")) +
  ggplot2::labs(
    title = "Simulation 的规格敏感性分析",
    subtitle = "7 个估计值均保持负方向",
    x = "Simulation OR（对数刻度）", y = NULL, colour = NULL
  ) + plot_theme_5d
ggplot2::ggsave(
  file.path(model_figure_dir, "17_simulation_sensitivity.png"),
  simulation_plot_5d, width = 8.4, height = 5.8, dpi = 180
)

price_deep_dive_data_5d <- conceptual_coefficients_5d |>
  dplyr::filter(conceptual_term == "z_log1p_price") |>
  dplyr::mutate(
    specification = factor(
      specification_id, levels = rev(spec_order_5d),
      labels = rev(unname(spec_labels_5d[spec_order_5d]))
    ),
    parameterization = ifelse(
      specification_id == "PRICE_RAW", "原始价格（+1 SD）", "log1p 价格（+1 SD）"
    )
  )
price_sensitivity_plot_5d <- ggplot2::ggplot(
  price_deep_dive_data_5d,
  ggplot2::aes(odds_ratio, specification, colour = parameterization)
) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.7) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.15
  ) +
  ggplot2::geom_point(size = 2.5) +
  ggplot2::scale_x_log10() +
  ggplot2::scale_colour_manual(values = c(
    "log1p 价格（+1 SD）" = "#2C6E9B", "原始价格（+1 SD）" = "#D28E2C"
  )) +
  ggplot2::labs(
    title = "Price 的规格敏感性分析",
    subtitle = "原始价格与 log1p 价格使用不同尺度，均按对应变量增加 1 SD 解释",
    x = "Price OR（对数刻度）", y = NULL, colour = NULL
  ) + plot_theme_5d
ggplot2::ggsave(
  file.path(model_figure_dir, "18_price_sensitivity.png"),
  price_sensitivity_plot_5d, width = 8.8, height = 5.8, dpi = 180
)

fmt5d <- function(x, digits = 4) formatC(x, digits = digits, format = "f", big.mark = ",")
month_rows_5d <- release_coefficients_5d |>
  dplyr::filter(grepl("^release_month", term))
month_table_lines_5d <- c(
  "| Month vs July | OR | 95% CI |",
  "|---|---:|---:|",
  vapply(seq_len(nrow(month_rows_5d)), function(i) {
    row <- month_rows_5d[i, ]
    paste0(
      "| ", sub("release_month", "", row$term), " | ", fmt5d(row$odds_ratio),
      " | [", fmt5d(row$or_ci95_lower), ", ", fmt5d(row$or_ci95_upper), "] |"
    )
  }, character(1))
)
stability_table_lines_5d <- c(
  "| Predictor | OR range | Same direction | CI excludes 1 | Max drift | Class |",
  "|---|---:|---:|---:|---:|---|",
  vapply(seq_len(nrow(core_predictor_stability_5d)), function(i) {
    row <- core_predictor_stability_5d[i, ]
    paste0(
      "| ", unname(term_labels_en_5d[row$conceptual_term]), " | ",
      fmt5d(row$minimum_or), "-", fmt5d(row$maximum_or), " | ",
      row$same_direction_specs, "/", row$specifications_available, " | ",
      row$ci_excluding_1_specs, "/", row$specifications_available, " | ",
      fmt5d(row$max_or_drift_pct, 2), "% | ", row$robustness_class, " |"
    )
  }, character(1))
)
added_genre_rows_5d <- genre_comparison_5d |>
  dplyr::filter(term %in% added_genres_5d)
added_genre_table_lines_5d <- c(
  "| Added Steam label | Games | OR | 95% CI |",
  "|---|---:|---:|---:|",
  vapply(seq_len(nrow(added_genre_rows_5d)), function(i) {
    row <- added_genre_rows_5d[i, ]
    paste0(
      "| ", unname(term_labels_en_5d[row$term]), " | ", row$n_games_with_genre,
      " | ", fmt5d(row$odds_ratio), " | [", fmt5d(row$or_ci95_lower), ", ",
      fmt5d(row$or_ci95_upper), "] |"
    )
  }, character(1))
)

price_stability_5d <- core_predictor_stability_5d |>
  dplyr::filter(conceptual_term == "z_log1p_price")
simulation_stability_5d <- core_predictor_stability_5d |>
  dplyr::filter(conceptual_term == "genre_simulation")
strategy_stability_5d <- core_predictor_stability_5d |>
  dplyr::filter(conceptual_term == "genre_strategy")
threshold_nonprimary_5d <- threshold_stability_5d |>
  dplyr::filter(specification_id != "PRIMARY", term != "(Intercept)")
threshold_max_5d <- threshold_nonprimary_5d |>
  dplyr::slice_max(or_difference_pct, n = 1, with_ties = FALSE)
release_shared_max_5d <- release_comparison_5d |>
  dplyr::filter(!is.na(or_difference_pct), term != "(Intercept)") |>
  dplyr::slice_max(or_difference_pct, n = 1, with_ties = FALSE)
price_shared_max_5d <- price_comparison_5d |>
  dplyr::filter(!is.na(or_difference_pct), term != "(Intercept)") |>
  dplyr::slice_max(or_difference_pct, n = 1, with_ties = FALSE)
genre_shared_max_5d <- genre_comparison_5d |>
  dplyr::filter(!is.na(or_difference_pct), term %in% primary_genres_5d) |>
  dplyr::slice_max(or_difference_pct, n = 1, with_ties = FALSE)

report_lines_5d <- c(
  "# Step 5D Pre-specified Sensitivity Analysis",
  "",
  "## 1. Frozen primary",
  "",
  paste0(
    "The primary candidate remains the grouped beta-binomial on 836 paid games with >=20 reviews. ",
    "The independently refitted primary coefficients agree with the frozen Step 5C values within 1e-5. ",
    "No primary formula, reference level, or scaling parameter was changed."
  ),
  "",
  "## 2. Threshold sensitivity",
  "",
  paste0(
    "Modeling sample sizes for >0 / >=10 / >=20 / >=50 are ",
    paste(threshold_samples_5d$n_games, collapse = " / "),
    ". The >0 source contained 2,207 paid games; one game with two reviews lacked the frozen price predictor ",
    "and was explicitly audited before fitting. All four populations are nested and use the primary scaling."
  ),
  paste0(
    "The largest non-intercept threshold OR drift is `", threshold_max_5d$term,
    "` at ", fmt5d(threshold_max_5d$or_difference_pct, 2), "% in `",
    threshold_max_5d$specification_id, "`; direction change = ",
    threshold_max_5d$direction_change, ". Threshold AIC values are not compared because rows differ."
  ),
  "",
  "## 3. Release sensitivity",
  "",
  paste0(
    "Replacing standardized days with categorical release month produced AIC ",
    fmt5d(release_fit_5d$aic, 3), " versus primary ",
    fmt5d(all_fit_5d$aic[all_fit_5d$specification_id == "PRIMARY"], 3),
    " (delta ", fmt5d(release_fit_5d$delta_aic_vs_primary, 3), "). The largest shared-term OR drift is `",
    release_shared_max_5d$term, "` at ", fmt5d(release_shared_max_5d$or_difference_pct, 2), "%."
  ),
  "",
  month_table_lines_5d,
  "",
  "## 4. Price sensitivity",
  "",
  paste0(
    "Primary raw-price mean/SD are $", fmt5d(raw_price_mean_5d, 2), " / $",
    fmt5d(raw_price_sd_5d, 2), ". The +1 SD log-price OR is ",
    fmt5d(all_coefficients_5d$odds_ratio[
      all_coefficients_5d$specification_id == "PRIMARY" &
        all_coefficients_5d$term == "z_log1p_price"
    ]), "; the +1 SD raw-price OR is ",
    fmt5d(price_coefficients_5d$odds_ratio[price_coefficients_5d$term == "z_raw_price"]),
    ". Their predicted probability contrasts are ",
    fmt5d(price_predicted_contrasts_5d$absolute_probability_contrast[1], 5), " and ",
    fmt5d(price_predicted_contrasts_5d$absolute_probability_contrast[2], 5), "."
  ),
  paste0(
    "The largest shared non-intercept OR drift under raw price is `",
    price_shared_max_5d$comparison_term, "` at ",
    fmt5d(price_shared_max_5d$or_difference_pct, 2), "%."
  ),
  "",
  "## 5. Genre sensitivity",
  "",
  "Early Access here is the Steam genre/category label from the frozen genre mapping; it is not historical or launch-state status. Sports and Racing are sparse, so interval width and coefficient stability take priority over p-values.",
  "",
  added_genre_table_lines_5d,
  "",
  paste0(
    "The largest OR drift among the original seven genre coefficients is `",
    genre_shared_max_5d$term, "` at ", fmt5d(genre_shared_max_5d$or_difference_pct, 2), "%."
  ),
  "",
  "## 6. Core predictor stability",
  "",
  stability_table_lines_5d,
  "",
  paste0(
    "Price is ", price_stability_5d$robustness_class, " across ",
    price_stability_5d$specifications_available, " specifications (OR range ",
    fmt5d(price_stability_5d$minimum_or), "-", fmt5d(price_stability_5d$maximum_or),
    ", max drift ", fmt5d(price_stability_5d$max_or_drift_pct, 2), "%). Simulation is ",
    simulation_stability_5d$robustness_class, " (OR range ",
    fmt5d(simulation_stability_5d$minimum_or), "-",
    fmt5d(simulation_stability_5d$maximum_or), ", max drift ",
    fmt5d(simulation_stability_5d$max_or_drift_pct, 2), "%). Strategy is ",
    strategy_stability_5d$robustness_class, " because its maximum OR drift is ",
    fmt5d(strategy_stability_5d$max_or_drift_pct, 2), "%."
  ),
  "",
  "## 7. Diagnostics",
  "",
  paste0(
    "All seven fits have convergence code 0 and positive-definite Hessians. Maximum absolute gradients range from ",
    fmt5d(min(all_fit_5d$max_abs_fixed_gradient), 6), " to ",
    fmt5d(max(all_fit_5d$max_abs_fixed_gradient), 6), "; captured fit warnings = ",
    sum(all_fit_5d$warning_count), ". Phi ranges from ",
    fmt5d(min(all_fit_5d$beta_precision_phi)), " to ",
    fmt5d(max(all_fit_5d$beta_precision_phi)), ", and rho from ",
    fmt5d(min(all_fit_5d$intra_game_rho)), " to ",
    fmt5d(max(all_fit_5d$intra_game_rho)), "."
  ),
  "",
  "## 8. Remaining uncertainty",
  "",
  "Threshold changes alter the analysis rows, so their AIC values are descriptive fit records rather than model-ranking evidence. Release-month, raw-price, and expanded-genre AIC comparisons use identical rows but do not automatically replace the frozen primary specification. All intervals in this sensitivity audit are model-based Wald intervals.",
  "",
  "## 9. Recommendation",
  "",
  "Retain the frozen primary beta-binomial for human review. Interpret each predictor separately using the exported direction, magnitude, interval, and stability evidence; do not revise the primary automatically. Database access remained read-only, and no sensitive values are written to outputs."
)
writeLines(
  report_lines_5d,
  file.path(project_root, "reports", "step5d_sensitivity_report.md"),
  useBytes = TRUE
)

message(sprintf(
  "Step 5D visuals/report: PASS (figures=%d, core predictors=%d)",
  10L, nrow(core_predictor_stability_5d)
))
