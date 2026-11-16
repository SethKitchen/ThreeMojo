# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the cumulative incidence of two competing causes with lifelines.

    mojo run -I . tools/make_competing.mojo
    cd assets/competing && python3 make_competing.py > competing_expected.txt

Run it with numpy 2.5.4, pandas and lifelines 0.30.3.
`tools/make_competing.mojo` writes the synthetic cohort, `patients.txt`:
80 patients with a relapse at a rate of 0.15 a year, a death without
relapse at 0.10 a year, and a censoring time spread evenly up to 10
years. Each patient keeps the first of the three. The times are in years
with six decimals, so no two events tie and lifelines does not jitter
them. The longest time is a censoring.

- `times` and `causes`: the time and the cause of each patient: 0 for a
  censoring, 1 for a relapse and 2 for a death.
- For each cause `k`, the lines `k_times`, `k_incidence`, `k_variance`,
  `k_lower` and `k_upper` hold, at each time of an event of either
  cause, the cumulative incidence of `AalenJohansenFitter`, its variance
  and its 95 percent interval.
"""

import numpy
from lifelines import AalenJohansenFitter

with open("patients.txt") as data:
    rows = numpy.array([[float(v) for v in line.split()] for line in data if line.strip()])
times = rows[:, 0]
causes = rows[:, 1].astype(int)


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


line("times", times)
line("causes", causes)
for cause in (1, 2):
    fitter = AalenJohansenFitter(calculate_variance=True)
    fitter.fit(times, causes, event_of_interest=cause)
    table = fitter.event_table
    keep = (table["observed"] > 0).values
    at = table.index.values[keep]
    incidence = fitter.cumulative_density_.values[keep, 0]
    variance = fitter.variance_.values[keep]
    bounds = fitter.confidence_interval_.values[keep]
    line(f"{cause}_times", at)
    line(f"{cause}_incidence", incidence)
    line(f"{cause}_variance", variance)
    # lifelines names its interval columns the other way round, so take the
    # smaller end as the low one. Both are not a number where F is 0.
    line(f"{cause}_lower", numpy.min(bounds, axis=1))
    line(f"{cause}_upper", numpy.max(bounds, axis=1))
