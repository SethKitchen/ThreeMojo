# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a synthetic cohort and its Cox model by lifelines, a Python library.

    mojo run -I . tools/make_cox.mojo
    cd assets/survival && python3 make_cox.py

Run it with numpy and lifelines 0.30.3. `tools/make_cox.mojo` writes 120
synthetic patients, `cox_cohort.txt`, one to a line: the time in whole
weeks, 1 for an event or 0 for a censored patient, the age in decades, 1
for the treatment or 0 for none, and a marker. This script reads them.

- `cox_expected.txt` holds the Cox model of lifelines with Efron's method
  for ties, fitted far past its default precision.

The times come from an exponential hazard of `exp(0.4 age - 0.7 treatment
+ 0.3 marker)`, and the censoring is uniform. Both round up to whole weeks,
so many times tie, and some events tie with censored patients.

The expected file has these lines:

- `cohort` and the coefficients, their standard errors, z values, p values,
  and the low and high ends of the 95 percent interval of each hazard
  ratio.
- `fit` with the log partial likelihood, the null log partial likelihood,
  the likelihood ratio statistic and its p value, and the concordance.
- `survival` with the predicted survival of three patients at 5, 20 and
  60 weeks, on the step curve of lifelines.
- `freireich` with the coefficient, its standard error and its p value
  for the placebo group of the 6-MP trial against the drug group.
"""

import numpy as np
from lifelines import CoxPHFitter
import pandas as pd

# lifelines stops when its log-likelihood stops changing, or when its
# Newton decrement falls below the precision. Both happen with one step
# of about 1e-8 still to take. A negative r_precision turns the first test
# off, and a precision of 1e-20 lets that last step go.
OPTIONS = {"precision": 1e-20, "r_precision": -1.0, "max_steps": 500}

with open("cox_cohort.txt") as data:
    rows = np.array([[float(v) for v in line.split()] for line in data if line.strip()])
time, event, age, treated, marker = rows.T
event = event.astype(int)
treated = treated.astype(int)

frame = pd.DataFrame(
    {"T": time, "E": event, "age": age, "treated": treated, "marker": marker}
)
cph = CoxPHFitter().fit(frame, "T", "E", fit_options=OPTIONS)
s = cph.summary
lines = []
values = []
for name in ["age", "treated", "marker"]:
    values += [
        s.loc[name, "coef"],
        s.loc[name, "se(coef)"],
        s.loc[name, "z"],
        s.loc[name, "p"],
        s.loc[name, "exp(coef) lower 95%"],
        s.loc[name, "exp(coef) upper 95%"],
    ]
lines.append("cohort " + " ".join(repr(float(v)) for v in values))
test = cph.log_likelihood_ratio_test()
lines.append(
    "fit %r %r %r %r %r"
    % (
        float(cph.log_likelihood_),
        float(cph._ll_null_),
        float(test.test_statistic),
        float(test.p_value),
        float(cph.concordance_index_),
    )
)
rows = pd.DataFrame(
    {"age": [5.0, 6.5, 8.0], "treated": [1, 0, 0], "marker": [0.5, 1.0, 2.0]}
)
# With `times`, lifelines interpolates between the times of events. The
# survival of the Breslow baseline is a step function, so take lifelines'
# curve at the last time of an event at or before each time.
curves = cph.predict_survival_function(rows)
steps = [curves[curves.index <= at].iloc[-1] for at in (5.0, 20.0, 60.0)]
lines.append(
    "survival "
    + " ".join(repr(float(steps[t].iloc[r])) for r in range(3) for t in range(3))
)

drug = "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
placebo = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"
rows = []
for group, text in [(0, drug), (1, placebo)]:
    for word in text.split():
        rows.append((float(word.rstrip("+")), int(not word.endswith("+")), group))
trial = pd.DataFrame(rows, columns=["T", "E", "placebo"])
fit = CoxPHFitter().fit(trial, "T", "E", fit_options=OPTIONS)
f = fit.summary
lines.append(
    "freireich %r %r %r"
    % (
        float(f.loc["placebo", "coef"]),
        float(f.loc["placebo", "se(coef)"]),
        float(f.loc["placebo", "p"]),
    )
)
with open("cox_expected.txt", "w") as out:
    out.write("\n".join(lines) + "\n")
