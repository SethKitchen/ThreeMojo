# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.map_controls`, and for `OrbitControls` panning
outside screen space.

The expected numbers come from three.js r180's own `MapControls`, run
headless in Node with the same camera, a view 100 pixels square, and the
same pan and zoom.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    ARROW_UP,
    InputEvent,
    KEY_DOWN,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    SECONDARY,
    WHEEL,
)
from controls.map_controls import MapControls
from controls.orbit_controls import DOLLY, PAN, ROTATE
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100


def _camera(y: Float32) raises -> PerspectiveCamera:
    """Return a camera at (0, y, 5) looking at the origin.

    Args:
        y: The camera's height.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, y, 5), Vector3(0, 0, 0))
    return camera


def _ortho(y: Float32) raises -> OrthographicCamera:
    """Return an orthographic camera at (0, y, 5) looking at the origin.

    Args:
        y: The camera's height.

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
    camera.place(Vector3(0, y, 5), Vector3(0, 0, 0))
    return camera^


def _frame() -> Duration:
    """Return one frame at sixty a second."""
    return Duration(1.0 / 60.0, SECOND)


def _near(actual: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector's components.

    Args:
        actual: The vector.
        x: The expected x.
        y: The expected y.
        z: The expected z.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(actual.x, x, atol=TOLERANCE)
    assert_almost_equal(actual.y, y, atol=TOLERANCE)
    assert_almost_equal(actual.z, z, atol=TOLERANCE)


def test_the_buttons_are_three_js_maps() raises:
    var controls = MapControls()
    assert_false(controls.screen_space_panning)
    assert_true(controls.primary_action == PAN)
    assert_true(controls.middle_action == DOLLY)
    assert_true(controls.secondary_action == ROTATE)


def test_a_pan_up_the_view_goes_forward_over_the_ground() raises:
    var camera = _camera(5)
    var controls = MapControls()
    controls.pan(0, 10, camera, SIZE)
    _ = controls.update(camera, _frame())
    _near(camera.position, 0, 5, 3.585786)
    _near(controls.target, 0, 0, -1.414214)


def test_a_drag_and_an_arrow_pan_over_the_ground() raises:
    var camera = _camera(5)
    var controls = MapControls()
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
    _near(controls.target, 0, 0, -1.414214)
    controls.handle(InputEvent(KEY_DOWN, key=ARROW_UP), camera, SIZE)
    _ = controls.update(camera, _frame())
    # The target stays on the ground.
    assert_almost_equal(controls.target.y, Float32(0), atol=TOLERANCE)
    assert_true(controls.target.z < -1.414214)
    # The secondary button rotates.
    controls.handle(
        InputEvent(POINTER_DOWN, button=SECONDARY, x=50, y=50), camera, SIZE
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=SECONDARY, x=60, y=50), camera, SIZE
    )
    _ = controls.update(camera, _frame())
    assert_true(camera.position.x < 0)


def test_a_zoom_to_the_cursor_looking_down_keeps_the_target_on_the_ground() raises:
    var camera = _camera(5)
    var controls = MapControls()
    controls.zoom_to_cursor = True
    controls.handle(InputEvent(WHEEL, x=90, y=49, wheel=-1), camera, SIZE)
    _ = controls.update(camera, _frame())
    _near(camera.position, 0.222527, 4.807682, 4.803797)
    _near(controls.target, 0.222527, 0, -0.003885)


def test_a_zoom_to_the_cursor_looking_level_keeps_the_target() raises:
    var camera = _camera(0)
    var controls = MapControls()
    controls.zoom_to_cursor = True
    controls.handle(InputEvent(WHEEL, x=90, y=49, wheel=-1), camera, SIZE)
    _ = controls.update(camera, _frame())
    _near(camera.position, 0.157351, 0.001943, 4.805740)
    _near(controls.target, 0, 0, 0)


def test_a_zoom_through_the_ground_keeps_the_target() raises:
    # The camera goes past the ground down the steep ray, so the ground is
    # behind it and the target stays where it was.
    var camera = _camera(5)
    var controls = MapControls()
    controls.zoom_to_cursor = True
    controls.handle(InputEvent(WHEEL, x=50, y=99, wheel=-1), camera, SIZE)
    controls.dolly_in(0.1)
    _ = controls.update(camera, _frame())
    assert_true(camera.position.y < 0)
    _near(controls.target, 0, 0, 0)


def test_an_orthographic_zoom_to_the_cursor_keeps_the_target_on_the_ground() raises:
    var camera = _ortho(5)
    var controls = MapControls()
    controls.zoom_to_cursor = True
    controls.handle(InputEvent(WHEEL, x=90, y=49, wheel=-1), camera, SIZE, SIZE)
    _ = controls.update(camera, _frame())
    assert_true(camera.position.x > 0)
    assert_almost_equal(controls.target.y, Float32(0), atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
