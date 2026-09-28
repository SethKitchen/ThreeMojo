# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The small helpers the sculptor shares, from three.js
`examples/jsm/misc/SculptorUtils.js`, itself adapted from SculptGL by
Stéphane Ginier (MIT; see THIRD-PARTY-NOTICES.md).

A point is a `Point3`: three doubles, as three.js keeps its points in plain
JavaScript arrays of numbers. The mesh stores its positions in `Float32`,
and every helper here reads them widened, as JavaScript reads a
`Float32Array`.

**Where this differs.** three.js's `intersectionRayTriangle` falls back to
a scaled test when a product overflows or is not a number. A ray here is
always a unit direction and a position is always a finite `Float32`, so
no product can overflow a double and the fallback is not ported. three.js
lends every helper one shared scratch buffer; here each returns its own
list.
"""

from std.math import isnan, sqrt

# The tag three.js writes in the fourth slot of a face. Kept for the
# record; a face here is three corners.
comptime TRI_INDEX = 4294967295
# The largest tag or sculpt flag before the counters start again.
comptime MAX_FLAG = 0x7FFFFFFF
# How far past an edge or behind the origin a ray may meet a triangle.
comptime RAY_EPSILON = 1e-15
# The spacing of doubles at one, JavaScript's `Number.EPSILON`.
comptime DOUBLE_EPSILON = 2.220446049250313e-16


@fieldwise_init
struct Point3(ImplicitlyCopyable, Writable):
    """Three doubles: a point or a direction, three.js's `[ x, y, z ]`."""

    var x: Float64
    var y: Float64
    var z: Float64


def point_of(values: List[Float32], vertex: Int) -> Point3:
    """Return one vertex of a packed list, widened to doubles.

    Args:
        values: Three numbers per vertex.
        vertex: Which vertex.

    Returns:
        Its three numbers.
    """
    var at = vertex * 3
    return Point3(
        Float64(values[at]), Float64(values[at + 1]), Float64(values[at + 2])
    )


def replace_element(mut array: List[Int], old_value: Int, new_value: Int):
    """Replace the first `old_value` with `new_value`, three.js's
    `replaceElement`.

    Args:
        array: The list to change.
        old_value: The value to find.
        new_value: The value to put in its place.
    """
    for i in range(len(array)):
        if array[i] == old_value:
            array[i] = new_value
            return


def remove_element(mut array: List[Int], value: Int):
    """Remove the first `value`, moving the last element into its place,
    three.js's `removeElement`.

    Args:
        array: The list to change.
        value: The value to remove.
    """
    for i in range(len(array)):
        if array[i] == value:
            array[i] = array[len(array) - 1]
            _ = array.pop()
            return


def tidy(mut array: List[Int]):
    """Sort a list and remove its repeats, three.js's `tidy`.

    Args:
        array: The list to change.
    """
    if len(array) < 2:
        return
    sort(array)
    var write_index = 1
    for i in range(1, len(array)):  # pragma: no branch
        if array[write_index - 1] != array[i]:
            array[write_index] = array[i]
            write_index += 1
    array.resize(write_index, 0)


def sqr_dist(a: Point3, b: Point3) -> Float64:
    """Return the squared distance between two points, three.js's
    `sqrDist`.

    Args:
        a: One point.
        b: The other.

    Returns:
        The squared distance.
    """
    var dx = a.x - b.x
    var dy = a.y - b.y
    var dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz


def _sub(a: Point3, b: Point3) -> Point3:
    """Return `a - b`."""
    return Point3(a.x - b.x, a.y - b.y, a.z - b.z)


def _cross(a: Point3, b: Point3) -> Point3:
    """Return `a x b`, in three.js's order of operations."""
    return Point3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _dot(a: Point3, b: Point3) -> Float64:
    """Return `a . b`, summed left to right."""
    return a.x * b.x + a.y * b.y + a.z * b.z


