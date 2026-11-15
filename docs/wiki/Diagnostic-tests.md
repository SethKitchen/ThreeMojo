# Diagnostic tests

`extensions/clinical/` measures diagnostic tests and the methods that measure patients. `roc` gives the ROC curve of a test, its area (AUC) with a 95 percent interval, the best threshold, and DeLong's comparison of two tests. `agreement` gives the Bland-Altman agreement of two methods and the intraclass correlations of several raters. `logistic` models the risk of an outcome from covariates. `proportions` measures a test from its two-by-two table, and compares the risks of two groups. `calibration` measures whether the risks of a model are right, and whether the model does more good than harm.

It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![The ROC curves of two synthetic markers, with the chance diagonal](out/roc.png)

`examples/roc.mojo` makes this picture. It uses 150 synthetic patients, 60 of them diseased, with two markers each. The blue curve is marker A, and the red curve is marker B. The gray diagonal is a test no better than chance.

Marker A has an AUC of 0.794, with a 95 percent interval from 0.723 to 0.865. Marker B has an AUC of 0.751, from 0.671 to 0.831. DeLong's test gives a difference of -0.043, with a p value of 0.28. Marker A at 0.9 or more has a sensitivity of 0.67 and a specificity of 0.81.

## Modules

| Module | What it gives |
|---|---|
| `roc` | `RocCurve`, `roc_curve`, `RocComparison`, `compare_roc` and `roc_image` |
| `agreement` | `BlandAltman`, `bland_altman`, `bland_altman_image`, `Icc`, `IccTable`, `intraclass_correlation` and `LIMIT_FACTOR` |
| `logistic` | `LogisticModel` and `logistic_regression` |
| `kappa` | `Kappa`, `cohens_kappa`, `linear_weighted_kappa`, `quadratic_weighted_kappa`, `FleissKappa`, `fleiss_kappa`, `MAX_CATEGORIES` and `MAX_SUBJECTS` |
| `rates` | `RateModel` and `poisson_regression`. Rates are per `YEAR64`, from `units.si` |
| `negbin` | `NegativeBinomialModel` and `negative_binomial_regression` |
| `calibration` | `brier_score`, `scaled_brier_score`, `RiskGroup`, `risk_groups`, `HosmerLemeshow`, `hosmer_lemeshow`, `CalibrationFit`, `calibration_fit`, `recalibrate`, `net_benefit`, `DecisionCurve`, `decision_curve`, `calibration_image`, `decision_curve_image`, `MAX_GROUPS` and `MAX_THRESHOLDS` |
| `proportions` | `Estimate`, `wilson_interval`, `exact_interval`, `DiagnosticAccuracy`, `diagnostic_accuracy`, `RiskComparison` and `compare_risks` |

## Make a ROC curve

A test gives each patient a score, such as the level of a marker or the output of a model. A threshold calls a patient diseased when the score is the threshold or more. A higher score must mean disease. For a marker that is low in disease, give its negative.

```mojo
from extensions.clinical.roc import roc_curve

var scores: List[Float64] = [3.0, 2.0, 2.0, 2.0, 1.0, 0.0]
var diseased: List[Bool] = [True, True, True, False, False, False]
var curve = roc_curve(scores, diseased)
print(curve.auc, curve.interval()[0], curve.interval()[1])
```

The curve holds one point for each threshold:

- `thresholds` falls from infinity, where no patient is called diseased, through each score once.
- `false_positive_rate` is the fraction of healthy patients called diseased.
- `sensitivity` is the fraction of diseased patients called diseased.

The specificity is `1 - false_positive_rate`.

## Read the AUC

The AUC is the area under the curve. It is also the chance that a diseased patient has a higher score than a healthy patient, with a tie counted as a half. 0.5 is no better than chance, and 1 is a perfect test.

`curve.standard_error` is the standard error of the AUC by the method of DeLong and others. `curve.interval()` gives the 95 percent interval, `AUC -+ 1.96 se`, held between 0 and 1.

The standard error uses the components of each patient. For a diseased patient, the component is the fraction of healthy patients below it. For a healthy patient, the component is the fraction of diseased patients above it. The module counts them from midranks, after Sun and Xu, so a curve takes time in proportion to `n log n`.

## Find a threshold

`curve.youden()` gives the threshold with the largest Youden index, `sensitivity + specificity - 1`. It returns the threshold, its sensitivity and its specificity. Of equal indices, it takes the highest threshold.

The Youden index weighs a missed disease and a false alarm the same. A screening test and a confirmatory test can need other thresholds.

