# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent convex-hull invariants across the Float64 exponent range."""

from math.convex_hull import (
    ConvexHull,
    DOUBLE_EPSILON,
    _Point,
    _unit_or_zero,
    _scale,
    _exponent,
)
from math.vector3 import Vector3
from std.math import inf, isfinite, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def point(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


def tetra(scale: Float64) -> List[SIMD[DType.float64, 4]]:
    return [
        point(0, 0, 0),
        point(scale, 0, 0),
        point(0, scale, 0),
        point(0, 0, scale),
    ]


def check_surface(hull: ConvexHull, reference: List[Vector3]) raises:
    """Check indices, winding, unit normals, support and closed edge pairing.

    The reference points are known small coordinates, independent of the
    implementation's conditioned points, normals and plane constants.
    """
    var used = List[Bool](length=len(reference), fill=False)
    for face in range(hull.face_count()):
        var a = hull.face_vertex(face, 0)
        var b = hull.face_vertex(face, 1)
        var c = hull.face_vertex(face, 2)
        assert_true(a != b and b != c and c != a)
        for vertex in [a, b, c]:
            assert_true(vertex >= 0 and vertex < len(reference))
            used[vertex] = True
        var normal = hull.face_normal(face)
        assert_true(
            isfinite(normal.x) and isfinite(normal.y) and isfinite(normal.z)
        )
        assert_almost_equal(Float64(normal.length()), 1, atol=2e-7)
        var winding = reference[b] - reference[a]
        winding.cross(reference[c] - reference[a])
        assert_true(winding.dot(normal) > 0)
        for p in reference:
            assert_true(normal.dot(p - reference[a]) <= 2e-6)
        for corner in range(3):
            var start = hull.face_vertex(face, corner)
            var end = hull.face_vertex(face, (corner + 1) % 3)
            var forward = 0
            var backward = 0
            for other in range(hull.face_count()):
                for edge in range(3):
                    var s = hull.face_vertex(other, edge)
                    var e = hull.face_vertex(other, (edge + 1) % 3)
                    forward += Int(s == start and e == end)
                    backward += Int(s == end and e == start)
            assert_equal(forward, 1)
            assert_equal(backward, 1)
    var vertices = 0
    for flag in used:
        vertices += Int(flag)
    assert_equal(hull.face_count(), 2 * vertices - 4)


def test_log_spaced_tetrahedra_keep_winding_support_and_containment() raises:
    var reference: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
    ]
    var scales: List[Float64] = [
        1e-308,
        1e-300,
        1e-200,
        1e-100,
        1e-60,
        1,
        1e60,
        1e100,
        1e200,
        1e300,
        1e308,
    ]
    for scale in scales:
        var points = tetra(scale)
        var hull = ConvexHull(points)
        assert_equal(hull.face_count(), 4)
        check_surface(hull, reference)
        for p in points:
            assert_true(hull.contains_point(p))
        assert_true(hull.contains_point(point(scale / 4, scale / 4, scale / 4)))
        assert_false(hull.contains_point(point(-scale, 0, 0)))
        assert_false(hull.contains_point(point(scale, scale, scale)))
        assert_true(isfinite(hull.tolerance))
        assert_true(hull.tolerance > 0)


def test_smallest_subnormal_tetrahedron_keeps_a_zero_public_tolerance() raises:
    var scale = Float64(5e-324)
    var points = tetra(scale)
    var hull = ConvexHull(points)
    assert_equal(hull.face_count(), 4)
    assert_equal(hull.tolerance, 0)
    for p in points:
        assert_true(hull.contains_point(p))
    assert_false(hull.contains_point(point(scale, scale, scale)))
    assert_false(hull.contains_point(point(-scale, 0, 0)))
    # A positive query distance can be smaller than the least subnormal.
    # It must not be rounded back to zero before comparing with tolerance.
    var slanted: List[SIMD[DType.float64, 4]] = [
        point(0, 0, 0),
        point(scale, 0, 0),
        point(0, scale, 0),
        point(0, 0, scale * 2),
    ]
    var other = ConvexHull(slanted)
    assert_equal(other.tolerance, 0)
    assert_false(other.contains_point(point(scale, 0, scale)))


