#!/usr/bin/env Rscript

# Build only presentation assets for Step 7A. No models are fitted here.

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg) > 0) sub("^--file=", "", file_arg[[1]]) else "R/build_full_report_assets.R"
root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
fig_dir <- file.path(root, "figures", "report")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("ggplot2 is required for Step 7A presentation assets.", call. = FALSE)
}
library(ggplot2)

save_plot <- function(plot, name, width = 11, height = 6.5) {
  ggsave(file.path(fig_dir, name), plot, width = width, height = height,
         units = "in", dpi = 180, bg = "white")
}

# 69 — analysis pipeline
png(file.path(fig_dir, "69_analysis_pipeline.png"), width = 1800, height = 1050,
    res = 180, bg = "white")
par(mar = c(0, 0, 0, 0), xpd = NA)
plot.new()
nodes <- data.frame(
  x = c(0.17, 0.50, 0.83, 0.17, 0.50, 0.83, 0.17, 0.50, 0.83),
  y = c(0.82, 0.82, 0.82, 0.58, 0.58, 0.58, 0.34, 0.34, 0.34),
  label = c(
    "Steam catalog / Store API / Review API", "Python collection & ETL", "3,000-game\nstratified sample",
    "MySQL analytical database", "SQL exploration", "R EDA",
    "Reception models", "Attention models", "Wilson / Empirical Bayes\nQuarto reports"
  ),
  col = c("#dbeafe", "#e0f2fe", "#dcfce7", "#fef3c7", "#fef3c7", "#fef3c7", "#fce7f3", "#fce7f3", "#ede9fe")
)
for (i in seq_len(nrow(nodes))) {
  rect(nodes$x[i] - 0.12, nodes$y[i] - 0.065, nodes$x[i] + 0.12, nodes$y[i] + 0.065,
       col = nodes$col[i], border = "#334155", lwd = 1.5)
  text(nodes$x[i], nodes$y[i], nodes$label[i], cex = 1.05, font = 2, col = "#0f172a")
}
edge_arrow <- function(i, j) {
  x1 <- nodes$x[i]; y1 <- nodes$y[i]; x2 <- nodes$x[j]; y2 <- nodes$y[j]
  if (abs(y1 - y2) < 1e-8) {
    x_start <- x1 + sign(x2 - x1) * 0.125
    x_end <- x2 - sign(x2 - x1) * 0.125
    y_start <- y_end <- y1
  } else {
    x_start <- x1; x_end <- x2
    y_start <- y1 - sign(y1 - y2) * 0.07
    y_end <- y2 + sign(y1 - y2) * 0.07
  }
  arrows(x_start, y_start, x_end, y_end, length = 0.10, angle = 25,
         code = 2, col = "#64748b", lwd = 2)
}
for (a in list(c(1, 2), c(2, 3), c(3, 6), c(6, 5), c(5, 4), c(4, 7), c(7, 8), c(8, 9))) {
  edge_arrow(a[1], a[2])
}
text(0.5, 0.08, "Reproducible path from collection to statistical interpretation", cex = 1.25,
     font = 3, col = "#475569")
dev.off()

# 70 — cross-domain direction summary
cross <- data.frame(
  predictor = c("Price", "Simulation", "Strategy", "Multi-platform", "RPG", "Adventure"),
  Attention = c("Higher-tier tendency", "Positive", "Uncertain / slight negative", "Positive", "Positive", "Positive"),
  Reception = c("Weak negative", "Negative", "Negative", "Positive", "Uncertain", "Uncertain"),
  att_score = c(1, 1, 0, 1, 1, 1),
  rec_score = c(-1, -1, -1, 1, 0, 0)
)
long <- rbind(
  data.frame(predictor = cross$predictor, domain = "Attention tier", score = cross$att_score, label = cross$Attention),
  data.frame(predictor = cross$predictor, domain = "Reception", score = cross$rec_score, label = cross$Reception)
)
long$predictor <- factor(long$predictor, levels = rev(cross$predictor))
long$domain <- factor(long$domain, levels = c("Attention tier", "Reception"))
long$fill <- factor(long$score, levels = c(-1, 0, 1), labels = c("Negative", "Uncertain", "Positive"))
p70 <- ggplot(long, aes(domain, predictor, fill = fill)) +
  geom_tile(color = "white", linewidth = 1.2, width = 0.94, height = 0.88) +
  geom_text(aes(label = label), color = "#0f172a", size = 3.8, lineheight = 0.9) +
  scale_fill_manual(values = c(Negative = "#f6ad8f", Uncertain = "#e2e8f0", Positive = "#a7d8bd"), drop = FALSE) +
  labs(title = "Attention and reception describe different dimensions",
       subtitle = "Direction only; odds-ratio magnitudes are not compared across outcomes",
       x = NULL, y = NULL, fill = NULL) +
  theme_minimal(base_size = 14) +
  theme(panel.grid = element_blank(), legend.position = "bottom",
        plot.title = element_text(face = "bold"), axis.text = element_text(color = "#0f172a"))
save_plot(p70, "70_attention_vs_reception_summary.png", 10.5, 6.5)

# 71 — model decision map
png(file.path(fig_dir, "71_model_decision_map.png"), width = 1800, height = 1200,
    res = 180, bg = "white")
par(mar = c(0, 0, 0, 0), xpd = NA)
plot.new()
segments <- list(
  list(y = 0.84, label = "Positive rate", col = "#dbeafe"),
  list(y = 0.70, label = "Binomial\noverdispersion", col = "#fee2e2"),
  list(y = 0.56, label = "Beta-binomial\nreception model", col = "#dcfce7"),
  list(y = 0.39, label = "Raw review count\nlong tail", col = "#dbeafe"),
  list(y = 0.25, label = "Poisson -> NB2 ->\ntruncated NB2 diagnostics", col = "#fee2e2"),
  list(y = 0.11, label = "Attention tiers ->\nordinal logistic", col = "#ede9fe")
)
for (s in segments) {
  rect(0.28, s$y - 0.045, 0.72, s$y + 0.045, col = s$col, border = "#334155", lwd = 1.5)
  text(0.50, s$y, s$label, cex = 1.15, font = 2, col = "#0f172a")
}
arrows(0.5, 0.79, 0.5, 0.75, length = 0.10, code = 2, lwd = 2, col = "#64748b")
arrows(0.5, 0.65, 0.5, 0.61, length = 0.10, code = 2, lwd = 2, col = "#64748b")
arrows(0.5, 0.51, 0.5, 0.44, length = 0.10, code = 2, lwd = 2, col = "#64748b")
arrows(0.5, 0.34, 0.5, 0.30, length = 0.10, code = 2, lwd = 2, col = "#64748b")
arrows(0.5, 0.20, 0.5, 0.16, length = 0.10, code = 2, lwd = 2, col = "#64748b")
text(0.11, 0.56, "retain denominator", cex = 0.95, col = "#475569")
text(0.11, 0.25, "diagnose before freezing", cex = 0.95, col = "#475569")
text(0.89, 0.56, "heterogeneity", cex = 0.95, col = "#475569")
text(0.89, 0.11, "change estimand", cex = 0.95, col = "#475569")
text(0.5, 0.95, "Model decisions followed the estimand and diagnostics", cex = 1.35,
     font = 2, col = "#0f172a")
dev.off()

message("Step 7A presentation assets: PASS (3 figures)")
