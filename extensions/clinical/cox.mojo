# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cox proportional hazards regression: the effect of covariates on
survival.

The Cox model takes the hazard of a patient as a baseline hazard, the same
for each patient, times `exp(x . b)`. Here `x` holds the covariates of the
patient, such as the age or a treatment, and `b` holds one coefficient for
each. `exp(b_i)` is the hazard ratio of covariate `i`: the factor by which
the hazard changes when that covariate grows by 1 and the others stay.

- `cox_regression` finds `b` by Newton steps on the partial likelihood,
  with Efron's method for tied times. A step that loses likelihood is
  halved. The standard errors come from the inverse of the information
  matrix.
- `CoxModel` gives the Wald z and p value of each coefficient, the 95
  percent interval of each hazard ratio, the likelihood ratio test of the
  whole model, and Harrell's concordance.
- `CoxModel.survival` predicts the survival of a patient from the Breslow
  baseline hazard.
- `chi_square_p_value` gives the upper tail of the chi-square
  distribution.

A covariate is a plain number in a unit that the caller chooses, such as an
age in decades. Its coefficient is per that unit. The fit subtracts the
mean of each covariate first, which does not change `b`.

See Cox (1972), Efron (1977), Breslow (1974) and Harrell and others (1982).
"""

from extensions.clinical.survival import Z95, require_group
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky,
    solve_lower,
    solve_lower_transposed,
)
from math.sort_utils import stable_sort
from std.math import erfc, exp, isfinite, log, sqrt
from units.si import Duration64, SECOND

# The most covariates of one model.
comptime MAX_COVARIATES = 32
# The most degrees of freedom of a chi-square test.
comptime MAX_FREEDOM = 1000
# The most halvings of one Newton step.
comptime _HALVINGS = 30
# A step may lose this much log-likelihood, relative, to roundoff.
comptime _SLACK = 1e-10
# ln(sqrt(pi) / 2), the logarithm of the gamma function at 3/2.
comptime _LOG_GAMMA_THREE_HALVES = -0.12078223763524522


def chi_square_p_value(statistic: Float64, freedom: Int) raises -> Float64:
    """Return the chance that a chi-square value is the statistic or more.

    Args:
        statistic: The statistic. 0 or more; infinity gives 0.
        freedom: The degrees of freedom, from 1 to 1000.

    Returns:
        The upper tail of the chi-square distribution, in closed form:
        a sum of Poisson terms for an even freedom, and `erfc` and a sum
        for an odd freedom.

    Raises:
        Error: If the freedom is out of range, or the statistic is negative
            or not a number.
    """
    if freedom < 1 or freedom > MAX_FREEDOM:
        raise Error("A chi-square test has from 1 to 1000 degrees of freedom")
    if not (statistic >= 0):
        raise Error("A chi-square statistic must be 0 or more")
    if statistic == 0:
        return 1.0
    if not isfinite(statistic):
        return 0.0
    var x = statistic / 2.0
    var lx = log(x)
    var total = 0.0
    if freedom % 2 == 0:
        # exp(-x) x^j / j! for j from 0 to freedom / 2 - 1.
        var log_factorial = 0.0
        for j in range(freedom // 2):  # pragma: no branch
            if j > 0:
                log_factorial += log(Float64(j))
            total += exp(Float64(j) * lx - x - log_factorial)
        return total
    # exp(-x) x^(j + 1/2) / gamma(j + 3/2) for j from 0 to (freedom - 3) / 2.
    var log_gamma = _LOG_GAMMA_THREE_HALVES
    for j in range(freedom // 2):
        if j > 0:
            log_gamma += log(Float64(j) + 0.5)
        total += exp((Float64(j) + 0.5) * lx - x - log_gamma)
    return erfc(sqrt(x)) + total


struct CoxModel(Copyable, Movable):
    """A fitted Cox model."""

    var coefficients: List[Float64]
    """The coefficient `b` of each covariate, per its unit."""
    var standard_errors: List[Float64]
    """The standard error of each coefficient."""
    var log_likelihood: Float64
    """The log partial likelihood at the coefficients."""
    var null_log_likelihood: Float64
    """The log partial likelihood with every coefficient 0."""
    var concordance: Float64
    """Harrell's concordance of the fitted risks with the times. 0.5 when
    no pair of patients can be compared."""
    var steps: Int
    """The Newton steps taken."""
    var converged: Bool
    """Whether the last step was below the tolerance."""
    var means: List[Float64]
    """The mean of each covariate over the patients."""
    var times: List[Duration64]
    """Each time at which one event or more happened, rising."""
    var cumulative_hazard: List[Float64]
    """The Breslow cumulative baseline hazard at each time, for a patient
    with the mean covariates."""

    def __init__(out self, count: Int):
        """Create an empty model.

        Args:
            count: The number of covariates.
        """
        self.coefficients = List[Float64](length=count, fill=0.0)
        self.standard_errors = List[Float64](length=count, fill=0.0)
        self.log_likelihood = 0.0
        self.null_log_likelihood = 0.0
        self.concordance = 0.5
        self.steps = 0
        self.converged = False
        self.means = List[Float64](length=count, fill=0.0)
        self.times = List[Duration64]()
        self.cumulative_hazard = List[Float64]()

    def _require_index(self, index: Int) raises:
        """Refuse an index that names no covariate."""
        if index < 0 or index >= len(self.coefficients):
            raise Error("A Cox model has no covariate of that index")

    def z(self, index: Int) raises -> Float64:
        """Return the Wald z value of a coefficient.

        Args:
            index: The covariate, from 0.

        Returns:
            The coefficient over its standard error.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        return self.coefficients[index] / self.standard_errors[index]

    def p_value(self, index: Int) raises -> Float64:
        """Return the two-sided Wald p value of a coefficient.

        Args:
            index: The covariate, from 0.

        Returns:
            The chance of a z this far from 0 when the coefficient is 0.

        Raises:
            Error: If the index names no covariate.
        """
        return erfc(abs(self.z(index)) / sqrt(2.0))

    def hazard_ratio(self, index: Int) raises -> Float64:
        """Return the hazard ratio of a covariate.

        Args:
            index: The covariate, from 0.

        Returns:
            `exp(b)`: the factor on the hazard for each unit of the
            covariate.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        return exp(self.coefficients[index])

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of a hazard ratio.

        Args:
            index: The covariate, from 0.

        Returns:
            The low and the high end, `exp(b -+ 1.96 se)`.

        Raises:
            Error: If the index names no covariate.
        """
        self._require_index(index)
        var b = self.coefficients[index]
        var half = Z95 * self.standard_errors[index]
        return (exp(b - half), exp(b + half))

    def likelihood_ratio(self) raises -> Tuple[Float64, Float64]:
        """Return the likelihood ratio test of the whole model.

        Returns:
            The statistic, twice the gain in log-likelihood over the null
            model, and its p value with one degree of freedom for each
            covariate.

        Raises:
            Error: If the model has no covariate.
        """
        var statistic = max(
            0.0, 2.0 * (self.log_likelihood - self.null_log_likelihood)
        )
        return (
            statistic,
            chi_square_p_value(statistic, len(self.coefficients)),
        )

    def relative_hazard(self, row: List[Float64]) raises -> Float64:
        """Return the hazard of a patient relative to the mean patient.

        Args:
            row: The covariates of the patient.

        Returns:
            `exp((x - mean) . b)`.

        Raises:
            Error: If the row does not have one finite value for each
                covariate.
        """
        if len(row) != len(self.coefficients):
            raise Error("A patient needs one value for each covariate")
        var eta = 0.0
        for a in range(len(row)):  # pragma: no branch
            if not isfinite(row[a]):
                raise Error("The covariates of a patient must be finite")
            eta += (row[a] - self.means[a]) * self.coefficients[a]
        return exp(eta)

    def survival(self, row: List[Float64], time: Duration64) raises -> Float64:
        """Return the predicted survival of a patient at a time.

        Args:
            row: The covariates of the patient.
            time: The time. 0 or more, and finite.

        Returns:
            `exp(-H0(t) r)`, with `H0` the Breslow baseline and `r` the
            relative hazard.

        Raises:
            Error: If the row is not valid, or the time is negative or not
                finite.
        """
        var r = self.relative_hazard(row)
        var t = time.to(SECOND)
        if not (t >= 0) or not isfinite(t):
            raise Error("A survival time must be 0 or more, and finite")
        var hazard = 0.0
        for i in range(len(self.times)):  # pragma: no branch
            if self.times[i].to(SECOND) > t:
                break
            hazard = self.cumulative_hazard[i]
        return exp(-hazard * r)