def test_translated_clouds_keep_original_indices_and_float64_detail() raises:
    for scale in [Float64(1e-250), Float64(1), Float64(1e250)]:
        var points = List[SIMD[DType.float64, 4]]()
        var reference = List[Vector3]()
        # Offsets are deliberately not representable in Float32 at the
        # extremes. An interior point first tests original index retention.
        points.append(point(3.5 * scale, -1.5 * scale, 5.5 * scale))
        reference.append(Vector3(0.5, 0.5, 0.5))
        for i in range(8):
            var x = Float64(i & 1)
            var y = Float64((i >> 1) & 1)
            var z = Float64((i >> 2) & 1)
            points.append(
                point((3 + x) * scale, (-2 + y) * scale, (5 + z) * scale)
            )
            reference.append(Vector3(Float32(x), Float32(y), Float32(z)))
        var hull = ConvexHull(points)
        assert_equal(hull.face_count(), 12)
        check_surface(hull, reference)
        for p in points:
            assert_true(hull.contains_point(p))
        for face in range(hull.face_count()):
            for corner in range(3):
                assert_true(hull.face_vertex(face, corner) > 0)
        assert_false(
            hull.contains_point(point(4.5 * scale, -1.5 * scale, 5.5 * scale))
        )
    # This edge survives Float64 but would collapse if narrowed to Float32.
    var offset = Float64(1e100)
    var side = offset * 1e-10
    var fine: List[SIMD[DType.float64, 4]] = [
        point(offset, offset, offset),
        point(offset + side, offset, offset),
        point(offset, offset + side, offset),
        point(offset, offset, offset + side),
    ]
    var fine_hull = ConvexHull(fine)
    assert_equal(fine_hull.face_count(), 4)
    assert_true(
        fine_hull.contains_point(
            point(offset + side / 4, offset + side / 4, offset + side / 4)
        )
    )
    assert_false(
        fine_hull.contains_point(
            point(offset + side, offset + side, offset + side)
        )
    )


def test_public_tolerance_stays_in_original_units_and_is_mutable() raises:
    for scale in [Float64(1e-300), Float64(1), Float64(1e300)]:
        var hull = ConvexHull(tetra(scale))
        assert_equal(
            hull.tolerance, 3 * DOUBLE_EPSILON * (scale + scale + scale)
        )
        var query = point(-scale / 8, 0, 0)
        assert_false(hull.contains_point(query))
        hull.tolerance = scale / 4
        assert_true(hull.contains_point(query))
        hull.tolerance = 0
        assert_false(hull.contains_point(query))
    var largest = ConvexHull(tetra(Float64(1e308)))
    assert_almost_equal(
        largest.tolerance / 1e308, 9 * DOUBLE_EPSILON, atol=1e-30
    )


def test_nonfinite_containment_queries_are_refused_in_each_spatial_lane() raises:
    var hull = ConvexHull(tetra(1))
    for bad in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        for axis in range(3):
            var p = point(0, 0, 0)
            p[axis] = bad
            assert_false(hull.contains_point(p))
            assert_false(
                hull.contains_point(
                    Vector3(Float32(p[0]), Float32(p[1]), Float32(p[2]))
                )
            )
    assert_true(
        hull.contains_point(
            SIMD[DType.float64, 4](0, 0, 0, nan[DType.float64]())
        )
    )


def test_finite_far_queries_do_not_overflow_conditioned_planes() raises:
    for scale in [Float64(1e-300), Float64(1), Float64(1e300)]:
        var hull = ConvexHull(tetra(scale))
        assert_false(hull.contains_point(point(1e308, -1e308, 1e308)))
        assert_false(hull.contains_point(point(-1e308, 1e308, -1e308)))
        assert_true(hull.contains_point(point(0, 0, 0)))
    var small = ConvexHull(tetra(Float64(1e-300)))
    assert_false(small.contains_point(point(1e60, 0, 0)))


