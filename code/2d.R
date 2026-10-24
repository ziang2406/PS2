# BUSFIN 8200 Problem Set 2, Question 2d
# Evaluate the BE/ME, momentum, and combined linear SDFs against all twenty
# test portfolios using the common July 1927--August 2026 sample.

be_me_path <- file.path("data", "BE_ME.csv")
momentum_path <- file.path("data", "10P_MOM.csv")
rf_path <- file.path("data", "RF.csv")
table_path <- file.path("figures", "2d.tex")

sample_start <- 192707L
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

  list(
    mu = mu,
    Sigma = Sigma,
    Sigma_rank = Sigma_rank,
    a = a,
    b = b,
    xR_star = xR_star,
    M_star = M_star
  )
}

pricing_errors <- function(M_star, XR_test) {
  M_centered <- M_star - mean(M_star)
  XR_centered <- sweep(XR_test, 2L, colMeans(XR_test), FUN = "-")

  # The prompt specifies the covariance estimator with denominator T.
  covariance_M_XR <- colMeans(sweep(XR_centered, 1L, M_centered, FUN = "*"))
  alpha <- colMeans(XR_test) + covariance_M_XR

  list(covariance_M_XR = covariance_M_XR, alpha = alpha)
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
  stop("The merged data do not span the requested 192707--202608 sample.")
}

sample_dates <- as.Date(paste0(common_data$YYYYMM, "01"), format = "%Y%m%d")
expected_dates <- seq.Date(
  as.Date("1927-07-01"),
  as.Date("2026-08-01"),
  by = "month"
)
if (!identical(sample_dates, expected_dates)) {
  stop("The merged common sample has one or more missing months.")
}

bm_names <- paste0("BM_D", seq_len(10L))
momentum_names <- paste0("MOM_D", seq_len(10L))
portfolio_names <- c(bm_names, momentum_names)
raw_returns <- as.matrix(common_data[, portfolio_names, drop = FALSE])
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

errors_BM <- pricing_errors(sdf_BM$M_star, XR_20)
errors_MOM <- pricing_errors(sdf_MOM$M_star, XR_20)
errors_20 <- pricing_errors(sdf_20$M_star, XR_20)

alpha_table <- data.frame(
  Portfolio = c(paste0("BE/ME D", seq_len(10L)), paste0("Momentum D", seq_len(10L))),
  BE_ME_SDF = as.vector(errors_BM$alpha),
  Momentum_SDF = as.vector(errors_MOM$alpha),
  Combined_SDF = as.vector(errors_20$alpha),
  check.names = FALSE
)

dir.create(dirname(table_path), recursive = TRUE, showWarnings = FALSE)
latex_lines <- c(
  "\\begin{table}[H]",
  "  \\centering",
  "  \\caption{Pricing Errors Under the Three Estimated SDFs}",
  "  \\label{tab:2d-pricing-errors}",
  "  \\begin{tabular}{lrrr}",
  "    \\toprule",
  "    Portfolio & BE/ME SDF & Momentum SDF & Combined SDF \\\\",
  "    \\midrule",
  sprintf(
    "    %s & %.6f & %.6f & %.6f \\\\",
    alpha_table$Portfolio,
    alpha_table$BE_ME_SDF,
    alpha_table$Momentum_SDF,
    alpha_table$Combined_SDF
  ),
  "    \\bottomrule",
  "  \\end{tabular}",
  "\\end{table}"
)
writeLines(latex_lines, table_path)

cat("Question 2d results\n")
cat("Common sample:", min(common_data$YYYYMM), "to", max(common_data$YYYYMM), "\n")
cat("T:", nrow(common_data), "months\n")
cat(
  "Sigma ranks (BE/ME, momentum, combined):",
  sdf_BM$Sigma_rank, sdf_MOM$Sigma_rank, sdf_20$Sigma_rank,
  "\n\n"
)
print(alpha_table, row.names = FALSE, digits = 10L)
