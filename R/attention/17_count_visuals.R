# Static scientific figures for the Chinese Step 6B visual audit.
plot_png_6b <- function(filename, draw) {
  path <- file.path(attention_figure_dir, filename)
  grDevices::png(path, width = 1400, height = 900, res = 160)
  tryCatch(draw(), finally = grDevices::dev.off())
  invisible(path)
}
plot_png_6b("53_review_count_price_curve.png", function() {
  plot(price_curve_6b$price_usd, price_curve_6b$predicted_positive_count,
    type = "l", lwd = 3, col = "#166088", log = "y", xlab = "Current paid price (USD)",
    ylab = "Predicted reviews among games with reviews (log scale)",
    main = "Positive-count price curve, reference paid game")
  abline(v = c(basis_definition_6b$price_p05_usd,
    basis_definition_6b$price_p95_usd), lty = 2, col = "gray50")
  mtext(sprintf("Reference days = %.0f; dashed lines = paid 5th/95th percentiles",
    ref_days_6b), side = 3, line = .2, cex = .8)
})
plot_png_6b("54_review_count_exposure_curve.png", function() {
  matplot(exposure_curve_6b$days, exposure_curve_6b[, -1], type = "l", lty = 1:3,
    col = c("#166088", "#B65D26", "#25805A"), lwd = 3,
    xlab = "Days since release", ylab = "Predicted positive review count",
    main = "Exposure-time specification comparison")
  legend("topleft", legend = c("Log-days covariate", "Strict offset", "Spline log-days"),
    lty = 1:3, lwd = 3, col = c("#166088", "#B65D26", "#25805A"), bty = "n")
})
plot_png_6b("55_count_rootogram.png", function() {
  at <- seq_len(nrow(fit_bins_6b))
  plot(at, fit_bins_6b$sqrt_observed, pch = 19, cex = 1.5,
    xaxt = "n", ylim = range(c(fit_bins_6b$sqrt_observed,
      fit_bins_6b$sqrt_expected)), xlab = "Positive review-count bin",
    ylab = "Square root of game count", main = "Observed and fitted count-bin frequency")
  axis(1, at = at, labels = fit_bins_6b$bin, las = 2)
  lines(at, fit_bins_6b$sqrt_expected, col = "#B65D26", lwd = 3)
  legend("topright", c("Observed", "Truncated NB2 expected"),
    pch = c(19, NA), lty = c(NA, 1), col = c("black", "#B65D26"), bty = "n")
})
plot_png_6b("56_poisson_vs_nb_fit.png", function() {
  fit_poisson <- as.numeric(stats::fitted(poisson_fit_6b))
  fit_nb <- as.numeric(stats::fitted(nb_fit_6b))
  plot(log10(y_6b), log10(pmax(fit_poisson, 1e-8)), pch = 16,
    col = grDevices::adjustcolor("#B65D26", alpha.f = .2),
    xlab = "Observed log10 review count", ylab = "Fitted log10 count",
    main = "Poisson and NB2 fitted means")
  points(log10(y_6b), log10(pmax(fit_nb, 1e-8)), pch = 16,
    col = grDevices::adjustcolor("#166088", alpha.f = .2))
  abline(0, 1, lty = 2)
  legend("topleft", c("Poisson", "Ordinary NB2"), pch = 16,
    col = c("#B65D26", "#166088"), bty = "n")
})
plot_png_6b("57_nb_residual_diagnostics.png", function() {
  plot(log10(mean_positive_6b), pearson_6b, pch = 16,
    col = grDevices::adjustcolor("#166088", alpha.f = .3),
    xlab = "Fitted positive-count mean (log10)", ylab = "Conditional Pearson residual",
    main = "Truncated NB2 residual audit")
  abline(h = 0, lty = 2); abline(h = c(-3, 3), lty = 3, col = "gray50")
})
plot_png_6b("58_tail_concentration.png", function() {
  ordered <- sort(y_all_6b)
  share_games <- c(0, seq_along(ordered) / length(ordered))
  share_reviews <- c(0, cumsum(ordered) / sum(ordered))
  plot(share_games, share_reviews, type = "l", lwd = 3, col = "#166088",
    xlab = "Cumulative share of positive-count games",
    ylab = "Cumulative share of reviews", main = "Review-volume concentration")
  abline(0, 1, lty = 2)
  legend("topleft", sprintf("Gini = %.3f", concentration_6b$gini), bty = "n")
})
plot_png_6b("59_tail_sensitivity_coefficients.png", function() {
  d <- coefficient_sensitivity_6b
  terms <- unique(d$term)
  mat <- sapply(unique(d$scenario), function(id)
    d$relative_ratio_drift[d$scenario == id][match(terms, d$term[d$scenario == id])])
  matplot(seq_along(terms), mat, type = "b", pch = 1:3, lty = 1:3,
    xaxt = "n", xlab = "Non-spline term", ylab = "Absolute relative ratio drift",
    main = "Coefficient sensitivity to removing head games")
  axis(1, at = seq_along(terms), labels = terms, las = 2, cex.axis = .7)
  legend("topright", legend = unique(d$scenario), lty = 1:3, pch = 1:3, bty = "n")
})
plot_png_6b("60_price_curve_tail_sensitivity.png", function() {
  d <- price_curve_tail_points_6b
  matplot(d$price_usd, d[, -1], type = "l", lty = 1:3, lwd = 3,
    col = c("#166088", "#B65D26", "#25805A"), xlab = "Paid price (USD), central support",
    ylab = "Predicted positive review count", main = "Price-curve head-tail sensitivity")
  legend("topright", c("Full", "Remove top 1%", "Remove top 5%"),
    lty = 1:3, lwd = 3, col = c("#166088", "#B65D26", "#25805A"), bty = "n")
})
plot_png_6b("61_platform_review_volume.png", function() {
  boxplot(log10(review_count) ~ platform_segment, data = positive_all_6b,
    las = 2, col = "#BBD5E2", xlab = "Platform segment",
    ylab = "log10 positive review count", main = "Positive review volume by platform")
})
plot_png_6b("62_genre_review_volume.png", function() {
  d <- genre_summary_6b[order(genre_summary_6b$mean_count, decreasing = TRUE), ]
  barplot(d$mean_count, names.arg = d$genre, las = 2, col = "#166088",
    ylab = "Mean positive review count", main = "Raw review volume by genre (overlapping genres)")
})
plot_png_6b("63_hurdle_decomposition.png", function() {
  par(mfrow = c(1, 2))
  barplot(c(zero_n_6b / market_n_6b, nrow(positive_all_6b) / market_n_6b),
    names.arg = c("Zero reviews", "At least one"), col = c("gray65", "#166088"),
    ylim = c(0, 1), ylab = "Market share", main = "Part 1: review entry")
  barplot(c(mean(y_all_6b), mean(games_market_wide$total_reviews)),
    names.arg = c("Among positive", "Across market"), col = c("#25805A", "#B65D26"),
    ylab = "Raw mean review count", main = "Part 2: count intensity")
  mtext("Descriptive identity only; not combined model predictions", outer = TRUE,
    side = 1, line = -1, cex = .8)
  par(mfrow = c(1, 1))
})
