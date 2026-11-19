# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write proportion intervals and two-by-two table measures by statsmodels,
a Python library.

    python3 make_proportions.py > proportions_expected.txt

Run it with numpy and statsmodels 0.15.0. All intervals are 95 percent.
The output has these lines:

- `proportion` with, for each case, the successes, the trials, the Wilson
  interval and the Clopper-Pearson interval of `proportion_confint`.
- `diagnostic` with a test of 90 true positives, 30 false positives, 10
  false negatives and 170 true negatives: the sensitivity, specificity,
  positive and negative predictive values, accuracy and prevalence, each
  with its Clopper-Pearson interval; then the positive and negative
  likelihood ratios, each with the log interval of `Table2x2`.
- `risk` with 30 events of 100 against 15 of 100: the risk difference with
  the Wald interval of `confint_proportions_2indep`, the risk ratio and
  the odds ratio with the intervals of `Table2x2`.
"""

import numpy as np
from statsmodels.stats.contingency_tables import Table2x2
from statsmodels.stats.proportion import (
    confint_proportions_2indep,
    proportion_confint,
)


def line(name, values):
    print(name + " " + " ".join(repr(float(v)) for v in values))


values = []
for x, n in [(45, 50), (0, 20), (20, 20), (3, 7), (512, 1000), (1, 1)]:
    values += [x, n]
    values += list(proportion_confint(x, n, method="wilson"))
    values += list(proportion_confint(x, n, method="beta"))
line("proportion", values)

tp, fp, fn, tn = 90, 30, 10, 170
values = []
for x, n in [
    (tp, tp + fn),
    (tn, tn + fp),
    (tp, tp + fp),
    (tn, tn + fn),
    (tp + tn, tp + fp + fn + tn),
    (tp + fn, tp + fp + fn + tn),
]:
    values += [x / n] + list(proportion_confint(x, n, method="beta"))
positive = Table2x2(np.array([[tp, fn], [fp, tn]]))
negative = Table2x2(np.array([[fn, tp], [tn, fp]]))
values += [positive.riskratio] + list(positive.riskratio_confint())
values += [negative.riskratio] + list(negative.riskratio_confint())
line("diagnostic", values)

table = Table2x2(np.array([[30, 70], [15, 85]]))
low, high = confint_proportions_2indep(30, 100, 15, 100, method="wald", compare="diff")
line(
    "risk",
    [0.30 - 0.15, low, high, table.riskratio]
    + list(table.riskratio_confint())
    + [table.oddsratio]
    + list(table.oddsratio_confint()),
)
