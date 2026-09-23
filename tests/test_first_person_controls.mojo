# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.first_person_controls`.

The expected numbers come from three.js r180's own `FirstPersonControls`,
run headless in Node with the same camera and input.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.first_person_controls import FirstPersonControls
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
    MIDDLE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
    WHEEL,
)
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
    AngularVelocity,
    DEGREE,
    DEGREE_PER_SECOND,
    Duration,
    Frequency,
    Length,
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    RADIAN,
    SECOND,
    Velocity,
)

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100


def _camera(y: Float32 = 0) raises -> PerspectiveCamera:
    """Return a camera at (0, y, 5), looking along -z.

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
    camera.place(Vector3(0, y, 5), Vector3(0, y, 0))
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


def _same_direction(actual: Angle, degrees: Float32) raises:
    """Assert an angle names the same direction as a number of degrees.

    three.js reads a longitude of 180 degrees where this port reads -180:
    the sign of a zero differs. Both name one direction.

    Args:
        actual: The angle.
        degrees: The expected angle, in degrees.

    Raises:
        Error: If the directions differ.
    """
    var difference = actual.to(DEGREE) - degrees
    var turns = difference / 360
    assert_almost_equal(turns, Float32(Int(round(turns))), atol=1e-5)


def _press(mut controls: FirstPersonControls, key: Key) raises:
    """Press a key.

    Args:
        controls: The controls.
        key: The key.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(InputEvent(KEY_DOWN, key=key), SIZE, SIZE)


