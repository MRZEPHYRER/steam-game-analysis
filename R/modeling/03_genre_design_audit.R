# Genre encoding, co-occurrence, sparse-cell, and predictor-only design audits.
# No response is used to select predictors and no outcome model is fitted.

if (!exists("model20_population_audit")) {
  .audit_candidates <- c(
    file.path("R", "modeling", "02_model_specification_audit.R"),
    file.path("modeling", "02_model_specification_audit.R"),
    "02_model_specification_audit.R"
  )
  .audit_path <- .audit_candidates[file.exists(.audit_candidates)][1]
  if (is.na(.audit_path)) stop("Could not locate 02_model_specification_audit.R.", call. = FALSE)
  source(.audit_path)
}

genre_counts_for <- function(data, count_name) {
  genre_long_model |>
    dplyr::filter(appid %in% data$appid) |>
    dplyr::count(genre_name, name = count_name)
}
genre_market_counts <- genre_counts_for(games_market_wide, "market_n")
genre_model20_counts <- genre_counts_for(model20_all, "model20_n")
genre_paid_counts <- genre_counts_for(model20_paid, "model20_paid_n")
genre_paid_reviews <- genre_long_model |>
  dplyr::filter(appid %in% model20_paid$appid) |>
  dplyr::left_join(
    model20_paid |>
      dplyr::select(appid, positive_reviews, negative_reviews),
    by = "appid"
  ) |>
  dplyr::group_by(genre_name) |>
  dplyr::summarise(
    positive_reviews = sum(positive_reviews),
    negative_reviews = sum(negative_reviews),
    .groups = "drop"
  )
genre_frequency <- data.frame(genre_name = genre_names) |>
  dplyr::left_join(genre_market_counts, by = "genre_name") |>
  dplyr::left_join(genre_model20_counts, by = "genre_name") |>
  dplyr::left_join(genre_paid_counts, by = "genre_name") |>
  dplyr::left_join(genre_paid_reviews, by = "genre_name") |>
  dplyr::mutate(
    dplyr::across(-genre_name, ~tidyr::replace_na(.x, 0)),
    model20_paid_pct = model20_paid_n / nrow(model20_paid),
    sparse_lt100 = model20_paid_n < 100,
    sparse_lt50 = model20_paid_n < 50,
    sparse_lt20 = model20_paid_n < 20
  ) |>
  dplyr::arrange(dplyr::desc(model20_paid_n), genre_name)

paid_genre_matrix <- as.matrix(
  model20_paid_complete[, genre_indicator_names, drop = FALSE]
)
storage.mode(paid_genre_matrix) <- "numeric"
colnames(paid_genre_matrix) <- genre_names
cooccurrence_matrix <- crossprod(paid_genre_matrix)
genre_cooccurrence <- expand.grid(
  genre_a = genre_names,
  genre_b = genre_names,
  stringsAsFactors = FALSE
)
genre_cooccurrence$cooccurrence_n <- as.vector(cooccurrence_matrix)

phi_matrix <- suppressWarnings(stats::cor(paid_genre_matrix))
pair_index <- which(upper.tri(phi_matrix), arr.ind = TRUE)
genre_correlation <- data.frame(
  genre_a = rownames(phi_matrix)[pair_index[, "row"]],
  genre_b = colnames(phi_matrix)[pair_index[, "col"]],
  phi_correlation = phi_matrix[pair_index],
  stringsAsFactors = FALSE
)
pair_cooccurrence <- cooccurrence_matrix[pair_index]
genre_sizes <- diag(cooccurrence_matrix)
genre_correlation$cooccurrence_n <- pair_cooccurrence
genre_correlation$smaller_genre_n <- pmin(
  genre_sizes[pair_index[, "row"]],
  genre_sizes[pair_index[, "col"]]
)
genre_correlation$smaller_genre_coverage <- ifelse(
  genre_correlation$smaller_genre_n > 0,
  genre_correlation$cooccurrence_n / genre_correlation$smaller_genre_n,
  NA_real_
)
genre_correlation <- genre_correlation |>
  dplyr::arrange(dplyr::desc(abs(phi_correlation)), dplyr::desc(cooccurrence_n))

candidate_genres_main <- genre_frequency |>
  dplyr::filter(model20_paid_n >= 100) |>
  dplyr::pull(genre_name)
candidate_genres_sensitivity <- genre_frequency |>
  dplyr::filter(model20_paid_n >= 20) |>
  dplyr::pull(genre_name)
