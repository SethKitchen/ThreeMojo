# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Weibull regression of censored times: the accelerated failure time
model.

The model gives each patient the Weibull survival
`S(t) = exp(-(t / lambda)^rho)`, with the scale `lambda = exp(b . x)` of
the covariates x after a 1 for the intercept, and one shape rho for all.
A coefficient b is a log time ratio: each unit of its covariate
multiplies the times to the event by `exp(b)`. Above 1, the covariate
delays the event.

`weibull_regression(times, events, covariates, tolerance, max_steps)`
fits it by Newton steps on `(g, rho)`, with `g = -rho b`. The hazard is
then `rho t^(rho - 1) exp(g . x)`, and the log-likelihood is concave in
`(g, rho)`. A step that would make rho 0 or less, or that loses
log-likelihood, is halved. The times are in units of the largest time
and the covariates centered while it searches.

The standard errors of b and of `ln rho` come from the inverse of the
observed information, as lifelines' `WeibullAFTFitter` gives them. The
model also gives the median and the survival of a patient, and the
likelihood ratio test of all the covariates against the Weibull model
without them.
"""

from extensions.clinical.cox import MAX_COVARIATES, chi_square_p_value
from extensions.numerics.elementary import LN2, precise_exp
from extensions.clinical.parametric import fit_weibull
from extensions.clinical.survival import Z95, require_group
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_inverse,
    cholesky_solve,
)
from std.math import erfc, inf, isfinite, log, sqrt
from units.si import SECOND, Duration64, DurationUnit64

# The most halvings of one Newton step, and the log-likelihood that a step
# may lose, relative, to roundoff.
comptime _HALVINGS = 30
comptime _SLACK = 1e-10


struct WeibullRegression(Copyable, Movable):
    """A fitted Weibull accelerated failure time model."""

    var coefficients: List[Float64]
    """The log time ratio b of each covariate."""
    var standard_errors: List[Float64]
    """The standard error of each coefficient."""
    var intercept_in_seconds: Float64
    """The log of the scale, in seconds, of a patient whose covariates are
    all 0."""
    var intercept_error: Float64
    """The standard error of the intercept."""
    var shape: Float64
    """The shape rho."""
    var log_shape_error: Float64
    """The standard error of `ln rho`."""
    var covariance: DenseMatrix
    """The covariance of the intercept, the coefficients and `ln rho`, in
    that order."""
    var log_likelihood_in_seconds: Float64
    """The log-likelihood, with the times in seconds."""
    var null_log_likelihood_in_seconds: Float64
    """The log-likelihood of the Weibull model without covariates."""
    var events: Int
    """The events."""
    var steps: Int
    """The Newton steps taken."""
    var converged: Bool
    """Whether the last step was below the tolerance."""

    def __init__(out self, count: Int) raises:
        """Create an empty model.

        Args:
            count: The covariates.

        Raises:
            Error: If the count is below 0.
        """
        self.coefficients = List[Float64](length=count, fill=0.0)
        self.standard_errors = List[Float64](length=count, fill=0.0)
        self.intercept_in_seconds = 0.0
        self.intercept_error = 0.0
        self.shape = 1.0
        self.log_shape_error = 0.0
        self.covariance = DenseMatrix(count + 2, count + 2)
        self.log_likelihood_in_seconds = 0.0
        self.null_log_likelihood_in_seconds = 0.0
        self.events = 0
        self.steps = 0
        self.converged = False

    def _require_index(self, index: Int) raises:
        """Refuse an index that names no covariate."""
        if index < 0 or index >= len(self.coefficients):
            raise Error("A Weibull regression has no covariate of that index")

    def time_ratio(self, index: Int) raises -> Float64:
        """Return the time ratio of a covariate.

        Args:
            index: The covariate, from 0.

        Returns:
            `exp(b)`: the factor on the times to the event for each unit of
            the covariate.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        return precise_exp(self.coefficients[index])

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of a time ratio.

        Args:
            index: The covariate, from 0.

        Returns:
            `exp(b -+ 1.96 se)`.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        var b = self.coefficients[index]
        var e = Z95 * self.standard_errors[index]
        return (precise_exp(b - e), precise_exp(b + e))

    def p_value(self, index: Int) raises -> Float64:
        """Return the two-sided Wald p value of a coefficient.

        Args:
            index: The covariate, from 0.

        Returns:
            The chance of a coefficient this far from 0 when it is 0.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        var z = self.coefficients[index] / self.standard_errors[index]
        return erfc(abs(z) / sqrt(2.0))

    def intercept(self, unit: DurationUnit64) -> Float64:
        """Return the intercept, the log of the scale of a patient whose
        covariates are all 0, with the times in a unit.

        Args:
            unit: The unit of time.

        Returns:
            The intercept, as lifelines gives it for times in the unit.
        """
        return self.intercept_in_seconds - log(Duration64(1.0, unit).to(SECOND))

    def log_likelihood(self, unit: DurationUnit64) -> Float64:
        """Return the log-likelihood, with the times in a unit.

        Args:
            unit: The unit of time.

        Returns:
            The log-likelihood, as lifelines gives it for times in the
            unit.
        """
        return self.log_likelihood_in_seconds + Float64(self.events) * log(
            Duration64(1.0, unit).to(SECOND)
        )

    def likelihood_ratio(self) raises -> Tuple[Float64, Float64]:
        """Return the likelihood ratio test of all the covariates.

        Returns:
            Twice the log-likelihood less that of the Weibull model without
            covariates, and its p value on one degree of freedom for each
            covariate.

        Raises:
            Error: If the model has more covariates than the test takes.
        """
        var statistic = max(
            2.0
            * (
                self.log_likelihood_in_seconds
                - self.null_log_likelihood_in_seconds
            ),
            0.0,
        )
        return (
            statistic,
            chi_square_p_value(statistic, len(self.coefficients)),
        )

    def _eta(self, row: List[Float64]) raises -> Float64:
        """Return `b . x` with the intercept, in seconds."""
        if len(row) != len(self.coefficients):
            raise Error("A patient needs one value for each covariate")
        var eta = self.intercept_in_seconds
        for a in range(len(row)):  # pragma: no branch
            if not isfinite(row[a]):
                raise Error("The covariates of a patient must be finite")
            eta += self.coefficients[a] * row[a]
        return eta

    def scale(self, row: List[Float64]) raises -> Duration64:
        """Return the scale of a patient.

        Args:
            row: The covariates of the patient.

        Returns:
            `exp(b . x)`: the time by which 63 percent of such patients
            have had the event.

        Raises:
            Error: If the row does not have one finite value for each
                covariate.
        """
        return Duration64(precise_exp(self._eta(row)), SECOND)

    def median(self, row: List[Float64]) raises -> Duration64:
        """Return the median time to the event of a patient.

        Args:
            row: The covariates of the patient.

        Returns:
            `exp(b . x) (ln 2)^(1 / rho)`.

        Raises:
            Error: If the row does not have one finite value for each
                covariate.
        """
        var eta = self._eta(row)
        return Duration64(precise_exp(eta + log(LN2) / self.shape), SECOND)

    def survival(self, row: List[Float64], time: Duration64) raises -> Float64:
        """Return the survival of a patient at a time.

        Args:
            row: The covariates of the patient.
            time: The time, 0 or more and finite.

        Returns:
            `exp(-(t / lambda)^rho)`.

        Raises:
            Error: If the row does not have one finite value for each
                covariate, or the time is below 0 or not finite.
        """
        var eta = self._eta(row)
        var t = time.to(SECOND)
        if not (t >= 0) or not isfinite(t):
            raise Error("The time of a survival model must be 0 or more")
        if t == 0:
            return 1.0
        return precise_exp(-precise_exp(self.shape * (log(t) - eta)))


struct _Data(Movable):
    """The positive times over the largest time, their logs, the events and
    the centered covariates."""

    var logs: List[Float64]
    var event: List[Bool]
    var x: List[List[Float64]]
    var means: List[Float64]
    var top: Float64
    var events: Int

    def __init__(
        out self,
        times: List[Duration64],
        events: List[Bool],
        covariates: List[List[Float64]],
    ) raises:
        """Check and keep a group. A patient censored at 0 adds nothing.

        Args:
            times: The time of each patient.
            events: Whether each patient had the event.
            covariates: The covariates of each patient.

        Raises:
            Error: If the group or the covariates are not valid, or an
                event is at 0.
        """
        self.logs = List[Float64]()
        self.event = List[Bool]()
        self.x = List[List[Float64]]()
        self.means = List[Float64]()
        self.top = 0.0
        self.events = 0
        require_group(times, events)
        if len(covariates) != len(times):
            raise Error(
                "A Weibull regression needs one row of covariates for each"
                " patient"
            )
        var k = len(covariates[0])
        if k < 1 or k > MAX_COVARIATES:
            raise Error("A Weibull regression has from 1 to 32 covariates")
        self.means = List[Float64](length=k, fill=0.0)
        for i in range(len(times)):  # pragma: no branch
            if len(covariates[i]) != k:
                raise Error("Each patient needs the same count of covariates")
            for v in covariates[i]:  # pragma: no branch
                if not isfinite(v):
                    raise Error("The covariates of a patient must be finite")
            var t = times[i].to(SECOND)
            if events[i] and t == 0:
                raise Error("A Weibull regression needs each event after 0")
            self.top = max(self.top, t)
        var kept = List[Int]()
        for i in range(len(times)):  # pragma: no branch
            if times[i].to(SECOND) > 0:
                kept.append(i)
        for i in kept:  # pragma: no branch
            for a in range(k):  # pragma: no branch
                self.means[a] += covariates[i][a] / Float64(len(kept))
        for i in kept:  # pragma: no branch
            self.logs.append(log(times[i].to(SECOND) / self.top))
            self.event.append(events[i])
            if events[i]:
                self.events += 1
            var row = List[Float64]()
            row.append(1.0)
            for a in range(k):  # pragma: no branch
                row.append(covariates[i][a] - self.means[a])
            self.x.append(row^)

    def log_likelihood(self, g: List[Float64], rho: Float64) -> Float64:
        """Return the log-likelihood of `(g, rho)` in units of the largest
        time. -infinity for a rho of 0 or less."""
        if not (rho > 0):
            return -inf[DType.float64]()
        var total = 0.0
        var log_rho = log(rho)
        for i in range(len(self.logs)):  # pragma: no branch
            var eta = 0.0
            for a in range(len(g)):  # pragma: no branch
                eta += g[a] * self.x[i][a]
            if self.event[i]:
                total += log_rho + (rho - 1.0) * self.logs[i] + eta
            total -= precise_exp(rho * self.logs[i] + eta)
        return total

    def information(
        self, g: List[Float64], rho: Float64
    ) raises -> Tuple[DenseMatrix, List[Float64]]:
        """Return the negative Hessian and the gradient of the
        log-likelihood in `(g, rho)`."""
        var n = len(g) + 1
        var h = DenseMatrix(n, n)
        var grad = List[Float64](length=n, fill=0.0)
        var d = Float64(self.events)
        grad[n - 1] = d / rho
        h.data[n * n - 1] = d / (rho * rho)
        for i in range(len(self.logs)):  # pragma: no branch
            ref row = self.x[i]
            var eta = 0.0
            for a in range(len(g)):  # pragma: no branch
                eta += g[a] * row[a]
            var w = precise_exp(rho * self.logs[i] + eta)
            var l = self.logs[i]
            var flag = 1.0 if self.event[i] else 0.0
            for a in range(len(g)):  # pragma: no branch
                grad[a] += (flag - w) * row[a]
                for c in range(len(g)):  # pragma: no branch
                    h.data[a * n + c] += w * row[a] * row[c]
                h.data[a * n + n - 1] += w * l * row[a]
                h.data[(n - 1) * n + a] += w * l * row[a]
            grad[n - 1] += (flag - w) * l
            h.data[n * n - 1] += w * l * l
        return (h^, grad^)


def weibull_regression(
    times: List[Duration64],
    events: List[Bool],
    covariates: List[List[Float64]],
    tolerance: Float64,
    max_steps: Int,
) raises -> WeibullRegression:
    """Fit a Weibull accelerated failure time model by Newton steps.

    Args:
        times: The time of each patient, to the event or to the censoring.
        events: Whether each patient had the event, or was censored.
        covariates: One row for each patient, of one value for each
            covariate, from 1 to 32 covariates.
        tolerance: The largest change of a parameter at the last step.
            Between 0 and 1.
        max_steps: The most Newton steps, from 1 to 1000.

    Returns:
        The model. `converged` is False when the steps ran out first.

    Raises:
        Error: If the group or the covariates are not valid, an event is
            at 0, the Weibull model without covariates has no fit, the
            tolerance or the steps are out of range, or the information
            matrix is not positive definite, as for a covariate that is
            constant or collinear with others.
    """
    var data = _Data(times, events, covariates)
    if not (tolerance > 0 and tolerance < 1):
        raise Error("The tolerance of a Weibull regression is from 0 to 1")
    if max_steps < 1 or max_steps > 1000:
        raise Error("A Weibull regression takes from 1 to 1000 Newton steps")
    var null = fit_weibull(times, events)
    var k = len(covariates[0])
    var model = WeibullRegression(k)
    model.events = data.events
    model.null_log_likelihood_in_seconds = null.log_likelihood_in_seconds
    # Start from the exponential model without covariates.
    var total = 0.0
    for l in data.logs:  # pragma: no branch
        total += precise_exp(l)
    var g = List[Float64](length=k + 1, fill=0.0)
    g[0] = log(Float64(data.events) / total)
    var rho = 1.0
    var current = data.log_likelihood(g, rho)
    var n = k + 2
    while model.steps < max_steps:
        var found = data.information(g, rho)
        var step = cholesky_solve(found[0], found[1])
        model.steps += 1
        var size = 0.0
        for a in range(n):  # pragma: no branch
            size = max(size, abs(step[a]))
        var scale = 1.0
        var trial = List[Float64]()
        var trial_rho = rho
        var value = current
        var floor = current - _SLACK * (1.0 + abs(current))
        for _ in range(_HALVINGS):  # pragma: no branch
            trial = List[Float64]()
            for a in range(k + 1):  # pragma: no branch
                trial.append(g[a] + scale * step[a])
            trial_rho = rho + scale * step[n - 1]
            value = data.log_likelihood(trial, trial_rho)
            if value >= floor:
                break
            scale *= 0.5
        g = trial^
        rho = trial_rho
        current = value
        if size < tolerance:
            model.converged = True
            break
    # From the centered covariates in units of the largest time back to
    # the covariates as given, in seconds.
    var shift = 0.0
    for a in range(k):  # pragma: no branch
        shift += g[a + 1] * data.means[a]
    var uncentered = g.copy()
    uncentered[0] = g[0] - shift
    var information = _Data(times, events, covariates)
    for i in range(len(information.x)):  # pragma: no branch
        for a in range(k):  # pragma: no branch
            information.x[i][a + 1] += data.means[a]
    var variance = cholesky_inverse(information.information(uncentered, rho)[0])
    # The Jacobian of `(b, ln rho)` in `(g, rho)`: b = -g / rho.
    var jacobian = DenseMatrix(n, n)
    for a in range(k + 1):  # pragma: no branch
        jacobian.data[a * n + a] = -1.0 / rho
        jacobian.data[a * n + n - 1] = uncentered[a] / (rho * rho)
    jacobian.data[n * n - 1] = 1.0 / rho
    # J V J^T, as T^T A T with T = J^T.
    model.covariance = jacobian.transposed().triple_product(variance)
    model.shape = rho
    model.intercept_in_seconds = -uncentered[0] / rho + log(data.top)
    model.intercept_error = sqrt(model.covariance.data[0])
    for a in range(k):  # pragma: no branch
        model.coefficients[a] = -uncentered[a + 1] / rho
        model.standard_errors[a] = sqrt(
            model.covariance.data[(a + 1) * n + a + 1]
        )
    model.log_shape_error = sqrt(model.covariance.data[n * n - 1])
    model.log_likelihood_in_seconds = current - Float64(data.events) * log(
        data.top
    )
    return model^
