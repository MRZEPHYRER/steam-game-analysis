# Step 5F-A: game-level raw ratings and 95% Wilson score intervals.

if (!exists("reception_gt0") || !exists("games_market_model")) {
  stop("Run 01_prepare_model_data.R before 14_wilson_rating.R.", call. = FALSE)
}

wilson_z_5f <- stats::qnorm(0.975)

wilson_interval_5f <- function(x, n, z = wilson_z_5f) {
  x <- as.numeric(x)
  n <- as.numeric(n)
  if (any(!is.finite(x) | !is.finite(n) | n <= 0 | x < 0 | x > n)) {
    stop("Wilson inputs must satisfy 0 <= x <= n and n > 0.", call. = FALSE)
  }
  p <- x / n
  denominator <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denominator
  halfwidth <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denominator
  lower <- pmax(0, center - halfwidth)
  upper <- pmin(1, center + halfwidth)
  lower[x == 0] <- 0
  upper[x == n] <- 1
  data.frame(
    wilson_lower_95 = lower,
    wilson_center = center,
    wilson_upper_95 = upper,
    wilson_width = upper - lower
  )
}

# Independent numerical check: invert the binomial score test with Base R's
# mature uniroot solver instead of reusing the Wilson closed form.
score_inversion_5f <- function(x, n, z = wilson_z_5f) {
  p_hat <- x / n
  eps <- 1e-12
  score <- function(p) (x - n * p) / sqrt(n * p * (1 - p))
  lower <- if (x == 0) {
    0
  } else {
    stats::uniroot(
      function(p) score(p) - z,
      c(eps, min(p_hat, 1 - eps)), tol = 1e-13
    )$root
  }
  upper <- if (x == n) {
    1
  } else {
    stats::uniroot(
      function(p) score(p) + z,
      c(max(p_hat, eps), 1 - eps), tol = 1e-13
    )$root
  }
  c(lower = lower, upper = upper)
}

rating_population_5f <- reception_gt0 |>
  dplyr::transmute(
    appid = as.integer(appid),
    name = as.character(name),
    is_free = as.integer(is_free),
    positive_reviews = as.integer(positive_reviews),
    negative_reviews = as.integer(negative_reviews),
    total_reviews = as.integer(total_reviews),
    raw_positive_rate = positive_reviews / total_reviews
  ) |>
  dplyr::arrange(appid)

market_n_5f <- nrow(games_market_model)
zero_review_n_5f <- sum(games_market_model$total_reviews == 0)
rating_population_n_5f <- nrow(rating_population_5f)

if (market_n_5f != 3000L || zero_review_n_5f != 759L || rating_population_n_5f != 2241L) {
  stop("Step 5F frozen population counts do not match 3000 / 759 / 2241.", call. = FALSE)
}
if (any(rating_population_5f$total_reviews <= 0) ||
    any(rating_population_5f$positive_reviews + rating_population_5f$negative_reviews !=
        rating_population_5f$total_reviews) ||
    anyDuplicated(rating_population_5f$appid)) {
  stop("Step 5F rating population identity or AppID uniqueness failed.", call. = FALSE)
}

rating_population_5f <- dplyr::bind_cols(
  rating_population_5f,
  wilson_interval_5f(
    rating_population_5f$positive_reviews,
    rating_population_5f$total_reviews
  )
)

validation_cases_5f <- data.frame(
  positive_reviews = c(0L, 1L, 1L, 2L, 10L, 20L, 100L, 1000L, 3L, 37L, 83L),
  total_reviews = c(1L, 1L, 2L, 2L, 10L, 20L, 100L, 1000L, 7L, 100L, 137L)
)
validation_manual_5f <- wilson_interval_5f(
  validation_cases_5f$positive_reviews,
  validation_cases_5f$total_reviews
)
validation_numeric_5f <- t(vapply(
  seq_len(nrow(validation_cases_5f)),
  function(i) score_inversion_5f(
    validation_cases_5f$positive_reviews[i],
    validation_cases_5f$total_reviews[i]
  ),
  numeric(2)
))
wilson_validation_5f <- dplyr::bind_cols(validation_cases_5f, validation_manual_5f) |>
  dplyr::mutate(
    score_inversion_lower = validation_numeric_5f[, "lower"],
    score_inversion_upper = validation_numeric_5f[, "upper"],
    lower_absolute_difference = abs(wilson_lower_95 - score_inversion_lower),
    upper_absolute_difference = abs(wilson_upper_95 - score_inversion_upper),
    validation_method = "Base R score-test inversion (uniroot)",
    tolerance = 1e-9,
    validation_pass = lower_absolute_difference <= tolerance &
      upper_absolute_difference <= tolerance
  )
if (!all(wilson_validation_5f$validation_pass)) {
  stop("Wilson closed-form validation against score-test inversion failed.", call. = FALSE)
}

wilson_examples_base_5f <- dplyr::bind_rows(
  data.frame(
    example_group = "raw_100_percent",
    positive_reviews = c(1L, 2L, 5L, 10L, 20L, 50L, 100L, 1000L),
    total_reviews = c(1L, 2L, 5L, 10L, 20L, 50L, 100L, 1000L)
  ),
  data.frame(
    example_group = "raw_50_percent",
    positive_reviews = c(1L, 2L, 5L, 10L, 50L, 500L),
    total_reviews = c(2L, 4L, 10L, 20L, 100L, 1000L)
  )
) |>
  dplyr::mutate(
    negative_reviews = total_reviews - positive_reviews,
    raw_positive_rate = positive_reviews / total_reviews
  )
wilson_examples_5f <- dplyr::bind_cols(
  wilson_examples_base_5f,
  wilson_interval_5f(
    wilson_examples_base_5f$positive_reviews,
    wilson_examples_base_5f$total_reviews
  )
)

if (any(rating_population_5f$wilson_lower_95 < 0) ||
    any(rating_population_5f$wilson_upper_95 > 1) ||
    any(rating_population_5f$wilson_lower_95 > rating_population_5f$raw_positive_rate) ||
    any(rating_population_5f$wilson_upper_95 < rating_population_5f$raw_positive_rate)) {
  stop("Wilson interval bounds failed.", call. = FALSE)
}

write_model_audit(wilson_examples_5f, "step5f_wilson_examples.csv")
write_model_audit(wilson_validation_5f, "step5f_wilson_validation.csv")

message("Step 5F Wilson intervals: PASS")
