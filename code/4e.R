# BUSFIN 8200 Problem Set 2, Question 4e
# Estimate the one-factor Fama--MacBeth regressions and HAC inference.

tex_path_4e <- file.path("figures", "4e.tex")
number_test_assets <- 21L

# Reproduce and reuse the complete validated 4b data-processing pipeline.
invisible(capture.output(source(file.path("code", "4b.R"), local = TRUE)))

F_factor <- gmm_data$Rw
test_returns <- excess_returns
test_asset_names <- moment_names

if (length(F_factor) != T_obs || nrow(test_returns) != T_obs) {
  stop("The factor or test assets do not use the validated common sample.")
}
if (ncol(test_returns) != number_test_assets) {
  stop("The test-return matrix does not contain the requested 21 assets.")
}
if (any(!is.finite(F_factor)) || any(!is.finite(test_returns))) {
  stop("The Fama--MacBeth inputs contain non-finite values.")
}

# First pass: xR_j,t = a_j + beta_j F_t + epsilon_j,t.
X_time_series <- cbind(intercept = 1, factor = F_factor)
if (qr(X_time_series)$rank < ncol(X_time_series)) {
  stop("The first-pass time-series design matrix is rank deficient.")
}
time_series_coefficients <- solve(
  crossprod(X_time_series),
  crossprod(X_time_series, test_returns)
)
time_series_intercepts <- time_series_coefficients["intercept", ]
beta_hat <- time_series_coefficients["factor", ]
names(time_series_intercepts) <- test_asset_names
names(beta_hat) <- test_asset_names

time_series_residuals <- test_returns - X_time_series %*% time_series_coefficients
time_series_normal_equation_error <- max(
  abs(crossprod(X_time_series, time_series_residuals))
)
if (time_series_normal_equation_error > 1e-10) {
  stop("The first-pass OLS normal equations are not sufficiently close to zero.")
}

# Second pass each month, through the origin:
# xR_j,t = beta_hat_j lambda_t + alpha_j,t.
beta_crossproduct <- as.numeric(crossprod(beta_hat))
if (!is.finite(beta_crossproduct) || beta_crossproduct <= 0) {
  stop("The cross-sectional beta cross-product is not positive and finite.")
}
lambda_time_series <- as.vector(test_returns %*% beta_hat / beta_crossproduct)
pricing_errors <- test_returns - tcrossprod(lambda_time_series, beta_hat)
colnames(pricing_errors) <- test_asset_names

cross_sectional_orthogonality_error <- max(
  abs(as.vector(pricing_errors %*% beta_hat))
)
if (cross_sectional_orthogonality_error > 1e-10) {
  stop("The monthly cross-sectional OLS residuals are not orthogonal to beta.")
}

# Scalar intercept-only HAC inference, with a separate bandwidth per series.
intercept_hac <- function(series) {
  if (length(series) != T_obs || any(!is.finite(series))) {
    stop("An intercept-only regression does not use the validated finite sample.")
  }

  estimate <- mean(series)
  residuals <- series - estimate
  centered_series <- residuals - mean(residuals)
  centered_matrix <- matrix(centered_series, ncol = 1L)
  selection <- bw_newey_west_ceiling(centered_matrix)
  bandwidth <- selection$bandwidth
  pilot_lag <- as.integer(selection$pilot_lag)
  lag_length <- as.integer(ceiling(bandwidth))

  scalar_autocovariance <- function(lag) {
    sum(
      centered_series[(lag + 1L):T_obs] *
        centered_series[seq_len(T_obs - lag)]
    ) / (T_obs - lag)
  }

  long_run_variance <- scalar_autocovariance(0L)
  if (lag_length > 0L) {
    for (lag in seq_len(lag_length)) {
      weight <- 1 - lag / (lag_length + 1)
      long_run_variance <- long_run_variance +
        2 * weight * scalar_autocovariance(lag)
    }
  }
  if (!is.finite(long_run_variance) || long_run_variance < 0) {
    stop("A scalar HAC long-run variance is negative or non-finite.")
  }

  standard_error <- sqrt(long_run_variance / T_obs)
  list(
    estimate = estimate,
    standard_error = standard_error,
    t_statistic = estimate / standard_error,
    bandwidth = bandwidth,
    pilot_lag = pilot_lag,
    lag_length = lag_length
  )
}

lambda_result <- intercept_hac(lambda_time_series)
alpha_results <- lapply(
  seq_len(number_test_assets),
  function(index) intercept_hac(pricing_errors[, index])
)