## Compare two tests

`compare_roc(first, second, diseased)` compares the AUC of two tests on the same patients. It gives the difference, the second AUC less the first, with its standard error, z and two-sided p value. It uses the covariance of the two tests, because the same patients take both.

Two equal tests give a difference of 0, a z of 0 and a p value of 1.

## Draw the curves

`roc_image(curves, colors, size)` plots the curves on a white square. The false positive rate runs from 0 at the left edge to 1 at the right edge. The sensitivity runs from 0 at the bottom edge to 1 at the top edge. Light gray lines mark each tenth, and a darker gray diagonal marks a test no better than chance.

## Measure a test from its table

Compare a test with a yes or no result against a reference standard. That gives a two-by-two table of true and false positives, and true and false negatives. `diagnostic_accuracy(true_positive, false_positive, false_negative, true_negative)` gives its measures. Each is an `Estimate` with a `value` and a 95 percent interval from `lower` to `upper`:

- `sensitivity` and `specificity`.
- `positive_predictive` and `negative_predictive`, the fractions of positive and negative results that are right. They depend on the prevalence of the patients in the table.
- `accuracy` and `prevalence`.
- `positive_likelihood`, `sensitivity / (1 - specificity)`, and `negative_likelihood`, `(1 - sensitivity) / specificity`. A likelihood ratio multiplies the odds of disease before the test, to give the odds after it.

The proportions have the exact intervals of Clopper and Pearson. The likelihood ratios have log intervals, with a half added to each cell when one is 0.

`exact_interval(successes, trials)` and `wilson_interval(successes, trials)` give the interval of any proportion. The exact interval uses the beta quantiles. Wilson's score interval is narrower, and it stays inside 0 and 1.

## Compare the risks of two groups

`compare_risks(events_a, total_a, events_b, total_b)` compares the risk of an event in two groups, such as a treatment and a control. It gives:

- `first` and `second`, the two risks, with exact intervals.
- `difference`, the first risk less the second, with the Wald interval.
- `ratio` and `odds_ratio`, with log intervals.
- `number_needed`, `1 / |difference|`: the patients to treat for one event more or less. It is infinite when the risks are equal.

## Model the risk of an outcome

`logistic_regression(outcomes, covariates, tolerance, max_steps)` models the risk of a binary outcome, such as a disease, from covariates, such as the age or smoking. It takes the log odds of the outcome as `b0 + x . b`. `exp(b_i)` is the odds ratio of covariate `i`: the factor on the odds for each unit of that covariate, with the others held.

```mojo
from extensions.clinical.logistic import logistic_regression

var outcomes: List[Bool] = [True, False, True, False, False, True]
var rows: List[List[Float64]] = [[6.1], [4.2], [5.0], [5.3], [3.9], [6.6]]
var model = logistic_regression(outcomes, rows, 1e-10, 50)
print(model.odds_ratio(1), model.interval(1)[0], model.risk([5.5]))
```

Index 0 of the model is the intercept, and index `i + 1` is covariate `i`. The model gives:

- `coefficients` and `standard_errors`, from the inverse of the information matrix.
- `odds_ratio(i)` and `interval(i)`, the odds ratio and its 95 percent interval, `exp(b -+ 1.96 se)`.
- `z(i)` and `p_value(i)`, the Wald test of each coefficient.
- `likelihood_ratio()`, the test of the covariates against the intercept alone.
- `risk(row)`, the predicted risk of a patient. Give the risks of the patients to `roc_curve` to measure how well the model separates them.

The fit uses Newton steps from 0, as statsmodels does. When the steps run out first, `converged` is `False`. That occurs when a covariate separates the patients with the outcome from those without it.

## Model the rate of events

A cohort counts the events of each stratum, such as the cancers of smokers in their sixties, over its person-time. `poisson_regression(events, exposure, covariates, tolerance, max_steps)` takes the events, the person-time as durations, and one row of covariates for each stratum. It models the rate of a stratum as a baseline rate times `exp(x . b)`. `exp(b_i)` is the rate ratio of covariate `i`.

The fit uses the log of the person-time as the offset. It uses iteratively reweighted least squares from `mu = (y + mean(y)) / 2`, as statsmodels starts. The model gives:

- `rate_ratio(i)`, `interval(i)`, `z(i)` and `p_value(i)` for covariate `i`, with `i` from 1.
- `baseline_rate()`, the rate of a stratum with every covariate 0, and `rate(row)`, the fitted rate of a stratum. Rates are per year: `YEAR64` is the Julian year of 365.25 days.
- `deviance` and `dispersion`. A dispersion above 1 means more spread than Poisson counts have. Then use the negative binomial model.

