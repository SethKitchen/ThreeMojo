# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the survival of two arms at three times, with its Greenwood
standard error, by statsmodels.

    python3 make_nnt.py > nnt_expected.txt

Run it with numpy 2.5.4 and statsmodels 0.15.0. The groups are the 6-MP
and placebo arms of the trial of Freireich and others (1963). At each
time, a `time` line holds the time in weeks, then the survival of the
6-MP arm and its standard error, then those of the placebo arm. They come
from statsmodels' `SurvfuncRight`, whose error is Greenwood's.

The test builds the difference, its standard error and interval, and the
number needed to treat of Altman and Andersen (1999) from them.
"""

import numpy
from statsmodels.duration.survfunc import SurvfuncRight

DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def curve(text):
    times = numpy.array([float(t.rstrip("+")) for t in text.split()])
    events = numpy.array([0 if t.endswith("+") else 1 for t in text.split()])
    return SurvfuncRight(times, events)


def at(fitted, t):
    """Return the survival and its error at t: those of the last event
    time at or before t, or 1 and 0 before the first."""
    last = numpy.searchsorted(fitted.surv_times, t, side="right") - 1
    if last < 0:
        return 1.0, 0.0
    return fitted.surv_prob[last], fitted.surv_prob_se[last]


drug = curve(DRUG)
placebo = curve(PLACEBO)
for t in (10.0, 15.0, 20.0):
    values = [t, *at(drug, t), *at(placebo, t)]
    print("time", " ".join(repr(float(v)) for v in values))
