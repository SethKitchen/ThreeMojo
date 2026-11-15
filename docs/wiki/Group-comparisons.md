# Group comparisons

`extensions/clinical/hypothesis.mojo` compares two groups, or the two values of pairs, by two-sided tests. It gives Student's, Welch's and the paired t test, with the interval of the difference of the means. It gives the Mann-Whitney U test and the Wilcoxon signed-rank test, which use ranks. `tables.mojo` tests tables of counts by Fisher's exact test, chi-square and McNemar's test. `multiple.mojo` adjusts p values for many tests.

`correlation.mojo` measures how two measures of the same subjects rise together. `anova.mojo` tests several groups at once. The results match scipy and statsmodels.

It is a library for research and teaching. Its results are not validated for a decision about the care of a patient.

## Modules

| Module | What it gives |
|---|---|
| `hypothesis` | `TTest`, `student_t_test`, `welch_t_test`, `paired_t_test`, `RankTest`, `mann_whitney`, `wilcoxon` and `midranks` |
| `tables` | `FisherTest`, `fisher_exact`, `TableTest`, `chi_square_test`, `yates_chi_square_test`, `mcnemar_exact`, `mcnemar_chi_square` and `MAX_SIDE` |
| `multiple` | `bonferroni`, `holm`, `benjamini_hochberg` and `benjamini_yekutieli` |
| `correlation` | `Correlation`, `pearson`, `spearman` and `kendall` |
| `anova` | `GroupsTest`, `one_way_anova`, `kruskal_wallis` and `MAX_GROUPS` |

## Choose a test

| Data | Test |
|---|---|
| Two groups, values near normal, equal spread | `student_t_test` |
| Two groups, values near normal | `welch_t_test` |
| Two groups, any shape, or ranks only | `mann_whitney` |
| Pairs, differences near normal | `paired_t_test` |
| Pairs, any shape | `wilcoxon` |
| Three groups or more, values near normal | `one_way_anova` |
| Three groups or more, any shape | `kruskal_wallis` |
| A two-by-two table of counts | `fisher_exact` |
| A larger table of counts | `chi_square_test` |
| Paired yes or no results | `mcnemar_exact` |

Welch's test does not need equal spreads, and it loses little when they are equal. Use it when you are not sure.

A value is a plain number in a unit that you choose, such as a blood pressure in mmHg. A difference is in that unit.

## Compare means

`student_t_test(first, second)`, `welch_t_test(first, second)` and `paired_t_test(first, second)` give a `TTest`:

- `statistic`, the t value: the difference over its standard error.
- `freedom`, the degrees of freedom. Student's test has `n1 + n2 - 2`, and Welch's test has the degrees of Welch and Satterthwaite, which are not whole numbers.
- `p_value`, two-sided.
- `difference`, first less second, with its 95 percent interval from `lower` to `upper`.

```mojo
from extensions.clinical.hypothesis import welch_t_test

var treated: List[Float64] = [12.0, 11.0, 3.0, 9.0, 7.0, 14.0]
var control: List[Float64] = [7.0, 7.0, 16.0, -1.0, 8.0, 0.0]
var test = welch_t_test(treated, control)
print(test.difference, test.lower, test.upper, test.p_value)
```

The paired test takes the two values of each pair, such as before and after a treatment, in the same order. It tests the mean of the differences.

## Compare by ranks

`mann_whitney(first, second)` and `wilcoxon(first, second)` give a `RankTest` with the `statistic`, its standardized `z`, and the two-sided `p_value`. They use the normal approximation, which suits about ten values a group or more.

- The Mann-Whitney statistic is U of the first group: the pairs in which its value is higher, with a tie counted as a half. The variance has the tie correction, and z moves a half toward 0, the continuity correction.
- The Wilcoxon statistic is the smaller of the sums of the ranks of the positive and the negative differences. Zero differences drop out, and the variance has the tie correction. There is no continuity correction.

`midranks(values)` gives the rank of each value from 1. Tied values take their mean rank.

## Compare several groups

`one_way_anova(groups)` and `kruskal_wallis(groups)` take the values of each group, and test whether any group differs. Each gives a `GroupsTest` with the `statistic`, the degrees of freedom `freedom` and `residual`, and the `p_value`.

- The one-way analysis of variance gives F: the variance between the group means over the variance within the groups. F has `k - 1` and `n - k` degrees of freedom. With two groups, F is the square of Student's t.
- The Kruskal-Wallis test gives H from the ranks of all the values, with the tie correction, against chi-square with `k - 1` degrees of freedom.

A test that finds a difference does not say which groups differ. Compare the pairs next, and correct their p values for many tests.

