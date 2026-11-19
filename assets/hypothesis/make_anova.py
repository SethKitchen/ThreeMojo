# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the results of scipy, a Python library, for several groups.

    mojo run -I . tools/make_anova.mojo
    cd assets/hypothesis && python3 make_anova.py

Run it with numpy and scipy 1.18.1. `tools/make_anova.mojo` writes the
synthetic groups, `three_groups.txt`: three lines of falls of LDL
cholesterol in mg/dL, whole numbers so that some tie. This script reads
them and writes `anova_expected.txt`:

- `anova`: F, the two degrees of freedom and the p value of `f_oneway`.
- `kruskal`: H with the tie correction, the degrees of freedom and the
  p value of `kruskal`.
"""

from scipy import stats

with open("three_groups.txt") as data:
    groups = [[float(v) for v in line.split()] for line in data if line.strip()]
f = stats.f_oneway(*groups)
k = stats.kruskal(*groups)
n = sum(len(g) for g in groups)
with open("anova_expected.txt", "w") as out:
    out.write("anova %r %r %r %r\n" % (float(f.statistic), 2.0, float(n - 3), float(f.pvalue)))
    out.write("kruskal %r %r %r\n" % (float(k.statistic), 2.0, float(k.pvalue)))
