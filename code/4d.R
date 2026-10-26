# BUSFIN 8200 Problem Set 2, Question 4d
# Estimate the one-factor beta-pricing regressions and the GRS joint-alpha test.

tex_path_4d <- file.path("figures", "4d.tex")
matrix_tolerance <- 1e-10
J <- 20L
K_factors <- 1L

# Reproduce and reuse the complete validated 4b data-processing pipeline.
invisible(capture.output(source(file.path("code", "4b.R"), local = TRUE)))

F_factor <- gmm_data$xRw
asset_returns <- excess_returns[, -1L, drop = FALSE]
asset_names <- moment_names[-1L]
if (ncol(asset_returns) != J) {
  stop("The test-asset matrix does not contain the requested 20 decile portfolios.")
}

hac_score_covariance <- function(centered_scores) {
  selection <- bw_newey_west_ceiling(centered_scores)
  bandwidth <- selection$bandwidth
  pilot_lag <- selection$pilot_lag
  lag_length <- ceiling(bandwidth)
  lag_length <- as.integer(lag_length)

  score_autocovariance <- function(lag) {
    current <- centered_scores[(lag + 1L):T_obs, , drop = FALSE]
    lagged <- centered_scores[seq_len(T_obs - lag), , drop = FALSE]
    crossprod(current, lagged) / (T_obs - lag)
  }

  S_HAC <- score_autocovariance(0L)
  if (lag_length > 0L) {
    for (lag in seq_len(lag_length)) {
      Gamma_l <- score_autocovariance(lag)
      weight <- 1 - lag / (lag_length + 1)
      S_HAC <- S_HAC + weight * (Gamma_l + t(Gamma_l))
    }
  }
  S_HAC <- (S_HAC + t(S_HAC)) / 2

  list(
    S_HAC = S_HAC,
    bandwidth = bandwidth,
    pilot_lag = pilot_lag,
    lag_length = lag_length
  )
}

ols_with_hac <- function(y, X, coefficient_names) {
  if (length(y) != T_obs || nrow(X) != T_obs) {
    stop("An OLS regression does not use the validated common sample.")
  }
  if (qr(X)$rank < ncol(X)) {
    stop("An OLS design matrix is rank deficient.")
  }

  beta_hat <- as.vector(solve(crossprod(X), crossprod(X, y)))
  names(beta_hat) <- coefficient_names
  residuals <- as.vector(y - X %*% beta_hat)

  score_matrix <- sweep(X, 1L, residuals, FUN = "*")
  centered_scores <- sweep(score_matrix, 2L, colMeans(score_matrix), FUN = "-")
  hac <- hac_score_covariance(centered_scores)

  bread <- solve(crossprod(X) / T_obs)
  covariance <- bread %*% hac$S_HAC %*% bread / T_obs
  covariance <- (covariance + t(covariance)) / 2
  standard_errors <- sqrt(pmax(diag(covariance), 0))
  names(standard_errors) <- coefficient_names

  list(
    coefficients = beta_hat,
    residuals = residuals,
    score_means = colMeans(score_matrix),
    covariance = covariance,
    standard_errors = standard_errors,
    bandwidth = hac$bandwidth,
    pilot_lag = hac$pilot_lag,
    lag_length = hac$lag_length
  )
}

# Factor-premium regression: F_t = lambda + e_t.
factor_regression <- ols_with_hac(
  y = F_factor,
  X = matrix(1, nrow = T_obs, ncol = 1L),
  coefficient_names = "lambda"
)
lambda_hat <- factor_regression$coefficients["lambda"]
se_lambda_hat <- factor_regression$standard_errors["lambda"]
t_lambda_hat <- lambda_hat / se_lambda_hat
if (abs(lambda_hat - mean(F_factor)) > 1e-12) {
  stop("The intercept-only OLS estimate does not equal the sample factor mean.")
}

# Test-asset regressions: xR_j,t = alpha_j + beta_j F_t + epsilon_j,t.
X_assets <- cbind(intercept = 1, factor = F_factor)
asset_regressions <- lapply(
  seq_len(J),
  function(index) {
    ols_with_hac(
      y = asset_returns[, index],
      X = X_assets,
      coefficient_names = c("alpha", "beta")
    )
  }
)

alpha_hat <- vapply(
  asset_regressions,
  function(result) result$coefficients["alpha"],
  numeric(1L)
)
beta_hat <- vapply(
  asset_regressions,
  function(result) result$coefficients["beta"],
  numeric(1L)
)
se_alpha_hat <- vapply(
  asset_regressions,
  function(result) result$standard_errors["alpha"],
  numeric(1L)
)
t_alpha_hat <- alpha_hat / se_alpha_hat
asset_bandwidths <- vapply(
  asset_regressions,
  function(result) result$bandwidth,
  numeric(1L)
)
asset_lags <- vapply(
  asset_regressions,
  function(result) result$lag_length,
  integer(1L)
)
residual_matrix <- do.call(
  cbind,
  lapply(asset_regressions, function(result) result$residuals)
)
colnames(residual_matrix) <- asset_names

Sigma_epsilon <- crossprod(residual_matrix) / T_obs
Sigma_epsilon <- (Sigma_epsilon + t(Sigma_epsilon)) / 2
if (any(!is.finite(Sigma_epsilon))) {
  stop("The GRS residual covariance matrix contains non-finite values.")
}
sigma_symmetry_error <- max(abs(Sigma_epsilon - t(Sigma_epsilon)))
sigma_eigenvalues <- eigen(
  Sigma_epsilon,
  symmetric = TRUE,
  only.values = TRUE
)$values
if (sigma_symmetry_error > matrix_tolerance ||
    min(sigma_eigenvalues) <= matrix_tolerance) {
  stop(
    "The GRS residual covariance matrix is not symmetric positive definite ",
    "within tolerance 1e-10."
  )
}
Sigma_epsilon_inverse <- tryCatch(
  solve(Sigma_epsilon),
  error = function(error) {
    stop("The GRS residual covariance matrix could not be inverted: ", conditionMessage(error))
  }
)

