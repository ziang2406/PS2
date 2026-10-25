# BUSFIN 8200 Problem Set 2, Question 3d
# Estimate two-step GMM using the validated 3c forecast and estimation sample.

data_path <- file.path("data", "EQ Dataset.csv")
forecast_path <- file.path("figures", "3c_OS_xRE.csv")
tex_path <- file.path("figures", "3d.tex")
csv_path <- file.path("figures", "3d.csv")

sample_start <- as.Date("1940-12-01")
sample_end <- as.Date("2021-12-01")
base_bounds <- c(-10, 10)
sensitivity_bounds <- list(c(-20, 20), c(-50, 50))
grid_spacing <- 0.01
optimization_tolerance <- 1e-10
relative_tolerance <- 1e-10

EQ <- read.csv(data_path, check.names = FALSE, stringsAsFactors = FALSE)
required_columns <- c("YEAR", "MONTH", "rf", "re")
missing_columns <- setdiff(required_columns, names(EQ))
if (length(missing_columns) > 0L) {
  stop("EQ Dataset.csv is missing: ", paste(missing_columns, collapse = ", "))
}
if (anyNA(EQ[, required_columns]) ||
    any(!is.finite(as.matrix(EQ[, required_columns])))) {
  stop(
    "Missing or non-finite values occur in the required EQ variables; ",
    "implementation paused as required by the prompt."
  )
}

EQ$date <- as.Date(sprintf("%04d-%02d-01", EQ$YEAR, EQ$MONTH))
month_index <- 12L * EQ$YEAR + EQ$MONTH
if (anyDuplicated(month_index) || any(diff(month_index) != 1L)) {
  stop("The EQ dataset contains duplicate or missing monthly dates.")
}
EQ$Rw <- exp(EQ$re)
EQ$Rf <- exp(EQ$rf)
EQ$xRw <- EQ$Rw - EQ$Rf

if (!file.exists(forecast_path)) {
  stop("Missing validated Question 3c forecast file: ", forecast_path)
}
forecast <- read.csv(forecast_path, check.names = FALSE, stringsAsFactors = FALSE)
required_forecast_columns <- c(
  "forecast_origin", "target_date", "OS_xRE_forecast"
)
missing_forecast_columns <- setdiff(required_forecast_columns, names(forecast))
if (length(missing_forecast_columns) > 0L) {
  stop(
    "The validated Question 3c forecast is missing: ",
    paste(missing_forecast_columns, collapse = ", ")
  )
}
forecast$forecast_origin <- as.Date(forecast$forecast_origin)
forecast$target_date <- as.Date(forecast$target_date)

realized_data <- data.frame(
  target_date = EQ$date,
  re = EQ$re,
  Rw = EQ$Rw,
  Rf = EQ$Rf,
  xRw = EQ$xRw,
  stringsAsFactors = FALSE
)
gmm_data <- merge(
  forecast,
  realized_data,
  by = "target_date",
  all = FALSE,
  sort = TRUE
)
gmm_data <- gmm_data[
  gmm_data$target_date >= sample_start & gmm_data$target_date <= sample_end,
]

required_gmm_columns <- c("OS_xRE_forecast", "re", "Rw", "Rf", "xRw")
if (nrow(gmm_data) == 0L || anyNA(gmm_data[, required_gmm_columns]) ||
    any(!is.finite(as.matrix(gmm_data[, required_gmm_columns])))) {
  stop(
    "Missing or non-finite values occur after the target-date merge; ",
    "implementation paused as required by the prompt."
  )
}

T_obs <- nrow(gmm_data)
expected_dates <- seq.Date(sample_start, sample_end, by = "month")
if (T_obs != 973L || min(gmm_data$target_date) != sample_start ||
    max(gmm_data$target_date) != sample_end ||
    anyDuplicated(gmm_data$target_date) ||
    !identical(gmm_data$target_date, expected_dates)) {
  stop("The reused 3c estimation sample has changed.")
}
if (gmm_data$forecast_origin[1L] != as.Date("1939-12-01") ||
    any(match(gmm_data$target_date, EQ$date) -
      match(gmm_data$forecast_origin, EQ$date) != 12L)) {
  stop("The reused 3c forecast timing has changed.")
}

