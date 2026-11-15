# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Observational studies: propensity scores, inverse probability weights,
covariate balance and the E-value.

In an observational study, the patients who get a treatment differ from
those who do not. The propensity score is the chance of each patient to
get the treatment, given the covariates, from a logistic model. Weight
each patient by the inverse of the chance of the treatment that the
patient got. In the weighted population, the covariates no longer predict
the treatment.

- `ipw_effect(treated, outcomes, covariates)` fits the propensity model.
  It gives the weighted mean outcome under each treatment and their
  difference, the average treatment effect. The standard errors come from
  the sandwich of the stacked estimating equations, so they take the
  propensity fit into account, as statsmodels' `TreatmentEffect.ipw` gives
  them.
- `standardized_difference(values, treated, weights)` measures the balance
  of a covariate, as Austin and Stuart (2015) give it.
- `effective_sample_size(weights)` is Kish's `(sum w)^2 / sum w^2`.
- `e_value(ratio)` and `e_value_bound(lower, upper)` give the E-value of
  VanderWeele and Ding (2017). It is the least risk ratio that an
  unmeasured confounder needs with both the treatment and the outcome to
  explain the effect away.

The weights remove the confounding of the measured covariates only.
"""

from extensions.clinical.logistic import logistic_regression
from extensions.clinical.proportions import Estimate
from extensions.numerics.dense import DenseMatrix, inverse
from std.math import isfinite, sqrt
from extensions.numerics.distributions import (
    normal_two_sided,
    ratio_interval,
    wald_interval,
)


struct IpwEffect(Copyable, Movable):
    """The inverse probability weighted effect of a treatment."""

    var difference: Float64
    """The average treatment effect: the treated mean less the control
    mean."""
    var difference_error: Float64
    """The standard error of the difference."""
    var treated_mean: Float64
    """The weighted mean outcome if every patient were treated."""
    var treated_error: Float64
    """The standard error of the treated mean."""
    var control_mean: Float64
    """The weighted mean outcome if no patient were treated."""
    var control_error: Float64
    """The standard error of the control mean."""
    var covariance: Float64
    """The covariance of the treated and the control means."""
    var propensity: List[Float64]
    """The propensity score of each patient."""
    var weights: List[Float64]
    """The weight of each patient: `1 / p` if treated, `1 / (1 - p)` if
    not."""
    var converged: Bool
    """Whether the propensity model converged in 100 Newton steps."""

    def __init__(out self):
        """Create an empty effect."""
        self.difference = 0.0
        self.difference_error = 0.0
        self.treated_mean = 0.0
        self.treated_error = 0.0
        self.control_mean = 0.0
        self.control_error = 0.0
        self.covariance = 0.0
        self.propensity = List[Float64]()
        self.weights = List[Float64]()
        self.converged = False

    def interval(self) -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the difference.

        Returns:
            The low and the high end, `difference -+ 1.96 se`.
        """
        return wald_interval(self.difference, self.difference_error)

    def p_value(self) -> Float64:
        """Return the two-sided p value of the difference.

        Returns:
            The chance of a difference this far from 0 when the treatment
            has no effect.
        """
        var z = self.difference / self.difference_error
        return normal_two_sided(z)

    def ratio_error(self) raises -> Float64:
        """Return the standard error of the log of the ratio of the means.

        Returns:
            The error by the delta method, with the covariance of the means.

        Raises:
            Error: If a mean is not above 0.
        """
        if not (self.treated_mean > 0 and self.control_mean > 0):
            raise Error("A ratio of means needs means above 0")
        var t = self.treated_mean
        var c = self.control_mean
        return sqrt(
            self.treated_error * self.treated_error / (t * t)
            + self.control_error * self.control_error / (c * c)
            - 2.0 * self.covariance / (t * c)
        )

    def ratio(self) raises -> Estimate:
        """Return the ratio of the treated to the control mean.

        For an outcome of 1 or 0, it is the risk ratio.

        Returns:
            The ratio with its 95 percent interval, `exp(log r -+ 1.96 se)`.

        Raises:
            Error: If a mean is not above 0.
        """
        var r = self.treated_mean / self.control_mean
        var band = ratio_interval(r, self.ratio_error())
        return Estimate(r, band[0], band[1])


