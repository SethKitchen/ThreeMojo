# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the Mantel-Haenszel measures of stratified two-by-two tables.

    python3 make_strata.py > strata_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and statsmodels 0.15.0. The tables
are a synthetic cohort in four age groups. Each `table` line holds a, b,
c and d: the exposed patients with and without the disease, then the
unexposed patients with and without it. Older patients are more often
exposed and more often ill, so age confounds the crude ratios.

- `odds`: the pooled odds ratio, the standard error of its log by Robins,
  Breslow and Greenland, and its interval, from statsmodels'
  `StratifiedTable`.
- `risk`: the pooled risk ratio from statsmodels, the standard error of
  its log by Greenland and Robins (1985) in numpy, and its interval.
- `cmh`: the Cochran-Mantel-Haenszel statistic and its p value, without
  and with the continuity correction. The p values are scipy's `chi2.sf`,
  because statsmodels takes `1 - cdf`.
- `breslow`: the Breslow-Day statistic and its p value, and the same with
  Tarone's adjustment.
- `crude`: the odds ratio and the risk ratio of the summed table.
- `odd`: two strata whose pooled odds ratio is small and whose first
  stratum has more exposed patients and cases than patients, then their
  Breslow-Day statistic and Tarone's. There, the expected cell takes the
  other form of the root.
"""

import numpy
import scipy.stats
from statsmodels.stats.contingency_tables import StratifiedTable

tables = numpy.array(
    [
        [12, 188, 30, 770],
        [35, 265, 42, 558],
        [60, 340, 38, 362],
        [96, 304, 30, 170],
    ],
    dtype=float,
)


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


for row in tables:
    line("table", row)
stack = numpy.stack([t.reshape(2, 2) for t in tables], axis=2)
result = StratifiedTable(stack)
low, high = result.oddsratio_pooled_confint()
line("odds", [result.oddsratio_pooled, result.logodds_pooled_se, low, high])

a, b, c, d = tables.T
n = a + b + c + d
exposed = a + b
unexposed = c + d
cases = a + c
top = numpy.sum((exposed * unexposed * cases - a * c * n) / n**2)
bottom = numpy.sum(a * unexposed / n) * numpy.sum(c * exposed / n)
se = numpy.sqrt(top / bottom)
rr = result.riskratio_pooled
z = scipy.stats.norm.ppf(0.975)
line("risk", [rr, se, rr * numpy.exp(-z * se), rr * numpy.exp(z * se)])

plain = result.test_null_odds(correction=False).statistic
corrected = result.test_null_odds(correction=True).statistic
line(
    "cmh",
    [plain, scipy.stats.chi2.sf(plain, 1), corrected, scipy.stats.chi2.sf(corrected, 1)],
)
day = result.test_equal_odds(adjust=False).statistic
tarone = result.test_equal_odds(adjust=True).statistic
k = len(tables) - 1
line("breslow", [day, scipy.stats.chi2.sf(day, k), tarone, scipy.stats.chi2.sf(tarone, k)])
A, B, C, D = tables.sum(axis=0)
line("crude", [A * D / (B * C), (A / (A + B)) / (C / (C + D))])

odd = numpy.array([[20, 2, 1, 1], [1, 30, 30, 1]], dtype=float)
pair = StratifiedTable(numpy.stack([t.reshape(2, 2) for t in odd], axis=2))
line(
    "odd",
    list(odd.ravel())
    + [
        pair.test_equal_odds(adjust=False).statistic,
        pair.test_equal_odds(adjust=True).statistic,
    ],
)
