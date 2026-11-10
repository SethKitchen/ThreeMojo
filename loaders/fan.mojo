# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a loader cuts a polygon into triangles.

The OBJ and PLY loaders cut a face of four or more corners into a fan of
triangles from its first corner, as three.js cuts it. A fan covers a
convex polygon and only that. `fan_problem` finds a face that is not
convex or has no area.

`cut_polygon` gives the triangles. A convex face is the fan. A face that
is not convex is cut by earcut, so that the triangles cover the face and
nothing else. three.js cuts such a face into a fan too, and draws it
wrong: the fan covers the cutout. A face with no area is refused.
"""

from geometries.earcut import earcut
from math.triangle_normal import _polygon_cross_wide, _triangle_cross_wide
from math.vector3 import Vector3
from std.math import sqrt

# What `fan_problem` answers for corners on one line.
comptime _NO_AREA = "a face has no area"


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
        return _NO_AREA
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


struct PolygonCut(Movable):
    """The triangles of a polygon, or why it has none."""

    # Three corner numbers for each triangle, in the polygon's winding.
    # Empty when `problem` is set.
    var triangles: List[Int]
    # Empty, or why the polygon is not cut, for the loader to name its
    # line or face before.
    var problem: String

    def __init__(out self):
        """Start with no triangles and no problem."""
        self.triangles = List[Int]()
        self.problem = String()


def _fan(corners: Int) -> List[Int]:
    """Return the fan of a polygon from its first corner: three.js's cut
    of every polygon. `corners` is four or more."""
    var triangles = List[Int](capacity=3 * (corners - 2))
    for triangle in range(corners - 2):  # pragma: no branch
        triangles.append(0)
        triangles.append(triangle + 1)
        triangles.append(triangle + 2)
    return triangles^


def cut_polygon(points: List[Vector3]) raises -> PolygonCut:
    """Return the triangles that cover a polygon of four or more corners.

    A convex polygon is cut into a fan from its first corner, as three.js
    cuts every polygon. A polygon that is not convex is cut by earcut.
    Its corners are laid on the coordinate plane that its Newell normal
    faces most, wound counterclockwise there, so that each of earcut's
    triangles turns the way the polygon turns. Dropping a coordinate
    changes no number, so the cut does not depend on the model's scale.

    A polygon that touches itself can have an area and no ear for earcut
    to cut. Earcut gives no triangles for it, and it is cut into a fan,
    as three.js cuts it, so that the face is not lost.

    Args:
        points: The corners, in order, four or more, each finite.

    Returns:
        The triangles: one at least, when there is no problem. For a
        polygon with no area, no triangles and the reason. A polygon that
        crosses itself is cut as earcut cuts it.

    Raises:
        Error: If earcut refuses the corners. It refuses more than 80
            corners with a coordinate that is not finite.
    """
    var cut = PolygonCut()
    var problem = fan_problem(points)
    if problem == "":
        cut.triangles = _fan(len(points))
        return cut^
    if problem == _NO_AREA:
        cut.problem = problem
        return cut^
    var normal = _polygon_cross_wide(points)
    var axis = 0
    for other in [1, 2]:  # pragma: no branch
        if abs(normal[other]) > abs(normal[axis]):
            axis = other
    # The two axes that are kept, in the order that turns about the
    # dropped one. A normal that points down the axis turns the other way.
    var first = (axis + 1) % 3
    var second = (axis + 2) % 3
    if normal[axis] < 0:
        first = (axis + 2) % 3
        second = (axis + 1) % 3
    var flat = List[Float64](capacity=2 * len(points))
    for point in points:  # pragma: no branch
        var along = [Float64(point.x), Float64(point.y), Float64(point.z)]
        flat.append(along[first])
        flat.append(along[second])
    cut.triangles = earcut(flat)
    if len(cut.triangles) == 0:
        # A face that touches itself can have an area and no ear for
        # earcut to cut. The fan keeps the face, as three.js keeps it.
        cut.triangles = _fan(len(points))
    return cut^
