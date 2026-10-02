# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Analytic face and rounding controls for wide ray queries."""

from math.bounds import Box3, Sphere
from math.ray import Ray, _distance_sq_ratio, _radius_relation
from math.octree import Octree
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, isnan, nan, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)


def permute(value: Vector3, axis: Int) -> Vector3:
    """Cycle a case through the three axis choices."""
    if axis == 0:
        return value
    if axis == 1:
        return Vector3(value.z, value.x, value.y)
    return Vector3(value.y, value.z, value.x)


def test_near_equal_direction_components_retain_the_corner() raises:
    for neighbor in range(-3, 4):
        var component = bitcast[DType.float32](UInt32(0x3F800000 + neighbor))
        for axis in range(3):
            var ray = Ray(
                Vector3(0, 0, 0), permute(Vector3(component, 1, 0.5), axis)
            )
            # Power-of-two scaling preserves an exact line through zero.
            ray.origin = ray.direction * -16
            var box = Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))
            assert_true(ray.intersects_box(box))
            var point = ray.intersect_box(box).value()
            assert_equal(point.x, 0)
            assert_equal(point.y, 0)
            assert_equal(point.z, 0)


def test_distant_disjoint_intervals_in_each_axis_order() raises:
    for axis in range(3):
        var ray = Ray(
            permute(Vector3(1e19, 1e19, 0), axis),
            permute(Vector3(-1, -1, 0), axis),
        )
        var box = Box3(
            permute(Vector3(0, 10, -1), axis), permute(Vector3(1, 11, 1), axis)
        )
        assert_false(ray.intersects_box(box))
        assert_false(Bool(ray.intersect_box(box)))


def test_parallel_face_neighbors_are_not_rounded_inward() raises:
    for axis in range(3):
        for neighbor in range(-1, 2):
            var y = bitcast[DType.float32](UInt32(0x3F800000 + neighbor))
            var ray = Ray(
                permute(Vector3(-4, y, 0), axis),
                permute(Vector3(1, 0, 0), axis),
            )
            var box = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
            assert_equal(ray.intersects_box(box), neighbor <= 0)
            assert_equal(Bool(ray.intersect_box(box)), neighbor <= 0)


def test_subnormal_direction_components_keep_finite_faces() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    for axis in range(3):
        var ray = Ray(Vector3(0, 0, 0), permute(Vector3(1, tiny, 0), axis))
        var box = Box3(
            permute(Vector3(1, tiny, -1), axis),
            permute(Vector3(2, 2 * tiny, 1), axis),
        )
        var point = ray.intersect_box(box).value()
        var want = permute(Vector3(1, tiny, 0), axis)
        assert_equal(point.x, want.x)
        assert_equal(point.y, want.y)
        assert_equal(point.z, want.z)


def test_an_origin_on_a_face_is_the_entry_not_the_exit() raises:
    for axis in range(3):
        var origin = permute(Vector3(2, -4, 1), axis)
        var ray = Ray(origin, permute(Vector3(-5, 0, 1), axis))
        var box = Box3(
            permute(Vector3(0, -4, -3), axis), permute(Vector3(2, 0, 3), axis)
        )
        var point = ray.intersect_box(box).value()
        assert_equal(point.x, origin.x)
        assert_equal(point.y, origin.y)
        assert_equal(point.z, origin.z)


def test_radius_comparison_preserves_division_at_adjacent_boundaries() raises:
    for radius_sq in [Float64(1e-60), Float64(1), Float64(1e38)]:
        for denominator in [
            Float64(0.99999997),
            Float64(1),
            Float64(1.00000003),
        ]:
            var product = radius_sq * denominator
            for neighbor in range(-6, 7):
                var numerator = bitcast[DType.float64](
                    UInt64(Int(bitcast[DType.uint64](product)) + neighbor)
                )
                var got = _radius_relation((numerator, denominator), radius_sq)
                assert_equal(got[0], numerator / denominator <= radius_sq)
                assert_equal(got[1], numerator / denominator > radius_sq)
    for numerator in [
        Float64(0),
        Float64(1),
        inf[DType.float64](),
        nan[DType.float64](),
    ]:
        for radius_sq in [
            Float64(0),
            inf[DType.float64](),
            nan[DType.float64](),
        ]:
            var got = _radius_relation((numerator, Float64(1)), radius_sq)
            assert_equal(got[0], numerator <= radius_sq)
            assert_equal(got[1], numerator > radius_sq)


