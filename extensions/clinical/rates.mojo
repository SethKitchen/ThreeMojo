# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Poisson regression of event rates: incidence rate ratios over
person-time.

A cohort counts the events of each stratum, such as the cancers among
smokers in their sixties, over its person-time. The model takes the rate
of a stratum as a baseline rate times `exp(x . b)`. `exp(b_i)` is the rate
ratio of covariate `i`: the factor on the rate for each unit of that
covariate, with the others held.

`poisson_regression` fits the log of the expected count, `log(T) + b0 +
x . b`, with the log of the person-time T as the offset. It uses
iteratively reweighted least squares from `mu = (y + mean(y)) / 2`, as
statsmodels starts. The result gives each rate ratio with its 95 percent
interval and Wald test, the baseline rate, the deviance and the Pearson
dispersion, and the rate of a stratum.

A dispersion above 1 means more spread than Poisson counts have. Then
multiply the standard errors by its square root.
"""

from extensions.clinical.cox import MAX_COVARIATES
from extensions.numerics.elementary import precise_exp
from extensions.clinical.survival import Z95
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_inverse,
    cholesky_solve,
)
from std.math import erfc, isfinite, log, sqrt
from units.quantity import Unit
from units.si import PER_YEAR64, YEAR64, Duration64, Frequency64

comptime _SQRT_TWO = 1.4142135623730951


struct RateModel(Copyable, Movable):
    """A fitted Poisson rate model. Index 0 is the intercept, the log of the
    baseline rate in events per year, and index `i + 1` is covariate `i`."""

    var coefficients: List[Float64]
    """The intercept, then the log rate ratio of each covariate."""
    var standard_errors: List[Float64]
    """The standard error of each coefficient."""
    var deviance: Float64
    """The Poisson deviance."""
    var dispersion: Float64
    """Pearson's chi-square over its degrees of freedom."""
    var steps: Int
    """The steps of the fit."""
    var converged: Bool
    """Whether the last step was below the tolerance."""

    def __init__(out self, count: Int):
        """Create an empty model.

        Args:
            count: The number of coefficients, the intercept included.
        """
        self.coefficients = List[Float64](length=count, fill=0.0)
        self.standard_errors = List[Float64](length=count, fill=0.0)
        self.deviance = 0.0
        self.dispersion = 0.0
        self.steps = 0
        self.converged = False

    def _require_index(self, index: Int) raises:
        """Refuse an index that names no covariate."""
        if index < 1 or index >= len(self.coefficients):
            raise Error("A rate model has no covariate of that index")

    def baseline_rate(self) -> Frequency64:
        """Return the rate of a stratum with every covariate 0.

        Returns:
            `exp(b0)`, per year.
        """
        return Frequency64(precise_exp(self.coefficients[0]), PER_YEAR64)

    def rate_ratio(self, index: Int) raises -> Float64:
        """Return the rate ratio of a covariate.

        Args:
            index: `i + 1` for covariate `i`.

        Returns:
            `exp(b)`.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        return precise_exp(self.coefficients[index])

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of a rate ratio.

        Args:
            index: `i + 1` for covariate `i`.

        Returns:
            The low and the high end, `exp(b -+ 1.96 se)`.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        var b = self.coefficients[index]
        var half = Z95 * self.standard_errors[index]
        return (precise_exp(b - half), precise_exp(b + half))

    def z(self, index: Int) raises -> Float64:
        """Return the Wald z of a covariate.

        Args:
            index: `i + 1` for covariate `i`.

        Returns:
            The coefficient over its standard error.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        return self.coefficients[index] / self.standard_errors[index]

    def p_value(self, index: Int) raises -> Float64:
        """Return the two-sided Wald p value of a covariate.

        Args:
            index: `i + 1` for covariate `i`.

        Returns:
            The chance of a z this far from 0 when the rate ratio is 1.

        Raises:
            Error: If the index names no covariate.
        """
        return erfc(abs(self.z(index)) / _SQRT_TWO)

    def rate(self, row: List[Float64]) raises -> Frequency64:
        """Return the fitted rate of a stratum.

        Args:
            row: The covariates of the stratum.

        Returns:
            `exp(b0 + x . b)`, per year.

        Raises:
            Error: If the row does not have one finite value for each
                covariate.
        """
        if len(row) + 1 != len(self.coefficients):
            raise Error("A stratum needs one value for each covariate")
        var eta = self.coefficients[0]
        for a in range(len(row)):
            if not isfinite(row[a]):
                raise Error("The covariates of a stratum must be finite")
            eta += row[a] * self.coefficients[a + 1]
        return Frequency64(precise_exp(eta), PER_YEAR64)


