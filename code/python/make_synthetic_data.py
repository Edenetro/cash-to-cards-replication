"""Generate a SYNTHETIC municipality-month panel with the same schema the R
script expects. The numbers are simulated: they are NOT the thesis data and
the effect size below is arbitrary. Purpose: let anyone run the full pipeline
(estimation, event studies, exports) without access to restricted data.

Usage (from the repository root):
    python code/python/make_synthetic_data.py
"""
import numpy as np
import pandas as pd

SEED = 2013
N_MUN = 400                       # municipalities
DATES = pd.date_range("2011-01-01", "2014-12-01", freq="MS")  # monthly
POLICY_DATE = pd.Timestamp("2013-07-01")
TRUE_EFFECT = 120.0               # debit cards per 10k adults, arbitrary

rng = np.random.default_rng(SEED)

# Municipality-level characteristics (time-invariant in this simulation)
mun = 1000 + np.arange(N_MUN)
atm = rng.gamma(shape=2.0, scale=3.0, size=N_MUN)             # ATMs per 10k
branches = 0.5 * atm + rng.gamma(2.0, 1.0, size=N_MUN)         # branches per 10k
pib13 = rng.lognormal(mean=8.0, sigma=1.0, size=N_MUN)         # local GDP proxy

# Treatment assignment depends on observables, so covariates matter
logit = -1.0 + 0.15 * (atm - atm.mean()) + 0.2 * (branches - branches.mean())
treated = rng.binomial(1, 1 / (1 + np.exp(-logit)))

# Outcome: cards per 10k adults = unit FE + trend + seasonality + effect + noise
unit_fe = 1500 + 120 * atm + 150 * branches + rng.normal(0, 200, N_MUN)
rows = []
for t_idx, d in enumerate(DATES):
    post = int(d >= POLICY_DATE)
    season = 40 * np.sin(2 * np.pi * d.month / 12)
    trend = 8.0 * t_idx + 0.4 * atm * t_idx           # covariate-specific trend
    y = (unit_fe + trend + season
         + TRUE_EFFECT * treated * post
         + rng.normal(0, 90, N_MUN))
    rows.append(pd.DataFrame({
        "mun": mun, "date": d.strftime("%Y-%m-%d"),
        "TDDtx10": y.clip(min=0), "ATM": atm, "sucx10": branches,
        "pib13": pib13, "DTOp13": treated,
    }))

panel = pd.concat(rows, ignore_index=True).round(4)
panel.to_csv("data/synthetic_panel.csv", index=False)
print(f"Wrote data/synthetic_panel.csv: {len(panel):,} rows, "
      f"{panel.mun.nunique()} municipalities, {panel.date.nunique()} months, "
      f"{treated.mean():.0%} treated")