def test_zero_direction_stays_refused() raises:
    with assert_raises():
        _ = Ray(Vector3(0, 0, 0), Vector3(0, 0, 0))


def test_invalid_mutable_rays_keep_their_existing_box_result() raises:
    var box = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
    for origin in [Vector3(0, 0, 0), Vector3(3, 3, 3)]:
        for direction in [
            Vector3(0, 0, 0),
            Vector3(nan[DType.float32](), 0, 0),
            Vector3(inf[DType.float32](), 0, 0),
        ]:
            var ray = Ray(origin, Vector3(1, 0, 0))
            ray.direction = direction
            assert_true(ray.intersects_box(box))
            var products = ray._query_products()
            assert_false(products.regular)
            assert_true(ray._box_decision[True](box, products)[0])
            var hit = ray.intersect_box(box).value()
            assert_true(isnan(hit.x) and isnan(hit.y) and isnan(hit.z))
    var ray = Ray(Vector3(nan[DType.float32](), 0, 0), Vector3(1, 0, 0))
    assert_true(ray.intersects_box(box))
    var products = ray._query_products()
    assert_false(products.regular)
    assert_true(ray._box_decision[True](box, products)[0])
    var hit = ray.intersect_box(box).value()
    assert_true(isnan(hit.x) and isnan(hit.y) and isnan(hit.z))


def test_mutable_nonunit_directions_keep_the_same_geometric_hits() raises:
    for scale in [
        Float32(1e-40),
        Float32(1e19),
        Float32(-1e-40),
        Float32(-1e19),
    ]:
        var sign = Float32(1) if scale > 0 else Float32(-1)
        for axis in range(3):
            var ray = Ray(
                permute(Vector3(-3 * sign, 0.25, 0), axis),
                permute(Vector3(sign, 0, 0), axis),
            )
            ray.direction = permute(Vector3(scale, 0, 0), axis)
            var box = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
            assert_true(ray.intersects_box(box))
            var point = ray.intersect_box(box).value()
            var want = permute(Vector3(-sign, 0.25, 0), axis)
            assert_equal(point.x, want.x)
            assert_equal(point.y, want.y)
            assert_equal(point.z, want.z)
            var sphere = Sphere(Vector3(0, 0, 0), 1)
            assert_true(ray.intersects_sphere(sphere))
            point = ray.intersect_sphere(sphere).value()
            want = permute(
                Vector3(-sign * sqrt(Float32(0.9375)), 0.25, 0), axis
            )
            assert_equal(point.x, want.x)
            assert_equal(point.y, want.y)
            assert_equal(point.z, want.z)


def test_degenerate_bounds_and_signed_zero_keep_their_surfaces() raises:
    var ray = Ray(Vector3(-2, 0, 0), Vector3(1, -0.0, -0.0))
    var point_box = Box3(Vector3(0, 0, 0), Vector3(0, 0, 0))
    assert_true(ray.intersects_box(point_box))
    var hit = ray.intersect_box(point_box).value()
    assert_equal(hit.x, 0)
    assert_equal(hit.y, 0)
    assert_equal(hit.z, 0)
    assert_equal(bitcast[DType.uint32](ray.direction.y), UInt32(0x80000000))
    var plane = Box3(Vector3(0, -1, -1), Vector3(0, 1, 1))
    assert_true(ray.intersects_box(plane))
    hit = ray.intersect_box(plane).value()
    assert_equal(hit.x, 0)
    var along = Ray(Vector3(0, -2, 0), Vector3(-0.0, 1, -0.0))
    assert_true(along.intersects_box(plane))
    hit = along.intersect_box(plane).value()
    assert_equal(hit.x, 0)
    assert_equal(hit.y, -1)
    assert_equal(hit.z, 0)
    along.origin.x = 1
    assert_false(along.intersects_box(plane))
    assert_false(Bool(along.intersect_box(plane)))


def test_each_octree_query_takes_a_fresh_ray_snapshot() raises:
    var tree = Octree()
    tree.add_triangle(
        Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
    )
    tree.build()
    var ray = Ray(Vector3(0.25, 0.25, 1), Vector3(0, 0, -1))
    assert_true(Bool(tree.ray_intersect(ray)))
    ray.origin.x = 3
    assert_false(Bool(tree.ray_intersect(ray)))
    ray.origin.x = 0.25
    ray.direction.z = 1
    assert_false(Bool(tree.ray_intersect(ray)))
    ray.direction.z = -1
    assert_true(Bool(tree.ray_intersect(ray)))


