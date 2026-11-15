# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write gamma tails and quantiles, exact Poisson intervals and
standardized ratios, with scipy and statsmodels.

    python3 make_standardize.py > standardize_expected.txt

Run it with scipy 1.18.1 and statsmodels 0.15.0. The lines are:

- `tails a x P Q`: scipy's `gammainc` and `gammaincc`.
- `quantile a p x`: scipy's `gamma.ppf`.
- `poisson k low high`: the exact central 95 percent interval of a count,
  from statsmodels' `confint_poisson` with `exact-c` and an exposure of 1.
- `ratio observed expected low high p`: the interval of a standardized
  ratio from `confint_poisson` with the expected count as exposure, and
  its p value from `test_poisson` with `exact-c`.

The test checks the directly standardized rate of Fay and Feuer (1997)
by its closed form, on the gamma points of these lines.
"""

import scipy.special
import scipy.stats
from statsmodels.stats.rates import confint_poisson, test_poisson


def words(values):
    return " ".join(repr(float(v)) for v in values)


for a in (0.1, 0.5, 1.0, 2.5, 10.0, 37.0, 1000.0, 1e5):
    for scale in (0.01, 0.5, 1.0, 1.5, 4.0):
        x = a * scale
        print("tails", words([a, x, scipy.special.gammainc(a, x), scipy.special.gammaincc(a, x)]))
    for p in (1e-10, 0.025, 0.5, 0.975, 1 - 1e-10):
        print("quantile", words([a, p, scipy.stats.gamma.ppf(p, a)]))

for k in (0, 1, 2, 7, 30, 250):
    low, high = confint_poisson(k, 1.0, method="exact-c")
    print("poisson", words([k, low, high]))

for observed, expected in ((0, 2.5), (3, 1.2), (7, 3.2), (40, 52.7), (210, 180.4)):
    low, high = confint_poisson(observed, expected, method="exact-c")
    p = test_poisson(observed, expected, 1.0, method="exact-c").pvalue
    print("ratio", words([observed, expected, low, high, p]))

