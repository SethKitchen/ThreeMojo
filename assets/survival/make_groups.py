# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the log-rank test of three groups by lifelines, a Python library.

    mojo run -I . tools/make_survival_groups.mojo
    cd assets/survival && python3 make_groups.py

Run it with lifelines 0.30.3. `tools/make_survival_groups.mojo` writes
three synthetic arms of a trial, `three_arms.txt`, each a line of times
in whole weeks, a `+` marking a censored patient, so that many times tie.
This script reads them.

- `groups_expected.txt` holds `multivariate_logrank_test`: the statistic,
  the degrees of freedom and the p value.
"""

from lifelines.statistics import multivariate_logrank_test

times, events, groups = [], [], []
with open("three_arms.txt") as data:
    for arm, line in enumerate(l for l in data if l.strip()):
        for word in line.split():
            times.append(float(word.rstrip("+")))
            events.append(not word.endswith("+"))
            groups.append(arm)
r = multivariate_logrank_test(times, groups, events)
with open("groups_expected.txt", "w") as out:
    out.write("groups %r %r %r\n" % (float(r.test_statistic), float(r.degrees_of_freedom), float(r.p_value)))
