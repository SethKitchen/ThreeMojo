# Survival analysis

`extensions/clinical/` gives the survival of groups of patients. It makes Kaplan-Meier curves with 95 percent intervals and medians. It compares two groups by the log-rank test, and it plots the curves. It fits Cox models of survival on covariates, such as an age or a treatment. It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![The Kaplan-Meier curves of 6-MP and of a placebo in acute leukemia, with a tick at each censored patient](out/survival.png)

`examples/survival.mojo` makes this picture. It uses the trial of 6-mercaptopurine (6-MP) against a placebo in 42 children with acute leukemia, of Freireich and others (1963). The blue curve is 6-MP, and the red curve is the placebo. Time runs from 0 to 36 weeks, with a gray line each 6 weeks. The median remission is 23 weeks with 6-MP and 8 weeks with the placebo. The log-rank chi-square is 16.79, and its p value is 4.2e-5.

A Cox model gives the placebo a hazard ratio of 4.82, with a 95 percent interval from 2.15 to 10.81. The program prints these values.

## Modules

| Module | What it gives |
|---|---|
| `survival` | `SurvivalCurve`, `kaplan_meier`, `LogRank`, `log_rank_test`, `survival_image`, `require_group`, `DAY64` and `WEEK64` |
| `cox` | `CoxModel`, `cox_regression`, `chi_square_p_value` and `MAX_COVARIATES` |

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

## Compare two groups

`log_rank_test(times_a, events_a, times_b, events_b)` asks whether two groups have one survival. At each time of an event in either group, each group expects its share at risk of the events. The statistic is `(O - E)^2 / V` of the first group. It has the chi-square distribution with one degree of freedom when the groups have one survival.

The result gives:

- `statistic`, the chi-square value.
- `p_value`, the chance of a statistic this large when the groups have one survival.
- `observed`, the events of each group.
- `expected`, the events that each group expects.

A time at which one patient alone is at risk adds no variance.

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

## Draw the curves

`survival_image(curves, colors, top, grid, width, height)` plots the curves as steps on a white image. Time runs from 0 at the left edge to `top` at the right edge. Survival runs from 0 at the bottom edge to 1 at the top edge. A light gray line marks each `grid` of time and each tenth of survival. A short vertical tick marks each censored patient on its curve.

## Verification

The tests compare the module with lifelines 0.30.3, a Python library, on the trial of Freireich and others. `assets/survival/make_survival.py` writes the expected values.

- At each time of a relapse in each group, the survival agrees to 1e-14. Both ends of the interval agree to 1e-11.
- The medians are 23 and 8 weeks, as lifelines gives.
- The log-rank statistic agrees to a relative 1e-12, and its p value to a relative 1e-11.
- The 6-MP group has 9 relapses, and the placebo group has 21.

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

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A group has no patient, or its times and flags differ in number | `kaplan_meier`, `log_rank_test`, `cox_regression` |
| A time is negative or not finite | `kaplan_meier`, `log_rank_test`, `cox_regression` |
| No event changes the risk of either group | `log_rank_test` |
| A row index names no time | `SurvivalCurve.interval` |
| There is no event, the covariates are not one finite row of 1 to 32 values for each patient, the tolerance is not between 0 and 1, or the steps are not from 1 to 1000 | `cox_regression` |
| The information matrix is not positive definite, because a covariate is constant, is collinear with others, or separates the patients | `cox_regression` |
| An index names no covariate, a row does not have one finite value for each covariate, or a time is negative or not finite | `CoxModel` |
| The freedom is not from 1 to 1000, or the statistic is negative or not a number | `chi_square_p_value` |
| The colors are not one for each curve, or there is no curve | `survival_image` |
| A side is out of 64 to 4096 pixels, the top time is not positive and finite, or the grid gives more than 100 lines | `survival_image` |

## Limits

- The log-rank test compares two groups only. It has no stratified test, no weighted test and no test of more than two groups.
- The Cox model takes covariates that do not change in time, one stratum and no weights. It does not test the proportional hazards assumption. Check that assumption before you use a hazard ratio.
- A Cox fit holds the risk sets in one pass over the sorted times, and Harrell's C compares each pair of patients. A cohort of many thousands of patients is slow.
- It takes right censoring only. A patient who enters the study late, or whose event happens between two visits, needs another method.
- The p value is for one test. Many tests on one data set need a correction.

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
- Kalbfleisch and Prentice, "The Statistical Analysis of Failure Time Data", 2nd edition, 2002.
