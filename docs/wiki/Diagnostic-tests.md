# Diagnostic tests

`extensions/clinical/roc.mojo` measures how well a diagnostic test separates diseased patients from healthy ones. It gives the ROC curve of a test, its area (AUC) with a 95 percent interval, and the threshold with the largest Youden index. It compares the AUC of two tests on the same patients by DeLong's test, and it plots the curves. It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

![The ROC curves of two synthetic markers, with the chance diagonal](out/roc.png)

`examples/roc.mojo` makes this picture. It uses 150 synthetic patients, 60 of them diseased, with two markers each. The blue curve is marker A, and the red curve is marker B. The gray diagonal is a test no better than chance.

Marker A has an AUC of 0.820, with a 95 percent interval from 0.751 to 0.890. Marker B has an AUC of 0.735, from 0.654 to 0.817. DeLong's test gives a difference of -0.085, with a p value of 0.014. Marker A at 0.6 or more has a sensitivity of 0.77 and a specificity of 0.74.

## Modules

| Module | What it gives |
|---|---|
| `roc` | `RocCurve`, `roc_curve`, `RocComparison`, `compare_roc` and `roc_image` |

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

## Verification

The tests compare the module with scikit-learn 1.9.1 and MLstatkit 0.1.91 on two synthetic markers of 150 patients. Marker A has one decimal, so many of its scores tie. `assets/roc/make_roc.py` writes the markers and the expected values.

- Each point of the curve of marker A is the same as the point of `roc_curve` of scikit-learn.
- The AUC of each marker agrees with `roc_auc_score` to a relative 1e-15.
- The ends of the interval of each AUC agree with MLstatkit to a relative 1e-13.
- DeLong's z and the standard error of the difference agree to a relative 1e-12. The p value agrees to a relative 1e-11.
- The threshold, sensitivity and specificity of the largest Youden index are the same as numpy finds on the curve.

The tests also check cases by hand:

- Three diseased scores of 3, 2 and 2 against healthy scores of 2, 1 and 0 give an AUC of 8/9. The standard error is from the variances 1/108 and 1/27 of the components. The best threshold is 2.
- A perfect test has an AUC of 1 and a standard error of 0. A test of ties has an AUC of a half.
- A test against itself gives a p value of 1. A perfect test against a reversed one has a difference with no variance, and the comparison refuses it.
- A perfect curve runs up the left edge and along the top edge of its plot.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| The scores are not one finite value for each patient | `roc_curve`, `compare_roc` |
| There are fewer than two diseased or two healthy patients | `roc_curve`, `compare_roc` |
| The difference of two AUCs is not 0 and has no variance | `compare_roc` |
| A curve has no point | `RocCurve.youden` |
| There is no curve, the colors are not one for each curve, or the side is out of 64 to 4096 pixels | `roc_image` |

## Limits

- The interval and the test use the normal approximation. With few patients, or an AUC near 0 or 1, they are rough.
- The comparison takes two tests on the same patients. Two tests on different patients need another test.
- The module gives no partial AUC, no smoothed curve and no bootstrap.
- An AUC does not show how a test changes care. A threshold must suit the use of the test.

## References

- Hanley and McNeil, "The meaning and use of the area under a receiver operating characteristic (ROC) curve", Radiology, 1982.
- DeLong, DeLong and Clarke-Pearson, "Comparing the areas under two or more correlated receiver operating characteristic curves: a nonparametric approach", Biometrics, 1988.
- Sun and Xu, "Fast implementation of DeLong's algorithm for comparing the areas under correlated receiver operating characteristic curves", IEEE Signal Processing Letters, 2014.
- Youden, "Index for rating diagnostic tests", Cancer, 1950.
- Robin and others, "pROC: an open-source package for R and S+ to analyze and compare ROC curves", BMC Bioinformatics, 2011.
