# BUSFIN 8200 Problem Set 2, Question 3c
# Estimate identity-weighted GMM with market and managed-portfolio moments.

data_path <- file.path("data", "EQ Dataset.csv")
ps1_forecast_path <- file.path("code", "2e_1.csv")
forecast_output_path <- file.path("figures", "3c_OS_xRE.csv")
tex_path <- file.path("figures", "3c.tex")
csv_path <- file.path("figures", "3c.csv")

sample_start <- as.Date("1940-12-01")
sample_end <- as.Date("2021-12-01")
base_bounds <- c(-10, 10)
sensitivity_bounds <- list(c(-20, 20), c(-50, 50))
grid_spacing <- 0.01
optimization_tolerance <- .Machine$double.eps^0.5

EQ <- read.csv(data_path, check.names = FALSE, stringsAsFactors = FALSE)
required_columns <- c("YEAR", "MONTH", "dp", "dg", "rf", "re")
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
EQ$D_P <- exp(EQ$dp)
EQ$G <- exp(EQ$dg)

if (!file.exists(ps1_forecast_path)) {
  stop(
    "Missing ", ps1_forecast_path,
    "; run code/2d_PS1.R and code/2e_PS1.R before Question 3c."
  )
}

ps1_forecast <- read.csv(
  ps1_forecast_path,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
required_forecast_columns <- c(
  "forecast_origin_date", "target_date", "out_of_sample_forecast"
)
missing_forecast_columns <- setdiff(
  required_forecast_columns,
  names(ps1_forecast)
)
if (length(missing_forecast_columns) > 0L) {
  stop(
    "The PS1 forecast output is missing: ",
    paste(missing_forecast_columns, collapse = ", ")
  )
}

ps1_forecast$forecast_origin_date <- as.Date(
  ps1_forecast$forecast_origin_date
)
ps1_forecast$target_date <- as.Date(ps1_forecast$target_date)

# Reconstruct the restricted PS1 2(e) forecasts and verify the saved output.
origin_index <- match(ps1_forecast$forecast_origin_date, EQ$date)
target_index <- match(ps1_forecast$target_date, EQ$date)
if (anyNA(origin_index) || anyNA(target_index)) {
  stop("One or more PS1 forecast dates do not match the EQ dataset.")
}
if (any(target_index - origin_index != 12L)) {
  stop("The PS1 forecast timing is not a twelve-month origin-to-target span.")
}

first_growth_index <- match(as.Date("1928-12-01"), EQ$date)
reconstructed_forecast <- numeric(nrow(ps1_forecast))
expanding_G_mean <- numeric(nrow(ps1_forecast))

for (i in seq_len(nrow(ps1_forecast))) {
  expanding_index <- seq.int(first_growth_index, origin_index[i])
  expanding_G_mean[i] <- mean(EQ$G[expanding_index])
  a_OS <- expanding_G_mean[i] - 1
  b_OS <- expanding_G_mean[i]
  reconstructed_forecast[i] <- a_OS + b_OS * EQ$D_P[origin_index[i]]
}

forecast_difference <- reconstructed_forecast -
  ps1_forecast$out_of_sample_forecast
if (max(abs(forecast_difference)) > 1e-12) {
  stop("The reconstructed forecast does not reproduce code/2e_PS1.R.")
}

forecast_output <- data.frame(
  forecast_origin = ps1_forecast$forecast_origin_date,
  target_date = ps1_forecast$target_date,
  OS_xRE_forecast = reconstructed_forecast,
  stringsAsFactors = FALSE
)

if (nrow(forecast_output) != 973L ||
    forecast_output$forecast_origin[1L] != as.Date("1939-12-01") ||
    forecast_output$target_date[1L] != sample_start ||
    tail(forecast_output$target_date, 1L) != sample_end) {
  stop("The reproduced forecast does not have the requested dates or length.")
}

realized_data <- data.frame(
  target_date = EQ$date,
  re = EQ$re,
  Rw = EQ$Rw,
  Rf = EQ$Rf,
  xRw = EQ$xRw,
  stringsAsFactors = FALSE
)

gmm_data <- merge(
  forecast_output,
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
if (nrow(gmm_data) != 973L || min(gmm_data$target_date) != sample_start ||
    max(gmm_data$target_date) != sample_end ||
    anyDuplicated(gmm_data$target_date)) {
  stop("The merged GMM sample does not match December 1940--December 2021.")
}

expected_target_dates <- seq.Date(sample_start, sample_end, by = "month")
if (!identical(gmm_data$target_date, expected_target_dates)) {
  stop("The merged GMM sample has one or more missing months.")
}

T_obs <- nrow(gmm_data)
sigma_e_squared <- mean((gmm_data$Rw - mean(gmm_data$Rw))^2)
if (!is.finite(sigma_e_squared) || sigma_e_squared <= 0) {
  stop("The denominator-T variance of Rw is not positive and finite.")
}
gmm_data$z_lag <- gmm_data$OS_xRE_forecast / sigma_e_squared
gmm_data$managed <- gmm_data$z_lag * gmm_data$xRw

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

gmm_objective <- function(gamma) {
  moments <- mean_moments(gamma)
  as.numeric(crossprod(moments))
}

run_optimization <- function(bounds) {
  optimize(
    f = gmm_objective,
    interval = bounds,
    tol = optimization_tolerance
  )
}

base_optimization <- run_optimization(base_bounds)
gamma_hat <- base_optimization$minimum
objective_hat <- base_optimization$objective

objective_grid_gamma <- seq(
  from = base_bounds[1L],
  to = base_bounds[2L],
  by = grid_spacing
)
objective_grid_value <- vapply(
  objective_grid_gamma,
  gmm_objective,
  numeric(1L)
)
grid_minimum_index <- which.min(objective_grid_value)
grid_gamma_hat <- objective_grid_gamma[grid_minimum_index]
grid_objective_hat <- objective_grid_value[grid_minimum_index]

sensitivity_optimizations <- lapply(sensitivity_bounds, run_optimization)
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

if (gamma_hat <= base_bounds[1L] || gamma_hat >= base_bounds[2L] ||
    any(sensitivity_gamma <= vapply(sensitivity_bounds, `[`, numeric(1L), 1L)) ||
    any(sensitivity_gamma >= vapply(sensitivity_bounds, `[`, numeric(1L), 2L))) {
  stop("At least one GMM estimate is on a numerical search boundary.")
}
if (abs(grid_gamma_hat - gamma_hat) > grid_spacing) {
  stop("The objective grid does not confirm the bounded optimizer solution.")
}

fitted_moments <- moment_matrix(gamma_hat)
alpha_hat <- colMeans(fitted_moments)
G_hat <- matrix(
  c(
    mean(-gmm_data$re * fitted_moments[, "market"]),
    mean(-gmm_data$re * fitted_moments[, "managed"])
  ),
  ncol = 1L,
  dimnames = list(c("market", "managed"), "gamma")
)
first_order_condition <- as.numeric(crossprod(G_hat, alpha_hat))

# Bartlett bwNeweyWest bandwidth selection with ceiling rounding for the
# pilot truncation and no prewhitening, as specified for Question 3b.
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
    pilot_lag = pilot_lag,
    optimal_constant = optimal_constant
  )
}