def test_infinite_mutable_direction_keeps_the_existing_sphere_rejection() raises:
    var ray = Ray(Vector3(0, 0, 0), Vector3(1, 0, 0))
    ray.direction.x = inf[DType.float32]()
    # With this invalid direction, the original projection is infinity /
    # infinity. It does not turn a containing sphere into a valid hit.
    assert_false(ray.intersects_sphere(Sphere(Vector3(-1, 0, 0), 2)))
    assert_true(isnan(ray.distance_to_point(Vector3(-1, 0, 0))))


def test_unbounded_boxes_keep_correct_volume_and_finite_surface_queries() raises:
    var top = inf[DType.float32]()
    var all_space = Box3(Vector3(-top, -top, -top), Vector3(top, top, top))
    var ray = Ray(Vector3(3, 2, 1), Vector3(-1, 0.25, 0.5))
    assert_true(ray.intersects_box(all_space))
    assert_false(Bool(ray.intersect_box(all_space)))
    for axis in range(3):
        var halfspace = Box3(
            Vector3(-top, -top, -top), permute(Vector3(0, top, top), axis)
        )
        var entering = Ray(
            permute(Vector3(3, 2, 1), axis),
            permute(Vector3(-1, 0.25, 0.5), axis),
        )
        assert_true(entering.intersects_box(halfspace))
        var hit = entering.intersect_box(halfspace).value()
        var want = permute(Vector3(0, 2.75, 2.5), axis)
        assert_equal(hit.x, want.x)
        assert_equal(hit.y, want.y)
        assert_equal(hit.z, want.z)
        var exiting = Ray(
            permute(Vector3(-3, 2, 1), axis), permute(Vector3(1, 0, 0), axis)
        )
        assert_true(exiting.intersects_box(halfspace))
        hit = exiting.intersect_box(halfspace).value()
        want = permute(Vector3(0, 2, 1), axis)
        assert_equal(hit.x, want.x)
        assert_equal(hit.y, want.y)
        assert_equal(hit.z, want.z)
        exiting.direction = permute(Vector3(-1, 0, 0), axis)
        assert_true(exiting.intersects_box(halfspace))
        assert_false(Bool(exiting.intersect_box(halfspace)))
        exiting.origin = permute(Vector3(3, 2, 1), axis)
        exiting.direction = permute(Vector3(1, 0, 0), axis)
        assert_false(exiting.intersects_box(halfspace))
        assert_false(Bool(exiting.intersect_box(halfspace)))
    assert_false(ray.intersects_box(Box3.empty()))
    assert_false(Bool(ray.intersect_box(Box3.empty())))
    var strip = Box3(Vector3(-top, 10, 20), Vector3(top, 11, 21))
    var diagonal = Ray(Vector3(0, 0, 0), Vector3(1, 1, 1))
    assert_false(diagonal.intersects_box(strip))
    assert_false(Bool(diagonal.intersect_box(strip)))


def test_nan_bounds_do_not_report_an_intersection() raises:
    var bad = nan[DType.float32]()
    var ray = Ray(Vector3(0, 0, 0), Vector3(1, 0, 0))
    for box in [
        Box3(Vector3(bad, -1, -1), Vector3(1, 1, 1)),
        Box3(Vector3(-1, -1, -1), Vector3(bad, 1, 1)),
    ]:
        assert_false(ray.intersects_box(box))
        assert_false(Bool(ray.intersect_box(box)))