sigma_e_squared <- mean((gmm_data$Rw - mean(gmm_data$Rw))^2)
if (!is.finite(sigma_e_squared) || sigma_e_squared <= 0) {
  stop("The denominator-T variance of Rw is not positive and finite.")
}
gmm_data$z_lag <- gmm_data$OS_xRE_forecast / sigma_e_squared
gmm_data$managed <- gmm_data$z_lag * gmm_data$xRw
if (any(!is.finite(gmm_data$z_lag)) || any(!is.finite(gmm_data$managed))) {
  stop("The reused 3c instrument or managed return is non-finite.")
}

moment_matrix <- function(gamma) {
  sdf <- gmm_data$Rw^(-gamma)
  cbind(
    market = sdf * gmm_data$xRw,
    managed = sdf * gmm_data$managed
  )
}

mean_moments <- function(gamma) {
  colMeans(moment_matrix(gamma))
}

derivative_matrix <- function(gamma) {
  moments <- moment_matrix(gamma)
  matrix(
    c(
      mean(-gmm_data$re * moments[, "market"]),
      mean(-gmm_data$re * moments[, "managed"])
    ),
    ncol = 1L,
    dimnames = list(c("market", "managed"), "gamma")
  )
}

# Bartlett bwNeweyWest selector with the inherited ceiling pilot rule and no
# prewhitening. The final HAC autocovariances use denominator T-lag.
bw_newey_west_ceiling <- function(centered_moments) {
  n <- nrow(centered_moments)
  pilot_lag <- ceiling(4 * (n / 100)^(2 / 9))
  selector_series <- as.vector(centered_moments %*% rep(1, ncol(centered_moments)))

  pilot_autocovariance <- function(lag) {
    sum(
      selector_series[seq_len(n - lag)] *
        selector_series[(lag + 1L):n]
    ) / n
  }

  pilot_covariances <- vapply(
    0:pilot_lag,
    pilot_autocovariance,
    numeric(1L)
  )
  s0 <- pilot_covariances[1L] + 2 * sum(pilot_covariances[-1L])
  pilot_lags <- seq_len(pilot_lag)
  s1 <- 2 * sum(pilot_lags * pilot_covariances[-1L])
  optimal_constant <- 1.1447 * ((s1 / s0)^2)^(1 / 3)

  list(
    bandwidth = optimal_constant * n^(1 / 3),
    pilot_lag = pilot_lag
  )
}

hac_matrix <- function(fitted_moments) {
  centered <- sweep(fitted_moments, 2L, colMeans(fitted_moments), FUN = "-")
  selection <- bw_newey_west_ceiling(centered)
  bandwidth <- selection$bandwidth
  lag_length <- ceiling(bandwidth)

  autocovariance <- function(lag) {
    current <- centered[(lag + 1L):T_obs, , drop = FALSE]
    lagged <- centered[seq_len(T_obs - lag), , drop = FALSE]
    crossprod(current, lagged) / (T_obs - lag)
  }

  S_HAC <- autocovariance(0L)
  if (lag_length > 0L) {
    for (lag in seq_len(lag_length)) {
      Gamma_l <- autocovariance(lag)
      weight <- 1 - lag / (lag_length + 1)
      S_HAC <- S_HAC + weight * (Gamma_l + t(Gamma_l))
    }
  }
  S_HAC <- (S_HAC + t(S_HAC)) / 2

  list(
    S_HAC = S_HAC,
    bandwidth = bandwidth,
    pilot_lag = selection$pilot_lag,
    lag_length = lag_length
  )
}

run_optimization <- function(objective, bounds) {
  optimize(
    f = objective,
    interval = bounds,
    tol = optimization_tolerance
  )
}

# Step 1: identity-weighted GMM.
objective_1 <- function(gamma) {
  moments <- mean_moments(gamma)
  as.numeric(crossprod(moments))
}
optimization_1 <- run_optimization(objective_1, base_bounds)
gamma_hat_1 <- optimization_1$minimum
moments_1 <- moment_matrix(gamma_hat_1)
G_hat_1 <- derivative_matrix(gamma_hat_1)
hac_1 <- hac_matrix(moments_1)
S_HAC_1 <- hac_1$S_HAC

