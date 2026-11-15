# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write Egger's test of the BCG vaccine trials by statsmodels, a Python
library.

    python3 make_egger.py > egger_expected.txt

Run it with numpy and statsmodels 0.15.0, on the trials of `bcg.txt` and
the log risk ratios of statsmodels' `effectsize_2proportions`. Egger's test regresses each
standardized effect, the effect over its standard error, on its precision,
one over the standard error, by `OLS`. The output line `egger` has the
intercept, its standard error, t and the two-sided p value on `k - 2`
degrees of freedom, then the slope.
"""

import numpy as np
import statsmodels.api as sm
from statsmodels.stats.meta_analysis import effectsize_2proportions

with open("bcg.txt") as source:
    rows = [line.split(",") for line in source.read().splitlines()]
a, b, c, d = (np.array([float(r[i]) for r in rows]) for i in range(1, 5))
effect, variance = effectsize_2proportions(
    a, a + b, c, c + d, statistic="risk-ratio"
)
se = np.sqrt(variance)
fit = sm.OLS(effect / se, sm.add_constant(1 / se)).fit()
print(
    "egger %r %r %r %r %r"
    % (float(fit.params[0]), float(fit.bse[0]), float(fit.tvalues[0]),
       float(fit.pvalues[0]), float(fit.params[1]))
)
