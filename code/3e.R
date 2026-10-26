# BUSFIN 8200 Problem Set 2, Question 3e
# Estimate identity-weighted GMM with the market and 20 annual decile returns.

eq_path <- file.path("data", "EQ Dataset.csv")
be_me_path <- file.path("data", "BE_ME.csv")
momentum_path <- file.path("data", "10P_MOM.csv")
rf_path <- file.path("data", "RF.csv")
tex_path <- file.path("figures", "3e.tex")
csv_path <- file.path("figures", "3e.csv")

monthly_start <- 192701L
monthly_end <- 202608L
base_bounds <- c(-10, 10)
sensitivity_bounds <- list(c(-20, 20), c(-50, 50))
optimization_tolerance <- 1e-10
grid_spacing <- 0.01
relative_tolerance <- 1e-10
expected_alpha_rank <- 20L
wald_degrees_freedom <- 20L

be_me_columns <- c(
  "Lo 10", "2-Dec", "3-Dec", "4-Dec", "5-Dec",
  "6-Dec", "7-Dec", "8-Dec", "9-Dec", "Hi 10"
)
momentum_columns <- c(
  "Lo PRIOR", "PRIOR 2", "PRIOR 3", "PRIOR 4", "PRIOR 5",
  "PRIOR 6", "PRIOR 7", "PRIOR 8", "PRIOR 9", "Hi PRIOR"
)
moment_names <- c(
  "Market",
  paste0("BM D", seq_len(10L)),
  paste0("MOM D", seq_len(10L))
)

read_csv_section <- function(path, header_index, row_pattern = "^\\s*[0-9]{6},") {
  lines <- readLines(path, warn = FALSE)
  data_indices <- seq.int(header_index + 1L, length(lines))
  data_indices <- data_indices[grepl(row_pattern, lines[data_indices])]
  if (length(data_indices) == 0L) {
    stop("No monthly observations found after the selected header in ", path)
  }

  breaks <- which(diff(data_indices) != 1L)
  if (length(breaks) > 0L) {
    data_indices <- data_indices[seq_len(breaks[1L])]
  }

  section_text <- paste(c(lines[header_index], lines[data_indices]), collapse = "\n")
  section <- read.csv(
    text = section_text,
    check.names = FALSE,
    strip.white = TRUE,
    stringsAsFactors = FALSE
  )
  names(section)[1L] <- "YYYYMM"
  section$YYYYMM <- as.integer(trimws(as.character(section$YYYYMM)))
  section
}

read_value_weighted_monthly <- function(path) {
  lines <- readLines(path, warn = FALSE)
  labels <- grep("^\\s*Value Weight Returns -- Monthly\\s*$", lines)
  if (length(labels) != 1L) {
    stop("Could not uniquely identify the value-weighted monthly panel in ", path)
  }
  read_csv_section(path, labels + 1L)
}

read_monthly_rf <- function(path) {
  lines <- readLines(path, warn = FALSE)
  headers <- grep("^,Mkt-RF,SMB,HML,RF\\s*$", lines)
  if (length(headers) < 1L) {
    stop("Could not identify the monthly factor header in ", path)
  }
  read_csv_section(path, headers[1L])
}

be_me <- read_value_weighted_monthly(be_me_path)
momentum <- read_value_weighted_monthly(momentum_path)
rf <- read_monthly_rf(rf_path)

required_be_me <- c("YYYYMM", be_me_columns)
required_momentum <- c("YYYYMM", momentum_columns)
if (!all(required_be_me %in% names(be_me))) {
  stop("BE_ME.csv is missing one or more requested value-weighted deciles.")
}
if (!all(required_momentum %in% names(momentum))) {
  stop("10P_MOM.csv is missing one or more requested value-weighted deciles.")
}
if (!all(c("YYYYMM", "RF") %in% names(rf))) {
  stop("RF.csv is missing YYYYMM or RF.")
}

be_me <- be_me[
  be_me$YYYYMM >= monthly_start & be_me$YYYYMM <= monthly_end,
  required_be_me
]
momentum <- momentum[
  momentum$YYYYMM >= monthly_start & momentum$YYYYMM <= monthly_end,
  required_momentum
]
rf <- rf[
  rf$YYYYMM >= monthly_start & rf$YYYYMM <= monthly_end,
  c("YYYYMM", "RF")
]
names(be_me)[-1L] <- paste0("BM_D", seq_len(10L))
names(momentum)[-1L] <- paste0("MOM_D", seq_len(10L))

if (anyDuplicated(be_me$YYYYMM) || anyDuplicated(momentum$YYYYMM) ||
    anyDuplicated(rf$YYYYMM)) {
  stop("Duplicate YYYYMM observations occur in a selected monthly panel.")
}

