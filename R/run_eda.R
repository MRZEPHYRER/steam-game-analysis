# Reproduce all Step 4B data checks, summaries, and figures in one R session.

.script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
.script_dir <- if (length(.script_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", .script_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath("R", mustWork = TRUE)
}
source(file.path(.script_dir, "analysis", "00_helpers.R"))
source(file.path(project_root, "R", "analysis", "01_load_data.R"))
source(file.path(project_root, "R", "analysis", "02_market_eda.R"))
source(file.path(project_root, "R", "analysis", "03_review_eda.R"))
source(file.path(project_root, "R", "analysis", "04_price_eda.R"))
source(file.path(project_root, "R", "analysis", "05_genre_eda.R"))
source(file.path(project_root, "R", "analysis", "06_sample_selection.R"))
source(file.path(project_root, "R", "analysis", "07_model_preparation.R"))

expected_figures <- sprintf("%02d_", 1:20)
actual_figures <- list.files(figure_dir, pattern = "\\.png$", full.names = FALSE)
stopifnot(all(vapply(expected_figures, function(prefix) any(startsWith(actual_figures, prefix)), logical(1))))
message("Step 4B R EDA: PASS (20 figures)")
