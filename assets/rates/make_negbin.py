# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a negative binomial (NB2) model of event rates with statsmodels.

    mojo run -I . tools/make_rates.mojo
    cd assets/rates && python3 make_negbin.py > negbin_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and statsmodels 0.15.0.
`tools/make_rates.mojo` writes the synthetic cohort, `negbin_strata.txt`:
120 strata, each with the events, a person-time in years, a smoking flag
and a standardized age. Its counts are gamma-Poisson with a dispersion
of 0.5, so they spread more than Poisson counts. This script copies each
stratum to a `stratum` line, then writes:

- `params`: the intercept, the two log rate ratios and alpha, from
  statsmodels' `NegativeBinomial` with `loglike_method="nb2"` and the
  person-time as the exposure, fitted by Newton steps to 1e-14.
- `errors`: their standard errors.
- `fit`: the log-likelihood of the model and of the Poisson model, the
  likelihood ratio statistic, and its p value on the boundary,
  `chi2.sf(LR, 1) / 2`.
- `glm`: the deviance and Pearson's chi-square over its degrees of freedom,
  from statsmodels' `GLM` with the negative binomial family at the fitted
  alpha. It gives the same coefficients.
"""

import numpy
import scipy.stats
import statsmodels.api as sm

with open("negbin_strata.txt") as data:
    rows = numpy.array([[float(v) for v in line.split()] for line in data if line.strip()])
events, years, smoking, age = rows.T
n = len(events)
X = sm.add_constant(numpy.column_stack([smoking, age]))


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


for i in range(n):
    line("stratum", [events[i], years[i], smoking[i], age[i]])
model = sm.NegativeBinomial(events, X, exposure=years, loglike_method="nb2")
fit = model.fit(method="newton", tol=1e-14, maxiter=500, disp=0)
line("params", fit.params)
line("errors", fit.bse)
poisson = sm.Poisson(events, X, exposure=years).fit(method="newton", tol=1e-14, disp=0)
statistic = 2.0 * (fit.llf - poisson.llf)
line("fit", [fit.llf, poisson.llf, statistic, scipy.stats.chi2.sf(statistic, 1) / 2.0])
glm = sm.GLM(
    events, X, family=sm.families.NegativeBinomial(alpha=fit.params[-1]), exposure=years
).fit(tol=1e-15)
line("glm", [glm.deviance, glm.pearson_chi2 / glm.df_resid, *glm.params])
