# Review-volume and positive-rate EDA. Zero-review games stay in volume plots
# and are excluded only where positive_rate is undefined by construction.

reviewed_games <- games_market |>
  dplyr::filter(total_reviews > 0)

p01 <- ggplot2::ggplot(games_market, ggplot2::aes(x = total_reviews)) +
  ggplot2::geom_histogram(binwidth = 10, fill = "#2A6F97", colour = "white") +
  ggplot2::coord_cartesian(xlim = c(0, 1000)) +
  ggplot2::scale_y_continuous(labels = scales::comma) +
  ggplot2::labs(
    title = "Review volume is concentrated near zero",
    subtitle = "Raw scale shown through 1,000 reviews; all 3,000 games remain in the data",
    x = "Total Steam-purchaser reviews", y = "Games",
    caption = "The long right tail extends to 136,842 reviews."
  ) +
  theme_steam_analysis()
save_eda_plot(p01, "01_review_count_hist_raw.png")

p02 <- ggplot2::ggplot(games_market, ggplot2::aes(x = log10_reviews)) +
  ggplot2::geom_histogram(binwidth = 0.15, fill = "#2A6F97", colour = "white") +
  ggplot2::geom_vline(
    xintercept = log10(21), colour = "#D97706", linewidth = 0.8,
    linetype = "dashed"
  ) +
  ggplot2::labs(
    title = "Log scale reveals the full review-volume distribution",
    subtitle = "Dashed line marks the model-sample threshold of 20 reviews",
    x = expression(log[10](1 + total~reviews)), y = "Games"
  ) +
  theme_steam_analysis()
save_eda_plot(p02, "02_review_count_hist_log.png")

p03 <- ggplot2::ggplot(games_market, ggplot2::aes(x = 1 + total_reviews)) +
  ggplot2::stat_ecdf(geom = "step", linewidth = 0.9, colour = "#2A6F97") +
  ggplot2::geom_vline(
    xintercept = c(10, 20, 100, 1000),
    colour = "#D97706", linewidth = 0.45, linetype = "dashed"
  ) +
  ggplot2::scale_x_log10(
    breaks = c(1, 11, 21, 101, 1001, 10001, 100001),
    labels = scales::comma(c(0, 10, 20, 100, 1000, 10000, 100000))
  ) +
  ggplot2::scale_y_continuous(labels = scales::percent) +
  ggplot2::labs(
    title = "Most games accumulate relatively few reviews",
    subtitle = "Empirical cumulative distribution; zero-review games are shown at the left boundary",
    x = "Total reviews (log scale)", y = "Cumulative share of games"
  ) +
  theme_steam_analysis()
save_eda_plot(p03, "03_review_count_ecdf.png")

review_payment_plot <- ggplot2::ggplot(
  games_market,
  ggplot2::aes(x = payment_segment, y = log10_reviews, fill = payment_segment)
) +
  ggplot2::geom_violin(trim = FALSE, alpha = 0.65, colour = NA) +
  ggplot2::geom_boxplot(width = 0.18, outlier.shape = NA, fill = "white") +
  ggplot2::scale_fill_manual(values = c("Free" = "#D97706", "Paid" = "#2A6F97")) +
  ggplot2::labs(
    title = "Free games in this launch cohort rarely clear the review threshold",
    x = NULL, y = expression(log[10](1 + total~reviews)), fill = NULL
  ) +
  theme_steam_analysis() +
  ggplot2::theme(legend.position = "none")

payment_selection_long <- payment_summary |>
  dplyr::select(payment_segment, zero_review_pct, model20_pct) |>
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

payment_selection_plot <- ggplot2::ggplot(
  payment_selection_long,
  ggplot2::aes(x = share_pct / 100, y = payment_segment, colour = metric)
) +
  ggplot2::geom_point(size = 3, position = ggplot2::position_dodge(width = 0.35)) +
  ggplot2::scale_colour_manual(
    values = c("Zero reviews" = "#64748B", "At least 20 reviews" = "#D97706")
  ) +
  ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(x = "Share within payment segment", y = NULL, colour = NULL) +
  theme_steam_analysis()

p04 <- review_payment_plot | payment_selection_plot
save_eda_plot(p04, "04_free_paid_review_volume.png", width = 11, height = 5.5)

p05 <- ggplot2::ggplot(reviewed_games, ggplot2::aes(x = positive_rate)) +
  ggplot2::geom_histogram(binwidth = 0.025, boundary = 0, fill = "#2A6F97", colour = "white") +
  ggplot2::scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(
    title = "Raw positive rates cluster toward the high end",
    subtitle = "Only the 2,241 games with at least one review are defined",
    x = "Positive review rate", y = "Games"
  ) +
  theme_steam_analysis()
