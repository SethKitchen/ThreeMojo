# Sample size and power

`extensions/clinical/power.mojo` plans the size of a study. It gives the patients that a study needs to find an effect, and the power that a study of a given size has. It covers two proportions, two means and survival, by the normal approximation. It is a library for research and teaching. A real study needs a statistician's plan.

## Modules

| Module | What it gives |
|---|---|
| `power` | `proportions_size`, `proportions_power`, `means_size`, `means_power`, `schoenfeld_events`, `freedman_size` and `freedman_power` |
| `distributions` | `normal_quantile`, among the functions of [Diagnostic tests](Diagnostic-tests#use-the-t-and-f-distributions) |

## Plan a study

A study plans for a two-sided test at a level `alpha`, such as 0.05. It also plans for a power, such as 0.8: the chance that the study finds a true effect of the size that it plans for. A smaller effect, a smaller `alpha` or a larger power needs more patients.

Each size is the exact real number of its formula. Round it up to a whole patient. A `ratio` is the size of one group over the other: 1 for equal groups.

```mojo
from extensions.clinical.power import proportions_size

# A cure rate of 30 percent against 15 percent, at 5 percent and 80 percent.
var n = proportions_size(0.30, 0.15, 0.05, 0.8, 1.0)
print(n)  # 120.47: plan 121 patients in each group
```

## Compare two proportions

`proportions_size(p1, p2, alpha, power, ratio)` gives the size of the first group. `proportions_power(p1, p2, n1, alpha, ratio)` gives the power of a first group of `n1` patients. The test takes the variance under the null hypothesis from the pooled proportion, and the variance under the alternative from the two proportions. This is the formula of Fleiss without a continuity correction, as statsmodels uses it.

## Compare two means

`means_size(difference, deviation, alpha, power, ratio)` and `means_power(difference, deviation, n1, alpha, ratio)` take the difference of the means and the standard deviation in each group, in one unit that you choose. They use a known deviation, as statsmodels' `NormalIndPower` does. A t test needs a few patients more.

## Plan a survival study

The power of a log-rank test or a Cox model depends on the events, not on the patients.

- `schoenfeld_events(hazard_ratio, alpha, power, allocation)` gives the events of both groups, `(z_a + z_b)^2 / (a (1 - a) ln(HR)^2)`. Here `a` is the fraction of patients in the first group.
- `freedman_size(hazard_ratio, alpha, power, ratio, first_events, second_events)` gives the patients of each group by Freedman's formula. It divides the events by the chance of an event in each group during the study, as lifelines does.
- `freedman_power(hazard_ratio, alpha, first, second, first_events, second_events)` gives the power of groups of a given size, as lifelines gives it.

## Use the normal quantile

`normal_quantile(p)` gives the z with P(Z <= z) = p. Acklam's rational approximation starts one step of Halley's method on `erfc`, which is exact. Above a half, the quantile is the negative of the quantile of `1 - p`. It takes a probability from 1e-300.

## Verification

The tests compare the module with scipy 1.18.1, statsmodels 0.15.0 and lifelines 0.30.3. `assets/power/make_power.py` writes the expected values.

- The normal quantile agrees with `norm.ppf` to a relative 1e-15, from 1e-300 to 0.999999.
- The sizes and powers of two proportions agree with `samplesize_proportions_2indep_onetail` and `power_proportions_2indep` to a relative 1e-13, for equal and unequal groups.
- The sizes and powers of two means agree with `normal_sample_size_one_tail` and `NormalIndPower` to 1e-13.
- Schoenfeld's events agree with the formula and `norm.ppf` to 1e-13.
- Freedman's sizes, rounded up, are those of lifelines' `sample_size_necessary_under_cph`, and the power agrees with `power_under_cph` to 1e-13.

The tests also check cases by hand:

- Equal groups a half deviation apart need `8 (z_a + z_b)^2` patients each. At that size, the power is 0.8 and the chance of the far tail.
- Even groups need `4 (z_a + z_b)^2 / ln(HR)^2` events.
- A power less than the level needs no patients.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| The level or the power is not between 0 and 1 | all |
| A proportion is not between 0 and 1, or the two are equal | `proportions_size`, `proportions_power` |
| The difference of the means is 0 or not finite, or the deviation is not positive and finite | `means_size`, `means_power` |
| A ratio or a group size is not positive and finite | all with a ratio or a size |
| The hazard ratio is 1, or not positive and finite, or the allocation is not between 0 and 1 | `schoenfeld_events`, `freedman_size`, `freedman_power` |
| A chance of an event is not in (0, 1] | `freedman_size`, `freedman_power` |
| A probability is less than 1e-300 | `normal_quantile` |

## Limits

- The sizes come from the normal approximation. With small groups, an exact test or a t test needs more patients.
- The module plans for two groups and one test. It does not correct for many tests, interim looks, dropouts or clusters.
- A survival study must estimate the chance of an event in each group from its accrual and its follow-up. The module does not model them.

## References

- Fleiss, Levin and Paik, "Statistical Methods for Rates and Proportions", 3rd edition, 2003.
- Schoenfeld, "Sample-size formula for the proportional-hazards regression model", Biometrics, 1983.
- Freedman, "Tables of the number of patients required in clinical trials using the logrank test", Statistics in Medicine, 1982.
- Chow, Shao and Wang, "Sample Size Calculations in Clinical Research", 2nd edition, 2008.
- Acklam, "An algorithm for computing the inverse normal cumulative distribution function", 2003.
