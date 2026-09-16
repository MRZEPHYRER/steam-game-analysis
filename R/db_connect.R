# Shared MySQL connection helper for Step 3C.

.db_connect_source_dir <- local({
  frames <- sys.frames()
  source_files <- vapply(
    frames,
    function(frame) {
      if (is.null(frame$ofile)) "" else as.character(frame$ofile)
    },
    character(1)
  )
  source_files <- source_files[nzchar(source_files)]
  if (length(source_files) == 0) {
    NULL
  } else {
    dirname(normalizePath(source_files[[length(source_files)]], mustWork = TRUE))
  }
})

find_project_root <- function() {
  starts <- unique(Filter(
    Negate(is.null),
    list(.db_connect_source_dir, normalizePath(getwd(), mustWork = TRUE))
  ))
  for (start in starts) {
    current <- normalizePath(start, mustWork = TRUE)
    repeat {
      markers_exist <- all(file.exists(c(
        file.path(current, "R", "db_connect.R"),
        file.path(current, "sql", "01_create_schema.sql"),
        file.path(current, ".env.example")
      )))
      if (markers_exist) {
        return(current)
      }
      parent <- dirname(current)
      if (identical(parent, current)) {
        break
      }
      current <- parent
    }
  }
  stop("Could not locate the steam-game-analysis project root.", call. = FALSE)
}

load_project_env <- function() {
  env_path <- file.path(find_project_root(), ".env")
  if (!file.exists(env_path)) {
    stop("Project-root .env file was not found.", call. = FALSE)
  }
  readRenviron(env_path)
  invisible(env_path)
}

mysql_config <- function() {
  load_project_env()
  names <- c(
    "MYSQL_HOST", "MYSQL_PORT", "MYSQL_DATABASE", "MYSQL_USER",
    "MYSQL_PASSWORD"
  )
  values <- Sys.getenv(names, unset = "")
  missing <- names[values == ""]
  if (length(missing) > 0) {
    stop(
      paste("Missing required MySQL environment variables:", paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
  if (values[["MYSQL_DATABASE"]] != "steam_game_analysis") {
    stop("MYSQL_DATABASE must be steam_game_analysis.", call. = FALSE)
  }
  list(
    host = values[["MYSQL_HOST"]],
    port = as.integer(values[["MYSQL_PORT"]]),
    dbname = values[["MYSQL_DATABASE"]],
    user = values[["MYSQL_USER"]],
    password = values[["MYSQL_PASSWORD"]]
  )
}

connect_steam_db <- function() {
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("R package DBI is required.", call. = FALSE)
  }
  if (!requireNamespace("RMariaDB", quietly = TRUE)) {
    stop("R package RMariaDB is required.", call. = FALSE)
  }
  cfg <- mysql_config()
  do.call(
    DBI::dbConnect,
    c(list(drv = RMariaDB::MariaDB()), cfg)
  )
}

with_steam_db <- function(code) {
  if (!is.function(code)) {
    stop("with_steam_db() requires a function.", call. = FALSE)
  }
  con <- connect_steam_db()
  on.exit({
    if (DBI::dbIsValid(con)) {
      DBI::dbDisconnect(con)
    }
  }, add = TRUE)
  code(con)
}
