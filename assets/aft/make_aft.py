# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write lifelines' Weibull accelerated failure time fits, and scipy's
p values of the reference statistics.

    mojo run -I . tools/make_aft.mojo
    mojo run -I . tools/reference_aft.mojo
    cd assets/aft && python3 make_aft.py

Run it with numpy 2.5.4, scipy 1.18.1, pandas and lifelines 0.30.3.
`tools/make_aft.mojo` writes the groups, `aft_cohort.txt`: the 6-MP trial
of Freireich and others (1963) in weeks, with 1 for the placebo, a
synthetic cohort of 150 patients in days, and two small groups of 6 and 4
patients that make the first Newton step too long. Each line holds the
group, a time, 1 for an event or 0, and the covariates.
`tools/reference_aft.mojo` writes the fits at about 32 digits,
`aft_expected.txt`. This script writes `aft_lifelines.txt` beside them.

The model is `log T = b . x + W / rho`. lifelines' `WeibullAFTFitter`
stops its search early, to about 1e-5, so the test compares it with the
reference to lifelines' own tolerance. For each group, the file holds:

- `coefficients`: the intercept, the covariates, then the log of rho;
- `errors`: their standard errors;
- `fit`: the log-likelihood, and scipy's `chi2.sf` of the reference
  likelihood ratio statistic, with one degree of freedom for each
  covariate;
- `median`: the median times of `predict_median` for the first, middle
  and last patient.
"""

import os

import numpy
import pandas
import scipy.stats
from lifelines import WeibullAFTFitter

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {
    "trial": ["placebo"],
    "cohort": ["age", "marker", "treated"],
    "spread": ["flag"],
    "tiny": ["flag"],
}


def words(values):
    return " ".join(repr(float(v)) for v in values)


groups = {}
with open(os.path.join(HERE, "aft_cohort.txt")) as data:
    for line in data:
        name, *values = line.split()
        groups.setdefault(name, []).append([float(v) for v in values])

statistics = {}
with open(os.path.join(HERE, "aft_expected.txt")) as data:
    for line in data:
        name, kind, *values = line.split()
        if kind == "fit":
            statistics[name] = float(values[2])

lines = []
for name, names in NAMES.items():
    rows = numpy.array(groups[name])
    t, e, x = rows[:, 0], rows[:, 1], rows[:, 2:]
    frame = pandas.DataFrame(x, columns=names)
    frame["T"] = t
    frame["E"] = e
    fitter = WeibullAFTFitter().fit(frame, "T", "E")
    keys = [("lambda_", n) for n in ["Intercept"] + names] + [("rho_", "Intercept")]
    lines.append("%s coefficients %s" % (name, words([fitter.params_[k] for k in keys])))
    lines.append(
        "%s errors %s" % (name, words([fitter.summary.loc[k, "se(coef)"] for k in keys]))
    )
    p = scipy.stats.chi2.sf(statistics[name], len(names))
    lines.append("%s fit %s" % (name, words([fitter.log_likelihood_, p])))
    probe = x[[0, len(x) // 2, len(x) - 1]]
    medians = fitter.predict_median(pandas.DataFrame(probe, columns=names))
    lines.append("%s median %s" % (name, words(medians)))

with open(os.path.join(HERE, "aft_lifelines.txt"), "w") as out:
    out.write("\n".join(lines) + "\n")
