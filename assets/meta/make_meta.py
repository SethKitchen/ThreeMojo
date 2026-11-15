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

The effect of each trial is its log risk ratio, with the variance
`1/a - 1/(a + b) + 1/c - 1/(c + d)`. The output has these lines:

- `effects` with the log risk ratio and its variance of each trial.
- `fixed` and `random` with the pooled estimate, its standard error, the
  low and high ends of its 95 percent interval, z and the p value, by
  statsmodels' `combine_effects` with the method of DerSimonian and
  Laird.
- `heterogeneity` with Q, its p value, I^2 and tau^2.
- `weights_fixed` and `weights_random` with the relative weight of each
  trial.
- `prediction` with the 95 percent prediction interval of Higgins and
  others (2009), from the t distribution with k - 2 degrees of freedom.
"""

import numpy as np
from scipy import stats
from statsmodels.stats.meta_analysis import combine_effects

with open("bcg.txt") as source:
    rows = [line.split(",") for line in source.read().splitlines()]
a, b, c, d = (np.array([float(r[i]) for r in rows]) for i in range(1, 5))
effect = np.log((a / (a + b)) / (c / (c + d)))
variance = 1 / a - 1 / (a + b) + 1 / c - 1 / (c + d)
result = combine_effects(effect, variance, method_re="dl")
frame = result.summary_frame()
k = len(effect)


def line(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


line("effects", np.column_stack([effect, variance]).ravel())
for name, row in [("fixed", "fixed effect"), ("random", "random effect")]:
    eff = frame.loc[row, "eff"]
    sd = frame.loc[row, "sd_eff"]
    z = eff / sd
    line(
        name,
        [eff, sd, frame.loc[row, "ci_low"], frame.loc[row, "ci_upp"], z,
         2 * stats.norm.sf(abs(z))],
    )
line(
    "heterogeneity",
    [result.q, stats.chi2.sf(result.q, k - 1), result.i2, result.tau2],
)
line("weights_fixed", result.weights_rel_fe)
line("weights_random", result.weights_rel_re)
t = stats.t.ppf(0.975, k - 2)
half = t * np.sqrt(result.tau2 + frame.loc["random effect", "sd_eff"] ** 2)
mean = frame.loc["random effect", "eff"]
line("prediction", [mean - half, mean + half])
