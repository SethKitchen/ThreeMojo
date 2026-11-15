# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write an inverse probability weighted effect with statsmodels and numpy.

    mojo run -I . tools/make_propensity.mojo
    cd assets/propensity && python3 make_propensity.py > propensity_expected.txt

Run it with numpy 2.5.4 and statsmodels 0.15.0.
`tools/make_propensity.mojo` writes a synthetic observational study,
`patients.txt`: 500 patients with a treatment, an outcome and three
covariates, a standardized age, a sex and a standardized severity. Older
and sicker patients are treated more often, and they also have the
outcome more often, so the crude risks are confounded. This script
copies each patient to a `patient` line, then writes:

- `effect`: the average treatment effect, the mean outcome under control
  and under treatment, from statsmodels' `TreatmentEffect.ipw`, and their
  standard errors. statsmodels takes the derivatives of its moments
  numerically.
- `covariance`: the variance of the effect, the covariance of the effect
  and the control mean, and the variance of the control mean, from the
  covariance of statsmodels' GMM fit.
- `score`: the propensity score of each patient, from statsmodels'
  `Logit.predict`.
- `moments`: for each covariate, the means of numpy's `average` and the
  variances of numpy's `cov` with `aweights`, of the treated and then the
  control patients. They come first without weights, then with the
  weights `1 / p` of the treated and `1 / (1 - p)` of the controls.

The weights, the standardized differences of Austin and Stuart (2015),
the risk ratio and its interval, the effective sample sizes and the
E-values are closed forms of these. The Mojo tests check them.
"""

import numpy
import statsmodels.api as sm
from statsmodels.treatment import treatment_effects

with open("patients.txt") as data:
    rows = numpy.array([[float(v) for v in line.split()] for line in data if line.strip()])
treated = rows[:, 0].astype(int)
outcome = rows[:, 1]
covariates = rows[:, 2:]
n = len(outcome)


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


for i in range(n):
    line("patient", [treated[i], outcome[i], *covariates[i]])

X = sm.add_constant(covariates)
select = sm.Logit(treated, X).fit(method="newton", tol=1e-14, disp=0)
effect = treatment_effects.TreatmentEffect(
    sm.OLS(outcome, numpy.ones(n)), treated, results_select=select
).ipw(return_results=True, disp=False)
line("effect", [*effect.effect, *effect.sd])
cov = effect.results_gmm.cov_params()
line("covariance", [cov[0, 0], cov[0, 1], cov[1, 1]])

p = select.predict()
line("score", p)
w = numpy.where(treated == 1, 1.0 / p, 1.0 / (1.0 - p))


def moments(x, weights):
    one = treated == 1
    zero = treated == 0
    return [
        numpy.average(x[one], weights=weights[one]),
        numpy.average(x[zero], weights=weights[zero]),
        numpy.cov(x[one], aweights=weights[one]),
        numpy.cov(x[zero], aweights=weights[zero]),
    ]


ones = numpy.ones(n)
for column in range(3):
    x = covariates[:, column]
    line("moments", moments(x, ones) + moments(x, w))