centered_moments <- sweep(fitted_moments, 2L, alpha_hat, FUN = "-")
bandwidth_selection <- bw_newey_west_ceiling(centered_moments)
bandwidth_hat <- bandwidth_selection$bandwidth
pilot_lag <- bandwidth_selection$pilot_lag
L <- ceiling(bandwidth_hat)

matrix_autocovariance <- function(lag) {
  current <- centered_moments[(lag + 1L):T_obs, , drop = FALSE]
  lagged <- centered_moments[seq_len(T_obs - lag), , drop = FALSE]
  crossprod(current, lagged) / (T_obs - lag)
}

S_HAC_hat <- matrix_autocovariance(0L)
if (L > 0L) {
  for (lag in seq_len(L)) {
    Gamma_l <- matrix_autocovariance(lag)
    weight <- 1 - lag / (L + 1)
    S_HAC_hat <- S_HAC_hat + weight * (Gamma_l + t(Gamma_l))
  }
}
S_HAC_hat <- (S_HAC_hat + t(S_HAC_hat)) / 2

G_crossprod_inverse <- 1 / as.numeric(crossprod(G_hat))
avar_gamma_hat <- as.numeric(
  G_crossprod_inverse * crossprod(G_hat, S_HAC_hat %*% G_hat) *
    G_crossprod_inverse / T_obs
)
se_gamma_hat <- sqrt(avar_gamma_hat)
t_gamma_hat <- gamma_hat / se_gamma_hat

