# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The random numbers of CARLA's sensors: one seeded generator a sensor.

A CARLA sensor draws its noise from a random engine that it seeds with
its `noise_seed` attribute. The engine is C++'s `std::minstd_rand`, the
Park-Miller "minimal standard" linear congruential generator: the next
state is the state times 48271, modulo 2^31 - 1. The C++ standard fixes
this generator, so one seed gives the same numbers on every platform.
Its source is CARLA's simulator plugin, `Carla/Util/RandomEngine.h`.

The standard leaves the distributions to the library. CARLA's Linux
build uses the GNU C++ library, and this module follows its algorithms:

- A uniform float in [0, 1) is one draw minus one, rounded to a
  `Float32`, over 2^31. A result of one becomes the float just below one.
- A uniform float in [a, b) is a + (b - a) u.
- A normal float is Marsaglia's polar method. It draws pairs until the
  pair falls inside the unit circle and is not zero, and returns the
  second of the two values that the pair gives. CARLA makes a new
  distribution for each draw, so the first value is never used.
"""

from std.ffi import external_call
from std.math import sqrt

comptime _MODULUS = UInt64(2147483647)
comptime _MULTIPLIER = UInt64(48271)
# The largest `Float32` below one.
comptime _BELOW_ONE = Float32(0.99999994039535522)


def _logf(value: Float32) -> Float32:
    return external_call["logf", Float32](value)


struct SensorRandom(Copyable, Movable):
    """A sensor's random engine, `std::minstd_rand`, with the GNU C++
    library's float distributions."""

    # From 1 to 2^31 - 2.
    var state: UInt64

    def __init__(out self, seed: Int):
        """Seed the engine, `minstd_rand::seed`.

        Args:
            seed: The `noise_seed` attribute. CARLA passes a 32-bit signed
                integer; a negative one wraps as the C++ conversion to the
                engine's unsigned type does.
        """
        var wrapped = UInt64(0) - UInt64(-seed) if seed < 0 else UInt64(seed)
        self.state = wrapped % _MODULUS
        if self.state == 0:
            self.state = 1

    def next(mut self) -> UInt64:
        """Advance the engine by one step.

        Returns:
            The new state, from 1 to 2^31 - 2.
        """
        self.state = self.state * _MULTIPLIER % _MODULUS
        return self.state

    def uniform(mut self) -> Float32:
        """Draw a uniform float, `std::uniform_real_distribution<float>()`.

        Returns:
            A float from 0 up to, but not including, one.
        """
        var sum = Float32(self.next() - 1)
        var out = sum / Float32(2147483648.0)
        if out >= 1.0:
            return _BELOW_ONE
        return out

    def uniform_in(mut self, minimum: Float32, maximum: Float32) -> Float32:
        """Draw a uniform float in a range, `GetUniformFloatInRange`.

        Args:
            minimum: The lower end.
            maximum: The upper end.

        Returns:
            The sum minimum + (maximum - minimum) u.
        """
        return self.uniform() * (maximum - minimum) + minimum

    def normal(mut self, mean: Float32, stddev: Float32) -> Float32:
        """Draw a normal float, `GetNormalDistribution`.

        A deviation of zero still draws, so the draws that follow are the
        same as CARLA's.

        Args:
            mean: The mean.
            stddev: The standard deviation.

        Returns:
            The sum mean + stddev z, with z from the polar method.
        """
        var x: Float32
        var y: Float32
        var r2: Float32
        while True:
            x = Float32(2.0 * Float64(self.uniform()) - 1.0)
            y = Float32(2.0 * Float64(self.uniform()) - 1.0)
            r2 = x * x + y * y
            # This fixed minstd_rand cannot yield two consecutive 0.5 draws.
            # Float32's half interval is states 1073741793..1073741889;
            # no next state under *48271 mod 2147483647 stays in it.
            # Nonzero centered draws have squares >= 2^-48, not underflow.
            # Recheck this invariant if the engine or rounding changes.
            # The sensor suite checks all 97 states and both endpoints.
            if not (Float64(r2) > 1.0):
                break
        var mult = sqrt(Float32(-2.0) * _logf(r2) / r2)
        return y * mult * stddev + mean
