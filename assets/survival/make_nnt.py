# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the difference of two survival curves at a time, and its number
needed to treat, with lifelines and numpy.

    python3 make_nnt.py > nnt_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and lifelines 0.30.3. The groups are
the 6-MP and placebo arms of the trial of Freireich and others (1963). At
each time, a `time` line holds the time in weeks, then:

- the survival of each arm from lifelines' `KaplanMeierFitter`;
- the difference, 6-MP less placebo, and its standard error from the
  Greenwood variance of each arm, `S^2 sum d / (n (n - d))`, in numpy;
- the ends of its 95 percent interval;
- the number needed to treat, `1 / difference`, as Altman and Andersen
  (1999) give it.
"""

import numpy
import scipy.stats
from lifelines import KaplanMeierFitter

DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def read(text):
    times = [float(t.rstrip("+")) for t in text.split()]
    events = [not t.endswith("+") for t in text.split()]
    return times, events


def at(times, events, t):
    fitter = KaplanMeierFitter().fit(times, events)
    survival = float(fitter.survival_function_at_times(t).iloc[0])
    table = fitter.event_table
    rows = table[(table.index > 0) & (table.index <= t)]
    d = rows["observed"].values
    n = rows["at_risk"].values
    greenwood = numpy.sum(d / (n * (n - d)))
    return survival, survival * survival * greenwood


z = scipy.stats.norm.ppf(0.975)
for t in (10.0, 15.0, 20.0):
    s1, v1 = at(*read(DRUG), t)
    s0, v0 = at(*read(PLACEBO), t)
    difference = s1 - s0
    error = numpy.sqrt(v1 + v0)
    print(
        "time",
        " ".join(
            repr(float(v))
            for v in [t, s1, s0, difference, error, difference - z * error, difference + z * error, 1.0 / difference]
        ),
    )
