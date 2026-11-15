# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a synthetic cohort and its logistic model by statsmodels, a
Python library.

    python3 make_logistic.py

Run it with numpy and statsmodels 0.15.0. It writes two files:

- `cohort.txt` holds 200 synthetic patients, one to a line: 1 for disease
  or 0 for none, the age in decades, 1 for a smoker or 0 for none, and a
  marker.
- `logistic_expected.txt` holds the model of statsmodels' `Logit`, fitted
  by Newton steps to a tolerance of 1e-12.

The disease comes from a risk of `1 / (1 + exp(-(-6 + 0.7 age + 0.9
smoker + 0.5 marker)))`.

The expected file has these lines:

- `intercept` and then one line `covariate` for each covariate, with the
  coefficient, its standard error, z, the p value, and the low and high
  ends of the 95 percent interval of the odds ratio.
- `fit` with the log-likelihood, the null log-likelihood, the likelihood
  ratio statistic and its p value. statsmodels fits its own null model
  with a looser default, which leaves its `llnull` 2e-8 below the
  maximum. So the script fits the null model by Newton steps to 1e-12
  too, and takes the test from it with scipy's `chi2.sf`.
- `risk` with the predicted risk of three patients.
"""

import numpy as np
import statsmodels.api as sm
from scipy.stats import chi2

rng = np.random.default_rng(20261115)
n = 200
age = np.round(rng.normal(6.0, 1.2, n), 1)
smoker = (rng.random(n) < 0.35).astype(int)
marker = np.round(rng.normal(2.0, 1.0, n), 2)
eta = -6.0 + 0.7 * age + 0.9 * smoker + 0.5 * marker
disease = (rng.random(n) < 1.0 / (1.0 + np.exp(-eta))).astype(int)

with open("cohort.txt", "w") as out:
    for i in range(n):
        out.write("%d %.1f %d %.2f\n" % (disease[i], age[i], smoker[i], marker[i]))

x = sm.add_constant(np.column_stack([age, smoker, marker]))
fit = sm.Logit(disease, x).fit(method="newton", tol=1e-12, maxiter=100, disp=0)
ci = fit.conf_int(alpha=0.05)
lines = []
for j, name in enumerate(["intercept", "covariate", "covariate", "covariate"]):
    values = [
        fit.params[j],
        fit.bse[j],
        fit.tvalues[j],
        fit.pvalues[j],
        np.exp(ci[j, 0]),
        np.exp(ci[j, 1]),
    ]
    lines.append(name + " " + " ".join(repr(float(v)) for v in values))
null = sm.Logit(disease, np.ones(n)).fit(
    method="newton", tol=1e-12, maxiter=100, disp=0
)
ratio = 2.0 * (fit.llf - null.llf)
lines.append(
    "fit %r %r %r %r"
    % (float(fit.llf), float(null.llf), float(ratio), float(chi2.sf(ratio, 3)))
)
rows = sm.add_constant(np.array([[5.0, 0, 1.0], [6.5, 1, 2.5], [8.0, 1, 4.0]]), has_constant="add")
lines.append("risk " + " ".join(repr(float(v)) for v in fit.predict(rows)))
with open("logistic_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
