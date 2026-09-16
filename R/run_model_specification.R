# Reproduce all Step 5A model specification and data audits.

.script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
.script_dir <- if (length(.script_arg) > 0) {
  dirname(normalizePath(sub("^--file=", "", .script_arg[[1]]), mustWork = TRUE))
} else {
  normalizePath("R", mustWork = TRUE)
}

source(file.path(.script_dir, "modeling", "00_model_helpers.R"))
source(file.path(project_root, "R", "modeling", "01_prepare_model_data.R"))
source(file.path(project_root, "R", "modeling", "02_model_specification_audit.R"))
source(file.path(project_root, "R", "modeling", "03_genre_design_audit.R"))

required_outputs <- c(
  "sample_flow.csv",
  "sample_threshold_summary.csv",
  "model20_population_audit.csv",
  "price_audit.csv",
  "release_timing_audit.csv",
  "platform_frequency.csv",
  "genre_frequency.csv",
  "genre_cooccurrence.csv",
  "genre_correlation.csv",
  "design_matrix_diagnostics.csv",
  "reception_distribution.csv",
  "review_concentration.csv",
  "top_review_contributors.csv",
  "missingness_model_fields.csv",
  "sparse_cells.csv"
)
stopifnot(all(file.exists(file.path(model_audit_dir, required_outputs))))
message(sprintf("Step 5A model specification audit: PASS (%d required outputs)", length(required_outputs)))