K <- diag(2L) - G_hat %*% (G_crossprod_inverse * t(G_hat))
avar_alpha_hat <- K %*% S_HAC_hat %*% t(K) / T_obs
avar_alpha_hat <- (avar_alpha_hat + t(avar_alpha_hat)) / 2
se_alpha_hat <- sqrt(pmax(diag(avar_alpha_hat), 0))
t_alpha_hat <- alpha_hat / se_alpha_hat

moore_penrose <- function(A) {
  decomposition <- svd(A)
  tolerance <- max(dim(A)) * max(decomposition$d) * .Machine$double.eps
  keep <- decomposition$d > tolerance
  inverse <- matrix(0, nrow = ncol(A), ncol = nrow(A))
  if (any(keep)) {
    inverse <- decomposition$v[, keep, drop = FALSE] %*%
      diag(1 / decomposition$d[keep], nrow = sum(keep)) %*%
      t(decomposition$u[, keep, drop = FALSE])
  }
  list(inverse = inverse, rank = sum(keep), tolerance = tolerance)
}

alpha_pseudoinverse <- moore_penrose(avar_alpha_hat)
alpha_rank <- alpha_pseudoinverse$rank
W_stat <- as.numeric(
  t(alpha_hat) %*% alpha_pseudoinverse$inverse %*% alpha_hat
)
p_value <- pchisq(W_stat, df = 1L, lower.tail = FALSE)

if (alpha_rank != 1L) {
  stop("The pricing-error covariance matrix does not have numerical rank one.")
}

max_sensitivity_difference <- max(abs(sensitivity_gamma - gamma_hat))
convergence_status <- if (
  abs(grid_gamma_hat - gamma_hat) <= grid_spacing &&
    max_sensitivity_difference <= grid_spacing
) {
  "Interior; grid and bounds checks passed"
} else {
  "Review numerical diagnostics"
}

summary_table <- data.frame(
  Statistic = c(
    "Gamma estimate",
    "Newey-West standard error",
    "Gamma t-statistic",
    "Market pricing error",
    "Market pricing-error Newey-West standard error",
    "Market pricing-error t-statistic",
    "Managed pricing error",
    "Managed pricing-error Newey-West standard error",
    "Managed pricing-error t-statistic",
    "Joint Wald statistic",
    "Joint-test p-value",
    "Number of observations",
    "Sample period",
    "Newey-West bandwidth",
    "Pilot truncation",
    "Bartlett lags",
    "Pricing-error covariance rank",
    "First-order condition",
    "Grid estimate on [-10,10]",
    "Sensitivity estimate on [-20,20]",
    "Sensitivity estimate on [-50,50]",
    "Convergence diagnostics"
  ),
  Value = c(
    sprintf("%.4f", gamma_hat),
    sprintf("%.4f", se_gamma_hat),
    sprintf("%.4f", t_gamma_hat),
    sprintf("%.4f", alpha_hat["market"]),
    sprintf("%.4f", se_alpha_hat["market"]),
    sprintf("%.4f", t_alpha_hat["market"]),
    sprintf("%.4f", alpha_hat["managed"]),
    sprintf("%.4f", se_alpha_hat["managed"]),
    sprintf("%.4f", t_alpha_hat["managed"]),
    sprintf("%.4f", W_stat),
    sprintf("%.4f", p_value),
    as.character(T_obs),
    paste0(format(sample_start, "%B %Y"), "--", format(sample_end, "%B %Y")),
    sprintf("%.4f", bandwidth_hat),
    as.character(pilot_lag),
    as.character(L),
    as.character(alpha_rank),
    sprintf("%.4f", first_order_condition),
    sprintf("%.4f", grid_gamma_hat),
    sprintf("%.4f", sensitivity_gamma[1L]),
    sprintf("%.4f", sensitivity_gamma[2L]),
    convergence_status
  ),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
write.csv(forecast_output, forecast_output_path, row.names = FALSE, quote = TRUE)
write.csv(summary_table, csv_path, row.names = FALSE, quote = TRUE)

latex_lines <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Identity-Weighted GMM with Market and Managed-Portfolio Moments}",
  "  \\label{tab:3c-gmm}",
  "  \\begin{tabular}{lr}",
  "    \\toprule",
  "    Statistic & Value \\\\",
  "    \\midrule",
  sprintf("    $\\hat{\\gamma}$ & %.4f \\\\" , gamma_hat),
  sprintf("    Newey--West standard error & %.4f \\\\" , se_gamma_hat),
  sprintf("    $\\hat{\\gamma}$ $t$-statistic & %.4f \\\\" , t_gamma_hat),
  sprintf("    Market pricing error & %.4f \\\\" , alpha_hat["market"]),
  sprintf("    Market pricing-error NW standard error & %.4f \\\\" , se_alpha_hat["market"]),
  sprintf("    Market pricing-error $t$-statistic & %.4f \\\\" , t_alpha_hat["market"]),
  sprintf("    Managed pricing error & %.4f \\\\" , alpha_hat["managed"]),
  sprintf("    Managed pricing-error NW standard error & %.4f \\\\" , se_alpha_hat["managed"]),
  sprintf("    Managed pricing-error $t$-statistic & %.4f \\\\" , t_alpha_hat["managed"]),
  sprintf("    Joint Wald statistic & %.4f \\\\" , W_stat),
  sprintf("    Joint-test $p$-value & %.4f \\\\" , p_value),
  sprintf("    Number of observations & %d \\\\" , T_obs),
  sprintf(
    "    Sample period & %s--%s \\\\" ,
    format(sample_start, "%B %Y"),
    format(sample_end, "%B %Y")
  ),
  sprintf("    Pricing-error covariance rank & %d \\\\" , alpha_rank),
  "    \\bottomrule",
  "  \\end{tabular}",
  sprintf(
    "  \\footnotesize{Note: The Bartlett bandwidth is %.4f; ceiling rounding gives pilot truncation %d and $L=%d$ lags. Lag-$\\ell$ autocovariances use denominator $T-\\ell$ and no prewhitening. The optimizer is interior; the 0.01 grid and $[-20,20]$ and $[-50,50]$ sensitivity checks agree to four decimals.}",
    bandwidth_hat,
    pilot_lag,
    L
  ),
  "\\end{table}"
)
writeLines(latex_lines, tex_path)

