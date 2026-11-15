# Observational studies

`extensions/clinical/propensity.mojo` estimates the effect of a treatment from an observational study, where the patients were not randomized. It fits a propensity score, and it weights each patient by the inverse probability of the treatment that the patient got. It measures the balance of the covariates. It gives the E-value of an effect: how strong an unmeasured confounder must be to explain the effect away. `extensions/clinical/standardize.mojo` standardizes rates for age, with exact Poisson intervals.

It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

## Modules

| Module | What it gives |
|---|---|
| `propensity` | `IpwEffect`, `ipw_effect`, `standardized_difference`, `effective_sample_size`, `e_value` and `e_value_bound` |
| `standardize` | `poisson_interval`, `StandardizedRatio`, `standardized_ratio`, `expected_events`, `DirectRate` and `direct_rate` |

## Weight the patients

In an observational study, the patients who get a treatment differ from those who do not. Older or sicker patients can get it more often. Then a crude comparison mixes the effect of the treatment with the effect of the age or the sickness.

The propensity score is the chance of each patient to get the treatment, given the covariates. Weight each treated patient by `1 / p` and each other patient by `1 / (1 - p)`. In the weighted population, the covariates no longer predict the treatment, as in a randomized trial.

```mojo
from extensions.clinical.propensity import e_value, ipw_effect

var effect = ipw_effect(treated, outcomes, covariates)
print(effect.difference, effect.interval()[0], effect.interval()[1])
var ratio = effect.ratio()
print(ratio.value, e_value(ratio.value))
```

`ipw_effect(treated, outcomes, covariates)` fits the logistic model of the treatment on the covariates. Each outcome is a number, such as 1 for an event and 0 for none. The `IpwEffect` gives:

- `treated_mean` and `control_mean`, the weighted mean outcome of each group, with the weights normalized in each group. They estimate the mean outcome if every patient were treated, and if none were.
- `difference`, the average treatment effect, with `interval()` and `p_value()`.
- `ratio()`, the ratio of the two means with its 95 percent interval. For an outcome of 1 or 0, it is the risk ratio. `ratio_error()` is the standard error of its log, by the delta method.
- `propensity` and `weights`, for each patient.

The standard errors come from the sandwich of the stacked estimating equations: the two weighted means and the scores of the logistic model. So they take the uncertainty of the propensity scores into account, as statsmodels' `TreatmentEffect.ipw` gives them.

## Check the balance

A weighting works only if it balances the covariates. `standardized_difference(values, treated, weights)` gives the difference of the weighted means of a covariate, over the root of the mean of the two weighted variances. Give weights of 1 for the balance before weighting. A standardized difference below 0.1 is usually taken as balanced.

`effective_sample_size(weights)` gives Kish's `(sum w)^2 / sum w^2` of a group. Large weights, from propensity scores near 0 or 1, shrink it. A small effective size means that a few patients carry the estimate.

## Find the E-value

An observational study cannot measure every confounder. The E-value of VanderWeele and Ding (2017) is the least risk ratio that an unmeasured confounder needs to explain the effect away. The confounder needs that ratio with both the treatment and the outcome. A larger E-value needs a stronger confounder.

- `e_value(ratio)` gives `RR + sqrt(RR (RR - 1))`. A ratio below 1 takes its inverse first.
- `e_value_bound(lower, upper)` gives the E-value of the end of the interval nearest to 1. It is 1 when the interval holds 1.

For an odds ratio of a common outcome, take its square root as the risk ratio first. For a rare outcome, the odds ratio and the hazard ratio are near the risk ratio.

## Standardize rates

Two groups of different ages have different rates of death, even when the risk at each age is the same. Standardization takes the ages out of a comparison of rates.

```mojo
from extensions.clinical.standardize import direct_rate, expected_events, standardized_ratio

var expected = expected_events(cohort_years, reference_rates)
var smr = standardized_ratio(deaths, expected)
print(smr.ratio, smr.lower, smr.upper, smr.p_value)
var rate = direct_rate(events, person_years, standard_shares)
print(rate.rate.to(PER_YEAR64), rate.lower.to(PER_YEAR64), rate.upper.to(PER_YEAR64))
```

- Indirect standardization: `expected_events(person_time, rates)` gives `sum T_i r_i`. These are the events of the cohort at the rate of a reference population in each group, such as each band of age. `standardized_ratio(observed, expected)` gives the observed over the expected events, such as the standardized mortality ratio (SMR).
- The interval of the ratio is the exact interval of the count over the expected count. Its p value is the exact central p value of a ratio of 1: twice the smaller Poisson tail of the count, at most 1.
- Direct standardization: `direct_rate(events, person_time, shares)` weights the rate of each group by its share of a standard population. With `y_i = w_i / T_i`, the rate is `R = sum y_i d_i`, and its variance `V = sum y_i^2 d_i`.
- The interval of the direct rate is that of Fay and Feuer (1997). Its low end is the 2.5 percent point of a gamma of mean R and variance V. Its high end is the 97.5 percent point of a gamma of mean `R + m` and variance `V + m^2`, with m the largest `y_i`.

