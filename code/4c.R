# BUSFIN 8200 Problem Set 2, Question 4c
# Estimate the efficient two-step linear-SDF GMM model analytically.

tex_path_4c <- file.path("figures", "4c.tex")
positive_definite_tolerance <- 1e-10
relative_tolerance_4c <- 1e-10
expected_alpha_rank_4c <- 20L
wald_degrees_freedom_4c <- 20L

# Reproduce and reuse the complete validated 4b first-stage data processing,
# identity-weighted estimate, fitted moments, and HAC matrix.
invisible(capture.output(source(file.path("code", "4b.R"), local = TRUE)))

b_hat_1 <- b_hat
S_HAC_1 <- S_HAC_hat
bandwidth_1 <- bandwidth_hat
pilot_lag_1 <- pilot_lag
L_1 <- L

if (any(!is.finite(S_HAC_1))) {
  stop("The first-stage HAC matrix contains non-finite values.")
}
symmetry_error_1 <- max(abs(S_HAC_1 - t(S_HAC_1)))
if (symmetry_error_1 > positive_definite_tolerance) {
  stop("The first-stage HAC matrix is not symmetric within tolerance 1e-10.")
}
eigenvalues_1 <- eigen(S_HAC_1, symmetric = TRUE, only.values = TRUE)$values
if (min(eigenvalues_1) <= positive_definite_tolerance) {
  stop("The first-stage HAC matrix is not numerically positive definite.")
}
eigenvalue_ratio_1 <- min(eigenvalues_1) / max(eigenvalues_1)

W_2 <- tryCatch(
  solve(S_HAC_1),
  error = function(error) {
    stop("The first-stage HAC matrix could not be inverted: ", conditionMessage(error))
  }
)

mean_xR <- matrix(
  colMeans(excess_returns),
  ncol = 1L,
  dimnames = list(moment_names, "mean_xR")
)
cov_vector <- matrix(
  colMeans(sweep(excess_returns, 1L, market_deviation, FUN = "*")),
  ncol = 1L,
  dimnames = list(moment_names, "cov")
)

analytic_denominator <- as.numeric(t(cov_vector) %*% W_2 %*% cov_vector)
if (!is.finite(analytic_denominator) || analytic_denominator <= 0) {
  stop("The analytical second-stage denominator is not positive and finite.")
}
analytic_numerator <- as.numeric(t(cov_vector) %*% W_2 %*% mean_xR)
b_hat_2 <- analytic_numerator / analytic_denominator

moments_2 <- moment_matrix(b_hat_2)
alpha_hat_2 <- colMeans(moments_2)
alpha_analytic_2 <- as.vector(mean_xR - b_hat_2 * cov_vector)
names(alpha_analytic_2) <- moment_names
if (max(abs(alpha_hat_2 - alpha_analytic_2)) > 1e-12) {
  stop("The analytical and time-series definitions of the second-stage moments disagree.")
}

G_hat_2 <- -cov_vector
colnames(G_hat_2) <- "b"
first_order_condition_2 <- as.numeric(
  t(G_hat_2) %*% W_2 %*% alpha_hat_2
)
if (abs(first_order_condition_2) > 1e-8) {
  stop("The second-stage weighted first-order condition is not sufficiently close to zero.")
}

centered_moments_2 <- sweep(moments_2, 2L, alpha_hat_2, FUN = "-")
bandwidth_selection_2 <- bw_newey_west_ceiling(centered_moments_2)
bandwidth_2 <- bandwidth_selection_2$bandwidth
pilot_lag_2 <- bandwidth_selection_2$pilot_lag
L_2 <- ceiling(bandwidth_2)

matrix_autocovariance_2 <- function(lag) {
  current <- centered_moments_2[(lag + 1L):T_obs, , drop = FALSE]
  lagged <- centered_moments_2[seq_len(T_obs - lag), , drop = FALSE]
  crossprod(current, lagged) / (T_obs - lag)
}

