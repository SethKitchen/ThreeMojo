# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write two-group tests by scipy, a Python library.

    mojo run -I . tools/make_hypothesis.mojo
    cd assets/hypothesis && python3 make_hypothesis.py

Run it with scipy 1.18.1. `tools/make_hypothesis.mojo` writes the
synthetic inputs, `groups.txt`: falls of blood pressure in mmHg, whole
numbers so that many tie. Its lines are a treated group of 25, a control
group of 30, and one group of 20 before and after a treatment. This
script reads them and writes `hypothesis_expected.txt`, all two-sided:

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

from scipy import stats

with open("groups.txt") as data:
    treated, control, before, after = [
        [float(v) for v in line.split()] for line in data if line.strip()
    ]


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