candidate_genre_sets <- dplyr::bind_rows(
  data.frame(set = "main", genre_name = candidate_genres_main),
  data.frame(set = "sensitivity", genre_name = candidate_genres_sensitivity)
) |>
  dplyr::left_join(
    genre_indicator_mapping,
    by = "genre_name"
  ) |>
  dplyr::left_join(
    genre_frequency |>
      dplyr::select(genre_name, model20_paid_n),
    by = "genre_name"
  )

design_data <- model20_paid_complete
design_data$release_month <- stats::relevel(
  droplevels(design_data$release_month), ref = "2025-07"
)
design_data$platform_segment <- stats::relevel(
  droplevels(design_data$platform_segment), ref = "Windows only"
)
main_indicators <- genre_indicator_mapping$indicator[
  genre_indicator_mapping$genre_name %in% candidate_genres_main
]
design_terms <- c(
  "scale(log1p_current_price)",
  "release_month",
  "platform_segment",
  main_indicators
)
design_formula <- stats::as.formula(
  paste("~", paste(design_terms, collapse = " + "))
)
design_matrix <- stats::model.matrix(design_formula, data = design_data)
design_qr <- qr(design_matrix, tol = 1e-10)
dependent_columns <- if (design_qr$rank < ncol(design_matrix)) {
  colnames(design_matrix)[
    design_qr$pivot[seq.int(design_qr$rank + 1L, ncol(design_matrix))]
  ]
} else {
  character(0)
}
design_matrix_diagnostics <- data.frame(
  n_rows = nrow(design_matrix),
  n_columns = ncol(design_matrix),
  matrix_rank = design_qr$rank,
  exact_linear_dependencies = ncol(design_matrix) - design_qr$rank,
  condition_number = kappa(design_matrix, exact = TRUE),
  reference_release_month = "2025-07",
  reference_platform = "Windows only",
  genre_reference = "absent (0)",
  stringsAsFactors = FALSE
)
design_matrix_columns <- data.frame(
  column = colnames(design_matrix),
  exact_dependency = colnames(design_matrix) %in% dependent_columns,
  stringsAsFactors = FALSE
)

platform_paid <- platform_frequency |>
  dplyr::filter(sample == "model20_paid")
sparse_platform_total <- sum(platform_paid$n_games[platform_paid$n_games < 20])
platform_recommendation <- platform_paid |>
  dplyr::mutate(
    recommendation = dplyr::case_when(
      n_games >= 20 ~ "retain",
      n_games >= 5 ~ "merge for primary; retain in sensitivity",
      TRUE ~ "merge or omit after review"
    ),
    proposed_level = ifelse(
      n_games >= 20, as.character(platform_segment), "Other sparse platforms"
    ),
    proposed_level_n = ifelse(n_games >= 20, n_games, sparse_platform_total),
    reason = ifelse(
      n_games >= 20,
      "At least 20 games in model20_paid",
      "Sparse level has fewer than 20 games"
    )
  )

release_levels <- levels(droplevels(model20_paid$release_month))
platform_levels <- levels(droplevels(model20_paid$platform_segment))
release_platform_counts <- model20_paid |>
  dplyr::count(release_month, platform_segment, name = "n")
release_platform_grid <- expand.grid(
  release_month = release_levels,
  platform_segment = platform_levels,
  stringsAsFactors = FALSE
) |>
  dplyr::left_join(release_platform_counts, by = c("release_month", "platform_segment")) |>
  dplyr::mutate(
    combination = "release_month_x_platform",
    level_a = release_month,
    level_b = platform_segment,
    n = tidyr::replace_na(n, 0L)
  ) |>
  dplyr::select(combination, level_a, level_b, n)

paid_genre_long <- genre_long_model |>
  dplyr::filter(appid %in% model20_paid$appid) |>
  dplyr::left_join(
    model20_paid |>
      dplyr::select(appid, release_month, platform_segment),
    by = "appid"
  )
release_genre_counts <- paid_genre_long |>
  dplyr::count(release_month, genre_name, name = "n")
release_genre_grid <- expand.grid(
  release_month = release_levels,
  genre_name = genre_names,
  stringsAsFactors = FALSE
) |>
  dplyr::left_join(release_genre_counts, by = c("release_month", "genre_name")) |>
  dplyr::mutate(
    combination = "release_month_x_genre",
    level_a = release_month,
    level_b = genre_name,
    n = tidyr::replace_na(n, 0L)
  ) |>
  dplyr::select(combination, level_a, level_b, n)

