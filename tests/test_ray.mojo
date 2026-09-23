# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.ray`.

Every hit is checked against a point worked out by hand on a unit box, a
unit sphere or one triangle in the xy plane, rather than against whatever
the implementation returns. The slab test's cases are chosen to reach each
of its comparisons both ways, including the ones that are only reached by
a direction of zero along an axis with the origin on that axis's face.
"""

from math.bounds import Box3, Plane, Sphere
from math.matrix4 import Matrix4, rotation_z, scaling, translation
from math.projection import perspective
from math.ray import Ray, SegmentApproach
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

comptime TOLERANCE = Float64(1e-5)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def assert_hit(
    hit: Optional[Vector3], x: Float32, y: Float32, z: Float32
) raises:
    """Assert a hit happened, at the given point."""
    assert_true(Bool(hit), "expected a hit")
    assert_point(hit.value(), x, y, z)


def assert_miss(hit: Optional[Vector3]) raises:
    """Assert there was no hit."""
    assert_false(Bool(hit), "expected a miss")


def unit_box() -> Box3:
    """Return the box from the origin to (1, 1, 1)."""
    return Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))


def along(
    ox: Float32, oy: Float32, oz: Float32, dx: Float32, dy: Float32, dz: Float32
) raises -> Ray:
    """Return a ray from an origin in a direction, both given by component."""
    return Ray(Vector3(ox, oy, oz), Vector3(dx, dy, dz))


# --- the ray itself ----------------------------------------------------------


def test_a_ray_makes_its_direction_unit_length() raises:
    var ray = along(1, 2, 3, 0, 3, 4)
    assert_point(ray.origin, 1, 2, 3)
    assert_point(ray.direction, 0, 0.6, 0.8)
    assert_point(ray.at(5), 1, 5, 7)
    assert_point(ray.at(-5), 1, -1, -1)


def test_a_ray_refuses_a_direction_with_no_length() raises:
    with assert_raises():
        _ = along(0, 0, 0, 0, 0, 0)


def test_a_ray_can_be_re_aimed_and_restarted() raises:
    var ray = along(0, 0, 0, 1, 0, 0)
    ray.look_at(Vector3(0, 0, -4))
    assert_point(ray.direction, 0, 0, -1)
    ray.recast(2)
    assert_point(ray.origin, 0, 0, -2)
    assert_point(ray.direction, 0, 0, -1)
    with assert_raises():
        ray.look_at(Vector3(0, 0, -2))


def test_the_nearest_point_is_the_foot_or_the_origin() raises:
    var ray = along(0, 0, 0, 1, 0, 0)
    # Ahead of the origin: the foot of the perpendicular.
    assert_point(ray.closest_point_to_point(Vector3(3, 4, 0)), 3, 0, 0)
    assert_almost_equal(
        ray.distance_to_point(Vector3(3, 4, 0)), Float32(4), atol=TOLERANCE
    )
    # Behind it: the origin, which is as near as the ray comes.
    assert_point(ray.closest_point_to_point(Vector3(-3, 4, 0)), 0, 0, 0)
    assert_almost_equal(
        ray.distance_to_point(Vector3(-3, 4, 0)), Float32(5), atol=TOLERANCE
    )
    assert_almost_equal(
        ray.distance_sq_to_point(Vector3(-3, 4, 0)),
        Float32(25),
        atol=TOLERANCE,
    )


# --- spheres -----------------------------------------------------------------


def test_a_sphere_is_hit_where_the_ray_enters_it() raises:
    var ball = Sphere(Vector3(0, 0, 0), 1)
    assert_hit(along(-3, 0, 0, 1, 0, 0).intersect_sphere(ball), -1, 0, 0)
    # Off center: the entry point is where the chord starts.
    assert_hit(along(-3, 0.6, 0, 1, 0, 0).intersect_sphere(ball), -0.8, 0.6, 0)
    assert_true(along(-3, 0.6, 0, 1, 0, 0).intersects_sphere(ball))


def test_a_ray_from_inside_a_sphere_hits_where_it_leaves() raises:
    var ball = Sphere(Vector3(0, 0, 0), 1)
    assert_hit(along(0, 0, 0, 0, 1, 0).intersect_sphere(ball), 0, 1, 0)
    assert_true(along(0, 0, 0, 0, 1, 0).intersects_sphere(ball))


def test_a_sphere_beside_or_behind_the_ray_is_missed() raises:
    var ball = Sphere(Vector3(0, 0, 0), 1)
    # Beside: the drop from the center is longer than the radius.
    assert_miss(along(-3, 2, 0, 1, 0, 0).intersect_sphere(ball))
    assert_false(along(-3, 2, 0, 1, 0, 0).intersects_sphere(ball))
    # Behind: the line crosses it, the ray does not.
    assert_miss(along(3, 0, 0, 1, 0, 0).intersect_sphere(ball))
    assert_false(along(3, 0, 0, 1, 0, 0).intersects_sphere(ball))


def test_a_distant_sphere_is_hit_or_missed_by_both_answers_alike() raises:
    # Ten kilometers out, the squared distance to the center and the
    # squared distance along the ray agree to every digit a Float32 has,
    # and their difference is zero: a sphere two meters off the ray, of
    # radius one, was "hit" at the axis. The drop is measured as a vector
    # now, and the point answer and the yes-or-no answer agree.
    var ray = along(0, 0, 0, 1, 0, 0)
    var beside = Sphere(Vector3(10000, 2, 0), 1)
    assert_miss(ray.intersect_sphere(beside))
    assert_false(ray.intersects_sphere(beside))
    # Off center but within reach: the entry is where the chord starts.
    var reached = Sphere(Vector3(10000, 0.6, 0), 1)
    assert_hit(ray.intersect_sphere(reached), 9999.2, 0, 0)
    assert_true(ray.intersects_sphere(reached))
    # Tangent: one point, and both answers say so.
    var grazed = Sphere(Vector3(5, 1, 0), 1)
    assert_hit(ray.intersect_sphere(grazed), 5, 0, 0)
    assert_true(ray.intersects_sphere(grazed))
    # From inside a distant sphere, out through its far side.
    var around = Sphere(Vector3(10000, 0, 0), 3)
    var inside = along(9999, 0, 0, 1, 0, 0)
    assert_hit(inside.intersect_sphere(around), 10003, 0, 0)
    assert_true(inside.intersects_sphere(around))


def test_an_empty_sphere_is_hit_nowhere() raises:
    # Its negative radius squares to a real one, so it is asked outright.
    assert_miss(along(-3, 0, 0, 1, 0, 0).intersect_sphere(Sphere.empty()))
    assert_false(along(-3, 0, 0, 1, 0, 0).intersects_sphere(Sphere.empty()))


# --- planes ------------------------------------------------------------------


def test_a_plane_is_met_at_the_distance_along_the_ray() raises:
    var floor = Plane(Vector3(0, 1, 0), 0)
    var ray = along(0, 3, 0, 0, -0.6, 0.8)
    var t = ray.distance_to_plane(floor)
    assert_true(Bool(t))
    assert_almost_equal(t.value(), Float32(5), atol=TOLERANCE)
    assert_hit(ray.intersect_plane(floor), 0, 0, 4)
    assert_true(ray.intersects_plane(floor))


def test_a_plane_the_ray_points_away_from_is_not_met() raises:
    var floor = Plane(Vector3(0, 1, 0), 0)
    var ray = along(0, 3, 0, 0, 1, 0)
    assert_false(Bool(ray.distance_to_plane(floor)))
    assert_miss(ray.intersect_plane(floor))
    assert_false(ray.intersects_plane(floor))


def test_a_parallel_ray_meets_a_plane_only_when_it_lies_in_it() raises:
    var floor = Plane(Vector3(0, 1, 0), 0)
    var above = along(0, 3, 0, 1, 0, 0)
    assert_false(Bool(above.distance_to_plane(floor)))
    assert_miss(above.intersect_plane(floor))
    assert_false(above.intersects_plane(floor))
    var within = along(2, 0, 0, 1, 0, 0)
    var t = within.distance_to_plane(floor)
    assert_true(Bool(t))
    assert_almost_equal(t.value(), Float32(0), atol=TOLERANCE)
    assert_hit(within.intersect_plane(floor), 2, 0, 0)
    assert_true(within.intersects_plane(floor))


# --- boxes -------------------------------------------------------------------


def test_a_box_is_hit_on_the_face_the_ray_enters() raises:
    # Straight at a face.
    assert_hit(
        along(-2, 0.5, 0.5, 1, 0, 0).intersect_box(unit_box()), 0, 0.5, 0.5
    )
    assert_true(along(-2, 0.5, 0.5, 1, 0, 0).intersects_box(unit_box()))
    # Diagonally, entering through the bottom: the y stretch starts later
    # than the x stretch and decides the entry.
    assert_hit(
        along(-1, -1.5, 0.5, 1, 1, 0).intersect_box(unit_box()), 0.5, 0, 0.5
    )
    # Diagonally, leaving through the top: the y stretch ends sooner than
    # the x stretch and decides the exit, and the entry is still on x.
    assert_hit(
        along(-0.5, 0.25, 0.5, 1, 1, 0).intersect_box(unit_box()), 0, 0.75, 0.5
    )
    # The same two, on z.
    assert_hit(
        along(-1, 0.5, -1.5, 1, 0, 1).intersect_box(unit_box()), 0.5, 0.5, 0
    )
    assert_hit(
        along(-0.5, 0.5, 0.25, 1, 0, 1).intersect_box(unit_box()), 0, 0.5, 0.75
    )


def test_a_ray_from_inside_a_box_hits_where_it_leaves() raises:
    assert_hit(
        along(0.5, 0.5, 0.5, 1, 0, 0).intersect_box(unit_box()), 1, 0.5, 0.5
    )


def test_a_box_the_ray_passes_by_or_leaves_behind_is_missed() raises:
    # The x stretch starts after the y stretch has ended.
    assert_miss(along(-4, 1.5, 0.5, 1, -1, 0).intersect_box(unit_box()))
    # The y stretch starts after the x stretch has ended.
    assert_miss(along(-1, 4, 0.5, 1, -1, 0).intersect_box(unit_box()))
    # The same two, on z.
    assert_miss(along(-4, 0.5, 1.5, 1, 0, -1).intersect_box(unit_box()))
    assert_miss(along(-1, 0.5, 4, 1, 0, -1).intersect_box(unit_box()))
    # Wholly behind the origin.
    assert_miss(along(3, 0.5, 0.5, 1, 0, 0).intersect_box(unit_box()))
    assert_false(along(3, 0.5, 0.5, 1, 0, 0).intersects_box(unit_box()))


def test_a_ray_along_a_face_of_a_box_still_hits_it() raises:
    # A direction of zero along x with the origin on an x face gives a
    # stretch end that is not a number, and the other axes supply it.
    # Entry not a number, on the near face:
    assert_hit(along(0, -1, 0.5, 0, 1, 0).intersect_box(unit_box()), 0, 0, 0.5)
    # Exit not a number, on the far face:
    assert_hit(along(1, -1, 0.5, 0, 1, 0).intersect_box(unit_box()), 1, 0, 0.5)
    # Both the x and y stretches not numbers, so z settles the entry:
    assert_hit(along(0, 0, -1, 0, 0, 1).intersect_box(unit_box()), 0, 0, 0)
    # And the exit:
    assert_hit(along(1, 1, -1, 0, 0, 1).intersect_box(unit_box()), 1, 1, 0)
    # The z stretch not a number, with y already settled:
    assert_hit(along(0.5, -1, 0, 0, 1, 0).intersect_box(unit_box()), 0.5, 0, 0)


def test_the_empty_box_is_hit_nowhere() raises:
    assert_miss(along(-2, 0.5, 0.5, 1, 0, 0).intersect_box(Box3.empty()))
    assert_false(along(-2, 0.5, 0.5, 1, 0, 0).intersects_box(Box3.empty()))


# --- triangles ---------------------------------------------------------------


def corner_a() -> Vector3:
    """Return the first corner of the test triangle, at the origin."""
    return Vector3(0, 0, 0)


def corner_b() -> Vector3:
    """Return the second corner, along x."""
    return Vector3(1, 0, 0)


def corner_c() -> Vector3:
    """Return the third corner, along y, so the triangle faces +z."""
    return Vector3(0, 1, 0)


def test_a_triangle_is_hit_from_its_front() raises:
    var ray = along(0.25, 0.25, 1, 0, 0, -1)
    assert_hit(
        ray.intersect_triangle(corner_a(), corner_b(), corner_c(), True),
        0.25,
        0.25,
        0,
    )
    assert_hit(
        ray.intersect_triangle(corner_a(), corner_b(), corner_c(), False),
        0.25,
        0.25,
        0,
    )


def test_a_hit_from_behind_counts_only_without_culling() raises:
    var ray = along(0.25, 0.25, -1, 0, 0, 1)
    assert_miss(
        ray.intersect_triangle(corner_a(), corner_b(), corner_c(), True)
    )
    assert_hit(
        ray.intersect_triangle(corner_a(), corner_b(), corner_c(), False),
        0.25,
        0.25,
        0,
    )


def test_a_ray_in_the_triangles_plane_misses_it() raises:
    var ray = along(-1, 0.25, 0, 1, 0, 0)
    assert_miss(
        ray.intersect_triangle(corner_a(), corner_b(), corner_c(), False)
    )
    # A degenerate triangle has no plane to be in.
    assert_miss(
        along(0, 0, 1, 0, 0, -1).intersect_triangle(
            corner_a(), corner_a(), corner_a(), False
        )
    )


def test_a_ray_past_any_edge_of_a_triangle_misses_it() raises:
    # Past the edge from a to c, which the first edge test guards.
    assert_miss(
        along(-0.5, 0.25, 1, 0, 0, -1).intersect_triangle(
            corner_a(), corner_b(), corner_c(), True
        )
    )
    # Past the edge from a to b, the second.
    assert_miss(
        along(0.25, -0.5, 1, 0, 0, -1).intersect_triangle(
            corner_a(), corner_b(), corner_c(), True
        )
    )
    # Past the edge from b to c, the sum.
    assert_miss(
        along(0.75, 0.75, 1, 0, 0, -1).intersect_triangle(
            corner_a(), corner_b(), corner_c(), True
        )
    )


def test_a_triangle_behind_the_origin_is_missed() raises:
    # Pointing away from the triangle, though inside its outline.
    assert_miss(
        along(0.25, 0.25, -1, 0, 0, -1).intersect_triangle(
            corner_a(), corner_b(), corner_c(), False
        )
    )


# --- transforms --------------------------------------------------------------


def test_a_transform_moves_the_origin_and_turns_the_direction() raises:
    var ray = along(0, 0, 0, 1, 0, 0)
    ray.apply_matrix4(translation(1, 2, 3))
    assert_point(ray.origin, 1, 2, 3)
    assert_point(ray.direction, 1, 0, 0)
    ray.apply_matrix4(rotation_z(Angle(90.0, DEGREE)))
    assert_point(ray.origin, -2, 1, 3)
    assert_point(ray.direction, 0, 1, 0)


def test_a_scaled_direction_is_made_unit_again() raises:
    var ray = along(0, 0, 0, 1, 1, 0)
    ray.apply_matrix4(scaling(3, 1, 1))
    assert_point(ray.direction, 0.9486833, 0.31622777, 0)


def test_a_ray_refuses_a_projection_and_a_flattening() raises:
    var ray = along(0, 0, 0, 1, 0, 0)
    with assert_raises():
        ray.apply_matrix4(perspective(-1, 1, 1, -1, 1, 10))
    with assert_raises():
        ray.apply_matrix4(scaling(0, 1, 1))
    # Neither touched it.
    assert_point(ray.origin, 0, 0, 0)
    assert_point(ray.direction, 1, 0, 0)


def _approach(start: Vector3, end: Vector3) raises -> SegmentApproach:
    """Return a ray from the origin down -z against a segment."""
    return Ray(Vector3(0, 0, 0), Vector3(0, 0, -1)).distance_sq_to_segment(
        start, end
    )


def test_a_segment_across_the_ray_meets_it_between_its_ends() raises:
    var met = _approach(Vector3(-1, 1, -5), Vector3(1, 1, -5))
    assert_almost_equal(met.distance_sq, Float32(1), atol=1e-5)
    assert_almost_equal(met.on_ray.z, Float32(-5), atol=1e-5)
    assert_almost_equal(met.on_segment.y, Float32(1), atol=1e-5)
    assert_almost_equal(met.on_segment.x, Float32(0), atol=1e-5)


def test_a_segment_to_one_side_is_met_at_its_nearer_end() raises:
    # Either way round, ahead of the origin: the end at x = 1.
    for flip in range(2):
        var a = Vector3(1, 1, -5)
        var b = Vector3(3, 1, -5)
        var met = _approach(a, b) if flip == 0 else _approach(b, a)
        assert_almost_equal(met.distance_sq, Float32(2), atol=1e-5)
        assert_almost_equal(met.on_segment.x, Float32(1), atol=1e-5)
        assert_almost_equal(met.on_ray.z, Float32(-5), atol=1e-5)


def test_a_segment_behind_the_origin_is_met_from_the_origin() raises:
    var across = _approach(Vector3(-1, 1, 5), Vector3(1, 1, 5))
    assert_almost_equal(across.distance_sq, Float32(26), atol=1e-4)
    assert_almost_equal(across.on_ray.z, Float32(0), atol=1e-5)
    for flip in range(2):
        var a = Vector3(1, 1, 5)
        var b = Vector3(3, 1, 5)
        var met = _approach(a, b) if flip == 0 else _approach(b, a)
        assert_almost_equal(met.distance_sq, Float32(27), atol=1e-4)
        assert_almost_equal(met.on_segment.x, Float32(1), atol=1e-5)
    # Behind and to one side, but reached along the ray's line past the
    # origin: the ray's end is still the origin.
    var side = _approach(Vector3(3, 1, 5), Vector3(3, 1, -5))
    assert_almost_equal(side.distance_sq, Float32(10), atol=1e-4)


def test_a_segment_parallel_to_the_ray_is_met_at_the_end_it_runs_to() raises:
    for flip in range(2):
        var a = Vector3(0, 1, -2)
        var b = Vector3(0, 1, -6)
        var met = _approach(a, b) if flip == 0 else _approach(b, a)
        assert_almost_equal(met.distance_sq, Float32(1), atol=1e-4)
        assert_almost_equal(met.on_segment.z, Float32(-6), atol=1e-4)
        assert_almost_equal(met.on_ray.z, Float32(-6), atol=1e-4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
