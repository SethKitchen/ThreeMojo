# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the calibration and decision curve of a synthetic risk model.

    mojo run -I . tools/make_calibration.mojo
    cd assets/calibration && python3 make_calibration.py > calibration_expected.txt

Run it with numpy 2.5.4, pandas, scikit-learn 1.9.1, statsmodels 0.15.0
and dcurves 1.1.7. `tools/make_calibration.mojo` writes 300 synthetic
patients, `patients.txt`: the risk of an overfitted model and the
outcome, 1 or 0. This script reads them. Each line holds a name and its
values:

- `risks` and `outcomes`: the model's risk and the outcome of each
  patient, 1 or 0.
- `brier`: the Brier score from scikit-learn.
- `slope`: the calibration intercept and slope, and their standard
  errors, from statsmodels' `Logit` of the outcome on the logit of the
  risk.
- `large`: the calibration in the large and its standard error, from
  statsmodels' binomial `GLM` with the logit of the risk as an offset.
- `thresholds`, `model`, `all` and `avoided`: the decision curve of
  dcurves at each threshold: the net benefit of the model and of treating
  all, and the interventions avoided for each patient.

The risk groups, the Hosmer-Lemeshow test, the scaled Brier score and
the expected over the observed events have no reference library. The
Mojo tests check them on cases worked by hand.
"""

import numpy
import pandas
import scipy.special
import sklearn.metrics
import statsmodels.api as sm
from dcurves import dca

with open("patients.txt") as data:
    rows = numpy.array([[float(v) for v in line.split()] for line in data if line.strip()])
risks = rows[:, 0]
y = rows[:, 1].astype(int)
n = len(y)
logit = scipy.special.logit(risks)


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


line("risks", risks)
line("outcomes", y)
line("brier", [sklearn.metrics.brier_score_loss(y, risks)])

fit = sm.Logit(y, sm.add_constant(logit)).fit(method="newton", tol=1e-14, disp=0)
line("slope", [fit.params[0], fit.params[1], fit.bse[0], fit.bse[1]])
large = sm.GLM(
    y, numpy.ones(n), family=sm.families.Binomial(), offset=logit
).fit(tol=1e-15)
line("large", [large.params[0], large.bse[0]])

thresholds = [k / 100.0 for k in range(2, 96, 3)]
frame = pandas.DataFrame({"y": y, "model": risks})
curve = dca(data=frame, outcome="y", modelnames=["model"], thresholds=thresholds)
model = curve[curve.model == "model"].sort_values("threshold")
everyone = curve[curve.model == "all"].sort_values("threshold")
line("thresholds", model.threshold)
line("model", model.net_benefit)
line("all", everyone.net_benefit)
line("avoided", model.net_intervention_avoided)
