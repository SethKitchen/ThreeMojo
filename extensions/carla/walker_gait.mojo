# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Deterministic limb motion for the procedural CARLA capsule walker.

The simulation advances the gait; rendering only reads it. One cycle uses
1.5 meters of horizontal travel. Its amplitude approaches twelve degrees
per meter per second, capped at thirty degrees, with a 0.15 second response.
At rest the phase holds and the amplitude tends to zero without a jump.
This is a visual model, not a skeleton or the separate humanoid rig.
"""

from std.math import exp, floor, isfinite, sin
from std.memory import bitcast
from units.si import (
    Angle,
    DEGREE,
    Duration,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    TURN,
    Velocity,
)


def _cycle_fraction(distance: Float64) -> Float64:
    """Reduce an exact nonnegative Float32 product by the 1.5 m period.

    A product of finite Float32 values is exact and finite in Float64.
    Above 1.5 it is normal: distance = mantissa * 2**exponent, with a
    53-bit integer mantissa and exponent >= -52. For exponent >= -1,
    reduce half-meters modulo three using the parity of exponent + 1.
    Otherwise divide the mantissa by 3 * 2**(-exponent - 1), which fits
    53 bits. Only small integer remainders reach the final division.
    Floating `%` loses large finite remainders on the pinned toolchain;
    issue #603 tracks the separate general-purpose modulo correction.
    """
    if distance < 1.5:
        return distance / 1.5
    var bits = bitcast[DType.uint64](distance)
    var mantissa = (bits & 0xFFFFFFFFFFFFF) | (UInt64(1) << 52)
    var exponent = Int((bits >> 52) & 0x7FF) - 1023 - 52
    if exponent >= -1:
        var factor = UInt64(1) << UInt64((exponent + 1) & 1)
        return Float64(((mantissa % 3) * factor) % 3) / 3
    var divisor = UInt64(3) << UInt64(-exponent - 1)
    return Float64(mantissa % divisor) / Float64(divisor)


struct WalkerGait(ImplicitlyCopyable):
    """A bounded phase and a smooth swing amplitude for four capsule limbs."""

    var _phase: Angle
    var _amplitude: Angle

    def __init__(out self):
        """Create a standing pose at phase zero."""
        self._phase = Angle(0)
        self._amplitude = Angle(0)

    def phase(self) -> Angle:
        """Read the phase as a value, within one turn.

        Returns:
            The current phase. Changing this copy cannot change the gait.
        """
        return self._phase

    def amplitude(self) -> Angle:
        """Read the amplitude as a value, from zero to thirty degrees.

        Returns:
            The current amplitude. Changing this copy cannot change the gait.
        """
        return self._amplitude

    def advance(mut self, speed: Velocity, delta: Duration) raises:
        """Advance from horizontal speed and elapsed simulation time.

        Args:
            speed: A finite, nonnegative horizontal speed.
            delta: A finite, nonnegative simulation duration; zero holds.

        Raises:
            Error: If speed or duration is negative or not finite.
        """
        var v = Float64(speed.to(METER_PER_SECOND))
        var dt = Float64(delta.to(SECOND))
        if not isfinite(v) or v < 0:
            raise Error("A gait speed must be finite and nonnegative")
        if not isfinite(dt) or dt < 0:
            raise Error("A gait duration must be finite and nonnegative")
        if dt == 0:
            return
        # Two Float32 inputs multiply exactly in Float64. Take the distance
        # remainder before division, which can round a huge cycle count to
        # an integer and lose its fractional cycle.
        var cycles = _cycle_fraction(v * dt)
        cycles += Float64(self._phase.to(TURN))
        self._phase = Angle(Float32(cycles - floor(cycles)), TURN)
        # Rounding the fraction to Float32 can reach exactly one turn.
        if self._phase.to(TURN) >= 1:
            self._phase = Angle(0)
        var target = min(v * 12, 30.0)
        var amplitude = Float64(self._amplitude.to(DEGREE))
        self._amplitude = Angle(
            Float32(target + (amplitude - target) * exp(-dt / 0.15)), DEGREE
        )

    def swing(self) -> Angle:
        """Read the left leg and right arm angle without advancing time.

        Returns:
            The signed swing; the other two limbs use its negative.
        """
        return Angle(self._amplitude.value * sin(self._phase.to(RADIAN)))
