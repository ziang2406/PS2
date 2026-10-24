# BUSFIN 8200 Problem Set 2, Question 2c
# Estimate linear SDFs for the BE/ME portfolios, momentum portfolios, and
# their combined 20-portfolio cross-section over a common monthly sample.

be_me_path <- file.path("data", "BE_ME.csv")
momentum_path <- file.path("data", "10P_MOM.csv")
rf_path <- file.path("data", "RF.csv")
figure_path <- file.path("figures", "2c.png")
table_path <- file.path("figures", "2c_sharpe_ratios.tex")

sample_start <- 192701L
sample_end <- 202608L

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

check_requested_columns <- function(data, columns, label) {
  missing_columns <- setdiff(c("YYYYMM", columns), names(data))
  if (length(missing_columns) > 0L) {
    stop(label, " data are missing: ", paste(missing_columns, collapse = ", "))
  }
}

estimate_linear_sdf <- function(XR, label) {
  mu <- colMeans(XR)
  Sigma <- cov(XR)
  Sigma_rank <- qr(Sigma)$rank

  if (Sigma_rank < ncol(Sigma)) {
    stop(label, " Sigma is singular; implementation paused as required by the prompt.")
  }

  Sigma_inverse <- tryCatch(
    solve(Sigma),
    error = function(error) {
      stop(label, " Sigma could not be inverted: ", conditionMessage(error))
    }
  )

  b <- as.vector(Sigma_inverse %*% mu)
  names(b) <- colnames(XR)
  a <- as.numeric(1 + crossprod(b, mu))
  xR_star <- as.vector(XR %*% b)
  M_star <- a - xR_star
  pricing_moments <- colMeans(sweep(XR, 1L, M_star, FUN = "*"))
  monthly_sharpe_ratio <- mean(xR_star) / sd(xR_star)

  list(
    mu = mu,
    Sigma = Sigma,
    Sigma_rank = Sigma_rank,
    a = a,
    b = b,
    xR_star = xR_star,
    M_star = M_star,
    mean_M_star = mean(M_star),
    pricing_moments = pricing_moments,
    monthly_sharpe_ratio = monthly_sharpe_ratio
  )
}

be_me_columns <- c(
  "Lo 10", "2-Dec", "3-Dec", "4-Dec", "5-Dec",
  "6-Dec", "7-Dec", "8-Dec", "9-Dec", "Hi 10"
)
momentum_columns <- c(
  "Lo PRIOR", "PRIOR 2", "PRIOR 3", "PRIOR 4", "PRIOR 5",
  "PRIOR 6", "PRIOR 7", "PRIOR 8", "PRIOR 9", "Hi PRIOR"
)

be_me <- read_value_weighted_monthly(be_me_path)
momentum <- read_value_weighted_monthly(momentum_path)
rf <- read_monthly_rf(rf_path)

check_requested_columns(be_me, be_me_columns, "BE/ME")
check_requested_columns(momentum, momentum_columns, "Momentum")
check_requested_columns(rf, "RF", "Risk-free")

be_me <- be_me[
  be_me$YYYYMM >= sample_start & be_me$YYYYMM <= sample_end,
  c("YYYYMM", be_me_columns)
]
momentum <- momentum[
  momentum$YYYYMM >= sample_start & momentum$YYYYMM <= sample_end,
  c("YYYYMM", momentum_columns)
]
rf <- rf[
  rf$YYYYMM >= sample_start & rf$YYYYMM <= sample_end,
  c("YYYYMM", "RF")
]

names(be_me)[-1L] <- paste0("BM_D", seq_len(10L))
names(momentum)[-1L] <- paste0("MOM_D", seq_len(10L))

if (anyDuplicated(be_me$YYYYMM) || anyDuplicated(momentum$YYYYMM) ||
    anyDuplicated(rf$YYYYMM)) {
  stop("Duplicate YYYYMM observations found in a selected monthly panel.")
}

common_data <- Reduce(
  function(left, right) merge(left, right, by = "YYYYMM", all = FALSE, sort = TRUE),
  list(be_me, momentum, rf)
)

if (nrow(common_data) == 0L || min(common_data$YYYYMM) != sample_start ||
    max(common_data$YYYYMM) != sample_end) {
  stop("The merged data do not span the requested 192701--202608 sample.")
}

sample_dates <- as.Date(paste0(common_data$YYYYMM, "01"), format = "%Y%m%d")
expected_dates <- seq.Date(
  as.Date("1927-01-01"),
  as.Date("2026-08-01"),
  by = "month"
)
if (!identical(sample_dates, expected_dates)) {
  stop("The merged common sample has one or more missing months.")
}

