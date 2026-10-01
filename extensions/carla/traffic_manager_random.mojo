# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's random numbers, CARLA's `RandomGenerator`.

CARLA draws every random choice of the traffic manager from one
`std::mt19937` and a `std::uniform_real_distribution<double>(0, 100)`.
This module gives the same stream for the same seed:

- `MersenneTwister` is the 32-bit Mersenne Twister, `mt19937`, as the
  C++ standard defines it. The seed is taken modulo 2^32, as the
  standard's `seed(value)` does.
- `RandomGenerator.next` is the GNU C++ library's `generate_canonical`
  with 53 bits: two draws, the first as the low word, divided by 2^64,
  and moved just below one if it rounds to one. The result times 100 is
  a percentage in [0, 100).

The draws of other C++ libraries can differ. CARLA's client builds with
the GNU library on Linux.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/RandomGenerator.h`.
"""

comptime _N = 624
comptime _M = 397
comptime _MATRIX_A = UInt64(0x9908B0DF)
comptime _UPPER_MASK = UInt64(0x80000000)
comptime _LOWER_MASK = UInt64(0x7FFFFFFF)
comptime _MASK32 = UInt64(0xFFFFFFFF)
# 2^32 and 2^64 as doubles.
comptime _TWO_32 = Float64(4294967296.0)
comptime _TWO_64 = Float64(18446744073709551616.0)
# The largest double below one, `nextafter(1.0, 0.0)`.
comptime _BELOW_ONE = Float64(0.99999999999999988898)


struct MersenneTwister(Copyable, Movable):
    """The 32-bit Mersenne Twister, C++'s `std::mt19937`."""

    var state: List[UInt64]
    var index: Int

    def __init__(out self, seed: UInt64):
        """Seed the generator, `mt19937(seed)`.

        Args:
            seed: The seed. Only its low 32 bits count.
        """
        self.state = List[UInt64](capacity=_N)
        self.state.append(seed & _MASK32)
        for i in range(1, _N):  # pragma: no branch
            var previous = self.state[i - 1]
            self.state.append(
                (UInt64(1812433253) * (previous ^ (previous >> 30)) + UInt64(i))
                & _MASK32
            )
        self.index = _N

    def _twist(mut self):
        for i in range(_N):  # pragma: no branch
            var y = (self.state[i] & _UPPER_MASK) | (
                self.state[(i + 1) % _N] & _LOWER_MASK
            )
            var value = self.state[(i + _M) % _N] ^ (y >> 1)
            if (y & 1) != 0:
                value ^= _MATRIX_A
            self.state[i] = value
        self.index = 0

    def next_u32(mut self) -> UInt64:
        """Return the next 32-bit draw.

        Returns:
            A number from 0 to 2^32 - 1.
        """
        if self.index >= _N:
            self._twist()
        var y = self.state[self.index]
        self.index += 1
        y ^= y >> 11
        y ^= (y << 7) & UInt64(0x9D2C5680)
        y ^= (y << 15) & UInt64(0xEFC60000)
        y ^= y >> 18
        return y & _MASK32


def canonical_from_draws(low: UInt64, high: UInt64) -> Float64:
    """Return the GNU library's `generate_canonical<double, 53>` of two
    draws.

    Args:
        low: The first 32-bit draw.
        high: The second 32-bit draw.

    Returns:
        (low + high 2^32) / 2^64 in double, moved just below one if it
        rounds to one.
    """
    var ret = (Float64(low) + Float64(high) * _TWO_32) / _TWO_64
    if ret >= 1.0:
        ret = _BELOW_ONE
    return ret


struct RandomGenerator(Copyable, Movable):
    """CARLA's `RandomGenerator`: percentages from a seeded Twister."""

    var engine: MersenneTwister

    def __init__(out self, seed: UInt64):
        """Seed the generator.

        Args:
            seed: The seed. Only its low 32 bits count.
        """
        self.engine = MersenneTwister(seed)

    def next(mut self) -> Float64:
        """Return the next percentage, `RandomGenerator::next`.

        Returns:
            A number in [0, 100).
        """
        var low = self.engine.next_u32()
        var high = self.engine.next_u32()
        return canonical_from_draws(low, high) * 100.0 + 0.0
