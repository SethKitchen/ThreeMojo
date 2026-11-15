# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write synthetic daily case counts and their growth by statsmodels, a
Python library.

    python3 make_incidence.py

Run it with numpy and statsmodels 0.15.0. It writes two files:

- `cases.txt` holds 40 days of synthetic case counts, one to a line. They
  are Poisson counts about `8 exp(0.12 t)` cases on day t, from 0.
- `incidence_expected.txt` holds the Poisson regression of the counts on
  the day, by statsmodels' `GLM` with a Poisson family, fitted by Newton
  steps to 1e-12: the intercept and the growth rate per day, their
  standard errors, the Pearson dispersion `X2 / (n - 2)`, and the
  deviance.
"""

import numpy as np
import statsmodels.api as sm

rng = np.random.default_rng(20261115)
days = np.arange(40)
cases = rng.poisson(8.0 * np.exp(0.12 * days))
with open("cases.txt", "w") as out:
    for c in cases:
        out.write("%d\n" % c)
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
