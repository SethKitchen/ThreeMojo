# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Vehicular live-load surcharge on walls.

AASHTO LRFD Art. 3.11.6.4 turns traffic behind a wall into an equivalent
height of soil, h_eq. `parallel_wall_height` is Table 3.11.6.4-2, for a
retaining wall parallel to traffic. The table depends on the wall height
and on the distance from the wall's back face to the edge of traffic: 0 ft
or 1 ft and more. `abutment_height` is Table 3.11.6.4-1, for an abutment
perpendicular to traffic. Both interpolate linearly on the height and are
level past the end rows, as Art. 3.11.6.4 directs.

The tables are in feet; the functions take and return lengths.
"""

from std.math import isfinite
from units.si import Length64


def _interpolate(rows: List[Tuple[Float64, Float64]], h: Float64) -> Float64:
    """Return a table value interpolated on its first column."""
    if h <= rows[0][0]:
        return rows[0][1]
    var n = len(rows)
    # Each table has three rows, so the loop always runs.
    for i in range(n - 1):  # pragma: no branch
        var h0 = rows[i][0]
        var v0 = rows[i][1]
        var h1 = rows[i + 1][0]
        var v1 = rows[i + 1][1]
        if h <= h1:
            return v0 + (h - h0) / (h1 - h0) * (v1 - v0)
    return rows[n - 1][1]


def _feet(length: Length64, what: String) raises -> Float64:
    """Return a finite length of zero or more in feet."""
    var ft = length.value / 0.3048
    if not (isfinite(ft) and ft >= 0):
        raise Error(what + " must be zero or more and finite")
    return ft


def parallel_wall_height(
    height: Length64, distance: Length64
) raises -> Length64:
    """Return h_eq for a retaining wall parallel to traffic.

    AASHTO LRFD Table 3.11.6.4-2. At a distance of 0 ft the rows are 5 ft
    for a 5 ft wall, 3.5 ft for 10 ft and 2 ft for 20 ft. At 1 ft and more
    every row is 2 ft. A distance under 1 ft reads the 0 ft column.

    Args:
        height: The height over which the surcharge pressure acts.
        distance: From the wall's back face to the edge of traffic.

    Returns:
        The equivalent height of soil.

    Raises:
        Error: If a length is negative or not finite.
    """
    var h = _feet(height, "A wall height")
    var d = _feet(distance, "A traffic distance")
    if d >= 1.0:
        return Length64(2.0 * 0.3048)
    var rows: List[Tuple[Float64, Float64]] = [
        (5.0, 5.0),
        (10.0, 3.5),
        (20.0, 2.0),
    ]
    return Length64(_interpolate(rows, h) * 0.3048)


def abutment_height(height: Length64) raises -> Length64:
    """Return h_eq for an abutment perpendicular to traffic.

    AASHTO LRFD Table 3.11.6.4-1: 4 ft for a 5 ft abutment, 3 ft for
    10 ft, and 2 ft for 20 ft and more.

    Args:
        height: The abutment height.

    Returns:
        The equivalent height of soil.

    Raises:
        Error: If the height is negative or not finite.
    """
    var h = _feet(height, "An abutment height")
    var rows: List[Tuple[Float64, Float64]] = [
        (5.0, 4.0),
        (10.0, 3.0),
        (20.0, 2.0),
    ]
    return Length64(_interpolate(rows, h) * 0.3048)
