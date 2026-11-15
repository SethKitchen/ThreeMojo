# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded pseudo-random numbers for synthetic data: the xorshift64 of
Marsaglia (2003), with the normal numbers of Box and Muller (1958).

A synthetic study, scan or alignment needs numbers that one seed gives
again on every machine. `Xorshift64(seed)` steps a 64-bit state by three
shifts. `uniform()` gives its top 53 bits as a number strictly between 0
and 1. `normal()` gives a standard normal number from two uniforms.
`between(low, high)`, `poisson(mean)` and `gamma(shape, scale)` give
uniform, Poisson and gamma numbers for synthetic counts and frailties.

The numbers are not for cryptography.
"""

from extensions.numerics.elementary import precise_power
from std.math import cos, isfinite, log, pi, sqrt

comptime _TWO_TO_53 = 9007199254740992.0


struct Xorshift64(Movable):
    """A seeded source of uniform and normal numbers."""

    var state: UInt64
    """The state, never 0."""

    def __init__(out self, seed: UInt64) raises:
        """Create a source from a seed.

        Args:
            seed: The seed, not 0.

        Raises:
            Error: If the seed is 0, which xorshift never leaves.
        """
        if seed == 0:
            raise Error("A xorshift seed must not be 0")
        self.state = seed

    def uniform(mut self) -> Float64:
        """Return the next uniform number.

        Returns:
            `(top 53 bits + 1/2) / 2^53`, strictly between 0 and 1.
        """
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return (Float64(self.state >> 11) + 0.5) / _TWO_TO_53

    def normal(mut self) -> Float64:
        """Return the next standard normal number.

        Returns:
            `sqrt(-2 ln u) cos(2 pi v)` of the next two uniforms u and v.
        """
        var u = self.uniform()
        var v = self.uniform()
        return sqrt(-2.0 * log(u)) * cos(2.0 * pi * v)

    def between(mut self, low: Float64, high: Float64) -> Float64:
        """Return the next uniform number between two ends.

        Args:
            low: The low end.
            high: The high end.

        Returns:
            `low + (high - low) u` of the next uniform u.
        """
        return low + (high - low) * self.uniform()

    def poisson(mut self, mean: Float64) raises -> Int:
        """Return the next Poisson count.

        The count is the number of arrivals of a unit-rate Poisson process
        by the time `mean`: the gaps are `-ln u` of uniform numbers. It
        takes about `mean + 1` uniforms.

        Args:
            mean: The mean, 0 or more and finite.

        Returns:
            The count.

        Raises:
            Error: If the mean is negative or not finite.
        """
        if not (mean >= 0) or not isfinite(mean):
            raise Error("A Poisson mean must be 0 or more and finite")
        var count = 0
        var time = -log(self.uniform())
        while time < mean:
            count += 1
            time -= log(self.uniform())
        return count

    def gamma(mut self, shape: Float64, scale: Float64) raises -> Float64:
        """Return the next gamma number, by Marsaglia and Tsang (2000).

        A shape below 1 draws a gamma of shape + 1 and scales it by
        `u^(1 / shape)`.

        Args:
            shape: The shape, positive and finite.
            scale: The scale, positive and finite.

        Returns:
            The number, with mean `shape scale`.

        Raises:
            Error: If the shape or the scale is not positive and finite.
        """
        if not (shape > 0 and scale > 0) or not (
            isfinite(shape) and isfinite(scale)
        ):
            raise Error("A gamma shape and scale must be positive and finite")
        if shape < 1:
            var boost = precise_power(self.uniform(), 1.0 / shape)
            return self.gamma(shape + 1.0, scale) * boost
        var d = shape - 1.0 / 3.0
        var c = 1.0 / sqrt(9.0 * d)
        while True:
            var x = self.normal()
            var v = 1.0 + c * x
            if v <= 0:
                continue
            v = v * v * v
            var u = self.uniform()
            if log(u) < 0.5 * x * x + d - d * v + d * log(v):
                return d * v * scale
