# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write exponential and Weibull fits of censored times, with mpmath, and
check them against lifelines.

    python3 make_parametric.py

Run it with numpy 2.5.4, scipy 1.18.1, mpmath 1.4.1 and lifelines 0.30.3.
It writes `parametric_data.txt` and `parametric_expected.txt` beside it.

The groups are the 6-MP and placebo arms of the trial of Freireich and
others (1963) in weeks, and two synthetic groups in days: a Weibull shape
of 1.6 and of 0.7, with uniform censoring. A time with a `+` is censored.

mpmath finds each fit at 40 digits. The Weibull shape is the root of the
profile score `d / rho + sum_e ln t - d sum t^rho ln t / sum t^rho`, and
the scale is `(sum t^rho / d)^(1 / rho)`. The variances are the inverse
of the observed information in (scale, shape). lifelines'
`ExponentialFitter` and `WeibullFitter` must agree with the fits to a
relative 1e-5: lifelines fits both by a search that stops early, though
the exponential fit has the closed form `sum t / d`.

For each group, `parametric_expected.txt` holds these lines, in the unit
of the group:

- `exponential`: the scale, its standard error and the log-likelihood;
- `weibull`: the scale, the shape, their standard errors, their
  covariance and the log-likelihood;
- `test`: the likelihood ratio statistic of shape 1 and its p value from
  scipy's `chi2.sf`;
- `median`: the Weibull median and the ends of its 95 percent interval,
  by the delta method on the log of the time;
- `quantile`: the same at a survival of 0.2;
- `at`: a time, the Weibull survival there, its delta-method standard
  error as lifelines gives it, the ends of its interval on the scale of
  the log cumulative hazard, and the hazard in events for each unit of
  time.
