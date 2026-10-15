# Cash to Cards: replication code (debit cards)

Code for the difference-in-differences and event-study analysis in the undergraduate thesis *From Cash to Cards* (ITAM), which studies how Mexico's 2013 anti-money laundering law affected the integration of organized crime into the formal financial system.

> **Data note.** The thesis data, including the organized-crime (DTO) presence indicator, cannot be redistributed. This repository ships a **synthetic** panel with the same schema so the full pipeline runs end to end. The synthetic numbers and effect size are simulated and are **not** the thesis results.

## Repository structure

```
code/
  install_packages.R          installs the R packages
  run_debit_cards.R           estimation: DiD and event studies (R)
  python/
    make_synthetic_data.py    generates the synthetic panel (Python)
data/
  synthetic_panel.csv         simulated municipality-month panel
output/                       created when the script runs
```

## Method

- **Design:** two-way fixed-effects difference-in-differences with municipality and time effects, comparing municipalities exposed to organized-crime presence before the law with unexposed ones, around the policy date (2013-07-01).
- **Outcome:** debit cards per 10,000 adults, winsorized at the 0.1th and 99.9th percentiles.
- **Covariates:** ATMs and bank branches per 10,000 adults at baseline (2013-09-01), interacted with time.
- **Inference:** standard errors clustered by municipality.
- **Event study:** monthly leads and lags relative to the month before the law (reference period = -1), used to inspect pre-trends.

## Input schema

| Column | Description |
|---|---|
| `mun` | Municipality identifier |
| `date` | Month (first day), `YYYY-MM-DD` |
| `TDDtx10` | Debit cards per 10,000 adults |
| `ATM` | ATMs per 10,000 adults |
| `sucx10` | Bank branches per 10,000 adults |
| `pib13` | Local GDP proxy (kept in the dataset, not used in the regressions) |
| `DTOp13` | 0/1 treatment: municipality exposed to organized-crime presence before the law |

## How to run

From the repository root:

```r
source("code/install_packages.R")
source("code/run_debit_cards.R")
```

To regenerate the synthetic data (optional):

```bash
pip install -r code/python/requirements.txt
python code/python/make_synthetic_data.py
```

To use your own panel with the same schema:

```r
Sys.setenv(C2C_INPUT = "path/to/your_panel.csv")
source("code/run_debit_cards.R")
```

## Outputs

Saved to `output/`: `model_summaries.txt`, `main_results.csv`, `analysis_dataset.csv`, `event_study_no_cov.png`, `event_study_cov.png`.

## Example output (synthetic data)

Without covariates, the event study shows a pre-trend:

![Event study without covariates](figures/event_study_no_cov.png)

With baseline ATM and branch controls, pre-trends are flat and the post-law estimate recovers the simulated effect (about 120 cards per 10,000 adults):

![Event study with covariates](figures/event_study_cov.png)

*These figures are generated from simulated data and are not the thesis results.*
## About the synthetic data

Treatment assignment in the simulation depends on ATM and branch density, and the simulated outcome has covariate-specific trends. As a result, the specification without covariates is biased upward and the specification with covariates recovers the simulated effect (120 cards per 10,000 adults). This mirrors why the covariate-adjusted model matters in the thesis.

## Author

Emiliano Denetro ([LinkedIn](https://linkedin.com/in/edenetro))
