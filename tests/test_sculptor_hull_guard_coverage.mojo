# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Pointer-ray validation and exact fallback face-normal controls."""

from core.assets import Assets
from core.object3d import Object3D
from geometries.sculptor import Sculptor
from math.convex_hull import ConvexHull, _Point
from math.vector3 import Vector3
from std.math import ldexp, isnan, isfinite
from std.memory import bitcast
from geometries.sculptor import _apply_matrix
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests.test_sculptor import _scene, _bumpy, _camera


def test_pointer_ray_checks_each_zero_component_and_a_rounded_zero_ray() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.connect(0, 0, 200, 200)
    _ = sculptor._update_mesh_matrix(scene)
    for axis in range(3):
        var camera = _camera()
        var target = [Float32(0), Float32(0), Float32(0)]
        target[axis] = 1
        if axis == 1:
            camera.up = Vector3(0, 0, 1)
        camera.place(Vector3(0, 0, 0), Vector3(target[0], target[1], target[2]))
        assert_true(sculptor._update_pointer_ray(camera, scene, 100, 100))
        var direction = sculptor._ray_direction
        for lane in range(3):
            assert_equal(
                [direction.x, direction.y, direction.z][lane],
                Float64(lane == axis),
            )
    # Finite placement can round both unprojected depths to the same stored
    # Float32 world position. Such a pointer has no usable direction.
    var distant = _camera()
    distant.place(Vector3(1e30, 1e30, 1e30), Vector3(0, 0, 0))
    assert_false(sculptor._update_pointer_ray(distant, scene, 100, 100))


def test_point_component_and_exact_face_fallback() raises:
    var point = _Point(2, 3, 5)
    assert_equal(point.component(0), Float64(2))
    assert_equal(point.component(1), Float64(3))
    assert_equal(point.component(2), Float64(5))
    comptime P = SIMD[DType.float64, 4]
    var points: List[P] = [
        P(0),
        P(1, 0, 0, 0),
        P(0, 1, 0, 0),
        P(0, 0, 1, 0),
        P(1e-200, 0, 0, 0),
        P(0, 1e-200, 0, 0),
    ]
    var hull = ConvexHull(points)
    # The valid finite triangle exists in the original point array, though
    # its area underflows direct binary64. Its exact normal remains +z.
    var face = hull._create_face(0, 4, 5)
    assert_equal(hull._normal[face].x, Float64(0))
    assert_equal(hull._normal[face].y, Float64(0))
    assert_equal(hull._normal[face].z, Float64(1))
    assert_equal(hull._ranking_normal[face].z, Float64(1))


def test_hull_initial_rank_recovers_an_underflowed_first_candidate() raises:
    comptime P = SIMD[DType.float64, 4]
    var points: List[P] = [
        P(0),
        P(1, 0, 0, 0),
        P(0.5, 1e-300, 0, 0),
        P(0, 1, 0, 0),
        P(0, 0, 1, 0),
    ]
    var hull = ConvexHull(points)
    assert_equal(hull.face_count(), 4)
    hull.tolerance = 0
    for point in points:
        assert_true(hull.contains_point(point))


def test_hull_small_exterior_offsets_survive_translated_plane_rounding() raises:
    from tests.test_convex_hull_exact import _check_closed

    comptime P = SIMD[DType.float64, 4]
    for h in [Float64(1125899906842624), Float64(281474976710656)]:
        var points: List[P] = [
            P(h, h, h, 0),
            P(h + 100, h, h, 0),
            P(h, h + 100, h, 0),
            P(h, h, h + 100, 0),
            P(h + 50, h + 25, h + 25.25, 0),
            P(h + 25, h + 50, h + 25.25, 0),
        ]
        var hull = ConvexHull(points)
        assert_equal(hull.face_count(), 8)
        _check_closed(hull, 6)
        hull.tolerance = 0
        for point in points:
            assert_true(hull.contains_point(point))


