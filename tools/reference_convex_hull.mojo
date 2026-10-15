# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate independent exact controls for the public convex-hull API.

    reference_convex_hull --check
    reference_convex_hull --write

The oracle decodes the retained binary64 words, enumerates supporting
triangles, and compares squared exact plane distances against tolerance.
It uses no production predicates or rounded plane normals. `--check`
verifies `assets/convex_hull/exact.txt`; `--write` replaces it.

The fixture is byte-identical to the Python generator's that this replaces.
Every float product in the cases scales by a power of two, so it is exact
and a fused multiply-add cannot change it.
"""

from std.ffi import c_int, external_call
from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_float import parse_float

comptime FIXTURE = "assets/convex_hull/exact.txt"
"""The saved controls."""

comptime Point = Tuple[Float64, Float64, Float64]
comptime Exact = Tuple[Fraction, Fraction, Fraction]


def ldexp(value: Float64, exponent: Int) -> Float64:
    """Return value * 2**exponent, as the C library computes it."""
    return external_call["ldexp", Float64](value, c_int(exponent))


def nextafter(value: Float64, toward: Float64) -> Float64:
    """Return the next double after value toward another."""
    return external_call["nextafter", Float64](value, toward)


def word(value: Float64) -> Int:
    """Return the double's bits as a signed decimal word.

    Args:
        value: The double.

    Returns:
        The bits read as a signed 64-bit integer.
    """
    return Int(bitcast[DType.int64](value))


def decode(value: Float64) raises -> Fraction:
    """Decode a finite double exactly, including the subnormal quantum.

    Args:
        value: A finite double.

    Returns:
        The exact value.

    Raises:
        Error: If the double is not finite.
    """
    return Fraction.from_float(value)


def _sub(a: Exact, b: Exact) raises -> Exact:
    """Return a - b."""
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a: Exact, b: Exact) raises -> Exact:
    """Return a x b."""
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _dot(a: Exact, b: Exact) raises -> Fraction:
    """Return a . b."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _exact(point: Point) raises -> Exact:
    """Return a point's exact coordinates."""
    return (decode(point[0]), decode(point[1]), decode(point[2]))


def facets(
    points: List[Point],
) raises -> Tuple[List[Exact], List[Tuple[Int, Int, Int]]]:
    """Enumerate all outward supporting triangles, coplanar ones included.

    Args:
        points: The hull's points.

    Returns:
        The exact points, and each supporting triangle with its corners in
        outward order.

    Raises:
        Error: If the points have no three-dimensional volume.
    """
    var exact = List[Exact]()
    for point in points:
        exact.append(_exact(point))
    var result = List[Tuple[Int, Int, Int]]()
    var zero = Fraction(0)
    for a in range(len(points)):
        for b in range(a + 1, len(points)):
            for c in range(b + 1, len(points)):
                var normal = _cross(
                    _sub(exact[b], exact[a]), _sub(exact[c], exact[a])
                )
                if _dot(normal, normal).is_zero():
                    continue
                var low = Fraction(0)
                var high = Fraction(0)
                for index in range(len(exact)):
                    var sign = _dot(normal, _sub(exact[index], exact[a]))
                    if index == 0 or sign < low:
                        low = sign.copy()
                    if index == 0 or sign > high:
                        high = sign.copy()
                if high == zero and low < zero:
                    result.append((a, b, c))
                elif low == zero and high > zero:
                    result.append((a, c, b))
    if len(result) == 0:
        raise Error("The fixture must have three-dimensional volume")
    return (exact^, result^)


def contains(
    points: List[Exact],
    planes: List[Tuple[Int, Int, Int]],
    query: Point,
    tolerance: Float64,
) raises -> Bool:
    """Return whether a query is inside every plane, within the tolerance.

    Args:
        points: The exact hull points.
        planes: The supporting triangles.
        query: The query point.
        tolerance: The distance a point may lie outside a plane.

    Returns:
        True when no plane has the point farther outside than the tolerance.
    """
    var exact = _exact(query)
    var limit = decode(tolerance)
    for plane in planes:
        var a = points[plane[0]].copy()
        var normal = _cross(
            _sub(points[plane[1]], a), _sub(points[plane[2]], a)
        )
        var determinant = _dot(normal, _sub(exact, a))
        if determinant > Fraction(
            0
        ) and determinant * determinant > limit * limit * _dot(normal, normal):
            return False
    return True