def test_conditioning_does_not_turn_degeneracy_into_a_hull() raises:
    with assert_raises(contains="four points"):
        _ = ConvexHull(List[Vector3]())
    for scale in [Float64(1e-300), Float64(1), Float64(1e300)]:
        with assert_raises(contains="more than one place"):
            _ = ConvexHull(
                [
                    point(scale, scale, scale),
                    point(scale, scale, scale),
                    point(scale, scale, scale),
                    point(scale, scale, scale),
                ]
            )
        with assert_raises(contains="in a line"):
            _ = ConvexHull(
                [
                    point(0, 0, 0),
                    point(scale, 0, 0),
                    point(scale / 2, 0, 0),
                    point(scale / 4, 0, 0),
                ]
            )
        with assert_raises(contains="in a plane"):
            _ = ConvexHull(
                [
                    point(0, 0, 0),
                    point(scale, 0, 0),
                    point(0, scale, 0),
                    point(scale, scale, 0),
                ]
            )


def test_lossy_conditioning_keeps_original_coordinates_for_predicates() raises:
    for axis in range(3):
        var p = point(0, 0, 0)
        p[axis] = Float64(5e-324)
        var points = tetra(Float64(1e308))
        points.append(p)
        var hull = ConvexHull(points)
        assert_equal(hull.face_count(), 4)
        for source in points:
            assert_true(hull.contains_point(source))
        hull.tolerance = 0
        for source in points:
            assert_true(hull.contains_point(source))
    # Scaling can also round low bits without producing zero. Originals
    # still determine exact containment after the tolerance becomes zero.
    var rounded = tetra(Float64(1e308))
    rounded.append(point(0, 1e-10, 0))
    var hull = ConvexHull(rounded)
    hull.tolerance = 0
    assert_true(hull.contains_point(rounded[4]))
    assert_false(hull.contains_point(point(-Float64(5e-324), 0, 0)))


def test_tiny_affine_gaps_are_distinct_from_true_degeneracy() raises:
    # This tetrahedron has nonzero exact volume, but its height is far
    # below the positive, original-unit construction tolerance.
    with assert_raises(contains="in a plane within tolerance"):
        _ = ConvexHull(
            [
                point(0, 0, 0),
                point(1, 0, 0),
                point(0, 1e-200, 0),
                point(0, 0, 1e-200),
            ]
        )
    # All four vertices lie exactly in x=1, despite their tiny separations.
    with assert_raises(contains="in a plane"):
        _ = ConvexHull(
            [
                point(1, 0, 0),
                point(1, 1e-200, 0),
                point(1, 0, 1e-200),
                point(1, 1e-200, 1e-200),
            ]
        )


def test_small_normal_length_does_not_square_away_its_direction() raises:
    var normal = _unit_or_zero(_Point(1e-300, -1e-300, 1e-300))
    assert_true(isfinite(normal.x))
    assert_almost_equal(normal.dot(normal), 1, atol=1e-15)
    assert_true(normal.x > 0 and normal.y < 0 and normal.z > 0)
    assert_equal(_unit_or_zero(_Point(0, 0, 0)).magnitude(), 0)


def test_exactly_collinear_decimal_points_and_faces_are_degenerate() raises:
    # Exactly collinear decimal points can leave a rounded projection gap.
    # Exact affine predicates classify them as collinear.
    with assert_raises(contains="in a line"):
        _ = ConvexHull(
            [
                point(0, 0, 0),
                point(1, 1, 1),
                point(0.1, 0.1, 0.1),
                point(0.7, 0.7, 0.7),
            ]
        )
    var hull = ConvexHull(tetra(1))
    with assert_raises(contains="in a line"):
        _ = hull._create_face(0, 0, 1)


