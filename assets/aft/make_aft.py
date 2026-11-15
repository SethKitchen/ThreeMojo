# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Weibull accelerated failure time fits with numpy, and check them
against lifelines.

    python3 make_aft.py

Run it with numpy 2.5.4, scipy 1.18.1, pandas and lifelines 0.30.3. It
writes `aft_cohort.txt` and `aft_expected.txt` beside it.

The model is `log T = b . x + W / rho`, with x the covariates after a 1
for the intercept: the scale of a patient is `exp(b . x)`, and the shape
rho is the same for all. The groups are the 6-MP trial of Freireich and
others (1963) in weeks, with 1 for the placebo, and a synthetic cohort of
150 patients in days, with an age in decades, a marker and a treatment.
Two small groups of 6 and 4 patients, in days, make the first Newton
step too long. Each line of `aft_cohort.txt` holds the group, a time, 1
for an event or 0, and the covariates.

numpy fits each group by Newton steps on `(-rho b, rho)`, in which the
log-likelihood is concave, to the last place. lifelines'
`WeibullAFTFitter` must agree with it: the coefficients, the log of the
shape and the standard errors to 1e-4, and the log-likelihood to 1e-9.
lifelines stops its search early.

For each group, `aft_expected.txt` holds:

- `coefficients`: the intercept, the covariates, then the log of rho;
- `errors`: their standard errors, from the inverse of the information;
- `fit`: rho, the log-likelihood in the unit of the group, and the
  likelihood ratio statistic and p value against no covariates;
- `median`: the covariates of a patient, then the median time and the
  survival at a time, given last.
