# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mulberry32 generator Clearwater uses to draw its ocean spectrum.

The bit operations match JavaScript `Math.imul` and `>>>`, so a seed of
7 draws the same sequence as the original page.
"""

from math.random import mulberry32_step
from std.math import cos, log, pi, sqrt


struct Mulberry32:
    """One mulberry32 stream. `state` is the 32-bit seed, not a signed word."""

    var state: Int

    def __init__(out self, seed: Int):
        """Start the stream at `seed`.

        Args:
            seed: The integer Clearwater passes to `mulberry`. The low 32
                bits are kept.
        """
        self.state = seed & 0xFFFFFFFF

    def next_unit(mut self) -> Float64:
        """Draw one number in `[0, 1)`.

        Returns:
            The next mulberry32 value, as JavaScript divides it.
        """
        var state = UInt32(self.state & 0xFFFFFFFF)
        var value = mulberry32_step(state)
        self.state = Int(state)
        return value

    def gauss(mut self) -> Float64:
        """Draw one standard normal sample, as Clearwater's `gauss` does.

        A zero uniform sample is drawn again. `log` of zero is not a
        Gaussian.

        Returns:
            A sample from the standard normal distribution.
        """
        var u = self.next_unit()
        while u == 0.0:
            u = self.next_unit()
        var v = self.next_unit()
        return sqrt(-2.0 * log(u)) * cos(2.0 * pi * v)


def gaussian_pair(u: Float64, v: Float64) -> Float64:
    """Return the Box-Muller sample Clearwater draws from two uniforms.

    Args:
        u: A uniform sample in `(0, 1)`. Zero is replaced with `1e-12`
            so `log` is defined.
        v: A uniform sample in `[0, 1)`.

    Returns:
        `sqrt(-2 log u) * cos(2 π v)`.
    """
    var unit = u
    if unit == 0.0:
        unit = 1e-12
    return sqrt(-2.0 * log(unit)) * cos(2.0 * pi * v)
