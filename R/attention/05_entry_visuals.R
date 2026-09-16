# Step 6A figures 35-44.

if (!exists("calibration_6a") || !exists("functional_form_decision_6a")) {
  stop("Run Step 6A diagnostics before visuals.", call. = FALSE)
}
if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("scales", quietly = TRUE)) {
  stop("Missing plotting package.", call. = FALSE)
}

font_6a <- if (.Platform$OS.type == "windows") "Microsoft YaHei" else "sans"
theme_6a <- ggplot2::theme_minimal(base_size = 12, base_family = font_6a) +
  ggplot2::theme(
    plot.title.position = "plot",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    axis.title = ggplot2::element_text(face = "bold")
  )
save_6a <- function(name, plot, width = 8.4, height = 6.2) {
  ggplot2::ggsave(file.path(attention_figure_dir, name), plot, width = width, height = height, dpi = 180)
}
curve_colours_6a <- c("Linear" = "#2C7FB8", "Natural spline df=3" = "#D9901A", "Linear log1p" = "#2C7FB8")

p35 <- ggplot2::ggplot(days_curve_6a, ggplot2::aes(days_since_release, predicted_probability, colour = model)) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_colour_manual(values = curve_colours_6a) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "上市时间与获得至少一条评论的概率",
    subtitle = "Primary linear term 与预设 natural spline df=3；其余变量固定在 reference",
    x = "上市至评论快照天数", y = "P(has review)", colour = "函数形式",
    caption = "Days 是 exposure-related predictor，不作为 offset。"
  ) + theme_6a
save_6a("35_days_review_entry_curve.png", p35)

p36 <- ggplot2::ggplot(price_curve_6a, ggplot2::aes(current_price_usd, predicted_probability, colour = model)) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_colour_manual(values = curve_colours_6a) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "付费游戏价格与 Review Entry 概率",
    subtitle = "仅限 paid games；比较 linear log1p 与 natural spline df=3",
    x = "Collection-time current price（USD）", y = "P(has review)", colour = "函数形式",
    caption = "价格是快照时点关联，不解释为因果效应。"
  ) + theme_6a
save_6a("36_paid_price_review_entry_curve.png", p36)

p37 <- ggplot2::ggplot(calibration_6a, ggplot2::aes(mean_predicted_probability, observed_has_review_rate)) +
  ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed", colour = "grey45") +
  ggplot2::geom_line(linewidth = 0.9, colour = "#2C7FB8") +
  ggplot2::geom_point(size = 2.8, colour = "#2C7FB8") +
  ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  ggplot2::scale_x_continuous(labels = scales::percent_format()) +
  ggplot2::scale_y_continuous(labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Primary Logistic 样本内校准",
    subtitle = "按预测概率十分位汇总；虚线为理想 45 度线",
    x = "平均预测概率", y = "观察 has-review rate",
    caption = "描述性 in-sample calibration，不是外部验证。"
  ) + theme_6a
save_6a("37_attention_entry_calibration.png", p37, 7.2, 6.2)

p38 <- ggplot2::ggplot(roc_points_6a, ggplot2::aes(false_positive_rate, true_positive_rate)) +
  ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed", colour = "grey45") +
  ggplot2::geom_path(linewidth = 1, colour = "#2C7FB8") +
  ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  ggplot2::labs(
    title = sprintf("Review Entry ROC（AUC = %.3f）", auc_6a$auc),
    subtitle = "Secondary in-sample discrimination diagnostic",
    x = "假阳性率", y = "真阳性率",
    caption = "不优化分类阈值；本分析不是预测竞赛。"
  ) + theme_6a
save_6a("38_attention_entry_roc.png", p38, 7.2, 6.2)

term_labels_6a <- c(
  "is_free" = "Free vs paid",
  "z_log1p_paid_price_component" = "Paid price（+1 SD）",
  "z_days_since_release" = "上市时间（+1 SD）",
  "platform_segmentWindows + macOS" = "Windows + macOS",
  "platform_segmentWindows + Linux" = "Windows + Linux",
  "platform_segmentWindows + macOS + Linux" = "三平台支持",
  "genre_action" = "Action", "genre_adventure" = "Adventure",
  "genre_casual" = "Casual", "genre_indie" = "Indie", "genre_rpg" = "RPG",
  "genre_simulation" = "Simulation", "genre_strategy" = "Strategy"
)
or_plot_data_6a <- primary_coefficients_6a |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::mutate(label = factor(unname(term_labels_6a[term]), levels = rev(unname(term_labels_6a))))
p39 <- ggplot2::ggplot(or_plot_data_6a, ggplot2::aes(odds_ratio, label)) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey45") +
  ggplot2::geom_errorbar(ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper), orientation = "y", width = 0.18, colour = "#6C757D") +
  ggplot2::geom_point(size = 2.7, colour = "#2C7FB8") +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "Review Entry Primary Logistic OR 与 95% CI",
    subtitle = "N 为完整 price-containing market model sample；Windows only 为平台 reference",
    x = "Odds ratio（log10）", y = NULL,
    caption = "条件关联，不解释为销量、owners 或因果效应。"
  ) + theme_6a