## Test a table of counts

`fisher_exact(a, b, c, d)` tests a two-by-two table with the rows (a, b) and (c, d), such as cured and not cured with a treatment and without it. It gives the `odds_ratio`, `a d / (b c)`, and the two-sided `p_value`. The p value is the chance of the tables with the same margins that are no more likely than this one. The test is exact for any counts, small or large.

The probabilities come from the ratio of each table to the next, from the most likely table, so they need no factorials. A table counts as no more likely within a relative 1e-7, as R counts it. When a margin is 0, the odds ratio is not a number and the p value is 1.

`chi_square_test(table)` tests whether the rows and the columns of a table are independent. It gives `sum((O - E)^2 / E)` with `(r - 1)(c - 1)` degrees of freedom, with no continuity correction. Each expected count E must be about 5 or more for the approximation to hold. `yates_chi_square_test(a, b, c, d)` tests a two-by-two table with Yates's correction: each count moves a half toward its expected count.

## Test paired yes or no results

McNemar's test compares paired results, such as two tests on each patient. Only the discordant pairs count: `b` pairs with yes first and no second, and `c` pairs with no first and yes second.

- `mcnemar_exact(b, c)` gives the exact two-sided p value from the binomial distribution, `min(1, 2 P(X <= min(b, c)))`.
- `mcnemar_chi_square(b, c)` gives `(|b - c| - 1)^2 / (b + c)` with 1 degree of freedom, as statsmodels gives it.

## Measure a correlation

A correlation runs from -1 to 1. It is 1 when one measure rises with the other, -1 when it falls, and 0 when there is no relation of that kind. Each function takes two measures of the same subjects, in the same order, and gives a `Correlation` with the `value` and its two-sided `p_value`.

- `pearson(x, y)` gives Pearson's r of a straight-line relation. It also gives the 95 percent interval from `lower` to `upper` by Fisher's z, `tanh(atanh(r) -+ 1.96 / sqrt(n - 3))`. It needs 4 pairs or more.
- `spearman(x, y)` gives Spearman's rho: r of the midranks. It measures a relation that only rises or only falls, of any shape.
- `kendall(x, y)` gives Kendall's tau-b: the concordant pairs less the discordant pairs, over the pairs, with a correction for ties. Its p value comes from the normal approximation with the tie-corrected variance. It compares each pair of subjects, so a large sample is slow.

The p value of r and of rho is `2 I_((1 - |r|) / 2)(n/2 - 1, n/2 - 1)`, from the beta distribution, as scipy computes it. A correlation does not show that one measure causes the other.

## Correct for many tests

With many tests, such as one for each of 50 biomarkers, some find an effect by chance. An adjusted p value corrects for the count of tests. A test rejects at a level, such as 0.05, when its adjusted p value is at or below that level. Each function takes the p values and returns the adjusted values in the same order.

- `bonferroni(p)` gives `min(1, m p)`.
- `holm(p)` multiplies the k-th least p value by `m - k + 1`, and holds each adjusted value at least as large as the one before it. It rejects at least what Bonferroni's method rejects.
- `benjamini_hochberg(p)` multiplies the k-th least p value by `m / k`, and holds each adjusted value at most as large as the one after it.
- `benjamini_yekutieli(p)` multiplies those of Benjamini and Hochberg by `sum(1 / k)`.

Bonferroni's and Holm's methods control the chance of any false finding. The methods of Benjamini control the expected share of false findings among the findings. Benjamini and Hochberg's method takes the tests as independent or positively dependent, and Benjamini and Yekutieli's method takes any dependence.

## Verification

The tests compare the module with scipy 1.18.1 on synthetic falls of blood pressure in whole mmHg, so that many tie. `assets/hypothesis/make_hypothesis.py` writes the data and the expected values.

- t and the degrees of freedom of `ttest_ind` and `ttest_rel` agree to a relative 1e-13. The p values agree to 1e-11, and the interval ends to 1e-12.
- U of `mannwhitneyu` is the same, and its p value agrees to 1e-12.
- The statistic of `wilcoxon` is the same, its z agrees to 1e-13, and its p value to 1e-11.

The tests compare `tables` with scipy 1.18.1 and statsmodels 0.15.0. `assets/hypothesis/make_tables.py` writes the expected values.

- The odds ratios of `fisher_exact` are the same, and the p values agree to a relative 1e-12. The tables include a cell of 0, a symmetric table with a p value of 1, and a table of 1000.
- The statistics of `chi2_contingency` agree to 1e-13 with and without Yates's correction, and the p values to 1e-11.
- The exact p values of statsmodels' `mcnemar` agree to 1e-12, and the chi-square form to 1e-11.

