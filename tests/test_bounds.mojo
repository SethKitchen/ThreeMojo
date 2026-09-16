# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.bounds`."""

from math.bounds import Box3, Plane, Sphere
from math.matrix4 import Matrix4, rotation_z, scaling, translation
from math.vector3 import Vector3
from std.math import cos, pi, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
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


def unit_box() -> Box3:
    """Return the box from the origin to (1, 1, 1)."""
    return Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))


def three_points() -> List[Vector3]:
    """Return three points whose box runs from (-1, -2, 1) to (2, 2, 5)."""
    var points = List[Vector3]()
    points.append(Vector3(1, 2, 3))
    points.append(Vector3(-1, 0, 5))
    points.append(Vector3(2, -2, 1))
    return points^


# --- box --------------------------------------------------------------------


def test_the_empty_box_holds_nothing_and_takes_the_first_point_whole() raises:
    var box = Box3.empty()
    assert_true(box.is_empty())
    assert_false(box.contains_point(Vector3(0, 0, 0)))
    box.expand_by_point(Vector3(1, 2, 3))
    assert_false(box.is_empty())
    assert_point(box.min, 1, 2, 3)
    assert_point(box.max, 1, 2, 3)
    assert_true(box.contains_point(Vector3(1, 2, 3)))


def test_a_box_from_points_is_the_smallest_around_them() raises:
    var box = Box3.from_points(three_points())
    assert_point(box.min, -1, -2, 1)
    assert_point(box.max, 2, 2, 5)
    assert_point(box.center(), 0.5, 0, 3)
    assert_point(box.size(), 3, 4, 4)
    assert_true(Box3.from_points(List[Vector3]()).is_empty())


def test_a_box_is_empty_if_any_axis_is_inside_out() raises:
    # Each axis has to be able to say so on its own.
    assert_false(unit_box().is_empty())
    assert_true(Box3(Vector3(1, 0, 0), Vector3(0, 1, 1)).is_empty())
    assert_true(Box3(Vector3(0, 1, 0), Vector3(1, 0, 1)).is_empty())
    assert_true(Box3(Vector3(0, 0, 1), Vector3(1, 1, 0)).is_empty())
    # An empty box has no center and no size to speak of.
    assert_point(Box3.empty().center(), 0, 0, 0)
    assert_point(Box3.empty().size(), 0, 0, 0)


def test_a_box_contains_its_inside_and_its_faces_and_nothing_past_them() raises:
    var box = unit_box()
    assert_true(box.contains_point(Vector3(0.5, 0.5, 0.5)))
    assert_true(box.contains_point(Vector3(0, 1, 0)))
    # A step past each face, one face at a time.
    assert_false(box.contains_point(Vector3(-0.1, 0.5, 0.5)))
    assert_false(box.contains_point(Vector3(1.1, 0.5, 0.5)))
    assert_false(box.contains_point(Vector3(0.5, -0.1, 0.5)))
    assert_false(box.contains_point(Vector3(0.5, 1.1, 0.5)))
    assert_false(box.contains_point(Vector3(0.5, 0.5, -0.1)))
    assert_false(box.contains_point(Vector3(0.5, 0.5, 1.1)))


def test_the_nearest_point_of_a_box_is_the_point_itself_or_its_surface() raises:
    var box = unit_box()
    assert_point(box.clamp_point(Vector3(0.5, 0.5, 0.5)), 0.5, 0.5, 0.5)
    assert_point(box.clamp_point(Vector3(2, -1, 0.5)), 1, 0, 0.5)
    assert_equal(box.distance_to_point(Vector3(0.5, 0.5, 0.5)), Float32(0))
    assert_almost_equal(
        box.distance_to_point(Vector3(4, 5, 0.5)), Float32(5), atol=TOLERANCE
    )


def test_boxes_intersect_unless_separated_along_some_axis() raises:
    var box = unit_box()
    assert_true(
        box.intersects_box(Box3(Vector3(0.5, 0.5, 0.5), Vector3(2, 2, 2)))
    )
    # Touching counts.
    assert_true(box.intersects_box(Box3(Vector3(1, 0, 0), Vector3(2, 1, 1))))
    # Separated on each side of each axis, one side at a time.
    assert_false(box.intersects_box(Box3(Vector3(-2, 0, 0), Vector3(-1, 1, 1))))
    assert_false(box.intersects_box(Box3(Vector3(2, 0, 0), Vector3(3, 1, 1))))
    assert_false(box.intersects_box(Box3(Vector3(0, -2, 0), Vector3(1, -1, 1))))
    assert_false(box.intersects_box(Box3(Vector3(0, 2, 0), Vector3(1, 3, 1))))
    assert_false(box.intersects_box(Box3(Vector3(0, 0, -2), Vector3(1, 1, -1))))
    assert_false(box.intersects_box(Box3(Vector3(0, 0, 2), Vector3(1, 1, 3))))


