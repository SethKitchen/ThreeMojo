# Sample size and power

`extensions/clinical/power.mojo` plans the size of a study. It gives the patients that a study needs to find an effect, and the power that a study of a given size has. It covers two proportions, two means and survival, by the normal approximation. `extensions/clinical/phase2.mojo` designs single-arm phase II trials by Simon's two stages, with exact binomial errors. It is a library for research and teaching. A real study needs a statistician's plan.

## Modules

| Module | What it gives |
|---|---|
| `power` | `proportions_size`, `proportions_power`, `means_size`, `means_power`, `schoenfeld_events`, `freedman_size` and `freedman_power` |
| `phase2` | `SimonDesign`, `simon_optimal`, `simon_minimax`, `simon_errors`, `posterior_above` and `MAX_SIMON_SIZE` |
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

## Design a phase II trial

A phase II trial of a new drug treats one arm. It asks whether the response rate is above a rate p0 of no interest, and near a rate p1 of interest. Simon (1989) gives two stages, so that a drug that does not work stops early.

```mojo
from extensions.clinical.phase2 import posterior_above, simon_minimax, simon_optimal

var design = simon_optimal(0.1, 0.3, 0.05, 0.2, 60)
print(design.r1, design.n1, design.r, design.n, design.expected)
print(posterior_above(1.0, 1.0, 7, 20, 0.2))
```

Treat `n1` patients first, and stop when `r1` or fewer respond. Else treat `n - n1` more, and reject p0 when more than `r` of all `n` respond. The chances come from the binomial distribution, with no approximation.

- `simon_optimal(p0, p1, alpha, beta, most)` searches each design of at most `most` patients. It keeps those with a type I error of at most alpha and a power of at least `1 - beta`. Of these, it gives the design with the least expected size under p0.
- `simon_minimax(p0, p1, alpha, beta, most)` gives the design with the least `n`, then the least expected size.
- For each `n`, `n1` and `r1`, the search takes the least `r` whose type I error is at most alpha, by bisection. A tie keeps the first design, in the order of `n`, `n1` and `r1`.
- A `SimonDesign` holds `r1`, `n1`, `r` and `n`, and under p0 its chance of an early stop and its expected size. It also holds its type I error and its power.
- `simon_errors(design, p)` gives the chance that a design rejects p0, and the chance that it stops early, at any true rate p.
- `posterior_above(a, b, responses, patients, p0)` gives the posterior probability that the rate is above p0. The prior is a beta of shapes a and b, and the posterior a beta of `a + responses` and `b + patients - responses`.

Take p0 = 0.1 and p1 = 0.3, with alpha 0.05 and a power of 0.8. The optimal design treats 10 patients, and stops if 1 or none respond. It then treats 19 more and needs more than 5 responses of 29. It treats 15 patients on average when the drug does not work.

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

The tests compare `phase2` with an exhaustive search of every design in scipy, to 60 patients, for three pairs of rates. `assets/phase2/make_phase2.py` writes it.

- The optimal and minimax designs have the same `r1`, `n1`, `r` and `n`. They are those of Simon's table of 1989: 1/10 then 5/29, and 1/15 then 5/25, for p0 = 0.1 and p1 = 0.3.
- The chance of an early stop and the power agree to a relative 1e-12. The expected size agrees to 1e-13, and the type I error to 1e-11.
- `simon_errors` of a design at p0 and p1 gives its type I error, its early stop and its power.
- The posterior probabilities of four priors and trials agree with scipy's `beta.sf` to 1e-12.

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
| The rates are not `0 < p0 < p1 < 1`, alpha or beta is not between 0 and 0.5, the most is not from 2 to 100, or no design of at most that many patients holds | `simon_optimal`, `simon_minimax` |
| A rate is not between 0 and 1, or a design is not `0 <= r1 < n1 < n` with `r1 <= r < n` and n at most 100 | `simon_errors` |
| A prior shape is not positive and finite, the responses are not from 0 to the patients, or p0 is not between 0 and 1 | `posterior_above` |

## Limits

- The sizes come from the normal approximation. With small groups, an exact test or a t test needs more patients.
- The module plans for two groups and one test. It does not correct for many tests, interim looks, dropouts or clusters.
- A survival study must estimate the chance of an event in each group from its accrual and its follow-up. The module does not model them.
- A Simon design takes each patient's response as known before the second stage. It plans for one arm and one end point, with no delay in response. The posterior takes a beta prior, and it is not a rule to stop a trial.

## References

- Fleiss, Levin and Paik, "Statistical Methods for Rates and Proportions", 3rd edition, 2003.
- Schoenfeld, "Sample-size formula for the proportional-hazards regression model", Biometrics, 1983.
- Freedman, "Tables of the number of patients required in clinical trials using the logrank test", Statistics in Medicine, 1982.
- Chow, Shao and Wang, "Sample Size Calculations in Clinical Research", 2nd edition, 2008.
- Acklam, "An algorithm for computing the inverse normal cumulative distribution function", 2003.
- Simon, "Optimal two-stage designs for phase II clinical trials", Controlled Clinical Trials, 1989.
