# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent exact support, topology and mutable-tolerance hull controls."""

from core.buffer_geometry import NORMAL, POSITION
from geometries.convex import convex
from math.convex_hull import ConvexHull
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.os import getenv
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _point(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


def _integer(x: Int, y: Int, z: Int) -> SIMD[DType.int64, 4]:
    return SIMD[DType.int64, 4](Int64(x), Int64(y), Int64(z), 0)


def _number(text: StringSlice) raises -> Float64:
    return bitcast[DType.float64](Int64(Int(text)))


def _check_closed(hull: ConvexHull, point_count: Int) raises:
    """Check original indices, unit normals, Euler and opposite edge pairs."""
    var used = List[Bool](length=point_count, fill=False)
    for face in range(hull.face_count()):
        var a = hull.face_vertex(face, 0)
        var b = hull.face_vertex(face, 1)
        var c = hull.face_vertex(face, 2)
        assert_true(a != b and b != c and c != a)
        for vertex in [a, b, c]:
            assert_true(vertex >= 0 and vertex < point_count)
            used[vertex] = True
        var normal = hull.face_normal(face)
        assert_true(
            isfinite(normal.x) and isfinite(normal.y) and isfinite(normal.z)
        )
        assert_almost_equal(Float64(normal.length()), 1, atol=2e-7)
        for edge in range(3):
            var start = hull.face_vertex(face, edge)
            var end = hull.face_vertex(face, (edge + 1) % 3)
            var forward = 0
            var backward = 0
            for other in range(hull.face_count()):
                for corner in range(3):
                    var s = hull.face_vertex(other, corner)
                    var e = hull.face_vertex(other, (corner + 1) % 3)
                    forward += Int(s == start and e == end)
                    backward += Int(s == end and e == start)
            assert_equal(forward, 1)
            assert_equal(backward, 1)
    var count = 0
    for flag in used:
        count += Int(flag)
    assert_equal(hull.face_count(), 2 * count - 4)


def _check_integer_support(
    hull: ConvexHull, reference: List[SIMD[DType.int64, 4]]
) raises:
    """Check exact signs with small integers, independent of hull arithmetic.

    Every coordinate has magnitude below 100, so the cross and determinant
    fit Int64. A common positive scale preserves all support signs.
    """
    _check_closed(hull, len(reference))
    for face in range(hull.face_count()):
        var a = reference[hull.face_vertex(face, 0)]
        var ab = reference[hull.face_vertex(face, 1)] - a
        var ac = reference[hull.face_vertex(face, 2)] - a
        var nx = ab[1] * ac[2] - ab[2] * ac[1]
        var ny = ab[2] * ac[0] - ab[0] * ac[2]
        var nz = ab[0] * ac[1] - ab[1] * ac[0]
        assert_true(nx != 0 or ny != 0 or nz != 0)
        var normal = hull.face_normal(face)
        assert_true(
            Float64(nx) * Float64(normal.x)
            + Float64(ny) * Float64(normal.y)
            + Float64(nz) * Float64(normal.z)
            > 0
        )
        var strict_inside = False
        for p in reference:
            var offset = p - a
            var determinant = nx * offset[0] + ny * offset[1] + nz * offset[2]
            assert_true(determinant <= 0)
            strict_inside = strict_inside or determinant < 0
        assert_true(strict_inside)


def test_fraction_oracle_for_facets_and_mutable_distance_boundaries() raises:
    # The generator uses Fraction on retained binary64 words. It enumerates
    # every supporting triangle and squares exact distance comparisons.
    var root = getenv("THREEMOJO_ASSET_ROOT", "assets")
    if root == "":
        root = "assets"
    var text = Path(root + "/convex_hull/exact.txt").read_text()
    var rows = text.splitlines()
    var row = 0
    while row < len(rows):
        var header = rows[row].split(" ")
        row += 1
        var point_count = Int(header[1])
        var facet_count = Int(header[2])
        var query_count = Int(header[3])
        var points = List[SIMD[DType.float64, 4]]()
        for _ in range(point_count):
            var fields = rows[row].split(" ")
            row += 1
            points.append(
                _point(
                    _number(fields[0]), _number(fields[1]), _number(fields[2])
                )
            )
        var allowed = List[SIMD[DType.int64, 4]]()
        for _ in range(facet_count):
            var fields = rows[row].split(" ")
            row += 1
            allowed.append(
                _integer(Int(fields[0]), Int(fields[1]), Int(fields[2]))
            )
        var hull = ConvexHull(points)
        _check_closed(hull, point_count)
        for face in range(hull.face_count()):
            var a = hull.face_vertex(face, 0)
            var b = hull.face_vertex(face, 1)
            var c = hull.face_vertex(face, 2)
            var supported = False
            for triangle in allowed:
                for shift in range(3):
                    supported = supported or (
                        a == Int(triangle[shift])
                        and b == Int(triangle[(shift + 1) % 3])
                        and c == Int(triangle[(shift + 2) % 3])
                    )
            assert_true(supported)
        # Source vertices must remain on their exact supporting planes even
        # after the public tolerance is set to zero.
        hull.tolerance = 0
        for p in points:
            assert_true(hull.contains_point(p))
        for _ in range(query_count):
            var fields = rows[row].split(" ")
            row += 1
            var query = _point(
                _number(fields[0]), _number(fields[1]), _number(fields[2])
            )
            hull.tolerance = _number(fields[3])
            assert_equal(hull.contains_point(query), Int(fields[4]) != 0)


def test_slanted_subnormal_horizons_keep_exact_support_and_closed_edges() raises:
    var s = bitcast[DType.float64](UInt64(1))
    # A sheared cube needs horizon expansion beyond the initial tetrahedron.
    # Interior and repeated source points also test original vertex indices.
    for reversed in [False, True]:
        var reference = List[SIMD[DType.int64, 4]]()
        reference.append(_integer(3, 4, 5))
        for index in range(8):
            var i = 7 - index if reversed else index
            var x = 2 * (i & 1)
            var y = 2 * ((i >> 1) & 1)
            var z = 2 * ((i >> 2) & 1)
            reference.append(_integer(2 * x + y, 3 * y + z, x + 4 * z))
        reference.append(reference[3])
        reference.append(_integer(2, 3, 5))
        var points = List[SIMD[DType.float64, 4]]()
        for p in reference:
            points.append(
                _point(Float64(p[0]) * s, Float64(p[1]) * s, Float64(p[2]) * s)
            )
        var hull = ConvexHull(points)
        assert_equal(hull.tolerance, 0)
        assert_equal(hull.face_count(), 12)
        _check_integer_support(hull, reference)
        for p in points:
            assert_true(hull.contains_point(p))
        assert_false(hull.contains_point(_point(-s, 0, 0)))


def test_subnormal_cloud_reassignment_keeps_every_supporting_halfspace() raises:
    var s = bitcast[DType.float64](UInt64(1))
    # Deterministic multi-face horizons and point reassignment, in two
    # opposite windings. The integer oracle never squares a tiny float.
    for mirror in [1, -1]:
        var reference = List[SIMD[DType.int64, 4]]()
        var points = List[SIMD[DType.float64, 4]]()
        for i in range(24):
            var x = (i * 7) % 23 - 11
            var y = (i * 13) % 29 - 14
            var z = mirror * ((i * 17) % 31 - 15)
            reference.append(_integer(x, y, z))
            points.append(
                _point(Float64(x) * s, Float64(y) * s, Float64(z) * s)
            )
        var hull = ConvexHull(points)
        assert_equal(hull.tolerance, 0)
        assert_true(hull.face_count() > 4)
        _check_integer_support(hull, reference)
        for p in points:
            assert_true(hull.contains_point(p))


def test_exact_degeneracy_is_distinct_from_positive_tolerance_rejection() raises:
    with assert_raises(contains="in a line"):
        _ = ConvexHull(
            [
                _point(0, 0, 0),
                _point(1, 1, 1),
                _point(0.1, 0.1, 0.1),
                _point(0.7, 0.7, 0.7),
            ]
        )
    var s = bitcast[DType.float64](UInt64(1))
    with assert_raises(contains="in a plane"):
        _ = ConvexHull(
            [_point(0, 0, 0), _point(s, 0, 0), _point(0, s, 0), _point(s, s, 0)]
        )
    with assert_raises(contains="tolerance"):
        _ = ConvexHull(
            [
                _point(0, 0, 0),
                _point(1, 0, 0),
                _point(0, 1e-200, 0),
                _point(0, 0, 1e-200),
            ]
        )
    with assert_raises(contains="tolerance"):
        _ = ConvexHull(
            [
                _point(0, 0, 0),
                _point(1, 0, 0),
                _point(0, 1, 0),
                _point(0, 0, 1e-200),
            ]
        )


def test_invalid_mutable_tolerances_are_refused_before_face_iteration() raises:
    var hull = ConvexHull(
        [_point(0, 0, 0), _point(1, 0, 0), _point(0, 1, 0), _point(0, 0, 1)]
    )
    for empty in [False, True]:
        if empty:
            hull.faces.clear()
        for tolerance in [
            Float64(-1),
            -bitcast[DType.float64](UInt64(1)),
            nan[DType.float64](),
            inf[DType.float64](),
            -inf[DType.float64](),
        ]:
            hull.tolerance = tolerance
            assert_false(hull.contains_point(_point(0, 0, 0)))
        hull.tolerance = -Float64(0)
        assert_true(hull.contains_point(_point(0, 0, 0)))


def test_ordinary_float64_hull_retains_three_js_face_order() raises:
    # Original indices of the retained r180 three.js position fixture in
    # test_geometry_addons.mojo; no new production output supplies them.
    var expected = [
        11,
        2,
        5,
        11,
        5,
        0,
        7,
        3,
        0,
        7,
        0,
        5,
        9,
        2,
        11,
        9,
        11,
        3,
        9,
        3,
        7,
        8,
        3,
        11,
        8,
        11,
        0,
        8,
        0,
        3,
        10,
        5,
        2,
        10,
        2,
        9,
        10,
        9,
        7,
        10,
        7,
        5,
    ]
    var points = List[SIMD[DType.float64, 4]]()
    for i in range(12):
        points.append(
            _point(
                Float64((i * 7) % 11 - 5) / 4,
                Float64((i * 5) % 13 - 6) / 4,
                Float64((i * 3) % 7 - 3) / 4,
            )
        )
    var hull = ConvexHull(points)
    assert_equal(hull.face_count(), 14)
    for face in range(14):
        for corner in range(3):
            assert_equal(
                hull.face_vertex(face, corner), expected[face * 3 + corner]
            )
    _check_closed(hull, len(points))


def test_exact_hull_acceptance_does_not_silently_collapse_float32_meshes() raises:
    for s in [bitcast[DType.float64](UInt64(1)), Float64(1e-300)]:
        var points: List[SIMD[DType.float64, 4]] = [
            _point(0, 0, 0),
            _point(2 * s, s, 0),
            _point(0, 3 * s, s),
            _point(s, 0, 4 * s),
        ]
        var hull = ConvexHull(points)
        assert_equal(hull.face_count(), 4)
        with assert_raises(contains="Float32 storage"):
            _ = convex(points)
    var huge: List[SIMD[DType.float64, 4]] = [
        _point(0, 0, 0),
        _point(1e300, 0, 0),
        _point(0, 1e300, 0),
        _point(0, 0, 1e300),
    ]
    var hull = ConvexHull(huge)
    assert_equal(hull.face_count(), 4)
    with assert_raises(contains="Float32 storage range"):
        _ = convex(huge)
    # Ordinary narrowing remains supported when it keeps usable faces.
    var ordinary = convex(
        [
            _point(0, 0, 0),
            _point(0.1, 0, 0),
            _point(0, 0.2, 0),
            _point(0, 0, 0.3),
        ]
    )
    assert_equal(ordinary.vertex_count(), 12)


def test_float32_mesh_rebuilds_closed_support_after_a_protrusion_collapses() raises:
    var reference: List[SIMD[DType.int64, 4]] = [
        _integer(0, 0, 0),
        _integer(1, 1, -1),
        _integer(1, -1, 1),
        _integer(2, 0, 0),
        _integer(1, 1, 1),
        _integer(2, 2, 0),
        _integer(2, 0, 2),
        _integer(3, 1, 1),
    ]
    var points = List[SIMD[DType.float64, 4]]()
    for p in reference:
        points.append(_point(Float64(p[0]), Float64(p[1]), Float64(p[2])))
    var delta = Float64(8.881784197001252e-16)
    points.append(_point(2 + delta, 1 + delta, 1 + delta))
    var exact_hull = ConvexHull(points)
    assert_equal(exact_hull.face_count(), 14)
    var retained = False
    for face in range(exact_hull.face_count()):
        for corner in range(3):
            retained = retained or exact_hull.face_vertex(face, corner) == 8
    assert_true(retained)

    # Narrowing sends the ninth point onto the interior of a cube face.
    # Check the actual stored triangles against independent small integers.
    var mesh = convex(points)
    assert_equal(mesh.vertex_count(), 36)
    ref positions = mesh.attribute_view(String(POSITION))
    ref normals = mesh.attribute_view(String(NORMAL))
    var indices = List[Int]()
    for vertex in range(mesh.vertex_count()):
        var p = positions.vector3(vertex)
        var found = -1
        for i in range(len(reference)):
            if (
                Float64(p.x) == Float64(reference[i][0])
                and Float64(p.y) == Float64(reference[i][1])
                and Float64(p.z) == Float64(reference[i][2])
            ):
                found = i
        assert_true(found >= 0)
        indices.append(found)
    for face in range(12):
        var a = reference[indices[3 * face]]
        var ab = reference[indices[3 * face + 1]] - a
        var ac = reference[indices[3 * face + 2]] - a
        var nx = ab[1] * ac[2] - ab[2] * ac[1]
        var ny = ab[2] * ac[0] - ab[0] * ac[2]
        var nz = ab[0] * ac[1] - ab[1] * ac[0]
        assert_true(nx != 0 or ny != 0 or nz != 0)
        for p in reference:
            var offset = p - a
            assert_true(nx * offset[0] + ny * offset[1] + nz * offset[2] <= 0)
        for corner in range(3):
            var normal = normals.vector3(3 * face + corner)
            assert_true(
                isfinite(normal.x) and isfinite(normal.y) and isfinite(normal.z)
            )
            assert_almost_equal(Float64(normal.length()), 1, atol=2e-7)
            assert_true(
                Float64(nx) * Float64(normal.x)
                + Float64(ny) * Float64(normal.y)
                + Float64(nz) * Float64(normal.z)
                > 0
            )
            var start = indices[3 * face + corner]
            var end = indices[3 * face + (corner + 1) % 3]
            var forward = 0
            var backward = 0
            for other in range(12):
                for edge in range(3):
                    var s = indices[3 * other + edge]
                    var e = indices[3 * other + (edge + 1) % 3]
                    forward += Int(s == start and e == end)
                    backward += Int(s == end and e == start)
            assert_equal(forward, 1)
            assert_equal(backward, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
