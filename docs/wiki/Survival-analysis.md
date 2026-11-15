# Survival analysis

`extensions/clinical/` gives the survival of groups of patients. It makes Kaplan-Meier curves with 95 percent intervals and medians, and it plots them. It compares groups by the log-rank test, and it fits Cox models of survival on covariates, such as an age or a treatment. It gives the cumulative hazard, the restricted mean survival time and the cumulative incidence of competing causes. It fits exponential and Weibull models, which carry a curve past the last follow-up.

It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![The Kaplan-Meier curves of 6-MP and of a placebo in acute leukemia, with a tick at each censored patient](out/survival.png)

`examples/survival.mojo` makes this picture. It uses the trial of 6-mercaptopurine (6-MP) against a placebo in 42 children with acute leukemia, of Freireich and others (1963). The blue curve is 6-MP, and the red curve is the placebo. Time runs from 0 to 36 weeks, with a gray line each 6 weeks. The median remission is 23 weeks with 6-MP and 8 weeks with the placebo. The log-rank chi-square is 16.79, and its p value is 4.2e-5.

A Cox model gives the placebo a hazard ratio of 4.82, with a 95 percent interval from 2.15 to 10.81. To 23 weeks, the restricted mean remission is 9.2 weeks longer with 6-MP, with a p value of 8.5e-6. The program prints these values.

## Modules

| Module | What it gives |
|---|---|
| `survival` | `SurvivalCurve`, `kaplan_meier`, `survival_image` and `require_group` |
| `cox` | `CoxModel`, `cox_regression` and `MAX_COVARIATES` |
| `logrank` | `LogRank`, `log_rank_test`, `GroupLogRank`, `log_rank_groups` and `MAX_GROUPS` |
| `rmst` | `CumulativeHazard`, `nelson_aalen`, `RestrictedMean`, `restricted_mean`, `RestrictedComparison` and `compare_restricted_means` |
| `competing` | `CumulativeIncidence`, `cumulative_incidence` and `incidence_image` |
| `nnt` | `SurvivalDifference` and `survival_difference` |
| `aft` | `WeibullRegression` and `weibull_regression` |
| `parametric` | `ParametricFit`, `fit_exponential`, `fit_weibull`, `constant_hazard_test`, and `draw_fit` |

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

The result gives the `statistic`, `freedom`, `p_value`, and the `observed` and `expected` events of each group. `log_rank_test` is this test with two groups.

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