@fieldwise_init
struct Hull(Copyable, Movable):
    """One fixture: its name, points and queries."""

    var name: String
    """The fixture's name."""
    var points: List[Point]
    """The hull's points."""
    var queries: List[Tuple[Point, Float64]]
    """Each query point and tolerance."""


def _scaled(points: List[Point], scale: Float64) -> List[Point]:
    """Return points scaled by a power of two."""
    var result = List[Point]()
    for p in points:
        result.append((p[0] * scale, p[1] * scale, p[2] * scale))
    return result^


def cases() raises -> List[Hull]:
    """Return every fixture, in the order the file lists them.

    Returns:
        The fixtures.
    """
    var tiny = ldexp(1.0, -1074)
    var slanted: List[Point] = [
        (0.0, 0.0, 0.0),
        (2.0, 1.0, 0.0),
        (0.0, 3.0, 1.0),
        (1.0, 0.0, 4.0),
    ]
    var probes: List[Point] = [
        (0.0, 0.0, 0.0),
        (1.0, 1.0, 1.0),
        (2.0, 2.0, 2.0),
        (-1.0, 0.0, 0.0),
        (2.0, 1.0, 1.0),
        (1.0, 2.0, 1.0),
        (0.0, 1.0, 0.0),
        (1.0, 0.0, 0.0),
    ]
    var result = List[Hull]()
    for exponent in [-1074, -1000, -500, 0, 500, 1000]:
        var scale = ldexp(1.0, exponent)
        var queries = List[Tuple[Point, Float64]]()
        for p in _scaled(probes, scale):
            for t in [0.0, scale]:
                queries.append((p, t))
        result.append(
            Hull(
                "slanted_" + String(exponent), _scaled(slanted, scale), queries^
            )
        )
    # A scaling-only representation loses these nonzero plane anchors.
    var huge = ldexp(1.0, 1000)
    var anchors: List[Point] = [
        (tiny, tiny, tiny),
        (huge, tiny, tiny),
        (tiny, huge, tiny),
        (tiny, tiny, huge),
    ]
    var anchor_queries = List[Tuple[Point, Float64]]()
    for p in anchors:
        anchor_queries.append((p, 0.0))
    for axis in range(3):
        var p: Point = (
            0.0 if axis == 0 else tiny,
            0.0 if axis == 1 else tiny,
            0.0 if axis == 2 else tiny,
        )
        anchor_queries.append((p, 0.0))
        anchor_queries.append((p, tiny))
    for t in [0.0, tiny]:
        anchor_queries.append(((0.0, 0.0, 0.0), t))
    result.append(Hull("retained_subnormal_anchors", anchors^, anchor_queries^))
    # Large translations expose cancellation in affine differences.
    var side = ldexp(1.0, 460)
    var offset = ldexp(1.0, 500)
    var moved = List[Point]()
    for p in slanted:
        moved.append(
            (offset + p[0] * side, -offset + p[1] * side, offset + p[2] * side)
        )
    var moved_queries = List[Tuple[Point, Float64]]()
    for p in probes:
        var q: Point = (
            offset + p[0] * side,
            -offset + p[1] * side,
            offset + p[2] * side,
        )
        for t in [0.0, side]:
            moved_queries.append((q, t))
    result.append(Hull("translated_slanted", moved^, moved_queries^))
    # This supporting plane has the exact normal (3, 4, 12) / 13. The query
    # is exactly one scale unit outside it, even at the exponent ends.
    for exponent in [-1074, -500, 0, 500, 1000]:
        var s = ldexp(1.0, exponent)
        var points: List[Point] = [
            (0.0, 0.0, 0.0),
            (4 * s, 0.0, 0.0),
            (0.0, 3 * s, 0.0),
            (0.0, 0.0, s),
        ]
        var q: Point = (3 * s, 4 * s, 0.0)
        var infinity = Float64.MAX * 2
        var boundary: List[Tuple[Point, Float64]] = [
            (q, nextafter(s, 0.0)),
            (q, s),
            (q, nextafter(s, infinity)),
            (q, 0.0),
        ]
        result.append(
            Hull("positive_boundary_" + String(exponent), points^, boundary^)
        )
    # A rotated cube keeps the last point out of the initial axis extremes.
    # A tolerance-based horizon can retain an adjacent visible face and
    # create a new face that excludes old vertices by much more than t.
    var cube: List[Point] = [
        (0.0, 0.0, 0.0),
        (1.0, 1.0, -1.0),
        (1.0, -1.0, 1.0),
        (2.0, 0.0, 0.0),
        (1.0, 1.0, 1.0),
        (2.0, 2.0, 0.0),
        (2.0, 0.0, 2.0),
        (3.0, 1.0, 1.0),
    ]
    var horizon_eye: Point = (
        parse_float("2.5000000000000053"),
        parse_float("0.4999999999999982"),
        parse_float("1.5000000000000053"),
    )
    # This extremal point is less than the positive tolerance outside the
    # original cube. Exact assignment must retain it for zero queries.
    var delta = ldexp(1.0, -50)
    var assignment_eye: Point = (2.0 + delta, 1.0 + delta, 1.0 + delta)
    var eyes = [("horizon", horizon_eye), ("assignment", assignment_eye)]
    for entry in eyes:
        for exponent in [-500, 0, 500]:
            var scale = ldexp(1.0, exponent)
            var corners = cube.copy()
            corners.append(entry[1])
            var points = _scaled(corners, scale)
            var queries = List[Tuple[Point, Float64]]()
            for p in points:
                queries.append((p, 0.0))
            queries.append(((1.5 * scale, 0.5 * scale, 0.5 * scale), 0.0))
            queries.append(((4.0 * scale, 0.0, 0.0), 0.0))
            result.append(
                Hull(
                    "strict_" + entry[0] + "_" + String(exponent),
                    points^,
                    queries^,
                )
            )
    return result^


