# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.projection`."""

from math.projection import look_at, perspective, viewport
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)

# Rotations and divides rarely land on exact zeros, and a relative tolerance
# cannot be satisfied against an expected zero.
comptime TOLERANCE = Float64(1e-5)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance.

    Args:
        got: The point to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.

    Raises:
        Error: If any component differs.
    """
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


# --- perspective ------------------------------------------------------------


def test_near_plane_center_maps_to_minus_one_depth() raises:
    var m = perspective(-1, 1, 1, -1, 1, 100)
    assert_point(m.transform_point(Vector3(0, 0, -1)), 0, 0, -1)


def test_far_plane_center_maps_to_plus_one_depth() raises:
    var m = perspective(-1, 1, 1, -1, 1, 100)
    assert_point(m.transform_point(Vector3(0, 0, -100)), 0, 0, 1)


def test_frustum_corners_map_to_the_ndc_cube() raises:
    # The frustum edges at the near plane are its corners in NDC.
    var m = perspective(-1, 1, 1, -1, 1, 100)
    assert_point(m.transform_point(Vector3(1, 1, -1)), 1, 1, -1)
    assert_point(m.transform_point(Vector3(-1, -1, -1)), -1, -1, -1)


def test_the_frustum_widens_with_distance() raises:
    # At twice the near distance the frustum is twice as wide, so a point
    # twice as far out still lands on the same NDC edge.
    var m = perspective(-1, 1, 1, -1, 1, 100)
    assert_almost_equal(
        m.transform_point(Vector3(2, 0, -2)).x, Float32(1), atol=TOLERANCE
    )


def test_distant_things_appear_smaller() raises:
    var m = perspective(-1, 1, 1, -1, 1, 100)
    var near = m.transform_point(Vector3(1, 0, -2))
    var far = m.transform_point(Vector3(1, 0, -20))
    assert_true(abs(far.x) < abs(near.x))


def test_an_off_center_frustum_shifts_the_axis() raises:
    # Shifting both edges right moves what counts as the center of the image.
    var m = perspective(0, 2, 1, -1, 1, 100)
    assert_almost_equal(
        m.transform_point(Vector3(1, 0, -1)).x, Float32(0), atol=TOLERANCE
    )


def test_a_near_plane_behind_the_camera_is_rejected() raises:
    with assert_raises():
        _ = perspective(-1, 1, 1, -1, 0, 100)
    with assert_raises():
        _ = perspective(-1, 1, 1, -1, -1, 100)


def test_a_far_plane_not_beyond_near_is_rejected() raises:
    with assert_raises():
        _ = perspective(-1, 1, 1, -1, 10, 10)
    with assert_raises():
        _ = perspective(-1, 1, 1, -1, 10, 1)


def test_a_frustum_with_no_width_or_height_is_rejected() raises:
    with assert_raises():
        _ = perspective(1, 1, 1, -1, 1, 100)
    with assert_raises():
        _ = perspective(-1, 1, 1, 1, 1, 100)


# --- look_at ----------------------------------------------------------------


def test_a_camera_at_the_origin_looking_down_minus_z_changes_nothing() raises:
    # The default orientation is already camera space.
    var m = look_at(Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
    assert_point(m.transform_point(Vector3(1, 2, -3)), 1, 2, -3)


def test_the_camera_position_maps_to_the_origin() raises:
    var m = look_at(Vector3(5, 6, 7), Vector3(0, 0, 0), Vector3(0, 1, 0))
    assert_point(m.transform_point(Vector3(5, 6, 7)), 0, 0, 0)


def test_the_target_lies_straight_ahead_on_minus_z() raises:
    # Whatever the camera is looking at must sit on the -z axis, at the
    # distance between them.
    var m = look_at(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0))
    assert_point(m.transform_point(Vector3(0, 0, 0)), 0, 0, -10)


def test_looking_along_an_axis_from_the_side() raises:
    var m = look_at(Vector3(10, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0))
    assert_point(m.transform_point(Vector3(0, 0, 0)), 0, 0, -10)
    # World +y is still up in camera space.
    assert_point(m.transform_point(Vector3(10, 1, 0)), 0, 1, 0)


def test_up_need_not_be_perpendicular() raises:
    # It only has to be non-parallel; the basis is built by cross products.
    var m = look_at(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0.3, 1, 0))
    assert_point(m.transform_point(Vector3(0, 0, 0)), 0, 0, -10)


def test_a_camera_at_its_own_target_is_rejected() raises:
    with assert_raises():
        _ = look_at(Vector3(1, 2, 3), Vector3(1, 2, 3), Vector3(0, 1, 0))


def test_up_parallel_to_the_view_direction_is_rejected() raises:
    # Looking straight down with up also pointing down leaves no sideways.
    with assert_raises():
        _ = look_at(Vector3(0, 10, 0), Vector3(0, 0, 0), Vector3(0, 1, 0))


# --- viewport ---------------------------------------------------------------


def test_ndc_center_maps_to_the_image_center() raises:
    assert_point(
        viewport(200, 100).transform_point(Vector3(0, 0, 0)), 100, 50, 0
    )


def test_ndc_corners_map_to_the_image_corners() raises:
    var m = viewport(200, 100)
    # NDC y is up, image y is down, so -1 becomes the bottom.
    assert_point(m.transform_point(Vector3(-1, 1, 0)), 0, 0, 0)
    assert_point(m.transform_point(Vector3(1, -1, 0)), 200, 100, 0)


def test_the_y_axis_is_flipped() raises:
    # Getting this wrong renders the whole scene upside down.
    var m = viewport(100, 100)
    var high = m.transform_point(Vector3(0, 0.5, 0))
    var low = m.transform_point(Vector3(0, -0.5, 0))
    assert_true(high.y < low.y)


def test_depth_passes_through_the_viewport_unchanged() raises:
    assert_almost_equal(
        viewport(64, 64).transform_point(Vector3(0, 0, 0.25)).z,
        Float32(0.25),
        atol=TOLERANCE,
    )


def test_a_viewport_with_no_area_is_rejected() raises:
    with assert_raises():
        _ = viewport(0, 100)
    with assert_raises():
        _ = viewport(100, 0)
    with assert_raises():
        _ = viewport(-1, 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