## Model rates that spread more than Poisson counts

Events such as asthma attacks or falls cluster in some patients. Then the counts spread more than a Poisson model allows, and its standard errors are too small. The negative binomial model (NB2) takes the variance of a count as `mu + alpha mu^2`. With alpha 0, it is the Poisson model.

```mojo
from extensions.clinical.negbin import negative_binomial_regression

var model = negative_binomial_regression(events, exposure, covariates)
print(model.alpha, model.rates.rate_ratio(1), model.p_value())
```

`negative_binomial_regression(events, exposure, covariates)` takes the same strata as `poisson_regression`. It fits the coefficients and alpha by maximum likelihood:

1. For each alpha, iteratively reweighted least squares gives the coefficients, with the weights `mu / (1 + alpha mu)`.
2. A golden-section search finds the alpha of the largest profile likelihood, on a log scale from 1e-8 to 1e4.
3. Three Newton steps on the coefficients and `log(alpha)` together polish the maximum.

The `NegativeBinomialModel` gives:

- `rates`, a `RateModel` with the coefficients and their standard errors, from the observed information. Its rate ratios, intervals, tests and rates work as for the Poisson model. Its `deviance` is the negative binomial deviance, and its `dispersion` is Pearson's chi-square over its degrees of freedom.
- `alpha` and `alpha_error`.
- `log_likelihood` and `poisson_log_likelihood`. `likelihood_ratio()` and `p_value()` test that alpha is 0. Alpha 0 is on the edge of its range, so the p value is half the tail of chi-square with 1 degree of freedom.

The log-likelihood takes `lgamma(y + r) - lgamma(r)` and its derivatives, with `r = 1 / alpha`, as finite sums over each count. So it needs no digamma function. Counts that spread no more than Poisson counts have their largest likelihood at alpha 0, and the fit refuses them: use the Poisson model.

## Evaluate a risk model

A risk model gives each patient a risk of an outcome. The AUC says whether the patients with the outcome get higher risks. Calibration says whether the risks are right: of the patients with a risk of 20 percent, about 20 percent must have the outcome. A decision curve says whether the model does more good than harm when a risk above a threshold leads to a treatment.

![The calibration plot and the decision curve of an overfitted risk model and of the same model recalibrated](out/risk-model.png)

`examples/risk_model.mojo` makes this picture from 2000 synthetic patients. An overfitted model, in orange, gives risks that are too high and too far from the mean. Its calibration slope is 0.76, and it expects 1.20 times the events that occur. `recalibrate` corrects the risks, in blue, with the same AUC of 0.775. On the left, the groups of the overfitted model fall below the gray diagonal. On the right, the recalibrated model has more net benefit above a threshold of about 20 percent.

The example fits the recalibration on the same patients that it draws, so the recalibration looks too good. A study fits it on other patients.

```mojo
from extensions.clinical.calibration import calibration_fit, decision_curve, hosmer_lemeshow

var fit = calibration_fit(risks, outcomes)
print(fit.slope, fit.in_the_large, fit.expected_over_observed)
var test = hosmer_lemeshow(risks, outcomes, 10)
var curve = decision_curve(risks, outcomes, [0.05, 0.1, 0.2, 0.3])
```

Each risk must be between 0 and 1, and not at either end.

- `brier_score(risks, outcomes)` is the mean of `(risk - outcome)^2`, with an outcome of 1 or 0. `scaled_brier_score` is `1 - B / (s (1 - s))`, where `s (1 - s)` is the score of giving each patient the share `s`.
- `risk_groups(risks, outcomes, groups)` sorts the patients by risk into groups of near-equal size, as `numpy.array_split` does. Each `RiskGroup` gives its `count`, its `expected` events, which are the sum of its risks, and its `events`. `mean_risk()` and `observed()` give the two shares that a calibration plot draws.
- `hosmer_lemeshow(risks, outcomes, groups)` sums `(O - E)^2 / (E (1 - E / n))` over the groups, with `g - 2` degrees of freedom. Use 10 groups. A large cohort finds a small miscalibration, so look at the plot too.
- `calibration_fit(risks, outcomes)` fits the logistic model of the outcome on the logit of the risk. Its `slope` is 1 for right risks, and below 1 for risks too far from the mean, as an overfitted model gives. `in_the_large` is the intercept with the logit as an offset, below 0 for risks that are too high. `expected_over_observed` is the sum of the risks over the events.
- `recalibrate(risks, fit)` gives `1 / (1 + exp(-(a + b logit(risk))))`. It keeps the order of the risks, so it keeps the AUC.

