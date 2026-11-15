# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the meta-analysis of the BCG vaccine trials by statsmodels and
scipy, two Python libraries.

    python3 make_meta.py > meta_expected.txt

Run it with numpy, scipy 1.18.1 and statsmodels 0.15.0.

`bcg.txt` holds the 13 trials of the BCG vaccine against tuberculosis of
Colditz and others (1994), one to a line: the trial, then the vaccinated
patients with and without tuberculosis, and the others with and without
it. They are the data `dat.bcg` of the R package metafor.

The effect of each trial is its log risk ratio, by statsmodels'
`effectsize_2proportions`. The output has these lines:

- `effects` with the log risk ratio and its variance of each trial.
- `fixed` and `random` with the pooled estimate, its standard error, the
  low and high ends of its 95 percent interval and the two-sided p value
  of the normal distribution, by statsmodels' `combine_effects` with the
  method of DerSimonian and Laird.
- `heterogeneity` with Q and its p value by statsmodels'
  `test_homogeneity`, then I^2 and tau^2.
- `weights_fixed` and `weights_random` with the relative weight of each
  trial.
- `t` with the 97.5 percent point of the t distribution with k - 2 degrees
  of freedom, by scipy. The test builds the prediction interval of Higgins
  and others (2009) from it.
"""

import numpy as np
from scipy import stats
from statsmodels.stats.meta_analysis import (
    combine_effects,
    effectsize_2proportions,
)

with open("bcg.txt") as source:
    rows = [line.split(",") for line in source.read().splitlines()]
a, b, c, d = (np.array([float(r[i]) for r in rows]) for i in range(1, 5))
effect, variance = effectsize_2proportions(
    a, a + b, c, c + d, statistic="risk-ratio"
)
result = combine_effects(effect, variance, method_re="dl")
frame = result.summary_frame()
homogeneity = result.test_homogeneity()


def line(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


line("effects", np.column_stack([effect, variance]).ravel())
for name, row in [("fixed", "fixed effect"), ("random", "random effect")]:
    eff = frame.loc[row, "eff"]
    sd = frame.loc[row, "sd_eff"]
    line(
        name,
        [eff, sd, frame.loc[row, "ci_low"], frame.loc[row, "ci_upp"],
         2 * stats.norm.sf(abs(eff) / sd)],
    )
line(
    "heterogeneity",
    [homogeneity.statistic, homogeneity.pvalue, result.i2, result.tau2],
)
line("weights_fixed", result.weights_rel_fe)
line("weights_random", result.weights_rel_re)
line("t", [stats.t.ppf(0.975, homogeneity.df - 1)])
