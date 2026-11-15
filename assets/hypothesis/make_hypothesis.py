# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write two-group tests by scipy, a Python library.

    python3 make_hypothesis.py

Run it with numpy and scipy 1.18.1. It writes two files:

- `groups.txt` holds synthetic falls of blood pressure in mmHg, whole
  numbers so that many tie: a first line of 25 values of a treated group, a
  second of 30 values of a control group, then two lines of 20 values of
  one group before and after a treatment.
- `hypothesis_expected.txt` holds the results, all two-sided:

  - `student` and `welch`: t, the degrees of freedom, the p value, and the
    95 percent interval of the treated mean less the control mean, by
    `ttest_ind` with equal and unequal variances.
  - `paired`: the same of `ttest_rel`, before less after.
  - `mann_whitney`: U of the treated group and the p value of
    `mannwhitneyu` by the normal approximation, with the tie correction and
    the continuity correction.
  - `wilcoxon`: the smaller of the signed rank sums, z and the p value of
    `wilcoxon` by the normal approximation, with zero differences dropped,
    the tie correction, and no continuity correction.
"""

import numpy as np
from scipy import stats

rng = np.random.default_rng(20261115)
treated = np.round(rng.normal(12.0, 6.0, 25))
control = np.round(rng.normal(7.0, 9.0, 30))
before = np.round(rng.normal(150.0, 12.0, 20))
after = before - np.round(rng.normal(4.0, 5.0, 20))
with open("groups.txt", "w") as out:
    for row in [treated, control, before, after]:
        out.write(" ".join("%d" % v for v in row) + "\n")


def line(name, values):
    return name + " " + " ".join(repr(float(v)) for v in values)


lines = []
for name, equal in [("student", True), ("welch", False)]:
    r = stats.ttest_ind(treated, control, equal_var=equal)
    ci = r.confidence_interval(0.95)
    lines.append(line(name, [r.statistic, r.df, r.pvalue, ci.low, ci.high]))
r = stats.ttest_rel(before, after)
ci = r.confidence_interval(0.95)
lines.append(line("paired", [r.statistic, r.df, r.pvalue, ci.low, ci.high]))
r = stats.mannwhitneyu(treated, control, use_continuity=True, method="asymptotic")
lines.append(line("mann_whitney", [r.statistic, r.pvalue]))
r = stats.wilcoxon(before, after, zero_method="wilcox", correction=False, method="approx")
lines.append(line("wilcoxon", [r.statistic, r.zstatistic, r.pvalue]))
with open("hypothesis_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
