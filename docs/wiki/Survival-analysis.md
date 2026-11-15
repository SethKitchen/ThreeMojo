# Survival analysis

`extensions/clinical/` gives the survival of groups of patients. It makes Kaplan-Meier curves with 95 percent intervals and medians. It compares two groups by the log-rank test, and it plots the curves. It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![The Kaplan-Meier curves of 6-MP and of a placebo in acute leukemia, with a tick at each censored patient](out/survival.png)

`examples/survival.mojo` makes this picture. It uses the trial of 6-mercaptopurine (6-MP) against a placebo in 42 children with acute leukemia, of Freireich and others (1963). The blue curve is 6-MP, and the red curve is the placebo. Time runs from 0 to 36 weeks, with a gray line each 6 weeks. The median remission is 23 weeks with 6-MP and 8 weeks with the placebo. The log-rank chi-square is 16.79, and its p value is 4.2e-5.

## Modules

| Module | What it gives |
|---|---|
| `survival` | `SurvivalCurve`, `kaplan_meier`, `LogRank`, `log_rank_test`, `survival_image`, `DAY64` and `WEEK64` |

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

## Draw the curves

`survival_image(curves, colors, top, grid, width, height)` plots the curves as steps on a white image. Time runs from 0 at the left edge to `top` at the right edge. Survival runs from 0 at the bottom edge to 1 at the top edge. A light gray line marks each `grid` of time and each tenth of survival. A short vertical tick marks each censored patient on its curve.

## Verification

The tests compare the module with lifelines 0.30.3, a Python library, on the trial of Freireich and others. `assets/survival/make_survival.py` writes the expected values.

- At each time of a relapse in each group, the survival agrees to 1e-14. Both ends of the interval agree to 1e-11.
- The medians are 23 and 8 weeks, as lifelines gives.
- The log-rank statistic agrees to a relative 1e-12, and its p value to a relative 1e-11.
- The 6-MP group has 9 relapses, and the placebo group has 21.

The tests also check a small group by hand. Five patients have events at 1, 2, 2 and 4 weeks, and one patient is censored at 3 weeks. The survival is 0.8, then 0.4, then 0. Two identical groups give a statistic of 0 and a p value of 1.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A group has no patient, or its times and flags differ in number | `kaplan_meier`, `log_rank_test` |
| A time is negative or not finite | `kaplan_meier`, `log_rank_test` |
| No event changes the risk of either group | `log_rank_test` |
| A row index names no time | `SurvivalCurve.interval` |
| The colors are not one for each curve, or there is no curve | `survival_image` |
| A side is out of 64 to 4096 pixels, the top time is not positive and finite, or the grid gives more than 100 lines | `survival_image` |

## Limits

- The module compares two groups only. It has no stratified test, no weighted test and no test of more than two groups.
- It has no regression model, such as the Cox proportional hazards model.
- It takes right censoring only. A patient who enters the study late, or whose event happens between two visits, needs another method.
- The p value is for one test. Many tests on one data set need a correction.

## References

- Kaplan and Meier, "Nonparametric estimation from incomplete observations", Journal of the American Statistical Association, 1958.
- Greenwood, "The natural duration of cancer", Reports on Public Health and Medical Subjects 33, 1926.
- Mantel, "Evaluation of survival data and two new rank order statistics arising in its consideration", Cancer Chemotherapy Reports, 1966.
- Freireich and others, "The effect of 6-mercaptopurine on the duration of steroid-induced remissions in acute leukemia", Blood, 1963.
- Gehan, "A generalized Wilcoxon test for comparing arbitrarily singly-censored samples", Biometrika, 1965.
- Kalbfleisch and Prentice, "The Statistical Analysis of Failure Time Data", 2nd edition, 2002.