`net_benefit(risks, outcomes, threshold)` treats each patient with a risk at the threshold or above, as dcurves does. The threshold is the risk at which a patient takes the harm of a treatment for the chance of its benefit. So a false positive weighs `t / (1 - t)` of a true positive:

    NB = TP / n - FP / n * t / (1 - t)

`decision_curve(risks, outcomes, thresholds)` gives the net benefit of the model and of treating all at each threshold. Treating none has a net benefit of 0. `avoided` gives the net treatments avoided for each patient, against treating all. A model is of use at the thresholds where its net benefit is above both other strategies.

`calibration_image(models, colors, size)` and `decision_curve_image(curves, colors, width, height)` draw them. The net benefit of a decision curve runs up to the prevalence, the most net benefit of any strategy. It runs down to a quarter of the prevalence below 0.

## Measure the agreement of two methods

![A Bland-Altman plot of two readers who measure 40 synthetic tumors](out/agreement.png)

`examples/agreement.mojo` makes this picture. Two readers measure the volumes of 40 synthetic tumors. Each cross is a tumor, with its mean volume across and the difference, reader A less reader B, up. The blue line is the bias, and the red lines are the limits of agreement. The gray line is 0.

Reader A reads 1.36 mL less than reader B, with a 95 percent interval from 0.92 to 1.79 mL less. The limits of agreement are -4.02 and 1.31 mL. The ICC(A,1) is 0.983, from 0.862 to 0.995.

`bland_altman(first, second)` takes the value of each subject by two methods. A value is a plain number in a unit that you choose, such as a volume in milliliters. The result gives:

- `bias`, the mean difference, the first method less the second.
- `deviation`, the sample standard deviation of the differences.
- `lower` and `upper`, the limits of agreement, `bias -+ 1.96 sd`. About 95 percent of the differences of new subjects fall between them.
- `bias_interval`, the 95 percent interval of the bias, from the t distribution.
- `lower_interval` and `upper_interval`, the 95 percent intervals of the limits. Each uses the approximate standard error `sqrt(3 sd^2 / n)` of Bland and Altman.

The limits do not say whether two methods agree well enough. Compare them with the difference that matters for the use of the measurement.

`bland_altman_image(first, second, result, width, height)` draws the plot. The mean runs across, with a margin of a tenth of its range. The difference runs from `-r` at the bottom edge to `r` at the top edge. Here `r` is 1.25 times the largest size of a difference or a limit.

## Measure the reliability of raters

`intraclass_correlation(ratings)` takes one row for each subject, with one rating by each rater. It gives the six intraclass correlations of Shrout and Fleiss, with the names of McGraw and Wong:

| Field | Name | What it measures |
|---|---|---|
| `one` | ICC(1,1) | One rating. Each subject has its own raters. |
| `agreement` | ICC(A,1) | One rating. The same raters, by absolute agreement. |
| `consistency` | ICC(C,1) | One rating. The same raters, by consistency: a constant shift of a rater does not count. |
| `one_average` | ICC(1,k) | The mean of the k ratings, by the model of ICC(1,1). |
| `agreement_average` | ICC(A,k) | The mean of the k ratings, by absolute agreement. |
| `consistency_average` | ICC(C,k) | The mean of the k ratings, by consistency. |

Each `Icc` gives the `value` and the F statistic `f` with its degrees of freedom `df1` and `df2`. It also gives the `p_value` of the test that the correlation is 0, and the 95 percent interval from `lower` to `upper`. The formulas are those of pingouin 0.7.0. The interval of ICC(A,1) uses the degrees of freedom of Satterthwaite, which are not whole numbers.

Use ICC(A,1) when two raters must give the same value, as for a radiomics feature that must be the same for each reader. Use ICC(C,1) when only the order of the subjects counts.

## Measure the agreement of raters on categories

Two raters, such as two radiologists, put each subject in one of k categories. Their table holds the subjects that rater A put in category i, by row, and rater B in category j, by column. Kappa is the agreement beyond the agreement that chance gives: 1 for full agreement, 0 for chance agreement, and below 0 for less than chance.

- `cohens_kappa(table)` counts exact agreement only, `(p_o - p_e) / (1 - p_e)`.
- `linear_weighted_kappa(table)` and `quadratic_weighted_kappa(table)` give part credit to near categories, for ordered categories such as grades. The agreement weight of categories i and j is `1 - |i - j| / (k - 1)`, or `1 - ((i - j) / (k - 1))^2`.

