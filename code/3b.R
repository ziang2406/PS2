# BUSFIN 8200 Problem Set 2, Question 3b
# Estimate CRRA gamma by one-moment GMM and compute its Newey-West standard error.

data_path <- file.path("data", "EQ Dataset.csv")
tex_path <- file.path("figures", "3b.tex")
csv_path <- file.path("figures", "3b.csv")

sample_start <- 192712L
sample_end <- 202112L
gamma_bounds <- c(-10, 10)
digits_to_report <- 4L

if (!requireNamespace("sandwich", quietly = TRUE)) {
  stop("Package 'sandwich' is required for bwNeweyWest().")
}

data <- read.csv(data_path, check.names = FALSE, stringsAsFactors = FALSE)
required_columns <- c("YEAR", "MONTH", "rf", "re")
missing_columns <- setdiff(required_columns, names(data))
if (length(missing_columns) > 0L) {
  stop("EQ Dataset.csv is missing: ", paste(missing_columns, collapse = ", "))
}

selected <- data[, required_columns]
if (anyNA(selected) || any(!is.finite(as.matrix(selected)))) {
  stop(
    "Missing or non-finite values occur in the requested variables; ",
    "implementation paused as required by the prompt."
  )
}

selected$YYYYMM <- as.integer(selected$YEAR * 100L + selected$MONTH)
selected <- selected[
  selected$YYYYMM >= sample_start & selected$YYYYMM <= sample_end,
  c("YYYYMM", "YEAR", "MONTH", "rf", "re")
]
selected <- selected[order(selected$YYYYMM), ]

if (nrow(selected) == 0L || min(selected$YYYYMM) != sample_start ||
    max(selected$YYYYMM) != sample_end) {
  stop("The selected data do not span the requested 192712--202112 sample.")
}
if (anyDuplicated(selected$YYYYMM)) {
  stop("Duplicate YEAR-MONTH observations occur in the requested sample.")
}

sample_dates <- as.Date(paste0(selected$YYYYMM, "01"), format = "%Y%m%d")
expected_dates <- seq.Date(
  as.Date("1927-12-01"),
  as.Date("2021-12-01"),
  by = "month"
)
if (!identical(sample_dates, expected_dates)) {
  stop(
    "The requested sample has one or more missing months; ",
    "implementation paused as required by the prompt."
  )
}

Rw <- exp(selected$re)
Rf <- exp(selected$rf)
xRw <- Rw - Rf
T_obs <- nrow(selected)

moment_values <- function(gamma) {
  Rw^(-gamma) * xRw
}

sample_moment <- function(gamma) {
  mean(moment_values(gamma))
}

gmm_objective <- function(gamma) {
  sample_moment(gamma)^2
}

optimization <- optimize(
  f = gmm_objective,
  interval = gamma_bounds,
  tol = .Machine$double.eps^0.5
)

gamma_hat <- optimization$minimum
moment_hat <- sample_moment(gamma_hat)
objective_hat <- optimization$objective

# Derivative of e_t(gamma) evaluated at the fitted gamma.
G_hat <- mean(-selected$re * exp(-gamma_hat * selected$re) * xRw)

e_hat <- moment_values(gamma_hat)
u_hat <- e_hat - mean(e_hat)

# bwNeweyWest returns a real-valued bandwidth. The corresponding Newey-West
# lag convention is its integer floor.
bandwidth_hat <- sandwich::bwNeweyWest(
  matrix(u_hat, ncol = 1L),
  kernel = "Bartlett",
  prewhite = FALSE
)
L <- floor(bandwidth_hat)

autocovariance <- function(lag) {
  sum(u_hat[(lag + 1L):T_obs] * u_hat[seq_len(T_obs - lag)]) / T_obs
}

Gamma_0 <- autocovariance(0L)
if (L > 0L) {
  lags <- seq_len(L)
  Gamma_l <- vapply(lags, autocovariance, numeric(1L))
  bartlett_weights <- 1 - lags / (L + 1)
  S_HAC_hat <- Gamma_0 + 2 * sum(bartlett_weights * Gamma_l)
} else {
  S_HAC_hat <- Gamma_0
}