S_HAC_2 <- matrix_autocovariance_2(0L)
if (L_2 > 0L) {
  for (lag in seq_len(L_2)) {
    Gamma_l <- matrix_autocovariance_2(lag)
    weight <- 1 - lag / (L_2 + 1)
    S_HAC_2 <- S_HAC_2 + weight * (Gamma_l + t(Gamma_l))
  }
}
S_HAC_2 <- (S_HAC_2 + t(S_HAC_2)) / 2
if (any(!is.finite(S_HAC_2))) {
  stop("The second-stage HAC matrix contains non-finite values.")
}

G_W_G_2 <- as.numeric(t(G_hat_2) %*% W_2 %*% G_hat_2)
if (!is.finite(G_W_G_2) || G_W_G_2 <= 0) {
  stop("The second-stage G'WG scalar is not positive and finite.")
}
G_W_G_inverse_2 <- 1 / G_W_G_2
avar_b_hat_2 <- as.numeric(
  G_W_G_inverse_2 *
    t(G_hat_2) %*% W_2 %*% S_HAC_2 %*% t(W_2) %*% G_hat_2 *
    G_W_G_inverse_2 / T_obs
)
se_b_hat_2 <- sqrt(avar_b_hat_2)
t_b_hat_2 <- b_hat_2 / se_b_hat_2

K_2 <- diag(length(moment_names)) -
  G_hat_2 %*% (G_W_G_inverse_2 * t(G_hat_2) %*% W_2)
if (max(abs(K_2 %*% G_hat_2)) > 1e-10) {
  stop("The second-stage pricing-error projection matrix does not annihilate G_hat_2.")
}
avar_alpha_hat_2 <- K_2 %*% S_HAC_2 %*% t(K_2) / T_obs
avar_alpha_hat_2 <- (avar_alpha_hat_2 + t(avar_alpha_hat_2)) / 2
se_alpha_hat_2 <- sqrt(pmax(diag(avar_alpha_hat_2), 0))
t_alpha_hat_2 <- alpha_hat_2 / se_alpha_hat_2

alpha_pseudoinverse_2 <- moore_penrose_relative(
  avar_alpha_hat_2,
  relative_tolerance_4c
)
alpha_rank_2 <- alpha_pseudoinverse_2$rank
if (alpha_rank_2 != expected_alpha_rank_4c) {
  stop(
    "The second-stage pricing-error covariance has numerical rank ",
    alpha_rank_2,
    ", not the expected rank ", expected_alpha_rank_4c, "."
  )
}

W_stat_2 <- as.numeric(
  t(alpha_hat_2) %*% alpha_pseudoinverse_2$inverse %*% alpha_hat_2
)
p_value_2 <- pchisq(
  W_stat_2,
  df = wald_degrees_freedom_4c,
  lower.tail = FALSE
)

format_four_4c <- function(x) {
  adjusted <- ifelse(round(x, 4L) == 0, 0, x)
  sprintf("%.4f", adjusted)
}

pricing_rows_2 <- vapply(
  seq_along(moment_names),
  function(index) {
    sprintf(
      "      %s pricing error & %s & %s & %s \\\\",
      moment_names[index],
      format_four_4c(alpha_hat_2[index]),
      format_four_4c(se_alpha_hat_2[index]),
      format_four_4c(t_alpha_hat_2[index])
    )
  },
  character(1L)
)

