#!/usr/bin/env Rscript

source_candidates_6b1 <- function(paths) {
  path <- paths[file.exists(paths)][1]
  if (is.na(path)) stop("Required Step 6B.1 source not found.", call. = FALSE)
  source(path, encoding = "UTF-8")
}

source_candidates_6b1(c("R/attention/00_attention_helpers.R", "attention/00_attention_helpers.R"))
write_model_audit_saved_6b1 <- write_model_audit
write_model_audit <- function(...) invisible(NULL)
source_candidates_6b1(c("R/modeling/01_prepare_model_data.R", "../modeling/01_prepare_model_data.R"))
write_model_audit <- write_model_audit_saved_6b1
rm(write_model_audit_saved_6b1)

for (script in c("19_tier_data.R", "20_tier_models.R", "21_tier_diagnostics.R",
                 "22_tier_visuals.R", "23_tier_report.R")) {
  source_candidates_6b1(c(file.path("R", "attention", script), file.path("attention", script)))
}
message(sprintf("Step 6B.1 attention-tier pipeline: %s", step6b1_decision$status))
