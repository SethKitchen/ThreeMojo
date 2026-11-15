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

The numbers are not for cryptography.
"""

from std.math import cos, log, pi, sqrt

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
