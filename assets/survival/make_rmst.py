# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Nelson-Aalen hazards, Kaplan-Meier curves and restricted mean
survival times by lifelines, a Python library.

    python3 make_rmst.py > rmst_expected.txt

Run it with numpy and lifelines 0.30.3, on the 6-MP trial of Freireich
and others (1963) of `make_survival.py`. The output has these lines, for
the drug group and then the placebo group:

- `hazard` with the count of event times, then each time, the
  Nelson-Aalen cumulative hazard of lifelines without smoothing, and the
  low and high ends of its 95 percent interval.
- `curve` with the count of event times, then each time, the patients at
  risk, the events and the survival of lifelines' `KaplanMeierFitter`.
- `rmst` with the restricted mean survival time to 23 weeks of
  lifelines' `restricted_mean_survival_time`.

lifelines gives no standard error of the mean: its variance is that of
the restricted time itself. The test builds the error of Klein and
Moeschberger, as R's survRM2 gives it, from the `curve` lines.
"""

import numpy as np
from lifelines import KaplanMeierFitter, NelsonAalenFitter
from lifelines.utils import restricted_mean_survival_time

DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"
HORIZON = 23.0


def read(text):
    times = np.array([float(t.rstrip("+")) for t in text.split()])
    events = np.array([not t.endswith("+") for t in text.split()])
    return times, events


def line(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


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
    survival = curve.survival_function_.iloc[:, 0]
    values = [len(at)]
    for t in at:
        values += [
            t,
            curve.event_table.loc[t, "at_risk"],
            curve.event_table.loc[t, "observed"],
            survival.loc[t],
        ]
    line("curve", values)
    line("rmst", [restricted_mean_survival_time(curve, t=HORIZON)])