Each gives a `Kappa` with the `value`, its `standard_error`, and the 95 percent interval from `lower` to `upper`. It also gives the test that kappa is 0: the `null_error`, z and the two-sided `p_value`. The errors are the large-sample errors of Fleiss, Cohen and Everitt, as statsmodels gives them.

Fleiss' kappa measures the agreement of more than two raters, such as six pathologists who grade each slide. `fleiss_kappa(table)` takes one row for each subject, of the number of raters who put it in each category. Each subject must have the same number of ratings, 2 or more. A rater can be another person for each subject.

```mojo
from extensions.clinical.kappa import fleiss_kappa

var result = fleiss_kappa([[0, 0, 0, 0, 14], [0, 2, 6, 4, 2], [0, 0, 3, 5, 6]])
print(result.value, result.p_value, result.categories[4])
```

The `FleissKappa` gives:

- `value`, `(P - Pe) / (1 - Pe)`. P is the mean share of rater pairs that agree on a subject, and Pe is the sum of the squares of the category shares.
- `null_error`, the standard error when the agreement is chance only, by Fleiss, Nee and Landis (1979). `z` and the two-sided `p_value` test that kappa is 0, as R's `irr::kappam.fleiss` gives them.
- `free_marginal`, Randolph's kappa, which takes chance agreement as 1 over the categories.
- `categories`, the kappa of each category, by Fleiss (1971). A category that no rater chose has no kappa, and gives not a number.

With two raters, Fleiss' kappa is Scott's pi, not Cohen's kappa.

## Use the t and F distributions