def render() raises -> Tuple[String, Int, Int]:
    """Return the fixture text, the number of hulls, and of queries.

    Returns:
        The text, the hull count and the query count.
    """
    var lines = List[String]()
    var query_count = 0
    var hulls = cases()
    for hull in hulls:
        var found = facets(hull.points)
        lines.append(
            hull.name
            + " "
            + String(len(hull.points))
            + " "
            + String(len(found[1]))
            + " "
            + String(len(hull.queries))
        )
        for p in hull.points:
            lines.append(
                String(word(p[0]))
                + " "
                + String(word(p[1]))
                + " "
                + String(word(p[2]))
            )
        for plane in found[1]:
            lines.append(
                String(plane[0])
                + " "
                + String(plane[1])
                + " "
                + String(plane[2])
            )
        for entry in hull.queries:
            var q = entry[0]
            var expected = Int(contains(found[0], found[1], q, entry[1]))
            lines.append(
                String(word(q[0]))
                + " "
                + String(word(q[1]))
                + " "
                + String(word(q[2]))
                + " "
                + String(word(entry[1]))
                + " "
                + String(expected)
            )
            query_count += 1
    return ("\n".join(lines) + "\n", len(hulls), query_count)


def main() raises:
    var given = argv()
    if len(given) != 2 or not (
        String(given[1]) == "--check" or String(given[1]) == "--write"
    ):
        print("usage: reference_convex_hull (--check | --write)", file=stderr)
        exit(2)
    var made = render()
    if String(given[1]) == "--write":
        Path(FIXTURE).write_text(made[0])
    elif Path(FIXTURE).read_text() != made[0]:
        print("Exact hull fixture differs", file=stderr)
        exit(1)
    print(
        "Verified "
        + String(made[1])
        + " convex hulls and "
        + String(made[2])
        + " exact queries"
    )
