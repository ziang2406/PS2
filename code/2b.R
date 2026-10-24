# BUSFIN 8200 Problem Set 2, Question 2b
# Construct the linear SDF for ten value-weighted momentum portfolios and
# compare it with the Question 2a BE/ME SDF.

be_me_path <- file.path("data", "BE_ME.csv")
momentum_path <- file.path("data", "10P_MOM.csv")
rf_path <- file.path("data", "RF.csv")
figure_path <- file.path("figures", "2b.png")

sample_start <- 192707L
sample_end <- 202608L

read_csv_section <- function(path, header_index, row_pattern = "^\\s*[0-9]{6},") {
  lines <- readLines(path, warn = FALSE)
  data_indices <- seq.int(header_index + 1L, length(lines))
  data_indices <- data_indices[grepl(row_pattern, lines[data_indices])]

  if (length(data_indices) == 0L) {
    stop("No monthly observations found after the selected header in ", path)
  }

  # Restrict the table to the first contiguous block of monthly observations.
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

estimate_linear_sdf <- function(
    portfolio_data,
    source_columns,
    rf_data,
    start_yyyymm,
    end_yyyymm,
    label) {
  decile_names <- paste0("D", seq_len(10L))
  required_portfolio_columns <- c("YYYYMM", source_columns)

  if (!all(required_portfolio_columns %in% names(portfolio_data))) {
    stop(label, " data are missing one or more required decile columns.")
  }
  if (!all(c("YYYYMM", "RF") %in% names(rf_data))) {
    stop("RF.csv is missing YYYYMM or RF.")
  }

  portfolio_data <- portfolio_data[
    portfolio_data$YYYYMM >= start_yyyymm &
      portfolio_data$YYYYMM <= end_yyyymm,
    required_portfolio_columns
  ]
  rf_data <- rf_data[
    rf_data$YYYYMM >= start_yyyymm & rf_data$YYYYMM <= end_yyyymm,
    c("YYYYMM", "RF")
  ]
  names(portfolio_data)[-1L] <- decile_names

  if (anyDuplicated(portfolio_data$YYYYMM) || anyDuplicated(rf_data$YYYYMM)) {
    stop("Duplicate YYYYMM observations found in the selected ", label, " panel.")
  }

  analysis_data <- merge(
    portfolio_data,
    rf_data,
    by = "YYYYMM",
    all = FALSE,
    sort = TRUE
  )
  if (nrow(analysis_data) == 0L) {
    stop("No common YYYYMM observations found for the ", label, " analysis.")
  }
  if (min(analysis_data$YYYYMM) != start_yyyymm ||
      max(analysis_data$YYYYMM) != end_yyyymm) {
    stop("The ", label, " data do not span the requested sample endpoints.")
  }

  sample_dates <- as.Date(paste0(analysis_data$YYYYMM, "01"), format = "%Y%m%d")
  start_date <- as.Date(paste0(start_yyyymm, "01"), format = "%Y%m%d")
  end_date <- as.Date(paste0(end_yyyymm, "01"), format = "%Y%m%d")
  if (!identical(sample_dates, seq.Date(start_date, end_date, by = "month"))) {
    stop("The ", label, " sample has one or more missing months.")
  }

  raw_returns <- as.matrix(analysis_data[, decile_names, drop = FALSE])
  raw_rf <- analysis_data$RF
  if (anyNA(raw_returns) || anyNA(raw_rf) ||
      any(raw_returns %in% c(-99.99, -999)) ||
      any(raw_rf %in% c(-99.99, -999))) {
    stop(
      "Missing or sentinel values occur in the selected ", label,
      " sample; the student must specify their treatment before implementation continues."
    )
  }

  portfolio_returns <- raw_returns / 100
  risk_free_rate <- raw_rf / 100
  XR <- sweep(portfolio_returns, 1L, risk_free_rate, FUN = "-")
  colnames(XR) <- decile_names

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
  names(b) <- decile_names
  a <- as.numeric(1 + crossprod(b, mu))
  xR_star <- as.vector(XR %*% b)
  M_star <- a - xR_star
  pricing_moments <- colMeans(sweep(XR, 1L, M_star, FUN = "*"))

  list(
    YYYYMM = analysis_data$YYYYMM,
    XR = XR,
    mu = mu,
    Sigma = Sigma,
    Sigma_rank = Sigma_rank,
    a = a,
    b = b,
    xR_star = xR_star,
    M_star = M_star,
    mean_M_star = mean(M_star),
    pricing_moments = pricing_moments
  )
}

be_me <- read_value_weighted_monthly(be_me_path)
momentum <- read_value_weighted_monthly(momentum_path)
rf <- read_monthly_rf(rf_path)

be_me_columns <- c(
  "Lo 10", "2-Dec", "3-Dec", "4-Dec", "5-Dec",
  "6-Dec", "7-Dec", "8-Dec", "9-Dec", "Hi 10"
)
momentum_columns <- c(
  "Lo PRIOR", "PRIOR 2", "PRIOR 3", "PRIOR 4", "PRIOR 5",
  "PRIOR 6", "PRIOR 7", "PRIOR 8", "PRIOR 9", "Hi PRIOR"
)

sdf_2a <- estimate_linear_sdf(
  be_me,
  be_me_columns,
  rf,
  start_yyyymm = sample_start,
  end_yyyymm = sample_end,
  label = "BE/ME"
)
sdf_2b <- estimate_linear_sdf(
  momentum,
  momentum_columns,
  rf,
  start_yyyymm = sample_start,
  end_yyyymm = sample_end,
  label = "momentum"
)

# Store the requested SDF coefficients and monthly SDF series.
M_star_2a <- data.frame(YYYYMM = sdf_2a$YYYYMM, M_star_2a = sdf_2a$M_star)
a_2b <- sdf_2b$a
b_2b <- sdf_2b$b
M_star_2b <- data.frame(YYYYMM = sdf_2b$YYYYMM, M_star_2b = sdf_2b$M_star)

correlation_sample <- merge(
  M_star_2a,
  M_star_2b,
  by = "YYYYMM",
  all = FALSE,
  sort = TRUE
)
if (nrow(correlation_sample) < 2L) {
  stop("Fewer than two common observations are available for the SDF correlation.")
}
M_star_correlation <- cor(
  correlation_sample$M_star_2a,
  correlation_sample$M_star_2b
)

dir.create(dirname(figure_path), recursive = TRUE, showWarnings = FALSE)
png(filename = figure_path, width = 1200, height = 800, res = 150)
plot(
  seq_along(b_2b),
  b_2b,
  type = "p",
  pch = 19,
  xaxt = "n",
  xlab = "Momentum portfolio decile",
  ylab = expression(b[p]),
  main = "SDF coefficients across momentum decile portfolios"
)
axis(1L, at = seq_along(b_2b), labels = seq_along(b_2b))
abline(h = 0, col = "gray70", lty = 2L)
dev.off()

cat("Question 2b results\n")
cat("Momentum sample:", min(sdf_2b$YYYYMM), "to", max(sdf_2b$YYYYMM), "\n")
cat("Momentum T:", nrow(sdf_2b$XR), "months\n")
cat("rank(Sigma_2b):", sdf_2b$Sigma_rank, "of", ncol(sdf_2b$Sigma), "\n")
cat("a_2b:", format(a_2b, digits = 12L), "\n")
cat("mean(M*_2b):", format(sdf_2b$mean_M_star, digits = 12L), "\n")
cat(
  "maximum absolute 2b pricing moment:",
  format(max(abs(sdf_2b$pricing_moments)), digits = 12L),
  "\n"
)
cat(
  "SDF correlation sample:", min(correlation_sample$YYYYMM), "to",
  max(correlation_sample$YYYYMM), "(", nrow(correlation_sample), "months )\n"
)
cat("cor(M*_2a, M*_2b):", format(M_star_correlation, digits = 12L), "\n\n")
cat("b_2b coefficients:\n")
print(b_2b, digits = 12L)
cat("\nE[M*_2b xR_p] sample moments:\n")
print(sdf_2b$pricing_moments, digits = 12L)