bm_names <- paste0("BM_D", seq_len(10L))
momentum_names <- paste0("MOM_D", seq_len(10L))
return_names <- c(bm_names, momentum_names)
raw_returns <- as.matrix(common_data[, return_names, drop = FALSE])
raw_rf <- common_data$RF

if (anyNA(raw_returns) || anyNA(raw_rf) ||
    any(raw_returns %in% c(-99.99, -999)) ||
    any(raw_rf %in% c(-99.99, -999))) {
  stop(
    "Missing or sentinel values occur in the common sample; ",
    "the student must specify their treatment before implementation continues."
  )
}

portfolio_returns <- raw_returns / 100
risk_free_rate <- raw_rf / 100
XR_20 <- sweep(portfolio_returns, 1L, risk_free_rate, FUN = "-")
XR_BM <- XR_20[, bm_names, drop = FALSE]
XR_MOM <- XR_20[, momentum_names, drop = FALSE]

sdf_BM <- estimate_linear_sdf(XR_BM, "BE/ME")
sdf_MOM <- estimate_linear_sdf(XR_MOM, "Momentum")
sdf_20 <- estimate_linear_sdf(XR_20, "Combined")

# Store the requested combined-SDF estimates and series.
a_2c <- sdf_20$a
b_2c <- sdf_20$b
M_star_2c <- data.frame(YYYYMM = common_data$YYYYMM, M_star_2c = sdf_20$M_star)

sharpe_table <- data.frame(
  Portfolio = c("BE/ME (10 portfolios)", "Momentum (10 portfolios)",
                "Combined (20 portfolios)"),
  Monthly_Sharpe_Ratio = c(
    sdf_BM$monthly_sharpe_ratio,
    sdf_MOM$monthly_sharpe_ratio,
    sdf_20$monthly_sharpe_ratio
  )
)

dir.create(dirname(figure_path), recursive = TRUE, showWarnings = FALSE)
png(filename = figure_path, width = 1200, height = 800, res = 150)
plot(
  seq_along(b_2c),
  b_2c,
  type = "n",
  xaxt = "n",
  xlab = "Portfolio",
  ylab = expression(b[p]),
  main = "SDF coefficients across BE/ME and momentum portfolios"
)
points(seq_len(10L), b_2c[seq_len(10L)], pch = 19, col = "blue")
points(11:20, b_2c[11:20], pch = 19, col = "red")
axis(1L, at = seq_along(b_2c), labels = seq_along(b_2c))
abline(h = 0, col = "gray70", lty = 2L)
legend(
  "topright",
  legend = c("BE/ME", "Momentum"),
  col = c("blue", "red"),
  pch = 19,
  bty = "n"
)
dev.off()

latex_lines <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Monthly Sharpe Ratios of the $xR^*$ Portfolios}",
  "  \\label{tab:2c-sharpe-ratios}",
  "  \\begin{tabular}{lr}",
  "    \\toprule",
  "    Portfolio set & Monthly Sharpe ratio \\\\",
  "    \\midrule",
  sprintf("    BE/ME (10 portfolios) & %.6f \\\\", sharpe_table$Monthly_Sharpe_Ratio[1L]),
  sprintf("    Momentum (10 portfolios) & %.6f \\\\", sharpe_table$Monthly_Sharpe_Ratio[2L]),
  sprintf("    Combined (20 portfolios) & %.6f \\\\", sharpe_table$Monthly_Sharpe_Ratio[3L]),
  "    \\bottomrule",
  "  \\end{tabular}",
  "\\end{table}"
)
writeLines(latex_lines, table_path)

cat("Question 2c results\n")
cat("Common sample:", min(common_data$YYYYMM), "to", max(common_data$YYYYMM), "\n")
cat("T:", nrow(common_data), "months\n")
cat("rank(Sigma_2c):", sdf_20$Sigma_rank, "of", ncol(sdf_20$Sigma), "\n")
cat("a_2c:", format(a_2c, digits = 12L), "\n")
cat("mean(M*_2c):", format(sdf_20$mean_M_star, digits = 12L), "\n")
cat(
  "maximum absolute 2c pricing moment:",
  format(max(abs(sdf_20$pricing_moments)), digits = 12L),
  "\n\n"
)
cat("b_2c coefficients:\n")
print(b_2c, digits = 12L)
cat("\nMonthly Sharpe ratios:\n")
print(sharpe_table, row.names = FALSE, digits = 12L)