monthly <- Reduce(
  function(x, y) merge(x, y, by = "YYYYMM", all = FALSE, sort = TRUE),
  list(be_me, momentum, rf)
)
expected_months <- seq.Date(
  as.Date("1927-01-01"),
  as.Date("2026-08-01"),
  by = "month"
)
monthly_dates <- as.Date(paste0(monthly$YYYYMM, "01"), format = "%Y%m%d")
if (nrow(monthly) == 0L || min(monthly$YYYYMM) != monthly_start ||
    max(monthly$YYYYMM) != monthly_end ||
    !identical(monthly_dates, expected_months)) {
  stop("The merged monthly data do not form the requested gap-free 192701--202608 sample.")
}

return_columns <- c(paste0("BM_D", seq_len(10L)), paste0("MOM_D", seq_len(10L)))
raw_monthly_values <- as.matrix(monthly[, c(return_columns, "RF"), drop = FALSE])
if (anyNA(raw_monthly_values) || any(!is.finite(raw_monthly_values)) ||
    any(raw_monthly_values %in% c(-99.99, -999))) {
  stop(
    "Missing, non-finite, or sentinel values occur in the selected monthly data; ",
    "implementation paused as required by prompt/3e.md."
  )
}

monthly_returns <- as.matrix(monthly[, return_columns, drop = FALSE]) / 100
monthly_rf <- monthly$RF / 100
if (any(1 + monthly_returns <= 0) || any(1 + monthly_rf <= 0)) {
  stop("At least one monthly gross return is nonpositive.")
}

rolling_product <- function(values, window = 12L) {
  n <- nrow(values)
  result <- matrix(NA_real_, nrow = n - window + 1L, ncol = ncol(values))
  for (index in seq.int(window, n)) {
    result[index - window + 1L, ] <- apply(
      1 + values[(index - window + 1L):index, , drop = FALSE],
      2L,
      prod
    )
  }
  colnames(result) <- colnames(values)
  result
}

annual_portfolio_gross <- rolling_product(monthly_returns)
annual_rf_gross <- as.vector(rolling_product(matrix(monthly_rf, ncol = 1L)))
annual_dates <- monthly_dates[12L:length(monthly_dates)]
annual_yyyymm <- monthly$YYYYMM[12L:nrow(monthly)]
annual_excess <- sweep(annual_portfolio_gross, 1L, annual_rf_gross, FUN = "-")
colnames(annual_excess) <- return_columns

for (index in seq_along(annual_dates)) {
  window_dates <- monthly_dates[index:(index + 11L)]
  if (!identical(window_dates, seq.Date(window_dates[1L], window_dates[12L], by = "month"))) {
    stop("An annual portfolio return does not contain 12 consecutive months.")
  }
}

annual_data <- data.frame(
  YYYYMM = annual_yyyymm,
  annual_excess,
  check.names = FALSE
)

eq <- read.csv(eq_path, check.names = FALSE, stringsAsFactors = FALSE)
required_eq <- c("YEAR", "MONTH", "rf", "re")
if (!all(required_eq %in% names(eq))) {
  stop("EQ Dataset.csv is missing one or more required columns.")
}
eq <- eq[, required_eq]
if (anyNA(eq) || any(!is.finite(as.matrix(eq)))) {
  stop(
    "Missing or non-finite values occur in the selected EQ data; ",
    "implementation paused as required by prompt/3e.md."
  )
}
eq$YYYYMM <- as.integer(eq$YEAR * 100L + eq$MONTH)
eq$Rw <- exp(eq$re)
eq$Rf <- exp(eq$rf)
eq$xRw <- eq$Rw - eq$Rf

gmm_data <- merge(
  eq[, c("YYYYMM", "re", "Rw", "Rf", "xRw")],
  annual_data,
  by = "YYYYMM",
  all = FALSE,
  sort = TRUE
)
required_gmm <- c("re", "Rw", "Rf", "xRw", return_columns)
if (nrow(gmm_data) == 0L || anyNA(gmm_data[, required_gmm]) ||
    any(!is.finite(as.matrix(gmm_data[, required_gmm])))) {
  stop(
    "Missing or non-finite values occur after the annual-return merge; ",
    "implementation paused as required by prompt/3e.md."
  )
}
if (anyDuplicated(gmm_data$YYYYMM)) {
  stop("Duplicate YYYYMM observations occur in the merged GMM sample.")
}

sample_dates <- as.Date(paste0(gmm_data$YYYYMM, "01"), format = "%Y%m%d")
expected_gmm_dates <- seq.Date(min(sample_dates), max(sample_dates), by = "month")
if (!identical(sample_dates, expected_gmm_dates)) {
  stop("The merged GMM sample has one or more missing months.")
}