def _require_data(
    events: List[Int],
    exposure: List[Duration64],
    covariates: List[List[Float64]],
) raises -> Int:
    """Refuse strata out of range. Return the count of covariates."""
    var n = len(events)
    if n == 0 or len(exposure) != n or len(covariates) != n:
        raise Error(
            "A rate model needs events, person-time and covariates per stratum"
        )
    var k = len(covariates[0])
    if k < 1 or k > MAX_COVARIATES:
        raise Error("A rate model has from 1 to 32 covariates")
    var total = 0
    for i in range(n):  # pragma: no branch
        if events[i] < 0:
            raise Error("The events of a stratum must be 0 or more")
        total += events[i]
        var years = exposure[i].to(YEAR64)
        if not (years > 0) or not isfinite(years):
            raise Error("The person-time of a stratum must be positive")
        if len(covariates[i]) != k:
            raise Error("Each stratum needs the same count of covariates")
        for v in covariates[i]:  # pragma: no branch
            if not isfinite(v):
                raise Error("The covariates of a stratum must be finite")
    if total == 0:
        raise Error("A rate model needs one event or more")
    if n <= k + 1:
        raise Error("A rate model needs more strata than coefficients")
    return k


def poisson_regression(
    events: List[Int],
    exposure: List[Duration64],
    covariates: List[List[Float64]],
    tolerance: Float64,
    max_steps: Int,
) raises -> RateModel:
    """Fit a Poisson model of event rates over person-time.

    Args:
        events: The events of each stratum.
        exposure: The person-time of each stratum.
        covariates: One row for each stratum, of one value for each
            covariate.
        tolerance: The largest change of a coefficient at the last step.
            Between 0 and 1.
        max_steps: The most steps, from 1 to 1000.

    Returns:
        The model. `converged` is False when the steps ran out first.

    Raises:
        Error: If the strata, the tolerance or the steps are out of range,
            or a covariate is constant or collinear with others.
    """
    var k = _require_data(events, exposure, covariates)
    if not (tolerance > 0 and tolerance < 1):
        raise Error("The tolerance of a rate model must be between 0 and 1")
    if max_steps < 1 or max_steps > 1000:
        raise Error("A rate model takes from 1 to 1000 steps")
    var n = len(events)
    var p = k + 1
    var offset = List[Float64]()
    var mean = 0.0
    for i in range(n):  # pragma: no branch
        offset.append(log(exposure[i].to(YEAR64)))
        mean += Float64(events[i]) / Float64(n)
    var mu = List[Float64]()
    for i in range(n):  # pragma: no branch
        mu.append((Float64(events[i]) + mean) / 2.0)
    var model = RateModel(p)
    var beta = List[Float64](length=p, fill=0.0)
    while model.steps < max_steps:
        # Weighted least squares of the working response on (1, x).
        var gram = DenseMatrix(p, p)
        var right = List[Float64](length=p, fill=0.0)
        for i in range(n):  # pragma: no branch
            var z = (
                log(mu[i]) - offset[i] + (Float64(events[i]) - mu[i]) / mu[i]
            )
            for a in range(p):  # pragma: no branch
                var xa = 1.0 if a == 0 else covariates[i][a - 1]
                right[a] += mu[i] * xa * z
                for b in range(a + 1):  # pragma: no branch
                    var xb = 1.0 if b == 0 else covariates[i][b - 1]
                    gram.add(a, b, mu[i] * xa * xb)
        var next: List[Float64]
        try:
            next = cholesky_solve(gram, right)
        except:
            raise Error(
                "A covariate of a rate model is constant or collinear with"
                " others"
            )
        var change = 0.0
        for a in range(p):  # pragma: no branch
            change = max(change, abs(next[a] - beta[a]))
        beta = next^
        model.steps += 1
        for i in range(n):  # pragma: no branch
            var eta = offset[i] + beta[0]
            for a in range(k):  # pragma: no branch
                eta += covariates[i][a] * beta[a + 1]
            mu[i] = precise_exp(eta)
        if model.steps > 1 and change < tolerance:
            model.converged = True
            break
    # The information at the last fit.
    var gram = DenseMatrix(p, p)
    var pearson = 0.0
    var deviance = 0.0
    for i in range(n):  # pragma: no branch
        var y = Float64(events[i])
        for a in range(p):  # pragma: no branch
            var xa = 1.0 if a == 0 else covariates[i][a - 1]
            for b in range(a + 1):  # pragma: no branch
                var xb = 1.0 if b == 0 else covariates[i][b - 1]
                gram.add(a, b, mu[i] * xa * xb)
        pearson += (y - mu[i]) * (y - mu[i]) / mu[i]
        deviance -= y - mu[i]
        if events[i] > 0:
            deviance += y * log(y / mu[i])
    var covariance = cholesky_inverse(gram)
    for a in range(p):  # pragma: no branch
        model.standard_errors[a] = sqrt(covariance.get(a, a))
        model.coefficients[a] = beta[a]
    model.deviance = 2.0 * deviance
    model.dispersion = pearson / Float64(n - p)
    return model^
