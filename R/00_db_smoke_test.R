.script_dir <- local({
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE))
  } else {
    frames <- sys.frames()
    source_files <- vapply(
      frames,
      function(frame) if (is.null(frame$ofile)) "" else as.character(frame$ofile),
      character(1)
    )
    source_files <- source_files[nzchar(source_files)]
    if (length(source_files) == 0) getwd() else dirname(normalizePath(tail(source_files, 1)))
  }
})
source(file.path(.script_dir, "db_connect.R"))

expected <- c(
  games = 3000L,
  genres = 13L,
  game_genres = 8796L,
  review_snapshots = 3000L,
  price_snapshots = 3000L,
  vw_game_analysis = 3000L,
  vw_game_genres = 8796L,
  vw_model_sample_20 = 844L
)

with_steam_db(function(con) {
  actual <- vapply(
    names(expected),
    function(object) {
      query <- sprintf("SELECT COUNT(*) AS n FROM `%s`", object)
      as.integer(DBI::dbGetQuery(con, query)$n[[1]])
    },
    integer(1)
  )

  if (!identical(actual, expected)) {
    stop("R database smoke test row counts differ from the frozen contract.", call. = FALSE)
  }

  identity_failures <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT COUNT(*) AS n FROM review_snapshots",
      "WHERE positive_reviews + negative_reviews <> total_reviews"
    )
  )$n[[1]]
  stopifnot(identity_failures == 0)
})

cat("R MySQL smoke test: PASS\n")
