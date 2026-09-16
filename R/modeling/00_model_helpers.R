# Shared helpers for Step 5A model specification and data auditing.

.db_candidates <- c(
  file.path("R", "db_connect.R"),
  file.path("..", "db_connect.R"),
  file.path("..", "R", "db_connect.R")
)
.db_path <- .db_candidates[file.exists(.db_candidates)][1]
if (is.na(.db_path)) stop("Could not locate R/db_connect.R.", call. = FALSE)
source(.db_path)

project_root <- find_project_root()
model_audit_dir <- file.path(project_root, "data", "analysis", "modeling")
model_figure_dir <- file.path(project_root, "figures", "modeling")
dir.create(model_audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(model_figure_dir, recursive = TRUE, showWarnings = FALSE)

required_packages <- c("dplyr", "tidyr")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(paste("Missing R packages:", paste(missing_packages, collapse = ", ")), call. = FALSE)
}

write_model_audit <- function(data, filename) {
  utils::write.csv(
    data,
    file.path(model_audit_dir, filename),
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
}

skewness_value <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) < 3) return(NA_real_)
  spread <- stats::sd(x)
  if (spread == 0) return(NA_real_)
  mean((x - mean(x))^3) / spread^3
}

derive_platform_segment <- function(windows, mac, linux) {
  value <- dplyr::case_when(
    windows == 1 & mac == 0 & linux == 0 ~ "Windows only",
    windows == 1 & mac == 1 & linux == 0 ~ "Windows + macOS",
    windows == 1 & mac == 0 & linux == 1 ~ "Windows + Linux",
    windows == 1 & mac == 1 & linux == 1 ~ "Windows + macOS + Linux",
    TRUE ~ "Other"
  )
  factor(
    value,
    levels = c(
      "Windows only", "Windows + macOS", "Windows + Linux",
      "Windows + macOS + Linux", "Other"
    )
  )
}

derive_price_band <- function(is_free, current_price_usd) {
  value <- dplyr::case_when(
    is_free == 1 ~ "Free",
    is.na(current_price_usd) ~ "Paid price missing",
    current_price_usd < 5 ~ "$0.01-$4.99",
    current_price_usd < 10 ~ "$5.00-$9.99",
    current_price_usd < 20 ~ "$10.00-$19.99",
    current_price_usd < 30 ~ "$20.00-$29.99",
    TRUE ~ "$30.00+"
  )
  factor(
    value,
    levels = c(
      "Free", "$0.01-$4.99", "$5.00-$9.99", "$10.00-$19.99",
      "$20.00-$29.99", "$30.00+", "Paid price missing"
    )
  )
}