"""

import os

import mpmath
import numpy
import scipy.stats
from lifelines import ExponentialFitter, WeibullFitter

mpmath.mp.dps = 40
HERE = os.path.dirname(os.path.abspath(__file__))
Z = mpmath.sqrt(2) * mpmath.erfinv(mpmath.mpf("0.95"))

DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def synthetic(seed, n, scale, shape, follow):
    rng = numpy.random.default_rng(seed)
    times = scale * rng.weibull(shape, n)
    censor = rng.uniform(0, follow, n)
    words = []
    for t, c in zip(times, censor):
        if t <= c:
            words.append("%.2f" % t)
        else:
            words.append("%.2f+" % c)
    return " ".join(words)


GROUPS = [
    ("drug", "wk", DRUG, ["5", "10", "20", "40"]),
    ("placebo", "wk", PLACEBO, ["1", "5", "10", "20"]),
    ("rising", "d", synthetic(7, 60, 10.0, 1.6, 25.0), ["0.5", "5", "10", "30"]),
    ("falling", "d", synthetic(11, 40, 8.0, 0.7, 30.0), ["0.1", "2", "10", "40"]),
]


def read(text):
    times = [mpmath.mpf(t.rstrip("+")) for t in text.split()]
    events = [not t.endswith("+") for t in text.split()]
    return times, events


def weibull(times, events):
    d = sum(events)
    logs = sum(mpmath.log(t) for t, e in zip(times, events) if e)

    def score(rho):
        a = sum(t**rho for t in times)
        b = sum(t**rho * mpmath.log(t) for t in times)
        return d / rho + logs - d * b / a

    rho = mpmath.findroot(score, mpmath.mpf(1))
    lam = (sum(t**rho for t in times) / d) ** (1 / rho)
    w = [(t / lam) ** rho for t in times]
    ln = [mpmath.log(t / lam) for t in times]
    info = mpmath.matrix(
        [
            [rho**2 * d / lam**2, -rho * sum(wi * li for wi, li in zip(w, ln)) / lam],
            [-rho * sum(wi * li for wi, li in zip(w, ln)) / lam, d / rho**2 + sum(wi * li * li for wi, li in zip(w, ln))],
        ]
    )
    variance = info**-1
    ll = d * mpmath.log(rho) - d * mpmath.log(lam) + (rho - 1) * sum(
        l for l, e in zip(ln, events) if e
    ) - sum(w)
    return lam, rho, variance, ll


def quantile(lam, rho, v, p):
    q = mpmath.log(1 / mpmath.mpf(p))
    t = lam * q ** (1 / rho)
    g = [1 / lam, -mpmath.log(q) / rho**2]
    var = g[0] ** 2 * v[0, 0] + 2 * g[0] * g[1] * v[0, 1] + g[1] ** 2 * v[1, 1]
    se = mpmath.sqrt(var)
    return t, t * mpmath.exp(-Z * se), t * mpmath.exp(Z * se)


def at(lam, rho, v, t):
    h = (t / lam) ** rho
    s = mpmath.exp(-h)
    ln = mpmath.log(t / lam)
    # The gradient of S, then of ln H, in (scale, shape).
    gs = [s * rho * h / lam, -s * h * ln]
    se_s = mpmath.sqrt(gs[0] ** 2 * v[0, 0] + 2 * gs[0] * gs[1] * v[0, 1] + gs[1] ** 2 * v[1, 1])
    gl = [-rho / lam, ln]
    se_l = mpmath.sqrt(gl[0] ** 2 * v[0, 0] + 2 * gl[0] * gl[1] * v[0, 1] + gl[1] ** 2 * v[1, 1])
    lower = mpmath.exp(-h * mpmath.exp(Z * se_l))
    upper = mpmath.exp(-h * mpmath.exp(-Z * se_l))
    hazard = rho / lam * (t / lam) ** (rho - 1)
    return s, se_s, lower, upper, hazard


def close(a, b, tolerance):
    assert abs(a - b) <= tolerance * abs(b), (a, b)


def words(values):
    return " ".join(repr(float(v)) for v in values)


data = []
expected = []
for name, unit, text, probes in GROUPS:
    data.append("%s %s %s" % (name, unit, text))
    times, events = read(text)
    d = sum(events)
    total = sum(times)
    lam_e = total / d
    se_e = lam_e / mpmath.sqrt(d)
    ll_e = -d * mpmath.log(lam_e) - total / lam_e
    lam, rho, v, ll = weibull(times, events)
    statistic = 2 * (ll - ll_e)
    p = scipy.stats.chi2.sf(float(statistic), 1)

    floats = [float(t) for t in times]
    exponential = ExponentialFitter().fit(floats, events)
    close(exponential.lambda_, float(lam_e), 1e-5)
    close(exponential.summary.loc["lambda_", "se(coef)"], float(se_e), 1e-4)
    close(exponential.log_likelihood_, float(ll_e), 1e-10)
    fitter = WeibullFitter().fit(floats, events)
    close(fitter.lambda_, float(lam), 1e-5)
    close(fitter.rho_, float(rho), 1e-5)
    close(fitter.log_likelihood_, float(ll), 1e-10)
    matrix = fitter.variance_matrix_.values
    close(matrix[0, 0], float(v[0, 0]), 1e-4)
    close(matrix[1, 1], float(v[1, 1]), 1e-4)
    close(matrix[0, 1], float(v[0, 1]), 1e-3)
    close(fitter.median_survival_time_, float(quantile(lam, rho, v, "0.5")[0]), 1e-5)

    expected.append("%s exponential %s" % (name, words([lam_e, se_e, ll_e])))
    expected.append(
        "%s weibull %s"
        % (name, words([lam, rho, mpmath.sqrt(v[0, 0]), mpmath.sqrt(v[1, 1]), v[0, 1], ll]))
    )
    expected.append("%s test %s" % (name, words([statistic, p])))
    expected.append("%s median %s" % (name, words(quantile(lam, rho, v, "0.5"))))
    expected.append("%s quantile %s" % (name, words(quantile(lam, rho, v, "0.2"))))
    for probe in probes:
        t = mpmath.mpf(probe)
        s, se_s, lower, upper, hazard = at(lam, rho, v, t)
        # lifelines gives S -+ z se on its timeline; ask at this time.
        point = WeibullFitter().fit(floats, events, timeline=[float(t)])
        frame = point.confidence_interval_survival_function_.values[0]
        close((frame[1] - frame[0]) / (2 * float(Z)), float(se_s), 1e-3)
        assert abs(float(point.survival_function_at_times(float(t)).iloc[0]) - float(s)) <= 1e-5
        expected.append("%s at %s" % (name, words([t, s, se_s, lower, upper, hazard])))

with open(os.path.join(HERE, "parametric_data.txt"), "w") as out:
    out.write("\n".join(data) + "\n")
with open(os.path.join(HERE, "parametric_expected.txt"), "w") as out:
    out.write("\n".join(expected) + "\n")
