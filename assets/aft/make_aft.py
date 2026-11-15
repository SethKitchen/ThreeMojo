# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Weibull accelerated failure time fits of lifelines, polished by
mpmath.

    mojo run -I . tools/make_aft.mojo
    cd assets/aft && python3 make_aft.py

Run it with numpy 2.5.4, scipy 1.18.1, pandas, mpmath 1.4.1 and
lifelines 0.30.3. `tools/make_aft.mojo` writes the groups,
`aft_cohort.txt`: the 6-MP trial of Freireich and others (1963) in
weeks, with 1 for the placebo, a synthetic cohort of 150 patients in
days, and two small groups of 6 and 4 patients that make the first
Newton step too long. Each line holds the group, a time, 1 for an event
or 0, and the covariates. This script writes `aft_expected.txt`.

The model is `log T = b . x + W / rho`, with x the covariates after a 1
for the intercept: the scale of a patient is `exp(b . x)`, and the shape
rho is the same for all. lifelines' `WeibullAFTFitter` fits each group,
and stops its search early, to about 1e-5. mpmath's `findroot` then
solves the score equations from that fit at 40 digits, in `(g, rho)`
with `g = -rho b`, where the log-likelihood is concave. lifelines must
agree with the result: the coefficients, the log of the shape and the
standard errors to 1e-4, and the log-likelihood to 1e-9. The model
without covariates starts from lifelines' `WeibullFitter`.

For each group, `aft_expected.txt` holds:

- `coefficients`: the intercept, the covariates, then the log of rho;
- `errors`: their standard errors, from the inverse of the information;
- `fit`: rho, the log-likelihood in the unit of the group, and the
  likelihood ratio statistic and its p value from scipy's `chi2.sf`;
- `median`: the covariates of a patient, then the median time and the
  survival at a time, given last.
"""

import os

import mpmath
import numpy
import pandas
import scipy.stats
from lifelines import WeibullAFTFitter, WeibullFitter

mpmath.mp.dps = 40
HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {
    "trial": ["placebo"],
    "cohort": ["age", "marker", "treated"],
    "spread": ["flag"],
    "tiny": ["flag"],
}


def polish(t, e, x, b, rho):
    """Solve the score equations of (g, rho) at 40 digits, from (b, rho)."""
    rows = [[mpmath.mpf(1)] + [mpmath.mpf(v) for v in row] for row in x]
    ln = [mpmath.log(mpmath.mpf(v)) for v in t]
    ev = [mpmath.mpf(v) for v in e]
    d = sum(ev)
    k = len(rows[0])

    def weights(g, r):
        return [mpmath.exp(r * ln[i] + mpmath.fsum(rows[i][j] * g[j] for j in range(k)))
                for i in range(len(rows))]

    def score(*p):
        g, r = p[:k], p[k]
        w = weights(g, r)
        out = [mpmath.fsum(rows[i][j] * (ev[i] - w[i]) for i in range(len(rows))) for j in range(k)]
        out.append(d / r + mpmath.fsum(ev[i] * ln[i] - w[i] * ln[i] for i in range(len(rows))))
        return out

    def hessian(*p):
        g, r = p[:k], p[k]
        w = weights(g, r)
        h = mpmath.matrix(k + 1, k + 1)
        for a in range(k):
            for c in range(k):
                h[a, c] = -mpmath.fsum(w[i] * rows[i][a] * rows[i][c] for i in range(len(rows)))
            h[a, k] = h[k, a] = -mpmath.fsum(w[i] * ln[i] * rows[i][a] for i in range(len(rows)))
        h[k, k] = -d / r**2 - mpmath.fsum(w[i] * ln[i] ** 2 for i in range(len(rows)))
        return h

    start = [-mpmath.mpf(rho) * mpmath.mpf(v) for v in b] + [mpmath.mpf(rho)]
    p = mpmath.findroot(score, start, J=hessian, tol=mpmath.mpf(10) ** -35, maxsteps=200)
    p = [p[i] for i in range(k + 1)]
    g, r = p[:k], p[k]
    w = weights(g, r)
    ll = mpmath.fsum(
        ev[i] * (mpmath.log(r) + (r - 1) * ln[i] + mpmath.fsum(rows[i][j] * g[j] for j in range(k)))
        for i in range(len(rows))
    ) - mpmath.fsum(w)
    h = hessian(*p)
    # From (g, rho) to (b, log rho): b = -g / rho.
    jac = mpmath.matrix(k + 1, k + 1)
    for a in range(k):
        jac[a, a] = -1 / r
        jac[a, k] = g[a] / r**2
    jac[k, k] = 1 / r
    variance = jac * (-h) ** -1 * jac.T
    return [-v / r for v in g], r, variance, ll


def close(a, b, tolerance):
    assert abs(a - b) <= tolerance * max(abs(b), 1e-300), (a, b)


def words(values):
    return " ".join(repr(float(v)) for v in values)


groups = {}
with open(os.path.join(HERE, "aft_cohort.txt")) as data:
    for line in data:
        name, *values = line.split()
        groups.setdefault(name, []).append([float(v) for v in values])

expected = []
for name, names in NAMES.items():
    rows = numpy.array(groups[name])
    t, e, x = rows[:, 0], rows[:, 1], rows[:, 2:]
    frame = pandas.DataFrame(x, columns=names)
    frame["T"] = t
    frame["E"] = e
    fitter = WeibullAFTFitter().fit(frame, "T", "E")
    start = [fitter.params_[("lambda_", n)] for n in ["Intercept"] + names]
    b, rho, variance, ll = polish(t, e, x, start, numpy.exp(fitter.params_[("rho_", "Intercept")]))
    plain = WeibullFitter().fit(t, e)
    _, _, _, ll0 = polish(t, e, numpy.zeros((len(t), 0)), [numpy.log(plain.lambda_)], plain.rho_)
    statistic = 2 * (ll - ll0)
    p = scipy.stats.chi2.sf(float(statistic), len(names))

    errors = [mpmath.sqrt(variance[i, i]) for i in range(len(b) + 1)]
    for i, n in enumerate(["Intercept"] + names):
        close(fitter.params_[("lambda_", n)], float(b[i]), 1e-4)
        close(fitter.summary.loc[("lambda_", n), "se(coef)"], float(errors[i]), 1e-4)
    close(fitter.params_[("rho_", "Intercept")], float(mpmath.log(rho)), 1e-4)
    close(fitter.summary.loc[("rho_", "Intercept"), "se(coef)"], float(errors[-1]), 1e-4)
    close(fitter.log_likelihood_, float(ll), 1e-9)

    expected.append("%s coefficients %s" % (name, words(list(b) + [mpmath.log(rho)])))
    expected.append("%s errors %s" % (name, words(errors)))
    expected.append("%s fit %s" % (name, words([rho, ll, statistic, p])))
    probe = x[[0, len(x) // 2, len(x) - 1]]
    at = numpy.median(t)
    for row in probe:
        scale = mpmath.exp(b[0] + mpmath.fsum(mpmath.mpf(row[j]) * b[j + 1] for j in range(len(row))))
        median = scale * mpmath.log(2) ** (1 / rho)
        survival = mpmath.exp(-((mpmath.mpf(at) / scale) ** rho))
        check = fitter.predict_median(pandas.DataFrame([row], columns=names)).iloc[0]
        close(check, float(median), 1e-4)
        expected.append("%s median %s" % (name, words(list(row) + [median, at, survival])))

with open(os.path.join(HERE, "aft_expected.txt"), "w") as out:
    out.write("\n".join(expected) + "\n")
