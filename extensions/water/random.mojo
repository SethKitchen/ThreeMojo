# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mulberry32 generator Clearwater uses to draw its ocean spectrum.

The bit operations match JavaScript `Math.imul` and `>>>`, so a seed of
7 draws the same sequence as the original page.
"""

from std.math import cos, log, pi, sqrt


def _i32(value: Int) -> Int:
    var bits = value & 0xFFFFFFFF
    if bits >= 0x80000000:
        return bits - 0x100000000
    return bits


def _imul(left: Int, right: Int) -> Int:
    return _i32(_i32(left) * _i32(right))


def _ushr(value: Int, shift: Int) -> Int:
    return (value & 0xFFFFFFFF) >> shift


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
        var a = _i32(self.state + 0x6D2B79F5)
        self.state = a & 0xFFFFFFFF
        var ua = self.state
        var t = _imul(ua ^ _ushr(ua, 15), 1 | ua)
        var ut = t & 0xFFFFFFFF
        t = _i32(t + _imul(ut ^ _ushr(ut, 7), 61 | ut)) ^ t
        var mixed = _ushr(t ^ _ushr(t, 14), 0)
        return Float64(mixed) / 4294967296.0

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
        u: A uniform sample in `(0, 1)`. Zero is replaced so `log` is defined.
        v: A uniform sample in `[0, 1)`.

    Returns:
        `sqrt(-2 log u) * cos(2 π v)`.
    """
    var unit = u
    if unit == 0.0:
        unit = 1e-12
    return sqrt(-2.0 * log(unit)) * cos(2.0 * pi * v)