mean_F <- mean(F_factor)
variance_F <- mean((F_factor - mean_F)^2)
if (!is.finite(variance_F) || variance_F <= 0) {
  stop("The denominator-T factor variance is not positive and finite.")
}
df1 <- J
df2 <- T_obs - J - K_factors
GRS_statistic <- as.numeric(
  ((T_obs - J - K_factors) / J) *
    (t(alpha_hat) %*% Sigma_epsilon_inverse %*% alpha_hat) /
    (1 + mean_F^2 / variance_F)
)
GRS_p_value <- pf(GRS_statistic, df1 = df1, df2 = df2, lower.tail = FALSE)

format_four_4d <- function(x) {
  adjusted <- ifelse(round(x, 4L) == 0, 0, x)
  sprintf("%.4f", adjusted)
}

asset_rows <- vapply(
  seq_len(J),
  function(index) {
    sprintf(
      "      %s $\\alpha$ & %s & %s & %s & %s & %s & %d \\\\",
      asset_names[index],
      format_four_4d(alpha_hat[index]),
      format_four_4d(beta_hat[index]),
      format_four_4d(se_alpha_hat[index]),
      format_four_4d(t_alpha_hat[index]),
      format_four_4d(asset_bandwidths[index]),
      asset_lags[index]
    )
  },
  character(1L)
)

latex_lines_4d <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Market-Factor Time-Series Regressions and GRS Test}",
  "  \\label{tab:4d-regressions}",
  "  \\begin{minipage}{0.99\\textwidth}",
  "    \\centering",
  "    \\scriptsize",
  "    \\begin{tabular*}{\\linewidth}{@{\\extracolsep{\\fill}}lrrrrrr@{}}",
  "      \\toprule",
  "      Quantity & Estimate & $\\hat{\\beta}$ & NW SE & $t$-statistic & BW & $L$ \\\\",
  "      \\midrule",
  "      \\multicolumn{7}{l}{\\textbf{Panel A: Factor premium and portfolio alphas}} \\\\",
  sprintf(
    "      $\\hat{\\lambda}$ & %s & 1.0000 & %s & %s & %s & %d \\\\",
    format_four_4d(lambda_hat),
    format_four_4d(se_lambda_hat),
    format_four_4d(t_lambda_hat),
    format_four_4d(factor_regression$bandwidth),
    factor_regression$lag_length
  ),
  asset_rows,
  "      \\midrule",
  "      \\multicolumn{7}{l}{\\textbf{Panel B: GRS joint-alpha test}} \\\\",
  sprintf(
    "      GRS statistic & %s & \\multicolumn{2}{c}{$df_1=%d$} & \\multicolumn{2}{c}{$df_2=%d$} & $p=%s$ \\\\",
    format_four_4d(GRS_statistic),
    df1,
    df2,
    format_four_4d(GRS_p_value)
  ),
  "      \\bottomrule",
  "    \\end{tabular*}",
  "",
  "    \\par\\smallskip",
  sprintf(
    paste0(
      "    {\\footnotesize\\raggedright \\textit{Note:} The sample covers %s--%s ",
      "($T=%d$) and the factor is $F_t=xR_{w,t}$. Each regression uses its own ",
      "sum-of-centered-score Newey--West bandwidth, Bartlett weights, denominator ",
      "$T-\\ell$, ceiling-rounded pilot and final lags, and no prewhitening. OLS ",
      "sandwich covariances use sample-average normalization without an additional ",
      "degrees-of-freedom adjustment. The GRS residual covariance minimum eigenvalue ",
      "is %.4f under tolerance $10^{-10}$.\\par}"
    ),
    format(sample_start, "%B %Y"),
    format(sample_end, "%B %Y"),
    T_obs,
    min(sigma_eigenvalues)
  ),
  "  \\end{minipage}",
  "\\end{table}"
)

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
writeLines(latex_lines_4d, tex_path_4d)

cat("Question 4d results\n")
cat("Sample:", format(sample_start), "to", format(sample_end), "\n")
cat("T:", T_obs, "observations\n")
cat("lambda_hat:", format(lambda_hat, digits = 12L), "\n")
cat("se_lambda_hat:", format(se_lambda_hat, digits = 12L), "\n")
cat("t_lambda_hat:", format(t_lambda_hat, digits = 12L), "\n")
cat("lambda bandwidth / lags:", format(factor_regression$bandwidth, digits = 12L), "/", factor_regression$lag_length, "\n")
cat("Sigma_epsilon symmetry error:", format(sigma_symmetry_error, digits = 12L), "\n")
cat("Sigma_epsilon minimum eigenvalue:", format(min(sigma_eigenvalues), digits = 12L), "\n")
cat("mean_F:", format(mean_F, digits = 12L), "\n")
cat("variance_F:", format(variance_F, digits = 12L), "\n")
cat("GRS statistic:", format(GRS_statistic, digits = 12L), "\n")
cat("degrees of freedom:", df1, ",", df2, "\n")
cat("GRS p-value:", format(GRS_p_value, digits = 12L), "\n\n")
print(
  data.frame(
    Portfolio = asset_names,
    Alpha = alpha_hat,
    Beta = beta_hat,
    NW_SE_alpha = se_alpha_hat,
    t_alpha = t_alpha_hat,
    Bandwidth = asset_bandwidths,
    Lags = asset_lags,
    row.names = NULL
  ),
  digits = 8L
)
