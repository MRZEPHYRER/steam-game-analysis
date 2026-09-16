# Reproduce the pre-specified Step 5D one-at-a-time sensitivity analysis.

.script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
.script_dir <- if (length(.script_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", .script_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath("R", mustWork = TRUE)
}

source(file.path(.script_dir, "modeling", "00_model_helpers.R"))
source(file.path(project_root, "R", "modeling", "01_prepare_model_data.R"))
source(file.path(project_root, "R", "modeling", "08_sensitivity_analysis.R"))
if (.Platform$OS.type == "windows") {
  invisible(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.936"))
}
source(
  file.path(project_root, "R", "modeling", "09_sensitivity_visuals.R"),
  encoding = "UTF-8"
)

required_outputs <- c(
  "step5d_threshold_samples.csv", "step5d_threshold_exclusions.csv",
  "step5d_threshold_appids.csv", "step5d_threshold_fit.csv",
  "step5d_threshold_coefficients.csv", "step5d_threshold_stability.csv",
  "step5d_release_fit.csv", "step5d_release_coefficients.csv",
  "step5d_release_comparison.csv", "step5d_price_fit.csv",
  "step5d_price_coefficients.csv", "step5d_price_comparison.csv",
  "step5d_price_predicted_contrasts.csv", "step5d_genre_fit.csv",
  "step5d_genre_coefficients.csv", "step5d_genre_comparison.csv",
  "step5d_master_specification_table.csv", "step5d_core_predictor_stability.csv",
  "step5d_direction_matrix.csv", "step5d_diagnostics.csv",
  "step5d_fit_warnings.csv", "step5d_formula_audit.csv",
  "step5d_database_preservation.csv"
)
required_figures <- sprintf("%02d_%s.png", 9:18, c(
  "threshold_or_comparison", "threshold_coefficient_drift",
  "release_specification_comparison", "release_month_effects",
  "price_specification_comparison", "genre_specification_comparison",
  "robustness_heatmap", "or_range_summary",
  "simulation_sensitivity", "price_sensitivity"
))

diagnostics <- read.csv(
  file.path(model_audit_dir, "step5d_diagnostics.csv"),
  check.names = FALSE
)
threshold_samples <- read.csv(
  file.path(model_audit_dir, "step5d_threshold_samples.csv"),
  check.names = FALSE
)

stopifnot(
  all(file.exists(file.path(model_audit_dir, required_outputs))),
  all(file.exists(file.path(model_figure_dir, required_figures))),
  file.exists(file.path(project_root, "reports", "step5d_sensitivity_report.md")),
  file.exists(file.path(project_root, "reports", "04_sensitivity_visual_audit.qmd")),
  nrow(diagnostics) == 7,
  all(diagnostics$convergence_code == 0),
  all(diagnostics$converged),
  all(diagnostics$positive_definite_hessian),
  all(diagnostics$warning_count == 0),
  identical(threshold_samples$n_games, c(2206L, 1127L, 836L, 548L))
)

message(sprintf(
  paste0(
    "Step 5D sensitivity audit: PASS (%d specifications, %d required outputs, ",
    "%d figures)"
  ),
  nrow(diagnostics), length(required_outputs), length(required_figures)
))