eigenvalues_1 <- eigen(S_HAC_1, symmetric = TRUE, only.values = TRUE)$values
eigenvalue_ratio_1 <- min(eigenvalues_1) / max(eigenvalues_1)
if (any(!is.finite(eigenvalues_1)) || min(eigenvalues_1) <= 0 ||
    eigenvalue_ratio_1 <= relative_tolerance) {
  stop(
    "S_HAC_1 failed the positive-definite/invertibility criterion; ",
    "implementation paused as required by the prompt."
  )
}
W_2 <- solve(S_HAC_1)
W_2 <- (W_2 + t(W_2)) / 2

# Step 2: efficient weighting matrix fixed throughout each optimization.
objective_2 <- function(gamma) {
  moments <- mean_moments(gamma)
  as.numeric(t(moments) %*% W_2 %*% moments)
}
optimization_2 <- run_optimization(objective_2, base_bounds)
gamma_hat_2 <- optimization_2$minimum
objective_hat_2 <- optimization_2$objective

grid_gamma <- seq(base_bounds[1L], base_bounds[2L], by = grid_spacing)
grid_objective <- vapply(grid_gamma, objective_2, numeric(1L))
grid_minimum_index <- which.min(grid_objective)
grid_gamma_hat <- grid_gamma[grid_minimum_index]

sensitivity_optimizations <- lapply(
  sensitivity_bounds,
  function(bounds) run_optimization(objective_2, bounds)
)
sensitivity_gamma <- vapply(
  sensitivity_optimizations,
  function(result) result$minimum,
  numeric(1L)
)
sensitivity_objective <- vapply(
  sensitivity_optimizations,
  function(result) result$objective,
  numeric(1L)
)

if (gamma_hat_2 <= base_bounds[1L] || gamma_hat_2 >= base_bounds[2L] ||
    any(sensitivity_gamma <= vapply(sensitivity_bounds, `[`, numeric(1L), 1L)) ||
    any(sensitivity_gamma >= vapply(sensitivity_bounds, `[`, numeric(1L), 2L))) {
  stop("At least one second-stage estimate is on a search boundary.")
}
if (abs(grid_gamma_hat - gamma_hat_2) > grid_spacing) {
  stop("The objective grid does not confirm the second-stage optimum.")
}

moments_2 <- moment_matrix(gamma_hat_2)
alpha_hat_2 <- colMeans(moments_2)
G_hat_2 <- derivative_matrix(gamma_hat_2)
first_order_condition_2 <- as.numeric(
  t(G_hat_2) %*% W_2 %*% alpha_hat_2
)
hac_2 <- hac_matrix(moments_2)
S_HAC_2 <- hac_2$S_HAC

G_W_G <- as.numeric(t(G_hat_2) %*% W_2 %*% G_hat_2)
G_W_G_inverse <- 1 / G_W_G
avar_gamma_hat_2 <- as.numeric(
  G_W_G_inverse *
    t(G_hat_2) %*% W_2 %*% S_HAC_2 %*% t(W_2) %*% G_hat_2 *
    G_W_G_inverse / T_obs
)
se_gamma_hat_2 <- sqrt(avar_gamma_hat_2)

K_2 <- diag(2L) -
  G_hat_2 %*% (G_W_G_inverse * t(G_hat_2) %*% W_2)
avar_alpha_hat_2 <- K_2 %*% S_HAC_2 %*% t(K_2) / T_obs
avar_alpha_hat_2 <- (avar_alpha_hat_2 + t(avar_alpha_hat_2)) / 2
se_alpha_hat_2 <- sqrt(pmax(diag(avar_alpha_hat_2), 0))
t_alpha_hat_2 <- alpha_hat_2 / se_alpha_hat_2

