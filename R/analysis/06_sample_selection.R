# Descriptive comparison of the full launch cohort and the >=20-review sample.

sample_composition <- dplyr::bind_rows(
  games_market |>
    dplyr::count(payment_segment, name = "games") |>
    dplyr::mutate(sample = "Market cohort"),
  games_model20 |>
    dplyr::count(payment_segment, name = "games") |>
    dplyr::mutate(sample = "At least 20 reviews")
) |>
  dplyr::group_by(sample) |>
  dplyr::mutate(share = games / sum(games)) |>
  dplyr::ungroup() |>
  dplyr::mutate(sample = factor(sample, levels = c("Market cohort", "At least 20 reviews")))

p10 <- ggplot2::ggplot(
  sample_composition,
  ggplot2::aes(x = sample, y = share, fill = payment_segment)
) +
  ggplot2::geom_col(width = 0.62) +
  ggplot2::geom_text(
    ggplot2::aes(label = scales::percent(share, accuracy = 0.1)),
    position = ggplot2::position_stack(vjust = 0.5),
    colour = "white", fontface = "bold", size = 3.5
  ) +
  ggplot2::scale_fill_manual(values = c("Free" = "#D97706", "Paid" = "#2A6F97")) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(
    title = "The model sample is almost entirely paid games",
    subtitle = "Composition before and after requiring at least 20 reviews",
    x = NULL, y = "Share of games", fill = NULL
  ) +
  theme_steam_analysis()
save_eda_plot(p10, "10_full_model_free_share.png", width = 8, height = 5.5)

release_month_summary <- games_market |>
  dplyr::group_by(release_month) |>
  dplyr::summarise(
    market_games = dplyr::n(),
    zero_review_pct = 100 * mean(total_reviews == 0),
    model20_games = sum(total_reviews >= 20),
    model20_coverage_pct = 100 * mean(total_reviews >= 20),
    median_reviews = stats::median(total_reviews),
    median_positive_rate = stats::median(positive_rate, na.rm = TRUE),
    .groups = "drop"
  )

month_count <- ggplot2::ggplot(
  release_month_summary,
  ggplot2::aes(x = release_month, y = market_games)
) +
  ggplot2::geom_col(fill = "#2A6F97") +
  ggplot2::labs(x = NULL, y = "Market games")

month_coverage_long <- release_month_summary |>
  dplyr::select(release_month, zero_review_pct, model20_coverage_pct) |>
  tidyr::pivot_longer(-release_month, names_to = "metric", values_to = "value") |>
  dplyr::mutate(
    metric = factor(
      metric,
      levels = c("zero_review_pct", "model20_coverage_pct"),
      labels = c("Zero reviews", "At least 20 reviews")
    )
  )
month_coverage <- ggplot2::ggplot(
  month_coverage_long,
  ggplot2::aes(x = release_month, y = value / 100, colour = metric, group = metric)
) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 2) +
  ggplot2::scale_colour_manual(values = c("Zero reviews" = "#64748B", "At least 20 reviews" = "#D97706")) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(x = NULL, y = "Share", colour = NULL)

month_reviews <- ggplot2::ggplot(
  games_market,
  ggplot2::aes(x = release_month, y = log10_reviews)
) +
  ggplot2::geom_violin(fill = "#8ECAE6", colour = NA, trim = FALSE) +
  ggplot2::geom_boxplot(width = 0.14, outlier.shape = NA, fill = "white") +
  ggplot2::stat_summary(fun = stats::median, geom = "point", colour = "#D97706", size = 2) +
  ggplot2::labs(x = "Release month", y = expression(log[10](1 + total~reviews)))

month_positive <- ggplot2::ggplot(
  release_month_summary,
  ggplot2::aes(x = release_month, y = median_positive_rate, group = 1)
) +
  ggplot2::geom_line(colour = "#D97706", linewidth = 0.8) +
  ggplot2::geom_point(colour = "#D97706", size = 2) +
  ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(x = "Release month", y = "Median positive rate")

p14 <- (month_count | month_coverage) / (month_reviews | month_positive) +
  patchwork::plot_annotation(
    title = "Review coverage varies across the July-December launch cohort",
    subtitle = "Counts, threshold coverage, median attention, and reviewed-game positivity",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", colour = "#17324D"),
      plot.subtitle = ggplot2::element_text(colour = "#52677A")
    )
  ) &
  theme_steam_analysis() &
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
save_eda_plot(p14, "14_release_month_coverage.png", width = 12, height = 8)

sample_price <- dplyr::bind_rows(
  paid_priced |>
    dplyr::mutate(sample = "Market paid games"),
  games_model20 |>
    dplyr::filter(is_free == 0, !is.na(current_price_usd)) |>
    dplyr::mutate(sample = "Model20 paid games")
) |>
  dplyr::mutate(sample = factor(sample, levels = c("Market paid games", "Model20 paid games")))

sample_price_plot <- ggplot2::ggplot(
  sample_price,
  ggplot2::aes(x = sample, y = current_price_usd, fill = sample)
) +
  ggplot2::geom_violin(trim = FALSE, alpha = 0.65, colour = NA) +
  ggplot2::geom_boxplot(width = 0.18, outlier.shape = NA, fill = "white") +
  ggplot2::coord_cartesian(ylim = c(0, 60)) +
  ggplot2::scale_fill_manual(
    values = c("Market paid games" = "#2A6F97", "Model20 paid games" = "#D97706")
  ) +
  ggplot2::labs(
    title = "The review threshold selects a higher-priced paid-game mix",
    subtitle = "Violins and boxplots; display clipped at $60 without dropping source rows",
    x = NULL, y = "Current price (USD)"
  ) +
  theme_steam_analysis() +
  ggplot2::theme(legend.position = "none")

