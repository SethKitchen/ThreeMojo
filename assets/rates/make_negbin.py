# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a negative binomial (NB2) model of event rates with statsmodels.

    python3 make_negbin.py > negbin_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and statsmodels 0.15.0. A synthetic
cohort has 120 strata, each with a person-time in years, a smoking flag
and an age in decades from 60. Its counts are gamma-Poisson with a
dispersion of 0.5, so they spread more than Poisson counts. Each `stratum`
line holds the events, the person-years and the two covariates.

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

generator = numpy.random.default_rng(20261115)
n = 120
years = numpy.round(generator.uniform(50.0, 400.0, n), 1)
smoking = (generator.random(n) < 0.4).astype(float)
age = numpy.round(generator.normal(0.0, 1.0, n), 2)
rate = numpy.exp(-3.0 + 0.6 * smoking + 0.4 * age)
mean = years * rate * generator.gamma(2.0, 0.5, n)
events = generator.poisson(mean)
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