moore_penrose_relative <- function(A, relative_cutoff) {
  decomposition <- svd(A)
  threshold <- max(decomposition$d) * relative_cutoff
  keep <- decomposition$d > threshold
  inverse <- matrix(0, nrow = ncol(A), ncol = nrow(A))
  if (any(keep)) {
    inverse <- decomposition$v[, keep, drop = FALSE] %*%
      diag(1 / decomposition$d[keep], nrow = sum(keep)) %*%
      t(decomposition$u[, keep, drop = FALSE])
  }
  list(inverse = inverse, rank = sum(keep), threshold = threshold)
}

alpha_pseudoinverse_2 <- moore_penrose_relative(
  avar_alpha_hat_2,
  relative_tolerance
)
alpha_rank_2 <- alpha_pseudoinverse_2$rank
if (alpha_rank_2 != 1L) {
  stop("The second-stage pricing-error covariance does not have rank one.")
}
W_stat_2 <- as.numeric(
  t(alpha_hat_2) %*% alpha_pseudoinverse_2$inverse %*% alpha_hat_2
)
p_value_2 <- pchisq(W_stat_2, df = 1L, lower.tail = FALSE)

max_sensitivity_difference <- max(abs(sensitivity_gamma - gamma_hat_2))
first_order_condition_for_table <- if (
  round(first_order_condition_2, 4L) == 0
) 0 else first_order_condition_2
convergence_status <- if (
  abs(grid_gamma_hat - gamma_hat_2) <= grid_spacing &&
    max_sensitivity_difference <= grid_spacing
) {
  "Interior; grid and bounds checks passed"
} else {
  "Review numerical diagnostics"
}

summary_table <- data.frame(
  Statistic = c(
    "Second-stage gamma estimate",
    "Newey-West standard error",
    "Market pricing error",
    "Market pricing-error t-statistic",
    "Managed pricing error",
    "Managed pricing-error t-statistic",
    "Joint Wald statistic",
    "Joint-test p-value",
    "Number of observations",
    "Sample period",
    "Stage-one bandwidth",
    "Stage-one Bartlett lags",
    "Stage-one minimum/maximum eigenvalue ratio",
    "Stage-two bandwidth",
    "Stage-two Bartlett lags",
    "Pricing-error covariance rank",
    "Second-stage first-order condition",
    "Grid estimate on [-10,10]",
    "Sensitivity estimate on [-20,20]",
    "Sensitivity estimate on [-50,50]",
    "Convergence diagnostics"
  ),
  Value = c(
    sprintf("%.4f", gamma_hat_2),
    sprintf("%.4f", se_gamma_hat_2),
    sprintf("%.4f", alpha_hat_2["market"]),
    sprintf("%.4f", t_alpha_hat_2["market"]),
    sprintf("%.4f", alpha_hat_2["managed"]),
    sprintf("%.4f", t_alpha_hat_2["managed"]),
    sprintf("%.4f", W_stat_2),
    sprintf("%.4f", p_value_2),
    as.character(T_obs),
    paste0(format(sample_start, "%B %Y"), "--", format(sample_end, "%B %Y")),
    sprintf("%.4f", hac_1$bandwidth),
    as.character(hac_1$lag_length),
    sprintf("%.4f", eigenvalue_ratio_1),
    sprintf("%.4f", hac_2$bandwidth),
    as.character(hac_2$lag_length),
    as.character(alpha_rank_2),
    sprintf("%.4f", first_order_condition_for_table),
    sprintf("%.4f", grid_gamma_hat),
    sprintf("%.4f", sensitivity_gamma[1L]),
    sprintf("%.4f", sensitivity_gamma[2L]),
    convergence_status
  ),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
write.csv(summary_table, csv_path, row.names = FALSE, quote = TRUE)

latex_lines <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Two-Step GMM with Market and Managed-Portfolio Moments}",
  "  \\label{tab:3d-gmm}",
  "  \\begin{tabular}{lr}",
  "    \\toprule",
  "    Statistic & Value \\\\",
  "    \\midrule",
  sprintf("    $\\hat{\\gamma}_2$ & %.4f \\\\" , gamma_hat_2),
  sprintf("    Newey--West standard error & %.4f \\\\" , se_gamma_hat_2),
  sprintf("    Market pricing error & %.4f \\\\" , alpha_hat_2["market"]),
  sprintf("    Market pricing-error $t$-statistic & %.4f \\\\" , t_alpha_hat_2["market"]),
  sprintf("    Managed pricing error & %.4f \\\\" , alpha_hat_2["managed"]),
  sprintf("    Managed pricing-error $t$-statistic & %.4f \\\\" , t_alpha_hat_2["managed"]),
  sprintf("    Joint Wald statistic & %.4f \\\\" , W_stat_2),
  sprintf("    Joint-test $p$-value & %.4f \\\\" , p_value_2),
  sprintf("    Number of observations & %d \\\\" , T_obs),
  sprintf(
    "    Sample period & %s--%s \\\\" ,
    format(sample_start, "%B %Y"),
    format(sample_end, "%B %Y")
  ),
  sprintf("    Pricing-error covariance rank & %d \\\\" , alpha_rank_2),
  "    \\bottomrule",
  "  \\end{tabular}",
  sprintf(
    "  \\footnotesize{Note: Stage-one and stage-two Bartlett bandwidths are %.4f and %.4f, giving $L_1=%d$ and $L_2=%d$ after ceiling rounding. Lag-$\\ell$ autocovariances use denominator $T-\\ell$ and no prewhitening. The stage-one eigenvalue ratio is %.4f. The optimizer is interior; the 0.01 grid and wider-bound checks agree to four decimals.}",
    hac_1$bandwidth,
    hac_2$bandwidth,
    hac_1$lag_length,
    hac_2$lag_length,
    eigenvalue_ratio_1
  ),
  "\\end{table}"
)
writeLines(latex_lines, tex_path)

