# Project-local helpers for preserving Unicode text in rendered reports.

decode_uplus_notation <- function(x) {
  if (length(x) == 0L) return(x)
  original_names <- names(x)
  value <- as.character(x)

  decode_token <- function(token) {
    hex <- sub(
      "^(?:<|&lt;)U\\+([[:xdigit:]]{4,6})(?:>|&gt;)$",
      "\\1", token, perl = TRUE
    )
    code_point <- strtoi(hex, base = 16L)
    if (
      is.na(code_point) || code_point > 0x10FFFFL ||
        (code_point >= 0xD800L && code_point <= 0xDFFFL)
    ) {
      return(token)
    }
    intToUtf8(code_point)
  }

  replace_tokens <- function(text, pattern) {
    locations <- gregexpr(pattern, text, perl = TRUE)
    tokens <- regmatches(text, locations)
    replacements <- lapply(
      tokens,
      function(items) vapply(items, decode_token, character(1), USE.NAMES = FALSE)
    )
    regmatches(text, locations) <- replacements
    text
  }

  value <- replace_tokens(value, "<U\\+[[:xdigit:]]{4,6}>")
  value <- replace_tokens(value, "&lt;U\\+[[:xdigit:]]{4,6}&gt;")
  Encoding(value) <- "UTF-8"
  names(value) <- original_names
  value
}
