# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write synthetic cohort strata and their Poisson regression by
statsmodels, a Python library.

    python3 make_rates.py

Run it with numpy and statsmodels 0.15.0. It writes two files:

- `strata.txt` holds 48 synthetic strata of a cohort, one to a line: the
  events, the person-years, the age in decades, 1 for smokers or 0, and
  an air pollution index.
- `rates_expected.txt` holds the Poisson regression of the events on the
  covariates with the log of the person-years as the offset, by `GLM`
  fitted to 1e-12:

  - `intercept` with the log of the baseline rate per year, its standard
    error, and one line `covariate` for each covariate with the
    coefficient, its standard error, z, the p value, and the low and high
    ends of the 95 percent interval of its rate ratio.
  - `fit` with the deviance and the Pearson dispersion.
  - `predict` with the rate per year of two strata.
"""

import numpy as np
import statsmodels.api as sm

rng = np.random.default_rng(20261115)
n = 48
age = np.round(rng.uniform(4.0, 8.0, n), 1)
smoker = (np.arange(n) % 2).astype(int)
pollution = np.round(rng.normal(3.0, 1.0, n), 2)
years = np.round(rng.uniform(200.0, 3000.0, n), 1)
rate = np.exp(-11.0 + 0.9 * age + 1.1 * smoker + 0.15 * pollution)
events = rng.poisson(rate * years)
with open("strata.txt", "w") as out:
    for i in range(n):
        out.write("%d %.1f %.1f %d %.2f\n" % (events[i], years[i], age[i], smoker[i], pollution[i]))
x = sm.add_constant(np.column_stack([age, smoker, pollution]))
fit = sm.GLM(events, x, family=sm.families.Poisson(), offset=np.log(years)).fit(
    method="newton", tol=1e-12, maxiter=100
)
ci = fit.conf_int(0.05)
lines = ["intercept %r %r" % (float(fit.params[0]), float(fit.bse[0]))]
for j in range(1, 4):
    values = [fit.params[j], fit.bse[j], fit.tvalues[j], fit.pvalues[j], np.exp(ci[j, 0]), np.exp(ci[j, 1])]
    lines.append("covariate " + " ".join(repr(float(v)) for v in values))
lines.append("fit %r %r" % (float(fit.deviance), float(fit.pearson_chi2 / fit.df_resid)))
rows = sm.add_constant(np.array([[5.0, 0, 2.0], [7.5, 1, 4.0]]), has_constant="add")
lines.append("predict " + " ".join(repr(float(v)) for v in fit.predict(rows)))
with open("rates_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