def test_certified_exterior_rankings_handle_zero_rounded_distances() raises:
    comptime P = SIMD[DType.float64, 4]
    var face_case = False
    var vertex_case = False
    for h in [Float64(1125899906842624), Float64(281474976710656)]:
        var points: List[P] = [
            P(h, h, h, 0),
            P(h + 100, h, h, 0),
            P(h, h + 100, h, 0),
            P(h, h, h + 100, 0),
            P(h + 50, h + 25, h + 25.25, 0),
            P(h + 25, h + 50, h + 25.25, 0),
            P(h + 50.25, h + 50.25, h - 0.25, 0),
            P(h + 50, h + 25, h + 25.5, 0),
        ]
        var hull = ConvexHull(points)
        var slanted = hull._create_face(1, 2, 3)
        var bottom = hull._create_face(0, 2, 1)
        assert_true(hull._sees(slanted, points[6], 0))
        assert_true(hull._sees(bottom, points[6], 0))
        if hull._distance(slanted, hull._points[6]) <= 0:
            # Exact distances are .25/sqrt(3) and .25, respectively.
            assert_true(hull._farther_face(bottom, slanted, 6))
            assert_false(hull._farther_face(slanted, bottom, 6))
            face_case = True
        assert_true(hull._sees(slanted, points[4], 0))
        assert_true(hull._sees(slanted, points[5], 0))
        var d4 = hull._distance(slanted, hull._points[4])
        var d5 = hull._distance(slanted, hull._points[5])
        if d4 <= 0 or d5 <= 0:
            # Both source points are exactly .25/sqrt(3) above the plane.
            assert_false(hull._farther_vertex(slanted, 4, 5))
            assert_false(hull._farther_vertex(slanted, 5, 4))
            vertex_case = True
            var zero = 4 if d4 <= 0 else 5
            assert_true(hull._distance(slanted, hull._points[7]) > 0)
            assert_true(hull._sees(slanted, points[7], 0))
            # The later point is exactly twice as far above this plane.
            assert_true(hull._farther_vertex(slanted, 7, zero))
            assert_false(hull._farther_vertex(slanted, zero, 7))
    assert_true(face_case)
    assert_true(vertex_case)


def test_pointer_rejects_overflow_after_a_finite_projective_world_transform() raises:
    var scale = ldexp(Float32(1), 120)
    var tiny = bitcast[DType.float32](UInt32(1))
    for axis in [1, 2]:
        # These public matrix overrides are finite and invertible, with
        # uniform spatial columns within the accepted orthogonality bound.
        # The inverse arithmetic leaves a tiny determinant residual. Its
        # projective products overflow only one local coordinate.
        var node = Object3D()
        node.matrix_auto_update = False
        if axis == 1:
            node.matrix.elements = [
                scale,
                tiny,
                0,
                0,
                0,
                scale,
                tiny,
                0,
                tiny,
                0,
                scale,
                scale,
                0,
                scale,
                0,
                -tiny,
            ]
        else:
            # Exact determinant: tiny^4 - scale^2*tiny^2, which is nonzero.
            node.matrix.elements = [
                scale,
                0,
                -tiny,
                scale,
                0,
                scale,
                0,
                -tiny,
                -tiny,
                0,
                scale,
                -tiny,
                0,
                -tiny,
                scale,
                0,
            ]
        var assets = Assets()
        var scene = _scene(_bumpy(), assets, node)
        var sculptor = Sculptor(scene, assets, 0)
        sculptor.connect(0, 0, 200, 200)
        assert_true(isfinite(sculptor._update_mesh_matrix(scene)))
        var camera = _camera()
        camera.place(Vector3(1e30, 1e30, 1e30), Vector3(0, 0, 0))
        var near = _apply_matrix(
            sculptor._matrix_inverse,
            sculptor._unproject(camera, scene, 100, 100, -1),
        )
        assert_true(isfinite(near.x))
        if axis == 1:
            assert_true(isnan(near.y))
            assert_true(isfinite(near.z))
        else:
            assert_true(isfinite(near.y))
            assert_true(isnan(near.z))
        assert_false(sculptor._update_pointer_ray(camera, scene, 100, 100))
        assert_false(sculptor.pick_from_pointer(camera, scene, 100, 100))