struct _Pass(Movable):
    """The log partial likelihood, its gradient and its information matrix
    at one set of coefficients."""

    var log_likelihood: Float64
    var gradient: List[Float64]
    var information: DenseMatrix

    def __init__(out self, count: Int) raises:
        self.log_likelihood = 0.0
        self.gradient = List[Float64](length=count, fill=0.0)
        self.information = DenseMatrix(count, count)


def _efron(
    order: List[Int],
    seconds: List[Float64],
    events: List[Bool],
    x: List[List[Float64]],
    beta: List[Float64],
) raises -> _Pass:
    """Evaluate the partial likelihood with Efron's method for ties.

    `order` runs from the latest time to the earliest, so the risk set
    grows as the pass goes. Only the lower triangle of the information
    matrix is filled.
    """
    var k = len(beta)
    var out = _Pass(k)
    var s0 = 0.0
    var s1 = List[Float64](length=k, fill=0.0)
    var s2 = DenseMatrix(k, k)
    var at = 0
    while at < len(order):
        var t = seconds[order[at]]
        var t0 = 0.0
        var t1 = List[Float64](length=k, fill=0.0)
        var t2 = DenseMatrix(k, k)
        var m = 0
        while at < len(order) and seconds[order[at]] == t:
            var i = order[at]
            ref row = x[i]
            var eta = 0.0
            for a in range(k):  # pragma: no branch
                eta += row[a] * beta[a]
            var w = exp(eta)
            s0 += w
            for a in range(k):  # pragma: no branch
                s1[a] += w * row[a]
                for b in range(a + 1):  # pragma: no branch
                    s2.add(a, b, w * row[a] * row[b])
            if events[i]:
                m += 1
                t0 += w
                out.log_likelihood += eta
                for a in range(k):  # pragma: no branch
                    t1[a] += w * row[a]
                    out.gradient[a] += row[a]
                    for b in range(a + 1):  # pragma: no branch
                        t2.add(a, b, w * row[a] * row[b])
            at += 1
        # The l-th of the m tied events removes l/m of each tied patient.
        for l in range(m):
            var f = Float64(l) / Float64(m)
            var phi = s0 - f * t0
            out.log_likelihood -= log(phi)
            for a in range(k):  # pragma: no branch
                var za = (s1[a] - f * t1[a]) / phi
                out.gradient[a] -= za
                for b in range(a + 1):  # pragma: no branch
                    var zb = (s1[b] - f * t1[b]) / phi
                    out.information.add(
                        a, b, (s2.get(a, b) - f * t2.get(a, b)) / phi - za * zb
                    )
    return out^


