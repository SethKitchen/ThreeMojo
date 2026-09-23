# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `OrbitControls` on an orthographic camera, on a camera whose
up is not +y, and zooming toward the cursor."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    MIDDLE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    RESIZE,
    SECONDARY,
    WHEEL,
)
from controls.orbit_controls import OrbitControls
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100


def _ortho() raises -> OrthographicCamera:
    """Return an orthographic camera ten meters square, five up +z.

    Returns:
        The camera.

    Raises:
        Error: If its volume is refused.
    """
    var camera = OrthographicCamera(
        Length(-5.0, METER),
        Length(5.0, METER),
        Length(5.0, METER),
        Length(-5.0, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def _perspective() raises -> PerspectiveCamera:
    """Return a perspective camera five up +z with a 90 degree view.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are refused.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def _frame() -> Duration:
    """Return one frame at sixty a second."""
    return Duration(1.0 / 60.0, SECOND)


def test_a_rotation_between_two_directions() raises:
    var turn = Quaternion.from_unit_vectors(Vector3(1, 0, 0), Vector3(0, 1, 0))
    var turned = turn.rotate(Vector3(1, 0, 0))
    assert_almost_equal(turned.y, Float32(1), atol=TOLERANCE)
    # Opposite directions: a half turn about a perpendicular axis.
    var flip = Quaternion.from_unit_vectors(Vector3(1, 0, 0), Vector3(-1, 0, 0))
    assert_almost_equal(
        flip.rotate(Vector3(1, 0, 0)).x, Float32(-1), atol=TOLERANCE
    )
    var over = Quaternion.from_unit_vectors(Vector3(0, 0, 1), Vector3(0, 0, -1))
    assert_almost_equal(
        over.rotate(Vector3(0, 0, 1)).z, Float32(-1), atol=TOLERANCE
    )


def test_an_orthographic_zoom_shrinks_the_volume() raises:
    var camera = _ortho()
    camera.zoom = 2
    var projection = camera.projection_matrix()
    # Five meters across maps to the edge at zoom one; half as far at two.
    assert_almost_equal(
        projection.transform_point(Vector3(2.5, 0, -1)).x,
        Float32(1),
        atol=TOLERANCE,
    )
    camera.zoom = 0
    with assert_raises(contains="zoom"):
        _ = camera.projection_matrix()


def test_a_wheel_zooms_an_orthographic_camera() raises:
    var camera = _ortho()
    var controls = OrbitControls()
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, SIZE, SIZE)
    assert_true(controls.update(camera, _frame()))
    assert_almost_equal(camera.zoom, Float32(1) / Float32(0.95), atol=TOLERANCE)
    # The distance is kept.
    assert_almost_equal(camera.position.z, Float32(5), atol=TOLERANCE)
    controls.max_zoom = 1
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, SIZE, SIZE)
    _ = controls.update(camera, _frame())
    assert_almost_equal(camera.zoom, Float32(1), atol=TOLERANCE)
    controls.min_zoom = 1
    controls.handle(InputEvent(WHEEL, wheel=1), camera, SIZE, SIZE)
    assert_false(controls.update(camera, _frame()))


def test_an_orthographic_pan_moves_by_the_extent() raises:
    var camera = _ortho()
    var controls = OrbitControls()
    # Ten meters across a hundred pixels: a tenth of a meter a pixel.
    controls.handle(
        InputEvent(POINTER_DOWN, button=SECONDARY, x=50, y=50),
        camera,
        SIZE,
        SIZE,
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=SECONDARY, x=60, y=50),
        camera,
        SIZE,
        SIZE,
    )
    controls.handle(
        InputEvent(POINTER_UP, button=SECONDARY, x=60, y=50), camera, SIZE, SIZE
    )
    _ = controls.update(camera, _frame())
    assert_almost_equal(camera.position.x, Float32(-1), atol=TOLERANCE)
    controls.pan(0, 10, camera, SIZE, SIZE)
    _ = controls.update(camera, _frame())
    assert_almost_equal(camera.position.y, Float32(1), atol=TOLERANCE)
    with assert_raises(contains="width"):
        controls.handle(InputEvent(WHEEL, wheel=1), camera, 0, SIZE)


def test_an_orthographic_zoom_to_the_cursor_keeps_the_point_under_it() raises:
    var camera = _ortho()
    var controls = OrbitControls()
    controls.zoom_to_cursor = True
    # The pointer at three quarters across: 2.5 meters right of center.
    controls.handle(InputEvent(WHEEL, x=74, y=49, wheel=-1), camera, SIZE, SIZE)
    _ = controls.update(camera, _frame())
    # Zoomed in about the cursor, so the camera moved toward it.
    assert_true(camera.position.x > 0)
    assert_almost_equal(controls.target.x, camera.position.x, atol=TOLERANCE)


def test_a_perspective_zoom_to_the_cursor_moves_toward_it() raises:
    var camera = _perspective()
    var controls = OrbitControls()
    controls.zoom_to_cursor = True
    controls.handle(InputEvent(WHEEL, x=90, y=49, wheel=-1), camera, SIZE)
    _ = controls.update(camera, _frame())
    assert_true(camera.position.x > 0)
    assert_true(camera.position.z < 5)
    # The view direction is kept: the target is straight ahead of it.
    assert_almost_equal(controls.target.x, camera.position.x, atol=TOLERANCE)
    # A dolly drag aims at the cursor too; a later frame with nothing
    # pending leaves it alone.
    controls.handle(
        InputEvent(POINTER_DOWN, button=MIDDLE, x=10, y=49), camera, SIZE
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=MIDDLE, x=10, y=40), camera, SIZE
    )
    controls.handle(
        InputEvent(POINTER_UP, button=MIDDLE, x=10, y=40), camera, SIZE
    )
    _ = controls.update(camera, _frame())
    assert_false(controls.update(camera, _frame()))


def test_the_poles_follow_the_cameras_up() raises:
    # A camera with +z up, looking along -y: a drag up turns it over the
    # target toward +z.
    var camera = _perspective()
    camera.up = Vector3(0, 0, 1)
    camera.place(Vector3(0, 5, 0), Vector3(0, 0, 0))
    var controls = OrbitControls()
    controls.handle(
        InputEvent(POINTER_DOWN, button=PRIMARY, x=50, y=50), camera, SIZE
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=PRIMARY, x=50, y=60), camera, SIZE
    )
    controls.handle(
        InputEvent(POINTER_UP, button=PRIMARY, x=50, y=60), camera, SIZE
    )
    _ = controls.update(camera, _frame())
    assert_true(camera.position.z > 1)
    assert_almost_equal(camera.position.length(), Float32(5), atol=1e-3)


def test_a_resize_changes_nothing() raises:
    var camera = _perspective()
    var controls = OrbitControls()
    controls.handle(InputEvent(RESIZE, x=80, y=48), camera, SIZE)
    assert_false(controls.update(camera, _frame()))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
