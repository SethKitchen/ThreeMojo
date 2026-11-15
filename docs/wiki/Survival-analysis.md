# Survival analysis

`extensions/clinical/` gives the survival of groups of patients. It makes Kaplan-Meier curves with 95 percent intervals and medians. It compares two groups by the log-rank test, and it plots the curves. It fits Cox models of survival on covariates, such as an age or a treatment. It gives the cumulative hazard and the restricted mean survival time. It gives the cumulative incidence of a cause when another cause can come first.

It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![The Kaplan-Meier curves of 6-MP and of a placebo in acute leukemia, with a tick at each censored patient](out/survival.png)

`examples/survival.mojo` makes this picture. It uses the trial of 6-mercaptopurine (6-MP) against a placebo in 42 children with acute leukemia, of Freireich and others (1963). The blue curve is 6-MP, and the red curve is the placebo. Time runs from 0 to 36 weeks, with a gray line each 6 weeks. The median remission is 23 weeks with 6-MP and 8 weeks with the placebo. The log-rank chi-square is 16.79, and its p value is 4.2e-5.

A Cox model gives the placebo a hazard ratio of 4.82, with a 95 percent interval from 2.15 to 10.81. To 23 weeks, the restricted mean remission is 9.2 weeks longer with 6-MP, with a p value of 8.5e-6. The program prints these values.

## Modules

| Module | What it gives |
|---|---|
| `survival` | `SurvivalCurve`, `kaplan_meier`, `LogRank`, `log_rank_test`, `survival_image`, `require_group`, `DAY64` and `WEEK64` |
| `cox` | `CoxModel`, `cox_regression`, `chi_square_p_value` and `MAX_COVARIATES` |
| `logrank` | `GroupLogRank`, `log_rank_groups` and `MAX_GROUPS` |
| `rmst` | `CumulativeHazard`, `nelson_aalen`, `RestrictedMean`, `restricted_mean`, `RestrictedComparison` and `compare_restricted_means` |
| `competing` | `CumulativeIncidence`, `cumulative_incidence` and `incidence_image` |

## Make a survival curve

A study follows each patient from a start, such as a diagnosis or a treatment, to an event, such as a relapse or a death. A patient who leaves the study before the event is censored at the time last seen. Give each patient a time and a flag. The flag is `True` for an event and `False` for a censored patient.

```mojo
from extensions.clinical.survival import WEEK64, kaplan_meier
from units.si import Duration64

var times: List[Duration64] = [
    Duration64(6, WEEK64), Duration64(7, WEEK64), Duration64(9, WEEK64)
]
var events: List[Bool] = [True, True, False]
var curve = kaplan_meier(times, events)
```

The curve holds one row for each time at which one event or more happened:

- `times` is each time, rising.
- `survival` is the survival just after the time.
- `at_risk` is the patients at risk just before the time. A patient censored at a time is at risk at that time.
- `events` is the events at the time.
- `censored` is the time of each censored patient.

At each time, the survival falls by the factor `1 - d / n`. Here `d` is the events at the time, and `n` is the patients at risk.

`curve.at(time)` gives the survival at any time. It is 1 before the first event.

## Give the interval and the median

`curve.interval(i)` gives the 95 percent interval of the survival at row `i`. It uses the exponential Greenwood formula, which keeps the interval between 0 and 1:

```text
S^exp(+-1.96 sqrt(v)),  v = sum(d / (n (n - d))) / (ln S)^2
```

Once no patient is left, the survival is 0 and both ends of the interval are 0.

`curve.median()` gives a flag and a time. The time is the first time of an event at which the survival is a half or less. When the survival stays above a half, the flag is `False`.

## Compare groups

`log_rank_test(times_a, events_a, times_b, events_b)` asks whether two groups have one survival. At each time of an event in either group, each group expects its share at risk of the events. The statistic is `(O - E)^2 / V` of the first group. It has the chi-square distribution with one degree of freedom when the groups have one survival.

The result gives:

- `statistic`, the chi-square value.
- `p_value`, the chance of a statistic this large when the groups have one survival.
- `observed`, the events of each group.
- `expected`, the events that each group expects.

A time at which one patient alone is at risk adds no variance.

`log_rank_groups(times, events)` compares two groups or more, such as the arms of a trial. It takes the times and the event flags of each group. At each time of an event in any group, each group expects its share at risk of the events. The statistic is `(O - E)' V^-1 (O - E)` over all groups but the last, with V the covariance of the observed events. It has one degree of freedom less than the groups.

The result gives the `statistic`, `freedom`, `p_value`, and the `observed` and `expected` events of each group. With two groups, it is the test of `log_rank_test`.

## Fit a Cox model

