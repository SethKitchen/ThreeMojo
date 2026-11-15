# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the Poisson regression of synthetic cohort strata by
statsmodels, a Python library.

    mojo run -I . tools/make_rates.mojo
    cd assets/rates && python3 make_rates.py

Run it with numpy and statsmodels 0.15.0. `tools/make_rates.mojo` writes
the 48 synthetic strata, `strata.txt`, one to a line: the events, the
person-years, the age in decades, 1 for smokers or 0, and an air
pollution index. This script reads them.

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

with open("strata.txt") as data:
    rows = np.array([[float(v) for v in line.split()] for line in data if line.strip()])
events, years, age, smoker, pollution = rows.T
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
