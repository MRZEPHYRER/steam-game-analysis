#!/usr/bin/env Rscript
source_candidates_6b <- function(paths) {
  path <- paths[file.exists(paths)][1]
  if (is.na(path)) stop("Required Step 6B source not found.", call. = FALSE)
  source(path, encoding = "UTF-8")
}
source_candidates_6b(c("R/attention/00_attention_helpers.R", "attention/00_attention_helpers.R"))
write_model_audit_saved_6b <- write_model_audit
write_model_audit <- function(...) invisible(NULL)
source_candidates_6b(c("R/modeling/01_prepare_model_data.R", "../modeling/01_prepare_model_data.R"))
write_model_audit <- write_model_audit_saved_6b
rm(write_model_audit_saved_6b)
games_market_wide$platform_segment <- factor(as.character(
  games_market_wide$platform_segment), levels = c("Windows only",
  "Windows + macOS", "Windows + Linux", "Windows + macOS + Linux"))
for (script in c("12_count_data.R", "12a_free_price_handling.R",
                 "12b_count_population_cleanup.R", "13_count_models.R",
                 "13a_truncated_prediction_contract.R", "14_count_outputs.R",
                 "15_count_diagnostics.R", "16_count_sensitivity.R",
                 "17_count_visuals.R", "18_count_report.R")) {
  source_candidates_6b(c(file.path("R", "attention", script), file.path("attention", script)))
}
message(sprintf("Step 6B positive review-count pipeline: %s", step6b_decision$status))
