# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.frustum`."""

from math.bounds import Box3, Sphere
from math.frustum import BOTTOM, FAR, Frustum, LEFT, NEAR, RIGHT, TOP
from math.matrix4 import Matrix4, scaling
from math.projection import look_at, orthographic, perspective
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-5)


def assert_plane(
    frustum: Frustum,
    which: Int,
    x: Float32,
    y: Float32,
    z: Float32,
    constant: Float32,
) raises:
    """Assert one plane of a frustum has the given normal and constant.

    Args:
        frustum: The frustum.
        which: Which plane, by its index in `planes`.
        x: Expected normal x.
        y: Expected normal y.
        z: Expected normal z.
        constant: Expected constant.

    Raises:
        Error: If any component differs.
    """
    ref plane = frustum.planes[which]
    assert_almost_equal(plane.normal.x, x, atol=TOLERANCE)
    assert_almost_equal(plane.normal.y, y, atol=TOLERANCE)
    assert_almost_equal(plane.normal.z, z, atol=TOLERANCE)
    assert_almost_equal(plane.constant, constant, atol=TOLERANCE)


def cube_frustum() raises -> Frustum:
    """Return the frustum of the identity: the cube from -1 to 1."""
    return Frustum.from_projection_matrix(Matrix4())


def camera_frustum() raises -> Frustum:
    """Return a perspective frustum in camera space: a 90-degree field of
    view either way, from one meter to ten down -z."""
    return Frustum.from_projection_matrix(perspective(-1, 1, 1, -1, 1, 10))


def test_the_identity_sees_the_unit_cube() raises:
    # Each plane faces inward, one unit from the origin, in three.js's
    # order: right, left, bottom, top, far, near.
    var cube = cube_frustum()
    assert_plane(cube, RIGHT, -1, 0, 0, 1)
    assert_plane(cube, LEFT, 1, 0, 0, 1)
    assert_plane(cube, BOTTOM, 0, 1, 0, 1)
    assert_plane(cube, TOP, 0, -1, 0, 1)
    assert_plane(cube, FAR, 0, 0, -1, 1)
    assert_plane(cube, NEAR, 0, 0, 1, 1)


def test_a_point_is_in_view_inside_the_cube_and_on_its_faces() raises:
    var cube = cube_frustum()
    assert_true(cube.contains_point(Vector3(0, 0, 0)))
    assert_true(cube.contains_point(Vector3(1, 1, 1)))
    assert_true(cube.contains_point(Vector3(-1, -1, -1)))
    # A step past each face, one face at a time.
    assert_false(cube.contains_point(Vector3(1.1, 0, 0)))
    assert_false(cube.contains_point(Vector3(-1.1, 0, 0)))
    assert_false(cube.contains_point(Vector3(0, 1.1, 0)))
    assert_false(cube.contains_point(Vector3(0, -1.1, 0)))
    assert_false(cube.contains_point(Vector3(0, 0, 1.1)))
    assert_false(cube.contains_point(Vector3(0, 0, -1.1)))


def test_a_perspective_frustum_widens_with_depth() raises:
    # Half a meter wide at the near plane and five at the far one, so a
    # point four meters off the axis is in view at depth five and not at
    # depth two.
    var view = camera_frustum()
    assert_true(view.contains_point(Vector3(0, 0, -5)))
    assert_true(view.contains_point(Vector3(4, 0, -5)))
    assert_false(view.contains_point(Vector3(4, 0, -2)))
    assert_true(view.contains_point(Vector3(0, -4, -5)))
    assert_false(view.contains_point(Vector3(0, -4, -2)))
    # Nearer than the near plane, or beyond the far one.
    assert_false(view.contains_point(Vector3(0, 0, -0.5)))
    assert_false(view.contains_point(Vector3(0, 0, -11)))
    # Behind the camera altogether.
    assert_false(view.contains_point(Vector3(0, 0, 3)))
    # The near and far planes face along z, at the distances asked for.
    assert_plane(view, NEAR, 0, 0, -1, -1)
    assert_plane(view, FAR, 0, 0, 1, 10)


def test_an_orthographic_frustum_is_a_box() raises:
    var box = Frustum.from_projection_matrix(orthographic(-2, 2, 3, -3, 0, 10))
    assert_plane(box, RIGHT, -1, 0, 0, 2)
    assert_plane(box, LEFT, 1, 0, 0, 2)
    assert_plane(box, TOP, 0, -1, 0, 3)
    assert_plane(box, BOTTOM, 0, 1, 0, 3)
    assert_plane(box, NEAR, 0, 0, -1, 0)
    assert_plane(box, FAR, 0, 0, 1, 10)
    assert_true(box.contains_point(Vector3(1.9, -2.9, -9.9)))
    assert_false(box.contains_point(Vector3(2.1, 0, -5)))


