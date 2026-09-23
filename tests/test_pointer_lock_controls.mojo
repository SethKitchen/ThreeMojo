# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.pointer_lock_controls`.

The expected numbers come from three.js r180's own `PointerLockControls`,
run headless in Node with the same camera and movement. three.js's
`moveForward` and `moveRight` read `camera.matrix`, so the camera's matrix
was brought up to date after the turn, as a render does.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    InputEvent,
    InputKind,
    KEY_DOWN,
    KEY_UP,
    Key,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
)
from controls.pointer_lock_controls import PointerLockControls
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle,
    DEGREE,
    Duration,
    Length,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Velocity,
)

comptime TOLERANCE = Float64(1e-4)


def _camera() raises -> PerspectiveCamera:
    """Return a camera five meters up +z, looking at the origin.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera


def _ortho() raises -> OrthographicCamera:
    """Return an orthographic camera five meters up +z.

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


def _seconds(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


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


def _drag(
    mut controls: PointerLockControls,
    mut camera: PerspectiveCamera,
    dx: Int,
    dy: Int,
) raises:
    """Press at (50, 50) and move by (dx, dy).

    Args:
        controls: The controls.
        camera: The camera.
        dx: Pixels right.
        dy: Pixels down.

    Raises:
        Error: If an event is refused.
    """
    controls.handle(
        InputEvent(POINTER_DOWN, button=PRIMARY, x=50, y=50), camera
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=PRIMARY, x=50 + dx, y=50 + dy), camera
    )
    controls.handle(
        InputEvent(POINTER_UP, button=PRIMARY, x=50 + dx, y=50 + dy), camera
    )


def test_the_defaults_are_three_js() raises:
    var controls = PointerLockControls()
    assert_false(controls.is_locked)
    assert_almost_equal(controls.pointer_speed, Float32(1), atol=TOLERANCE)
    assert_almost_equal(
        controls.max_polar_angle.to(DEGREE), Float32(180), atol=TOLERANCE
    )
    controls.lock()
    assert_true(controls.is_locked)
    controls.unlock()
    assert_false(controls.is_locked)


def test_a_move_turns_as_three_js_does() raises:
    var camera = _camera()
    var controls = PointerLockControls()
    controls.lock()
    _drag(controls, camera, 30, -20)
    var frame = CameraFrame.of(camera)
    _near(frame.forward(), 0.059916, 0.039989, -0.997402)
    _near(frame.above, -0.002398, 0.999200, 0.039917)
    _near(controls.get_direction(camera), 0.059916, 0.039989, -0.997402)
    # The camera keeps its up and its distance.
    _near(camera.up, 0, 1, 0)
    assert_almost_equal(frame.reach, Float32(5), atol=TOLERANCE)
    controls.move_forward(camera, Length(1.0, METER))
    controls.move_right(camera, Length(2.0, METER))
    _near(camera.position, 2.056365, 0, 4.121727)
    _near(CameraFrame.of(camera).forward(), 0.059916, 0.039989, -0.997402)


def test_the_polar_angle_is_kept_in_range() raises:
    var camera = _camera()
    var controls = PointerLockControls()
    controls.lock()
    _drag(controls, camera, 30, -20)
    controls.min_polar_angle = Angle(1.2, RADIAN)
    _drag(controls, camera, 0, -500)
    _near(CameraFrame.of(camera).forward(), 0.055889, 0.362358, -0.930362)


def test_a_move_turns_only_when_locked_and_seen() raises:
    var camera = _camera()
    var controls = PointerLockControls()
    # Unlocked: nothing turns.
    _drag(controls, camera, 30, 0)
    _near(CameraFrame.of(camera).forward(), 0, 0, -1)
    # Locked, but the first move after the lock only sets where the
    # pointer is.
    controls.lock()
    controls.handle(InputEvent(POINTER_MOVE, x=0, y=0), camera)
    _near(CameraFrame.of(camera).forward(), 0, 0, -1)
    controls.handle(InputEvent(POINTER_MOVE, x=10, y=0), camera)
    # A move right turns right.
    assert_true(CameraFrame.of(camera).forward().x > 0)