The exact intervals come from the [gamma functions](Numerics#use-statistical-distributions) of `numerics.distributions`.

- `poisson_interval(count)` gives the exact central 95 percent interval of the mean of a count, after Garwood (1936). It runs from the 2.5 percent point of a gamma of shape `count` to the 97.5 percent point of a gamma of shape `count + 1`.

## Verification

The tests compare the module with statsmodels 0.15.0 on a synthetic study of 500 patients with three covariates. Older and sicker patients are treated more often and have the outcome more often. `tools/make_propensity.mojo` writes the study, and `assets/propensity/make_propensity.py` writes the expected values.

- The average treatment effect and the two means agree with statsmodels' `TreatmentEffect.ipw` to a relative 1e-12.
- statsmodels takes the derivatives of its moments numerically, so the standard errors agree to 1e-9. The covariance of the two means agrees with the covariance of its GMM fit to 1e-8.
- The risk ratio agrees with the ratio of the two means to 1e-13. The error of its log agrees with the delta method on the covariance of statsmodels to 1e-8.
- The standardized differences of the three covariates agree with numpy's `average` and `cov` with `aweights` to 1e-12 before weighting and 1e-9 after it. The weighting brings the differences of age and severity from 0.48 and 0.49 to below 0.03.
- The effective sample sizes agree with `(sum w)^2 / sum w^2` to 1e-12.

The tests also check cases by hand:

- A risk ratio of 3.9 has an E-value of 7.26. Its low end of 1.8 has one of 3.0, as in VanderWeele and Ding. A ratio and its inverse have one E-value. An interval that holds 1 gives 1.
- Weights of 1, 1, 1 and 1 give an effective size of 4, and weights of 1 and 3 give 1.6.
- Means of 1 and 2 with variances of 2 give a standardized difference of `-1 / sqrt(2)`.
- A covariate with the same mean in each group gives each patient a propensity of a half and a weight of 2.

The tests compare `standardize` with scipy 1.18.1 and statsmodels 0.15.0. `assets/standardize/make_standardize.py` writes the values.

- The tests take the gamma tails at 40 points, with shapes from 0.1 to 1e5. Below a shape of 1000, they agree with scipy's `gammainc` and `gammaincc` to a relative 5e-14. Above it, they agree to 5e-10, because `a ln x - x - ln Gamma(a)` cancels.
- The quantiles at probabilities from 1e-10 to `1 - 1e-10` agree with scipy's `gamma.ppf` to 5e-14 below a shape of 1000, and to 2e-12 above it.
- The exact intervals of six counts from 0 to 250 agree with statsmodels' `confint_poisson` with `exact-c` to 1e-12.
- Five standardized ratios agree with the intervals of `confint_poisson` to 1e-12. Their p values agree with `test_poisson` with `exact-c` to 1e-11. An observed count equal to the expected count has a p value of 1.
- The direct rate of a synthetic cohort of six age groups agrees with the sum `R = sum y_i d_i` to 1e-13. Its interval agrees with the closed form of Fay and Feuer on the gamma points to 1e-11. With no event, the rate and the low end are 0, and the high end is `-m ln 0.025`.
- A cohort of 1000 person-years at 0.001 a year and 500 at 0.004 a year expects 3 events.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| The outcomes are not one finite value for each patient | `ipw_effect` |
| The propensity model refuses the covariates or the treatments | `ipw_effect`, as `logistic_regression` |
| A mean is not above 0 | `IpwEffect.ratio`, `IpwEffect.ratio_error` |
| There is no weight, or a weight is not positive and finite | `standardized_difference`, `effective_sample_size` |
| The lists differ in length, a value is not finite, a group has fewer than two patients, or the covariate does not vary | `standardized_difference` |
| A ratio is not positive and finite, or an interval does not rise | `e_value`, `e_value_bound` |
| A count is below 0 or at least 1e7, or an expected count is not positive and finite | `poisson_interval`, `standardized_ratio` |
| The lists are empty or differ in length, or a person-time or a rate is below 0 or not finite | `expected_events` |
| The lists are empty or differ in length, an event count is below 0, a person-time is not positive and finite, the shares are not 0 or more and finite with a sum of 1, or an end of the interval needs a gamma shape above 1e7 | `direct_rate` |

## Limits

- The weights remove the confounding of the measured covariates only. An unmeasured confounder can still bias the effect. Report the E-value with the effect.
- The propensity model is a logistic model with no interaction or curve that the caller does not add as a covariate. A wrong model leaves the covariates unbalanced, so check the standardized differences.
- The module does not trim or truncate extreme weights, and it has no matching, stratification or doubly robust estimator.
- The effect is the average effect over the whole population, not over the treated only.
- Standardized rates take the events as Poisson counts. They do not correct for overdispersion. An SMR compares a cohort with the reference population only, so two SMRs of different cohorts do not compare their rates. The intervals are for 95 percent only.

## References

- Rosenbaum and Rubin, "The central role of the propensity score in observational studies for causal effects", Biometrika, 1983.
- Lunceford and Davidian, "Stratification and weighting via the propensity score in estimation of causal treatment effects: a comparative study", Statistics in Medicine, 2004.
- Austin and Stuart, on the best practice of inverse probability of treatment weighting with the propensity score, Statistics in Medicine, 2015.
- VanderWeele and Ding, "Sensitivity analysis in observational research: introducing the E-value", Annals of Internal Medicine, 2017.
- Kish, "Survey Sampling", Wiley, 1965.
- Garwood, "Fiducial limits for the Poisson distribution", Biometrika, 1936.
- Fay and Feuer, "Confidence intervals for directly standardized rates: a method based on the gamma distribution", Statistics in Medicine, 1997.
- Breslow and Day, "Statistical Methods in Cancer Research, Volume II: The Design and Analysis of Cohort Studies", IARC, 1987.