A Cox model gives the effect of each covariate on the hazard, with the other covariates held. The hazard of a patient is a baseline hazard times `exp(x . b)`. Here `x` holds the covariates of the patient, and `b` holds one coefficient for each covariate. The baseline is the same for each patient, and the model does not estimate it.

`cox_regression(times, events, covariates, tolerance, max_steps)` takes one row of covariates for each patient. A covariate is a plain number in a unit that you choose, such as an age in decades or 1 for a treatment. A coefficient is per that unit.

```mojo
from extensions.clinical.cox import cox_regression
from extensions.clinical.survival import WEEK64
from units.si import Duration64

var times: List[Duration64] = [
    Duration64(1, WEEK64),
    Duration64(2, WEEK64),
    Duration64(3, WEEK64),
    Duration64(3, WEEK64),
]
var events: List[Bool] = [True, True, False, False]
var treated: List[List[Float64]] = [[1.0], [0.0], [1.0], [0.0]]
var model = cox_regression(times, events, treated, 1e-10, 50)
print(model.hazard_ratio(0), model.interval(0)[0], model.p_value(0))
```

Here the hazard ratio is exactly `sqrt(2)`. See [Verification](#verification).

The fit uses Newton steps on the partial likelihood, from `b = 0`. It uses Efron's method for tied times. When a step loses likelihood, the fit halves the step. The fit stops when no coefficient changes by more than `tolerance`, and then sets `converged`.

When the steps run out first, `converged` is `False`. That occurs when a covariate separates the patients, and a coefficient grows at each step. With more steps, the information matrix of such a fit becomes singular, and the fit raises an error.

The model gives:

- `coefficients` and `standard_errors`. The standard errors come from the inverse of the information matrix.
- `hazard_ratio(i)`, which is `exp(b_i)`: the factor on the hazard for each unit of covariate `i`.
- `interval(i)`, the 95 percent interval of the hazard ratio, `exp(b -+ 1.96 se)`.
- `z(i)` and `p_value(i)`, the Wald test of each coefficient.
- `likelihood_ratio()`, the test of the whole model against a model with no covariate. It has one degree of freedom for each covariate.
- `concordance`, Harrell's C. It is the fraction of comparable pairs in which the patient with the higher risk has the event first. A tie of risk counts a half. 0.5 is no better than chance, and 1 is a perfect order.

`model.survival(row, time)` predicts the survival of a patient. It uses the Breslow baseline hazard of the fitted model. `model.relative_hazard(row)` gives the hazard of a patient relative to a patient with the mean covariates.

`chi_square_p_value(statistic, freedom)` gives the upper tail of the chi-square distribution in closed form.

## Find the cumulative hazard

`nelson_aalen(curve)` gives the Nelson-Aalen cumulative hazard of a group from its Kaplan-Meier curve. At each time of an event, the hazard grows by `d / n`. The `variance` grows by `d (n - d) / n^3`, and `interval(i)` gives the 95 percent interval `H exp(-+ 1.96 sqrt(v) / H)`. These are the values of lifelines without smoothing.

## Find the restricted mean survival time

`restricted_mean(curve, horizon)` gives the restricted mean survival time (RMST): the area under the curve from 0 to the horizon. It is the mean time free of the event over that span. It is in units of time, and it does not need proportional hazards.

```mojo
from extensions.clinical.rmst import restricted_mean

var mean = restricted_mean(curve, Duration64(9, WEEK64))
print(mean.mean.to(WEEK64), mean.interval()[0].to(WEEK64))
```

The standard error is that of Klein and Moeschberger, as R's survRM2 gives. It sums `A_j^2 d_j / (n_j (n_j - d_j))` over the times of events up to the horizon, with `A_j` the area from `t_j` to the horizon. Choose a horizon where both groups still have patients at risk.

`compare_restricted_means(first, second, horizon)` gives the difference of two restricted means, first less second, with its standard error, z, two-sided p value and 95 percent interval.

## Account for competing risks

A patient who dies of another cause can no longer relapse. The Kaplan-Meier curve of relapse, with the deaths censored, takes the dead as if they could still relapse. So `1 - S` overstates the risk of relapse. Use the cumulative incidence of Aalen and Johansen when another cause can come first.

![The cumulative incidence of relapse and of death without relapse, beside one minus the Kaplan-Meier curve of relapse](out/competing.png)

`examples/competing.mojo` makes this picture from 400 synthetic patients. Each has a relapse at a rate of 0.15 a year and a death without relapse at 0.10 a year. The blue steps are the incidence of relapse, and the gray steps that of death without relapse. The red steps are `1 - S`, with the deaths censored. At 5 years, `1 - S` gives 0.58, but the incidence of relapse is only 0.45.

```mojo
from extensions.clinical.competing import cumulative_incidence

var relapse_curve = cumulative_incidence(times, relapse, death)
print(relapse_curve.at(Duration64(5, YEAR64)), relapse_curve.interval(0)[1])
```

`cumulative_incidence(times, events, competing)` takes the time of each patient to the first event or to the censoring. `events` marks the patients whose first event is the cause of interest, and `competing` those whose first event is another cause. A patient has one first event at most. At each time of an event of either cause:

    F(t) = F(t-) + S(t-) d / n

`S` is the Kaplan-Meier survival from every cause, `d` the events of the cause of interest and `n` the patients at risk.

The result gives `times`, `incidence`, `at_risk`, `events` and `competing` at each time of an event of either cause. `variance` is the delta-method variance of Collett, as lifelines gives it. `interval(i)` is symmetric for `log(-log F)`, so it stays between 0 and 1. `at(time)` gives the incidence at any time. With no competing event, the incidence is `1 - S` and its variance is Greenwood's.

Events of both causes at one time count at once. lifelines jitters such ties apart at random instead.

`incidence_image(curves, colors, top, grid, ceiling, width, height)` draws the curves as rising steps. The incidence runs from 0 at the bottom edge to `ceiling` at the top edge.

## Draw the curves

`survival_image(curves, colors, top, grid, width, height)` plots the curves as steps on a white image. Time runs from 0 at the left edge to `top` at the right edge. Survival runs from 0 at the bottom edge to 1 at the top edge. A light gray line marks each `grid` of time and each tenth of survival. A short vertical tick marks each censored patient on its curve.

## Verification

The tests compare the module with lifelines 0.30.3, a Python library, on the trial of Freireich and others. `assets/survival/make_survival.py` writes the expected values.

- At each time of a relapse in each group, the survival agrees to 1e-14. Both ends of the interval agree to 1e-11.
- The medians are 23 and 8 weeks, as lifelines gives.
- The log-rank statistic agrees to a relative 1e-12, and its p value to a relative 1e-11.
- The 6-MP group has 9 relapses, and the placebo group has 21.
- The log-rank test of three synthetic arms with ties agrees with lifelines' `multivariate_logrank_test` to a relative 1e-12, and its p value to 1e-11. With two groups, it is the two-group test.
- The Nelson-Aalen hazard of each group agrees with lifelines to a relative 1e-14, and the ends of its interval to 1e-13.
- The restricted mean to 23 weeks agrees with lifelines' `restricted_mean_survival_time` to 1e-14. Its standard error agrees with the formula in numpy to 1e-13, and the test of the difference to 1e-11.

The tests compare `competing` with the `AalenJohansenFitter` of lifelines on a synthetic cohort of 80 patients with two causes. No two events tie, so lifelines does not jitter them. `assets/competing/make_competing.py` writes them.

- At the 42 times of an event, the incidence of each cause agrees to a relative 1e-14, and its variance to 1e-12.
- The ends of the interval agree to 1e-12. lifelines names its two interval columns the other way round, so the script takes the smaller end as the low end.
- With no competing event, the incidence is `1 - S` of `kaplan_meier` to 1e-14, and its variance is `S^2` times Greenwood's sum to 1e-12.

The tests compare the Cox model with lifelines on a synthetic cohort of 120 patients with three covariates. The cohort has 70 events and 32 tied times. `assets/survival/make_cox.py` makes it.

- The coefficients agree to 1e-12. The standard errors, z values and interval ends agree to a relative 1e-11, and the p values to a relative 1e-10.
- The log partial likelihood and the null log partial likelihood agree to a relative 1e-14. The likelihood ratio statistic agrees to a relative 1e-11.
- The concordance is the same number.
- The predicted survival of three patients at three times agrees to a relative 1e-11.
- On the trial of Freireich and others, the coefficient of the placebo agrees to a relative 1e-12.

lifelines stops its fit when its log-likelihood stops changing, and when its Newton decrement is less than its precision. At its default settings, one step of about 1e-8 is still to take. The script turns off the first test and sets the precision to 1e-20.

The tests also check a small group by hand. Five patients have events at 1, 2, 2 and 4 weeks, and one patient is censored at 3 weeks. The survival is 0.8, then 0.4, then 0. Two identical groups give a statistic of 0 and a p value of 1.

The tests check Cox models by hand:

- Four patients without ties have the score `1 - u/(u + 1) - u/(u + 2)`, with `u = exp(b)`. The fit gives `u = sqrt(2)`, the information `6 sqrt(2) - 8`, the concordance 0.6 and the Breslow survival.
- Two tied events give `u = sqrt(6)` by Efron's method. Breslow's method would give `u = 2`.
- A cohort whose first full step loses likelihood halves the step and converges.
- Three events at one time give no comparable pair, and a coefficient of 0.
- The chi-square tail matches scipy for 3, 4, 200 and 201 degrees of freedom.

The tests check the cumulative hazard and the restricted mean by hand. Three patients have events at 1 and 2 weeks, and one is censored at 3 weeks. To 4 weeks, the area is `1 + 2/3 + 2 x 1/3 = 7/3`, and its variance is `(16/9) / 6 + (4/9) / 2`. A group with no event has a restricted mean of the whole horizon, with no error.

The tests check competing risks by hand. Four patients have a relapse at 1 day, a death at 2, a censoring at 3 and a relapse at 4. The incidence of relapse is 0.25, then 0.25, then 0.75, and that of death is 0.25. Once no patient is left, the two incidences sum to 1. The first variance is `p (1 - p) / n`, or 3/64. A relapse and a death at one time of three patients give each cause an incidence of 1/3.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A group has no patient, or its times and flags differ in number | `kaplan_meier`, `log_rank_test`, `cox_regression` |
| A time is negative or not finite | `kaplan_meier`, `log_rank_test`, `cox_regression` |
| No event changes the risk of either group | `log_rank_test` |
| A row index names no time | `SurvivalCurve.interval`, `CumulativeHazard.interval` |
| There are not 2 to 100 groups, or the events do not change the risk of the groups | `log_rank_groups` |
| The horizon is not positive and finite | `restricted_mean`, `compare_restricted_means` |
| There is no event, the covariates are not one finite row of 1 to 32 values for each patient, the tolerance is not between 0 and 1, or the steps are not from 1 to 1000 | `cox_regression` |
| The information matrix is not positive definite, because a covariate is constant, is collinear with others, or separates the patients | `cox_regression` |
| An index names no covariate, a row does not have one finite value for each covariate, or a time is negative or not finite | `CoxModel` |
| The freedom is not from 1 to 1000, or the statistic is negative or not a number | `chi_square_p_value` |
| The colors are not one for each curve, or there is no curve | `survival_image` |
| A side is out of 64 to 4096 pixels, the top time is not positive and finite, or the grid gives more than 100 lines | `survival_image` |
| The competing events are not one for each patient, or a patient has both first events | `cumulative_incidence` |
| A row index names no time | `CumulativeIncidence.interval` |
| There is no curve, the colors are not one for each, a side is out of 64 to 4096 pixels, a time is out of range, or the ceiling is not above 0 and at most 1 | `incidence_image` |

## Limits

- The log-rank tests have no strata and no weights, such as those of Fleming and Harrington.
- The Cox model takes covariates that do not change in time, one stratum and no weights. It does not test the proportional hazards assumption. Check that assumption before you use a hazard ratio.
- A Cox fit holds the risk sets in one pass over the sorted times, and Harrell's C compares each pair of patients. A cohort of many thousands of patients is slow.
- It takes right censoring only. A patient who enters the study late, or whose event happens between two visits, needs another method.
- The p value is for one test. Many tests on one data set need a correction.
- The cumulative incidence takes independent censoring. The module has no test of Gray to compare incidences, and no Fine-Gray model of the subdistribution hazard.

## References

- Kaplan and Meier, "Nonparametric estimation from incomplete observations", Journal of the American Statistical Association, 1958.
- Greenwood, "The natural duration of cancer", Reports on Public Health and Medical Subjects 33, 1926.
- Mantel, "Evaluation of survival data and two new rank order statistics arising in its consideration", Cancer Chemotherapy Reports, 1966.
- Freireich and others, "The effect of 6-mercaptopurine on the duration of steroid-induced remissions in acute leukemia", Blood, 1963.
- Gehan, "A generalized Wilcoxon test for comparing arbitrarily singly-censored samples", Biometrika, 1965.
- Cox, "Regression models and life-tables", Journal of the Royal Statistical Society, Series B, 1972.
- Efron, "The efficiency of Cox's likelihood function for censored data", Journal of the American Statistical Association, 1977.
- Breslow, "Covariance analysis of censored survival data", Biometrics, 1974.
- Harrell and others, "Evaluating the yield of medical tests", Journal of the American Medical Association, 1982.
- Nelson, "Theory and applications of hazard plotting for censored failure data", Technometrics, 1972.
- Aalen and Johansen, "An empirical transition matrix for non-homogeneous Markov chains based on censored observations", Scandinavian Journal of Statistics, 1978.
- Collett, a textbook on the survival data of medical research, third edition, CRC Press, 2015.
- Putter, Fiocco and Geskus, "Tutorial in biostatistics: competing risks and multi-state models", Statistics in Medicine, 2007.
- Aalen, "Nonparametric inference for a family of counting processes", Annals of Statistics, 1978.
- Royston and Parmar, "Restricted mean survival time: an alternative to the hazard ratio", BMC Medical Research Methodology, 2013.
- Klein and Moeschberger, "Survival Analysis: Techniques for Censored and Truncated Data", 2nd edition, 2003.
- Kalbfleisch and Prentice, "The Statistical Analysis of Failure Time Data", 2nd edition, 2002.