def test_held_keys_walk() raises:
    var camera = _camera()
    var controls = PointerLockControls()
    controls.movement_speed = Velocity(2.0, METER_PER_SECOND)
    controls.handle(InputEvent(KEY_DOWN, key=Key(87)), camera)
    controls.handle(InputEvent(KEY_DOWN, key=Key(100)), camera)
    controls.update(camera, _seconds(0.5))
    _near(camera.position, 1, 0, 4)
    _near(camera.target, 1, 0, -1)
    controls.handle(InputEvent(KEY_UP, key=Key(119)), camera)
    controls.handle(InputEvent(KEY_UP, key=Key(100)), camera)
    for arrow in [ARROW_DOWN, ARROW_LEFT]:
        controls.handle(InputEvent(KEY_DOWN, key=arrow), camera)
    controls.update(camera, _seconds(0.5))
    _near(camera.position, 0, 0, 5)
    controls.handle(InputEvent(KEY_DOWN, key=ARROW_UP), camera)
    controls.handle(InputEvent(KEY_DOWN, key=ARROW_RIGHT), camera)
    controls.handle(InputEvent(KEY_DOWN, key=Key(115)), camera)
    controls.handle(InputEvent(KEY_DOWN, key=Key(97)), camera)
    # Each pair cancels.
    controls.update(camera, _seconds(0.5))
    _near(camera.position, 0, 0, 5)
    # After the timeout nothing is held.
    controls.update(camera, _seconds(1))
    controls.handle(InputEvent(KEY_DOWN, key=Key(119)), camera)
    controls.key_timeout = _seconds(0.1)
    controls.update(camera, _seconds(0.5))
    controls.update(camera, _seconds(0.5))
    _near(camera.position, 0, 0, 4)


def test_an_orthographic_camera_turns_and_walks() raises:
    var camera = _ortho()
    var controls = PointerLockControls()
    controls.lock()
    controls.handle(InputEvent(POINTER_DOWN, x=50, y=50), camera)
    controls.handle(InputEvent(POINTER_MOVE, x=80, y=30), camera)
    _near(controls.get_direction(camera), 0.059916, 0.039989, -0.997402)
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    controls.handle(InputEvent(KEY_DOWN, key=Key(119)), camera)
    controls.update(camera, _seconds(1))
    _near(camera.position, 0, 0, 4)
    controls.move_right(camera, Length(1.0, METER))
    _near(camera.position, 1, 0, 4)
    controls.move_forward(camera, Length(-1.0, METER))
    _near(camera.position, 1, 0, 5)


def test_disabled_controls_do_nothing() raises:
    var camera = _camera()
    var ortho = _ortho()
    var controls = PointerLockControls()
    controls.lock()
    controls.enabled = False
    _drag(controls, camera, 30, 0)
    _near(CameraFrame.of(camera).forward(), 0, 0, -1)
    controls.move_forward(camera, Length(1.0, METER))
    controls.move_right(camera, Length(1.0, METER))
    controls.move_forward(ortho, Length(1.0, METER))
    controls.move_right(ortho, Length(1.0, METER))
    _near(camera.position, 0, 0, 5)
    _near(ortho.position, 0, 0, 5)


def test_bad_input_is_refused() raises:
    var camera = _camera()
    var ortho = _ortho()
    var controls = PointerLockControls()
    with assert_raises(contains="kind"):
        controls.handle(InputEvent(InputKind(9)), camera)
    with assert_raises(contains="button"):
        controls.handle(
            InputEvent(POINTER_DOWN, button=PointerButton(5)), camera
        )
    with assert_raises(contains="key"):
        controls.handle(InputEvent(KEY_DOWN, key=Key(200)), ortho)
    with assert_raises(contains="negative"):
        controls.update(camera, _seconds(-1))
    with assert_raises(contains="negative"):
        controls.update(ortho, _seconds(-1))
    controls.key_timeout = _seconds(0)
    with assert_raises(contains="timeout"):
        controls.update(camera, _seconds(1))
    controls.min_polar_angle = Angle(2.0, RADIAN)
    controls.max_polar_angle = Angle(1.0, RADIAN)
    with assert_raises(contains="polar"):
        controls.handle(InputEvent(POINTER_MOVE), camera)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
