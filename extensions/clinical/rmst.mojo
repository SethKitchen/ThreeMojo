# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cumulative hazard and the restricted mean survival time of a
Kaplan-Meier curve.

- `nelson_aalen(curve)` gives the cumulative hazard `H(t) = sum(d / n)` at
  each time of an event, with the variance `sum(d (n - d) / n^3)` and a
  log interval, as lifelines gives them without smoothing.
- `restricted_mean(curve, horizon)` gives the restricted mean survival time
  (RMST): the area under the curve from 0 to the horizon. It is the mean
  time free of the event over that span. Its standard error is that of
  Klein and Moeschberger, as R's survRM2 gives.
- `compare_restricted_means` gives the difference of the RMST of two
  groups, with its test.

The RMST does not need proportional hazards, and it is in units of time.
"""

from extensions.clinical.distributions import precise_exp
from extensions.clinical.survival import SurvivalCurve, Z95
from std.math import erfc, isfinite, sqrt
from units.si import Duration64, SECOND


struct CumulativeHazard(Copyable, Movable):
    """The Nelson-Aalen cumulative hazard of a group."""

    var times: List[Duration64]
    """Each time of an event, rising."""
    var hazard: List[Float64]
    """The cumulative hazard just after each time."""
    var variance: List[Float64]
    """The variance of the cumulative hazard at each time."""

    def __init__(out self):
        """Create an empty hazard."""
        self.times = List[Duration64]()
        self.hazard = List[Float64]()
        self.variance = List[Float64]()

    def interval(self, index: Int) raises -> Tuple[Float64, Float64]:
        """Return the 95 percent interval of the hazard at a time.

        Args:
            index: The time, from 0, in `times`.

        Returns:
            `H exp(-+ 1.96 sqrt(v) / H)`.

        Raises:
            Error: If the index names no time.
        """
        if index < 0 or index >= len(self.times):
            raise Error("A cumulative hazard has no time of that index")
        var h = self.hazard[index]
        var spread = Z95 * sqrt(self.variance[index]) / h
        return (h * precise_exp(-spread), h * precise_exp(spread))


def nelson_aalen(curve: SurvivalCurve) -> CumulativeHazard:
    """Return the Nelson-Aalen cumulative hazard of a group.

    Args:
        curve: The Kaplan-Meier curve of the group, from `kaplan_meier`,
            which holds the patients at risk and the events at each time.

    Returns:
        The cumulative hazard at each time of an event.
    """
    var out = CumulativeHazard()
    var hazard = 0.0
    var variance = 0.0
    for j in range(len(curve.times)):
        var n = Float64(curve.at_risk[j])
        var d = Float64(curve.events[j])
        hazard += d / n
        variance += d * (n - d) / (n * n * n)
        out.times.append(curve.times[j])
        out.hazard.append(hazard)
        out.variance.append(variance)
    return out^


struct RestrictedMean(Copyable, Movable):
    """The restricted mean survival time of a group."""

    var mean: Duration64
    """The area under the survival curve from 0 to the horizon."""
    var standard_error: Duration64
    """Its standard error."""
    var horizon: Duration64
    """The end of the span."""

    def __init__(
        out self,
        mean: Duration64,
        standard_error: Duration64,
        horizon: Duration64,
    ):
        """Create a result.

        Args:
            mean: The restricted mean.
            standard_error: Its standard error.
            horizon: The end of the span.
        """
        self.mean = mean
        self.standard_error = standard_error
        self.horizon = horizon

    def interval(self) -> Tuple[Duration64, Duration64]:
        """Return the 95 percent interval of the restricted mean.

        Returns:
            The mean `-+ 1.96 se`.
        """
        var m = self.mean.to(SECOND)
        var half = Z95 * self.standard_error.to(SECOND)
        return (Duration64(m - half, SECOND), Duration64(m + half, SECOND))


def _horizon(horizon: Duration64) raises -> Float64:
    """Return the horizon in seconds, or refuse one that is not positive and
    finite."""
    var tau = horizon.to(SECOND)
    if not (tau > 0) or not isfinite(tau):
        raise Error("The horizon of a restricted mean must be positive")
    return tau


def _area_and_variance(
    curve: SurvivalCurve, tau: Float64
) -> Tuple[Float64, Float64]:
    """Return the area under the curve to tau, and the variance of Klein
    and Moeschberger: the sum of `A_j^2 d_j / (n_j (n_j - d_j))` over the
    times of events up to tau, with `A_j` the area from `t_j` to tau."""
    var last = 0
    while last < len(curve.times) and curve.times[last].to(SECOND) <= tau:
        last += 1
    # The area after the last event before tau, then back to the first.
    var tail = 0.0
    var variance = 0.0
    var j = last - 1
    var right = tau
    while j >= 0:
        var t = curve.times[j].to(SECOND)
        tail += curve.survival[j] * (right - t)
        right = t
        var n = Float64(curve.at_risk[j])
        var d = Float64(curve.events[j])
        if d < n:
            variance += tail * tail * d / (n * (n - d))
        j -= 1
    # Before the first event the survival is 1.
    return (tail + right, variance)


def restricted_mean(
    curve: SurvivalCurve, horizon: Duration64
) raises -> RestrictedMean:
    """Return the restricted mean survival time of a group.

    Args:
        curve: The Kaplan-Meier curve of the group.
        horizon: The end of the span. Positive and finite. Choose it where
            patients are still at risk.

    Returns:
        The area under the curve from 0 to the horizon, and its standard
        error.

    Raises:
        Error: If the horizon is not positive and finite.
    """
    var tau = _horizon(horizon)
    var result = _area_and_variance(curve, tau)
    return RestrictedMean(
        Duration64(result[0], SECOND),
        Duration64(sqrt(result[1]), SECOND),
        horizon,
    )


struct RestrictedComparison(Copyable, Movable):
    """The difference of the restricted mean survival time of two
    groups."""

    var difference: Duration64
    """The first restricted mean less the second."""
    var standard_error: Duration64
    """The standard error of the difference."""
    var z: Float64
    """The difference over its standard error."""
    var p_value: Float64
    """The two-sided chance of a z this far from 0 when the groups have one
    restricted mean."""

    def __init__(out self, first: RestrictedMean, second: RestrictedMean):
        """Compare two restricted means.

        Args:
            first: The restricted mean of the first group.
            second: The restricted mean of the second group.
        """
        var gap = first.mean.to(SECOND) - second.mean.to(SECOND)
        var a = first.standard_error.to(SECOND)
        var b = second.standard_error.to(SECOND)
        var error = sqrt(a * a + b * b)
        self.difference = Duration64(gap, SECOND)
        self.standard_error = Duration64(error, SECOND)
        self.z = 0.0
        if error > 0:
            self.z = gap / error
        self.p_value = erfc(abs(self.z) / sqrt(2.0))

    def interval(self) -> Tuple[Duration64, Duration64]:
        """Return the 95 percent interval of the difference.

        Returns:
            The difference `-+ 1.96 se`.
        """
        var g = self.difference.to(SECOND)
        var half = Z95 * self.standard_error.to(SECOND)
        return (Duration64(g - half, SECOND), Duration64(g + half, SECOND))


def compare_restricted_means(
    first: SurvivalCurve, second: SurvivalCurve, horizon: Duration64
) raises -> RestrictedComparison:
    """Compare the restricted mean survival time of two groups.

    Args:
        first: The Kaplan-Meier curve of the first group.
        second: The Kaplan-Meier curve of the second group.
        horizon: The end of the span, the same for both. Positive and
            finite.

    Returns:
        The difference, first less second, with its test.

    Raises:
        Error: If the horizon is not positive and finite.
    """
    return RestrictedComparison(
        restricted_mean(first, horizon), restricted_mean(second, horizon)
    )
