# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the growth of synthetic daily case counts by statsmodels, a
Python library.

    mojo run -I . tools/make_incidence.mojo
    cd assets/incidence && python3 make_incidence.py

Run it with numpy and statsmodels 0.15.0. `tools/make_incidence.mojo`
writes 40 days of synthetic case counts, `cases.txt`, one to a line:
Poisson counts about `8 exp(0.12 t)` cases on day t, from 0. This script
reads them.

- `incidence_expected.txt` holds the Poisson regression of the counts on
  the day, by statsmodels' `GLM` with a Poisson family, fitted by Newton
  steps to 1e-12: the intercept and the growth rate per day, their
  standard errors, the Pearson dispersion `X2 / (n - 2)`, and the
  deviance.
"""

import numpy as np
import statsmodels.api as sm

with open("cases.txt") as data:
    cases = np.array([int(line) for line in data if line.strip()])
days = np.arange(len(cases))
x = sm.add_constant(days.astype(float))
fit = sm.GLM(cases, x, family=sm.families.Poisson()).fit(
    method="newton", tol=1e-12, maxiter=100
)
values = [
    fit.params[0],
    fit.params[1],
    fit.bse[0],
    fit.bse[1],
    fit.pearson_chi2 / fit.df_resid,
    fit.deviance,
]
with open("incidence_expected.txt", "w") as out:
    out.write("fit " + " ".join(repr(float(v)) for v in values) + "\n")
