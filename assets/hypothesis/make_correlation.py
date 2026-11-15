# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write correlations by scipy, a Python library.

    mojo run -I . tools/make_correlation.mojo
    cd assets/hypothesis && python3 make_correlation.py

Run it with scipy 1.18.1. `tools/make_correlation.mojo` writes the
synthetic inputs, `pairs.txt`: two lines of 30 values, a fasting glucose
in mmol/L to 0.1 and an HbA1c in percent to 0.1, so that some tie. This
script reads them and writes `correlation_expected.txt`:

  - `pearson`: r, the two-sided p value, and the 95 percent interval of
    `pearsonr` by Fisher's z.
  - `spearman`: rho and the p value of `spearmanr`.
  - `kendall`: tau-b and the p value of `kendalltau` by the normal
    approximation.
"""

from scipy import stats

with open("pairs.txt") as data:
    glucose, hba1c = [[float(v) for v in line.split()] for line in data if line.strip()]

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
