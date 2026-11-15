# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write sample sizes and powers by scipy, statsmodels and lifelines,
three Python libraries.

    python3 make_power.py > power_expected.txt

Run it with scipy 1.18.1, statsmodels 0.15.0 and lifelines 0.30.3. The
output has these lines:

- `normal` with each probability and its normal quantile, `norm.ppf`.
  The test builds the events of Schoenfeld (1983) from these quantiles.
- `proportions` with, for each case, p1, p2, alpha, power, the ratio, the
  size of `samplesize_proportions_2indep_onetail`, a size n1 and the power
  of `power_proportions_2indep` at it.
- `means` with, for each case, the difference, the deviation, alpha,
  power, the ratio, the size of `normal_sample_size_one_tail`, a size n1
  and the power of `NormalIndPower` at it.
- `freedman` with, for each case, the hazard ratio, alpha, power, the
  ratio, the two chances of an event, the two sizes of lifelines'
  `sample_size_necessary_under_cph`, which rounds up, and the power of
  `power_under_cph` at those sizes.
"""

import numpy as np
from lifelines.statistics import power_under_cph, sample_size_necessary_under_cph
from scipy import stats
from statsmodels.stats.power import NormalIndPower, normal_sample_size_one_tail
from statsmodels.stats.proportion import (
    power_proportions_2indep,
    samplesize_proportions_2indep_onetail,
)


def line(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


values = []
for p in [1e-300, 1e-10, 0.001, 0.02, 0.025, 0.1, 0.3, 0.5, 0.7, 0.8, 0.9, 0.975, 0.995, 0.999999]:
    values += [p, stats.norm.ppf(p)]
line("normal", values)

values = []
for p1, p2, alpha, power, ratio, n1 in [
    (0.3, 0.15, 0.05, 0.8, 1.0, 120.0),
    (0.5, 0.6, 0.01, 0.9, 2.0, 300.0),
]:
    size = samplesize_proportions_2indep_onetail(
        p1 - p2, p2, power, ratio=ratio, alpha=alpha, alternative="two-sided"
    )
    reached = power_proportions_2indep(
        p1 - p2, p2, n1, ratio=ratio, alpha=alpha, return_results=False
    )
    values += [p1, p2, alpha, power, ratio, size, n1, reached]
line("proportions", values)

values = []
for d, sd, alpha, power, ratio, n1 in [
    (5.0, 12.0, 0.05, 0.8, 1.0, 80.0),
    (-0.4, 1.1, 0.01, 0.95, 0.5, 150.0),
]:
    size = normal_sample_size_one_tail(
        d, power, alpha / 2, std_null=sd * np.sqrt(1 + 1 / ratio)
    )
    reached = NormalIndPower().power(d / sd, n1, alpha, ratio=ratio)
    values += [d, sd, alpha, power, ratio, size, n1, reached]
line("means", values)

values = []
for hr, alpha, power, ratio, pe, pc in [
    (0.7, 0.05, 0.8, 1.0, 0.25, 0.35),
    (1.4, 0.01, 0.9, 2.0, 0.5, 0.4),
]:
    n_exp, n_con = sample_size_necessary_under_cph(power, ratio, pe, pc, hr, alpha)
    reached = power_under_cph(n_exp, n_con, pe, pc, hr, alpha)
    values += [hr, alpha, power, ratio, pe, pc, n_exp, n_con, reached]
line("freedman", values)