T_obs <- nrow(gmm_data)
sample_start <- min(sample_dates)
sample_end <- max(sample_dates)
excess_returns <- cbind(
  Market = gmm_data$xRw,
  as.matrix(gmm_data[, paste0("BM_D", seq_len(10L)), drop = FALSE]),
  as.matrix(gmm_data[, paste0("MOM_D", seq_len(10L)), drop = FALSE])
)
colnames(excess_returns) <- moment_names

moment_matrix <- function(gamma) {
  sweep(excess_returns, 1L, gmm_data$Rw^(-gamma), FUN = "*")
}

mean_moments <- function(gamma) {
  colMeans(moment_matrix(gamma))
}

gmm_objective <- function(gamma) {
  moments <- mean_moments(gamma)
  as.numeric(crossprod(moments))
}

run_optimization <- function(bounds) {
  optimize(gmm_objective, interval = bounds, tol = optimization_tolerance)
}

optimization <- run_optimization(base_bounds)
gamma_hat <- optimization$minimum
objective_hat <- optimization$objective

grid_gamma <- seq(base_bounds[1L], base_bounds[2L], by = grid_spacing)
grid_objective <- vapply(grid_gamma, gmm_objective, numeric(1L))
grid_gamma_hat <- grid_gamma[which.min(grid_objective)]

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
  colMeans(sweep(fitted_moments, 1L, -gmm_data$re, FUN = "*")),
  ncol = 1L,
  dimnames = list(moment_names, "gamma")
)
first_order_condition <- as.numeric(crossprod(G_hat, alpha_hat))
if (abs(objective_hat - as.numeric(crossprod(alpha_hat))) > 1e-12) {
  stop("The fitted objective does not equal the sum of squared pricing errors.")
}
if (abs(first_order_condition) > 1e-8) {
  stop("The identity-weighted GMM first-order condition is not sufficiently close to zero.")
}

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

  pilot_covariances <- vapply(0:pilot_lag, pilot_autocovariance, numeric(1L))
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

K <- diag(length(moment_names)) -
  G_hat %*% (G_crossprod_inverse * t(G_hat))
if (max(abs(K %*% G_hat)) > 1e-10) {
  stop("The pricing-error projection matrix does not annihilate G_hat.")
}
avar_alpha_hat <- K %*% S_HAC_hat %*% t(K) / T_obs
avar_alpha_hat <- (avar_alpha_hat + t(avar_alpha_hat)) / 2
se_alpha_hat <- sqrt(pmax(diag(avar_alpha_hat), 0))
t_alpha_hat <- alpha_hat / se_alpha_hat

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

alpha_pseudoinverse <- moore_penrose_relative(
  avar_alpha_hat,
  relative_tolerance
)
alpha_rank <- alpha_pseudoinverse$rank
if (alpha_rank != expected_alpha_rank) {
  stop(
    "The pricing-error covariance matrix has numerical rank ", alpha_rank,
    ", not the expected rank ", expected_alpha_rank, "."
  )
}

W_stat <- as.numeric(
  t(alpha_hat) %*% alpha_pseudoinverse$inverse %*% alpha_hat
)
p_value <- pchisq(W_stat, df = wald_degrees_freedom, lower.tail = FALSE)

max_sensitivity_difference <- max(abs(sensitivity_gamma - gamma_hat))
convergence_status <- if (
  abs(grid_gamma_hat - gamma_hat) <= grid_spacing &&
    max_sensitivity_difference <= grid_spacing
) {
  "Interior; grid and bounds checks passed"
} else {
  "Review numerical diagnostics"
}

format_four <- function(x) {
  adjusted <- ifelse(round(x, 4L) == 0, 0, x)
  sprintf("%.4f", adjusted)
}

