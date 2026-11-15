# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear regression by least squares, as statsmodels' `OLS` gives it.

The model takes an outcome, such as a blood pressure, as `b0 + x . b`
plus a normal error. Here `x` holds the covariates of a subject, such as
the age. `b_i` is the change of the outcome for each unit of covariate
`i`, with the others held.

`linear_regression` solves the normal equations of the covariates less
their means, by Cholesky's method, then finds the intercept. Centering
keeps the equations well conditioned. The result gives each coefficient
with its standard error, t, p value and 95 percent interval, R^2, the
adjusted R^2, the F test of all the covariates, and predictions.

The outcome and each covariate are plain numbers in units that the
caller chooses. A coefficient is in outcome units per covariate unit.
"""

from extensions.clinical.cox import MAX_COVARIATES
from extensions.numerics.distributions import (
    f_upper,
    student_t_quantile,
    student_t_upper,
)
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_inverse,
    cholesky_solve,
)
from std.math import isfinite, sqrt


struct LinearModel(Copyable, Movable):
    """A least squares fit. Index 0 is the intercept, and index `i + 1` is
    covariate `i`."""

    var coefficients: List[Float64]
    """The intercept, then the coefficient of each covariate."""
    var standard_errors: List[Float64]
    """The standard error of each coefficient."""
    var residual_deviation: Float64
    """The standard deviation of the residuals, on `n - p` degrees of
    freedom."""
    var freedom: Int
    """The residual degrees of freedom, `n - p`."""
    var r_squared: Float64
    """The share of the variance of the outcome that the fit explains."""
    var adjusted_r_squared: Float64
    """R^2 adjusted for the count of covariates."""
    var f: Float64
    """The F statistic of all the covariates against the intercept
    alone."""
    var f_p_value: Float64
    """The p value of F."""

    def __init__(out self, count: Int):
        """Create an empty model.

        Args:
            count: The number of coefficients, the intercept included.
        """
        self.coefficients = List[Float64](length=count, fill=0.0)
        self.standard_errors = List[Float64](length=count, fill=0.0)
        self.residual_deviation = 0.0
        self.freedom = 0
        self.r_squared = 0.0
        self.adjusted_r_squared = 0.0
        self.f = 0.0
        self.f_p_value = 1.0

    def _require_index(self, index: Int) raises:
        """Refuse an index that names no coefficient."""
        if index < 0 or index >= len(self.coefficients):
            raise Error("A linear model has no coefficient of that index")

    def t(self, index: Int) raises -> Float64:
        """Return t of a coefficient.

        Args:
            index: 0 for the intercept, or `i + 1` for covariate `i`.

        Returns:
            The coefficient over its standard error.

        Raises:
            Error: If the index names no coefficient.
        """
        self._require_index(index)
        return self.coefficients[index] / self.standard_errors[index]

    def p_value(self, index: Int) raises -> Float64:
        """Return the two-sided p value of a coefficient.

        Args:
            index: 0 for the intercept, or `i + 1` for covariate `i`.

        Returns:
            The chance of a t this far from 0 when the coefficient is 0.

        Raises:
            Error: If the index names no coefficient.
        """
        var t = self.t(index)
        return 2.0 * student_t_upper(abs(t), Float64(self.freedom))

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of a coefficient.

        Args:
            index: 0 for the intercept, or `i + 1` for covariate `i`.

        Returns:
            The coefficient `-+ t se`, with t of `n - p` degrees of
            freedom.

        Raises:
            Error: If the index names no coefficient.
        """
        self._require_index(index)
        var half = (
            student_t_quantile(0.975, Float64(self.freedom))
            * self.standard_errors[index]
        )
        return (
            self.coefficients[index] - half,
            self.coefficients[index] + half,
        )

    def predict(self, row: List[Float64]) raises -> Float64:
        """Return the fitted outcome of a subject.

        Args:
            row: The covariates of the subject.

        Returns:
            `b0 + x . b`.

        Raises:
            Error: If the row does not have one finite value for each
                covariate.
        """
        if len(row) + 1 != len(self.coefficients):
            raise Error("A subject needs one value for each covariate")
        var out = self.coefficients[0]
        for a in range(len(row)):
            if not isfinite(row[a]):
                raise Error("The covariates of a subject must be finite")
            out += row[a] * self.coefficients[a + 1]
        return out


