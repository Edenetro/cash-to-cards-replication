required_packages <- c("dplyr", "fixest", "Hmisc", "readr", "broom")

missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
if (length(missing_packages) > 0) {
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

cat("All required packages are installed.\n")