alpha_hat <- vapply(alpha_results, function(result) result$estimate, numeric(1L))
se_alpha_hat <- vapply(
  alpha_results,
  function(result) result$standard_error,
  numeric(1L)
)
t_alpha_hat <- vapply(
  alpha_results,
  function(result) result$t_statistic,
  numeric(1L)
)
alpha_bandwidths <- vapply(
  alpha_results,
  function(result) result$bandwidth,
  numeric(1L)
)
alpha_lags <- vapply(
  alpha_results,
  function(result) result$lag_length,
  integer(1L)
)

alpha_identity_error <- max(
  abs(alpha_hat - (colMeans(test_returns) - beta_hat * lambda_result$estimate))
)
if (alpha_identity_error > 1e-12) {
  stop("The average pricing errors do not satisfy the Fama--MacBeth identity.")
}

format_four_4e <- function(x) {
  adjusted <- ifelse(round(x, 4L) == 0, 0, x)
  sprintf("%.4f", adjusted)
}

alpha_rows <- vapply(
  seq_len(number_test_assets),
  function(index) {
    sprintf(
      "      %s pricing error & %s & %s & %s & %s & %d \\\\",
      test_asset_names[index],
      format_four_4e(alpha_hat[index]),
      format_four_4e(se_alpha_hat[index]),
      format_four_4e(t_alpha_hat[index]),
      format_four_4e(alpha_bandwidths[index]),
      alpha_lags[index]
    )
  },
  character(1L)
)

latex_lines_4e <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Fama--MacBeth Factor Premium and Pricing Errors}",
  "  \\label{tab:4e-fama-macbeth}",
  "  \\begin{minipage}{0.99\\textwidth}",
  "    \\centering",
  "    \\scriptsize",
  "    \\begin{tabular*}{\\linewidth}{@{\\extracolsep{\\fill}}lrrrrr@{}}",
  "      \\toprule",
  "      Quantity & Estimate & NW SE & $t$-statistic & BW & $L$ \\\\",
  "      \\midrule",
  "      \\multicolumn{6}{l}{\\textbf{Panel A: Average factor premium and pricing errors}} \\\\",
  sprintf(
    "      $\\hat{\\lambda}$ & %s & %s & %s & %s & %d \\\\",
    format_four_4e(lambda_result$estimate),
    format_four_4e(lambda_result$standard_error),
    format_four_4e(lambda_result$t_statistic),
    format_four_4e(lambda_result$bandwidth),
    lambda_result$lag_length
  ),
  alpha_rows,
  "      \\bottomrule",
  "    \\end{tabular*}",
  "",
  "    \\par\\smallskip",
  sprintf(
    paste0(
      "    {\\footnotesize\\raggedright \\textit{Note:} The sample covers %s--%s ",
      "($T=%d$). The factor is the gross market return $F_t=R_{w,t}$, and the ",
      "test assets are $xR_w$ and the 20 BM and MOM decile portfolios. First-pass ",
      "betas are fixed in the monthly cross-sectional regressions through the ",
      "origin. Each of the 22 intercept-only time-series regressions uses its own ",
      "Newey--West bandwidth, centered series, Bartlett weights, denominator ",
      "$T-\\ell$, ceiling-rounded pilot and final lags, no prewhitening, and no ",
      "additional degrees-of-freedom adjustment.\\par}"
    ),
    format(sample_start, "%B %Y"),
    format(sample_end, "%B %Y"),
    T_obs
  ),
  "  \\end{minipage}",
  "\\end{table}"
)

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
writeLines(latex_lines_4e, tex_path_4e)

cat("Question 4e results\n")
cat("Sample:", format(sample_start), "to", format(sample_end), "\n")
cat("T:", T_obs, "observations\n")
cat("lambda_hat:", format(lambda_result$estimate, digits = 12L), "\n")
cat("se_lambda_hat:", format(lambda_result$standard_error, digits = 12L), "\n")
cat("t_lambda_hat:", format(lambda_result$t_statistic, digits = 12L), "\n")
cat("lambda bandwidth / lags:", format(lambda_result$bandwidth, digits = 12L), "/", lambda_result$lag_length, "\n")
cat("first-pass normal-equation error:", format(time_series_normal_equation_error, digits = 12L), "\n")
cat("cross-sectional orthogonality error:", format(cross_sectional_orthogonality_error, digits = 12L), "\n")
cat("average-pricing-error identity error:", format(alpha_identity_error, digits = 12L), "\n\n")
print(
  data.frame(
    Portfolio = test_asset_names,
    Beta = beta_hat,
    Average_pricing_error = alpha_hat,
    NW_SE = se_alpha_hat,
    t_statistic = t_alpha_hat,
    Bandwidth = alpha_bandwidths,
    Lags = alpha_lags,
    row.names = NULL
  ),
  digits = 8L
)
