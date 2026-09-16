# Reproduce the pre-specified Step 5C robust models and influence sensitivity.

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
source(file.path(project_root, "R", "modeling", "06_robust_models.R"))
source(file.path(project_root, "R", "modeling", "07_influence_sensitivity.R"))

required_outputs <- c(
  "step5c_quasi_coefficients.csv", "step5c_quasi_fit.csv",
  "step5c_quasi_inflation.csv", "step5c_beta_binomial_fit.csv",
  "step5c_beta_binomial_coefficients.csv", "step5c_beta_dispersion.csv",
  "step5c_beta_diagnostics.csv", "step5c_quasi_inflation_summary.csv",
  "step5c_specification_audit.csv", "step5c_database_preservation.csv",
  "step5c_model_comparison.csv", "step5c_coefficient_comparison.csv",
  "step5c_direction_stability.csv", "step5c_influence_populations.csv",
  "step5c_influence_coefficients.csv", "step5c_coefficient_drift.csv",
  "step5c_review_mass_removed.csv", "step5c_predicted_effect_comparison.csv",
  "step5c_fit_warnings.csv"
)
required_figures <- sprintf("%02d_%s.png", 5:8, c(
  "robust_or_comparison", "ci_width_comparison",
  "influence_sensitivity_coefficients", "review_mass_removed"
))
stopifnot(
  all(file.exists(file.path(model_audit_dir, required_outputs))),
  all(file.exists(file.path(model_figure_dir, required_figures))),
  file.exists(file.path(project_root, "reports", "step5c_robust_reception_report.md"))
)
message(sprintf(
  "Step 5C robust modeling audit: PASS (%d required outputs, %d figures)",
  length(required_outputs), length(required_figures)
))
