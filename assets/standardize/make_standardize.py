# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write gamma tails and quantiles, exact Poisson intervals, standardized
ratios and directly standardized rates, with scipy and statsmodels.

    python3 make_standardize.py > standardize_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and statsmodels 0.15.0. The lines
are:

- `tails a x P Q`: scipy's `gammainc` and `gammaincc`.
- `quantile a p x`: scipy's `gamma.ppf`.
- `poisson k low high`: the exact central 95 percent interval of a count,
  from statsmodels' `confint_poisson` with `exact-c` and an exposure of 1.
- `ratio observed expected ratio low high p`: a standardized ratio, its
  interval from `confint_poisson` with the expected count as exposure, and
  its p value from `test_poisson` with `exact-c`.
- `direct` lines: a synthetic cohort of six age groups, with the events,
  the person-years and the share of each group in a standard population.
  The rate and its interval of Fay and Feuer (1997) come from scipy's
  `gamma.ppf`, in events for each person-year. The standard population is
  synthetic.
"""

import numpy
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
    print("ratio", words([observed, expected, observed / expected, low, high, p]))

# Six age groups: events, person-years and standard shares.
events = numpy.array([2, 5, 11, 24, 41, 63])
years = numpy.array([12000.0, 10500.0, 8200.0, 6100.0, 3900.0, 1800.0])
shares = numpy.array([0.28, 0.22, 0.19, 0.15, 0.10, 0.06])
for at in range(6):
    print("group", words([events[at], years[at], shares[at]]))
y = shares / years
rate = numpy.sum(y * events)
var = numpy.sum(y * y * events)
top = y.max()
low = var / (2 * rate) * scipy.stats.chi2.ppf(0.025, 2 * rate**2 / var)
high = (var + top**2) / (2 * (rate + top)) * scipy.stats.chi2.ppf(0.975, 2 * (rate + top) ** 2 / (var + top**2))
print("direct", words([rate, low, high]))
# With no event: the rate is 0, the low end 0, the high end from one top.
print("empty", words([0.0, 0.0, top * scipy.stats.gamma.ppf(0.975, 1.0)]))
