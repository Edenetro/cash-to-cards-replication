# Cash to Cards: difference-in-differences and event-study estimation
# Outcome: debit cards per 10,000 adults (TDDtx10), municipality-month panel
# Author: Emiliano Denetro
#
# Run from the repository root:
#   source("code/install_packages.R")
#   source("code/run_debit_cards.R")
#
# By default the script runs on the SYNTHETIC panel in data/. To run on your
# own data with the same schema, set the environment variable before sourcing:
#   Sys.setenv(C2C_INPUT = "path/to/your_panel.csv")

# -----------------------------
# 1) Packages
# -----------------------------
required_packages <- c("dplyr", "fixest", "Hmisc", "readr", "broom")
missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Missing packages: ", paste(missing_packages, collapse = ", "),
       ". Run source('code/install_packages.R') first.")
}
suppressPackageStartupMessages(invisible(lapply(required_packages, library, character.only = TRUE)))

# -----------------------------
# 2) Settings
# -----------------------------
input_file  <- Sys.getenv("C2C_INPUT", unset = file.path("data", "synthetic_panel.csv"))
output_dir  <- "output"
policy_date <- as.Date("2013-07-01")  # law enters into force
base_date   <- as.Date("2013-09-01")  # date at which baseline covariates are measured

# 0/1 municipality-level treatment indicator available in the input file
# (default: municipality exposed to organized-crime presence before the law)
TREATMENT_SOURCE_VAR <- "DTOp13"

# -----------------------------
# 3) Helper functions
# -----------------------------
check_required_columns <- function(df, cols) {
  missing_cols <- setdiff(cols, names(df))
  if (length(missing_cols) > 0) {
    stop("Missing required columns in input data: ", paste(missing_cols, collapse = ", "))
  }
}

winsorize_series <- function(x, lower_prob, upper_prob) {
  qs <- Hmisc::wtd.quantile(x, probs = c(lower_prob, upper_prob), na.rm = TRUE)
  x <- ifelse(x < qs[1], qs[1], x)
  x <- ifelse(x > qs[2], qs[2], x)
  x
}

extract_baseline_covariate <- function(df, value_var, baseline_date, new_name) {
  out <- df %>%
    dplyr::filter(date == baseline_date) %>%
    dplyr::transmute(mun, !!new_name := .data[[value_var]])
  if (nrow(out) == 0) {
    stop("No observations found for baseline date ", baseline_date,
         " when extracting ", value_var)
  }
  out
}

# -----------------------------
# 4) Load data
# -----------------------------
if (!file.exists(input_file)) stop("Input file not found: ", input_file)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

ready <- readr::read_csv(input_file, show_col_types = FALSE)

required_cols <- c("mun", "date", "TDDtx10", "ATM", "sucx10", "pib13", TREATMENT_SOURCE_VAR)
check_required_columns(ready, required_cols)
message("Input: ", input_file, " (", nrow(ready), " rows)")

# -----------------------------
# 5) Clean data and construct variables
# -----------------------------
ready <- ready %>%
  dplyr::mutate(
    mun     = as.numeric(mun),
    date    = as.Date(date),
    TDDtx10 = as.numeric(TDDtx10),
    ATM     = as.numeric(ATM),
    sucx10  = as.numeric(sucx10),
    pib13   = as.numeric(pib13),
    treatment_source = as.numeric(.data[[TREATMENT_SOURCE_VAR]])
  )

# Winsorize the outcome at the 0.1th and 99.9th percentiles
ready <- ready %>%
  dplyr::mutate(TDDtx10W = winsorize_series(TDDtx10, 0.001, 0.999))

# Baseline covariates (ATMs and branches per 10k adults at base_date)
atm13    <- extract_baseline_covariate(ready, "ATM",    base_date, "ATM13")
sucx1013 <- extract_baseline_covariate(ready, "sucx10", base_date, "sucx1013")