def test_a_frustum_from_a_view_as_well_is_in_world_space() raises:
    # A camera at (0, 0, 4) looking at the origin sees the origin and not
    # what is behind it.
    var clip = perspective(-1, 1, 1, -1, 1, 10)
    clip.multiply(look_at(Vector3(0, 0, 4), Vector3(0, 0, 0), Vector3(0, 1, 0)))
    var view = Frustum.from_projection_matrix(clip)
    assert_true(view.contains_point(Vector3(0, 0, 0)))
    assert_true(view.contains_point(Vector3(0, 0, -5)))
    assert_false(view.contains_point(Vector3(0, 0, 5)))
    assert_false(view.contains_point(Vector3(0, 0, 3.5)))
    assert_false(view.contains_point(Vector3(0, 0, -7)))


def test_a_sphere_is_in_view_until_a_plane_has_all_of_it_behind() raises:
    var view = camera_frustum()
    assert_true(view.intersects_sphere(Sphere(Vector3(0, 0, -5), 1)))
    # The right plane passes through (5, 0, -5) at 45 degrees, so a sphere
    # centered a meter past it in x is 0.707 behind: in view with a radius
    # of one, out with a radius of half.
    assert_true(view.intersects_sphere(Sphere(Vector3(6, 0, -5), 1)))
    assert_false(view.intersects_sphere(Sphere(Vector3(6, 0, -5), 0.5)))
    # A sphere wholly beyond the far plane, and one wholly before the near.
    assert_false(view.intersects_sphere(Sphere(Vector3(0, 0, -12), 1)))
    assert_true(view.intersects_sphere(Sphere(Vector3(0, 0, -10.5), 1)))
    assert_false(view.intersects_sphere(Sphere(Vector3(0, 0, 0.5), 1)))
    # Touching a plane from behind counts, as it does for a point.
    assert_true(view.intersects_sphere(Sphere(Vector3(0, 0, 0), 1)))
    # An empty sphere holds nothing, so nothing of it is in view, whatever
    # a negative radius would say to the arithmetic.
    assert_false(view.intersects_sphere(Sphere.empty()))
    assert_false(view.intersects_sphere(Sphere(Vector3(0, 0, -5), -1)))


def test_a_box_is_in_view_until_a_plane_has_all_of_it_behind() raises:
    var cube = cube_frustum()
    assert_true(
        cube.intersects_box(
            Box3(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5))
        )
    )
    # Straddling a face, and touching one from outside, both count.
    assert_true(
        cube.intersects_box(Box3(Vector3(0.5, 0.5, 0.5), Vector3(2, 2, 2)))
    )
    assert_true(
        cube.intersects_box(Box3(Vector3(1, -0.5, -0.5), Vector3(2, 0.5, 0.5)))
    )
    # Wholly past each face, one face at a time.
    assert_false(
        cube.intersects_box(
            Box3(Vector3(1.1, -0.5, -0.5), Vector3(2, 0.5, 0.5))
        )
    )
    assert_false(
        cube.intersects_box(
            Box3(Vector3(-2, -0.5, -0.5), Vector3(-1.1, 0.5, 0.5))
        )
    )
    assert_false(
        cube.intersects_box(
            Box3(Vector3(-0.5, 1.1, -0.5), Vector3(0.5, 2, 0.5))
        )
    )
    assert_false(
        cube.intersects_box(
            Box3(Vector3(-0.5, -2, -0.5), Vector3(0.5, -1.1, 0.5))
        )
    )
    assert_false(
        cube.intersects_box(
            Box3(Vector3(-0.5, -0.5, 1.1), Vector3(0.5, 0.5, 2))
        )
    )
    assert_false(
        cube.intersects_box(
            Box3(Vector3(-0.5, -0.5, -2), Vector3(0.5, 0.5, -1.1))
        )
    )
    # A box larger than the whole view is in view.
    assert_true(
        cube.intersects_box(Box3(Vector3(-5, -5, -5), Vector3(5, 5, 5)))
    )
    # An empty box holds nothing.
    assert_false(cube.intersects_box(Box3.empty()))


def test_a_box_is_tested_by_the_corner_nearest_each_tilted_plane() raises:
    # In a perspective frustum the side planes are tilted, so the deciding
    # corner is the one furthest toward the axis and deepest: a box past
    # the right plane at its near face can still reach in at its far one.
    var view = camera_frustum()
    assert_true(
        view.intersects_box(Box3(Vector3(3, -1, -6), Vector3(5, 1, -2)))
    )
    assert_false(
        view.intersects_box(Box3(Vector3(3, -1, -2.5), Vector3(5, 1, -2)))
    )


def test_a_matrix_that_describes_no_volume_is_refused() raises:
    # A scale of zero leaves the bottom row alone and empties the others,
    # so the right plane has no normal.
    with assert_raises():
        _ = Frustum.from_projection_matrix(scaling(0, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
