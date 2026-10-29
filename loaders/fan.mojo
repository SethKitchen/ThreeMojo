# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The test a polygon passes before a loader cuts it into a fan.

The OBJ and PLY loaders cut a face of four or more corners into a fan of
triangles from its first corner, as three.js cuts it. A fan covers a
convex polygon and only that. `fan_problem` finds a face that is not
convex or has no area, so the loader refuses it rather than draws it
wrong, as three.js draws it.
"""

from math.triangle_normal import _polygon_cross_wide, _triangle_cross_wide
from math.vector3 import Vector3
from std.math import sqrt


def _span(a: Vector3, b: Vector3) -> Float64:
    """Return the length from `a` to `b`, in doubles."""
    var x = Float64(b.x) - Float64(a.x)
    var y = Float64(b.y) - Float64(a.y)
    var z = Float64(b.z) - Float64(a.z)
    return sqrt(x * x + y * y + z * z)


def fan_problem(points: List[Vector3]) -> String:
    """Return why a fan from a polygon's first corner would not cover it.

    The polygon's normal is Newell's sum over its edges, which is twice
    its area as a vector and is zero for corners on one line. Each corner
    then turns the same way about that normal in a convex polygon, and the
    other way somewhere in a concave one, where a fan triangle would cover
    the cutout. Both sums are found from the corners' `Float32` values
    without rounding.

    A corner is let through when it turns the wrong way by no more than
    the rounding of the file's numbers to `Float32` can explain, or by a
    millionth of the area. So a corner that is straight in the file, such
    as a T-junction far from the origin, does not refuse it.

    Args:
        points: The corners, in order, four or more.

    Returns:
        An empty string when a fan covers the polygon, else the reason,
        for the loader to name its line or face before.
    """
    var count = len(points)
    var normal = _polygon_cross_wide(points)
    var area_squared = (normal * normal).reduce_add()
    if area_squared == 0:
        return "a face has no area"
    # Rounding a number to a `Float32` moves it by at most 2**-24 of the
    # largest coordinate. Moving the three corners of a turn that far
    # moves the turn by less than 4 times that, times its two sides.
    var largest = Float64(0)
    for point in points:  # pragma: no branch
        largest = max(
            largest,
            Float64(max(abs(point.x), max(abs(point.y), abs(point.z)))),
        )
    var rounding = 4 * largest * 2.0**-24 * sqrt(area_squared)
    for index in range(count):  # pragma: no branch
        var a = points[index]
        var b = points[(index + 1) % count]
        var c = points[(index + 2) % count]
        var turn = _triangle_cross_wide(a, b, c)
        var slack = 1e-6 * area_squared + rounding * (_span(a, b) + _span(b, c))
        if (turn * normal).reduce_add() < -slack:
            return (
                "a face is not convex, and only a convex face cuts into a"
                " fan of triangles"
            )
    return ""
