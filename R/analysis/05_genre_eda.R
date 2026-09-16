# Genre is multi-label: one game contributes once to every assigned genre.

genre_base <- games_genres |>
  dplyr::group_by(genre_id, genre_name) |>
  dplyr::summarise(
    market_games = dplyr::n_distinct(appid),
    reviewed_games = dplyr::n_distinct(appid[total_reviews > 0]),
    model20_games = dplyr::n_distinct(appid[total_reviews >= 20]),
    review_coverage_pct = 100 * reviewed_games / market_games,
    model20_coverage_pct = 100 * model20_games / market_games,
    median_reviews = stats::median(total_reviews),
    positive_rate_all_reviewed = stats::median(positive_rate[total_reviews > 0], na.rm = TRUE),
    positive_rate_model20 = stats::median(positive_rate[total_reviews >= 20], na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    market_composition_pct = 100 * market_games / sum(market_games),
    model20_composition_pct = 100 * model20_games / sum(model20_games),
    composition_change_pp = model20_composition_pct - market_composition_pct
  ) |>
  dplyr::arrange(dplyr::desc(market_games), genre_name)

genre_top <- genre_base |>
  dplyr::slice_head(n = 15)
genre_top_levels <- rev(genre_top$genre_name)

genre_composition_plot <- genre_base |>
  dplyr::slice_max(abs(composition_change_pp), n = 15, with_ties = FALSE) |>
  dplyr::mutate(genre_name = stats::reorder(genre_name, composition_change_pp))

p11 <- ggplot2::ggplot(
  genre_composition_plot,
  ggplot2::aes(x = composition_change_pp, y = genre_name)
) +
  ggplot2::geom_vline(xintercept = 0, colour = "#94A3B8", linewidth = 0.5) +
  ggplot2::geom_col(ggplot2::aes(fill = composition_change_pp >= 0), width = 0.7) +
  ggplot2::scale_fill_manual(values = c("TRUE" = "#D97706", "FALSE" = "#2A6F97")) +
  ggplot2::labs(
    title = "The 20-review rule changes genre composition",
    subtitle = "Largest absolute changes; percentage points among multi-label genre assignments",
    x = "Model20 share minus market share (percentage points)", y = NULL
  ) +
  theme_steam_analysis() +
  ggplot2::theme(legend.position = "none")
save_eda_plot(p11, "11_model_selection_by_genre.png", width = 9, height = 6)

p12 <- ggplot2::ggplot(
  genre_top |>
    dplyr::mutate(genre_name = factor(genre_name, levels = genre_top_levels)),
  ggplot2::aes(x = market_games, y = genre_name)
) +
  ggplot2::geom_col(fill = "#2A6F97") +
  ggplot2::geom_text(
    ggplot2::aes(label = scales::comma(market_games)),
    hjust = -0.15, size = 3.1
  ) +
  ggplot2::scale_x_continuous(
    labels = scales::comma,
    expand = ggplot2::expansion(mult = c(0, 0.12))
  ) +
  ggplot2::labs(
    title = "Genre assignments are dominated by broad labels",
    subtitle = "Top 15 genres; counts exceed 3,000 in aggregate because genre is multi-label",
    x = "Games carrying genre", y = NULL
  ) +
  theme_steam_analysis()
save_eda_plot(p12, "12_genre_frequency.png", width = 9, height = 6)

genre_coverage_long <- genre_top |>
  dplyr::transmute(
    genre_name = factor(genre_name, levels = genre_top_levels),
    zero_review = 1 - reviewed_games / market_games,
    model20 = model20_coverage_pct / 100
  ) |>
  tidyr::pivot_longer(
    cols = c(zero_review, model20), names_to = "metric", values_to = "share"
  ) |>
  dplyr::mutate(
    metric = factor(
      metric,
      levels = c("zero_review", "model20"),
      labels = c("Zero reviews", "At least 20 reviews")
    )
  )

genre_coverage_plot <- ggplot2::ggplot(
  genre_coverage_long,
  ggplot2::aes(x = share, y = genre_name, colour = metric)
) +
  ggplot2::geom_point(size = 2.3, position = ggplot2::position_dodge(width = 0.4)) +
  ggplot2::scale_colour_manual(
    values = c("Zero reviews" = "#64748B", "At least 20 reviews" = "#D97706")
  ) +
  ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(
    x = "Share within genre", y = NULL, colour = NULL
  ) +
  theme_steam_analysis()

genre_median_plot <- ggplot2::ggplot(
  genre_top |>
    dplyr::mutate(genre_name = factor(genre_name, levels = genre_top_levels)),
  ggplot2::aes(x = median_reviews, y = genre_name)
) +
  ggplot2::geom_segment(
    ggplot2::aes(x = 0, xend = median_reviews, yend = genre_name),
    colour = "#CBD5E1", linewidth = 0.7
  ) +
  ggplot2::geom_point(size = 2.3, colour = "#2A6F97") +
  ggplot2::labs(x = "Median total reviews", y = NULL) +
  theme_steam_analysis()

p13 <- (genre_coverage_plot | genre_median_plot) +
  patchwork::plot_annotation(
    title = "Review coverage and median attention vary by genre",
    subtitle = "Multi-label genre membership; all measures are descriptive",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", colour = "#17324D"),
      plot.subtitle = ggplot2::element_text(colour = "#52677A")
    )
  )
