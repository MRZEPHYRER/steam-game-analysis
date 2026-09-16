#!/usr/bin/env Rscript

# Step 5F reproducible entry point. Database access remains read-only.
if (.Platform$OS.type == "windows") {
  invisible(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.936"))
}

source_candidates <- function(paths) {
  path <- paths[file.exists(paths)][1]
  if (is.na(path)) stop("Required source file not found.", call. = FALSE)
  source(path, encoding = "UTF-8")
}

source_candidates(c(
  file.path("R", "modeling", "00_model_helpers.R"),
  file.path("modeling", "00_model_helpers.R")
))

# Step 5A preparation writes an already-frozen mapping as a side effect. Suppress
# that write so this runner creates only Step 5F outputs.
write_model_audit_5f <- write_model_audit
write_model_audit <- function(...) invisible(NULL)
source_candidates(c(
  file.path("R", "modeling", "01_prepare_model_data.R"),
  file.path("modeling", "01_prepare_model_data.R")
))
write_model_audit <- write_model_audit_5f
rm(write_model_audit_5f)

for (script in c(
  "14_wilson_rating.R",
  "15_empirical_bayes_rating.R",
  "16_rating_adjustment_visuals.R",
  "17_rating_adjustment_report.R"
)) {
  source_candidates(c(
    file.path("R", "modeling", script),
    file.path("modeling", script)
  ))
}

message("Step 5F analysis pipeline: PASS")
