# Five portfolio-ready figures; no additional model search.
plot_png_6b1 <- function(filename, draw) {
  grDevices::png(file.path(attention_figure_dir, filename),
    width = 1400, height = 900, res = 160)
  tryCatch(draw(), finally = grDevices::dev.off())
}

plot_png_6b1("64_attention_tier_distribution.png", function() {
  bars <- barplot(tier_distribution_6b1$percent,
    names.arg = tier_distribution_6b1$attention_tier,
    col = c("#DCEAF2", "#93BDD2", "#4F8EAD", "#165E82"),
    ylim = c(0, max(tier_distribution_6b1$percent) * 1.18),
    ylab = "Percent of reviewed games", xlab = "Attention tier",
    main = "Attention-tier distribution among reviewed games")
  text(bars, tier_distribution_6b1$percent,
    labels = sprintf("%d\n%.1f%%", tier_distribution_6b1$n_games,
      tier_distribution_6b1$percent), pos = 3, cex = .9)
})

plot_png_6b1("65_attention_tier_price_probabilities.png", function() {
  matplot(price_tier_probabilities_6b1$price_usd,
    price_tier_probabilities_6b1[, tier_levels_6b1], type = "b",
    pch = 15:18, lty = 1:4, lwd = 2.5,
    col = c("#777777", "#4F8EAD", "#C47A2C", "#8A4F7D"),
    ylim = c(0, 1), xlab = "Current paid price (USD)",
    ylab = "Predicted probability", main = "Predicted attention-tier probability by paid price")
  legend("right", legend = tier_levels_6b1, pch = 15:18, lty = 1:4,
    lwd = 2.5, col = c("#777777", "#4F8EAD", "#C47A2C", "#8A4F7D"), bty = "n")
  mtext(sprintf("Paid reference; %d days; Windows only; genres absent",
    price_tier_probabilities_6b1$days_since_release[1]), side = 3, cex = .8)
})

pretty_term_6b1 <- function(x) {
  x <- sub("platform_segment", "Platform: ", x, fixed = TRUE)
  x <- sub("genre_", "Genre: ", x, fixed = TRUE)
  x <- sub("log_days", "Log days", x, fixed = TRUE)
  x <- sub("is_free", "Free", x, fixed = TRUE)
  x
}
ordinal_plot_6b1 <- ordinal_coefficients_6b1[
  !ordinal_coefficients_6b1$term %in% price_terms_6b1, ]
plot_png_6b1("66_attention_tier_or.png", function() {
  par(mar = c(5, 17, 4, 2) + .1)
  o <- order(ordinal_plot_6b1$odds_ratio_higher_tier)
  d <- ordinal_plot_6b1[o, ]; y <- seq_len(nrow(d))
  plot(d$odds_ratio_higher_tier, y, log = "x", pch = 19, yaxt = "n",
    xlim = range(c(d$ci95_lower, d$ci95_upper, 1)), xlab = "Odds ratio for higher tier (log scale)",
    ylab = "", main = "Ordinal logistic associations")
  segments(d$ci95_lower, y, d$ci95_upper, y, lwd = 2, col = "#165E82")
  points(d$odds_ratio_higher_tier, y, pch = 19, col = "#165E82")
  axis(2, at = y, labels = pretty_term_6b1(d$term), las = 2, cex.axis = .72)
  abline(v = 1, lty = 2)
})

high_plot_6b1 <- high100_coefficients_6b1[
  high100_coefficients_6b1$term != "(Intercept)" &
    !high100_coefficients_6b1$term %in% price_terms_6b1, ]
plot_png_6b1("67_high100_logistic_or.png", function() {
  par(mar = c(5, 17, 4, 2) + .1)
  o <- order(high_plot_6b1$odds_ratio_high100); d <- high_plot_6b1[o, ]; y <- seq_len(nrow(d))
  plot(d$odds_ratio_high100, y, log = "x", pch = 17, yaxt = "n",
    xlim = range(c(d$ci95_lower, d$ci95_upper, 1)), xlab = "Odds ratio for at least 100 reviews (log scale)",
    ylab = "", main = "High-100 logistic robustness model")
  segments(d$ci95_lower, y, d$ci95_upper, y, lwd = 2, col = "#C47A2C")
  points(d$odds_ratio_high100, y, pch = 17, col = "#C47A2C")
  axis(2, at = y, labels = pretty_term_6b1(d$term), las = 2, cex.axis = .72)
  abline(v = 1, lty = 2)
})

compare_plot_6b1 <- direction_comparison_6b1[
  !direction_comparison_6b1$term %in% price_terms_6b1, ]
plot_png_6b1("68_ordinal_vs_high100_direction.png", function() {
  par(mar = c(5, 17, 4, 2) + .1)
  o <- order(compare_plot_6b1$estimate_log_odds_ordinal)
  d <- compare_plot_6b1[o, ]; y <- seq_len(nrow(d))
  lim <- range(c(d$estimate_log_odds_ordinal, d$estimate_log_odds_high100, 0))
  plot(d$estimate_log_odds_ordinal, y, pch = 19, col = "#165E82",
    yaxt = "n", xlim = lim, xlab = "Log odds coefficient", ylab = "",
    main = "Ordinal and High-100 direction comparison")
  segments(d$estimate_log_odds_ordinal, y, d$estimate_log_odds_high100, y,
    col = "gray60", lwd = 2)
  points(d$estimate_log_odds_high100, y, pch = 17, col = "#C47A2C")
  axis(2, at = y, labels = pretty_term_6b1(d$term), las = 2, cex.axis = .72)
  abline(v = 0, lty = 2)
  legend("bottomright", c("Ordinal", "High-100"), pch = c(19, 17),
    col = c("#165E82", "#C47A2C"), bty = "n")
})
