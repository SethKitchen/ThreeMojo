# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write an inverse probability weighted effect with statsmodels and numpy.

    python3 make_propensity.py > propensity_expected.txt

Run it with numpy 2.5.4 and statsmodels 0.15.0. A synthetic observational
study has 500 patients with three covariates: an age in decades from 60, a
sex, and a severity score. Older and sicker patients are treated more
often, and they also have the outcome more often, so the crude risks are
confounded. Each `patient` line holds the treatment, the outcome and the
three covariates.

- `effect`: the average treatment effect, the mean outcome under control
  and under treatment, from statsmodels' `TreatmentEffect.ipw`, and their
  standard errors. statsmodels takes the derivatives of its moments
  numerically. So the line also holds the errors from the same sandwich
  with exact derivatives in numpy, and the covariance of the two means.
- `closed`: the same effect and means from their closed form in numpy, the
  weighted means of each group.
- `ratio`: the risk ratio of the two means, and its interval by the delta
  method on the logs.
- `balance`: for each covariate, the standardized difference before and
  after weighting, as Austin and Stuart (2015) give it.
- `size`: the effective sample size of the treated and of the controls,
  `(sum w)^2 / sum w^2`.
- `evalue`: the E-value of the risk ratio and of its interval, by
  VanderWeele and Ding (2017).
"""

import numpy
import scipy.stats
import statsmodels.api as sm
from statsmodels.treatment import treatment_effects

generator = numpy.random.default_rng(20261115)
n = 500
age = generator.normal(0.0, 1.0, n)
sex = (generator.random(n) < 0.5).astype(float)
severity = generator.normal(0.0, 1.0, n)
logit = -0.4 + 0.7 * age + 0.3 * sex + 0.6 * severity
treated = (generator.random(n) < 1.0 / (1.0 + numpy.exp(-logit))).astype(int)
risk = 1.0 / (1.0 + numpy.exp(-(-1.2 + 0.6 * age + 0.2 * sex + 0.8 * severity - 0.5 * treated)))
outcome = (generator.random(n) < risk).astype(float)
covariates = numpy.column_stack([age, sex, severity])


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


for i in range(n):
    line("patient", [treated[i], outcome[i], *covariates[i]])

X = sm.add_constant(covariates)
select = sm.Logit(treated, X).fit(method="newton", tol=1e-14, disp=0)
effect = treatment_effects.TreatmentEffect(
    sm.OLS(outcome, numpy.ones(n)), treated, results_select=select
).ipw(return_results=True, disp=False)

p = select.predict()
w = treated / p + (1 - treated) / (1 - p)
mean1 = numpy.sum(w * treated * outcome) / numpy.sum(w * treated)
mean0 = numpy.sum(w * (1 - treated) * outcome) / numpy.sum(w * (1 - treated))
tau = mean1 - mean0
residual = outcome - tau * treated - mean0
k = X.shape[1]
moments = numpy.column_stack([w * residual * treated, w * residual, (treated - p)[:, None] * X])
dw = numpy.where(treated == 1, -(1 - p) / p, p / (1 - p))[:, None] * X
G = numpy.zeros((2 + k, 2 + k))
G[0, 0] = G[0, 1] = G[1, 0] = numpy.mean(-w * treated)
G[1, 1] = numpy.mean(-w)
G[0, 2:] = numpy.mean(dw * (residual * treated)[:, None], axis=0)
G[1, 2:] = numpy.mean(dw * residual[:, None], axis=0)
G[2:, 2:] = -(X * (p * (1 - p))[:, None]).T @ X / n
inverse = numpy.linalg.inv(G)
V = inverse @ (moments.T @ moments / n) @ inverse.T / n
var1 = V[0, 0] + V[1, 1] + 2 * V[0, 1]
cov10 = V[0, 1] + V[1, 1]
line(
    "effect",
    [*effect.effect, *effect.sd, numpy.sqrt(V[0, 0]), numpy.sqrt(V[1, 1]), numpy.sqrt(var1), cov10],
)

line("closed", [tau, mean0, mean1])
ratio = mean1 / mean0
log_var = var1 / mean1**2 + V[1, 1] / mean0**2 - 2 * cov10 / (mean1 * mean0)
z = scipy.stats.norm.ppf(0.975)
lower = ratio * numpy.exp(-z * numpy.sqrt(log_var))
upper = ratio * numpy.exp(z * numpy.sqrt(log_var))
line("ratio", [ratio, numpy.sqrt(log_var), lower, upper])


def weighted(x, weights):
    mean = numpy.sum(weights * x) / numpy.sum(weights)
    total = numpy.sum(weights)
    variance = total / (total**2 - numpy.sum(weights**2)) * numpy.sum(weights * (x - mean) ** 2)
    return mean, variance


def difference(x, weights):
    m1, v1 = weighted(x[treated == 1], weights[treated == 1])
    m0, v0 = weighted(x[treated == 0], weights[treated == 0])
    return (m1 - m0) / numpy.sqrt((v1 + v0) / 2.0)


ones = numpy.ones(n)
for column in range(3):
    x = covariates[:, column]
    line("balance", [difference(x, ones), difference(x, w)])
line(
    "size",
    [numpy.sum(w[treated == 1]) ** 2 / numpy.sum(w[treated == 1] ** 2),
     numpy.sum(w[treated == 0]) ** 2 / numpy.sum(w[treated == 0] ** 2)],
)


def e_value(rr):
    rr = rr if rr >= 1 else 1.0 / rr
    return rr + numpy.sqrt(rr * (rr - 1.0))


bound = 1.0 if lower <= 1.0 <= upper else (e_value(lower) if lower > 1 else e_value(upper))
line("evalue", [e_value(ratio), bound])
