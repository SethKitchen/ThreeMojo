# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gait timing by dynamic similarity.

Animals of different sizes move alike at equal Froude numbers,
`Fr = u^2 / (g h)`, with `u` the speed and `h` the hip height
(Alexander and Jayes, *A dynamic similarity hypothesis for the gaits of
quadrupedal mammals*, J. Zool. 201:135-152, 1983). The relative stride
length follows `lambda / h = 2.3 Fr^0.3` (Alexander, *Estimates of
speeds of dinosaurs*, Nature 261:129-130, 1976, as quoted; grade
`FROM_TEXT`). Quadrupeds change from a walk to a trot near `Fr = 0.5`;
horses do so near 0.35 (grade `FROM_TEXT`).

A walk at `Fr = 0.25` is a design choice: a comfortable walk below the
transition for every size.
"""

from std.math import isfinite, pow, sqrt
from units.si import (
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    STANDARD_GRAVITY,
    Frequency,
    Length,
    Velocity,
)

# A walk below the walk-trot transition, for every size.
comptime WALK_FROUDE = 0.25
# Where quadrupeds change from a walk to a trot.
comptime TROT_FROUDE = 0.5


def _height(hip: Length) raises -> Float64:
    var h = Float64(hip.to(METER))
    if not (h > 0.0 and isfinite(h)):
        raise Error("A hip height must be positive and finite")
    return h


def froude(speed: Velocity, hip: Length) raises -> Float64:
    """Return the Froude number of a speed.

    Args:
        speed: The forward speed.
        hip: The hip height, ground to hip joint.

    Returns:
        `u^2 / (g h)`.

    Raises:
        Error: If the hip height is not positive and finite, or the speed
            is not finite.
    """
    var h = _height(hip)
    var u = Float64(speed.to(METER_PER_SECOND))
    if not isfinite(u):
        raise Error("A speed must be finite")
    return u * u / (Float64(STANDARD_GRAVITY.value) * h)


def speed_at(fr: Float64, hip: Length) raises -> Velocity:
    """Return the speed at a Froude number.

    Args:
        fr: The Froude number, zero or more.
        hip: The hip height.

    Returns:
        `sqrt(Fr g h)`.

    Raises:
        Error: If the Froude number is negative or not finite, or the
            hip height is not positive and finite.
    """
    var h = _height(hip)
    if not (fr >= 0.0 and isfinite(fr)):
        raise Error("A Froude number must be zero or more")
    var u = sqrt(fr * Float64(STANDARD_GRAVITY.value) * h)
    if not isfinite(Float32(u)) or (fr > 0.0 and Float32(u) == 0.0):
        raise Error("A speed must fit a finite SI quantity")
    return Velocity(Float32(u), METER_PER_SECOND)


def stride_length(fr: Float64, hip: Length) raises -> Length:
    """Return the stride length at a Froude number.

    Args:
        fr: The Froude number, more than zero.
        hip: The hip height.

    Returns:
        `2.3 Fr^0.3 h`: one full cycle of a foot.

    Raises:
        Error: If the Froude number is not positive and finite, or the
            hip height is not positive and finite.
    """
    var h = _height(hip)
    if not (fr > 0.0 and isfinite(fr)):
        raise Error("A stride needs a positive Froude number")
    var stride = Float32(2.3 * pow(fr, 0.3) * h)
    if not (isfinite(stride) and stride > 0.0):
        raise Error("A stride must fit a positive finite SI quantity")
    return Length(stride, METER)


def stride_frequency(fr: Float64, hip: Length) raises -> Frequency:
    """Return how many strides a second an animal takes at a Froude number.

    Args:
        fr: The Froude number, more than zero.
        hip: The hip height.

    Returns:
        Speed over stride length.

    Raises:
        Error: If the Froude number or the hip height is not positive
            and finite.
    """
    var u = Float64(speed_at(fr, hip).value)
    var stride = Float64(stride_length(fr, hip).value)
    var frequency = Float32(u / stride)
    # Accepted positive speed and stride share the same Froude/height
    # inputs; their ratio stays above the Float32 zero-rounding boundary.
    if not isfinite(frequency):
        raise Error("A stride frequency must fit a positive finite SI quantity")
    return Frequency(frequency, PER_SECOND)
