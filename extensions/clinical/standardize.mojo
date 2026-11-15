# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rates and standardization: exact Poisson intervals, standardized
ratios such as the SMR, and directly standardized rates.

Two groups with different ages have different rates of death, even when
the risk at each age is the same. Standardization takes the ages out:

- Indirect: `expected_events` applies the rates of a reference population
  at each age to the person-time of a cohort. `standardized_ratio` gives
  the observed over the expected events, such as the standardized
  mortality ratio (SMR), with its exact interval and p value.
- Direct: `direct_rate` weights the rate of each age group by its share
  of a standard population, with the gamma interval of Fay and Feuer
  (1997).

The exact intervals come from the gamma functions of
`numerics.distributions`. `poisson_interval(count)` gives the exact
central 95 percent interval of the mean of a Poisson count, of Garwood
(1936).
"""

from extensions.numerics.distributions import (
    MAX_SHAPE,
    gamma_quantile,
    gamma_tails,
    gamma_upper_quantile,
)
from std.math import isfinite
from units.si import Duration64, Frequency64, PER_SECOND, SECOND

# The tail of each end of a 95 percent interval.
comptime _TAIL = 0.025


def _require_count(count: Int) raises:
    """Refuse a count below 0 or too large for the gamma functions."""
    if count < 0 or Float64(count) >= MAX_SHAPE:
        raise Error("A Poisson count must be from 0 to below 1e7")


def poisson_interval(count: Int) raises -> Tuple[Float64, Float64]:
    """Return the exact central 95 percent interval of a Poisson mean.

    Args:
        count: The observed count, from 0 to below 1e7.

    Returns:
        The low end, the 2.5 percent point of a gamma of shape `count`,
        or 0 for a count of 0, and the high end, the 97.5 percent point of
        a gamma of shape `count + 1`, after Garwood (1936).

    Raises:
        Error: If the count is out of range.
    """
    _require_count(count)
    var low = 0.0
    if count > 0:
        low = gamma_quantile(_TAIL, Float64(count))
    return (low, gamma_upper_quantile(_TAIL, Float64(count) + 1.0))


struct StandardizedRatio(Copyable, Movable):
    """The observed over the expected count of events, such as an SMR."""

    var observed: Int
    """The observed events."""
    var expected: Float64
    """The expected events."""
    var ratio: Float64
    """The observed over the expected events."""
    var lower: Float64
    """The low end of the exact 95 percent interval of the ratio."""
    var upper: Float64
    """The high end of the exact 95 percent interval of the ratio."""
    var p_value: Float64
    """The exact central p value of a ratio of 1: twice the smaller tail
    of the observed count, at most 1."""

    def __init__(
        out self,
        observed: Int,
        expected: Float64,
        lower: Float64,
        upper: Float64,
        p_value: Float64,
    ):
        """Create a ratio.

        Args:
            observed: The observed events.
            expected: The expected events, above 0.
            lower: The low end of the interval.
            upper: The high end of the interval.
            p_value: The p value.
        """
        self.observed = observed
        self.expected = expected
        self.ratio = Float64(observed) / expected
        self.lower = lower
        self.upper = upper
        self.p_value = p_value


def standardized_ratio(
    observed: Int, expected: Float64
) raises -> StandardizedRatio:
    """Return the standardized ratio of observed to expected events.

    Args:
        observed: The observed events, from 0 to below 1e7.
        expected: The expected events, above 0 and finite, such as from
            `expected_events`.

    Returns:
        The ratio, its exact interval from `poisson_interval` over the
        expected count, and its exact central p value from the Poisson
        distribution of mean `expected`.

    Raises:
        Error: If the count is out of range, or the expected count is not
            positive and finite.
    """
    _require_count(observed)
    if not (expected > 0) or not isfinite(expected):
        raise Error("An expected count must be positive and finite")
    var band = poisson_interval(observed)
    # P(X <= O) is Q(O + 1, E), and P(X >= O) is P(O, E), or 1 at O = 0.
    var below = gamma_tails(expected, Float64(observed) + 1.0)[1]
    var above = 1.0
    if observed > 0:
        above = gamma_tails(expected, Float64(observed))[0]
    var p = min(1.0, 2.0 * min(below, above))
    return StandardizedRatio(
        observed, expected, band[0] / expected, band[1] / expected, p
    )


def expected_events(
    person_time: List[Duration64], rates: List[Frequency64]
) raises -> Float64:
    """Return the events that a cohort would have at the rates of a
    reference population.

    Args:
        person_time: The person-time of the cohort in each group, such as
            each band of age, 0 or more and finite.
        rates: The rate of the reference population in each group, 0 or
            more and finite.

    Returns:
        `sum T_i r_i`.

    Raises:
        Error: If the lists differ in length or are empty, or a value is
            below 0 or not finite.
    """
    if len(person_time) == 0 or len(person_time) != len(rates):
        raise Error("Expected events need one rate for each group")
    var total = 0.0
    for i in range(len(rates)):  # pragma: no branch
        var t = person_time[i].to(SECOND)
        var r = rates[i].to(PER_SECOND)
        if not (t >= 0) or not isfinite(t) or not (r >= 0) or not isfinite(r):
            raise Error("A person-time and a rate must be 0 or more, finite")
        total += t * r
    return total


struct DirectRate(Copyable, Movable):
    """A directly standardized rate, with its interval."""

    var rate: Frequency64
    """The rate: the rate of each group weighted by its standard share."""
    var lower: Frequency64
    """The low end of the 95 percent interval of Fay and Feuer."""
    var upper: Frequency64
    """The high end of the 95 percent interval of Fay and Feuer."""

    def __init__(
        out self, rate: Frequency64, lower: Frequency64, upper: Frequency64
    ):
        """Create a rate.

        Args:
            rate: The rate.
            lower: The low end of the interval.
            upper: The high end of the interval.
        """
        self.rate = rate
        self.lower = lower
        self.upper = upper


def direct_rate(
    events: List[Int], person_time: List[Duration64], shares: List[Float64]
) raises -> DirectRate:
    """Return the directly standardized rate of a cohort.

    With `y_i = w_i / T_i`, the rate is `R = sum y_i d_i` and its variance
    is `V = sum y_i^2 d_i`. The interval of Fay and Feuer (1997) runs from
    the 2.5 percent point of a gamma of mean R and variance V to the 97.5
    percent point of a gamma of mean `R + m` and variance `V + m^2`, with
    m the largest `y_i`.

    Args:
        events: The events of each group, 0 or more.
        person_time: The person-time of each group, positive and finite.
        shares: The share of each group in the standard population, 0 or
            more and finite, with a sum of 1.

    Returns:
        The rate and its interval. With no event, the low end is 0.

    Raises:
        Error: If the lists differ in length or are empty, an event count
            is below 0, a person-time is not positive and finite, the
            shares are not 0 or more and finite with a sum of 1, or an end
            of the interval needs a gamma shape above 1e7.
    """
    var n = len(events)
    if n == 0 or len(person_time) != n or len(shares) != n:
        raise Error("A direct rate needs events, person-time and a share")
    var sum = 0.0
    var rate = 0.0
    var variance = 0.0
    var top = 0.0
    for i in range(n):  # pragma: no branch
        var t = person_time[i].to(SECOND)
        if events[i] < 0:
            raise Error("An event count must be 0 or more")
        if not (t > 0) or not isfinite(t):
            raise Error("A person-time must be positive and finite")
        if not (shares[i] >= 0) or not isfinite(shares[i]):
            raise Error("A standard share must be 0 or more, and finite")
        sum += shares[i]
        var y = shares[i] / t
        rate += y * Float64(events[i])
        variance += y * y * Float64(events[i])
        top = max(top, y)
    if abs(sum - 1.0) > 1e-9:
        raise Error("The standard shares must sum to 1")
    var low = 0.0
    if rate > 0:
        low = variance / rate * gamma_quantile(_TAIL, rate * rate / variance)
    var v = variance + top * top
    var m = rate + top
    var high = v / m * gamma_upper_quantile(_TAIL, m * m / v)
    return DirectRate(
        Frequency64(rate, PER_SECOND),
        Frequency64(low, PER_SECOND),
        Frequency64(high, PER_SECOND),
    )
