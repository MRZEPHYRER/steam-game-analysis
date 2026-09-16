# Step 6A.1 figures 45-52.

if (!exists("step6a1_stage_decision_6a1") || !exists("df4_curve_6a1")) {
  stop("Run Step 6A.1 diagnostics before visuals.", call. = FALSE)
}
if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("scales", quietly = TRUE)) {
  stop("Missing plotting package.", call. = FALSE)
}

font_6a1 <- if (.Platform$OS.type == "windows") "Microsoft YaHei" else "sans"
theme_6a1 <- ggplot2::theme_minimal(base_size = 12, base_family = font_6a1) +
  ggplot2::theme(
    plot.title.position = "plot",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    axis.title = ggplot2::element_text(face = "bold")
  )
save_6a1 <- function(name, plot, width = 8.6, height = 6.2) {
  ggplot2::ggsave(
    file.path(attention_figure_dir, name),
    plot,
    width = width,
    height = height,
    dpi = 180
  )
}
price_breaks_6a1 <- c(0.5, 1, 3, 5, 10, 20, 50, 100, 200)

p45 <- ggplot2::ggplot(price_curve_6a1, ggplot2::aes(price_usd, predicted_probability)) +
  ggplot2::annotate(
    "rect", xmin = price_support_6a1$p05_usd, xmax = price_support_6a1$p95_usd,
    ymin = -Inf, ymax = Inf, fill = "#DCEAF5", alpha = 0.45
  ) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = ci95_lower, ymax = ci95_upper),
    fill = "#2C7FB8", alpha = 0.18
  ) +
  ggplot2::geom_line(linewidth = 1.1, colour = "#2C7FB8") +
  ggplot2::geom_vline(xintercept = peak_audit_6a1$peak_price_usd, linetype = "dashed", colour = "#D9901A") +
  ggplot2::geom_point(
    data = peak_audit_6a1,
    ggplot2::aes(x = peak_price_usd, y = peak_predicted_probability),
    inherit.aes = FALSE, size = 3, colour = "#D9901A"
  ) +
  ggplot2::scale_x_log10(breaks = price_breaks_6a1, labels = scales::dollar_format()) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "最终 nonlinear paid-price Review Entry 曲线",
    subtitle = "Natural spline df=3；阴影带为 link-scale 95% CI，浅蓝区域为 paid-price 5–95% support",
    x = "Collection-time current price（USD，log10 轴）", y = "P(has review)",
    caption = "拟合峰值只描述模型曲线，不代表最优或因果价格。"
  ) + theme_6a1
save_6a1("45_price_nonlinear_primary_curve.png", p45)

p46 <- ggplot2::ggplot(paid_price_population_6a1, ggplot2::aes(current_price_usd)) +
  ggplot2::geom_histogram(bins = 35, fill = "#2C7FB8", colour = "white", linewidth = 0.25) +
  ggplot2::geom_vline(
    xintercept = c(price_support_6a1$p05_usd, price_support_6a1$p95_usd),
    linetype = "dashed", colour = "#6C757D"
  ) +
  ggplot2::geom_vline(xintercept = peak_audit_6a1$peak_price_usd, colour = "#D9901A", linewidth = 1) +
  ggplot2::scale_x_log10(breaks = price_breaks_6a1, labels = scales::dollar_format()) +
  ggplot2::labs(
    title = "Paid Price 数据支持与稀疏高价尾部",
    subtitle = "虚线为 5th/95th percentiles；橙线为 df=3 拟合峰值",
    x = "Collection-time current price（USD，log10 轴）", y = "Paid game count",
    caption = sprintf(
      "N≥$20: %d；N≥$30: %d；N≥$50: %d；N≥$100: %d。",
      price_support_6a1$n_ge_20_usd, price_support_6a1$n_ge_30_usd,
      price_support_6a1$n_ge_50_usd, price_support_6a1$n_ge_100_usd
    )
  ) + theme_6a1
save_6a1("46_price_curve_support_density.png", p46)