cat("Question 3c results\n")
cat("Sample:", format(sample_start), "to", format(sample_end), "\n")
cat("T:", T_obs, "observations\n")
cat("sigma_e_squared:", format(sigma_e_squared, digits = 12L), "\n")
cat("maximum PS1 forecast difference:", format(max(abs(forecast_difference)), digits = 12L), "\n")
cat("gamma_hat:", format(gamma_hat, digits = 12L), "\n")
cat("objective:", format(objective_hat, digits = 12L), "\n")
cat("grid gamma:", format(grid_gamma_hat, digits = 12L), "\n")
cat("grid objective:", format(grid_objective_hat, digits = 12L), "\n")
cat("sensitivity gamma:", paste(format(sensitivity_gamma, digits = 12L), collapse = ", "), "\n")
cat("sensitivity objective:", paste(format(sensitivity_objective, digits = 12L), collapse = ", "), "\n")
cat("alpha_hat:", paste(format(alpha_hat, digits = 12L), collapse = ", "), "\n")
cat("G_hat:", paste(format(G_hat[, 1L], digits = 12L), collapse = ", "), "\n")
cat("first-order condition:", format(first_order_condition, digits = 12L), "\n")
cat("Newey-West bandwidth:", format(bandwidth_hat, digits = 12L), "\n")
cat("pilot truncation:", pilot_lag, "\n")
cat("Newey-West lags:", L, "\n")
cat("S_HAC_hat:\n")
print(S_HAC_hat, digits = 12L)
cat("se_gamma_hat:", format(se_gamma_hat, digits = 12L), "\n")
cat("t_gamma_hat:", format(t_gamma_hat, digits = 12L), "\n")
cat("pricing-error standard errors:", paste(format(se_alpha_hat, digits = 12L), collapse = ", "), "\n")
cat("pricing-error t-statistics:", paste(format(t_alpha_hat, digits = 12L), collapse = ", "), "\n")
cat("pricing-error covariance rank:", alpha_rank, "\n")
cat("pseudoinverse tolerance:", format(alpha_pseudoinverse$tolerance, digits = 12L), "\n")
cat("Wald statistic:", format(W_stat, digits = 12L), "\n")
cat("p-value:", format(p_value, digits = 12L), "\n")
