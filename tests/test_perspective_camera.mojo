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
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from math.matrix4 import Matrix4
from math.projection import look_at
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, FOOT, Length, METER, RADIAN

comptime TOLERANCE = Float64(1e-4)


def square_camera() raises -> PerspectiveCamera:
    """Return a 90-degree square camera 5 m back from the origin.

    Returns:
        A camera whose geometry is easy to check by hand.

    Raises:
        Error: If the camera parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(1.0, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def test_the_origin_projects_to_the_image_center() raises:
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
        Angle(90.0, DEGREE), 2.0, Length(1.0, METER), Length(100.0, METER)
    )
    wide.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var from_square = square.project(Vector3(2, 0, 0), 200, 200).x - 100
    var from_wide = wide.project(Vector3(2, 0, 0), 200, 200).x - 100
    assert_true(abs(from_wide) < abs(from_square))


def test_a_wider_field_of_view_shrinks_what_is_on_screen() raises:
    var narrow = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(1.0, METER), Length(100.0, METER)
    )
    narrow.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var wide = square_camera()
    var narrow_y = narrow.project(Vector3(0, 1, 0), 200, 200).y - 100
    var wide_y = wide.project(Vector3(0, 1, 0), 200, 200).y - 100
    assert_true(abs(wide_y) < abs(narrow_y))


def test_distant_points_move_towards_the_center() raises:
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
    # The new target is what sits at the center now.
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
        Angle(1.5707963, RADIAN), 1.0, Length(1.0, METER), Length(100.0, METER)
    )
    from_radians.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    assert_almost_equal(
        from_degrees.project(Vector3(1, 2, 0), 200, 200).x,
        from_radians.project(Vector3(1, 2, 0), 200, 200).x,
        atol=TOLERANCE,
    )


def test_feet_and_meters_describe_the_same_clipping_planes() raises:
    # A camera specified in feet must behave identically.
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE),
        1.0,
        Length(1.0, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var same = PerspectiveCamera(
        Angle(90.0, DEGREE),
        1.0,
        Length(3.2808399, FOOT),
        Length(100.0, METER),
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
            Angle(90.0, DEGREE), 0.0, Length(1.0, METER), Length(100.0, METER)
        )
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), -1.0, Length(1.0, METER), Length(100.0, METER)
        )


def test_a_non_positive_field_of_view_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(0.0, DEGREE), 1.0, Length(1.0, METER), Length(100.0, METER)
        )


def test_a_near_plane_behind_the_camera_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), 1.0, Length(0.0, METER), Length(100.0, METER)
        )


def test_a_far_plane_not_beyond_near_is_rejected() raises:
    with assert_raises():
        _ = PerspectiveCamera(
            Angle(90.0, DEGREE), 1.0, Length(10.0, METER), Length(10.0, METER)
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


def assert_same_matrix(a: Matrix4, b: Matrix4) raises:
    """Assert two matrices agree element by element."""
    for index in range(16):
        assert_almost_equal(
            a.elements[index], b.elements[index], atol=TOLERANCE
        )


# --- riding a node -----------------------------------------------------------


def test_a_placed_camera_answers_the_same_with_or_without_a_scene() raises:
    var camera = square_camera()
    assert_equal(camera.node, NO_PARENT)
    assert_same_matrix(camera.view_matrix_in(Scene()), camera.view_matrix())


def test_an_attached_camera_looks_from_its_node() raises:
    # A node five meters up +z with no rotation looks down -z at the origin,
    # which is exactly where `place` put the square camera.
    var scene = Scene()
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    var node = scene.add(eye^)
    scene.update()
    var camera = square_camera()
    camera.attach(node)
    assert_equal(camera.node, node)
    assert_same_matrix(
        camera.view_matrix_in(scene),
        look_at(Vector3(0, 0, 5), Vector3(0, 0, 0), Vector3(0, 1, 0)),
    )


def test_an_attached_camera_is_carried_by_its_parent() raises:
    # The eye hangs off a pivot turned a quarter turn about y, so it ends up
    # on +x, still facing the origin.
    var scene = Scene()
    var pivot = Object3D()
    pivot.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    var rig = scene.add(pivot^)
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    var node = scene.attach(eye^, rig)
    scene.update()
    var camera = square_camera()
    camera.attach(node)
    assert_same_matrix(
        camera.view_matrix_in(scene),
        look_at(Vector3(5, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0)),
    )


def test_an_attached_camera_refuses_to_answer_without_the_scene() raises:
    var camera = square_camera()
    camera.attach(NodeId(0))
    with assert_raises():
        _ = camera.view_matrix()
    # Placing it again lets go of the node.
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    assert_equal(camera.node, NO_PARENT)
    _ = camera.view_matrix()


def test_an_attached_camera_needs_a_current_scene_and_a_real_node() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var camera = square_camera()
    camera.attach(node)
    # Stale: the node was added and nothing has been updated since.
    with assert_raises():
        _ = camera.view_matrix_in(scene)
    scene.update()
    _ = camera.view_matrix_in(scene)
    camera.attach(NodeId(7))
    with assert_raises():
        _ = camera.view_matrix_in(scene)


def test_an_attached_camera_takes_position_and_turn_but_not_scale() raises:
    # three.js drops scale from a camera's world matrix before inverting it,
    # and so does `node_view_matrix`: a scaled group carries the camera but
    # must not change its lens.
    var scene = Scene()
    var group = Object3D()
    group.set_scale(3, 3, 3)
    var rig = scene.add(group^)
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    eye.set_scale(2, 1, 1)
    var node = scene.attach(eye^, rig)
    scene.update()
    var camera = square_camera()
    camera.attach(node)
    # Position is inherited, scale included: the eye sits at (0, 0, 15).
    assert_same_matrix(
        camera.view_matrix_in(scene),
        look_at(Vector3(0, 0, 15), Vector3(0, 0, 0), Vector3(0, 1, 0)),
    )


def test_a_scale_along_the_nodes_own_axes_drops_out_even_beside_a_turn() raises:
    # A node turned 45 degrees about z and scaled (2, 1, 1) along its own
    # axes still has world axes at right angles: the scale drops out and the
    # turn stays, so the camera's up is the turned +y.
    var scene = Scene()
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    eye.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(45.0, DEGREE))
    eye.set_scale(2, 1, 1)
    var node = scene.add(eye^)
    scene.update()
    var camera = square_camera()
    camera.attach(node)
    var up = Vector3(-0.70710678, 0.70710678, 0)
    assert_same_matrix(
        camera.view_matrix_in(scene),
        look_at(Vector3(0, 0, 5), Vector3(0, 0, 0), up),
    )


def test_a_sheared_camera_node_is_refused() raises:
    # A group scaled (2, 1, 1) above a node turned 45 degrees about z: the
    # node's world x and y axes are no longer at right angles, and no
    # rotation has axes like that. Normalizing them and inverting the result
    # as a view, as the first version did, skewed the image.
    var scene = Scene()
    var group = Object3D()
    group.set_scale(2, 1, 1)
    var rig = scene.add(group^)
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    eye.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(45.0, DEGREE))
    var node = scene.attach(eye^, rig)
    scene.update()
    var camera = square_camera()
    camera.attach(node)
    with assert_raises():
        _ = camera.view_matrix_in(scene)


def test_a_camera_draws_layer_zero_unless_told_otherwise() raises:
    var camera = square_camera()
    assert_true(camera.visible_layers().is_enabled(0))
    assert_true(not camera.visible_layers().is_enabled(1))
    camera.layers.enable(1)
    assert_true(camera.visible_layers().is_enabled(1))


def test_a_mirrored_or_flattened_camera_node_is_refused() raises:
    var scene = Scene()
    var mirror = Object3D()
    mirror.set_position(0, 0, 5)
    mirror.set_scale(-1, 1, 1)
    var mirrored = scene.add(mirror^)
    var flat = Object3D()
    flat.set_position(0, 0, 5)
    flat.set_scale(1, 0, 1)
    var flattened = scene.add(flat^)
    scene.update()
    var camera = square_camera()
    camera.attach(mirrored)
    with assert_raises():
        _ = camera.view_matrix_in(scene)
    camera.attach(flattened)
    with assert_raises():
        _ = camera.view_matrix_in(scene)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