price_band_selection <- games_market |>
  dplyr::group_by(price_band) |>
  dplyr::summarise(
    market_games = dplyr::n(),
    zero_review_pct = 100 * mean(total_reviews == 0),
    model20_pct = 100 * mean(total_reviews >= 20),
    .groups = "drop"
  )
price_band_long <- price_band_selection |>
  tidyr::pivot_longer(
    cols = c(zero_review_pct, model20_pct),
    names_to = "metric", values_to = "share_pct"
  ) |>
  dplyr::mutate(
    metric = factor(
      metric,
      levels = c("zero_review_pct", "model20_pct"),
      labels = c("Zero reviews", "At least 20 reviews")
    )
  )
price_selection_plot <- ggplot2::ggplot(
  price_band_long,
  ggplot2::aes(x = share_pct / 100, y = price_band, colour = metric)
) +
  ggplot2::geom_point(size = 2.5, position = ggplot2::position_dodge(width = 0.4)) +
  ggplot2::scale_colour_manual(
    values = c("Zero reviews" = "#64748B", "At least 20 reviews" = "#D97706")
  ) +
  ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(x = "Share within price band", y = NULL, colour = NULL) +
  theme_steam_analysis()

p15 <- sample_price_plot | price_selection_plot
save_eda_plot(p15, "15_full_model_price_distribution.png", width = 12, height = 5.5)

platform_support <- dplyr::bind_rows(
  data.frame(
    sample = "Market cohort",
    platform = c("Windows", "macOS", "Linux"),
    games = c(
      sum(games_market$platform_windows == 1),
      sum(games_market$platform_mac == 1),
      sum(games_market$platform_linux == 1)
    ),
    denominator = nrow(games_market)
  ),
  data.frame(
    sample = "At least 20 reviews",
    platform = c("Windows", "macOS", "Linux"),
    games = c(
      sum(games_model20$platform_windows == 1),
      sum(games_model20$platform_mac == 1),
      sum(games_model20$platform_linux == 1)
    ),
    denominator = nrow(games_model20)
  )
) |>
  dplyr::mutate(
    share = games / denominator,
    sample = factor(sample, levels = c("Market cohort", "At least 20 reviews"))
  )

platform_selection <- games_market |>
  dplyr::group_by(platform_segment) |>
  dplyr::summarise(
    market_games = dplyr::n(),
    model20_games = sum(total_reviews >= 20),
    model20_coverage_pct = 100 * mean(total_reviews >= 20),
    .groups = "drop"
  )

platform_share_plot <- ggplot2::ggplot(
  platform_support,
  ggplot2::aes(x = platform, y = share, fill = sample)
) +
  ggplot2::geom_col(position = "dodge", width = 0.68) +
  ggplot2::scale_fill_manual(
    values = c("Market cohort" = "#2A6F97", "At least 20 reviews" = "#D97706")
  ) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(x = NULL, y = "Games supporting platform", fill = NULL)

platform_cutoff_plot <- ggplot2::ggplot(
  platform_selection,
  ggplot2::aes(
    x = model20_coverage_pct / 100,
    y = stats::reorder(platform_segment, model20_coverage_pct)
  )
) +
  ggplot2::geom_segment(
    ggplot2::aes(x = 0, xend = model20_coverage_pct / 100, yend = platform_segment),
    colour = "#CBD5E1", linewidth = 0.8
  ) +
  ggplot2::geom_point(colour = "#D97706", size = 2.5) +
  ggplot2::scale_x_continuous(labels = scales::percent) +
  ggplot2::labs(x = "Share reaching 20 reviews", y = NULL)

p18 <- (platform_share_plot | platform_cutoff_plot) +
  patchwork::plot_annotation(
    title = "Platform support is associated with different sample retention",
    subtitle = "Multi-platform support shares and descriptive 20-review coverage",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", colour = "#17324D"),
      plot.subtitle = ggplot2::element_text(colour = "#52677A")
    )
  )
p18 <- p18 & theme_steam_analysis()
save_eda_plot(p18, "18_platform_support_and_selection.png", width = 12, height = 5.5)

high_attention_games <- games_market |>
  dplyr::arrange(dplyr::desc(total_reviews), appid) |>
  dplyr::slice_head(n = 20) |>
  dplyr::mutate(name_label = stats::reorder(name, total_reviews))

p20 <- ggplot2::ggplot(
  high_attention_games,
  ggplot2::aes(x = total_reviews, y = name_label)
) +
  ggplot2::geom_col(fill = "#2A6F97") +
  ggplot2::scale_x_continuous(labels = scales::comma) +
  ggplot2::labs(
    title = "A small set of games dominates review attention",
    subtitle = "Top 20 launch-cohort games by Steam-purchaser review count",
    x = "Total reviews", y = NULL
  ) +
  theme_steam_analysis()
save_eda_plot(p20, "20_high_attention_games.png", width = 10, height = 7)

utils::write.csv(
  sample_composition,
  file.path(r_analysis_dir, "sample_selection_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  release_month_summary,
  file.path(r_analysis_dir, "release_month_eda.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  platform_support,
  file.path(r_analysis_dir, "platform_eda.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  price_band_selection,
  file.path(r_analysis_dir, "price_band_selection.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  high_attention_games |>
    dplyr::select(appid, name, total_reviews, positive_rate, current_price_usd, is_free),
  file.path(r_analysis_dir, "high_attention_games.csv"),
  row.names = FALSE,
  na = ""
)

stopifnot(
  sum(sample_composition$games[sample_composition$sample == "Market cohort"]) == 3000,
  sum(sample_composition$games[sample_composition$sample == "At least 20 reviews"]) == 844,
  nrow(high_attention_games) == 20
)