platform_genre_counts <- paid_genre_long |>
  dplyr::count(platform_segment, genre_name, name = "n")
platform_genre_grid <- expand.grid(
  platform_segment = platform_levels,
  genre_name = genre_names,
  stringsAsFactors = FALSE
) |>
  dplyr::left_join(platform_genre_counts, by = c("platform_segment", "genre_name")) |>
  dplyr::mutate(
    combination = "platform_x_genre",
    level_a = platform_segment,
    level_b = genre_name,
    n = tidyr::replace_na(n, 0L)
  ) |>
  dplyr::select(combination, level_a, level_b, n)

sparse_cells <- dplyr::bind_rows(
  release_platform_grid, release_genre_grid, platform_genre_grid
) |>
  dplyr::mutate(
    empty = n == 0,
    sparse_lt5 = n < 5,
    sparse_lt10 = n < 10
  ) |>
  dplyr::arrange(combination, n, level_a, level_b)

sparse_cell_summary <- sparse_cells |>
  dplyr::group_by(combination) |>
  dplyr::summarise(
    cells = dplyr::n(),
    empty_cells = sum(empty),
    cells_lt5 = sum(sparse_lt5),
    cells_lt10 = sum(sparse_lt10),
    .groups = "drop"
  )

genre_outcome_heterogeneity <- paid_genre_long |>
  dplyr::left_join(
    model20_paid |>
      dplyr::select(appid, positive_reviews, negative_reviews, positive_rate),
    by = "appid"
  ) |>
  dplyr::group_by(genre_name) |>
  dplyr::summarise(
    n_games = dplyr::n_distinct(appid),
    positive_reviews = sum(positive_reviews),
    negative_reviews = sum(negative_reviews),
    total_reviews = positive_reviews + negative_reviews,
    pooled_positive_rate = positive_reviews / total_reviews,
    median_game_positive_rate = stats::median(positive_rate),
    .groups = "drop"
  ) |>
  dplyr::transmute(
    segment_type = "genre",
    segment = genre_name,
    n_games,
    positive_reviews,
    negative_reviews,
    total_reviews,
    pooled_positive_rate,
    median_game_positive_rate
  )
outcome_heterogeneity <- dplyr::bind_rows(
  outcome_heterogeneity,
  genre_outcome_heterogeneity
)

specification_choices <- data.frame(
  decision = c(
    "primary_response", "population_recommendation", "price_main",
    "price_alternative", "release_model_a", "release_model_b",
    "platform_reference", "genre_reference", "weighting"
  ),
  recommendation = c(
    "cbind(positive_reviews, negative_reviews)",
    "model20_paid recommended; model20_all retained as sensitivity",
    "log1p_current_price", "current_price_usd",
    "release_month with 2025-07 reference",
    "days_since_release; do not combine by default",
    "Windows only", "genre absent (0)",
    "no ad-hoc weights; binomial denominator carries information"
  ),
  stringsAsFactors = FALSE
)

write_model_audit(genre_frequency, "genre_frequency.csv")
write_model_audit(genre_cooccurrence, "genre_cooccurrence.csv")
write_model_audit(genre_correlation, "genre_correlation.csv")
write_model_audit(candidate_genre_sets, "candidate_genre_sets.csv")
write_model_audit(design_matrix_diagnostics, "design_matrix_diagnostics.csv")
write_model_audit(design_matrix_columns, "design_matrix_columns.csv")
write_model_audit(platform_recommendation, "platform_recommendation.csv")
write_model_audit(sparse_cells, "sparse_cells.csv")
write_model_audit(sparse_cell_summary, "sparse_cell_summary.csv")
write_model_audit(outcome_heterogeneity, "outcome_heterogeneity.csv")
write_model_audit(specification_choices, "specification_choices.csv")

stopifnot(
  nrow(genre_wide) == 3000,
  dplyr::n_distinct(genre_wide$appid) == 3000,
  nrow(genre_cooccurrence) == length(genre_names)^2,
  design_matrix_diagnostics$n_rows == nrow(model20_paid_complete),
  "2025-07" %in% levels(design_data$release_month),
  "Windows only" %in% levels(design_data$platform_segment),
  identical(loaded_model_data$counts_before, loaded_model_data$counts_after)
)

message("Step 5A structural audit: PASS")
