# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Kaplan-Meier and log-rank results with lifelines, a Python library.

    python3 make_survival.py > freireich_expected.txt

Run it with lifelines 0.30.3. The data are the remission times in weeks of
the trial of 6-mercaptopurine against a placebo in acute leukemia, of
Freireich and others (1963), as Gehan (1965) gives them. A time with a
`+` is censored: the patient was still in remission when last seen.

For each group the output gives, at each time of a relapse, the time, the
survival after it, and the 95 percent interval of lifelines' exponential
Greenwood formula. Then it gives the median survival of each group, and
the statistic and the p value of the log-rank test.
"""

from lifelines import KaplanMeierFitter
from lifelines.statistics import logrank_test

DRUG = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def read(text):
    times = [float(t.rstrip("+")) for t in text.split()]
    events = [not t.endswith("+") for t in text.split()]
    return times, events


groups = {}
for name, text in [("drug", DRUG), ("placebo", PLACEBO)]:
    times, events = read(text)
    groups[name] = (times, events)
    fit = KaplanMeierFitter().fit(times, events)
    s = fit.survival_function_["KM_estimate"]
    ci = fit.confidence_interval_
    lows = ci.iloc[:, 0]
    highs = ci.iloc[:, 1]
    relapse = sorted(set(t for t, e in zip(times, events) if e))
    rows = []
    for t in relapse:
        rows.append(f"{t!r} {float(s.loc[t])!r} {float(lows.loc[t])!r} {float(highs.loc[t])!r}")
    print(name, len(relapse), " ".join(rows))
    print(name + "_median", repr(float(fit.median_survival_time_)))
a = groups["drug"]
b = groups["placebo"]
test = logrank_test(a[0], b[0], event_observed_A=a[1], event_observed_B=b[1])
print("logrank", repr(float(test.test_statistic)), repr(float(test.p_value)))