def ipw_effect(
    treated: List[Bool],
    outcomes: List[Float64],
    covariates: List[List[Float64]],
) raises -> IpwEffect:
    """Estimate the effect of a treatment by inverse probability weights.

    The means are the weighted means of each group, with the weights
    normalized in each group.

    Args:
        treated: Whether each patient got the treatment.
        outcomes: The outcome of each patient, such as 1 or 0.
        covariates: One row for each patient, of the covariates that
            predict the treatment.

    Returns:
        The two means, their difference and their errors, the propensity
        score and the weight of each patient.

    Raises:
        Error: If the outcomes are not one finite value for each patient,
            or the propensity model refuses the covariates or the
            treatments, as `logistic_regression` does.
    """
    var n = len(treated)
    if len(outcomes) != n:
        raise Error("An effect needs one outcome for each patient")
    for y in outcomes:  # pragma: no branch
        if not isfinite(y):
            raise Error("The outcomes must be finite")
    var model = logistic_regression(treated, covariates, 1e-10, 100)
    var out = IpwEffect()
    out.converged = model.converged
    var k = len(covariates[0]) + 1
    var top_t = 0.0
    var bottom_t = 0.0
    var top_c = 0.0
    var bottom_c = 0.0
    for i in range(n):  # pragma: no branch
        var p = model.risk(covariates[i])
        out.propensity.append(p)
        var w = 1.0 / p if treated[i] else 1.0 / (1.0 - p)
        out.weights.append(w)
        if treated[i]:
            top_t += w * outcomes[i]
            bottom_t += w
        else:
            top_c += w * outcomes[i]
            bottom_c += w
    out.treated_mean = top_t / bottom_t
    out.control_mean = top_c / bottom_c
    out.difference = out.treated_mean - out.control_mean
    # The sandwich of the moments (w r t, w r, (t - p) x), with r the
    # residual y - tau t - mu0 and x the covariates after a 1.
    var m = k + 2
    var jacobian = DenseMatrix(m, m)
    var spread = DenseMatrix(m, m)
    var size = Float64(n)
    for i in range(n):  # pragma: no branch
        var p = out.propensity[i]
        var w = out.weights[i]
        var t = 1.0 if treated[i] else 0.0
        var r = outcomes[i] - out.difference * t - out.control_mean
        var slope = -(1.0 - p) / p if treated[i] else p / (1.0 - p)
        var row = List[Float64]()
        row.append(1.0)
        for v in covariates[i]:  # pragma: no branch
            row.append(v)
        var g = List[Float64]()
        g.append(w * r * t)
        g.append(w * r)
        for a in range(k):  # pragma: no branch
            g.append((t - p) * row[a])
        jacobian.add(0, 0, -w * t / size)
        jacobian.add(0, 1, -w * t / size)
        jacobian.add(1, 0, -w * t / size)
        jacobian.add(1, 1, -w / size)
        for a in range(k):  # pragma: no branch
            jacobian.add(0, 2 + a, slope * row[a] * r * t / size)
            jacobian.add(1, 2 + a, slope * row[a] * r / size)
            for b in range(k):  # pragma: no branch
                jacobian.add(
                    2 + a, 2 + b, -p * (1.0 - p) * row[a] * row[b] / size
                )
        for a in range(m):  # pragma: no branch
            for b in range(m):  # pragma: no branch
                spread.add(a, b, g[a] * g[b] / size)
    # V = J^-1 S J^-T / n, as T^T S T with T = J^-T.
    var v = inverse(jacobian).transposed().triple_product(spread)
    var var_tau = v.get(0, 0) / size
    var var_mu0 = v.get(1, 1) / size
    var cov = v.get(0, 1) / size
    out.difference_error = sqrt(var_tau)
    out.control_error = sqrt(var_mu0)
    out.treated_error = sqrt(var_tau + var_mu0 + 2.0 * cov)
    out.covariance = cov + var_mu0
    return out^


def _require_weights(weights: List[Float64]) raises:
    """Refuse no weight, or a weight that is not positive and finite."""
    if len(weights) == 0:
        raise Error("A weighting needs one weight or more")
    for w in weights:  # pragma: no branch
        if not (w > 0) or not isfinite(w):
            raise Error("A weight must be positive and finite")


