#!/usr/bin/env Rscript

if (.Platform$OS.type == "windows") {
  invisible(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.936"))
}
source_candidates_6a1 <- function(paths) {
  path <- paths[file.exists(paths)][1]
  if (is.na(path)) stop("Required source file not found.", call. = FALSE)
  source(path, encoding = "UTF-8")
}

source_candidates_6a1(c(
  file.path("R", "attention", "00_attention_helpers.R"),
  file.path("attention", "00_attention_helpers.R")
))

write_model_audit_saved_6a1 <- write_model_audit
write_model_audit <- function(...) invisible(NULL)
source_candidates_6a1(c(
  file.path("R", "modeling", "01_prepare_model_data.R"),
  file.path("..", "modeling", "01_prepare_model_data.R")
))
write_model_audit <- write_model_audit_saved_6a1
rm(write_model_audit_saved_6a1)

for (script in c(
  "01_attention_data_audit.R", "02_entry_logistic.R", "03_functional_form_audit.R",
  "04_entry_diagnostics.R", "06z_nonlinear_alias.R", "07_nonlinear_price_basis.R",
  "08_nonlinear_entry_model.R", "09_nonlinear_diagnostics_sensitivity.R",
  "10_nonlinear_visuals.R", "11_nonlinear_report.R"
)) {
  source_candidates_6a1(c(
    file.path("R", "attention", script),
    file.path("attention", script)
  ))
}

message(sprintf(
  "Step 6A.1 nonlinear review-entry pipeline: %s",
  step6a1_stage_decision_6a1$step6a1_status
))
