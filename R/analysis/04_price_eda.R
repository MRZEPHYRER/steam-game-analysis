# Price distributions and descriptive price relationships.

paid_priced <- games_market |>
  dplyr::filter(is_free == 0, !is.na(current_price_usd))

price_hist <- ggplot2::ggplot(paid_priced, ggplot2::aes(x = current_price_usd)) +
  ggplot2::geom_histogram(binwidth = 2.5, fill = "#2A6F97", colour = "white") +
  ggplot2::coord_cartesian(xlim = c(0, 60)) +
  ggplot2::labs(x = "Current price (USD)", y = "Paid games")

price_ecdf <- ggplot2::ggplot(paid_priced, ggplot2::aes(x = current_price_usd)) +
  ggplot2::stat_ecdf(geom = "step", colour = "#D97706", linewidth = 0.9) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::coord_cartesian(xlim = c(0, 60)) +
  ggplot2::labs(x = "Current price (USD)", y = "Cumulative share")

price_box <- ggplot2::ggplot(paid_priced, ggplot2::aes(x = "", y = current_price_usd)) +
  ggplot2::geom_boxplot(fill = "#8ECAE6", width = 0.4, outlier.alpha = 0.35) +
  ggplot2::coord_cartesian(ylim = c(0, 60)) +
  ggplot2::labs(x = NULL, y = "Current price (USD)")

p08 <- (price_hist | price_ecdf | price_box) +
  patchwork::plot_annotation(
    title = "Paid-game prices are right-skewed",
    subtitle = "Histogram and ECDF shown through $60; boxplot retains outliers before display clipping",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", colour = "#17324D"),
      plot.subtitle = ggplot2::element_text(colour = "#52677A")
    )
  ) &
  theme_steam_analysis()
save_eda_plot(p08, "08_price_distribution.png", width = 12, height = 4.8)

p09 <- ggplot2::ggplot(
  paid_priced,
  ggplot2::aes(x = current_price_usd, y = log10_reviews)
) +
  ggplot2::geom_point(alpha = 0.25, size = 1.2, colour = "#2A6F97") +
  ggplot2::geom_smooth(
    method = "loess", formula = y ~ x, se = FALSE,
    colour = "#D97706", linewidth = 0.8
  ) +
  ggplot2::coord_cartesian(xlim = c(0, 60)) +
  ggplot2::labs(
    title = "Price and review attention have substantial overlap",
    subtitle = "Paid games only; orange curve is descriptive and the display is clipped at $60",
    x = "Current price (USD)", y = expression(log[10](1 + total~reviews))
  ) +
  theme_steam_analysis()
save_eda_plot(p09, "09_price_vs_review_volume.png")

price_positive_data <- dplyr::bind_rows(
  reviewed_games |>
    dplyr::filter(is_free == 0, !is.na(current_price_usd)) |>
    dplyr::mutate(sample = "All reviewed games"),
  games_model20 |>
    dplyr::filter(is_free == 0, !is.na(current_price_usd)) |>
    dplyr::mutate(sample = "At least 20 reviews")
) |>
  dplyr::mutate(
    sample = factor(sample, levels = c("All reviewed games", "At least 20 reviews"))
  )

p16 <- ggplot2::ggplot(
  price_positive_data,
  ggplot2::aes(x = current_price_usd, y = positive_rate)
) +
  ggplot2::geom_point(alpha = 0.22, size = 1, colour = "#2A6F97") +
  ggplot2::geom_smooth(
    method = "loess", formula = y ~ x, se = FALSE,
    colour = "#D97706", linewidth = 0.8
  ) +
  ggplot2::facet_wrap(~sample, ncol = 2) +
  ggplot2::coord_cartesian(xlim = c(0, 60)) +
  ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(
    title = "Price-positive-rate patterns depend on denominator filtering",
    subtitle = "Paid games only; panels separate all defined rates from the 20-review sample",
    x = "Current price (USD; display clipped at $60)", y = "Positive review rate"
  ) +
  theme_steam_analysis()
save_eda_plot(p16, "16_price_positive_rate_all_vs_model20.png", width = 11, height = 5)

price_summary <- paid_priced |>
  dplyr::summarise(
    games = dplyr::n(),
    mean_price = mean(current_price_usd),
    median_price = stats::median(current_price_usd),
    q1_price = stats::quantile(current_price_usd, 0.25),
    q3_price = stats::quantile(current_price_usd, 0.75),
    min_price = min(current_price_usd),
    max_price = max(current_price_usd)
  )
utils::write.csv(
  price_summary,
  file.path(r_analysis_dir, "price_summary.csv"),
  row.names = FALSE,
  na = ""
)

stopifnot(nrow(paid_priced) == 2597, price_summary$median_price == 4.99)
