# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the log-rank test of three groups by lifelines, a Python library.

    python3 make_groups.py

Run it with numpy and lifelines 0.30.3. It writes two files:

- `three_arms.txt` holds three synthetic arms of a trial, each a line of
  times in whole weeks, a `+` marking a censored patient, so that many
  times tie.
- `groups_expected.txt` holds `multivariate_logrank_test`: the statistic,
  the degrees of freedom and the p value.
"""

import numpy as np
from lifelines.statistics import multivariate_logrank_test

rng = np.random.default_rng(20261115)
times, events, groups = [], [], []
lines = []
for arm, scale in enumerate([20.0, 28.0, 40.0]):
    t = np.ceil(rng.exponential(scale, 25))
    c = np.ceil(rng.uniform(10, 60, 25))
    seen = np.minimum(t, c)
    happened = t <= c
    words = ["%d%s" % (s, "" if e else "+") for s, e in zip(seen, happened)]
    lines.append(" ".join(words))
    times += list(seen)
    events += list(happened)
    groups += [arm] * 25
with open("three_arms.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
r = multivariate_logrank_test(times, groups, events)
with open("groups_expected.txt", "w") as out:
    out.write("groups %r %r %r\n" % (float(r.test_statistic), float(r.degrees_of_freedom), float(r.p_value)))
