# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Nelson-Aalen hazards and restricted mean survival times by
lifelines, a Python library, and numpy.

    python3 make_rmst.py > rmst_expected.txt

Run it with numpy, scipy and lifelines 0.30.3, on the 6-MP trial of
Freireich and others (1963) of `make_survival.py`. The output has these
lines, for the drug group and then the placebo group:

- `hazard` with the count of event times, then each time, the
  Nelson-Aalen cumulative hazard of lifelines without smoothing, and the
  low and high ends of its 95 percent interval.
- `rmst` with the restricted mean survival time to 23 weeks of
  lifelines' `restricted_mean_survival_time`, and its standard error,
  `sqrt(sum(A_j^2 d_j / (n_j (n_j - d_j))))` with `A_j` the area under the
  curve from event time `t_j` to 23 weeks, by numpy.

A last line `difference` has the drug's mean less the placebo's, its
standard error, z and the two-sided p value.
"""

import numpy as np
from lifelines import KaplanMeierFitter, NelsonAalenFitter
from lifelines.utils import restricted_mean_survival_time
from scipy import stats

DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"
HORIZON = 23.0


def read(text):
    times = np.array([float(t.rstrip("+")) for t in text.split()])
    events = np.array([not t.endswith("+") for t in text.split()])
    return times, events


def line(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


means = []
for text in [DRUG, PLACEBO]:
    times, events = read(text)
    hazard = NelsonAalenFitter(nelson_aalen_smoothing=False).fit(times, events)
    table = hazard.event_table
    at = [t for t in table.index if table.loc[t, "observed"] > 0]
    values = [len(at)]
    for t in at:
        values += [
            t,
            hazard.cumulative_hazard_.loc[t].iloc[0],
            hazard.confidence_interval_.loc[t].iloc[0],
            hazard.confidence_interval_.loc[t].iloc[1],
        ]
    line("hazard", values)
    curve = KaplanMeierFitter().fit(times, events)
    mean = restricted_mean_survival_time(curve, t=HORIZON)
    # The standard error of Klein and Moeschberger, as R's survRM2 gives.
    s = curve.survival_function_.iloc[:, 0]
    grid = [0.0] + [t for t in s.index if 0 < t <= HORIZON] + [HORIZON]
    variance = 0.0
    for t in at:
        if t > HORIZON:
            continue
        n = table.loc[t, "at_risk"]
        d = table.loc[t, "observed"]
        if d == n:
            continue
        area = 0.0
        for a, b in zip(grid[:-1], grid[1:]):
            if a >= t:
                area += (b - a) * curve.predict(a)
        variance += area * area * d / (n * (n - d))
    means.append((mean, variance))
    line("rmst", [mean, np.sqrt(variance)])
gap = means[0][0] - means[1][0]
error = np.sqrt(means[0][1] + means[1][1])
line("difference", [gap, error, gap / error, 2 * stats.norm.sf(abs(gap / error))])