def test_a_union_takes_in_the_other_box_and_ignores_an_empty_one() raises:
    var box = unit_box()
    box.union(Box3(Vector3(-1, 2, 0.5), Vector3(0.5, 3, 0.5)))
    assert_point(box.min, -1, 0, 0)
    assert_point(box.max, 1, 3, 1)
    box.union(Box3.empty())
    assert_point(box.min, -1, 0, 0)
    assert_point(box.max, 1, 3, 1)


def test_a_box_and_a_sphere_intersect_by_the_nearest_point() raises:
    var box = unit_box()
    assert_true(box.intersects_sphere(Sphere(Vector3(2, 0.5, 0.5), 1.0)))
    assert_false(box.intersects_sphere(Sphere(Vector3(2, 0.5, 0.5), 0.9)))
    assert_true(box.intersects_sphere(Sphere(Vector3(0.5, 0.5, 0.5), 0.1)))
    assert_true(Sphere(Vector3(2, 0.5, 0.5), 1.0).intersects_box(box))
    assert_false(Sphere(Vector3(2, 0.5, 0.5), 0.9).intersects_box(box))


def test_a_transformed_box_bounds_its_transformed_corners() raises:
    # A cube turned an eighth of a turn about z: its shadow on x and on y
    # grows to the diagonal, and z is untouched.
    var box = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
    box.apply_matrix4(rotation_z(Angle(45.0, DEGREE)))
    var diagonal = Float32(1.41421356)
    assert_almost_equal(box.max.x, diagonal, atol=TOLERANCE)
    assert_almost_equal(box.min.x, -diagonal, atol=TOLERANCE)
    assert_almost_equal(box.max.y, diagonal, atol=TOLERANCE)
    assert_almost_equal(box.max.z, Float32(1), atol=TOLERANCE)
    # Moved, it moves; empty, it stays empty rather than becoming nonsense.
    var moved = unit_box()
    moved.apply_matrix4(translation(5, 0, 0))
    assert_point(moved.min, 5, 0, 0)
    assert_point(moved.max, 6, 1, 1)
    var nothing = Box3.empty()
    nothing.apply_matrix4(translation(5, 0, 0))
    assert_true(nothing.is_empty())


def test_a_boxs_sphere_reaches_its_corners() raises:
    var sphere = unit_box().bounding_sphere()
    assert_point(sphere.center, 0.5, 0.5, 0.5)
    assert_almost_equal(sphere.radius, Float32(0.8660254), atol=TOLERANCE)
    assert_true(sphere.contains_point(Vector3(1, 1, 1)))
    assert_true(Box3.empty().bounding_sphere().is_empty())


# --- sphere -----------------------------------------------------------------


def test_the_empty_sphere_holds_nothing_and_takes_the_first_point_whole() raises:
    var sphere = Sphere.empty()
    assert_true(sphere.is_empty())
    assert_false(sphere.contains_point(Vector3(0, 0, 0)))
    sphere.expand_by_point(Vector3(1, 2, 3))
    assert_false(sphere.is_empty())
    assert_point(sphere.center, 1, 2, 3)
    assert_equal(sphere.radius, Float32(0))
    assert_true(sphere.contains_point(Vector3(1, 2, 3)))


def test_a_sphere_grows_toward_a_point_outside_and_not_for_one_inside() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    sphere.expand_by_point(Vector3(0.5, 0, 0))
    assert_equal(sphere.radius, Float32(1))
    assert_point(sphere.center, 0, 0, 0)
    # Three away: the sphere moves one toward it and grows by one, so it
    # still holds the far side it held before.
    sphere.expand_by_point(Vector3(3, 0, 0))
    assert_almost_equal(sphere.radius, Float32(2), atol=TOLERANCE)
    assert_point(sphere.center, 1, 0, 0)
    assert_true(sphere.contains_point(Vector3(3, 0, 0)))
    assert_true(sphere.contains_point(Vector3(-1, 0, 0)))