ready <- ready %>%
  dplyr::left_join(atm13,    by = "mun") %>%
  dplyr::left_join(sucx1013, by = "mun") %>%
  dplyr::group_by(mun) %>%
  dplyr::mutate(
    treated = dplyr::if_else(any(treatment_source == 1, na.rm = TRUE), 1, 0),
    post    = dplyr::if_else(date >= policy_date, 1, 0)
  ) %>%
  dplyr::ungroup()

# Event-study / DiD working dataset.
# pib13 is kept in the dataset but is not used in the regression formulas:
# the debit-card specification controls only for ATM and branch density.
dd_data <- ready %>%
  dplyr::transmute(
    unidades   = mun,
    time       = date,
    post       = post,
    T3         = treated,
    DebitCards = TDDtx10W,
    covariate1 = as.numeric(ATM13),
    covariate2 = as.numeric(sucx1013),
    covariate3 = as.numeric(pib13)
  ) %>%
  dplyr::mutate(
    time_dd    = as.numeric(time - policy_date),
    time_ddtri = floor(time_dd / 30),   # ~monthly event time, 0 = policy month
    treat_post = T3 * post
  )

# -----------------------------
# 6) Estimation (municipality and time fixed effects, clustered SEs)
# -----------------------------
es_no_cov <- fixest::feols(
  DebitCards ~ i(time_ddtri, T3, ref = -1) | unidades + time,
  cluster = ~unidades, data = dd_data
)

reg_no_cov <- fixest::feols(
  DebitCards ~ treat_post | unidades + time,
  cluster = ~unidades, data = dd_data
)

es_cov <- fixest::feols(
  DebitCards ~ i(time_ddtri, T3, ref = -1) +
    i(time_ddtri, covariate1, ref = -1) +
    i(time_ddtri, covariate2, ref = -1) |
    unidades + time,
  cluster = ~unidades, data = dd_data
)

reg_cov <- fixest::feols(
  DebitCards ~ treat_post +
    i(time, covariate1, ref = as.Date("2013-06-01")) +
    i(time, covariate2, ref = as.Date("2013-06-01")) |
    unidades + time,
  cluster = ~unidades, data = dd_data
)

# -----------------------------
# 7) Export results
# -----------------------------
summary_file  <- file.path(output_dir, "model_summaries.txt")
coef_file     <- file.path(output_dir, "main_results.csv")
analysis_file <- file.path(output_dir, "analysis_dataset.csv")

sink(summary_file)
cat("Cash to Cards - Debit cards per 10k\n")
cat("Input file: ", input_file, "\n", sep = "")
cat("Treatment variable: ", TREATMENT_SOURCE_VAR, "\n\n", sep = "")
for (m in list(
  list("DiD without covariates", reg_no_cov),
  list("DiD with covariates", reg_cov),
  list("Event study without covariates", es_no_cov),
  list("Event study with covariates", es_cov)
)) {
  cat("==============================\n", m[[1]], "\n==============================\n", sep = "")
  print(summary(m[[2]]))
  cat("\n\n")
}
sink()

results_table <- dplyr::bind_rows(
  broom::tidy(reg_no_cov) %>% dplyr::mutate(model = "did_no_cov"),
  broom::tidy(reg_cov)    %>% dplyr::mutate(model = "did_cov"),
  broom::tidy(es_no_cov)  %>% dplyr::mutate(model = "event_study_no_cov"),
  broom::tidy(es_cov)     %>% dplyr::mutate(model = "event_study_cov")
) %>%
  dplyr::select(model, dplyr::everything())

readr::write_csv(results_table, coef_file)
readr::write_csv(dd_data, analysis_file)

png(file.path(output_dir, "event_study_no_cov.png"), width = 1200, height = 800, res = 150)
fixest::iplot(es_no_cov, main = "Event study: debit cards per 10k (no covariates)")
dev.off()

png(file.path(output_dir, "event_study_cov.png"), width = 1200, height = 800, res = 150)
fixest::iplot(es_cov, main = "Event study: debit cards per 10k (with covariates)")
dev.off()

message("Done. Outputs saved in: ", normalizePath(output_dir))
