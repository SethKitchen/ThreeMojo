# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write correlations by scipy, a Python library.

    python3 make_correlation.py

Run it with numpy and scipy 1.18.1. It writes two files:

- `pairs.txt` holds two lines of 30 synthetic values each: a fasting
  glucose in mmol/L to 0.1, and an HbA1c in percent to 0.1, so that some
  tie.
- `correlation_expected.txt` holds the results:

  - `pearson`: r, the two-sided p value, and the 95 percent interval of
    `pearsonr` by Fisher's z.
  - `spearman`: rho and the p value of `spearmanr`.
  - `kendall`: tau-b and the p value of `kendalltau` by the normal
    approximation.
"""

import numpy as np
from scipy import stats

rng = np.random.default_rng(20261115)
glucose = np.round(rng.normal(6.5, 1.2, 30), 1)
hba1c = np.round(4.0 + 0.4 * glucose + rng.normal(0.0, 0.35, 30), 1)
with open("pairs.txt", "w") as out:
    out.write(" ".join("%.1f" % v for v in glucose) + "\n")
    out.write(" ".join("%.1f" % v for v in hba1c) + "\n")

p = stats.pearsonr(glucose, hba1c)
ci = p.confidence_interval(0.95)
s = stats.spearmanr(glucose, hba1c)
k = stats.kendalltau(glucose, hba1c, method="asymptotic")
lines = [
    "pearson %r %r %r %r" % (float(p.statistic), float(p.pvalue), float(ci.low), float(ci.high)),
    "spearman %r %r" % (float(s.statistic), float(s.pvalue)),
    "kendall %r %r" % (float(k.statistic), float(k.pvalue)),
]
with open("correlation_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