def test_a_sphere_from_points_is_centered_on_their_box() raises:
    # Three points and a fourth near the middle, which changes neither the
    # box nor the radius: only the farthest point sets that.
    var points = three_points()
    points.append(Vector3(0.5, 0.5, 3))
    var sphere = Sphere.from_points(points)
    assert_point(sphere.center, 0.5, 0, 3)
    # The farthest point sets the radius: (2, -2, 1) at the root of 10.25.
    assert_almost_equal(sphere.radius, Float32(3.2015621), atol=TOLERANCE)
    for point in points:
        assert_true(sphere.contains_point(point))
    assert_true(Sphere.from_points(List[Vector3]()).is_empty())


def test_a_spheres_distance_is_signed_from_its_surface() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 2)
    assert_almost_equal(
        sphere.distance_to_point(Vector3(5, 0, 0)), Float32(3), atol=TOLERANCE
    )
    assert_almost_equal(
        sphere.distance_to_point(Vector3(1, 0, 0)), Float32(-1), atol=TOLERANCE
    )
    assert_almost_equal(
        sphere.distance_to_point(Vector3(0, 2, 0)), Float32(0), atol=TOLERANCE
    )
    assert_true(sphere.contains_point(Vector3(0, 2, 0)))
    assert_false(sphere.contains_point(Vector3(0, 2.1, 0)))


def test_spheres_intersect_when_their_centers_are_within_both_radii() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    assert_true(sphere.intersects_sphere(Sphere(Vector3(2, 0, 0), 1)))
    assert_false(sphere.intersects_sphere(Sphere(Vector3(2.1, 0, 0), 1)))
    assert_true(sphere.intersects_sphere(Sphere(Vector3(0.5, 0, 0), 0.1)))


def test_a_transformed_sphere_grows_by_the_largest_scale() raises:
    var sphere = Sphere(Vector3(1, 0, 0), 1)
    var stretch = translation(0, 5, 0)
    stretch.multiply(scaling(1, 3, 2))
    sphere.apply_matrix4(stretch)
    assert_point(sphere.center, 1, 5, 0)
    assert_almost_equal(sphere.radius, Float32(3), atol=TOLERANCE)


def test_a_spheres_box_reaches_its_radius() raises:
    var box = Sphere(Vector3(1, 2, 3), 2).bounding_box()
    assert_point(box.min, -1, 0, 1)
    assert_point(box.max, 3, 4, 5)
    assert_true(Sphere.empty().bounding_box().is_empty())


def test_a_transformed_sphere_still_holds_its_transformed_points() raises:
    # A scale of (2, 1, 1) above a turn of 45 degrees: the diagonal of the
    # unit sphere stretches to two while no axis is longer than 1.58, so a
    # sphere grown by the longest axis, as three.js grows it, misses the
    # point (1, -1, 0) / root 2, which lands at (2, 0, 0). This one grows
    # by a bound on the stretch and holds every point it held.
    var sheared = scaling(2, 1, 1)
    sheared.multiply(rotation_z(Angle(45.0, DEGREE)))
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    sphere.apply_matrix4(sheared)
    assert_almost_equal(sphere.radius, Float32(2), atol=Float64(1e-4))
    var corner = sheared.transform_point(Vector3(0.70710678, -0.70710678, 0))
    assert_point(corner, 2, 0, 0)
    assert_true(sphere.contains_point(corner))
    # And all the way round the equator and the meridians.
    for step in range(36):
        var angle = Float32(step) / 36 * 2 * Float32(pi)
        var on_equator = Vector3(cos(angle), sin(angle), 0)
        var on_meridian = Vector3(cos(angle), 0, sin(angle))
        assert_true(sphere.contains_point(sheared.transform_point(on_equator)))
        assert_true(sphere.contains_point(sheared.transform_point(on_meridian)))


def test_a_transformed_sphere_survives_extreme_scales() raises:
    # A huge sphere scaled down to a meter, and a tiny one scaled up: the
    # stretch is worked in Float64, so neither radius is lost on the way.
    var huge = Sphere(Vector3(0, 0, 0), 1e25)
    huge.apply_matrix4(scaling(1e-25, 1e-25, 1e-25))
    assert_almost_equal(huge.radius, Float32(1), atol=Float64(1e-4))
    var tiny = Sphere(Vector3(0, 0, 0), 1e-20)
    tiny.apply_matrix4(scaling(1e20, 1e20, 1e20))
    assert_almost_equal(tiny.radius, Float32(1), atol=Float64(1e-4))


