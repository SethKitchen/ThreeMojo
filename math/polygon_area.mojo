# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared signed area for stored Float32 polygon contours.

Subtract one contour point before multiplying, then accumulate in doubles.
Moving a small contour far from the origin must not change its winding.
"""

from math.vector2 import Vector2


def signed_area64(contour: List[Vector2]) -> Float64:
    """Return a contour's signed area without large translation products.

    Args:
        contour: The points in meters. The last is joined to the first;
            repeating the first point is optional.

    Returns:
        The area in square meters, positive for counterclockwise winding.
        Fewer than three points give zero. The result stays in doubles so
        a winding test does not lose a small nonzero area to Float32.

    Raises:
        None.
    """
    var count = len(contour)
    if count < 3:
        return 0
    var ox = Float64(contour[0].x)
    var oy = Float64(contour[0].y)
    var total = Float64(0)
    var before_x = Float64(contour[1].x) - ox
    var before_y = Float64(contour[1].y) - oy
    for index in range(2, count):  # pragma: no branch
        var x = Float64(contour[index].x) - ox
        var y = Float64(contour[index].y) - oy
        total += before_x * y - x * before_y
        before_x = x
        before_y = y
    return total * 0.5
