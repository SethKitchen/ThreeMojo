# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Build a `Length` or an `Angle` from a `Float64` count.

The count is rounded to `Float32`, which is what a `Length` and an `Angle`
store.
"""

from units.si import DEGREE, METER, RADIAN, Angle, Length


def length_meters(value: Float64) -> Length:
    """Return a number of meters as a length.

    Args:
        value: The size in meters.

    Returns:
        The length.

    Raises:
        Error: Never.
    """
    return Length(Float32(value), METER)


def angle_radians(value: Float64) -> Angle:
    """Return a number of radians as an angle.

    Args:
        value: The size in radians.

    Returns:
        The angle.

    Raises:
        Error: Never.
    """
    return Angle(Float32(value), RADIAN)


def angle_degrees(value: Float64) -> Angle:
    """Return a number of degrees as an angle.

    Args:
        value: The size in degrees.

    Returns:
        The angle.

    Raises:
        Error: Never.
    """
    return Angle(Float32(value), DEGREE)