def test_zero_tolerance_slanted_faces_use_exact_support() raises:
    var s = Float64(5e-324)
    var points: List[SIMD[DType.float64, 4]] = [
        point(0, 0, 0),
        point(2 * s, s, 0),
        point(0, 3 * s, s),
        point(s, 0, 4 * s),
    ]
    var hull = ConvexHull(points)
    assert_equal(hull.tolerance, 0)
    assert_equal(hull.face_count(), 4)
    for p in points:
        assert_true(hull.contains_point(p))
    check_surface(
        hull,
        [
            Vector3(0, 0, 0),
            Vector3(2, 1, 0),
            Vector3(0, 3, 1),
            Vector3(1, 0, 4),
        ],
    )
    assert_false(hull.contains_point(point(-s, 0, 0)))
    with assert_raises(contains="in a plane"):
        _ = ConvexHull(
            [point(0, 0, 0), point(s, 0, 0), point(0, s, 0), point(s, s, 0)]
        )


def test_mixed_range_queries_are_exterior_even_when_anchors_underflow() raises:
    var s = Float64(1e-300)
    var hull = ConvexHull(
        [
            point(0, 0, 0),
            point(2 * s, s, 0),
            point(0, 3 * s, s),
            point(s, 0, 4 * s),
        ]
    )
    for sign in [Float64(-1), Float64(1)]:
        for axis in range(3):
            var query = point(sign * 5e-324, -sign * s, sign * s)
            query[axis] = sign * 1e308
            assert_false(hull.contains_point(query))
            # The plane tolerance may itself scale to zero for this query.
            hull.tolerance = Float64(5e-324)
            assert_false(hull.contains_point(query))
            hull.tolerance = 0
            assert_false(hull.contains_point(query))
    assert_true(hull.contains_point(point(0.75 * s, s, 1.25 * s)))


def test_power_of_two_helpers_cover_binary64_endpoints() raises:
    assert_equal(_scale(1, -1074), Float64(5e-324))
    assert_equal(_scale(Float64(5e-324), 1074), Float64(1))
    assert_equal(_exponent(Float64(5e-324)), -1073)
    assert_equal(_exponent(0), 0)
    var huge = Float64(1e308)
    assert_equal(_scale(_scale(huge, -1024), 1024), huge)
    var normal = _unit_or_zero(_Point(1e-160, -1e-160, 1e-160))
    assert_almost_equal(normal.dot(normal), 1, atol=1e-15)


def test_finite_opposite_extremes_do_not_overflow_spans_or_midpoints() raises:
    var points = List[SIMD[DType.float64, 4]]()
    var reference = List[Vector3]()
    for i in range(8):
        var x = Float64(2 * (i & 1) - 1)
        var y = Float64(2 * ((i >> 1) & 1) - 1)
        var z = Float64(2 * ((i >> 2) & 1) - 1)
        points.append(point(x * 1e308, y * 1e308, z * 1e308))
        reference.append(Vector3(Float32(x), Float32(y), Float32(z)))
    var hull = ConvexHull(points)
    check_surface(hull, reference)
    assert_true(isfinite(hull.tolerance))
    for p in points:
        assert_true(hull.contains_point(p))
    assert_true(hull.contains_point(point(0, 0, 0)))
    assert_false(hull.contains_point(point(1.5e308, 0, 0)))


def test_empty_public_face_list_preserves_finite_containment() raises:
    for scale in [Float64(1), Float64(1e-300)]:
        var hull = ConvexHull(tetra(scale))
        hull.faces.clear()
        assert_true(hull.contains_point(Vector3(0, 0, 0)))
        assert_true(hull.contains_point(point(scale, scale, scale)))
        assert_false(hull.contains_point(Vector3(nan[DType.float32](), 0, 0)))
        assert_false(hull.contains_point(point(0, inf[DType.float64](), 0)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
