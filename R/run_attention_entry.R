#!/usr/bin/env Rscript

if (.Platform$OS.type == "windows") {
  invisible(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.936"))
}
source_candidates_6a <- function(paths) {
  path <- paths[file.exists(paths)][1]
  if (is.na(path)) stop("Required source file not found.", call. = FALSE)
  source(path, encoding = "UTF-8")
}
source_candidates_6a(c(file.path("R", "attention", "00_attention_helpers.R"), file.path("attention", "00_attention_helpers.R")))

write_model_audit_saved_6a <- write_model_audit
write_model_audit <- function(...) invisible(NULL)
source_candidates_6a(c(file.path("R", "modeling", "01_prepare_model_data.R"), file.path("..", "modeling", "01_prepare_model_data.R")))
write_model_audit <- write_model_audit_saved_6a
rm(write_model_audit_saved_6a)

for (script in c(
  "01_attention_data_audit.R", "02_entry_logistic.R", "03_functional_form_audit.R",
  "04_entry_diagnostics.R", "05_entry_visuals.R", "06_entry_report.R"
)) {
  source_candidates_6a(c(file.path("R", "attention", script), file.path("attention", script)))
}
message("Step 6A attention-entry pipeline: PASS")
