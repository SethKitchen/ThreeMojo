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

The exact intervals come from the gamma distribution:

- `gamma_tails(x, a)` gives the regularized incomplete gamma functions
  P(a, x) and Q(a, x), by the series or the continued fraction of
  Numerical Recipes, section 6.2.
- `gamma_quantile(p, a)` inverts P by Newton steps, kept in a bracket by
  bisection.
- `poisson_interval(count)` gives the exact central 95 percent interval of
  the mean of a Poisson count, of Garwood (1936).
"""

from extensions.clinical.distributions import precise_exp
from extensions.clinical.survival import require_group
from std.math import inf, isfinite, lgamma, log
from units.si import Duration64, Frequency64, PER_SECOND, SECOND

comptime MAX_SHAPE = 1e7
"""The largest shape of a gamma distribution here."""
# The most terms of a series or a fraction, and the most steps of a search.
comptime _TERMS = 100000
comptime _SEARCH = 400
comptime _EPSILON = 1e-17
comptime _TINY = 1e-300
# The tail of each end of a 95 percent interval.
comptime _TAIL = 0.025


def _require_shape(a: Float64) raises:
    """Refuse a shape that is not above 0 and at most MAX_SHAPE."""
    if not (a > 0 and a <= MAX_SHAPE):
        raise Error("A gamma shape must be above 0 and at most 1e7")


def _front(x: Float64, a: Float64) -> Float64:
    """Return `x^a e^-x / Gamma(a)` for x above 0."""
    return precise_exp(a * log(x) - x - lgamma(a))


def _tails(x: Float64, a: Float64) -> Tuple[Float64, Float64]:
    """Return P(a, x) and Q(a, x) for an x of 0 or more."""
    if x == 0:
        return (0.0, 1.0)
    if not isfinite(x):
        return (1.0, 0.0)
    if x < a + 1.0:
        # The series: P = front sum x^n / (a (a + 1) ... (a + n)).
        var term = 1.0 / a
        var sum = term
        var n = a
        for _ in range(_TERMS):  # pragma: no branch
            n += 1.0
            term *= x / n
            sum += term
            if abs(term) < abs(sum) * _EPSILON:
                break
        var lower = sum * _front(x, a)
        return (lower, 1.0 - lower)
    # The continued fraction of Q, by the modified Lentz method. For x at
    # or above a + 1, its denominators stay well away from 0.
    var b = x + 1.0 - a
    var c = 1.0 / _TINY
    var d = 1.0 / b
    var h = d
    for i in range(1, _TERMS):  # pragma: no branch
        var an = -Float64(i) * (Float64(i) - a)
        b += 2.0
        d = 1.0 / (an * d + b)
        c = b + an / c
        var delta = d * c
        h *= delta
        if abs(delta - 1.0) < _EPSILON:
            break
    var upper = _front(x, a) * h
    return (1.0 - upper, upper)


def gamma_tails(x: Float64, a: Float64) raises -> Tuple[Float64, Float64]:
    """Return both tails of the gamma distribution of unit scale.

    Args:
        x: The point, 0 or more. Infinity gives 1 and 0.
        a: The shape, above 0 and at most 1e7.

    Returns:
        The regularized incomplete gamma functions P(a, x) and Q(a, x).
        The smaller of the two keeps its relative accuracy far out.

    Raises:
        Error: If the point is below 0 or not a number, or the shape is out
            of range.
    """
    _require_shape(a)
    if not (x >= 0):
        raise Error("A gamma point must be 0 or more")
    return _tails(x, a)


def _gap(x: Float64, a: Float64, target: Float64, upper: Bool) -> Float64:
    """Return P(a, x) less the target, or the target less Q(a, x) when
    `upper`. Both rise with x."""
    var tails = _tails(x, a)
    if upper:
        return target - tails[1]
    return tails[0] - target


def _invert(target: Float64, a: Float64, upper: Bool) -> Float64:
    """Return the x with P(a, x) = target, or Q(a, x) = target when
    `upper`, for a target between 0 and 1/2."""
    # A first guess from the far tail of each side.
    var x = a - log(target)
    if not upper:
        x = min(precise_exp((log(target) + lgamma(a + 1.0)) / a), a)
    var low = 0.0
    var high = max(2.0 * x, 1.0)
    while not (_gap(high, a, target, upper) > 0):
        low = high
        high *= 2.0
    # The guess is below the first `high`; only a wider bracket passes it.
    if not (x > low):
        x = 0.5 * (low + high)
    for _ in range(_SEARCH):  # pragma: no branch
        var gap = _gap(x, a, target, upper)
        if gap > 0:
            high = x
        else:
            low = x
        var density = precise_exp((a - 1.0) * log(x) - x - lgamma(a))
        var next = x - gap / density
        if not (next > low and next < high):
            next = 0.5 * (low + high)
        if abs(next - x) <= 4e-16 * next:
            x = next
            break
        x = next
    return x


def gamma_quantile(p: Float64, a: Float64) raises -> Float64:
    """Return the quantile of the gamma distribution of unit scale.

    Args:
        p: The probability, above 0 and below 1.
        a: The shape, above 0 and at most 1e7.

    Returns:
        The x with P(a, x) = p. Above a half, the search runs on Q, so a
        large x keeps its accuracy.

    Raises:
        Error: If the probability or the shape is out of range.
    """
    _require_shape(a)
    if not (p > 0 and p < 1):
        raise Error("A gamma quantile needs a probability above 0, below 1")
    if p <= 0.5:
        return _invert(p, a, False)
    return _invert(1.0 - p, a, True)


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
        low = _invert(_TAIL, Float64(count), False)
    return (low, _invert(_TAIL, Float64(count) + 1.0, True))


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
    var below = _tails(expected, Float64(observed) + 1.0)[1]
    var above = 1.0
    if observed > 0:
        above = _tails(expected, Float64(observed))[0]
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
            is below 0, a person-time is not positive and finite, or the
            shares are not 0 or more and finite with a sum of 1.
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
        low = variance / rate * _invert(_TAIL, rate * rate / variance, False)
    var v = variance + top * top
    var m = rate + top
    var high = v / m * _invert(_TAIL, m * m / v, True)
    return DirectRate(
        Frequency64(rate, PER_SECOND),
        Frequency64(low, PER_SECOND),
        Frequency64(high, PER_SECOND),
    )