The intervals and the tests take the t, F, beta and normal distributions from `distributions` of the [Numerics](Numerics#use-statistical-distributions) extension.

## Verification

The tests compare the module with scikit-learn 1.9.1 and MLstatkit 0.1.91 on two synthetic markers of 150 patients. Marker A has one decimal, so many of its scores tie. `tools/make_roc.mojo` writes the markers, and `assets/roc/make_roc.py` writes the expected values.

- Each point of the curve of marker A is the same as the point of `roc_curve` of scikit-learn.
- The AUC of each marker agrees with `roc_auc_score` to a relative 1e-15.
- The ends of the interval of each AUC agree with MLstatkit to a relative 1e-13.
- DeLong's z and the standard error of the difference agree to a relative 1e-12. The p value agrees to a relative 1e-11.
- The threshold, sensitivity and specificity of the largest Youden index are the same as numpy finds on the curve.

The tests compare `agreement` and the [distributions](Numerics#use-statistical-distributions) with pingouin 0.7.0 and scipy 1.18.1. `assets/agreement/make_agreement.py` writes the expected values and 40 synthetic pairs of tumor volumes.

- The six ICC of table 2 of Shrout and Fleiss and of the two readers agree with pingouin to a relative 1e-12. Their F statistics agree to 1e-12, and their p values and interval ends to 1e-10. pingouin rounds its intervals to two decimals. So the script finds the ends with its formulas and scipy, and checks that they round to the ends of pingouin.
- The six ICC of Shrout and Fleiss are their published values to two decimals: 0.17, 0.29, 0.71, 0.44, 0.62 and 0.91.
- The bias, deviation and limits of the two readers agree with numpy to a relative 1e-13. Their intervals agree to 1e-12.
- The upper tail and the 0.975 quantile of t and F agree with scipy to a relative 1e-12. The cases have whole and real degrees of freedom.

The tests compare `logistic` with the `Logit` model of statsmodels 0.15.0 on a synthetic cohort of 200 patients with three covariates. `tools/make_logistic.mojo` writes the cohort, and `assets/logistic/make_logistic.py` writes the expected values.

- The coefficients, standard errors, z values and interval ends agree to a relative 1e-12. The p values agree to 1e-10.
- The log-likelihoods agree to a relative 1e-14, and the likelihood ratio statistic to 1e-12.
- The predicted risks of three patients agree to a relative 1e-12.

statsmodels fits its own null model with a looser tolerance, which leaves its null log-likelihood 2e-8 below the maximum. So the script fits the null model to 1e-12 too, and then the null log-likelihood agrees exactly.

The tests compare `proportions` with statsmodels 0.15.0. `assets/proportions/make_proportions.py` writes the expected values.

- Wilson's interval agrees with `proportion_confint` to a relative 1e-13, and the exact interval to 1e-12. The cases include no success, all successes and one trial.
- The six proportions of a test of 90, 30, 10 and 170 patients, and their exact intervals, agree to 1e-12. Its likelihood ratios and their intervals agree with `Table2x2` to 1e-12.
- The risk difference of 30 of 100 against 15 of 100 agrees with the Wald interval of `confint_proportions_2indep`. Its risk ratio and odds ratio agree with `Table2x2`, all to 1e-12.

The tests compare `rates` with the Poisson `GLM` of statsmodels 0.15.0, with an offset, on 48 synthetic strata. `tools/make_rates.mojo` writes them, and `assets/rates/make_rates.py` writes the expected values. The coefficients agree to a relative 1e-12. The standard errors, z values, interval ends, deviance, dispersion and rates agree to 1e-11.

The tests compare `negbin` with the `NegativeBinomial` model of statsmodels 0.15.0 on 120 synthetic strata of gamma-Poisson counts, with alpha near 0.5. `tools/make_rates.mojo` writes them, and `assets/rates/make_negbin.py` writes the expected values. The coefficients and alpha agree to a relative 1e-10, and their errors to 1e-9. The log-likelihoods agree to 1e-12, and the likelihood ratio to 1e-11. The deviance and the dispersion agree with statsmodels' `GLM` at the fitted alpha to 1e-9 and 1e-8.

The tests compare `kappa` with `cohens_kappa` of statsmodels 0.15.0. The tables are four grades of 120 synthetic films, by each weighting, and two categories of 60 smears. `assets/agreement/make_kappa.py` writes them. Kappa agrees to a relative 1e-14, and its errors and interval ends to 1e-12.

The tests compare `fleiss_kappa` with `fleiss_kappa` of statsmodels 0.15.0 on two tables. One is the example of 10 subjects and 14 raters on the Wikipedia page of Fleiss' kappa, with a kappa of 0.210. The other has 40 synthetic films and 6 readers. `assets/agreement/make_fleiss.py` writes them. Kappa and Randolph's kappa agree to a relative 1e-14. The null error, z and the category kappas agree with their formulas in numpy to 1e-13, and the p value with scipy to 1e-10.

The tests compare `calibration` with scikit-learn 1.9.1, statsmodels 0.15.0 and dcurves 1.1.7 on 300 synthetic patients. `tools/make_calibration.mojo` writes them, and `assets/calibration/make_calibration.py` writes the expected values.

- The Brier score agrees with `brier_score_loss` to a relative 1e-14. The scaled score agrees with `1 - B / (p (1 - p))` of that score to 1e-13, and the E/O with the sum of the risks over the events to 1e-14.
- The calibration intercept, the slope and their errors agree with the `Logit` model of statsmodels to 1e-11. The calibration in the large and its error agree with its binomial `GLM` with an offset to 1e-12.
- At 32 thresholds, the net benefit of the model differs from that of dcurves by 1e-15 or less. Treating all differs by 1e-14 or less, and the treatments avoided by 1e-12 or less.

The tests also check cases by hand:

- Three diseased scores of 3, 2 and 2 against healthy scores of 2, 1 and 0 give an AUC of 8/9. The standard error is from the variances 1/108 and 1/27 of the components. The best threshold is 2.
- A perfect test has an AUC of 1 and a standard error of 0. A test of ties has an AUC of a half.
- A test against itself gives a p value of 1. A perfect test against a reversed one has a difference with no variance, and the comparison refuses it.
- A perfect curve runs up the left edge and along the top edge of its plot.
- The beta tails of `I_x(1, 1) = x`, `I_x(3, 1) = x^3` and `I_x(1, 2) = 1 - (1 - x)^2` are exact. Student's t with 1 degree of freedom is Cauchy's, and with 2 degrees it has a closed form. F with 2 and 2 degrees has the tail `1 / (1 + x)`.
- Differences of 1, 0, 1 and 0 give a bias of 1/2 and a deviation of `sqrt(1/3)`. Their plot has the bias and the zero line in the right rows.
- Two raters who differ by a constant leave no residual, and the ICC refuses them.
- A two-by-two table of 10 and 20 exposed patients, and 5 and 40 others, gives an odds ratio of 4. Its standard error is Woolf's `sqrt(1/10 + 1/20 + 1/5 + 1/40)`. The intercept is the log odds 5/40.
- A covariate that separates the outcomes does not converge.
- Events of 10 in 100 person-years against 20 in 50 give a rate ratio of 4 and a baseline rate of 0.1 a year. The log of the ratio has the standard error `sqrt(1/10 + 1/20)`.
- Full agreement gives a kappa of 1 with no error. Equal cells give a kappa of 0 and a p value of 1. With two categories, the weighted kappas are the simple one. Systematic disagreement gives a kappa below 0.
- Full agreement of many raters gives a Fleiss' kappa of 1, in each category too. Raters who split each subject evenly give -1. A category that no rater chose has no kappa.
- With no success in 20 trials, the exact high end is `1 - 0.025^(1/20)`. The beta quantile of Beta(2, 1) is the square root, on both sides of a half.
- The likelihood ratios of the test are 6 and 0.1 / 0.85. With no false positive, a half is added to each cell.
- Equal risks need an infinite number to treat.
- A negative binomial model of one flag fits the mean of each group. Counts with means of 4 and 12 a year give a rate ratio of 3. Counts that spread less than Poisson counts are refused.
- Risks of 0.2 and 0.8, for outcomes of 0 and 1, give a Brier score of 0.04, scaled to 0.84.
- Seven patients make groups of 3, 2 and 2, and patients of equal risk keep their order. Their Hosmer-Lemeshow statistic is `1/3 + 0 + 6/7 = 25/21` on one degree of freedom, with the p value `erfc(sqrt(25/42))`. Groups whose events are what the model expects give a statistic of 0 and a p value of 1.
- No library gives the groups of risk or the Hosmer-Lemeshow test, so the tests check them by hand only.
- Risks of 0.25 and 0.75, with a quarter and three quarters of events, are right. They give a slope of 1, intercepts of 0 and an E/O of 1, and recalibration changes no risk.
- At a threshold of 0.3, two true positives and one false positive of four patients give a net benefit of `1/2 - 1/4 * 3/7`.
- The calibration plot and the decision curve have their groups, curves, lines and frame in the right pixels.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| The scores are not one finite value for each patient | `roc_curve`, `compare_roc` |
| There are fewer than two diseased or two healthy patients | `roc_curve`, `compare_roc` |
| The difference of two AUCs is not 0 and has no variance | `compare_roc` |
| A curve has no point | `RocCurve.youden` |
| The methods do not give one finite value each for two subjects or more | `bland_altman`, `bland_altman_image` |
| The result is not that of the data, the means or the differences do not vary, or a side is out of 64 to 4096 pixels | `bland_altman_image` |
| The ratings are not a finite table of two subjects and two raters or more, or they have no residual variation | `intraclass_correlation` |
| A proportion has no trial, or successes out of range | `wilson_interval`, `exact_interval`, `compare_risks` |
| The strata are not one count of 0 or more, positive person-time and one finite row each, with an event in all and more strata than coefficients, or the tolerance or the steps are out of range | `poisson_regression` |
| A covariate is constant or collinear with others, or an index names no covariate | `poisson_regression`, `RateModel` |
| The strata are not valid, as for `poisson_regression`, the counts spread no more than Poisson counts, or the information is not positive definite at the maximum | `negative_binomial_regression` |
| A kappa table is not square, has not 2 to 100 categories, has a count below 0 or no subject, or its raters agree by chance alone | `kappa` |
| A table of many raters has not 1 to 100000 subjects of 2 to 100 categories, a count below 0, not one number of ratings of 2 or more, or every rating in one category | `fleiss_kappa` |
| A cell of a diagnostic table is negative, or the table has no diseased, healthy, positive or negative patient | `diagnostic_accuracy` |
| The covariates are not one finite row of 1 to 32 values for each patient, all outcomes are the same, the tolerance is not between 0 and 1, or the steps are not from 1 to 1000 | `logistic_regression` |
| The information matrix is not positive definite, because a covariate is constant, is collinear with others, or separates the outcomes | `logistic_regression` |
| An index names no coefficient, or a row does not have one finite value for each covariate | `LogisticModel` |
| There is no curve, the colors are not one for each curve, or the side is out of 64 to 4096 pixels | `roc_image` |
| A risk is not between 0 and 1, or there is not one risk for each outcome | `calibration` |
| The outcomes are all the same | `scaled_brier_score`, `calibration_fit` |
| There are not 2 to 100 groups and no more than the patients, or fewer than 3 groups for a test | `risk_groups`, `hosmer_lemeshow` |
| The logits of the risks are all equal or separate the outcomes | `calibration_fit` |
| The intercept or the slope is not finite | `recalibrate` |
| A threshold is not between 0 and 1, there are not 2 to 1000 rising thresholds, or no patient has the outcome | `net_benefit`, `decision_curve` |
| There is no model, the colors are not one for each, a model has no group, the curves do not share thresholds and patients, or a side is out of 64 to 4096 pixels | `calibration_image`, `decision_curve_image` |

## Limits

- The interval and the test use the normal approximation. With few patients, or an AUC near 0 or 1, they are rough.
- The comparison takes two tests on the same patients. Two tests on different patients need another test.
- The module gives no partial AUC, no smoothed curve and no bootstrap.
- An AUC does not show how a test changes care. A threshold must suit the use of the test.
- Bland-Altman takes the differences as normal, with no trend in the mean. When the difference grows with the size, plot ratios or logarithms.
- The ICC needs a complete table, with each rating present. It uses an analysis of variance, not a mixed model.
- A p value below about 1e-307 is given as 0.
- The logistic model has no penalty, so a covariate that separates the outcomes has no finite estimate. It adds no interaction or curve that the caller does not add as a covariate.
- Groups of risk split patients of equal risk by their order, so a tool that keeps ties together can give other groups. The Hosmer-Lemeshow test changes with the number of groups.
- Calibration and net benefit are those of the patients given. Measure a model on patients other than those it was fitted on.
- A decision curve takes one threshold for all patients, and no harm other than the harm that the threshold implies.

## References

- Hanley and McNeil, "The meaning and use of the area under a receiver operating characteristic (ROC) curve", Radiology, 1982.
- DeLong, DeLong and Clarke-Pearson, "Comparing the areas under two or more correlated receiver operating characteristic curves: a nonparametric approach", Biometrics, 1988.
- Sun and Xu, "Fast implementation of DeLong's algorithm for comparing the areas under correlated receiver operating characteristic curves", IEEE Signal Processing Letters, 2014.
- Youden, "Index for rating diagnostic tests", Cancer, 1950.
- Bland and Altman, "Statistical methods for assessing agreement between two methods of clinical measurement", The Lancet, 1986.
- Bland and Altman, "Measuring agreement in method comparison studies", Statistical Methods in Medical Research, 1999.
- Shrout and Fleiss, "Intraclass correlations: uses in assessing rater reliability", Psychological Bulletin, 1979.
- Brier, "Verification of forecasts expressed in terms of probability", Monthly Weather Review, 1950.
- Hosmer, Lemeshow and Sturdivant, "Applied Logistic Regression", third edition, Wiley, 2013.
- Van Calster and others, "Calibration: the Achilles heel of predictive analytics", BMC Medicine, 2019.
- Vickers and Elkin, "Decision curve analysis: a novel method for evaluating prediction models", Medical Decision Making, 2006.
- McGraw and Wong, "Forming inferences about some intraclass correlation coefficients", Psychological Methods, 1996.
- Koo and Li, "A guideline of selecting and reporting intraclass correlation coefficients for reliability research", Journal of Chiropractic Medicine, 2016.
- Breslow and Day, "Statistical Methods in Cancer Research, Volume II: The Design and Analysis of Cohort Studies", 1987.
- Cohen, "A coefficient of agreement for nominal scales", Educational and Psychological Measurement, 1960.
- Fleiss, Cohen and Everitt, "Large sample standard errors of kappa and weighted kappa", Psychological Bulletin, 1969.
- Fleiss, "Measuring nominal scale agreement among many raters", Psychological Bulletin, 1971.
- Fleiss, Nee and Landis, "Large sample variance of kappa in the case of different sets of raters", Psychological Bulletin, 1979.
- Randolph, "Free-marginal multirater kappa (multirater K[free]): an alternative to Fleiss' fixed-marginal multirater kappa", Joensuu Learning and Instruction Symposium, 2005.
- Clopper and Pearson, "The use of confidence or fiducial limits illustrated in the case of the binomial", Biometrika, 1934.
- Wilson, "Probable inference, the law of succession, and statistical inference", Journal of the American Statistical Association, 1927.
- Simel, Samsa and Matchar, "Likelihood ratios with confidence: sample size estimation for diagnostic test studies", Journal of Clinical Epidemiology, 1991.
- Laupacis, Sackett and Roberts, "An assessment of clinically useful measures of the consequences of treatment", New England Journal of Medicine, 1988.
- Hosmer, Lemeshow and Sturdivant, "Applied Logistic Regression", 3rd edition, 2013.
- Woolf, "On estimating the relation between blood group and disease", Annals of Human Genetics, 1955.
- Press and others, "Numerical Recipes", 3rd edition, 2007, section 6.4.
- Robin and others, "pROC: an open-source package for R and S+ to analyze and compare ROC curves", BMC Bioinformatics, 2011.