primary_table <- data.frame(
  Statistic = c("Gamma estimate", paste0(moment_names, " pricing error")),
  Estimate = format_four(c(gamma_hat, alpha_hat)),
  `Newey-West SE` = format_four(c(se_gamma_hat, se_alpha_hat)),
  `t-statistic` = format_four(c(t_gamma_hat, t_alpha_hat)),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

diagnostic_table <- data.frame(
  Statistic = c(
    "Joint Wald statistic",
    "Joint-test degrees of freedom",
    "Joint-test p-value",
    "Number of observations",
    "Sample period",
    "Newey-West bandwidth",
    "Pilot truncation",
    "Bartlett lags",
    "Pricing-error covariance rank",
    "First-order condition",
    "GMM objective",
    "Grid estimate on [-10,10]",
    "Sensitivity estimate on [-20,20]",
    "Sensitivity estimate on [-50,50]",
    "Convergence diagnostics"
  ),
  Estimate = c(
    format_four(W_stat),
    as.character(wald_degrees_freedom),
    format_four(p_value),
    as.character(T_obs),
    paste0(format(sample_start, "%B %Y"), "--", format(sample_end, "%B %Y")),
    format_four(bandwidth_hat),
    as.character(pilot_lag),
    as.character(L),
    as.character(alpha_rank),
    format_four(first_order_condition),
    format_four(objective_hat),
    format_four(grid_gamma_hat),
    format_four(sensitivity_gamma[1L]),
    format_four(sensitivity_gamma[2L]),
    convergence_status
  ),
  `Newey-West SE` = "",
  `t-statistic` = "",
  check.names = FALSE,
  stringsAsFactors = FALSE
)
summary_table <- rbind(primary_table, diagnostic_table)

dir.create("figures", recursive = TRUE, showWarnings = FALSE)
write.csv(summary_table, csv_path, row.names = FALSE, quote = TRUE)

pricing_rows <- vapply(
  seq_along(moment_names),
  function(index) {
    sprintf(
      "      %s pricing error & %s & %s & %s \\\\",
      moment_names[index],
      format_four(alpha_hat[index]),
      format_four(se_alpha_hat[index]),
      format_four(t_alpha_hat[index])
    )
  },
  character(1L)
)

latex_lines <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Identity-Weighted GMM with 21 Pricing Moments}",
  "  \\label{tab:3e-gmm}",
  "  \\begin{minipage}{0.98\\textwidth}",
  "    \\centering",
  "    \\scriptsize",
  "    \\begin{tabular*}{\\linewidth}{@{\\extracolsep{\\fill}}lrrr@{}}",
  "      \\toprule",
  "      Parameter / Moment & Estimate & NW SE & $t$-statistic \\\\",
  "      \\midrule",
  sprintf(
    "      $\\hat{\\gamma}$ & %s & %s & %s \\\\",
    format_four(gamma_hat),
    format_four(se_gamma_hat),
    format_four(t_gamma_hat)
  ),
  pricing_rows,
  "      \\midrule",
  sprintf(
    "      Joint pricing-error test & %s & $df=%d$ & $p=%s$ \\\\",
    format_four(W_stat),
    wald_degrees_freedom,
    format_four(p_value)
  ),
  "      \\bottomrule",
  "    \\end{tabular*}",
  "",
  "    \\par\\smallskip",
  sprintf(
    paste0(
      "    {\\footnotesize\\raggedright \\textit{Note:} The sample covers %s--%s ",
      "($T=%d$). The Bartlett bandwidth is %.4f; ceiling rounding gives pilot ",
      "truncation $m=%d$ and $L=%d$. Lag-$\\ell$ autocovariances use denominator ",
      "$T-\\ell$ and no prewhitening. The pricing-error covariance has numerical ",
      "rank %d under relative tolerance $10^{-10}$. The optimizer is interior; ",
      "the 0.01 grid and wider-bound checks passed.\\par}"
    ),
    format(sample_start, "%B %Y"),
    format(sample_end, "%B %Y"),
    T_obs,
    bandwidth_hat,
    pilot_lag,
    L,
    alpha_rank
  ),
  "  \\end{minipage}",
  "\\end{table}"
)
writeLines(latex_lines, tex_path)

cat("Question 3e results\n")
cat("Monthly construction sample:", monthly_start, "to", monthly_end, "\n")
cat("GMM sample:", format(sample_start), "to", format(sample_end), "\n")
cat("T:", T_obs, "observations\n")
cat("gamma_hat:", format(gamma_hat, digits = 12L), "\n")
cat("objective:", format(objective_hat, digits = 12L), "\n")
cat("grid gamma:", format(grid_gamma_hat, digits = 12L), "\n")
cat("sensitivity gamma:", paste(format(sensitivity_gamma, digits = 12L), collapse = ", "), "\n")
cat("sensitivity objective:", paste(format(sensitivity_objective, digits = 12L), collapse = ", "), "\n")
cat("first-order condition:", format(first_order_condition, digits = 12L), "\n")
cat("Newey-West bandwidth:", format(bandwidth_hat, digits = 12L), "\n")
cat("pilot truncation:", pilot_lag, "\n")
cat("Newey-West lags:", L, "\n")
cat("se_gamma_hat:", format(se_gamma_hat, digits = 12L), "\n")
cat("t_gamma_hat:", format(t_gamma_hat, digits = 12L), "\n")
cat("pricing-error covariance rank:", alpha_rank, "\n")
cat("pseudoinverse threshold:", format(alpha_pseudoinverse$threshold, digits = 12L), "\n")
cat("Wald statistic:", format(W_stat, digits = 12L), "\n")
cat("degrees of freedom:", wald_degrees_freedom, "\n")
cat("p-value:", format(p_value, digits = 12L), "\n\n")
print(
  data.frame(
    Moment = moment_names,
    Pricing_error = alpha_hat,
    NW_SE = se_alpha_hat,
    t_statistic = t_alpha_hat,
    row.names = NULL
  ),
  digits = 8L
)
