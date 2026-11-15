# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Logistic regression: the risk of a binary outcome from covariates.

The model takes the log odds of the outcome, such as a disease, as
`b0 + x . b`. Here `x` holds the covariates of a patient, such as the age
or smoking. `exp(b_i)` is the odds ratio of covariate `i`: the factor on
the odds when that covariate grows by 1 and the others stay.

- `logistic_regression` finds the coefficients by Newton steps on the
  log-likelihood, from 0, as statsmodels does. The weights `p (1 - p)`
  are largest at 0, so the first steps fall short of the answer rather
  than past it. The standard errors come from the inverse of the
  information matrix.
- `LogisticModel` gives the Wald z and p value of each coefficient, the
  95 percent interval of each odds ratio, the likelihood ratio test of the
  covariates, and the predicted risk of a patient.

A covariate is a plain number in a unit that the caller chooses. Its
coefficient is per that unit.
"""

from extensions.clinical.cox import MAX_COVARIATES
from extensions.numerics.elementary import logistic, precise_exp, softplus
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_inverse,
)
from std.math import isfinite, log, log1p, sqrt
from extensions.numerics.distributions import (
    chi_square_p_value,
    normal_two_sided,
    ratio_interval,
)


struct LogisticModel(Copyable, Movable):
    """A fitted logistic model. Index 0 is the intercept, and index `i + 1`
    is covariate `i`."""

    var coefficients: List[Float64]
    """The intercept, then the coefficient of each covariate."""
    var standard_errors: List[Float64]
    """The standard error of each coefficient."""
    var log_likelihood: Float64
    """The log-likelihood at the coefficients."""
    var null_log_likelihood: Float64
    """The log-likelihood of the intercept alone."""
    var steps: Int
    """The Newton steps taken."""
    var converged: Bool
    """Whether the last step was below the tolerance."""

    def __init__(out self, count: Int):
        """Create an empty model.

        Args:
            count: The number of coefficients, the intercept included.
        """
        self.coefficients = List[Float64](length=count, fill=0.0)
        self.standard_errors = List[Float64](length=count, fill=0.0)
        self.log_likelihood = 0.0
        self.null_log_likelihood = 0.0
        self.steps = 0
        self.converged = False

    def _require_index(self, index: Int) raises:
        """Refuse an index that names no coefficient."""
        if index < 0 or index >= len(self.coefficients):
            raise Error("A logistic model has no coefficient of that index")

    def z(self, index: Int) raises -> Float64:
        """Return the Wald z value of a coefficient.

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
        """Return the two-sided Wald p value of a coefficient.

        Args:
            index: 0 for the intercept, or `i + 1` for covariate `i`.

        Returns:
            The chance of a z this far from 0 when the coefficient is 0.

        Raises:
            Error: If the index names no coefficient.
        """
        return normal_two_sided(self.z(index))

    def odds_ratio(self, index: Int) raises -> Float64:
        """Return the odds ratio of a coefficient.

        Args:
            index: 0 for the intercept, or `i + 1` for covariate `i`.

        Returns:
            `exp(b)`. For the intercept, the odds of a patient with every
            covariate 0.

        Raises:
            Error: If the index names no coefficient.
        """
        self._require_index(index)
        return precise_exp(self.coefficients[index])

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of an odds ratio.

        Args:
            index: 0 for the intercept, or `i + 1` for covariate `i`.

        Returns:
            The low and the high end, `exp(b -+ 1.96 se)`.

        Raises:
            Error: If the index names no coefficient.
        """
        self._require_index(index)
        return ratio_interval(
            precise_exp(self.coefficients[index]), self.standard_errors[index]
        )

    def likelihood_ratio(self) raises -> Tuple[Float64, Float64]:
        """Return the likelihood ratio test of the covariates.

        Returns:
            The statistic, twice the gain in log-likelihood over the
            intercept alone, and its p value with one degree of freedom for
            each covariate.

        Raises:
            Error: If the model has no covariate.
        """
        var statistic = max(
            0.0, 2.0 * (self.log_likelihood - self.null_log_likelihood)
        )
        return (
            statistic,
            chi_square_p_value(statistic, len(self.coefficients) - 1),
        )

    def risk(self, row: List[Float64]) raises -> Float64:
        """Return the predicted risk of a patient.

        Args:
            row: The covariates of the patient.

        Returns:
            `1 / (1 + exp(-(b0 + x . b)))`.

        Raises:
            Error: If the row does not have one finite value for each
                covariate.
        """
        if len(row) + 1 != len(self.coefficients):
            raise Error("A patient needs one value for each covariate")
        var eta = self.coefficients[0]
        for a in range(len(row)):
            if not isfinite(row[a]):
                raise Error("The covariates of a patient must be finite")
            eta += row[a] * self.coefficients[a + 1]
        return logistic(eta)


struct _Pass(Movable):
    """The log-likelihood, its gradient and its information matrix at one
    set of coefficients."""

    var log_likelihood: Float64
    var gradient: List[Float64]
    var information: DenseMatrix

    def __init__(out self, count: Int) raises:
        self.log_likelihood = 0.0
        self.gradient = List[Float64](length=count, fill=0.0)
        self.information = DenseMatrix(count, count)


def _evaluate(
    outcomes: List[Bool], x: List[List[Float64]], beta: List[Float64]
) raises -> _Pass:
    """Evaluate the log-likelihood with a leading 1 for the intercept.
    Only the lower triangle of the information matrix is filled."""
    var k = len(beta)
    var out = _Pass(k)
    for i in range(len(outcomes)):  # pragma: no branch
        ref row = x[i]
        var eta = beta[0]
        for a in range(1, k):  # pragma: no branch
            eta += row[a - 1] * beta[a]
        var p = logistic(eta)
        var weight = p * (1.0 - p)
        var residual = -p
        out.log_likelihood -= softplus(eta)
        if outcomes[i]:
            out.log_likelihood += eta
            residual += 1.0
        for a in range(k):  # pragma: no branch
            var xa = 1.0 if a == 0 else row[a - 1]
            out.gradient[a] += residual * xa
            for b in range(a + 1):  # pragma: no branch
                var xb = 1.0 if b == 0 else row[b - 1]
                out.information.add(a, b, weight * xa * xb)
    return out^


def _moved(beta: List[Float64], step: List[Float64]) -> List[Float64]:
    """Return `beta + step`."""
    var out = beta.copy()
    for a in range(len(out)):  # pragma: no branch
        out[a] += step[a]
    return out^


def _inverse(information: DenseMatrix) raises -> DenseMatrix:
    """Invert the information matrix, or say why it cannot be."""
    try:
        return cholesky_inverse(information)
    except:
        raise Error(
            "The information of a logistic model is not positive definite:"
            " a covariate may be constant, collinear with others, or"
            " separate the outcomes"
        )


def logistic_regression(
    outcomes: List[Bool],
    covariates: List[List[Float64]],
    tolerance: Float64,
    max_steps: Int,
) raises -> LogisticModel:
    """Fit a logistic model by Newton steps.

    Args:
        outcomes: Whether each patient has the outcome.
        covariates: One row for each patient, of one value for each
            covariate.
        tolerance: The largest change of a coefficient at the last step.
            Between 0 and 1.
        max_steps: The most Newton steps, from 1 to 1000.

    Returns:
        The model. `converged` is False when the steps ran out first.

    Raises:
        Error: If the covariates are not one finite row of 1 to 32 values
            for each patient, the outcomes are all the same, the tolerance
            or the steps are out of range, or the information matrix is not
            positive definite.
    """
    var n = len(outcomes)
    if n == 0 or len(covariates) != n:
        raise Error("A logistic model needs one row of covariates per patient")
    var k = len(covariates[0])
    if k < 1 or k > MAX_COVARIATES:
        raise Error("A logistic model has from 1 to 32 covariates")
    for row in covariates:  # pragma: no branch
        if len(row) != k:
            raise Error("Each patient needs the same count of covariates")
        for v in row:  # pragma: no branch
            if not isfinite(v):
                raise Error("The covariates of a patient must be finite")
    if not (tolerance > 0 and tolerance < 1):
        raise Error("The tolerance of a logistic model must be between 0 and 1")
    if max_steps < 1 or max_steps > 1000:
        raise Error("A logistic model takes from 1 to 1000 Newton steps")
    var cases = 0
    for o in outcomes:  # pragma: no branch
        if o:
            cases += 1
    if cases == 0 or cases == n:
        raise Error(
            "A logistic model needs patients with and without the outcome"
        )
    var model = LogisticModel(k + 1)
    var share = Float64(cases) / Float64(n)
    model.null_log_likelihood = Float64(n) * (
        share * log(share) + (1.0 - share) * log1p(-share)
    )
    var beta = List[Float64](length=k + 1, fill=0.0)
    var current = _evaluate(outcomes, covariates, beta)
    while model.steps < max_steps:
        var step = _inverse(current.information).multiply_vector(
            current.gradient
        )
        model.steps += 1
        var size = 0.0
        for a in range(k + 1):  # pragma: no branch
            size = max(size, abs(step[a]))
        beta = _moved(beta, step)
        current = _evaluate(outcomes, covariates, beta)
        if size < tolerance:
            model.converged = True
            break
    model.log_likelihood = current.log_likelihood
    var covariance = _inverse(current.information)
    for a in range(k + 1):  # pragma: no branch
        model.standard_errors[a] = sqrt(covariance.get(a, a))
        model.coefficients[a] = beta[a]
    return model^