"""

import os

import numpy
import pandas
import scipy.stats
from lifelines import WeibullAFTFitter

HERE = os.path.dirname(os.path.abspath(__file__))
DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def trial():
    rows = []
    for text, flag in ((DRUG, 0.0), (PLACEBO, 1.0)):
        for word in text.split():
            rows.append([float(word.rstrip("+")), 0.0 if word.endswith("+") else 1.0, flag])
    return numpy.array(rows)


def cohort():
    rng = numpy.random.default_rng(1127)
    n = 150
    age = rng.uniform(4.0, 8.5, n)
    marker = rng.normal(0.0, 1.0, n)
    treated = (rng.random(n) < 0.5).astype(float)
    scale = numpy.exp(4.5 - 0.25 * (age - 6.0) - 0.3 * marker + 0.4 * treated)
    times = scale * rng.weibull(1.4, n)
    censor = rng.uniform(20.0, 250.0, n)
    event = (times <= censor).astype(float)
    t = numpy.round(numpy.minimum(times, censor), 2)
    return numpy.column_stack([t, event, numpy.round(age, 3), numpy.round(marker, 4), treated])


def newton(t, e, x):
    """Fit (g, rho) of h = rho t^(rho - 1) exp(g . x), g = -rho b."""
    x = numpy.column_stack([numpy.ones(len(t)), x])
    ln = numpy.log(t)
    d = e.sum()
    g = numpy.zeros(x.shape[1])
    g[0] = numpy.log(d / t.sum())
    rho = 1.0

    def ll(g, rho):
        return numpy.sum(e * (numpy.log(rho) + (rho - 1) * ln + x @ g)) - numpy.sum(numpy.exp(rho * ln + x @ g))

    for _ in range(100):
        w = numpy.exp(rho * ln + x @ g)
        grad = numpy.concatenate([x.T @ (e - w), [d / rho + e @ ln - w @ ln]])
        h = numpy.zeros((len(g) + 1, len(g) + 1))
        h[:-1, :-1] = -(x.T * w) @ x
        h[:-1, -1] = h[-1, :-1] = -(x.T @ (w * ln))
        h[-1, -1] = -d / rho**2 - w @ (ln * ln)
        step = -numpy.linalg.solve(h, grad)
        scale = 1.0
        while rho + scale * step[-1] <= 0 or ll(g + scale * step[:-1], rho + scale * step[-1]) < ll(g, rho) - 1e-12:
            scale /= 2
        g = g + scale * step[:-1]
        rho = rho + scale * step[-1]
        if numpy.max(numpy.abs(step)) < 1e-14:
            break
    w = numpy.exp(rho * ln + x @ g)
    h = numpy.zeros((len(g) + 1, len(g) + 1))
    h[:-1, :-1] = -(x.T * w) @ x
    h[:-1, -1] = h[-1, :-1] = -(x.T @ (w * ln))
    h[-1, -1] = -d / rho**2 - w @ (ln * ln)
    # From (g, rho) to (b, log rho): b = -g / rho.
    jac = numpy.zeros_like(h)
    jac[:-1, :-1] = -numpy.eye(len(g)) / rho
    jac[:-1, -1] = g / rho**2
    jac[-1, -1] = 1.0 / rho
    variance = jac @ numpy.linalg.inv(-h) @ jac.T
    return -g / rho, rho, variance, ll(g, rho)


def close(a, b, tolerance):
    assert abs(a - b) <= tolerance * max(abs(b), 1e-300), (a, b)


def words(values):
    return " ".join(repr(float(v)) for v in values)


# Two small groups whose first Newton step must be halved: one would make
# rho negative, and the other would lower the log-likelihood.
SPREAD = numpy.array([[t, 1.0, k % 2] for k, t in enumerate([0.01, 0.1, 1.0, 10.0, 100.0, 1000.0])])
TINY = numpy.array([[1.0, 1.0, 0.0], [2.0, 1.0, 1.0], [3.0, 1.0, 0.0], [100.0, 1.0, 1.0]])
groups = [
    ("trial", trial(), ["placebo"]),
    ("cohort", cohort(), ["age", "marker", "treated"]),
    ("spread", SPREAD, ["flag"]),
    ("tiny", TINY, ["flag"]),
]
data = []
expected = []
for name, rows, names in groups:
    for row in rows:
        data.append("%s %s" % (name, words(row)))
    t, e, x = rows[:, 0], rows[:, 1], rows[:, 2:]
    b, rho, variance, ll = newton(t, e, x)
    b0, rho0, _, ll0 = newton(t, e, numpy.zeros((len(t), 0)))
    statistic = 2 * (ll - ll0)
    p = scipy.stats.chi2.sf(statistic, len(names))

    frame = pandas.DataFrame(x, columns=names)
    frame["T"] = t
    frame["E"] = e
    fitter = WeibullAFTFitter().fit(frame, "T", "E")
    for i, n in enumerate(["Intercept"] + names):
        close(fitter.params_[("lambda_", n)], b[i], 1e-4)
        close(fitter.summary.loc[("lambda_", n), "se(coef)"], numpy.sqrt(variance[i, i]), 1e-4)
    close(fitter.params_[("rho_", "Intercept")], numpy.log(rho), 1e-4)
    close(fitter.summary.loc[("rho_", "Intercept"), "se(coef)"], numpy.sqrt(variance[-1, -1]), 1e-4)
    close(fitter.log_likelihood_, ll, 1e-9)

    errors = numpy.sqrt(numpy.diag(variance))
    expected.append("%s coefficients %s" % (name, words(list(b) + [numpy.log(rho)])))
    expected.append("%s errors %s" % (name, words(errors)))
    expected.append("%s fit %s" % (name, words([rho, ll, statistic, p])))
    probe = x[[0, len(x) // 2, len(x) - 1]]
    at = numpy.median(t)
    for row in probe:
        scale = numpy.exp(b[0] + row @ b[1:])
        median = scale * numpy.log(2.0) ** (1.0 / rho)
        survival = numpy.exp(-((at / scale) ** rho))
        check = fitter.predict_median(pandas.DataFrame([row], columns=names)).iloc[0]
        close(check, median, 1e-4)
        expected.append("%s median %s" % (name, words(list(row) + [median, at, survival])))

with open(os.path.join(HERE, "aft_cohort.txt"), "w") as out:
    out.write("\n".join(data) + "\n")
with open(os.path.join(HERE, "aft_expected.txt"), "w") as out:
    out.write("\n".join(expected) + "\n")