def _release(mut controls: FirstPersonControls, key: Key) raises:
    """Let a key go.

    Args:
        controls: The controls.
        key: The key.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(InputEvent(KEY_UP, key=key), SIZE, SIZE)


def _step(
    mut controls: FirstPersonControls,
    key: Key,
    x: Float32,
    y: Float32,
    z: Float32,
) raises:
    """Hold a key for a second from (0, 0, 5) and check where it went.

    Args:
        controls: The controls.
        key: The key.
        x: The expected x.
        y: The expected y.
        z: The expected z.

    Raises:
        Error: If the camera went elsewhere.
    """
    var camera = _camera()
    _press(controls, key)
    controls.update(camera, _seconds(1))
    _release(controls, key)
    _near(camera.position, x, y, z)


def test_the_defaults_are_three_js() raises:
    var controls = FirstPersonControls(_camera())
    assert_almost_equal(
        controls.look_speed.to(DEGREE_PER_SECOND), Float32(0.005), atol=1e-6
    )
    assert_almost_equal(
        controls.movement_speed.to(METER_PER_SECOND), Float32(1), atol=TOLERANCE
    )
    assert_true(controls.look_vertical)
    assert_true(controls.active_look)
    assert_almost_equal(
        controls.vertical_max.to(DEGREE), Float32(180), atol=TOLERANCE
    )
    # Looking down -z is a longitude of a half turn.
    assert_almost_equal(
        controls.latitude().to(DEGREE), Float32(0), atol=TOLERANCE
    )
    _same_direction(controls.longitude(), 180)


def test_the_pointer_and_a_key_move_as_three_js_does() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    controls.look_speed = AngularVelocity(0.1, DEGREE_PER_SECOND)
    controls.movement_speed = Velocity(2.0, METER_PER_SECOND)
    controls.handle(InputEvent(POINTER_MOVE, x=80, y=30), SIZE, SIZE)
    _press(controls, Key(119))
    controls.update(camera, _seconds(0.5))
    _near(camera.position, 0, 0, 4)
    _near(CameraFrame.of(camera).forward(), 0.026173, 0.017452, -0.999505)
    assert_almost_equal(
        controls.latitude().to(DEGREE), Float32(1), atol=TOLERANCE
    )
    _same_direction(controls.longitude(), 178.5)
    # The camera keeps its up and its distance to the target.
    _near(camera.up, 0, 1, 0)
    assert_almost_equal(
        CameraFrame.of(camera).reach, Float32(5), atol=TOLERANCE
    )


def test_a_vertical_range_and_height_speed_move_as_three_js_does() raises:
    var camera = _camera(3)
    var controls = FirstPersonControls(camera)
    controls.look_speed = AngularVelocity(0.1, DEGREE_PER_SECOND)
    controls.movement_speed = Velocity(2.0, METER_PER_SECOND)
    controls.constrain_vertical = True
    controls.vertical_min = Angle(1.0, RADIAN)
    controls.vertical_max = Angle(2.0, RADIAN)
    controls.height_speed = True
    controls.height_min = Length(0.0, METER)
    controls.height_max = Length(10.0, METER)
    controls.height_coef = Frequency(0.5, PER_SECOND)
    controls.auto_forward = True
    controls.handle(InputEvent(POINTER_MOVE, x=50, y=90), SIZE, SIZE)
    controls.update(camera, _seconds(0.5))
    _near(camera.position, 0, 3, 3.25)
    _near(CameraFrame.of(camera).forward(), 0, 0.035882, -0.999356)


def test_every_key_moves_its_way() raises:
    var controls = FirstPersonControls(_camera())
    _step(controls, Key(119), 0, 0, 4)
    _step(controls, ARROW_UP, 0, 0, 4)
    _step(controls, Key(83), 0, 0, 6)
    _step(controls, ARROW_DOWN, 0, 0, 6)
    _step(controls, Key(97), -1, 0, 5)
    _step(controls, ARROW_LEFT, -1, 0, 5)
    _step(controls, Key(100), 1, 0, 5)
    _step(controls, ARROW_RIGHT, 1, 0, 5)
    _step(controls, Key(114), 0, 1, 5)
    _step(controls, Key(102), 0, -1, 5)
    _step(controls, Key(120), 0, 0, 5)
    # Auto forward stops while moving back.
    controls.auto_forward = True
    _step(controls, Key(115), 0, 0, 6)


def test_a_key_lets_go_after_its_timeout() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    _press(controls, Key(119))
    controls.update(camera, _seconds(0.2))
    controls.update(camera, _seconds(0.2))
    controls.update(camera, _seconds(0.2))
    _near(camera.position, 0, 0, 4.6)


def test_the_buttons_move_while_looking_is_on() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    controls.handle(InputEvent(POINTER_DOWN, button=PRIMARY), SIZE, SIZE)
    assert_true(controls.mouse_drag_on)
    controls.update(camera, _seconds(1))
    controls.handle(InputEvent(POINTER_UP, button=PRIMARY), SIZE, SIZE)
    assert_false(controls.mouse_drag_on)
    controls.handle(InputEvent(POINTER_DOWN, button=SECONDARY), SIZE, SIZE)
    controls.handle(InputEvent(POINTER_DOWN, button=MIDDLE), SIZE, SIZE)
    controls.update(camera, _seconds(2))
    controls.handle(InputEvent(POINTER_UP, button=SECONDARY), SIZE, SIZE)
    _near(camera.position, 0, 0, 6)
    controls.active_look = False
    controls.handle(InputEvent(POINTER_DOWN, button=PRIMARY), SIZE, SIZE)
    controls.handle(InputEvent(POINTER_MOVE, x=0, y=0), SIZE, SIZE)
    controls.update(camera, _seconds(1))
    # Neither a move nor a turn.
    _near(camera.position, 0, 0, 6)
    _near(CameraFrame.of(camera).forward(), 0, 0, -1)


def test_the_latitude_stops_at_85_degrees() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    controls.look_speed = AngularVelocity(10.0, DEGREE_PER_SECOND)
    controls.handle(InputEvent(POINTER_MOVE, x=50, y=0), SIZE, SIZE)
    controls.update(camera, _seconds(1))
    assert_almost_equal(controls.latitude().to(DEGREE), Float32(85), atol=1e-3)
    controls.look_vertical = False
    controls.handle(InputEvent(POINTER_MOVE, x=50, y=100), SIZE, SIZE)
    controls.update(camera, _seconds(1))
    assert_almost_equal(controls.latitude().to(DEGREE), Float32(85), atol=1e-3)


def test_look_at_turns_the_camera() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    controls.look_at(camera, Vector3(5, 0, 5))
    assert_almost_equal(controls.longitude().to(DEGREE), Float32(90), atol=1e-3)
    var ortho = _ortho()
    var flat = FirstPersonControls(ortho)
    flat.look_at(ortho, Vector3(0, 5, 5))
    assert_almost_equal(flat.latitude().to(DEGREE), Float32(90), atol=1e-3)


def test_an_orthographic_camera_walks() raises:
    var camera = _ortho()
    var controls = FirstPersonControls(camera)
    _press(controls, Key(119))
    controls.update(camera, _seconds(1))
    _near(camera.position, 0, 0, 4)
    _near(camera.target, 0, 0, -1)


def test_disabled_controls_do_nothing() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    controls.enabled = False
    _press(controls, Key(119))
    controls.enabled = True
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    _press(controls, Key(119))
    controls.enabled = False
    controls.update(camera, _seconds(1))
    _near(camera.position, 0, 0, 5)


def test_bad_input_is_refused() raises:
    var camera = _camera()
    var controls = FirstPersonControls(camera)
    with assert_raises(contains="kind"):
        controls.handle(InputEvent(InputKind(9)), SIZE, SIZE)
    with assert_raises(contains="button"):
        controls.handle(
            InputEvent(POINTER_DOWN, button=PointerButton(5)), SIZE, SIZE
        )
    with assert_raises(contains="key"):
        controls.handle(InputEvent(KEY_DOWN, key=Key(200)), SIZE, SIZE)
    with assert_raises(contains="size"):
        controls.handle(InputEvent(KEY_DOWN, key=Key(119)), 0, SIZE)
    with assert_raises(contains="size"):
        controls.handle(InputEvent(KEY_DOWN, key=Key(119)), SIZE, 0)
    with assert_raises(contains="negative"):
        controls.update(camera, _seconds(-1))
    controls.constrain_vertical = True
    controls.vertical_max = Angle(0.0, RADIAN)
    with assert_raises(contains="vertical"):
        controls.update(camera, _seconds(1))
    var ortho = _ortho()
    with assert_raises(contains="vertical"):
        controls.update(ortho, _seconds(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