save_eda_plot(p05, "05_positive_rate_distribution.png")

p06 <- ggplot2::ggplot(
  reviewed_games,
  ggplot2::aes(x = total_reviews, y = positive_rate)
) +
  ggplot2::geom_point(alpha = 0.25, size = 1.2, colour = "#2A6F97") +
  ggplot2::geom_smooth(
    method = "loess", formula = y ~ x, se = FALSE,
    linewidth = 0.8, colour = "#D97706"
  ) +
  ggplot2::scale_x_log10(labels = scales::comma) +
  ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(
    title = "Positive-rate extremes are concentrated at low review counts",
    subtitle = "Orange curve is a descriptive LOESS smoother, not a fitted research model",
    x = "Total reviews (log scale)", y = "Positive review rate"
  ) +
  theme_steam_analysis()
save_eda_plot(p06, "06_positive_rate_vs_reviews.png")

perfect_rate_summary <- reviewed_games |>
  dplyr::mutate(
    perfect_positive_rate = positive_rate == 1,
    count_group = factor(
      dplyr::case_when(
        total_reviews < 10 ~ "1-9",
        total_reviews < 20 ~ "10-19",
        total_reviews < 50 ~ "20-49",
        total_reviews < 100 ~ "50-99",
        TRUE ~ "100+"
      ),
      levels = c("1-9", "10-19", "20-49", "50-99", "100+")
    )
  ) |>
  dplyr::group_by(count_group) |>
  dplyr::summarise(
    games = dplyr::n(),
    perfect_games = sum(perfect_positive_rate),
    perfect_pct = 100 * mean(perfect_positive_rate),
    .groups = "drop"
  )

p07 <- ggplot2::ggplot(
  perfect_rate_summary,
  ggplot2::aes(x = count_group, y = perfect_games)
) +
  ggplot2::geom_col(fill = "#2A6F97") +
  ggplot2::geom_text(
    ggplot2::aes(label = paste0(perfect_games, " / ", games)),
    vjust = -0.3, size = 3.2
  ) +
  ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.1))) +
  ggplot2::labs(
    title = "Perfect raw rates are mostly a small-denominator pattern",
    subtitle = "Labels show perfect-rate games / reviewed games in each count group",
    x = "Review-count group", y = "Games with 100% positive reviews"
  ) +
  theme_steam_analysis()
save_eda_plot(p07, "07_perfect_rate_by_count_group.png")

wilson_targets <- c(1L, 5L, 20L, 50L, 100L)
wilson_rows <- do.call(
  rbind,
  lapply(wilson_targets, function(target) {
    reviewed_games |>
      dplyr::filter(positive_rate == 1) |>
      dplyr::mutate(distance = abs(total_reviews - target)) |>
      dplyr::arrange(distance, appid) |>
      dplyr::slice(1) |>
      dplyr::select(appid, name, total_reviews, positive_reviews, positive_rate)
  })
) |>
  dplyr::distinct(appid, .keep_all = TRUE)
intervals <- wilson_interval(wilson_rows$positive_reviews, wilson_rows$total_reviews)
wilson_examples <- dplyr::bind_cols(wilson_rows, intervals) |>
  dplyr::arrange(total_reviews)

p19 <- ggplot2::ggplot(
  wilson_examples,
  ggplot2::aes(x = total_reviews, y = positive_rate, ymin = lower, ymax = upper)
) +
  ggplot2::geom_linerange(linewidth = 0.8, colour = "#2A6F97") +
  ggplot2::geom_point(size = 2.4, colour = "#D97706") +
  ggplot2::scale_x_log10(labels = scales::comma) +
  ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  ggplot2::labs(
    title = "Wilson intervals expose low-count uncertainty",
    subtitle = "Observed 100% positive games near selected review counts; intervals are descriptive",
    x = "Total reviews (log scale)", y = "Positive rate with 95% Wilson interval"
  ) +
  theme_steam_analysis()
save_eda_plot(p19, "19_wilson_interval_examples.png")

utils::write.csv(
  perfect_rate_summary,
  file.path(r_analysis_dir, "perfect_rate_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  wilson_examples,
  file.path(r_analysis_dir, "wilson_examples.csv"),
  row.names = FALSE,
  na = ""
)

stopifnot(
  nrow(reviewed_games) == 2241,
  sum(perfect_rate_summary$perfect_games) == 832,
  all(wilson_examples$lower <= wilson_examples$positive_rate + 1e-12),
  all(wilson_examples$upper + 1e-12 >= wilson_examples$positive_rate)
)