latex_lines_4c <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Efficient Two-Step Linear-SDF GMM with 21 Pricing Moments}",
  "  \\label{tab:4c-gmm}",
  "  \\begin{minipage}{0.98\\textwidth}",
  "    \\centering",
  "    \\scriptsize",
  "    \\begin{tabular*}{\\linewidth}{@{\\extracolsep{\\fill}}lrrr@{}}",
  "      \\toprule",
  "      Parameter / Moment & Estimate & NW SE & $t$-statistic \\\\",
  "      \\midrule",
  sprintf(
    "      $\\hat{b}_2$ & %s & %s & %s \\\\",
    format_four_4c(b_hat_2),
    format_four_4c(se_b_hat_2),
    format_four_4c(t_b_hat_2)
  ),
  pricing_rows_2,
  "      \\midrule",
  sprintf(
    "      Joint pricing-error test & %s & $df=%d$ & $p=%s$ \\\\",
    format_four_4c(W_stat_2),
    wald_degrees_freedom_4c,
    format_four_4c(p_value_2)
  ),
  "      \\bottomrule",
  "    \\end{tabular*}",
  "",
  "    \\par\\smallskip",
  sprintf(
    paste0(
      "    {\\footnotesize\\raggedright \\textit{Note:} The sample covers %s--%s ",
      "($T=%d$), with $\\overline{R}_w=%.4f$ treated as fixed. The first- and ",
      "second-stage Bartlett bandwidths are %.4f and %.4f, giving $L_1=%d$ and ",
      "$L_2=%d$. Lag-$\\ell$ autocovariances use denominator $T-\\ell$ and no ",
      "prewhitening. The first-stage HAC minimum eigenvalue is %.4f and its ",
      "minimum/maximum eigenvalue ratio is %.4f. The analytical denominator is ",
      "%.4f, the weighted first-order condition is %.4e, and the second-stage ",
      "pricing-error covariance has numerical rank %d under relative tolerance ",
      "$10^{-10}$.\\par}"
    ),
    format(sample_start, "%B %Y"),
    format(sample_end, "%B %Y"),
    T_obs,
    mean_Rw,
    bandwidth_1,
    bandwidth_2,
    L_1,
    L_2,
    min(eigenvalues_1),
    eigenvalue_ratio_1,
    analytic_denominator,
    first_order_condition_2,
    alpha_rank_2
  ),
  "  \\end{minipage}",
  "\\end{table}"
)

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
writeLines(latex_lines_4c, tex_path_4c)

cat("Question 4c results\n")
cat("GMM sample:", format(sample_start), "to", format(sample_end), "\n")
cat("T:", T_obs, "observations\n")
cat("mean_Rw:", format(mean_Rw, digits = 12L), "\n")
cat("b_hat_1:", format(b_hat_1, digits = 12L), "\n")
cat("first-stage bandwidth / lags:", format(bandwidth_1, digits = 12L), "/", L_1, "\n")
cat("S_HAC_1 symmetry error:", format(symmetry_error_1, digits = 12L), "\n")
cat("S_HAC_1 minimum eigenvalue:", format(min(eigenvalues_1), digits = 12L), "\n")
cat("S_HAC_1 eigenvalue ratio:", format(eigenvalue_ratio_1, digits = 12L), "\n")
cat("analytic denominator:", format(analytic_denominator, digits = 12L), "\n")
cat("b_hat_2:", format(b_hat_2, digits = 12L), "\n")
cat("weighted first-order condition:", format(first_order_condition_2, digits = 12L), "\n")
cat("second-stage bandwidth / lags:", format(bandwidth_2, digits = 12L), "/", L_2, "\n")
cat("se_b_hat_2:", format(se_b_hat_2, digits = 12L), "\n")
cat("t_b_hat_2:", format(t_b_hat_2, digits = 12L), "\n")
cat("pricing-error covariance rank:", alpha_rank_2, "\n")
cat("pseudoinverse threshold:", format(alpha_pseudoinverse_2$threshold, digits = 12L), "\n")
cat("Wald statistic:", format(W_stat_2, digits = 12L), "\n")
cat("degrees of freedom:", wald_degrees_freedom_4c, "\n")
cat("p-value:", format(p_value_2, digits = 12L), "\n\n")
print(
  data.frame(
    Moment = moment_names,
    Pricing_error = alpha_hat_2,
    NW_SE = se_alpha_hat_2,
    t_statistic = t_alpha_hat_2,
    row.names = NULL
  ),
  digits = 8L
)
