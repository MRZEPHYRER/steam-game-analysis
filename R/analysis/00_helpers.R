# Shared Step 4B helpers: project paths, packages, factors, and plot export.

.helper_candidates <- c(
  file.path("R", "db_connect.R"),
  file.path("..", "db_connect.R"),
  file.path("..", "R", "db_connect.R")
)
.helper_path <- .helper_candidates[file.exists(.helper_candidates)][1]
if (is.na(.helper_path)) stop("Could not locate R/db_connect.R.", call. = FALSE)
source(.helper_path)

project_root <- find_project_root()
figure_dir <- file.path(project_root, "figures", "eda")
r_analysis_dir <- file.path(project_root, "data", "analysis", "r")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(r_analysis_dir, recursive = TRUE, showWarnings = FALSE)

required_packages <- c("dplyr", "tidyr", "ggplot2", "scales", "patchwork")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(paste("Missing R packages:", paste(missing_packages, collapse = ", ")), call. = FALSE)
}

theme_steam_analysis <- function() {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title.position = "plot",
      plot.title = ggplot2::element_text(face = "bold", colour = "#17324D"),
      plot.subtitle = ggplot2::element_text(colour = "#52677A"),
      axis.title = ggplot2::element_text(colour = "#17324D"),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "#E5EAF0", linewidth = 0.3),
      legend.position = "bottom",
      strip.text = ggplot2::element_text(face = "bold"),
      plot.caption = ggplot2::element_text(colour = "#64748B", hjust = 0)
    )
}

save_eda_plot <- function(plot, filename, width = 9, height = 5.5) {
  path <- file.path(figure_dir, filename)
  ggplot2::ggsave(
    filename = path,
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )
  invisible(path)
}

derive_price_band <- function(is_free, current_price_usd) {
  value <- dplyr::case_when(
    is_free == 1 ~ "Free",
    is.na(current_price_usd) ~ "Paid price missing",
    current_price_usd < 5 ~ "$0.01-$4.99",
    current_price_usd < 10 ~ "$5.00-$9.99",
    current_price_usd < 20 ~ "$10.00-$19.99",
    current_price_usd < 30 ~ "$20.00-$29.99",
    TRUE ~ "$30.00+"
  )
  factor(
    value,
    levels = c(
      "Free", "$0.01-$4.99", "$5.00-$9.99", "$10.00-$19.99",
      "$20.00-$29.99", "$30.00+", "Paid price missing"
    )
  )
}

derive_platform_segment <- function(windows, mac, linux) {
  value <- dplyr::case_when(
    windows == 1 & mac == 0 & linux == 0 ~ "Windows only",
    windows == 1 & mac == 1 & linux == 0 ~ "Windows + macOS",
    windows == 1 & mac == 0 & linux == 1 ~ "Windows + Linux",
    windows == 1 & mac == 1 & linux == 1 ~ "Windows + macOS + Linux",
    TRUE ~ "Other"
  )
  factor(
    value,
    levels = c(
      "Windows only", "Windows + macOS", "Windows + Linux",
      "Windows + macOS + Linux", "Other"
    )
  )
}

wilson_interval <- function(successes, trials, z = 1.96) {
  p <- successes / trials
  denominator <- 1 + z^2 / trials
  centre <- (p + z^2 / (2 * trials)) / denominator
  margin <- z * sqrt((p * (1 - p) + z^2 / (4 * trials)) / trials) / denominator
  data.frame(lower = centre - margin, upper = centre + margin)
}
