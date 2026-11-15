# Observational studies

`extensions/clinical/propensity.mojo` estimates the effect of a treatment from an observational study, where the patients were not randomized. It fits a propensity score, and it weights each patient by the inverse probability of the treatment that the patient got. It measures the balance of the covariates. It gives the E-value of an effect: how strong an unmeasured confounder must be to explain the effect away.

It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

## Modules

| Module | What it gives |
|---|---|
| `propensity` | `IpwEffect`, `ipw_effect`, `standardized_difference`, `effective_sample_size`, `e_value` and `e_value_bound` |

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

## Verification

The tests compare the module with statsmodels 0.15.0 on a synthetic study of 500 patients with three covariates. Older and sicker patients are treated more often and have the outcome more often. `assets/propensity/make_propensity.py` writes the study.

- The average treatment effect and the two means agree with statsmodels' `TreatmentEffect.ipw` and their closed form to a relative 1e-12.
- statsmodels takes the derivatives of its moments numerically, so its standard errors agree to 1e-9. The same sandwich with exact derivatives in numpy agrees to 1e-11.
- The risk ratio, the error of its log and its interval agree with numpy to 1e-11.
- The standardized differences of the three covariates agree with numpy to 1e-12 before weighting and 1e-9 after it. The weighting brings the differences of age and severity from 0.54 and 0.50 to below 0.04.
- The effective sample sizes and the E-values agree to 1e-11.

The tests also check cases by hand:

- A risk ratio of 3.9 has an E-value of 7.26. Its low end of 1.8 has one of 3.0, as in VanderWeele and Ding. A ratio and its inverse have one E-value. An interval that holds 1 gives 1.
- Weights of 1, 1, 1 and 1 give an effective size of 4, and weights of 1 and 3 give 1.6.
- Means of 1 and 2 with variances of 2 give a standardized difference of `-1 / sqrt(2)`.
- A covariate with the same mean in each group gives each patient a propensity of a half and a weight of 2.

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

## Limits

- The weights remove the confounding of the measured covariates only. An unmeasured confounder can still bias the effect. Report the E-value with the effect.
- The propensity model is a logistic model with no interaction or curve that the caller does not add as a covariate. A wrong model leaves the covariates unbalanced, so check the standardized differences.
- The module does not trim or truncate extreme weights, and it has no matching, stratification or doubly robust estimator.
- The effect is the average effect over the whole population, not over the treated only.

## References

- Rosenbaum and Rubin, "The central role of the propensity score in observational studies for causal effects", Biometrika, 1983.
- Lunceford and Davidian, "Stratification and weighting via the propensity score in estimation of causal treatment effects: a comparative study", Statistics in Medicine, 2004.
- Austin and Stuart, on the best practice of inverse probability of treatment weighting with the propensity score, Statistics in Medicine, 2015.
- VanderWeele and Ding, "Sensitivity analysis in observational research: introducing the E-value", Annals of Internal Medicine, 2017.
- Kish, "Survey Sampling", Wiley, 1965.