cat("Question 3d results\n")
cat("Sample:", format(sample_start), "to", format(sample_end), "\n")
cat("T:", T_obs, "observations\n")
cat("sigma_e_squared:", format(sigma_e_squared, digits = 12L), "\n")
cat("gamma_hat_1:", format(gamma_hat_1, digits = 12L), "\n")
cat("S_HAC_1 eigenvalues:", paste(format(eigenvalues_1, digits = 12L), collapse = ", "), "\n")
cat("S_HAC_1 eigenvalue ratio:", format(eigenvalue_ratio_1, digits = 12L), "\n")
cat("stage-one bandwidth / lags:", format(hac_1$bandwidth, digits = 12L), "/", hac_1$lag_length, "\n")
cat("gamma_hat_2:", format(gamma_hat_2, digits = 12L), "\n")
cat("objective_2:", format(objective_hat_2, digits = 12L), "\n")
cat("grid gamma:", format(grid_gamma_hat, digits = 12L), "\n")
cat("sensitivity gamma:", paste(format(sensitivity_gamma, digits = 12L), collapse = ", "), "\n")
cat("sensitivity objective:", paste(format(sensitivity_objective, digits = 12L), collapse = ", "), "\n")
cat("alpha_hat_2:", paste(format(alpha_hat_2, digits = 12L), collapse = ", "), "\n")
cat("G_hat_2:", paste(format(G_hat_2[, 1L], digits = 12L), collapse = ", "), "\n")
cat("first-order condition_2:", format(first_order_condition_2, digits = 12L), "\n")
cat("stage-two bandwidth / lags:", format(hac_2$bandwidth, digits = 12L), "/", hac_2$lag_length, "\n")
cat("S_HAC_2:\n")
print(S_HAC_2, digits = 12L)
cat("se_gamma_hat_2:", format(se_gamma_hat_2, digits = 12L), "\n")
cat("pricing-error standard errors:", paste(format(se_alpha_hat_2, digits = 12L), collapse = ", "), "\n")
cat("pricing-error t-statistics:", paste(format(t_alpha_hat_2, digits = 12L), collapse = ", "), "\n")
cat("pricing-error covariance rank:", alpha_rank_2, "\n")
cat("pseudoinverse threshold:", format(alpha_pseudoinverse_2$threshold, digits = 12L), "\n")
cat("Wald statistic:", format(W_stat_2, digits = 12L), "\n")
cat("p-value:", format(p_value_2, digits = 12L), "\n")
