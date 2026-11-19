# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write tests of count tables by scipy and statsmodels, two Python
libraries.

    python3 make_tables.py > tables_expected.txt

Run it with scipy 1.18.1 and statsmodels 0.15.0. Each line starts with a
name and the table's cells by rows:

- `fisher` with a two-by-two table, its odds ratio and the two-sided p
  value of `fisher_exact`.
- `chi2` with the rows and columns of a table, its cells, then the
  statistic, the degrees of freedom and the p value of `chi2_contingency`
  without the continuity correction.
- `yates` with a two-by-two table, then the statistic and the p value of
  `chi2_contingency` with Yates's correction.
- `mcnemar` with the two discordant counts b and c of paired results, the
  exact p value of statsmodels' `mcnemar`, and the statistic and p value of
  its chi-square form with the continuity correction.
"""

import numpy as np
from scipy import stats
from statsmodels.stats.contingency_tables import mcnemar


def show(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


for table in [
    [[8, 2], [1, 5]],
    [[3, 12], [9, 4]],
    [[20, 15], [12, 33]],
    [[0, 7], [6, 2]],
    [[5, 5], [5, 5]],
    [[120, 380], [90, 410]],
]:
    r = stats.fisher_exact(table)
    show("fisher", list(np.ravel(table)) + [r.statistic, r.pvalue])

for table in [
    [[12, 30, 8], [20, 25, 15], [18, 10, 22]],
    [[30, 70], [45, 55]],
]:
    r = stats.chi2_contingency(table, correction=False)
    t = np.array(table)
    show("chi2", [t.shape[0], t.shape[1]] + list(t.ravel()) + [r.statistic, r.dof, r.pvalue])

for table in [[[30, 70], [45, 55]], [[3, 12], [9, 4]]]:
    r = stats.chi2_contingency(table, correction=True)
    show("yates", list(np.ravel(table)) + [r.statistic, r.pvalue])

for b, c in [(12, 4), (25, 40), (3, 3), (0, 9)]:
    exact = mcnemar([[50, b], [c, 50]], exact=True)
    approx = mcnemar([[50, b], [c, 50]], exact=False, correction=True)
    show("mcnemar", [b, c, exact.pvalue, approx.statistic, approx.pvalue])
