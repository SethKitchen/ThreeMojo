# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write lifelines' exponential and Weibull fits of censored times, and
scipy's p values of the reference statistics.

    mojo run -I . tools/make_parametric.mojo
    mojo run -I . tools/reference_parametric.mojo
    cd assets/parametric && python3 make_parametric.py

Run it with scipy 1.18.1 and lifelines 0.30.3. `tools/make_parametric.mojo`
writes the groups, `parametric_data.txt`: the 6-MP and placebo arms of the
trial of Freireich and others (1963) in weeks, and two synthetic groups in
days, with a Weibull shape of 1.6 and of 0.7 and uniform censoring. A time
with a `+` is censored. `tools/reference_parametric.mojo` writes the fits
at about 32 digits, `parametric_expected.txt`. This script writes
`parametric_lifelines.txt` beside them.

lifelines fits by a search that stops early, so the test compares it with
the reference to lifelines' own tolerance. For each group, the file holds
these lines, in the unit of the group:

- `exponential`: the scale of `ExponentialFitter`, its standard error and
  the log-likelihood;
- `weibull`: the scale and the shape of `WeibullFitter`, its variance
  matrix by `(0, 0)`, `(1, 1)` and `(0, 1)`, the log-likelihood and the
  median;
- `test`: scipy's `chi2.sf` of the reference statistic, on one degree of
  freedom;
- `at`: a probe time of the reference, the survival of lifelines there,
  and the half width of its 95 percent interval over z, which is its
  standard error.
"""

import os

import scipy.stats
from lifelines import ExponentialFitter, WeibullFitter

HERE = os.path.dirname(os.path.abspath(__file__))
Z = scipy.stats.norm.ppf(0.975)


def read(text):
    times = [float(t.rstrip("+")) for t in text.split()]
    events = [not t.endswith("+") for t in text.split()]
    return times, events


def words(values):
    return " ".join(repr(float(v)) for v in values)


reference = {}
with open(os.path.join(HERE, "parametric_expected.txt")) as data:
    for line in data:
        name, kind, *values = line.split()
        reference.setdefault((name, kind), []).append([float(v) for v in values])

lines = []
with open(os.path.join(HERE, "parametric_data.txt")) as data:
    for line in data:
        name, unit, text = line.rstrip("\n").split(" ", 2)
        times, events = read(text)
        exponential = ExponentialFitter().fit(times, events)
        lines.append(
            "%s exponential %s"
            % (
                name,
                words(
                    [
                        exponential.lambda_,
                        exponential.summary.loc["lambda_", "se(coef)"],
                        exponential.log_likelihood_,
                    ]
                ),
            )
        )
        fitter = WeibullFitter().fit(times, events)
        matrix = fitter.variance_matrix_.values
        lines.append(
            "%s weibull %s"
            % (
                name,
                words(
                    [
                        fitter.lambda_,
                        fitter.rho_,
                        matrix[0, 0],
                        matrix[1, 1],
                        matrix[0, 1],
                        fitter.log_likelihood_,
                        fitter.median_survival_time_,
                    ]
                ),
            )
        )
        statistic = reference[(name, "test")][0][0]
        lines.append("%s test %s" % (name, words([scipy.stats.chi2.sf(statistic, 1)])))
        for row in reference[(name, "at")]:
            t = row[0]
            point = WeibullFitter().fit(times, events, timeline=[t])
            frame = point.confidence_interval_survival_function_.values[0]
            survival = point.survival_function_at_times(t).iloc[0]
            lines.append(
                "%s at %s" % (name, words([t, survival, (frame[1] - frame[0]) / (2 * Z)]))
            )

with open(os.path.join(HERE, "parametric_lifelines.txt"), "w") as out:
    out.write("\n".join(lines) + "\n")