def test_an_empty_sphere_meets_nothing_and_stays_empty() raises:
    # The sum of an empty sphere's radius and a real one's is positive, so
    # the plain test would say they meet; asked outright, they do not.
    var empty = Sphere.empty()
    var solid = Sphere(Vector3(0, 0, 0), 2)
    assert_false(empty.intersects_sphere(solid))
    assert_false(solid.intersects_sphere(empty))
    assert_false(empty.intersects_box(unit_box()))
    assert_false(unit_box().intersects_sphere(empty))
    assert_false(Plane(Vector3(0, 0, 1), 0).intersects_sphere(empty))
    # A scale of zero would turn its radius into minus zero, which is not
    # negative; transformed, it stays empty instead.
    empty.apply_matrix4(scaling(0, 0, 0))
    assert_true(empty.is_empty())
    empty.apply_matrix4(translation(5, 0, 0))
    assert_true(empty.is_empty())


def test_a_finite_inside_out_box_is_as_empty_as_the_empty_box() raises:
    # Inside out on x alone, with finite corners a plain comparison would
    # take for a real box.
    var inverted = Box3(Vector3(3, 8, 8), Vector3(2, 9, 9))
    assert_true(inverted.is_empty())
    var big = Box3(Vector3(-10, -10, -10), Vector3(10, 10, 10))
    assert_false(inverted.intersects_box(big))
    assert_false(big.intersects_box(inverted))
    assert_false(inverted.intersects_sphere(Sphere(Vector3(2.5, 8.5, 8.5), 5)))
    assert_false(Plane(Vector3(0, 0, 1), -8.5).intersects_box(inverted))
    assert_true(inverted.bounding_sphere().is_empty())
    # Taking it into a box changes nothing; taking a box into it makes it
    # that box.
    var box = unit_box()
    box.union(inverted)
    assert_point(box.min, 0, 0, 0)
    assert_point(box.max, 1, 1, 1)
    var grown = inverted
    grown.union(unit_box())
    assert_point(grown.min, 0, 0, 0)
    assert_point(grown.max, 1, 1, 1)
    # Expanded by a point it is the box of that point, not of the point
    # and its stale corners.
    var one = inverted
    one.expand_by_point(Vector3(0, 0, 0))
    assert_point(one.min, 0, 0, 0)
    assert_point(one.max, 0, 0, 0)
    # And a transform leaves it empty.
    var moved = inverted
    moved.apply_matrix4(translation(5, 0, 0))
    assert_true(moved.is_empty())


def test_an_empty_bound_has_no_nearest_point() raises:
    with assert_raises():
        _ = Box3.empty().clamp_point(Vector3(1, 1, 1))
    with assert_raises():
        _ = Box3(Vector3(3, 8, 8), Vector3(2, 9, 9)).distance_to_point(
            Vector3(1, 1, 1)
        )
    with assert_raises():
        _ = Sphere.empty().distance_to_point(Vector3(1, 1, 1))
    with assert_raises():
        _ = Plane(Vector3(0, 0, 1), 0).distance_to_sphere(Sphere.empty())


def test_a_projection_cannot_carry_a_bound() raises:
    # A corner crossing w = 0 has no finite image, so a matrix with a
    # bottom row that is not (0, 0, 0, 1) is refused by both bounds.
    var projecting = Matrix4()
    projecting.put(3, 2, -1)
    var box = unit_box()
    with assert_raises():
        box.apply_matrix4(projecting)
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    with assert_raises():
        sphere.apply_matrix4(projecting)


# --- plane ------------------------------------------------------------------


def test_a_plane_normalizes_what_it_is_given() raises:
    # A normal of (0, 0, 2) and a constant of -4 is the plane z = 2, and
    # stays that plane once the normal is unit length.
    var plane = Plane(Vector3(0, 0, 2), -4)
    assert_point(plane.normal, 0, 0, 1)
    assert_almost_equal(plane.constant, Float32(-2), atol=TOLERANCE)
    assert_almost_equal(
        plane.distance_to_point(Vector3(0, 0, 5)), Float32(3), atol=TOLERANCE
    )
    assert_almost_equal(
        plane.distance_to_point(Vector3(0, 0, 0)), Float32(-2), atol=TOLERANCE
    )
    with assert_raises():
        _ = Plane(Vector3(0, 0, 0), 1)


