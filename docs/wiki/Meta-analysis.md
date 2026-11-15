# Meta-analysis

`extensions/clinical/meta.mojo` pools the effects of several studies of one question. It gives the fixed effect and the random effects of DerSimonian and Laird, with their intervals and tests. It gives Cochran's Q, I^2, tau^2 and the prediction interval of a new study. It finds the effect of a study from its counts, and it draws forest plots. It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![A forest plot of the 13 trials of the BCG vaccine against tuberculosis](out/forest.png)

`examples/forest.mojo` makes this picture. It uses the 13 trials of the BCG vaccine against tuberculosis of Colditz and others (1994). Each row is a trial, with its log risk ratio of tuberculosis, vaccinated against not. The line is the 95 percent interval of the trial, and the area of the square is in proportion to its weight. The gray diamond is the fixed effect, and the blue diamond is the random effect. The gray line is no effect, and left of it the vaccine protects.

The random effects risk ratio is 0.49, with a 95 percent interval from 0.34 to 0.70. The trials differ much more than chance allows: Q is 152 on 12 degrees of freedom, and I^2 is 92 percent. So the prediction interval of a new trial is wide, from 0.14 to 1.77.

## Modules

| Module | What it gives |
|---|---|
| `meta` | `MetaAnalysis`, `Pooled`, `meta_analysis`, `log_risk_ratio`, `log_odds_ratio`, `forest_image`, `MAX_STUDIES` and `FOREST_ROW` |

## Find the effect of a study

A meta-analysis pools one effect from each study, with its variance. Use an effect on a scale where its interval is symmetric. A log risk ratio, a log odds ratio and a difference of means are such effects.

`log_risk_ratio(events_a, total_a, events_b, total_b)` and `log_odds_ratio(events_a, total_a, events_b, total_b)` find the effect of a study from its counts. Each returns the effect and its variance:

- The log risk ratio is `ln((a / n1) / (c / n2))`, with the variance `1/a - 1/n1 + 1/c - 1/n2`.
- The log odds ratio is `ln(a d / (b c))`, with Woolf's variance `1/a + 1/b + 1/c + 1/d`.

When a cell of the two-by-two table is 0, each cell takes a half more.

## Pool the studies

`meta_analysis(effects, variances)` takes 2 to 160 studies.

```mojo
from extensions.clinical.meta import log_risk_ratio, meta_analysis

var first = log_risk_ratio(4, 123, 11, 139)
var second = log_risk_ratio(6, 306, 29, 303)
var third = log_risk_ratio(3, 231, 11, 220)
var result = meta_analysis(
    [first[0], second[0], third[0]], [first[1], second[1], third[1]]
)
print(result.random.estimate, result.i_squared)
```

The result gives two pooled effects. Each `Pooled` has the `estimate`, its `standard_error`, the 95 percent interval from `lower` to `upper`, `z` and the two-sided `p_value`.

- `fixed` weighs each study by the inverse of its variance. It takes all studies to measure one true effect.
- `random` lets the true effect differ from study to study, with the variance `tau_squared`. It adds `tau_squared` to the variance of each study before it weighs them. So small studies get more weight, and the interval is wider.

The result also gives:

- `q` and `q_p_value`, Cochran's test that the studies share one effect. The test has little power with few studies.
- `i_squared`, the share of the variation of the effects that comes from the studies and not from chance, `(Q - df) / Q`, held at 0 or more.
- `tau_squared`, by the method of moments of DerSimonian and Laird.
- `fixed_weights` and `random_weights`, the relative weight of each study. Each set sums to 1.
- `prediction_interval()`, the 95 percent interval of the effect of a new study, from the t distribution with `k - 2` degrees of freedom. It needs three studies or more.

## Draw a forest plot

`forest_image(effects, variances, result, width)` draws one row for each study, then a gray diamond for the fixed effect and a blue diamond for the random effect. Each row is 24 pixels high. The effect runs across the image, with a gray line at 0. For a log ratio, 0 is a ratio of 1.

## Verification

The tests compare the module with statsmodels 0.15.0 and scipy 1.18.1 on the BCG trials. `assets/meta/make_meta.py` writes the expected values.

- The log risk ratio and the variance of each trial agree with numpy to a relative 1e-14.
- The fixed and random effects, their standard errors, interval ends and z agree with `combine_effects` of statsmodels to a relative 1e-12. The p values agree to 1e-10.
- Q, I^2, tau^2 and the weights agree to 1e-12. They are the published values of the R package metafor: Q is 152.23, I^2 is 92.12 percent and tau^2 is 0.3088.
- The prediction interval agrees with scipy's t quantile to 1e-12.

The tests also check cases by hand:

- Two studies have the effects 0 and 2, and a variance of 1 each. They give a fixed effect of 1 with a standard error of `sqrt(1/2)`. Q is 2, tau^2 is 1 and I^2 is a half. The random effect has a standard error of 1.
- Three equal effects give Q, tau^2 and I^2 of 0, a p value of 1, and two equal models.
- A risk ratio of 10 of 30 against 5 of 45 is 3. Its odds ratio is 4, with Woolf's variance 0.375. A cell of 0 adds a half to each cell.
- The forest plot of two studies has the zero line, the squares, the interval lines and the diamonds in the right pixels.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| There are not 2 to 160 studies, an effect is not finite, or a variance is not positive and finite | `meta_analysis`, `forest_image` |
| A group has no patient, or its events are not from 0 to its count | `log_risk_ratio`, `log_odds_ratio` |
| There are fewer than three studies | `MetaAnalysis.prediction_interval` |
| The result is not that of the studies, or the width is not from 128 to 4096 pixels | `forest_image` |

## Limits

- The random effects use the method of moments of DerSimonian and Laird, with normal intervals. With few studies, its interval is too narrow. The module has no REML, Paule-Mandel or Hartung-Knapp method.
- The module has no meta-regression, subgroup test or test of small-study effects, such as Egger's test.
- A pooled effect is only as good as the studies. Heterogeneity, as in the BCG trials, can come from a cause such as the latitude of a trial, which a pooled effect hides.

## References

- DerSimonian and Laird, "Meta-analysis in clinical trials", Controlled Clinical Trials, 1986.
- Cochran, "The combination of estimates from different experiments", Biometrics, 1954.
- Higgins and Thompson, "Quantifying heterogeneity in a meta-analysis", Statistics in Medicine, 2002.
- Higgins, Thompson and Spiegelhalter, "A re-evaluation of random-effects meta-analysis", Journal of the Royal Statistical Society, Series A, 2009.
- Colditz and others, "Efficacy of BCG vaccine in the prevention of tuberculosis: meta-analysis of the published literature", JAMA, 1994.
- Viechtbauer, the metafor package for R, Journal of Statistical Software, 2010.
