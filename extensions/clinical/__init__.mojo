# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clinical research: survival, diagnostic tests, evidence and epidemics.

- `survival`: Kaplan-Meier curves with their intervals, medians, the
  log-rank test of two groups, and a picture of the curves.
- `cox`: Cox proportional hazards regression.
- `logrank`: the log-rank test of two groups or more.
- `rmst`: the Nelson-Aalen hazard and the restricted mean survival time.
- `competing`: the cumulative incidence of competing causes.
- `nnt`: the difference of two survival curves at a time, and its NNT.
- `parametric`: exponential and Weibull models of censored times.
- `roc`: ROC curves of diagnostic tests, their AUC and DeLong's test.
- `agreement`: Bland-Altman agreement and intraclass correlations.
- `kappa`: Cohen's kappa, simple and weighted, and Fleiss' kappa.
- `logistic`: logistic regression with odds ratios.
- `rates`: Poisson regression of event rates over person-time.
- `negbin`: negative binomial regression of overdispersed event rates.
- `calibration`: the calibration and the decision curve of a risk model.
- `proportions`: proportion intervals and two-by-two tables.
- `meta`: meta-analysis of studies, with forest plots.
- `epidemic`: SIR and SEIR models of an epidemic.
- `incidence`: the growth rate of case counts and its reproduction number.
- `power`: the sample size and the power of a study.
- `hypothesis`: t tests and rank tests of two groups and of pairs.
- `tables`: Fisher's exact test, chi-square tests and McNemar's test.
- `strata`: Mantel-Haenszel pooling of two-by-two tables over strata.
- `propensity`: inverse probability weights, covariate balance and E-values.
- `multiple`: adjusted p values for many tests.
- `correlation`: Pearson's, Spearman's and Kendall's correlations.
- `anova`: one-way analysis of variance and the Kruskal-Wallis test.
- `regression`: linear regression by least squares.
- `distributions`: the t and F distributions.

See the wiki pages Survival analysis, Diagnostic tests, Meta-analysis,
Epidemic models, Sample size and power, Group comparisons, and
Observational studies.
"""