The tests take 30 synthetic pairs of glucose and HbA1c with ties. Their correlations agree with scipy's `pearsonr`, `spearmanr` and `kendalltau` to a relative 1e-14. The p values agree to 1e-11, and Pearson's interval to 1e-13. `assets/hypothesis/make_correlation.py` writes them.

F and H of three synthetic groups agree with scipy's `f_oneway` and `kruskal` to a relative 1e-13, and their p values to 1e-10 and 1e-11. `assets/hypothesis/make_anova.py` writes them.

The adjusted p values of 12 p values, with a tie, agree with statsmodels' `multipletests` to a relative 1e-15 by each method. `assets/hypothesis/make_multiple.py` writes them.

The tests also check cases by hand:

- The ranks of 20, 10, 20 and 30 are 2.5, 1, 2.5 and 4.
- Groups of 1, 2, 3 and 4, 5, 6 give t = `-3 / sqrt(2/3)` on 4 degrees of freedom by both t tests.
- Two groups apart give U = 0. A U at its mean gives z = 0 and p = 1.
- Pairs with two zero differences drop them, and the rest give the signed rank sum 3.
- The most extreme table of three and three has a p value of 2 / 20. A table with a margin of 0 has a p value of 1.
- With two groups, F is the square of Student's t, with the same p value. Groups of equal means give F = 0. The ranks 1 and 2 against 3 and 4 give H = 2.4.
- A straight line has r = 1, a p value of 0 and an interval of no width. A cube that only rises has rho = 1. Two concordant pairs and one discordant pair give tau = 1/3. A negated measure mirrors r and its interval.
- The p values 0.01, 0.04 and 0.03 become 0.03, 0.06 and 0.06 by Holm's method, and 0.03, 0.04 and 0.04 by Benjamini and Hochberg's.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A group has fewer than two values, or a value is not finite | t tests, `wilcoxon` |
| The values or the differences do not vary | t tests |
| The paired lists differ in length | `paired_t_test`, `wilcoxon` |
| A group is empty, or all the values tie | `mann_whitney` |
| Every difference is 0 | `wilcoxon` |
| A cell is below 0 | `tables` |
| A table is not a rectangle of 2 to 100 rows and columns, or a row or a column sums to 0 | `chi_square_test`, `yates_chi_square_test` |
| There is no discordant pair | `mcnemar_chi_square` |
| There is no p value, or one is not from 0 to 1 | `multiple` |
| There are not 2 to 1000 groups, a group is empty, a value is not finite, there are no more values than groups, or no group varies | `anova` |
| The measures differ in length, have too few pairs or a value that is not finite, or a measure does not vary | `correlation` |

## Limits

- The tests are two-sided. The module has no one-sided tests, no exact rank tests for small groups, and no analysis of variance of more than one factor.
- A p value is for one test. Many tests on one data set need a correction, such as those of `multiple`.
- A test that finds no difference does not show that the groups are the same.

## References

- Student, "The probable error of a mean", Biometrika, 1908.
- Welch, "The generalization of Student's problem when several different population variances are involved", Biometrika, 1947.
- Mann and Whitney, "On a test of whether one of two random variables is stochastically larger than the other", Annals of Mathematical Statistics, 1947.
- Wilcoxon, "Individual comparisons by ranking methods", Biometrics Bulletin, 1945.
- Fisher, "On the interpretation of chi-square from contingency tables, and the calculation of P", Journal of the Royal Statistical Society, 1922.
- Yates, "Contingency tables involving small numbers and the chi-square test", Supplement to the Journal of the Royal Statistical Society, 1934.
- Fisher, "Statistical Methods for Research Workers", 1925.
- Kruskal and Wallis, "Use of ranks in one-criterion variance analysis", Journal of the American Statistical Association, 1952.
- Pearson, "Notes on the history of correlation", Biometrika, 1920.
- Spearman, "The proof and measurement of association between two things", American Journal of Psychology, 1904.
- Kendall, "The treatment of ties in ranking problems", Biometrika, 1945.
- Holm, "A simple sequentially rejective multiple test procedure", Scandinavian Journal of Statistics, 1979.
- Benjamini and Hochberg, "Controlling the false discovery rate", Journal of the Royal Statistical Society, Series B, 1995.
- Benjamini and Yekutieli, "The control of the false discovery rate in multiple testing under dependency", Annals of Statistics, 2001.
- McNemar, "Note on the sampling error of the difference between correlated proportions or percentages", Psychometrika, 1947.
- Virtanen and others, "SciPy 1.0: fundamental algorithms for scientific computing in Python", Nature Methods, 2020.