def test_a_plane_through_a_point_passes_through_it() raises:
    var plane = Plane.from_normal_and_point(Vector3(0, 3, 0), Vector3(1, 2, 3))
    assert_almost_equal(
        plane.distance_to_point(Vector3(1, 2, 3)), Float32(0), atol=TOLERANCE
    )
    assert_almost_equal(
        plane.distance_to_point(Vector3(0, 5, 0)), Float32(3), atol=TOLERANCE
    )
    assert_point(plane.coplanar_point(), 0, 2, 0)
    with assert_raises():
        _ = Plane.from_normal_and_point(Vector3(0, 0, 0), Vector3(1, 2, 3))


def test_a_plane_through_three_points_faces_their_counter_clockwise_side() raises:
    # Three points counter-clockwise seen from +z: the plane faces +z.
    var plane = Plane.from_coplanar_points(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
    )
    assert_point(plane.normal, 0, 0, 1)
    assert_almost_equal(plane.constant, Float32(0), atol=TOLERANCE)
    assert_true(plane.distance_to_point(Vector3(0, 0, 1)) > 0)
    var lifted = Plane.from_coplanar_points(
        Vector3(0, 0, 2), Vector3(1, 0, 2), Vector3(0, 1, 2)
    )
    assert_almost_equal(
        lifted.distance_to_point(Vector3(5, 5, 2)), Float32(0), atol=TOLERANCE
    )
    with assert_raises():
        _ = Plane.from_coplanar_points(
            Vector3(0, 0, 0), Vector3(1, 1, 1), Vector3(2, 2, 2)
        )
    with assert_raises():
        _ = Plane.from_coplanar_points(
            Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)
        )


def test_a_point_projects_to_its_foot_on_the_plane() raises:
    var plane = Plane(Vector3(0, 0, 1), -2)
    assert_point(plane.project_point(Vector3(3, 4, 7)), 3, 4, 2)
    assert_point(plane.project_point(Vector3(3, 4, -1)), 3, 4, 2)


def test_negating_and_moving_a_plane() raises:
    var plane = Plane(Vector3(0, 0, 1), -2)
    plane.negate()
    assert_point(plane.normal, 0, 0, -1)
    assert_almost_equal(plane.constant, Float32(2), atol=TOLERANCE)
    assert_almost_equal(
        plane.distance_to_point(Vector3(0, 0, 5)), Float32(-3), atol=TOLERANCE
    )
    # Moved up by one it is z = 3, still facing down.
    plane.translate(Vector3(0, 0, 1))
    assert_almost_equal(
        plane.distance_to_point(Vector3(0, 0, 5)), Float32(-2), atol=TOLERANCE
    )
    assert_almost_equal(
        plane.distance_to_point(Vector3(0, 0, 3)), Float32(0), atol=TOLERANCE
    )


def test_a_plane_meets_a_sphere_that_reaches_it() raises:
    var plane = Plane(Vector3(0, 0, 1), -2)
    assert_true(plane.intersects_sphere(Sphere(Vector3(0, 0, 3), 1)))
    assert_false(plane.intersects_sphere(Sphere(Vector3(0, 0, 3), 0.9)))
    assert_true(plane.intersects_sphere(Sphere(Vector3(0, 0, 1), 1)))
    assert_almost_equal(
        plane.distance_to_sphere(Sphere(Vector3(0, 0, 5), 1)),
        Float32(2),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        plane.distance_to_sphere(Sphere(Vector3(0, 0, -5), 1)),
        Float32(-8),
        atol=TOLERANCE,
    )


def test_a_plane_meets_a_box_it_passes_through_whichever_way_it_faces() raises:
    var box = unit_box()
    # The same diagonal plane through the box's center, facing either way:
    # each sign of each component picks the other face of the box.
    assert_true(Plane(Vector3(1, 1, 1), -1.5).intersects_box(box))
    assert_true(Plane(Vector3(-1, -1, -1), 1.5).intersects_box(box))
    # Touching a corner counts; wholly behind or wholly in front does not.
    assert_true(Plane(Vector3(1, 1, 1), 0).intersects_box(box))
    assert_false(Plane(Vector3(1, 1, 1), 0.5).intersects_box(box))
    assert_false(Plane(Vector3(1, 1, 1), -4).intersects_box(box))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
