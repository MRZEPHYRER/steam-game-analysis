# Drop an unused platform factor level from descriptive split summaries.
platform_summary_6b <- do.call(rbind, lapply(split(positive_all_6b,
  droplevels(positive_all_6b$platform_segment), drop = TRUE), function(d) {
  cbind(platform_segment = as.character(d$platform_segment[1]),
    summarize_count_6b(d))
}))
stopifnot(nrow(platform_summary_6b) == 4L,
  sum(platform_summary_6b$n_games) == nrow(positive_all_6b),
  all(is.finite(platform_summary_6b$max_count)))
write_attention_audit(platform_summary_6b, "step6b_platform_summary.csv")
