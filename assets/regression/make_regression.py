# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a synthetic cohort and its linear regression by statsmodels, a
Python library.

    python3 make_regression.py

Run it with numpy and statsmodels 0.15.0. It writes two files:

- `pressure.txt` holds 80 synthetic patients, one to a line: the systolic
  blood pressure in mmHg, the age in years, the body mass index in kg/m^2,
  and the salt intake in g a day.
- `regression_expected.txt` holds the least squares fit of `OLS` with an
  intercept:

  - `intercept` and one line `covariate` for each covariate, with the
    coefficient, its standard error, t, the p value, and the low and high
    ends of its 95 percent interval.
  - `fit` with R^2, the adjusted R^2, F, its p value, and the residual
    standard deviation.
  - `predict` with the fitted pressure of two patients.
"""

import numpy as np
import statsmodels.api as sm

rng = np.random.default_rng(20261115)
n = 80
age = np.round(rng.uniform(30, 80, n))
bmi = np.round(rng.normal(27.0, 4.0, n), 1)
salt = np.round(rng.normal(8.0, 2.5, n), 1)
pressure = np.round(90 + 0.6 * age + 0.9 * bmi + 1.2 * salt + rng.normal(0, 9, n))
with open("pressure.txt", "w") as out:
    for i in range(n):
        out.write("%d %d %.1f %.1f\n" % (pressure[i], age[i], bmi[i], salt[i]))
x = sm.add_constant(np.column_stack([age, bmi, salt]))
fit = sm.OLS(pressure, x).fit()
ci = fit.conf_int(0.05)
lines = []
for j, name in enumerate(["intercept", "covariate", "covariate", "covariate"]):
    values = [fit.params[j], fit.bse[j], fit.tvalues[j], fit.pvalues[j], ci[j, 0], ci[j, 1]]
    lines.append(name + " " + " ".join(repr(float(v)) for v in values))
lines.append(
    "fit %r %r %r %r %r"
    % (float(fit.rsquared), float(fit.rsquared_adj), float(fit.fvalue),
       float(fit.f_pvalue), float(np.sqrt(fit.scale)))
)
rows = sm.add_constant(np.array([[45.0, 24.0, 6.0], [70.0, 31.5, 11.0]]), has_constant="add")
lines.append("predict " + " ".join(repr(float(v)) for v in fit.predict(rows)))
with open("regression_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