save_eda_plot(p13, "13_genre_review_coverage.png", width = 12, height = 6)

genre_positive_long <- genre_top |>
  dplyr::select(
    genre_name, reviewed_games, model20_games,
    positive_rate_all_reviewed, positive_rate_model20
  ) |>
  tidyr::pivot_longer(
    cols = c(positive_rate_all_reviewed, positive_rate_model20),
    names_to = "sample", values_to = "median_positive_rate"
  ) |>
  dplyr::mutate(
    n = ifelse(sample == "positive_rate_all_reviewed", reviewed_games, model20_games),
    sample = factor(
      sample,
      levels = c("positive_rate_all_reviewed", "positive_rate_model20"),
      labels = c("All reviewed", "At least 20 reviews")
    ),
    genre_name = factor(genre_name, levels = genre_top_levels)
  ) |>
  dplyr::filter(!is.na(median_positive_rate))

p17 <- ggplot2::ggplot(
  genre_positive_long,
  ggplot2::aes(x = median_positive_rate, y = genre_name, colour = sample)
) +
  ggplot2::geom_point(size = 2.3, position = ggplot2::position_dodge(width = 0.45)) +
  ggplot2::geom_text(
    ggplot2::aes(label = paste0("n=", n)),
    position = ggplot2::position_dodge(width = 0.45),
    hjust = -0.2, size = 2.7, show.legend = FALSE
  ) +
  ggplot2::scale_colour_manual(
    values = c("All reviewed" = "#2A6F97", "At least 20 reviews" = "#D97706")
  ) +
  ggplot2::scale_x_continuous(
    labels = scales::percent,
    limits = c(0, 1.08),
    breaks = seq(0, 1, 0.2)
  ) +
  ggplot2::labs(
    title = "Genre-level positivity shifts after applying the review cutoff",
    subtitle = "Median raw positive rate with game counts; top 15 genres",
    x = "Median positive review rate", y = NULL, colour = NULL
  ) +
  theme_steam_analysis()
save_eda_plot(p17, "17_genre_positive_rate_all_vs_model20.png", width = 10.5, height = 7)

utils::write.csv(
  genre_base,
  file.path(r_analysis_dir, "genre_eda_summary.csv"),
  row.names = FALSE,
  na = ""
)

stopifnot(
  sum(genre_base$market_games) == 8796,
  all(genre_base$model20_games <= genre_base$reviewed_games),
  all(genre_base$reviewed_games <= genre_base$market_games)
)
