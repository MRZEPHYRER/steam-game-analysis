# Shared helpers for Step 6A review-attention entry analysis.

.model_helper_candidates <- c(
  file.path("R", "modeling", "00_model_helpers.R"),
  file.path("..", "modeling", "00_model_helpers.R"),
  file.path("modeling", "00_model_helpers.R")
)
.model_helper_path <- .model_helper_candidates[file.exists(.model_helper_candidates)][1]
if (is.na(.model_helper_path)) stop("Could not locate modeling helpers.", call. = FALSE)
source(.model_helper_path, encoding = "UTF-8")

attention_audit_dir <- file.path(project_root, "data", "analysis", "attention")
attention_figure_dir <- file.path(project_root, "figures", "attention")
dir.create(attention_audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(attention_figure_dir, recursive = TRUE, showWarnings = FALSE)

write_attention_audit <- function(data, filename) {
  utils::write.csv(
    data, file.path(attention_audit_dir, filename), row.names = FALSE,
    na = "", fileEncoding = "UTF-8"
  )
}

fit_glm_with_warnings_6a <- function(formula, data) {
  warnings <- character()
  fit <- withCallingHandlers(
    stats::glm(formula, family = stats::binomial(link = "logit"), data = data),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(fit = fit, warnings = unique(warnings))
}

tidy_logistic_6a <- function(fit, model_id) {
  matrix <- summary(fit)$coefficients
  data.frame(
    model_id = model_id,
    term = rownames(matrix),
    estimate_log_odds = matrix[, 1],
    std_error = matrix[, 2],
    z_value = matrix[, 3],
    p_value = matrix[, 4],
    odds_ratio = exp(matrix[, 1]),
    or_ci95_lower = exp(matrix[, 1] - stats::qnorm(0.975) * matrix[, 2]),
    or_ci95_upper = exp(matrix[, 1] + stats::qnorm(0.975) * matrix[, 2]),
    direction = ifelse(matrix[, 1] > 0, "POSITIVE", ifelse(matrix[, 1] < 0, "NEGATIVE", "ZERO")),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

fit_summary_6a <- function(fit, model_id, warning_count = 0L) {
  matrix <- stats::model.matrix(fit)
  data.frame(
    model_id = model_id,
    n_games = stats::nobs(fit),
    event_n = sum(stats::model.response(stats::model.frame(fit)) == 1L),
    non_event_n = sum(stats::model.response(stats::model.frame(fit)) == 0L),
    parameter_count = length(stats::coef(fit)),
    residual_df = stats::df.residual(fit),
    log_likelihood = as.numeric(stats::logLik(fit)),
    aic = stats::AIC(fit),
    bic = stats::BIC(fit),
    null_deviance = fit$null.deviance,
    residual_deviance = fit$deviance,
    converged = isTRUE(fit$converged),
    matrix_rank = fit$rank,
    matrix_columns = ncol(matrix),
    warning_count = warning_count,
    formula = paste(deparse(stats::formula(fit)), collapse = " "),
    weights_used = FALSE,
    count_offset_used = FALSE,
    interactions_used = FALSE,
    stringsAsFactors = FALSE
  )
}

auc_delong_6a <- function(outcome, score) {
  positive_scores <- score[outcome == 1L]
  negative_scores <- score[outcome == 0L]
  comparison <- outer(
    positive_scores, negative_scores,
    function(pos, neg) (pos > neg) + 0.5 * (pos == neg)
  )
  v_positive <- rowMeans(comparison)
  v_negative <- colMeans(comparison)
  auc <- mean(v_positive)
  standard_error <- sqrt(
    stats::var(v_positive) / length(v_positive) +
      stats::var(v_negative) / length(v_negative)
  )
  data.frame(
    auc = auc,
    standard_error = standard_error,
    ci95_lower = max(0, auc - stats::qnorm(0.975) * standard_error),
    ci95_upper = min(1, auc + stats::qnorm(0.975) * standard_error),
    ci_method = "DeLong placement-value normal approximation",
    diagnostic_scope = "In-sample descriptive discrimination; no threshold optimization",
    stringsAsFactors = FALSE
  )
}