def test_initial_hull_ranking_keeps_certified_points_after_dot_cancellation() raises:
    from math.exact_predicates import _plane_above
    from tests.test_convex_hull_exact import _check_closed

    comptime P = SIMD[DType.float64, 4]
    var b = P(
        bitcast[DType.float64](UInt64(0x3FEEF6718231B490)),
        bitcast[DType.float64](UInt64(0x3FE67601F41085C0)),
        bitcast[DType.float64](UInt64(0x3FE6B143851ACB30)),
        0,
    )
    var c = P(
        bitcast[DType.float64](UInt64(0x3FDEF6718231B890)),
        bitcast[DType.float64](UInt64(0x3FD67601F41081C0)),
        bitcast[DType.float64](UInt64(0x3FD6B143851AC730)),
        0,
    )
    var queries: List[P] = [
        P(
            bitcast[DType.float64](UInt64(0x3E01F95385CD607C)),
            bitcast[DType.float64](UInt64(0x3DFA13CBE06FF562)),
            bitcast[DType.float64](UInt64(0x3DFA577C9A12417E)),
            0,
        ),
        P(
            2.652826105259242e-10,
            1.9244154775721533e-10,
            1.9436184251135187e-10,
            0,
        ),
        P(
            5.382560113935459e-10,
            3.904621554984165e-10,
            3.9454891563035223e-10,
            0,
        ),
        P(
            bitcast[DType.float64](UInt64(0x3DB5D4C8582D175E)),
            bitcast[DType.float64](UInt64(0x3DAFAF1419695BE8)),
            bitcast[DType.float64](UInt64(0x3DB0000000000000)),
            0,
        ),
    ]
    for variant in range(4):
        var q = queries[variant]
        var next = q
        var changed_axis = 1 if variant == 3 else 2
        next[changed_axis] = bitcast[DType.float64](
            bitcast[DType.uint64](q[changed_axis]) + UInt64(1)
        )
        var points: List[P] = [P(0), b, c, q, next, q * 0.5]
        # Independent Fraction enumeration supplies these supporting faces
        # as vertex bit masks. Point 5 is on A-Q. The three cases cover
        # cross-product contraction orders without assuming an intermediate
        # rounded score is part of the public geometry contract.
        var facets: List[Int] = [7, 11, 13, 14]
        if variant == 1:
            facets = [7, 19, 13, 25, 14, 26]
        elif variant == 2 or variant == 3:
            facets = [7, 19, 21, 22]
        var hull = ConvexHull(points)
        assert_false(hull._exact_ranking)
        assert_true(hull.tolerance < 1.59e-15)
        # Independent exact squared comparisons place every query strictly
        # beyond the constructor tolerance. The fourth query was solved
        # from the pinned native/instrumented normal and fused-dot order;
        # its power-of-two z product permits exact rounded cancellation.
        for query in [q, next, q * 0.5]:
            if variant == 2:
                assert_true(_plane_above(P(0), c, b, query, hull.tolerance))
            else:
                assert_true(_plane_above(P(0), b, c, query, hull.tolerance))
        assert_equal(hull.face_count(), len(facets))
        for face in range(hull.face_count()):
            var mask = 0
            for corner in range(3):
                mask |= 1 << hull.face_vertex(face, corner)
            var supported = False
            for allowed in facets:
                supported = supported or mask == allowed
            assert_true(supported)
        _check_closed(hull, len(points))
        hull.tolerance = 0
        for point in points:
            assert_true(hull.contains_point(point))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