def _newton_step(current: _Pass) raises -> List[Float64]:
    """Solve the information matrix against the gradient by Cholesky."""
    var factor: DenseMatrix
    try:
        factor = cholesky(current.information)
    except:
        raise Error(
            "The information of a Cox model is not positive definite: a"
            " covariate may be constant, collinear with others, or"
            " separate the patients"
        )
    return solve_lower_transposed(factor, solve_lower(factor, current.gradient))


def _moved(
    beta: List[Float64], step: List[Float64], scale: Float64
) -> List[Float64]:
    """Return `beta + scale * step`."""
    var out = beta.copy()
    for a in range(len(out)):  # pragma: no branch
        out[a] += scale * step[a]
    return out^


def _require_covariates(
    covariates: List[List[Float64]], patients: Int
) raises -> Int:
    """Refuse covariates that are not one finite row for each patient, of
    one count from 1 to MAX_COVARIATES. Return that count."""
    if len(covariates) != patients:
        raise Error("A Cox model needs one row of covariates for each patient")
    var k = len(covariates[0])
    if k < 1 or k > MAX_COVARIATES:
        raise Error("A Cox model has from 1 to 32 covariates")
    for row in covariates:  # pragma: no branch
        if len(row) != k:
            raise Error("Each patient needs the same count of covariates")
        for v in row:  # pragma: no branch
            if not isfinite(v):
                raise Error("The covariates of a patient must be finite")
    return k


def _concordance(
    seconds: List[Float64], events: List[Bool], risk: List[Float64]
) -> Float64:
    """Return Harrell's concordance, as lifelines counts it.

    A pair is comparable when the first patient had the event, and the
    second left later, or at the same time without the event. The pair
    agrees when the first patient has the higher risk; a tie counts a half.
    """
    var pairs = 0
    var agree = 0.0
    for i in range(len(seconds)):  # pragma: no branch
        if not events[i]:
            continue
        for j in range(len(seconds)):  # pragma: no branch
            if not (
                seconds[i] < seconds[j]
                or (seconds[i] == seconds[j] and not events[j])
            ):
                continue
            pairs += 1
            if risk[i] > risk[j]:
                agree += 1.0
            elif risk[i] == risk[j]:
                agree += 0.5
    if pairs == 0:
        return 0.5
    return agree / Float64(pairs)


