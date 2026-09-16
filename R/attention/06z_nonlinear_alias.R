# Step 6A.1 explicit alias for the frozen paid-market price training population.

if (!exists("paid_price_population_6a")) {
  stop("Run 01_attention_data_audit.R before Step 6A.1.", call. = FALSE)
}
paid_price_population_6a1 <- paid_price_population_6a
