#!/usr/bin/env Rscript

# Step 5E reproducible entry point. Database access remains read-only.
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

# Step 5A preparation writes one already-frozen mapping as a side effect. Suppress
# that write here so Step 5E only creates its own machine-readable outputs.
write_model_audit_5e <- write_model_audit
write_model_audit <- function(...) invisible(NULL)
source_candidates(c(
  file.path("R", "modeling", "01_prepare_model_data.R"),
  file.path("modeling", "01_prepare_model_data.R")
))
write_model_audit <- write_model_audit_5e
rm(write_model_audit_5e)

source_candidates(c(
  file.path("R", "modeling", "10_high_rating_logistic.R"),
  file.path("modeling", "10_high_rating_logistic.R")
))
source_candidates(c(
  file.path("R", "modeling", "11_high_rating_diagnostics.R"),
  file.path("modeling", "11_high_rating_diagnostics.R")
))
source_candidates(c(
  file.path("R", "modeling", "12_high_rating_visuals.R"),
  file.path("modeling", "12_high_rating_visuals.R")
))

fmt <- function(x, digits = 4) formatC(x, digits = digits, format = "f")
primary_fit_row <- primary_high_rating_fit_summary[1, ]
distribution_lines <- vapply(seq_len(nrow(outcome_distribution)), function(i) {
  row <- outcome_distribution[i, ]
  paste0(
    "- ", row$model_id, ": ", row$high_rated_n, "/", row$n_total,
    " (", fmt(row$high_rated_percent, 2), "%); exact boundary = ",
    row$exact_boundary_n
  )
}, character(1))
primary_or_lines <- vapply(
  seq_len(nrow(primary_high_rating_coefficients)),
  function(i) {
    row <- primary_high_rating_coefficients[i, ]
    paste0(
      "- `", row$term, "`: OR ", fmt(row$odds_ratio),
      " (95% CI ", fmt(row$or_ci95_lower), " to ",
      fmt(row$or_ci95_upper), "); direction ", row$direction
    )
  },
  character(1)
)
stability_counts <- table(rating_threshold_stability$stability_class)
direction_agree_n <- sum(beta_logistic_direction_comparison$direction_agreement)
direction_total_n <- nrow(beta_logistic_direction_comparison)

technical_report <- c(
  "# Step 5E Secondary High-Rating Logistic Analysis",
  "",
  "## Scope and hierarchy",
  "",
  paste(
    "The Beta-binomial remains the primary inferential model. Step 5E is a",
    "secondary, business-readable game-level threshold analysis. Each game",
    "contributes one binary observation, so a 20-review game and a",
    "100,000-review game receive equal likelihood weight."
  ),
  "",
  paste(
    "The 85% threshold is a pre-specified, business-readable cutoff rather",
    "than a natural scientific boundary. HIGH80 and HIGH90 are fixed",
    "sensitivity analyses; no cutoff or classification threshold is optimized."
  ),
  "",
  "## Population and outcome audit",
  "",
  paste0(
    "The frozen paid-game sample contains N = ", nrow(high_rating_data),
    " unique games, all with at least 20 reviews. High rating is defined from",
    " `positive_reviews / total_reviews >= cutoff`. Review volume is neither a",
    " weight nor a model covariate."
  ),
  "",
  distribution_lines,
  "",
  "## HIGH85 primary logistic fit",
  "",
  paste0(
    "The model converged = ", primary_fit_row$converged,
    ", with ", primary_fit_row$event_n, " events and ",
    primary_fit_row$non_event_n, " non-events. logLik = ",
    fmt(primary_fit_row$log_likelihood, 3), ", AIC = ",
    fmt(primary_fit_row$aic, 3), ", BIC = ",
    fmt(primary_fit_row$bic, 3), ". Null/residual deviance = ",
    fmt(primary_fit_row$null_deviance, 3), "/",
    fmt(primary_fit_row$residual_deviance, 3), "."
  ),
  "",
  primary_or_lines,
  "",
  "## Diagnostics",
  "",
  paste0(
    "Separation heuristics flagged ", sum(separation_diagnostics_5e$n_flagged),
    " total conditions. Maximum leverage = ",
    fmt(influence_summary$max_leverage), "; maximum Cook's D = ",
    fmt(influence_summary$max_cooks_distance), ". The maximum absolute",
    " standardized deviance residual is ",
    fmt(influence_summary$max_absolute_standardized_deviance_residual), "."
  ),
  "",
  paste0(
    "In-sample ROC AUC = ", fmt(auc_5e$auc), " (95% CI ",
    fmt(auc_5e$ci95_lower), " to ", fmt(auc_5e$ci95_upper),
    "). AUC is a secondary descriptive diagnostic, not the model-selection",
    " objective. Calibration is also in-sample and descriptive."
  ),
  "",
  "## Rating-threshold stability",
  "",
  paste0(
    "Descriptive stability counts: ROBUST = ",
    ifelse("ROBUST" %in% names(stability_counts), stability_counts[["ROBUST"]], 0),
    ", PARTIAL = ",
    ifelse("PARTIAL" %in% names(stability_counts), stability_counts[["PARTIAL"]], 0),
    ", SENSITIVE = ",
    ifelse("SENSITIVE" %in% names(stability_counts), stability_counts[["SENSITIVE"]], 0),
    ". Classification uses direction agreement plus maximum relative OR drift",
    " from HIGH85 and is not a statistical test."
  ),
  "",
  "## Comparison with the primary Beta-binomial model",
  "",
  paste0(
    "Direction agrees for ", direction_agree_n, "/", direction_total_n,
    " shared coefficients. The OR magnitudes are not directly comparable",
    " because the outcomes and likelihood contributions differ."
  ),
  "",
  "## Interpretation boundary",
  "",
  paste(
    "All estimates describe conditional associations with reaching a high-rating",
    "threshold. They do not show that a feature causes a rating change. The",
    "Beta-binomial remains the primary inferential analysis."
  )
)
writeLines(
  enc2utf8(technical_report),
  file.path(project_root, "reports", "step5e_high_rating_logistic_report.md"),
  useBytes = TRUE
)

source_candidates(c(
  file.path("R", "modeling", "13_high_rating_report.R"),
  file.path("modeling", "13_high_rating_report.R")
))

message("Step 5E analysis pipeline: PASS")
