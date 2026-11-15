# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clinical research: survival, diagnostic tests, evidence and epidemics.

- `survival`: Kaplan-Meier curves with their intervals, medians, the
  log-rank test of two groups, and a picture of the curves.
- `cox`: Cox proportional hazards regression.
- `rmst`: the Nelson-Aalen hazard and the restricted mean survival time.
- `roc`: ROC curves of diagnostic tests, their AUC and DeLong's test.
- `agreement`: Bland-Altman agreement and intraclass correlations.
- `logistic`: logistic regression with odds ratios.
- `proportions`: proportion intervals and two-by-two tables.
- `meta`: meta-analysis of studies, with forest plots.
- `epidemic`: SIR and SEIR models of an epidemic.
- `power`: the sample size and the power of a study.
- `distributions`: the t and F distributions.

See the wiki pages Survival analysis, Diagnostic tests, Meta-analysis,
Epidemic models, and Sample size and power.
"""