linear_vs_curve_plot_6a1 <- dplyr::bind_rows(
  linear_price_curve_6a1 |>
    dplyr::transmute(price_usd, model = "Linear benchmark", predicted_probability, ci95_lower, ci95_upper),
  price_curve_6a1 |>
    dplyr::transmute(price_usd, model = "Spline df=3 primary", predicted_probability, ci95_lower, ci95_upper)
)
p47 <- ggplot2::ggplot(
  linear_vs_curve_plot_6a1,
  ggplot2::aes(price_usd, predicted_probability, colour = model)
) +
  ggplot2::annotate(
    "rect", xmin = price_support_6a1$p05_usd, xmax = price_support_6a1$p95_usd,
    ymin = -Inf, ymax = Inf, fill = "#DCEAF5", alpha = 0.35
  ) +
  ggplot2::geom_line(linewidth = 1.05) +
  ggplot2::scale_colour_manual(values = c("Linear benchmark" = "#6C757D", "Spline df=3 primary" = "#D9901A")) +
  ggplot2::scale_x_log10(breaks = price_breaks_6a1, labels = scales::dollar_format()) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Linear Benchmark 与最终 Spline Price Curve",
    subtitle = "相同 N=2,998；浅蓝区域为 paid-price central 5–95% support",
    x = "Collection-time current price（USD，log10 轴）", y = "P(has review)", colour = "模型",
    caption = "Linear benchmark 保留作审计基准，不再作为最终 price functional form。"
  ) + theme_6a1
save_6a1("47_linear_vs_spline_price_curve.png", p47)

term_labels_6a1 <- c(
  "is_free" = "Free vs paid（centered price）",
  "z_days_since_release" = "上市时间（+1 SD）",
  "platform_segmentWindows + macOS" = "Windows + macOS",
  "platform_segmentWindows + Linux" = "Windows + Linux",
  "platform_segmentWindows + macOS + Linux" = "三平台支持",
  "genre_action" = "Action", "genre_adventure" = "Adventure",
  "genre_casual" = "Casual", "genre_indie" = "Indie", "genre_rpg" = "RPG",
  "genre_simulation" = "Simulation", "genre_strategy" = "Strategy"
)
or_plot_6a1 <- nonlinear_non_spline_coefficients_6a1 |>
  dplyr::filter(term != "(Intercept)") |>
  dplyr::mutate(label = factor(unname(term_labels_6a1[term]), levels = rev(unname(term_labels_6a1))))
p48 <- ggplot2::ggplot(or_plot_6a1, ggplot2::aes(odds_ratio, label)) +
  ggplot2::geom_vline(xintercept = 1, colour = "grey45") +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = or_ci95_lower, xmax = or_ci95_upper),
    orientation = "y", width = 0.18, colour = "#6C757D"
  ) +
  ggplot2::geom_point(size = 2.7, colour = "#2C7FB8") +
  ggplot2::scale_x_log10() +
  ggplot2::labs(
    title = "Nonlinear Review Entry Primary OR 与 95% CI",
    subtitle = "Spline basis coefficients 不作为 substantive effects 展示",
    x = "Odds ratio（log10）", y = NULL,
    caption = "Free OR 对应 centered paid-price reference；其余为条件关联。"
  ) + theme_6a1
save_6a1("48_nonlinear_primary_or.png", p48, 9.5, 7.2)

p49 <- ggplot2::ggplot(
  calibration_comparison_6a1,
  ggplot2::aes(mean_predicted_probability, observed_has_review_rate, colour = model_id)
) +
  ggplot2::geom_abline(intercept = 0, slope = 1, linetype = "dashed", colour = "grey45") +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::geom_point(size = 2.5) +
  ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  ggplot2::scale_colour_manual(values = c("LINEAR_BENCHMARK" = "#6C757D", "NONLINEAR_PRICE_DF3_PRIMARY" = "#2C7FB8")) +
  ggplot2::scale_x_continuous(labels = scales::percent_format()) +
  ggplot2::scale_y_continuous(labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Linear 与 Nonlinear Primary 的样本内校准",
    subtitle = "按预测概率十分位汇总；虚线为理想 45 度线",
    x = "平均预测概率", y = "观察 has-review rate", colour = "模型",
    caption = "描述性 in-sample calibration，不是外部验证。"
  ) + theme_6a1
save_6a1("49_nonlinear_calibration.png", p49, 7.5, 6.4)