def _weighted(
    values: List[Float64], weights: List[Float64]
) raises -> Tuple[Float64, Float64]:
    """Return the weighted mean and variance of a group."""
    if len(values) < 2:
        raise Error(
            "A standardized difference needs two patients in each group"
        )
    var total = 0.0
    var squares = 0.0
    var sum = 0.0
    for i in range(len(values)):  # pragma: no branch
        total += weights[i]
        squares += weights[i] * weights[i]
        sum += weights[i] * values[i]
    var mean = sum / total
    var spread = 0.0
    for i in range(len(values)):  # pragma: no branch
        var d = values[i] - mean
        spread += weights[i] * d * d
    return (mean, total / (total * total - squares) * spread)


def standardized_difference(
    values: List[Float64], treated: List[Bool], weights: List[Float64]
) raises -> Float64:
    """Return the standardized difference of a covariate between the groups.

    The difference of the weighted means over the root of the mean of the
    two weighted variances. A weighted variance is
    `sum w / ((sum w)^2 - sum w^2) * sum w (x - mean)^2`. Below 0.1 is
    usually taken as balanced. Give weights of 1 for the balance before
    weighting.

    Args:
        values: The covariate of each patient.
        treated: Whether each patient got the treatment.
        weights: The weight of each patient.

    Returns:
        `(m1 - m0) / sqrt((v1 + v0) / 2)`.

    Raises:
        Error: If the lists differ in length, a value is not finite, a
            weight is not positive and finite, a group has fewer than two
            patients, or the covariate does not vary.
    """
    _require_weights(weights)
    if len(values) != len(weights) or len(treated) != len(weights):
        raise Error(
            "A standardized difference needs one value and weight per patient"
        )
    var groups = List[List[Float64]](length=2, fill=List[Float64]())
    var shares = List[List[Float64]](length=2, fill=List[Float64]())
    for i in range(len(values)):  # pragma: no branch
        if not isfinite(values[i]):
            raise Error("A covariate must be finite")
        var g = 1 if treated[i] else 0
        groups[g].append(values[i])
        shares[g].append(weights[i])
    var one = _weighted(groups[1], shares[1])
    var zero = _weighted(groups[0], shares[0])
    var pooled = (one[1] + zero[1]) / 2.0
    if not (pooled > 0):
        raise Error("A standardized difference needs a covariate that varies")
    return (one[0] - zero[0]) / sqrt(pooled)


def effective_sample_size(weights: List[Float64]) raises -> Float64:
    """Return Kish's effective sample size of weighted patients.

    Args:
        weights: The weight of each patient, such as those of one group.

    Returns:
        `(sum w)^2 / sum w^2`: the patients of equal weight that carry as
        much information.

    Raises:
        Error: If there is no weight, or a weight is not positive and
            finite.
    """
    _require_weights(weights)
    var total = 0.0
    var squares = 0.0
    for w in weights:  # pragma: no branch
        total += w
        squares += w * w
    return total * total / squares


def e_value(ratio: Float64) raises -> Float64:
    """Return the E-value of a risk ratio.

    Args:
        ratio: The risk ratio, positive and finite. A ratio below 1 takes
            its inverse.

    Returns:
        `RR + sqrt(RR (RR - 1))`.

    Raises:
        Error: If the ratio is not positive and finite.
    """
    if not (ratio > 0) or not isfinite(ratio):
        raise Error("An E-value needs a positive, finite ratio")
    var rr = ratio if ratio >= 1 else 1.0 / ratio
    return rr + sqrt(rr * (rr - 1.0))


def e_value_bound(lower: Float64, upper: Float64) raises -> Float64:
    """Return the E-value of the end of an interval nearest to 1.

    Args:
        lower: The low end of the interval of a risk ratio.
        upper: The high end.

    Returns:
        1 when the interval holds 1, else the E-value of the end nearest
        to 1.

    Raises:
        Error: If an end is not positive and finite, or the ends fall.
    """
    if not (lower > 0 and lower <= upper) or not isfinite(upper):
        raise Error("An E-value needs a positive, finite interval that rises")
    if lower > 1:
        return e_value(lower)
    if upper < 1:
        return e_value(upper)
    return 1.0
