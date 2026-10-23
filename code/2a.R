# BUSFIN 8200 Problem Set 2, Question 2a
# Construct the minimum-variance linear SDF for the ten value-weighted
# book-to-market decile portfolios.

be_me_path <- file.path("data", "BE_ME.csv")
rf_path <- file.path("data", "RF.csv")
figure_path <- file.path("figures", "2a.png")

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

be_me_lines <- readLines(be_me_path, warn = FALSE)
value_weight_label <- grep(
  "^\\s*Value Weight Returns -- Monthly\\s*$",
  be_me_lines
)
if (length(value_weight_label) != 1L) {
  stop("Could not uniquely identify the value-weighted monthly BE/ME panel.")
}
be_me <- read_csv_section(be_me_path, value_weight_label + 1L)

rf_lines <- readLines(rf_path, warn = FALSE)
rf_headers <- grep("^,Mkt-RF,SMB,HML,RF\\s*$", rf_lines)
if (length(rf_headers) < 1L) {
  stop("Could not identify the monthly factor header in RF.csv.")
}
rf <- read_csv_section(rf_path, rf_headers[1L])

source_columns <- c(
  "Lo 10", "2-Dec", "3-Dec", "4-Dec", "5-Dec",
  "6-Dec", "7-Dec", "8-Dec", "9-Dec", "Hi 10"
)
decile_names <- paste0("D", seq_len(10L))

required_be_me <- c("YYYYMM", source_columns)
if (!all(required_be_me %in% names(be_me))) {
  stop("BE_ME.csv is missing one or more required decile columns.")
}
if (!all(c("YYYYMM", "RF") %in% names(rf))) {
  stop("RF.csv is missing YYYYMM or RF.")
}

be_me <- be_me[be_me$YYYYMM >= 192607L, required_be_me]
rf <- rf[rf$YYYYMM >= 192607L, c("YYYYMM", "RF")]
names(be_me)[-1L] <- decile_names

if (anyDuplicated(be_me$YYYYMM) || anyDuplicated(rf$YYYYMM)) {
  stop("Duplicate YYYYMM observations found in a selected monthly panel.")
}

analysis_data <- merge(be_me, rf, by = "YYYYMM", all = FALSE, sort = TRUE)
if (nrow(analysis_data) == 0L) {
  stop("No common YYYYMM observations found between BE_ME.csv and RF.csv.")
}

raw_returns <- as.matrix(analysis_data[, decile_names, drop = FALSE])
raw_rf <- analysis_data$RF
if (anyNA(raw_returns) || anyNA(raw_rf) ||
    any(raw_returns %in% c(-99.99, -999)) || any(raw_rf %in% c(-99.99, -999))) {
  stop(
    "Missing or sentinel values occur in the selected sample; ",
    "the student must specify their treatment before implementation continues."
  )
}

# Convert percentage returns to decimals and form the T x 10 excess-return matrix.
portfolio_returns <- raw_returns / 100
risk_free_rate <- raw_rf / 100
XR <- sweep(portfolio_returns, 1L, risk_free_rate, FUN = "-")
colnames(XR) <- decile_names

mu <- colMeans(XR)
Sigma <- cov(XR)

if (qr(Sigma)$rank < ncol(Sigma)) {
  stop("Sigma is singular; implementation paused as required by prompt/2a.md.")
}

Sigma_inverse <- tryCatch(
  solve(Sigma),
  error = function(error) {
    stop("Sigma could not be inverted: ", conditionMessage(error))
  }
)

b <- as.vector(Sigma_inverse %*% mu)
names(b) <- decile_names
a <- as.numeric(1 + crossprod(b, mu))

xR_star <- as.vector(XR %*% b)
M_star <- a - xR_star

mean_M_star <- mean(M_star)
pricing_moments <- colMeans(sweep(XR, 1L, M_star, FUN = "*"))

dir.create(dirname(figure_path), recursive = TRUE, showWarnings = FALSE)
png(filename = figure_path, width = 1200, height = 800, res = 150)
plot(
  seq_along(b),
  b,
  type = "p",
  pch = 19,
  xaxt = "n",
  xlab = "Book-to-market portfolio decile",
  ylab = expression(b[p]),
  main = "SDF coefficients across BE/ME decile portfolios"
)
axis(1L, at = seq_along(b), labels = seq_along(b))
abline(h = 0, col = "gray70", lty = 2L)
dev.off()

cat("Question 2a results\n")
cat("Sample:", min(analysis_data$YYYYMM), "to", max(analysis_data$YYYYMM), "\n")
cat("T:", nrow(XR), "months\n")
cat("rank(Sigma):", qr(Sigma)$rank, "of", ncol(Sigma), "\n")
cat("a:", format(a, digits = 12L), "\n")
cat("mean(M*):", format(mean_M_star, digits = 12L), "\n")
cat("maximum absolute pricing moment:",
    format(max(abs(pricing_moments)), digits = 12L), "\n\n")
cat("b coefficients:\n")
print(b, digits = 12L)
cat("\nE[M* xR_p] sample moments:\n")
print(pricing_moments, digits = 12L)