def linear_regression(
    outcome: List[Float64], covariates: List[List[Float64]]
) raises -> LinearModel:
    """Fit a linear model with an intercept by least squares.

    Args:
        outcome: The outcome of each subject.
        covariates: One row for each subject, of one value for each
            covariate. From 1 to 32 covariates, and more subjects than
            coefficients.

    Returns:
        The fit.

    Raises:
        Error: If the outcome and the rows differ in count, a row is out
            of range or holds a value that is not finite, there are no more
            subjects than coefficients, a covariate is constant or collinear
            with others, or the fit leaves no residual.
    """
    var n = len(outcome)
    if n == 0 or len(covariates) != n:
        raise Error("A linear model needs one row of covariates per subject")
    var k = len(covariates[0])
    if k < 1 or k > MAX_COVARIATES:
        raise Error("A linear model has from 1 to 32 covariates")
    for i in range(n):  # pragma: no branch
        if len(covariates[i]) != k:
            raise Error("Each subject needs the same count of covariates")
        if not isfinite(outcome[i]):
            raise Error("The outcome of a subject must be finite")
        for v in covariates[i]:  # pragma: no branch
            if not isfinite(v):
                raise Error("The covariates of a subject must be finite")
    if n <= k + 1:
        raise Error("A linear model needs more subjects than coefficients")
    var means = List[Float64](length=k, fill=0.0)
    var mean_y = 0.0
    for i in range(n):  # pragma: no branch
        mean_y += outcome[i] / Float64(n)
        for a in range(k):  # pragma: no branch
            means[a] += covariates[i][a] / Float64(n)
    # The normal equations of the centered covariates.
    var gram = DenseMatrix(k, k)
    var right = List[Float64](length=k, fill=0.0)
    var total = 0.0
    for i in range(n):  # pragma: no branch
        var dy = outcome[i] - mean_y
        total += dy * dy
        for a in range(k):  # pragma: no branch
            var xa = covariates[i][a] - means[a]
            right[a] += xa * dy
            for b in range(a + 1):  # pragma: no branch
                gram.add(a, b, xa * (covariates[i][b] - means[b]))
    # The slopes by triangular solves, so an exact fit leaves no residual.
    var slopes: List[Float64]
    try:
        slopes = cholesky_solve(gram, right)
    except:
        raise Error(
            "A covariate of a linear model is constant or collinear with others"
        )
    var inverse = cholesky_inverse(gram)
    var model = LinearModel(k + 1)
    var intercept = mean_y
    for a in range(k):  # pragma: no branch
        intercept -= slopes[a] * means[a]
        model.coefficients[a + 1] = slopes[a]
    model.coefficients[0] = intercept
    var residual = 0.0
    for i in range(n):  # pragma: no branch
        var fitted = intercept
        for a in range(k):  # pragma: no branch
            fitted += slopes[a] * covariates[i][a]
        residual += (outcome[i] - fitted) * (outcome[i] - fitted)
    if not (residual > 0):
        raise Error("A linear model needs an outcome that the fit misses")
    var df = n - k - 1
    var scale = residual / Float64(df)
    model.freedom = df
    model.residual_deviation = sqrt(scale)
    # The inverse of the centered normal matrix. The intercept's variance
    # adds that of the mean of the outcome.
    for a in range(k):  # pragma: no branch
        model.standard_errors[a + 1] = sqrt(scale * inverse.get(a, a))
    var spread = 1.0 / Float64(n)
    for a in range(k):  # pragma: no branch
        for b in range(k):  # pragma: no branch
            spread += means[a] * inverse.get(a, b) * means[b]
    model.standard_errors[0] = sqrt(scale * spread)
    model.r_squared = 1.0 - residual / total
    model.adjusted_r_squared = 1.0 - (1.0 - model.r_squared) * Float64(
        n - 1
    ) / Float64(df)
    model.f = ((total - residual) / Float64(k)) / scale
    model.f_p_value = f_upper(model.f, Float64(k), Float64(df))
    return model^
