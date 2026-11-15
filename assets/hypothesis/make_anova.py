# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write tests of several groups by scipy, a Python library.

    python3 make_anova.py

Run it with numpy and scipy 1.18.1. It writes two files:

- `three_groups.txt` holds three lines of synthetic falls of LDL
  cholesterol in mg/dL, whole numbers so that some tie, of 18, 22 and 20
  patients on three doses.
- `anova_expected.txt` holds the results:

  - `anova`: F, the two degrees of freedom and the p value of
    `f_oneway`.
  - `kruskal`: H with the tie correction, the degrees of freedom and the
    p value of `kruskal`.
"""

import numpy as np
from scipy import stats

rng = np.random.default_rng(20261115)
groups = [
    np.round(rng.normal(20.0, 8.0, 18)),
    np.round(rng.normal(26.0, 8.0, 22)),
    np.round(rng.normal(31.0, 9.0, 20)),
]
with open("three_groups.txt", "w") as out:
    for g in groups:
        out.write(" ".join("%d" % v for v in g) + "\n")
f = stats.f_oneway(*groups)
k = stats.kruskal(*groups)
n = sum(len(g) for g in groups)
with open("anova_expected.txt", "w") as out:
    out.write("anova %r %r %r %r\n" % (float(f.statistic), 2.0, float(n - 3), float(f.pvalue)))
    out.write("kruskal %r %r %r\n" % (float(k.statistic), 2.0, float(k.pvalue)))