def test_sphere_filter_keeps_entry_exit_and_miss_for_stored_norms() raises:
    for axis in range(3):
        for speed in [Float32(2), Float32(1e-40), Float32(3e38)]:
            for sign in [Float32(-1), Float32(1)]:
                var ray = Ray(
                    permute(Vector3(-4 * sign, 0, 0), axis),
                    permute(Vector3(sign, 0, 0), axis),
                )
                ray.direction = permute(Vector3(speed * sign, 0, 0), axis)
                var sphere = Sphere(Vector3(0, 0, 0), 1)
                var point = ray.intersect_sphere(sphere).value()
                var expected = permute(Vector3(-sign, 0, 0), axis)
                assert_equal(point.x, expected.x)
                assert_equal(point.y, expected.y)
                assert_equal(point.z, expected.z)
                ray.origin = Vector3(0, 0, 0)
                point = ray.intersect_sphere(sphere).value()
                expected = permute(Vector3(sign, 0, 0), axis)
                assert_equal(point.x, expected.x)
                assert_equal(point.y, expected.y)
                assert_equal(point.z, expected.z)
                ray.origin = permute(Vector3(4 * sign, 0, 0), axis)
                assert_false(Bool(ray.intersect_sphere(sphere)))
                ray.origin = permute(Vector3(-4 * sign, 3, 0), axis)
                assert_false(Bool(ray.intersect_sphere(sphere)))


def test_sphere_filter_boundaries_keep_analytic_axis_contacts() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    var ray = Ray(Vector3(1, 0, 0), Vector3(1, 0, 0))
    # The fallback helper retains its explicit empty-input defense.
    assert_false(
        ray._intersect_sphere_fallback(Sphere(Vector3(0, 0, 0), -1)).found
    )
    for direction in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0)]:
        ray.direction = direction
        var point = ray.intersect_sphere(sphere).value()
        assert_equal(point.x, 1)
        assert_equal(point.y, 0)
        assert_equal(point.z, 0)
    ray = Ray(Vector3(1, 0, -4), Vector3(0, 0, 1))
    var point = ray.intersect_sphere(sphere).value()
    assert_equal(point.x, 1)
    assert_equal(point.y, 0)
    assert_equal(point.z, 0)
    ray.origin.z = 4
    assert_false(Bool(ray.intersect_sphere(sphere)))
    ray.origin = Vector3(bitcast[DType.float32](UInt32(0x3F800001)), 0, -4)
    assert_false(Bool(ray.intersect_sphere(sphere)))


def test_sphere_filter_does_not_narrow_a_huge_parameter() raises:
    var center = Float32(3e38)
    var radius = Float32(1e37)
    var ray = Ray(Vector3(-center, 0, 0), Vector3(1, 0, 0))
    var point = ray.intersect_sphere(
        Sphere(Vector3(center, 0, 0), radius)
    ).value()
    assert_equal(point.x, Float32(Float64(center) - Float64(radius)))
    assert_equal(point.y, 0)
    assert_equal(point.z, 0)


def test_invalid_snapshot_keeps_legacy_result_after_a_finite_pair_misses() raises:
    var ray = Ray(Vector3(nan[DType.float32](), 2, -10), Vector3(0, -1, 1))
    var box = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
    assert_true(ray.intersects_box(box))
    assert_true(ray._box_decision[True](box, ray._query_products())[0])
    var point = ray.intersect_box(box).value()
    assert_true(isnan(point.x) and isnan(point.y) and isnan(point.z))


def test_public_sphere_nonfinite_controls_match_divided_distance() raises:
    # Frozen pre-557 extended point results in loop order: miss, all NaN,
    # positive-infinite x with NaN y/z, zero, or unit-x. NaN payloads are
    # deliberately not a geometric contract.
    var snapshot = String(
        "ZUINMMINNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
        + "MMINMMINNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
        + "NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
        + "NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
    )
    var snapshot_index = 0
    var infinity = inf[DType.float32]()
    var invalid = nan[DType.float32]()
    for origin in [
        Vector3(0, 0, 0),
        Vector3(1, 2, 3),
        Vector3(infinity, 0, 0),
        Vector3(invalid, 2, -10),
    ]:
        for direction in [
            Vector3(1, 0, 0),
            Vector3(0, 0, 0),
            Vector3(infinity, 1, 0),
            Vector3(0, infinity, -1),
            Vector3(invalid, 1, 0),
            Vector3(1, invalid, infinity),
        ]:
            var ray = Ray(origin, Vector3(1, 0, 0))
            ray.direction = direction
            for center in [
                Vector3(0, 0, 0),
                Vector3(1, -2, 3),
                Vector3(infinity, 1, 0),
                Vector3(invalid, 0, 0),
            ]:
                for radius in [Float32(0), Float32(1), infinity, invalid]:
                    var sphere = Sphere(center, radius)
                    # This checks inherited comparison semantics, not a
                    # geometric contract for nonfinite or zero rays.
                    var ratio = _distance_sq_ratio(origin, direction, center)
                    var want = ratio[0] / ratio[1] <= Float64(radius) * Float64(
                        radius
                    )
                    assert_equal(ray.intersects_sphere(sphere), want)
                    var hit = ray.intersect_sphere(sphere)
                    var code = snapshot.as_bytes()[snapshot_index]
                    snapshot_index += 1
                    assert_equal(Bool(hit), code != 77)
                    if hit:
                        var point = hit.value()
                        if code == 78:
                            assert_true(
                                isnan(point.x)
                                and isnan(point.y)
                                and isnan(point.z)
                            )
                        elif code == 73:
                            assert_equal(point.x, infinity)
                            assert_true(isnan(point.y) and isnan(point.z))
                        else:
                            assert_equal(
                                point.x, Float32(1 if code == 85 else 0)
                            )
                            assert_equal(point.y, 0)
                            assert_equal(point.z, 0)


