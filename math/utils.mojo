# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scalar helpers, from three.js `src/math/MathUtils.js`.

three.js's `degToRad` and `radToDeg` are not here: an `Angle` converts
itself. `smoothstep` is in `math.smoothstep`, where both rasterizers
already read it.

The random numbers come from a `SeededRandom`, three.js's Mulberry32
generator, so that a sequence is the same on every run and every
platform. three.js's unseeded `randFloat` reads `Math.random`; a caller
here keeps a generator and asks it.
"""

from math.smoothstep import smoothstep
from std.math import exp, floor
from units.si import Duration, SECOND


def clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return `value` limited to the range from `low` to `high`.

    Args:
        value: The value.
        low: The smallest answer.
        high: The largest answer.

    Returns:
        The value within the range.
    """
    return max(low, min(high, value))


def lerp(x: Float32, y: Float32, t: Float32) -> Float32:
    """Return the value a fraction `t` of the way from `x` to `y`.

    Args:
        x: The start.
        y: The end.
        t: The fraction.

    Returns:
        `(1 - t) x + t y`.
    """
    return (1 - t) * x + t * y


def inverse_lerp(x: Float32, y: Float32, value: Float32) -> Float32:
    """Return the fraction of the way `value` lies from `x` to `y`.

    Args:
        x: The start.
        y: The end.
        value: The value.

    Returns:
        The fraction, or zero when the ends are equal, as in three.js.
    """
    if x == y:
        return 0
    return (value - x) / (y - x)


def map_linear(
    value: Float32, a1: Float32, a2: Float32, b1: Float32, b2: Float32
) -> Float32:
    """Map a value from one range to another.

    Args:
        value: The value in the first range.
        a1: The first range's start.
        a2: The first range's end.
        b1: The second range's start.
        b2: The second range's end.

    Returns:
        The value at the same fraction of the second range.
    """
    return b1 + (value - a1) * (b2 - b1) / (a2 - a1)


def damp(x: Float32, y: Float32, rate: Float32, delta: Duration) -> Float32:
    """Move `x` toward `y` at a rate that does not depend on the frame
    rate.

    Args:
        x: The current value.
        y: The target.
        rate: How fast, per second. Larger is faster.
        delta: The time since the last step.

    Returns:
        The damped value.
    """
    return lerp(x, y, 1 - exp(-rate * delta.to(SECOND)))


def euclidean_modulo(n: Float32, m: Float32) -> Float32:
    """Return the remainder of `n / m`, always with the sign of `m`.

    Args:
        n: The dividend.
        m: The divisor.

    Returns:
        A value from zero up to, not including, `m`.
    """
    return ((n % m) + m) % m


def pingpong(x: Float32, length: Float32 = 1) -> Float32:
    """Return a value that runs from zero to `length` and back.

    Args:
        x: The input.
        length: The peak.

    Returns:
        A value from zero to `length`.
    """
    return length - abs(euclidean_modulo(x, length * 2) - length)


def smootherstep(x: Float32, low: Float32, high: Float32) -> Float32:
    """Return Ken Perlin's smootherstep: a rise from zero to one with a
    flat first and second derivative at each end.

    Args:
        x: The value.
        low: Where the rise starts.
        high: Where the rise ends.

    Returns:
        A number from zero to one.
    """
    if x <= low:
        return 0
    if x >= high:
        return 1
    var t = (x - low) / (high - low)
    return t * t * t * (t * (t * 6 - 15) + 10)


def smooth_step(x: Float32, low: Float32, high: Float32) -> Float32:
    """Return three.js's `smoothstep(x, min, max)`, with its argument
    order.

    Args:
        x: The value.
        low: Where the rise starts.
        high: Where the rise ends.

    Returns:
        A number from zero to one.
    """
    return smoothstep(low, high, x)


def is_power_of_two(value: Int) -> Bool:
    """Return True if `value` is a positive power of two.

    Args:
        value: The number.

    Returns:
        Whether one bit of it is set.
    """
    return value > 0 and (value & (value - 1)) == 0


def ceil_power_of_two(value: Int) raises -> Int:
    """Return the smallest power of two at least `value`.

    Args:
        value: A positive number.

    Returns:
        The power of two.

    Raises:
        Error: If the value is not positive.
    """
    if value <= 0:
        raise Error("Only a positive number has a power of two above it")
    var power = 1
    while power < value:
        power <<= 1
    return power


def floor_power_of_two(value: Int) raises -> Int:
    """Return the largest power of two at most `value`.

    Args:
        value: A positive number.

    Returns:
        The power of two.

    Raises:
        Error: If the value is not positive.
    """
    if value <= 0:
        raise Error("Only a positive number has a power of two below it")
    var power = 1
    while power * 2 <= value:
        power <<= 1
    return power


struct SeededRandom(Copyable, Movable):
    """The Mulberry32 generator of three.js's `seededRandom`.

    One generator gives the same numbers from the same seed, on every
    platform.
    """

    var state: UInt32

    def __init__(out self, seed: Int):
        """Create a generator.

        Args:
            seed: The seed. Only its low 32 bits are kept.
        """
        self.state = UInt32(seed & 0xFFFFFFFF)

    def next(mut self) -> Float64:
        """Return the next number.

        Returns:
            A number from zero up to, not including, one.
        """
        self.state = self.state + 0x6D2B79F5
        var t = self.state
        t = (t ^ (t >> 15)) * (t | 1)
        t ^= t + (t ^ (t >> 7)) * (t | 61)
        return Float64(t ^ (t >> 14)) / 4294967296.0

    def float_in(mut self, low: Float32, high: Float32) -> Float32:
        """Return a number in a range. three.js: `randFloat`.

        Args:
            low: The smallest.
            high: The top, not reached.

        Returns:
            The number.
        """
        return low + Float32(self.next()) * (high - low)

    def float_spread(mut self, spread: Float32) -> Float32:
        """Return a number within half a spread of zero. three.js:
        `randFloatSpread`.

        Args:
            spread: The width of the range.

        Returns:
            The number.
        """
        return spread * (0.5 - Float32(self.next()))

    def int_in(mut self, low: Int, high: Int) -> Int:
        """Return a whole number in a range, both ends included.
        three.js: `randInt`.

        Args:
            low: The smallest.
            high: The largest.

        Returns:
            The number.
        """
        return low + Int(floor(self.next() * Float64(high - low + 1)))