save_6a("39_attention_entry_primary_or.png", p39, 9.5, 7.4)

p40 <- ggplot2::ggplot(free_paid_summary_6a, ggplot2::aes(game_type, has_review_rate, fill = game_type)) +
  ggplot2::geom_col(width = 0.62) +
  ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%%\nN=%d", has_review_percent, n_games)), vjust = -0.35, family = font_6a) +
  ggplot2::scale_fill_manual(values = c("Free" = "#D9901A", "Paid" = "#2C7FB8"), guide = "none") +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Free 与 Paid 游戏的 Raw Review Entry Rate",
    subtitle = "未调整市场描述；zero-review 是 outcome 的非事件部分",
    x = NULL, y = "Has-review rate",
    caption = "Raw gap 不代表 free status 的因果效应。"
  ) + theme_6a
save_6a("40_free_paid_attention.png", p40, 7.0, 6.0)

p41 <- ggplot2::ggplot(platform_summary_6a, ggplot2::aes(has_review_rate, stats::reorder(as.character(platform_segment), has_review_rate))) +
  ggplot2::geom_col(width = 0.62, fill = "#2C7FB8") +
  ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%% (N=%d)", has_review_percent, n_games)), hjust = -0.05, family = font_6a) +
  ggplot2::scale_x_continuous(limits = c(0, 1.08), labels = scales::percent_format()) +
  ggplot2::labs(title = "Platform Segment 的 Raw Review Entry Rate", x = "Has-review rate", y = NULL, caption = "Raw group comparison；调整后 association 见 OR 图。") + theme_6a
save_6a("41_platform_attention.png", p41, 9.0, 5.8)

p42 <- ggplot2::ggplot(genre_summary_6a, ggplot2::aes(has_review_rate, stats::reorder(genre, has_review_rate), size = n_games)) +
  ggplot2::geom_point(colour = "#2C7FB8", alpha = 0.8) +
  ggplot2::scale_x_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::scale_size_continuous(range = c(2.5, 8), name = "Genre N") +
  ggplot2::labs(title = "完整市场中各 Genre 的 Raw Review Entry Rate", x = "Has-review rate", y = NULL, caption = "Genre 可重叠；点大小表示该标签的游戏数。") + theme_6a
save_6a("42_genre_attention.png", p42, 9.0, 7.0)

p43 <- ggplot2::ggplot(month_summary_6a, ggplot2::aes(release_month, has_review_rate, group = 1)) +
  ggplot2::geom_line(linewidth = 0.9, colour = "#2C7FB8") +
  ggplot2::geom_point(size = 2.8, colour = "#2C7FB8") +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(title = "Release Month 与 Raw Review Entry Rate", subtitle = "较早发布通常拥有更长评论暴露时间", x = "Release month", y = "Has-review rate", caption = "Primary 使用连续 days；month 仅作预设 sensitivity。") + theme_6a
save_6a("43_release_attention.png", p43)

functional_plot_6a <- functional_form_decision_6a |>
  dplyr::select(predictor, linear_aic, spline_aic) |>
  tidyr::pivot_longer(c(linear_aic, spline_aic), names_to = "form", values_to = "aic") |>
  dplyr::group_by(predictor) |>
  dplyr::mutate(delta_aic_from_best = aic - min(aic)) |>
  dplyr::ungroup() |>
  dplyr::mutate(form = factor(form, levels = c("linear_aic", "spline_aic"), labels = c("Linear", "Spline df=3")))
p44 <- ggplot2::ggplot(functional_plot_6a, ggplot2::aes(delta_aic_from_best, form, fill = form)) +
  ggplot2::geom_col(width = 0.58) +
  ggplot2::facet_wrap(~predictor, scales = "free_x") +
  ggplot2::scale_fill_manual(values = c("Linear" = "#2C7FB8", "Spline df=3" = "#D9901A"), guide = "none") +
  ggplot2::labs(title = "Linear 与预设 Spline df=3 的 AIC 比较", subtitle = "每个 predictor 内最佳模型设为 Delta AIC = 0", x = "Delta AIC from best", y = NULL, caption = "仅同 outcome、同 rows 的模型内比较；不自动替换 primary。") + theme_6a
save_6a("44_functional_form_comparison.png", p44, 8.4, 5.4)

message("Step 6A figures: PASS (35-44 generated)")
