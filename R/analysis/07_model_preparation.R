# EDA-only preparation notes. This script computes no inferential or predictive model.

correlation_data <- games_market |>
  dplyr::transmute(
    current_price_usd,
    total_reviews,
    log1p_reviews = log1p(total_reviews),
    positive_rate
  )

correlation_to_long <- function(method) {
  matrix_value <- stats::cor(
    correlation_data,
    use = "pairwise.complete.obs",
    method = method
  )
  indices <- expand.grid(
    variable_x = colnames(matrix_value),
    variable_y = rownames(matrix_value),
    stringsAsFactors = FALSE
  )
  indices$method <- method
  indices$correlation <- as.vector(matrix_value)
  indices
}

correlation_summary <- dplyr::bind_rows(
  correlation_to_long("pearson"),
  correlation_to_long("spearman")
) |>
  dplyr::filter(variable_x <= variable_y) |>
  dplyr::arrange(method, variable_x, variable_y)

skewness_value <- function(x) {
  x <- x[is.finite(x)]
  centre <- mean(x)
  spread <- stats::sd(x)
  if (length(x) < 3 || spread == 0) return(NA_real_)
  mean((x - centre)^3) / spread^3
}

model_preparation_summary <- data.frame(
  variable = c(
    "total_reviews", "log1p_total_reviews", "positive_rate",
    "current_price_usd", "is_free", "release_month", "platform_segment",
    "genre_multi_label"
  ),
  role = c(
    "attention outcome candidate", "transformed attention candidate",
    "reception outcome candidate", "numeric predictor candidate",
    "binary predictor candidate", "categorical predictor candidate",
    "categorical predictor candidate", "multi-label predictor candidate"
  ),
  available_n = c(
    sum(!is.na(games_market$total_reviews)),
    sum(!is.na(games_market$total_reviews)),
    sum(!is.na(games_market$positive_rate)),
    sum(!is.na(games_market$current_price_usd)),
    sum(!is.na(games_market$is_free)),
    sum(!is.na(games_market$release_month)),
    sum(!is.na(games_market$platform_segment)),
    nrow(games_genres)
  ),
  missing_n = c(
    sum(is.na(games_market$total_reviews)),
    sum(is.na(games_market$total_reviews)),
    sum(is.na(games_market$positive_rate)),
    sum(is.na(games_market$current_price_usd)),
    sum(is.na(games_market$is_free)),
    sum(is.na(games_market$release_month)),
    sum(is.na(games_market$platform_segment)),
    0L
  ),
  eda_note = c(
    "Strong right skew and structural zeros; do not assume Gaussian scale.",
    "Reduces right-tail leverage while retaining zero-review games.",
    "Undefined for zero-review games; denominator-aware analysis is required.",
    "One paid-game value is missing; free and paid definitions remain separate.",
    "Free games are strongly underrepresented after the 20-review cutoff.",
    "Six fixed launch-cohort months; inspect coverage differences.",
    "Support combinations are sparse outside Windows-only.",
    "One-to-many relation; encode deliberately and avoid duplicate game outcomes."
  ),
  stringsAsFactors = FALSE
)

distribution_diagnostics <- data.frame(
  variable = c("total_reviews", "log1p_total_reviews", "current_price_usd", "positive_rate"),
  n = c(
    sum(!is.na(games_market$total_reviews)),
    sum(!is.na(games_market$total_reviews)),
    sum(!is.na(games_market$current_price_usd)),
    sum(!is.na(games_market$positive_rate))
  ),
  median = c(
    stats::median(games_market$total_reviews),
    stats::median(log1p(games_market$total_reviews)),
    stats::median(games_market$current_price_usd, na.rm = TRUE),
    stats::median(games_market$positive_rate, na.rm = TRUE)
  ),
  skewness = c(
    skewness_value(games_market$total_reviews),
    skewness_value(log1p(games_market$total_reviews)),
    skewness_value(games_market$current_price_usd),
    skewness_value(games_market$positive_rate)
  )
)

review_outliers <- games_market |>
  dplyr::arrange(dplyr::desc(total_reviews), appid) |>
  dplyr::slice_head(n = 10) |>
  dplyr::transmute(
    outlier_basis = "highest review volume",
    appid, name, total_reviews, positive_rate, current_price_usd
  )
price_outliers <- games_market |>
  dplyr::filter(!is.na(current_price_usd)) |>
  dplyr::arrange(dplyr::desc(current_price_usd), appid) |>
  dplyr::slice_head(n = 10) |>
  dplyr::transmute(
    outlier_basis = "highest current price",
    appid, name, total_reviews, positive_rate, current_price_usd
  )
outlier_table <- dplyr::bind_rows(review_outliers, price_outliers)

dataset_audit <- data.frame(
  dataset = c("games_market", "games_model20", "games_genres"),
  rows = c(nrow(games_market), nrow(games_model20), nrow(games_genres)),
  distinct_appids = c(
    dplyr::n_distinct(games_market$appid),
    dplyr::n_distinct(games_model20$appid),
    dplyr::n_distinct(games_genres$appid)
  ),
  expected_rows = c(3000L, 844L, 8796L)
)

utils::write.csv(
  genre_base,
  file.path(r_analysis_dir, "genre_eda_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  correlation_summary,
  file.path(r_analysis_dir, "correlation_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  model_preparation_summary,
  file.path(r_analysis_dir, "model_preparation_summary.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  distribution_diagnostics,
  file.path(r_analysis_dir, "distribution_diagnostics.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  outlier_table,
  file.path(r_analysis_dir, "outlier_table.csv"),
  row.names = FALSE,
  na = ""
)
utils::write.csv(
  dataset_audit,
  file.path(r_analysis_dir, "dataset_audit.csv"),
  row.names = FALSE,
  na = ""
)

stopifnot(
  all(dataset_audit$rows == dataset_audit$expected_rows),
  nrow(outlier_table) == 20,
  nrow(correlation_summary) == 20
)
