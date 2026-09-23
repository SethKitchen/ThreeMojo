# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.fly_controls`.

The expected numbers come from three.js r180's own `FlyControls`, run
headless in Node with the same camera and input. three.js's `rollSpeed` of
0.1 is a `roll_speed` of 0.2 radians a second here.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.fly_controls import FlyControls
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
    RESIZE,
    SECONDARY,
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
    Duration,
    Length,
    METER,
    METER_PER_SECOND,
    RADIAN_PER_SECOND,
    SECOND,
    Velocity,
)

comptime TOLERANCE = Float64(1e-4)
comptime SIZE = 100


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


def _key(mut controls: FlyControls, code: Int) raises:
    """Press a key.

    Args:
        controls: The controls.
        code: The key's code.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(InputEvent(KEY_DOWN, key=Key(code)), SIZE, SIZE)


def test_the_defaults_are_three_js() raises:
    var controls = FlyControls()
    assert_almost_equal(
        controls.movement_speed.to(METER_PER_SECOND), Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(
        controls.roll_speed.to(RADIAN_PER_SECOND), Float32(0.01), atol=TOLERANCE
    )
    assert_false(controls.drag_to_look)
    assert_false(controls.auto_forward)


def test_keys_move_and_turn_as_three_js_does() raises:
    var camera = _camera()
    var controls = FlyControls()
    controls.movement_speed = Velocity(2.0, METER_PER_SECOND)
    controls.roll_speed = AngularVelocity(0.2, RADIAN_PER_SECOND)
    _key(controls, 87)
    _key(controls, 100)
    controls.handle(InputEvent(KEY_DOWN, key=ARROW_LEFT), SIZE, SIZE)
    _key(controls, 113)
    assert_true(controls.update(camera, _seconds(0.5)))
    _near(camera.position, 1, 0, 4)
    var frame = CameraFrame.of(camera)
    _near(frame.forward(), -0.099502, -0.004975, -0.995025)
    _near(camera.up, -0.099502, 0.995025, 0.004975)
    # The target stays five meters ahead.
    assert_almost_equal(frame.reach, Float32(5), atol=TOLERANCE)


def test_the_pointer_yaws_and_pitches_as_three_js_does() raises:
    var camera = _camera()
    var controls = FlyControls()
    controls.roll_speed = AngularVelocity(0.2, RADIAN_PER_SECOND)
    controls.handle(InputEvent(POINTER_MOVE, x=75, y=25), SIZE, SIZE)
    _ = controls.update(camera, _seconds(1))
    _near(camera.position, 0, 0, 5)
    _near(CameraFrame.of(camera).forward(), 0.099502, 0.099502, -0.990050)
    _near(camera.up, -0.004975, 0.995025, 0.099502)


def test_every_key_holds_its_move() raises:
    var controls = FlyControls()
    for code in [119, 115, 97, 100, 114, 102, 113, 101, 120]:
        _key(controls, code)
    for arrow in [ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT]:
        controls.handle(InputEvent(KEY_DOWN, key=arrow), SIZE, SIZE)
    # Each pair cancels.
    _near(controls.move_vector(), 0, 0, 0)
    _near(controls.rotation_vector(), 0, 0, 0)
    controls.handle(InputEvent(KEY_UP, key=Key(115)), SIZE, SIZE)
    controls.handle(InputEvent(KEY_UP, key=Key(68)), SIZE, SIZE)
    controls.handle(InputEvent(KEY_UP, key=ARROW_DOWN), SIZE, SIZE)
    controls.handle(InputEvent(KEY_UP, key=ARROW_RIGHT), SIZE, SIZE)
    controls.handle(InputEvent(KEY_UP, key=Key(101)), SIZE, SIZE)
    controls.handle(InputEvent(KEY_UP, key=Key(102)), SIZE, SIZE)
    _near(controls.move_vector(), -1, 1, -1)
    _near(controls.rotation_vector(), 1, 1, 1)


def test_a_key_with_alt_is_ignored() raises:
    var controls = FlyControls()
    controls.handle(InputEvent(KEY_DOWN, key=Key(119), alt=True), SIZE, SIZE)
    _near(controls.move_vector(), 0, 0, 0)


def test_a_key_lets_go_after_its_timeout() raises:
    var camera = _camera()
    var controls = FlyControls()
    controls.key_timeout = _seconds(0.25)
    _key(controls, 119)
    _ = controls.update(camera, _seconds(0.2))
    _near(controls.move_vector(), 0, 0, -1)
    _ = controls.update(camera, _seconds(0.2))
    _near(controls.move_vector(), 0, 0, 0)
    _near(camera.position, 0, 0, 4.6)
    # Nothing held: the camera stays, and says so.
    assert_false(controls.update(camera, _seconds(0.2)))


def test_the_buttons_move_forward_and_back() raises:
    var controls = FlyControls()
    controls.handle(InputEvent(POINTER_DOWN, button=PRIMARY), SIZE, SIZE)
    _near(controls.move_vector(), 0, 0, -1)
    controls.handle(InputEvent(POINTER_UP, button=PRIMARY), SIZE, SIZE)
    controls.handle(InputEvent(POINTER_DOWN, button=SECONDARY), SIZE, SIZE)
    _near(controls.move_vector(), 0, 0, 1)
    controls.handle(InputEvent(POINTER_UP, button=SECONDARY), SIZE, SIZE)
    controls.handle(InputEvent(POINTER_DOWN, button=MIDDLE), SIZE, SIZE)
    _near(controls.move_vector(), 0, 0, 0)
    controls.auto_forward = True
    _near(controls.move_vector(), 0, 0, -1)
    controls.handle(InputEvent(POINTER_DOWN, button=SECONDARY), SIZE, SIZE)
    _near(controls.move_vector(), 0, 0, 1)


def test_drag_to_look_turns_only_while_a_button_is_held() raises:
    var controls = FlyControls()
    controls.drag_to_look = True
    controls.handle(InputEvent(POINTER_MOVE, x=0, y=0), SIZE, SIZE)
    _near(controls.rotation_vector(), 0, 0, 0)
    controls.handle(InputEvent(POINTER_DOWN, button=PRIMARY), SIZE, SIZE)
    # A button does not move forward with drag to look.
    _near(controls.move_vector(), 0, 0, 0)
    controls.handle(InputEvent(POINTER_MOVE, x=0, y=100), SIZE, SIZE)
    _near(controls.rotation_vector(), -1, 1, 0)
    controls.handle(InputEvent(POINTER_UP, button=PRIMARY), SIZE, SIZE)
    _near(controls.rotation_vector(), 0, 0, 0)
    controls.handle(InputEvent(RESIZE, x=10, y=10), SIZE, SIZE)
    _near(controls.rotation_vector(), 0, 0, 0)


def test_disabled_controls_do_nothing() raises:
    var camera = _camera()
    var controls = FlyControls()
    controls.enabled = False
    _key(controls, 119)
    _near(controls.move_vector(), 0, 0, 0)
    controls.enabled = True
    _key(controls, 119)
    controls.enabled = False
    assert_false(controls.update(camera, _seconds(1)))
    _near(camera.position, 0, 0, 5)
    controls.handle(InputEvent(RESIZE, x=10, y=10), SIZE, SIZE)


def test_an_orthographic_camera_flies() raises:
    var camera = OrthographicCamera(
        Length(-5.0, METER),
        Length(5.0, METER),
        Length(5.0, METER),
        Length(-5.0, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var controls = FlyControls()
    _key(controls, 114)
    assert_true(controls.update(camera, _seconds(1)))
    _near(camera.position, 0, 1, 5)
    _near(camera.target, 0, 1, 0)


def test_bad_input_is_refused() raises:
    var camera = _camera()
    var controls = FlyControls()
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
        _ = controls.update(camera, _seconds(-1))
    controls.key_timeout = _seconds(0)
    with assert_raises(contains="timeout"):
        _ = controls.update(camera, _seconds(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
