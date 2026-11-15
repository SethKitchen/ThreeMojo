# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the calibration and decision curve of a synthetic risk model.

    python3 make_calibration.py > calibration_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1, scikit-learn 1.9.1, statsmodels
0.15.0 and dcurves 1.1.7. A cohort of 300 synthetic patients has a true
risk of `1 / (1 + exp(-(-1.2 + 1.1 x + 0.8 z)))`, with x normal and z a
coin. A model that was overfitted gives each patient the risk
`1 / (1 + exp(-(-0.9 + 1.5 x + 1.0 z)))`: too high, and too far from the
mean. Each line holds a name and its values:

- `risks` and `outcomes`: the model's risk and the outcome of each
  patient, 1 or 0.
- `brier`: the Brier score from scikit-learn, and the scaled Brier score.
- `groups`: for each of ten groups of risk, its count, mean risk, events
  and observed share. The groups are `numpy.array_split` of the patients
  sorted by risk, so the first groups hold one patient more.
- `hosmer`: the Hosmer-Lemeshow statistic, its degrees of freedom and its
  p value from scipy.
- `slope`: the calibration intercept and slope, and their standard
  errors, from statsmodels' `Logit` of the outcome on the logit of the
  risk.
- `large`: the calibration in the large and its standard error, from
  statsmodels' binomial `GLM` with the logit of the risk as an offset,
  and the expected over the observed events.
- `thresholds`, `model`, `all` and `avoided`: the decision curve of
  dcurves at each threshold: the net benefit of the model and of treating
  all, and the interventions avoided for each patient.
"""

import numpy
import pandas
import scipy.stats
import sklearn.metrics
import statsmodels.api as sm
from dcurves import dca

generator = numpy.random.default_rng(20261115)
n = 300
x = generator.normal(size=n)
z = (generator.random(n) < 0.5).astype(float)
truth = 1.0 / (1.0 + numpy.exp(-(-1.2 + 1.1 * x + 0.8 * z)))
y = (generator.random(n) < truth).astype(int)
risks = 1.0 / (1.0 + numpy.exp(-(-0.9 + 1.5 * x + 1.0 * z)))
logit = numpy.log(risks / (1.0 - risks))


def line(name, values):
    print(name, " ".join(repr(float(v)) for v in values))


line("risks", risks)
line("outcomes", y)
brier = sklearn.metrics.brier_score_loss(y, risks)
share = y.mean()
line("brier", [brier, 1.0 - brier / (share * (1.0 - share))])

statistic = 0.0
for part in numpy.array_split(numpy.argsort(risks, kind="stable"), 10):
    count = len(part)
    expected = risks[part].sum()
    events = y[part].sum()
    line("groups", [count, expected / count, events, events / count])
    statistic += (events - expected) ** 2 / (expected * (1.0 - expected / count))
line("hosmer", [statistic, 8, scipy.stats.chi2.sf(statistic, 8)])

fit = sm.Logit(y, sm.add_constant(logit)).fit(method="newton", tol=1e-14, disp=0)
line("slope", [fit.params[0], fit.params[1], fit.bse[0], fit.bse[1]])
large = sm.GLM(
    y, numpy.ones(n), family=sm.families.Binomial(), offset=logit
).fit(tol=1e-15)
line("large", [large.params[0], large.bse[0], risks.sum() / y.sum()])

thresholds = [k / 100.0 for k in range(2, 96, 3)]
frame = pandas.DataFrame({"y": y, "model": risks})
curve = dca(data=frame, outcome="y", modelnames=["model"], thresholds=thresholds)
model = curve[curve.model == "model"].sort_values("threshold")
everyone = curve[curve.model == "all"].sort_values("threshold")
line("thresholds", model.threshold)
line("model", model.net_benefit)
line("all", everyone.net_benefit)
line("avoided", model.net_intervention_avoided)