p50 <- ggplot2::ggplot(
  price_curve_sensitivity_6a1,
  ggplot2::aes(price_usd, predicted_probability, colour = model_id)
) +
  ggplot2::annotate(
    "rect", xmin = price_support_6a1$p05_usd, xmax = price_support_6a1$p95_usd,
    ymin = -Inf, ymax = Inf, fill = "#DCEAF5", alpha = 0.35
  ) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::scale_colour_manual(values = c(
    "NONLINEAR_PRICE_DF3_PRIMARY" = "#2C7FB8",
    "RELEASE_MONTH_SENSITIVITY" = "#D9901A",
    "EXPANDED_GENRE_SENSITIVITY" = "#4C956C"
  )) +
  ggplot2::scale_x_log10(breaks = price_breaks_6a1, labels = scales::dollar_format()) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Paid-price Curve 的 Release 与 Genre Sensitivity",
    subtitle = "同一 frozen df=3 basis；浅蓝区域为 central 5–95% support",
    x = "Collection-time current price（USD，log10 轴）", y = "P(has review)", colour = "模型",
    caption = "稳定性主要在 central support 判断；稀疏高价尾部不作强推断。"
  ) + theme_6a1
save_6a1("50_nonlinear_price_sensitivity.png", p50)

df_compare_plot_6a1 <- dplyr::bind_rows(
  price_curve_6a1 |>
    dplyr::transmute(price_usd, model = "Spline df=3 primary", predicted_probability),
  df4_curve_6a1 |>
    dplyr::transmute(price_usd, model = "Spline df=4 sensitivity", predicted_probability)
)
p51 <- ggplot2::ggplot(df_compare_plot_6a1, ggplot2::aes(price_usd, predicted_probability, colour = model)) +
  ggplot2::annotate(
    "rect", xmin = price_support_6a1$p05_usd, xmax = price_support_6a1$p95_usd,
    ymin = -Inf, ymax = Inf, fill = "#DCEAF5", alpha = 0.35
  ) +
  ggplot2::geom_line(linewidth = 1.05) +
  ggplot2::scale_colour_manual(values = c("Spline df=3 primary" = "#2C7FB8", "Spline df=4 sensitivity" = "#D9901A")) +
  ggplot2::scale_x_log10(breaks = price_breaks_6a1, labels = scales::dollar_format()) +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  ggplot2::labs(
    title = "Paid-price Spline df=3 与 df=4 Shape Sensitivity",
    subtitle = "仅一个预设复杂度 sensitivity；没有进行 df grid search",
    x = "Collection-time current price（USD，log10 轴）", y = "P(has review)", colour = "规格",
    caption = "Freeze 判断以 central 5–95% support 的 shape 稳定性为主。"
  ) + theme_6a1
save_6a1("51_price_df3_vs_df4.png", p51)

if (nrow(gam_curve_6a1) > 0L) {
  gam_compare_plot_6a1 <- dplyr::bind_rows(
    price_curve_6a1 |>
      dplyr::transmute(price_usd, model = "Spline df=3 primary", predicted_probability),
    gam_curve_6a1 |>
      dplyr::transmute(price_usd, model = "Optional GAM k=5", predicted_probability)
  )
  p52 <- ggplot2::ggplot(gam_compare_plot_6a1, ggplot2::aes(price_usd, predicted_probability, colour = model)) +
    ggplot2::annotate(
      "rect", xmin = price_support_6a1$p05_usd, xmax = price_support_6a1$p95_usd,
      ymin = -Inf, ymax = Inf, fill = "#DCEAF5", alpha = 0.35
    ) +
    ggplot2::geom_line(linewidth = 1.05) +
    ggplot2::scale_colour_manual(values = c("Spline df=3 primary" = "#2C7FB8", "Optional GAM k=5" = "#8E5EA2")) +
    ggplot2::scale_x_log10(breaks = price_breaks_6a1, labels = scales::dollar_format()) +
    ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
    ggplot2::labs(
      title = "Spline df=3 与 Optional GAM Price Curve",
      subtitle = "GAM 仅用于 shape diagnostic，不替代 inferential primary",
      x = "Collection-time current price（USD，log10 轴）", y = "P(has review)", colour = "规格",
      caption = "浅蓝区域为 central 5–95% support。"
    ) + theme_6a1
  save_6a1("52_price_spline_vs_gam.png", p52)
}

message(sprintf(
  "Step 6A.1 figures: PASS (45-51%s generated)",
  if (nrow(gam_curve_6a1) > 0L) " and 52" else ""
))