avar_gamma_hat <- S_HAC_hat / (T_obs * G_hat^2)
se_gamma_hat <- sqrt(avar_gamma_hat)
t_stat <- gamma_hat / se_gamma_hat
moment_hat_for_table <- if (round(moment_hat, digits_to_report) == 0) 0 else moment_hat

sample_period <- paste0(
  format(min(sample_dates), "%B %Y"),
  "--",
  format(max(sample_dates), "%B %Y")
)

summary_table <- data.frame(
  Statistic = c(
    "Gamma estimate",
    "Sample moment at gamma estimate",
    "GMM objective",
    "Newey-West standard error",
    "t-statistic",
    "G estimate",
    "S HAC estimate",
    "Number of observations",
    "Sample period"
  ),
  Value = c(
    sprintf("%.4f", gamma_hat),
    sprintf("%.4f", moment_hat_for_table),
    sprintf("%.4f", objective_hat),
    sprintf("%.4f", se_gamma_hat),
    sprintf("%.4f", t_stat),
    sprintf("%.4f", G_hat),
    sprintf("%.4f", S_HAC_hat),
    as.character(T_obs),
    sample_period
  ),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

dir.create(dirname(tex_path), recursive = TRUE, showWarnings = FALSE)
write.csv(summary_table, csv_path, row.names = FALSE, quote = TRUE)

latex_lines <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{One-Moment GMM Estimate of Risk Aversion}",
  "  \\label{tab:3b-gmm}",
  "  \\begin{tabular}{lr}",
  "    \\toprule",
  "    Statistic & Value \\\\",
  "    \\midrule",
  sprintf("    $\\hat{\\gamma}$ & %.4f \\\\" , gamma_hat),
  sprintf("    $\\widehat{\\mathbb{E}}[e(\\hat{\\gamma})]$ & %.4f \\\\" , moment_hat_for_table),
  sprintf("    $\\widehat{\\mathbb{E}}[e(\\hat{\\gamma})]^2$ & %.4f \\\\" , objective_hat),
  sprintf("    Newey--West standard error & %.4f \\\\" , se_gamma_hat),
  sprintf("    $t$-statistic & %.4f \\\\" , t_stat),
  sprintf("    $\\hat{G}$ & %.4f \\\\" , G_hat),
  sprintf("    $\\hat{S}^{\\mathrm{HAC}}$ & %.4f \\\\" , S_HAC_hat),
  sprintf("    Number of observations & %d \\\\" , T_obs),
  sprintf("    Sample period & %s \\\\" , sample_period),
  "    \\bottomrule",
  "  \\end{tabular}",
  sprintf(
    "  \\footnotesize{Note: The Newey--West bandwidth is %.4f; its integer floor gives $L=%d$ Bartlett lags. Prewhitening is not used.}",
    bandwidth_hat,
    L
  ),
  "\\end{table}"
)
writeLines(latex_lines, tex_path)

cat("Question 3b results\n")
cat("Sample:", min(selected$YYYYMM), "to", max(selected$YYYYMM), "\n")
cat("T:", T_obs, "observations\n")
cat("gamma_hat:", format(gamma_hat, digits = 12L), "\n")
cat("sample moment:", format(moment_hat, digits = 12L), "\n")
cat("objective:", format(objective_hat, digits = 12L), "\n")
cat("G_hat:", format(G_hat, digits = 12L), "\n")
cat("Newey-West bandwidth:", format(bandwidth_hat, digits = 12L), "\n")
cat("Newey-West lags:", L, "\n")
cat("S_HAC_hat:", format(S_HAC_hat, digits = 12L), "\n")
cat("se_gamma_hat:", format(se_gamma_hat, digits = 12L), "\n")
cat("t_stat:", format(t_stat, digits = 12L), "\n")
