# glmmTMB type='conditional' is already the positive-truncated expectation.
# The log-link prediction is the latent (untruncated) NB2 mean used in the
# density and P(Y=0); confusing these changes the likelihood by thousands.
mu_latent_6b <- exp(as.numeric(stats::predict(primary_truncated_6b,
  newdata = positive_model_6b, type = "link")))
p0_6b <- stats::dnbinom(0, mu = mu_latent_6b, size = theta_6b)
latent_to_positive_mean_6b <- function(mu, theta) {
  zero_probability <- stats::dnbinom(0, mu = mu, size = theta)
  mu / (1 - zero_probability)
}
mean_positive_6b <- latent_to_positive_mean_6b(mu_latent_6b, theta_6b)
package_positive_mean_6b <- as.numeric(stats::predict(primary_truncated_6b,
  newdata = positive_model_6b, type = "conditional"))
stopifnot(max(abs(mean_positive_6b / package_positive_mean_6b - 1)) < 1e-5)
likelihood_manual_6b["truncated_nb"] <- sum(
  stats::dnbinom(positive_model_6b$review_count, mu = mu_latent_6b,
    size = theta_6b, log = TRUE) - log1p(-p0_6b))
likelihood_constant_ok_6b <- all(abs(likelihood_manual_6b -
  likelihood_package_6b) < 1e-3)
# The downstream prediction helper receives glmmTMB's already-truncated mean.
conditional_mean_6b <- function(mu, theta) mu