def test_exact_stored_sphere_boundary_decisions() raises:
    """Retain every distinct Fraction-oracle failure from issue 557.

    These are stored Float32 bits, not decimal or renormalized inputs.
    Exact rational polynomials determine each expected decision.
    """
    var rows = [
        [
            UInt32(228737632),
            UInt32(2384609888),
            UInt32(242443152),
            UInt32(1058931123),
            UInt32(3189637555),
            UInt32(1061519903),
            UInt32(2376221280),
            UInt32(237126240),
            UInt32(2376221280),
            UInt32(250831760),
            UInt32(1),
        ],
        [
            UInt32(245514848),
            UInt32(0),
            UInt32(2392998496),
            UInt32(3211065646),
            UInt32(0),
            UInt32(1055193390),
            UInt32(228737632),
            UInt32(2384609888),
            UInt32(0),
            UInt32(242443152),
            UInt32(1),
        ],
        [
            UInt32(2376221280),
            UInt32(256561912),
            UInt32(228737632),
            UInt32(1058446848),
            UInt32(1044959915),
            UInt32(1061737131),
            UInt32(2376221280),
            UInt32(228737632),
            UInt32(228737632),
            UInt32(255232684),
            UInt32(1),
        ],
        [
            UInt32(245514848),
            UInt32(2402716332),
            UInt32(2392998496),
            UInt32(3196638839),
            UInt32(3209511346),
            UInt32(1057543799),
            UInt32(0),
            UInt32(2376221280),
            UInt32(2389926800),
            UInt32(255232684),
            UInt32(1),
        ],
        [
            UInt32(248173304),
            UInt32(2401387104),
            UInt32(2389926800),
            UInt32(0),
            UInt32(3205365973),
            UInt32(1062535488),
            UInt32(228737632),
            UInt32(0),
            UInt32(2384609888),
            UInt32(255232684),
            UInt32(1),
        ],
        [
            UInt32(250831760),
            UInt32(256561912),
            UInt32(237126240),
            UInt32(3210704002),
            UInt32(1054831746),
            UInt32(1046443138),
            UInt32(228737632),
            UInt32(2384609888),
            UInt32(237126240),
            UInt32(260298222),
            UInt32(1),
        ],
        [
            UInt32(2392998496),
            UInt32(2400057876),
            UInt32(2376221280),
            UInt32(1065027414),
            UInt32(0),
            UInt32(1044959915),
            UInt32(228737632),
            UInt32(2384609888),
            UInt32(0),
            UInt32(248173304),
            UInt32(0),
        ],
        [
            UInt32(242443152),
            UInt32(2376221280),
            UInt32(2392998496),
            UInt32(1062027698),
            UInt32(3205027447),
            UInt32(1049155191),
            UInt32(228737632),
            UInt32(2384609888),
            UInt32(2384609888),
            UInt32(242443152),
            UInt32(1),
        ],
        [
            UInt32(2389926800),
            UInt32(242443152),
            UInt32(228737632),
            UInt32(0),
            UInt32(1062535488),
            UInt32(1057882325),
            UInt32(228737632),
            UInt32(2376221280),
            UInt32(242443152),
            UInt32(250831760),
            UInt32(1),
        ],
        [
            UInt32(248173304),
            UInt32(2398315408),
            UInt32(250831760),
            UInt32(3206125978),
            UInt32(0),
            UInt32(1061997773),
            UInt32(2376221280),
            UInt32(228737632),
            UInt32(0),
            UInt32(257891140),
            UInt32(1),
        ],
        [
            UInt32(250831760),
            UInt32(0),
            UInt32(250831760),
            UInt32(1062755335),
            UInt32(1057083601),
            UInt32(1043142252),
            UInt32(0),
            UInt32(2384609888),
            UInt32(242443152),
            UInt32(252574228),
            UInt32(1),
        ],
        [
            UInt32(250831760),
            UInt32(248173304),
            UInt32(248173304),
            UInt32(1051372203),
            UInt32(3207244459),
            UInt32(1059760811),
            UInt32(0),
            UInt32(2376221280),
            UInt32(2384609888),
            UInt32(257891140),
            UInt32(1),
        ],
        [
            UInt32(2400057876),
            UInt32(2376221280),
            UInt32(2376221280),
            UInt32(3203022049),
            UInt32(3203022049),
            UInt32(1061368508),
            UInt32(2376221280),
            UInt32(237126240),
            UInt32(2389926800),
            UInt32(252574228),
            UInt32(1),
        ],
        [
            UInt32(248173304),
            UInt32(257891140),
            UInt32(2384609888),
            UInt32(3205745978),
            UInt32(1058262330),
            UInt32(1058262330),
            UInt32(2376221280),
            UInt32(2376221280),
            UInt32(237126240),
            UInt32(260962836),
            UInt32(1),
        ],
        [
            UInt32(2392998496),
            UInt32(256561912),
            UInt32(250831760),
            UInt32(3212335939),
            UInt32(0),
            UInt32(1048075075),
            UInt32(0),
            UInt32(2384609888),
            UInt32(0),
            UInt32(260962836),
            UInt32(1),
        ],
        [
            UInt32(2389926800),
            UInt32(228737632),
            UInt32(2389926800),
            UInt32(0),
            UInt32(1064492264),
            UInt32(1050798235),
            UInt32(2376221280),
            UInt32(2384609888),
            UInt32(242443152),
            UInt32(252574228),
            UInt32(1),
        ],
        [
            UInt32(245514848),
            UInt32(253903456),
            UInt32(245514848),
            UInt32(3207568724),
            UInt32(1057207807),
            UInt32(1057207807),
            UInt32(0),
            UInt32(0),
            UInt32(242443152),
            UInt32(255232684),
            UInt32(1),
        ],
        [
            UInt32(3212836864),
            UInt32(3240099840),
            UInt32(1084227584),
            UInt32(3204691455),
            UInt32(0),
            UInt32(1062962345),
            UInt32(3212836864),
            UInt32(1073741824),
            UInt32(0),
            UInt32(1095761920),
            UInt32(1),
        ],
        [
            UInt32(3238002688),
            UInt32(3225419776),
            UInt32(3221225472),
            UInt32(1052649195),
            UInt32(3205406001),
            UInt32(1061037803),
            UInt32(0),
            UInt32(1065353216),
            UInt32(3225419776),
            UInt32(1091567616),
            UInt32(1),
        ],
        [
            UInt32(3229614080),
            UInt32(3235905536),
            UInt32(3212836864),
            UInt32(1065027414),
            UInt32(0),
            UInt32(1044959915),
            UInt32(1065353216),
            UInt32(3221225472),
            UInt32(0),
            UInt32(1084227584),
            UInt32(0),
        ],
        [
            UInt32(1088421888),
            UInt32(1086324736),
            UInt32(1086324736),
            UInt32(1057543799),
            UInt32(3196638839),
            UInt32(1062027698),
            UInt32(1065353216),
            UInt32(0),
            UInt32(3212836864),
            UInt32(1093664768),
            UInt32(1),
        ],
        [
            UInt32(3225419776),
            UInt32(1065353216),
            UInt32(3225419776),
            UInt32(0),
            UInt32(1064492264),
            UInt32(1050798235),
            UInt32(3212836864),
            UInt32(3221225472),
            UInt32(1077936128),
            UInt32(1088421888),
            UInt32(1),
        ],
        [
            UInt32(71362),
            UInt32(0),
            UInt32(0),
            UInt32(1065353211),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(71362),
            UInt32(1),
        ],
        [
            UInt32(1621981420),
            UInt32(0),
            UInt32(0),
            UInt32(1065353209),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(1621981420),
            UInt32(1),
        ],
        [
            UInt32(0),
            UInt32(71362),
            UInt32(0),
            UInt32(0),
            UInt32(1065353211),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(71362),
            UInt32(1),
        ],
        [
            UInt32(0),
            UInt32(1621981420),
            UInt32(0),
            UInt32(0),
            UInt32(1065353209),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(1621981420),
            UInt32(1),
        ],
        [
            UInt32(0),
            UInt32(0),
            UInt32(71362),
            UInt32(0),
            UInt32(0),
            UInt32(1065353211),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(71362),
            UInt32(1),
        ],
        [
            UInt32(0),
            UInt32(0),
            UInt32(1621981420),
            UInt32(0),
            UInt32(0),
            UInt32(1065353209),
            UInt32(0),
            UInt32(0),
            UInt32(0),
            UInt32(1621981420),
            UInt32(1),
        ],
        [
            UInt32(252574228),
            UInt32(0),
            UInt32(2384609888),
            UInt32(1063751562),
            UInt32(1050304434),
            UInt32(1050304434),
            UInt32(228737632),
            UInt32(2384609888),
            UInt32(228737632),
            UInt32(252574228),
            UInt32(1),
        ],
    ]
    for row in rows:
        var origin = Vector3(
            bitcast[DType.float32](row[0]),
            bitcast[DType.float32](row[1]),
            bitcast[DType.float32](row[2]),
        )
        var direction = Vector3(
            bitcast[DType.float32](row[3]),
            bitcast[DType.float32](row[4]),
            bitcast[DType.float32](row[5]),
        )
        var center = Vector3(
            bitcast[DType.float32](row[6]),
            bitcast[DType.float32](row[7]),
            bitcast[DType.float32](row[8]),
        )
        for axis in range(3):
            var ray = Ray(permute(origin, axis), Vector3(1, 0, 0))
            ray.direction = permute(direction, axis)
            var sphere = Sphere(
                permute(center, axis), bitcast[DType.float32](row[9])
            )
            assert_equal(ray.intersects_sphere(sphere), row[10] != 0)
            assert_equal(Bool(ray.intersect_sphere(sphere)), row[10] != 0)


