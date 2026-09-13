# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `cameras.perspective_camera`.

Most of these pick numbers that make the arithmetic checkable by hand. A
vertical field of view of 90 degrees means the visible half-height equals the
distance, so a point 5 m away and 5 m up sits exactly on the top edge of the
image — no tolerance-fudging required to see whether it is right.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, FOOT, Length, METRE, RADIAN

comptime TOLERANCE = Float64(1e-4)


def square_camera() raises -> PerspectiveCamera:
    """Return a 90-degree square camera 5 m back from the origin.

    Returns:
        A camera whose geometry is easy to check by hand.

    Raises:
        Error: If the camera parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(1.0, METRE), Length(100.0, METRE)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def test_the_origin_projects_to_the_image_centre() raises:
    var point = square_camera().project(Vector3(0, 0, 0), 200, 200)
    assert_almost_equal(point.x, Float32(100), atol=TOLERANCE)
    assert_almost_equal(point.y, Float32(100), atol=TOLERANCE)


def test_a_ninety_degree_fov_makes_half_height_equal_distance() raises:
    # 5 m away and 5 m up lands exactly on the top edge.
    var camera = square_camera()
    assert_almost_equal(
        camera.project(Vector3(0, 5, 0), 200, 200).y, Float32(0), atol=TOLERANCE
    )
    assert_almost_equal(
        camera.project(Vector3(0, -5, 0), 200, 200).y,
        Float32(200),
        atol=TOLERANCE,
    )


def test_the_horizontal_edge_follows_the_aspect_ratio() raises:
    var camera = square_camera()
    assert_almost_equal(
        camera.project(Vector3(5, 0, 0), 200, 200).x,
        Float32(200),
        atol=TOLERANCE,
    )


def test_a_wider_aspect_ratio_fits_more_in_horizontally() raises:
    # Same point, wider camera: it lands closer to the middle.
    var square = square_camera()
    var wide = PerspectiveCamera(
        Angle(90.0, DEGREE), 2.0, Length(1.0, METRE), Length(100.0, METRE)
    )
    wide.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var from_square = square.project(Vector3(2, 0, 0), 200, 200).x - 100
    var from_wide = wide.project(Vector3(2, 0, 0), 200, 200).x - 100
    assert_true(abs(from_wide) < abs(from_square))


def test_a_wider_field_of_view_shrinks_what_is_on_screen() raises:
    var narrow = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(1.0, METRE), Length(100.0, METRE)
    )
    narrow.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var wide = square_camera()
    var narrow_y = narrow.project(Vector3(0, 1, 0), 200, 200).y - 100
    var wide_y = wide.project(Vector3(0, 1, 0), 200, 200).y - 100
    assert_true(abs(wide_y) < abs(narrow_y))


def test_distant_points_move_towards_the_centre() raises:
    var camera = square_camera()
    var near = camera.project(Vector3(1, 0, 0), 200, 200)
    var far = camera.project(Vector3(1, 0, -10), 200, 200)
    assert_true(abs(far.x - 100) < abs(near.x - 100))


def test_depth_is_minus_one_at_the_near_plane() raises:
    # The camera sits at z = 5 with a 1 m near plane, so z = 4 is on it.
    assert_almost_equal(
        square_camera().project(Vector3(0, 0, 4), 200, 200).z,
        Float32(-1),
        atol=TOLERANCE,
    )


def test_depth_is_plus_one_at_the_far_plane() raises:
    assert_almost_equal(
        square_camera().project(Vector3(0, 0, -95), 200, 200).z,
        Float32(1),
        atol=TOLERANCE,
    )


def test_depth_increases_with_distance() raises:
    var camera = square_camera()
    var closer = camera.project(Vector3(0, 0, 0), 200, 200).z
    var further = camera.project(Vector3(0, 0, -20), 200, 200).z
    assert_true(closer < further)


def test_moving_the_camera_moves_the_view() raises:
    var camera = square_camera()
    camera.place(Vector3(2, 0, 5), Vector3(2, 0, 0))
    # The new target is what sits at the centre now.
    var point = camera.project(Vector3(2, 0, 0), 200, 200)
    assert_almost_equal(point.x, Float32(100), atol=TOLERANCE)


def test_looking_from_the_side() raises:
    var camera = square_camera()
    camera.place(Vector3(5, 0, 0), Vector3(0, 0, 0))
    var point = camera.project(Vector3(0, 0, 0), 200, 200)
    assert_almost_equal(point.x, Float32(100), atol=TOLERANCE)
    assert_almost_equal(point.y, Float32(100), atol=TOLERANCE)


def test_degrees_and_radians_describe_the_same_camera() raises:
    var from_degrees = square_camera()
    var from_radians = PerspectiveCamera(
        Angle(1.5707963, RADIAN), 1.0, Length(1.0, METRE), Length(100.0, METRE)
    )
    from_radians.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    assert_almost_equal(
        from_degrees.project(Vector3(1, 2, 0), 200, 200).x,
        from_radians.project(Vector3(1, 2, 0), 200, 200).x,
        atol=TOLERANCE,
    )


def test_feet_and_metres_describe_the_same_clipping_planes() raises:
    # A camera specified in feet must behave identically.
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE),
        1.0,
        Length(1.0, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var same = PerspectiveCamera(
        Angle(90.0, DEGREE),
        1.0,
        Length(3.2808399, FOOT),
        Length(100.0, METRE),
    )
    same.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    assert_almost_equal(
        camera.project(Vector3(0, 0, 4), 200, 200).z,
        same.project(Vector3(0, 0, 4), 200, 200).z,
        atol=TOLERANCE,
    )


def test_a_non_positive_aspect_ratio_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), 0.0, Length(1.0, METRE), Length(100.0, METRE)
        )
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), -1.0, Length(1.0, METRE), Length(100.0, METRE)
        )


def test_a_non_positive_field_of_view_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(0.0, DEGREE), 1.0, Length(1.0, METRE), Length(100.0, METRE)
        )


def test_a_near_plane_behind_the_camera_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), 1.0, Length(0.0, METRE), Length(100.0, METRE)
        )


def test_a_far_plane_not_beyond_near_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), 1.0, Length(10.0, METRE), Length(10.0, METRE)
        )


def test_a_camera_sitting_on_its_target_cannot_produce_a_view() raises:
    var camera = square_camera()
    camera.place(Vector3(1, 1, 1), Vector3(1, 1, 1))
    with assert_raises():
        _ = camera.view_matrix()


def test_an_invalid_viewport_is_rejected() raises:
    var camera = square_camera()
    with assert_raises():
        _ = camera.project(Vector3(0, 0, 0), 0, 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
