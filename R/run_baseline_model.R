# Reproduce the frozen Step 5B grouped-binomial baseline and diagnostics.

.script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
.script_dir <- if (length(.script_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", .script_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath("R", mustWork = TRUE)
}

source(file.path(.script_dir, "modeling", "00_model_helpers.R"))
source(file.path(project_root, "R", "modeling", "01_prepare_model_data.R"))
source(file.path(project_root, "R", "modeling", "04_baseline_binomial.R"))
source(file.path(project_root, "R", "modeling", "05_baseline_diagnostics.R"))

required_outputs <- c(
  "step5b_model_fit_summary.csv",
  "step5b_coefficients.csv",
  "step5b_profile_ci.csv",
  "step5b_scaling_parameters.csv",
  "step5b_predicted_effects.csv",
  "step5b_dispersion_diagnostics.csv",
  "step5b_residual_summary.csv",
  "step5b_top_residuals.csv",
  "step5b_leverage_summary.csv",
  "step5b_top_leverage.csv",
  "step5b_cooks_summary.csv",
  "step5b_top_influence.csv",
  "step5b_collinearity.csv",
  "step5b_matrix_diagnostics.csv",
  "step5b_fitted_probability_summary.csv",
  "step5b_calibration_deciles.csv",
  "step5b_review_influence_association.csv",
  "step5b_fit_warnings.csv"
)
required_figures <- sprintf("%02d_%s.png", 1:4, c(
  "baseline_calibration", "residuals_vs_fitted",
  "influence_review_volume", "baseline_odds_ratios"
))
stopifnot(
  all(file.exists(file.path(model_audit_dir, required_outputs))),
  all(file.exists(file.path(model_figure_dir, required_figures))),
  file.exists(file.path(project_root, "reports", "step5b_baseline_binomial_report.md"))
)
message(sprintf(
  "Step 5B baseline binomial audit: PASS (%d required outputs, %d figures)",
  length(required_outputs), length(required_figures)
))