The tests take the chi-square tail from `chi_square_p_value` of the [Numerics](Numerics#use-statistical-distributions) extension.

## Fit a Weibull regression

A Weibull regression gives the effect of each covariate on the time to the event, not on the hazard. Each unit of a covariate multiplies the times by its time ratio. A time ratio above 1 delays the event.

```mojo
from extensions.clinical.aft import weibull_regression

var model = weibull_regression(times, events, covariates, 1e-12, 100)
print(model.time_ratio(0), model.interval(0)[0], model.interval(0)[1])
print(model.median([1.0]).to(WEEK64))
```

The model gives each patient the Weibull survival `S(t) = exp(-(t / lambda)^rho)`. The scale is `lambda = exp(b0 + b . x)`, and one shape rho holds for every patient. This is the accelerated failure time model of lifelines' `WeibullAFTFitter`. It is also a proportional hazards model, with a hazard ratio of `exp(-rho b)`.

`weibull_regression(times, events, covariates, tolerance, max_steps)` fits it by Newton steps on `(-rho b, rho)`, in which the log-likelihood is concave. A step that would make rho 0 or less, or that loses log-likelihood, is halved. The fit stops when no parameter changes by more than `tolerance`. It starts from the exponential model without covariates.

The model gives:

- `coefficients` and `standard_errors`, the log time ratios. `intercept(unit)` is `b0`, the log of the scale of a patient whose covariates are all 0, in a unit of time.
- `shape` and `log_shape_error`. The errors come from the inverse of the observed information, and `covariance` holds them all.
- `time_ratio(i)`, `interval(i)` and `p_value(i)`: `exp(b_i)`, its 95 percent interval and its Wald test.
- `scale(row)`, `median(row)` and `survival(row, time)` of a patient.
- `log_likelihood(unit)`, and `likelihood_ratio()` against the Weibull model without covariates.

In the 6-MP trial, the placebo has a time ratio of 0.28: its remissions are 28 percent as long as with 6-MP.

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

## Find the number needed to treat

A difference of survival at a time is easy to read as a number needed to treat (NNT). It is the number of patients to treat for one more to be free of the event at that time.

```mojo
from extensions.clinical.nnt import survival_difference

var gap = survival_difference(drug, placebo, Duration64(10, WEEK64))
print(gap.difference, gap.nnt(), gap.nnt_interval()[0], gap.nnt_interval()[1])
```

`survival_difference(treated, control, time)` gives the survival of each Kaplan-Meier curve at the time and their difference, treated less control. The standard error of the difference sums the Greenwood variance `S^2 sum d / (n (n - d))` of each curve. A curve that falls to 0 has no variance from then on. The result gives the 95 percent interval from `lower` to `upper`.

`nnt()` gives `1 / difference`, as Altman and Andersen (1999) give it. It is below 0 when the treated group does worse: its size is then the number needed to harm. `nnt_interval()` gives `1 / upper` and `1 / lower`. When the interval of the difference holds 0, the first end is the least number to treat for a benefit. The second end is then below 0. The NNT then runs from that benefit through infinity to that harm.

In the 6-MP trial, 75 percent of the 6-MP group and 38 percent of the placebo group are in remission at 10 weeks. The difference is 0.37, so 2.7 children need 6-MP for one more to be in remission at 10 weeks.

## Fit a parametric model

A Kaplan-Meier curve stops at the last follow-up. A parametric model gives the survival at any time, as a health economic model or a trial plan needs it.

```mojo
from extensions.clinical.parametric import fit_weibull

var fit = fit_weibull(times, events)
print(fit.scale.to(WEEK64), fit.shape, fit.median().to(WEEK64))
print(fit.survival(Duration64(52, WEEK64)))
```

A Weibull model has the survival `S(t) = exp(-(t / lambda)^rho)`. The scale lambda is the time at which 63 percent of a group has had the event. The hazard rises when the shape rho is above 1, and falls when rho is below 1. The exponential model holds rho at 1, so its hazard is constant.

`fit_exponential(times, events)` gives the scale `sum t / d`, the total time over the d events. Its standard error is `lambda / sqrt(d)`. `fit_weibull(times, events)` gives the maximum likelihood scale and shape. The shape is the root of its profile score, which falls as the shape rises. A bisection finds it to the last place, and the scale follows in closed form.

The standard errors and the covariance of the scale and the shape come from the inverse of the observed information. A `ParametricFit` gives these values at a time or a survival:

- `survival(time)`, `cumulative_hazard(time)` and `hazard(time)`. The hazard is a `Frequency64`: the events for each unit of time of those still free of the event.
- `survival_error(time)`: the delta-method standard error of the survival, as lifelines gives it. `S -+ 1.96` of it can fall outside 0 and 1.
- `survival_interval(time)`: the 95 percent interval by the delta method on the log of the cumulative hazard. It stays in 0 to 1.
- `quantile(survival)` and `median()`: the time at a survival, `lambda (-ln S)^(1 / rho)`. `quantile_interval(survival)` gives its interval on the log of the time.
- `log_likelihood(unit)` and `aic(unit)`. The density of an event changes with the unit of time, so these values do too. Compare two models in one unit.

`constant_hazard_test(times, events)` tests a shape of 1. Its statistic is twice the log-likelihood of the Weibull fit less that of the exponential fit. Its p value is on one degree of freedom.

![The Kaplan-Meier curves of the 6-MP trial, with dashed Weibull fits carried to 52 weeks](out/parametric.png)

`examples/parametric.mojo` makes this picture. The steps are the Kaplan-Meier curves of the 6-MP trial, and the dashed lines are the Weibull fits. `draw_fit(image, fit, color, top)` draws them on a plot from `survival_image`. Time runs from 0 to 52 weeks, with a gray line each 4 weeks. The trial follows no patient past 35 weeks. Past that time, the dashed lines show the model alone.

The 6-MP group has a scale of 33.8 weeks and a shape of 1.35, with a median remission of 25.8 weeks. The placebo group has a scale of 9.5 weeks and a shape of 1.37, with a median of 7.3 weeks. Neither shape differs from 1 at the 5 percent level: the p values are 0.31 and 0.09. At 52 weeks, the model gives 17 percent of the 6-MP group in remission, from 1 to 49 percent.

## Draw the curves

`survival_image(curves, colors, top, grid, width, height)` plots the curves as steps on a white image. Time runs from 0 at the left edge to `top` at the right edge. Survival runs from 0 at the bottom edge to 1 at the top edge. A light gray line marks each `grid` of time and each tenth of survival. A short vertical tick marks each censored patient on its curve.

## Verification

The tests compare the module with lifelines 0.30.3, a Python library, on the trial of Freireich and others. `assets/survival/make_survival.py` writes the expected values.

- At each time of a relapse in each group, the survival agrees to 1e-14. Both ends of the interval agree to 1e-11.
- The medians are 23 and 8 weeks, as lifelines gives.
- The log-rank statistic agrees to a relative 1e-12, and its p value to a relative 1e-11.
- The 6-MP group has 9 relapses, and the placebo group has 21.
- The log-rank test of three synthetic arms with ties agrees with lifelines' `multivariate_logrank_test` to a relative 1e-12, and its p value to 1e-11. `tools/make_survival_groups.mojo` writes the arms. With two groups, it is the two-group test.
- The Nelson-Aalen hazard of each group agrees with lifelines to a relative 1e-14, and the ends of its interval to 1e-13.
- The restricted mean to 23 weeks agrees with lifelines' `restricted_mean_survival_time` to 1e-14. lifelines gives no standard error of the mean. So the test builds it from lifelines' Kaplan-Meier curve by the formula of Klein and Moeschberger. The error agrees to 1e-13, and the test of the difference to 1e-11.

The tests compare `nnt` with statsmodels on the 6-MP trial at 10, 15 and 20 weeks. `assets/survival/make_nnt.py` writes the values. Each survival agrees with statsmodels' `SurvfuncRight` to 1e-14. The test builds the standard error of the difference from the Greenwood errors of statsmodels. The error, the interval and the NNT agree with it to 1e-13.

The tests compare `parametric` with mpmath fits at 40 digits, on the two arms of the 6-MP trial and on two synthetic groups. One synthetic group has a rising hazard, and the other a falling hazard. `tools/make_parametric.mojo` writes the groups. `assets/parametric/make_parametric.py` writes the fits, and checks that lifelines' `ExponentialFitter` and `WeibullFitter` agree with them to a relative 1e-5.

- The exponential scale, its standard error and the log-likelihood agree to a relative 1e-14.
- The Weibull scale and shape agree to a relative 1e-13, and their standard errors to 1e-12. The covariance agrees to 1e-11, and the log-likelihood to 1e-14.
- The likelihood ratio test of a constant hazard agrees to a relative 1e-11, with its p value from scipy.
- The median, the time at a survival of 0.2 and the ends of their intervals agree to a relative 1e-12 or better.
- At four times in each group, the survival and the hazard agree to a relative 1e-13. The standard error of the survival and the ends of its interval agree to 1e-11.

lifelines fits both models by a search that stops early. Its Weibull scale and shape are off by about 1e-6, relative, and its exponential scale by 5e-8. The exponential scale has the closed form `sum t / d`, so the module does not search for it.

The tests compare `aft` with fits of four groups. They are the 6-MP trial, a synthetic cohort of 150 patients with three covariates, and two small groups. The first Newton step of each small group must be halved. `tools/make_aft.mojo` writes the groups. `assets/aft/make_aft.py` fits each with lifelines' `WeibullAFTFitter`, then solves its score equations from that fit at 40 digits with mpmath. lifelines agrees with the result to 1e-4.

- The intercept, the coefficients and `ln rho` agree to 1e-12, and their standard errors to 1e-10.
- The log-likelihood agrees to 1e-13. The likelihood ratio test agrees to 1e-10, and its p value from scipy to 1e-9.
- The median and the survival of three patients of each group agree to 1e-12.
- The survival at the scale of a patient is `1/e`. The intercept moves by `ln 7` from weeks to days, and a patient censored at 0 changes nothing.

The tests compare `competing` with the `AalenJohansenFitter` of lifelines on a synthetic cohort of 80 patients with two causes. No two events tie, so lifelines does not jitter them. `tools/make_competing.mojo` writes the cohort, and `assets/competing/make_competing.py` writes the expected values.

- At the 42 times of an event, the incidence of each cause agrees to a relative 1e-14, and its variance to 1e-12.
- The ends of the interval agree to 1e-12. lifelines names its two interval columns the other way round, so the script takes the smaller end as the low end.
- With no competing event, the incidence is `1 - S` of `kaplan_meier` to 1e-14, and its variance is `S^2` times Greenwood's sum to 1e-12.

The tests compare the Cox model with lifelines on a synthetic cohort of 120 patients with three covariates. The cohort has 76 events and 29 tied times. `tools/make_cox.mojo` makes it, and `assets/survival/make_cox.py` writes the expected values. The predicted survival is read from the step curve of lifelines, because `predict_survival_function` with `times` interpolates between events.

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

The tests check the NNT by hand. Before any event, both groups survive whole, with no error, and the NNT is refused. After the last event of a group, its survival is 0 with no variance. A difference of -1/2 gives an NNT of -2, a number needed to harm of 2. An interval of the difference that holds 0 gives an NNT interval from a benefit to a harm.

The tests check parametric fits by hand. Three events at 1, 2 and 3 weeks and one censoring at 4 weeks give an exponential scale of 10/3 weeks. The hazard is then 0.3 for each week at any time. At the scale, the survival is `1/e` and the cumulative hazard 1. The log-likelihoods in days and in weeks differ by `3 ln 7`. A patient censored at 0 changes neither fit.

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
| The colors are not one for each curve, or there is no curve | `survival_image` |
| A side is out of 64 to 4096 pixels, the top time is not positive and finite, or the grid gives more than 100 lines | `survival_image` |
| The competing events are not one for each patient, or a patient has both first events | `cumulative_incidence` |
| A row index names no time | `CumulativeIncidence.interval` |
| The time of a survival difference is below 0 or not finite, or the difference is 0 for an NNT | `survival_difference`, `SurvivalDifference.nnt` |
| There is no curve, the colors are not one for each, a side is out of 64 to 4096 pixels, a time is out of range, or the ceiling is not above 0 and at most 1 | `incidence_image` |
| The covariates are not one finite row of 1 to 32 values for each patient, an event is at 0, the tolerance is not between 0 and 1, the steps are not from 1 to 1000, or the information matrix is not positive definite | `weibull_regression` |
| An index names no covariate, a row does not have one finite value for each covariate, or a time is negative or not finite | `WeibullRegression` |
| A group has no event, or has an event at 0 | `fit_exponential`, `fit_weibull`, `constant_hazard_test` |
| No event is before the largest time, so the shape has no finite estimate | `fit_weibull`, `constant_hazard_test` |
| A time is below 0 or not finite | `ParametricFit` |
| A survival is not above 0 and below 1 | `ParametricFit.quantile`, `ParametricFit.quantile_interval` |
| The top time is not positive and finite | `draw_fit` |

## Limits

- The log-rank tests have no strata and no weights, such as those of Fleming and Harrington.
- The Cox model takes covariates that do not change in time, one stratum and no weights. It does not test the proportional hazards assumption. Check that assumption before you use a hazard ratio.
- A Cox fit holds the risk sets in one pass over the sorted times, and Harrell's C compares each pair of patients. A cohort of many thousands of patients is slow.
- It takes right censoring only. A patient who enters the study late, or whose event happens between two visits, needs another method.
- The p value is for one test. Many tests on one data set need a correction.
- The parametric models are exponential and Weibull only. The Weibull regression takes covariates for the scale only, with one shape for all. A curve past the last follow-up holds only if the model holds there. Check the fit against the Kaplan-Meier curve first.
- The cumulative incidence takes independent censoring. The module has no test of Gray to compare incidences, and no Fine-Gray model of the subdistribution hazard.

## References

- Kaplan and Meier, "Nonparametric estimation from incomplete observations", Journal of the American Statistical Association, 1958.
- Greenwood, "The natural duration of cancer", Reports on Public Health and Medical Subjects 33, 1926.
- Mantel, "Evaluation of survival data and two new rank order statistics arising in its consideration", Cancer Chemotherapy Reports, 1966.
- Freireich and others, "The effect of 6-mercaptopurine on the duration of steroid-induced remissions in acute leukemia", Blood, 1963.
- Gehan, "A generalized Wilcoxon test for comparing arbitrarily singly-censored samples", Biometrika, 1965.
- Cox, "Regression models and life-tables", Journal of the Royal Statistical Society, Series B, 1972.
- Efron, "The efficiency of Cox's likelihood function for censored data", Journal of the American Statistical Association, 1977.
- Klein and Moeschberger, "Survival Analysis: Techniques for Censored and Truncated Data", second edition, Springer, 2003.
- Breslow, "Covariance analysis of censored survival data", Biometrics, 1974.
- Harrell and others, "Evaluating the yield of medical tests", Journal of the American Medical Association, 1982.
- Nelson, "Theory and applications of hazard plotting for censored failure data", Technometrics, 1972.
- Aalen and Johansen, "An empirical transition matrix for non-homogeneous Markov chains based on censored observations", Scandinavian Journal of Statistics, 1978.
- Collett, a textbook on the survival data of medical research, third edition, CRC Press, 2015.
- Putter, Fiocco and Geskus, "Tutorial in biostatistics: competing risks and multi-state models", Statistics in Medicine, 2007.
- Altman and Andersen, "Calculating the number needed to treat for trials where the outcome is time to an event", BMJ, 1999.
- Aalen, "Nonparametric inference for a family of counting processes", Annals of Statistics, 1978.
- Royston and Parmar, "Restricted mean survival time: an alternative to the hazard ratio", BMC Medical Research Methodology, 2013.
- Klein and Moeschberger, "Survival Analysis: Techniques for Censored and Truncated Data", 2nd edition, 2003.
- Kalbfleisch and Prentice, "The Statistical Analysis of Failure Time Data", 2nd edition, 2002.