def cox_regression(
    times: List[Duration64],
    events: List[Bool],
    covariates: List[List[Float64]],
    tolerance: Float64,
    max_steps: Int,
) raises -> CoxModel:
    """Fit a Cox proportional hazards model by Newton steps.

    Args:
        times: The time of each patient, to the event or to the censoring.
        events: Whether each patient had the event, or was censored.
        covariates: One row for each patient, of one value for each
            covariate.
        tolerance: The largest change of a coefficient at the last step.
            Between 0 and 1.
        max_steps: The most Newton steps, from 1 to 1000.

    Returns:
        The model. `converged` is False when the steps ran out first.

    Raises:
        Error: If the group or the covariates are not valid, there is no
            event, the tolerance or the steps are out of range, or the
            information matrix is not positive definite.
    """
    require_group(times, events)
    var k = _require_covariates(covariates, len(times))
    if not (tolerance > 0 and tolerance < 1):
        raise Error("The tolerance of a Cox model must be between 0 and 1")
    if max_steps < 1 or max_steps > 1000:
        raise Error("A Cox model takes from 1 to 1000 Newton steps")
    var n = len(times)
    var seconds = List[Float64]()
    var any_event = False
    for i in range(n):  # pragma: no branch
        seconds.append(times[i].to(SECOND))
        any_event = any_event or events[i]
    if not any_event:
        raise Error("A Cox model needs one event or more")
    var model = CoxModel(k)
    for row in covariates:  # pragma: no branch
        for a in range(k):  # pragma: no branch
            model.means[a] += row[a] / Float64(n)
    var x = List[List[Float64]]()
    for row in covariates:  # pragma: no branch
        var centered = List[Float64]()
        for a in range(k):  # pragma: no branch
            centered.append(row[a] - model.means[a])
        x.append(centered^)
    var order = List[Int]()
    for i in range(n):  # pragma: no branch
        order.append(i)

    def later(a: Int, b: Int) capturing -> Bool:
        return seconds[a] > seconds[b]

    stable_sort[later](order)

    var beta = List[Float64](length=k, fill=0.0)
    var current = _efron(order, seconds, events, x, beta)
    model.null_log_likelihood = current.log_likelihood
    while model.steps < max_steps:
        var step = _newton_step(current)
        model.steps += 1
        var size = 0.0
        for a in range(k):  # pragma: no branch
            size = max(size, abs(step[a]))
        if size < tolerance:
            beta = _moved(beta, step, 1.0)
            current = _efron(order, seconds, events, x, beta)
            model.converged = True
            break
        var scale = 1.0
        var trial = _efron(order, seconds, events, x, _moved(beta, step, 1.0))
        var floor = current.log_likelihood - _SLACK * (
            1.0 + abs(current.log_likelihood)
        )
        for _ in range(_HALVINGS):  # pragma: no branch
            if trial.log_likelihood >= floor:
                break
            scale *= 0.5
            trial = _efron(order, seconds, events, x, _moved(beta, step, scale))
        beta = _moved(beta, step, scale)
        current = trial^
    model.log_likelihood = current.log_likelihood
    # The covariance is the inverse of the information matrix.
    var factor = cholesky(current.information)
    for a in range(k):  # pragma: no branch
        var unit = List[Float64](length=k, fill=0.0)
        unit[a] = 1.0
        var column = solve_lower_transposed(factor, solve_lower(factor, unit))
        model.standard_errors[a] = sqrt(column[a])
        model.coefficients[a] = beta[a]
    var risk = List[Float64]()
    for i in range(n):  # pragma: no branch
        var eta = 0.0
        for a in range(k):  # pragma: no branch
            eta += x[i][a] * beta[a]
        risk.append(eta)
    model.concordance = _concordance(seconds, events, risk)
    # The Breslow baseline: the events at each time over the risk set's
    # sum of relative hazards, from the latest time back.
    var s0 = 0.0
    var at = 0
    var backward = List[Float64]()
    var jumps = List[Float64]()
    while at < n:
        var t = seconds[order[at]]
        var d = 0
        while at < n and seconds[order[at]] == t:
            s0 += exp(risk[order[at]])
            if events[order[at]]:
                d += 1
            at += 1
        if d > 0:
            backward.append(t)
            jumps.append(Float64(d) / s0)
    var hazard = 0.0
    var j = len(backward) - 1
    while j >= 0:
        hazard += jumps[j]
        model.times.append(Duration64(backward[j], SECOND))
        model.cumulative_hazard.append(hazard)
        j -= 1
    return model^