def _hypot(p: Point3) -> Float64:
    """Return the length of `p`, three.js's `Math.hypot`."""
    return sqrt(p.x * p.x + p.y * p.y + p.z * p.z)


def intersection_ray_triangle(
    origin: Point3, direction: Point3, v1: Point3, v2: Point3, v3: Point3
) -> Float64:
    """Return how far along a ray it meets a triangle, or -1, three.js's
    `intersectionRayTriangle`: Möller and Trumbore's test, with a tolerance
    scaled to the triangle.

    Args:
        origin: Where the ray starts.
        direction: Which way it goes; a unit vector.
        v1: The triangle's first corner.
        v2: Its second.
        v3: Its third.

    Returns:
        The distance along the ray, or -1 when it misses. The hit point is
        `origin + direction * distance`.
    """
    var edge1 = _sub(v2, v1)
    var edge2 = _sub(v3, v1)
    var pvec = _cross(direction, edge2)
    var det = _dot(edge1, pvec)
    var determinant_scale = _hypot(edge1) * _hypot(edge2) * _hypot(direction)
    if abs(det) <= RAY_EPSILON * determinant_scale:
        return -1.0
    var inv_det = 1.0 / det
    var tvec = _sub(origin, v1)
    var u = _dot(tvec, pvec) * inv_det
    if u < -RAY_EPSILON or u > 1.0 + RAY_EPSILON:
        return -1.0
    var qvec = _cross(tvec, edge1)
    var v = _dot(direction, qvec) * inv_det
    if v < -RAY_EPSILON or u + v > 1.0 + RAY_EPSILON:
        return -1.0
    var t = _dot(edge2, qvec) * inv_det
    if t < -RAY_EPSILON:
        return -1.0
    return t


def ray_point(origin: Point3, direction: Point3, distance: Float64) -> Point3:
    """Return the point a distance along a ray, three.js's
    `setRayIntersection`.

    Args:
        origin: Where the ray starts.
        direction: Which way it goes.
        distance: How far along.

    Returns:
        The point.
    """
    return Point3(
        origin.x + direction.x * distance,
        origin.y + direction.y * distance,
        origin.z + direction.z * distance,
    )


def distance_sq_to_segment(point: Point3, v1: Point3, v2: Point3) -> Float64:
    """Return the squared distance from a point to a segment, three.js's
    `distanceSqToSegment`.

    Args:
        point: The point.
        v1: One end of the segment.
        v2: The other end.

    Returns:
        The squared distance.
    """
    var ptx = point.x - v1.x
    var pty = point.y - v1.y
    var ptz = point.z - v1.z
    var vx = v2.x - v1.x
    var vy = v2.y - v1.y
    var vz = v2.z - v1.z
    var length_squared = vx * vx + vy * vy + vz * vz
    if length_squared == 0:
        return ptx * ptx + pty * pty + ptz * ptz
    var t = (ptx * vx + pty * vy + ptz * vz) / length_squared
    if t < 0:
        return ptx * ptx + pty * pty + ptz * ptz
    if t > 1:
        return sqr_dist(point, v2)
    var rx = point.x - v1.x - t * vx
    var ry = point.y - v1.y - t * vy
    var rz = point.z - v1.z - t * vz
    return rx * rx + ry * ry + rz * rz


def _degenerate_distance(point: Point3, v1: Point3, v2: Point3, v3: Point3) -> Float64:
    """Return the squared distance to the nearest of a flat triangle's
    three edges."""
    return min(
        min(
            distance_sq_to_segment(point, v1, v2),
            distance_sq_to_segment(point, v2, v3),
        ),
        distance_sq_to_segment(point, v3, v1),
    )