def test_exact_surface_origin_is_the_first_forward_sphere_point() raises:
    """An exact zero root must never select the opposite surface."""
    for pair in [
        [UInt32(0x1E3CE508), UInt32(0x3F7FFFFE)],
        [UInt32(0x60AD78EC), UInt32(0x3F800005)],
    ]:
        var radius = bitcast[DType.float32](pair[0])
        var component = bitcast[DType.float32](pair[1])
        for axis in range(3):
            for sign in [Float32(-1), Float32(1)]:
                var origin = permute(Vector3(-radius, 0, 0), axis)
                var ray = Ray(origin, Vector3(1, 0, 0))
                ray.direction = permute(Vector3(sign * component, 0, 0), axis)
                var sphere = Sphere(Vector3(0, 0, 0), radius)
                assert_true(ray.intersects_sphere(sphere))
                var point = ray.intersect_sphere(sphere).value()
                assert_equal(point.x, origin.x)
                assert_equal(point.y, origin.y)
                assert_equal(point.z, origin.z)


def test_near_surface_inside_tangent_direction_uses_exit() raises:
    """The origin-side sign chooses exit even with an ambiguous discriminant."""
    var x = bitcast[DType.float32](UInt32(0x3F7FFFFF))
    var ray = Ray(Vector3(x, 0, 0), Vector3(0, 1, 0))
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    var point = ray.intersect_sphere(sphere).value()
    assert_equal(point.x, x)
    assert_equal(point.y, Float32(sqrt(1 - Float64(x) * Float64(x))))
    assert_equal(point.z, 0)
    assert_true(ray.intersects_sphere(sphere))


def test_infinite_center_with_finite_nonzero_components_stays_a_miss() raises:
    """An infinite perpendicular gap retains the extended-input rejection."""
    var ray = Ray(Vector3(0, 0, 0), Vector3(1, 1, 1))
    var sphere = Sphere(Vector3(inf[DType.float32](), 0, 0), 1)
    assert_false(ray.intersects_sphere(sphere))
    assert_false(Bool(ray.intersect_sphere(sphere)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