def distance_sq_to_triangle(
    point: Point3, v1: Point3, v2: Point3, v3: Point3
) -> Float64:
    """Return the squared distance from a point to a triangle, three.js's
    `distanceSqToTriangle`: Ericson's closest point by Voronoi regions.

    Args:
        point: The point.
        v1: The triangle's first corner.
        v2: Its second.
        v3: Its third.

    Returns:
        The squared distance. A triangle with no area is measured to its
        edges.
    """
    var ab = _sub(v2, v1)
    var ac = _sub(v3, v1)
    var bc = _sub(v3, v2)
    var normal = Point3(
        ab.y * ac.z - ab.z * ac.y,
        ab.z * ac.x - ab.x * ac.z,
        ab.x * ac.y - ab.y * ac.x,
    )
    var area_squared = _dot(normal, normal)
    var max_edge_squared = max(max(_dot(ab, ab), _dot(ac, ac)), _dot(bc, bc))
    if area_squared <= DOUBLE_EPSILON * max_edge_squared * max_edge_squared:
        return _degenerate_distance(point, v1, v2, v3)
    var ap = _sub(point, v1)
    var d1 = _dot(ab, ap)
    var d2 = _dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return _dot(ap, ap)
    var bp = _sub(point, v2)
    var d3 = _dot(ab, bp)
    var d4 = _dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return _dot(bp, bp)
    var vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        var v = d1 / (d1 - d3)
        return _dot(_edge_rest(ap, ab, v), _edge_rest(ap, ab, v))
    var cp = _sub(point, v3)
    var d5 = _dot(ab, cp)
    var d6 = _dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return _dot(cp, cp)
    var vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        var w = d2 / (d2 - d6)
        return _dot(_edge_rest(ap, ac, w), _edge_rest(ap, ac, w))
    var va = d3 * d6 - d5 * d4
    if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0:
        var w = (d4 - d3) / (d4 - d3 + d5 - d6)
        return _dot(_edge_rest(bp, bc, w), _edge_rest(bp, bc, w))
    var inverse = 1.0 / (va + vb + vc)
    var v = vb * inverse
    var w = vc * inverse
    var dx = ap.x - ab.x * v - ac.x * w
    var dy = ap.y - ab.y * v - ac.y * w
    var dz = ap.z - ab.z * v - ac.z * w
    return dx * dx + dy * dy + dz * dz


def _edge_rest(offset: Point3, edge: Point3, share: Float64) -> Point3:
    """Return `offset - edge * share`, the gap to a point on an edge."""
    return Point3(
        offset.x - edge.x * share,
        offset.y - edge.y * share,
        offset.z - edge.z * share,
    )


def triangle_inside_sphere(
    point: Point3, radius_squared: Float64, v1: Point3, v2: Point3, v3: Point3
) -> Bool:
    """Return True if any of a triangle lies inside a sphere, three.js's
    `triangleInsideSphere`.

    Args:
        point: The sphere's center.
        radius_squared: Its squared radius.
        v1: The triangle's first corner.
        v2: Its second.
        v3: Its third.

    Returns:
        Whether the triangle comes nearer the center than the radius.
    """
    return distance_sq_to_triangle(point, v1, v2, v3) < radius_squared


def falloff(dist: Float64) -> Float64:
    """Return a brush's weight at a distance, three.js's `falloff`: one at
    the center and zero at the rim, `3d^4 - 4d^3 + 1`.

    Args:
        dist: The distance, as a share of the radius.

    Returns:
        The weight.
    """
    var d2 = dist * dist
    return 3.0 * d2 * d2 - 4.0 * d2 * dist + 1.0


def js_min(a: Float64, b: Float64) -> Float64:
    """Return the smaller of two numbers, or a NaN if either is one, as
    JavaScript's `Math.min` does.

    Args:
        a: One number.
        b: The other.

    Returns:
        The smaller, or the NaN.
    """
    if isnan(a):
        return a
    if isnan(b):
        return b
    return a if a < b else b


def js_max(a: Float64, b: Float64) -> Float64:
    """Return the larger of two numbers, or a NaN if either is one, as
    JavaScript's `Math.max` does.

    Args:
        a: One number.
        b: The other.

    Returns:
        The larger, or the NaN.
    """
    if isnan(a):
        return a
    if isnan(b):
        return b
    return a if a > b else b
