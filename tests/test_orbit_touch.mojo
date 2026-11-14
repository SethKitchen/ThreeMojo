# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the touch input of `controls.orbit_controls`.

Every test starts from a camera five meters up +z from the origin, with a
field of view of 90 degrees and a view 100 pixels square. At that distance
the view covers ten meters top to bottom, so a pixel of pan is a tenth of
a meter, and a drag of 25 pixels is a quarter turn.

The expected numbers are worked out by hand from the arithmetic of
three.js r180's `OrbitControls`: `_handleTouchMoveRotate`,
`_handleTouchMovePan` and `_handleTouchMoveDolly`. three.js runs `update`
after each move, so a test that reads the camera between two moves runs
`update` there too.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    InputKind,
    POINTER_CANCEL,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerId,
    PointerType,
    WHEEL,
    touch_event,
)
from controls.map_controls import MapControls
from controls.orbit_controls import (
    NO_TOUCH_ACTION,
    OrbitControls,
    TOUCH_DOLLY_PAN,
    TOUCH_DOLLY_ROTATE,
    TOUCH_PAN,
    TOUCH_ROTATE,
    TouchAction,
)
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND
from tests._cameras import orthographic_above

comptime SIZE = 100
comptime TOLERANCE = Float64(1e-4)


def _camera() raises -> PerspectiveCamera:
    """Return the camera every test starts from.

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


def _touch(
    mut controls: OrbitControls,
    camera: PerspectiveCamera,
    kind: InputKind,
    finger: Int,
    x: Int,
    y: Int,
) raises:
    """Send one finger's event.

    Args:
        controls: The controls.
        camera: The camera.
        kind: What the finger did.
        finger: The finger's pointer id.
        x: The pixel's column.
        y: The pixel's row.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(touch_event(kind, PointerId(finger), x, y), camera, SIZE)


def _pinch(mut controls: OrbitControls, camera: PerspectiveCamera) raises:
    """Put finger 1 at (40, 50) and finger 2 at (60, 50).

    Args:
        controls: The controls.
        camera: The camera.

    Raises:
        Error: If an event is refused.
    """
    _touch(controls, camera, POINTER_DOWN, 1, 40, 50)
    _touch(controls, camera, POINTER_DOWN, 2, 60, 50)


def test_a_touch_action_knows_its_values() raises:
    assert_true(NO_TOUCH_ACTION.is_valid())
    assert_true(TOUCH_DOLLY_ROTATE.is_valid())
    assert_false(TouchAction(-1).is_valid())
    assert_false(TouchAction(5).is_valid())
    var controls = OrbitControls()
    assert_true(controls.touch_one == TOUCH_ROTATE)
    assert_true(controls.touch_two == TOUCH_DOLLY_PAN)


def test_one_finger_rotates_as_a_left_drag_does() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    _touch(controls, camera, POINTER_UP, 1, 75, 50)
    assert_true(controls.update(camera, _frame()))
    # 25 pixels of a view 100 high is a quarter turn to the left.
    _near(camera.position, -5, 0, 0)
    # A finger down a tenth of the height lifts the camera a tenth of a
    # turn.
    camera = _camera()
    controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 50, 60)
    _ = controls.update(camera, _frame())
    var lifted = Float32(2 * pi / 10)
    _near(camera.position, 0, 5 * sin(lifted), 5 * cos(lifted))


def test_one_finger_can_pan() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.touch_one = TOUCH_PAN
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 60, 45)
    _ = controls.update(camera, _frame())
    # Ten pixels right and five up, at a tenth of a meter a pixel. The
    # content follows the finger, so the camera goes the other way.
    _near(controls.target, -1, -0.5, 0)
    _near(camera.position, -1, -0.5, 5)
    # With panning off, the press starts nothing.
    camera = _camera()
    controls = OrbitControls()
    controls.touch_one = TOUCH_PAN
    controls.enable_pan = False
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 60, 45)
    assert_false(controls.update(camera, _frame()))


def test_two_fingers_that_spread_dolly_in_and_pan_by_their_midpoint() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _pinch(controls, camera)
    # Finger 1 goes ten left: 30 apart from 20, and the midpoint five left.
    _touch(controls, camera, POINTER_MOVE, 1, 30, 50)
    assert_true(controls.update(camera, _frame()))
    _near(controls.target, 0.5, 0, 0)
    _near(camera.position, 0.5, 0, Float32(5) / Float32(1.5))
    # Finger 2 goes ten right: 40 apart from 30, and the midpoint back.
    # A pixel is now 2 * 3.3333 / 100 meters.
    _touch(controls, camera, POINTER_MOVE, 2, 70, 50)
    _ = controls.update(camera, _frame())
    _near(controls.target, 0.166667, 0, 0)
    _near(camera.position, 0.166667, 0, 2.5)


def test_two_fingers_that_move_together_pan() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _pinch(controls, camera)
    # Finger 1 to (50, 60): the fingers are sqrt(200) apart, and the
    # midpoint is five right and five down.
    _touch(controls, camera, POINTER_MOVE, 1, 50, 60)
    _ = controls.update(camera, _frame())
    _near(controls.target, -0.5, 0.5, 0)
    _near(camera.position, -0.5, 0.5, 5 * sqrt(Float32(2)))
    # Finger 2 to (70, 60): 20 apart again, and five more each way, at
    # 2 * 7.0711 / 100 meters a pixel.
    _touch(controls, camera, POINTER_MOVE, 2, 70, 60)
    _ = controls.update(camera, _frame())
    _near(controls.target, -1.207107, 1.207107, 0)
    _near(camera.position, -1.207107, 1.207107, 5)


def test_two_fingers_can_dolly_and_rotate() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.touch_two = TOUCH_DOLLY_ROTATE
    _pinch(controls, camera)
    # 10 apart from 20, then 30 apart from 10: a third nearer in all. The
    # midpoint goes 15 right: 54 degrees to the left.
    _touch(controls, camera, POINTER_MOVE, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    var radius = Float32(5) / Float32(1.5)
    var turned = Float32(2 * pi * 15 / 100)
    _near(camera.position, -radius * sin(turned), 0, radius * cos(turned))
    _near(controls.target, 0, 0, 0)


def test_the_zoom_speed_is_a_power_of_the_pinch() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.zoom_speed = 2
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    # Twice as far apart, squared: a quarter of the distance.
    _near(camera.position, -1, 0, 1.25)


def test_a_pinch_zooms_toward_the_midpoint() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.zoom_to_cursor = True
    controls.enable_pan = False
    _touch(controls, camera, POINTER_DOWN, 1, 70, 30)
    _touch(controls, camera, POINTER_DOWN, 2, 80, 30)
    _touch(controls, camera, POINTER_MOVE, 2, 90, 30)
    _ = controls.update(camera, _frame())
    # The midpoint is at pixel center (80.5, 30.5): 0.61 across and 0.39
    # up. The camera goes half the distance down the ray through it.
    var length = sqrt(Float32(0.61 * 0.61 + 0.39 * 0.39 + 1))
    var step = Float32(2.5) / length
    _near(camera.position, 0.61 * step, 0.39 * step, 5 - step)
    # The view direction is kept: the target is straight ahead.
    _near(controls.target, 0.61 * step, 0.39 * step, 2.5 - step)


def test_the_finger_left_goes_on_with_the_one_finger_action() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_UP, 2, 60, 50)
    # Finger 1 rotates from where it is, at (40, 50).
    _touch(controls, camera, POINTER_MOVE, 1, 65, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, -5, 0, 0)
    _near(controls.target, 0, 0, 0)


def test_three_fingers_do_nothing() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_DOWN, 2, 60, 50)
    _touch(controls, camera, POINTER_DOWN, 3, 70, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 80, 80)
    assert_false(controls.update(camera, _frame()))
    # Two of the three left: still nothing, as in three.js.
    _touch(controls, camera, POINTER_UP, 3, 70, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 20, 20)
    assert_false(controls.update(camera, _frame()))
    # One left: it rotates from where it is.
    _touch(controls, camera, POINTER_UP, 2, 60, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 45, 20)
    _ = controls.update(camera, _frame())
    _near(camera.position, -5, 0, 0)


def test_a_cancel_lets_a_finger_go() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_CANCEL, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera, _frame()))
    # A mouse that is canceled lets its button go too.
    controls.handle(
        InputEvent(POINTER_DOWN, button=PRIMARY, x=50, y=50), camera, SIZE
    )
    controls.handle(InputEvent(POINTER_CANCEL, x=50, y=50), camera, SIZE)
    controls.handle(
        InputEvent(POINTER_MOVE, button=PRIMARY, x=75, y=50), camera, SIZE
    )
    assert_false(controls.update(camera, _frame()))


def test_a_finger_pressed_twice_is_followed_once() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_DOWN, 1, 10, 10)
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, -5, 0, 0)


def test_map_controls_pan_with_one_finger_and_rotate_with_two() raises:
    var camera = _camera()
    var controls = MapControls()
    assert_true(controls.touch_one == TOUCH_PAN)
    assert_true(controls.touch_two == TOUCH_DOLLY_ROTATE)
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 60, 50)
    _ = controls.update(camera, _frame())
    _near(controls.target, -1, 0, 0)
    _near(camera.position, -1, 0, 5)
    _touch(controls, camera, POINTER_UP, 1, 60, 50)
    # Two fingers: twice as far apart, and the midpoint ten right.
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    var turned = Float32(2 * pi * 10 / 100)
    _near(camera.position, -1 - 2.5 * sin(turned), 0, 2.5 * cos(turned))


def test_a_pinch_zooms_an_orthographic_camera() raises:
    var camera = orthographic_above()
    var controls = OrbitControls()
    controls.handle(
        touch_event(POINTER_DOWN, PointerId(1), 40, 50), camera, SIZE, SIZE
    )
    controls.handle(
        touch_event(POINTER_DOWN, PointerId(2), 60, 50), camera, SIZE, SIZE
    )
    controls.handle(
        touch_event(POINTER_MOVE, PointerId(2), 80, 50), camera, SIZE, SIZE
    )
    assert_true(controls.update(camera, _frame()))
    # Twice as far apart is twice the zoom. The midpoint went ten right,
    # at a tenth of a meter a pixel.
    assert_almost_equal(camera.zoom, Float32(2), atol=TOLERANCE)
    _near(camera.position, -1, 0, 5)
    _near(controls.target, -1, 0, 0)


def test_a_two_finger_action_that_is_off_leaves_the_state() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.enable_zoom = False
    controls.enable_pan = False
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_DOWN, 2, 70, 50)
    # Still a rotation, now read midway between the fingers: at (65, 50)
    # from the (50, 50) it started at, as in three.js.
    _touch(controls, camera, POINTER_MOVE, 1, 60, 50)
    _ = controls.update(camera, _frame())
    var turned = Float32(2 * pi * 15 / 100)
    _near(camera.position, -5 * sin(turned), 0, 5 * cos(turned))
    # The same with a dolly and a rotation both off.
    camera = _camera()
    controls = OrbitControls()
    controls.touch_two = TOUCH_DOLLY_ROTATE
    controls.touch_one = TOUCH_PAN
    controls.enable_zoom = False
    controls.enable_rotate = False
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_DOWN, 2, 70, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 60, 50)
    _ = controls.update(camera, _frame())
    # Still a pan, by the 15 pixels to the midpoint.
    _near(controls.target, -1.5, 0, 0)


def test_one_half_of_a_two_finger_action_can_be_off() raises:
    # No dolly: the pinch only pans.
    var camera = _camera()
    var controls = OrbitControls()
    controls.enable_zoom = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, -1, 0, 5)
    # No pan: the pinch only dollies.
    camera = _camera()
    controls = OrbitControls()
    controls.enable_pan = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, 0, 0, 2.5)
    # No rotation: a dolly and rotate only dollies.
    camera = _camera()
    controls = OrbitControls()
    controls.touch_two = TOUCH_DOLLY_ROTATE
    controls.touch_one = TOUCH_PAN
    controls.enable_rotate = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, 0, 0, 2.5)
    # No dolly: a dolly and rotate only rotates.
    camera = _camera()
    controls = OrbitControls()
    controls.touch_two = TOUCH_DOLLY_ROTATE
    controls.enable_zoom = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera, _frame())
    var turned = Float32(2 * pi * 10 / 100)
    _near(camera.position, -5 * sin(turned), 0, 5 * cos(turned))


def test_an_action_turned_off_during_a_touch_stops() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    controls.enable_rotate = False
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera, _frame()))
    controls = OrbitControls()
    controls.touch_one = TOUCH_PAN
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    controls.enable_pan = False
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera, _frame()))


def test_a_two_finger_move_with_one_finger_left_does_nothing() raises:
    # three.js reads the second finger's position there, and has none.
    var camera = _camera()
    var controls = OrbitControls()
    controls.enable_rotate = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_UP, 2, 60, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 50, 50)
    assert_false(controls.update(camera, _frame()))
    controls = OrbitControls()
    controls.touch_two = TOUCH_DOLLY_ROTATE
    controls.touch_one = TOUCH_PAN
    controls.enable_pan = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_UP, 2, 60, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 50, 50)
    assert_false(controls.update(camera, _frame()))


def test_a_finger_and_a_mouse_button_do_not_count_together() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.handle(
        InputEvent(POINTER_DOWN, button=PRIMARY, x=50, y=50), camera, SIZE
    )
    # One finger, though a button is held: it rotates.
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, -5, 0, 0)
    # The finger's release leaves the button held.
    _touch(controls, camera, POINTER_UP, 1, 75, 50)
    controls.handle(
        InputEvent(POINTER_MOVE, button=PRIMARY, x=25, y=50), camera, SIZE
    )
    _ = controls.update(camera, _frame())
    _near(camera.position, 0, 0, 5)


def test_fingers_on_one_pixel_do_not_dolly() raises:
    # three.js divides by the distance between them.
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_DOWN, 2, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 2, 60, 50)
    # No dolly from nothing apart, then twice as far apart.
    _touch(controls, camera, POINTER_MOVE, 2, 70, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, -1, 0, 2.5)
    camera = _camera()
    controls = OrbitControls()
    controls.enable_pan = False
    _pinch(controls, camera)
    # No dolly to nothing apart, and none from it.
    _touch(controls, camera, POINTER_MOVE, 2, 40, 50)
    _touch(controls, camera, POINTER_MOVE, 2, 50, 50)
    assert_false(controls.update(camera, _frame()))
    _touch(controls, camera, POINTER_MOVE, 2, 60, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, 0, 0, 2.5)


def test_a_press_while_disabled_is_not_followed() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.enabled = False
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 60, 50)
    controls.enabled = True
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera, _frame()))
    # The release of a finger that is not followed changes nothing.
    _touch(controls, camera, POINTER_UP, 1, 75, 50)
    # A release while disabled still ends the touch, as in three.js.
    _touch(controls, camera, POINTER_DOWN, 2, 50, 50)
    controls.enabled = False
    _touch(controls, camera, POINTER_UP, 2, 50, 50)
    controls.enabled = True
    _touch(controls, camera, POINTER_MOVE, 2, 75, 50)
    assert_false(controls.update(camera, _frame()))


def test_a_finger_that_was_not_followed_still_moves_the_action() raises:
    # three.js reads a move's own position when one finger is followed,
    # whichever finger moved.
    var camera = _camera()
    var controls = OrbitControls()
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 5, 75, 50)
    _ = controls.update(camera, _frame())
    _near(camera.position, -5, 0, 0)


def test_auto_rotate_and_the_wheel_wait_for_a_touch() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.auto_rotate = True
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    assert_false(controls.update(camera, Duration(1.0, SECOND)))
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, SIZE)
    assert_false(controls.update(camera, Duration(1.0, SECOND)))
    _touch(controls, camera, POINTER_UP, 1, 50, 50)
    assert_true(controls.update(camera, Duration(1.0, SECOND)))


def test_the_speeds_scale_a_touch() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.rotate_speed = 2
    controls.pan_speed = 3
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 55, 50)
    _ = controls.update(camera, _frame())
    var turned = Float32(2 * pi * 10 / 100)
    _near(camera.position, -5 * sin(turned), 0, 5 * cos(turned))
    camera = _camera()
    controls = OrbitControls()
    controls.pan_speed = 3
    controls.enable_zoom = False
    _pinch(controls, camera)
    _touch(controls, camera, POINTER_MOVE, 1, 42, 50)
    _ = controls.update(camera, _frame())
    # The midpoint went one pixel right, times three.
    _near(controls.target, -0.3, 0, 0)


def test_actions_that_are_not_for_that_many_fingers_do_nothing() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.touch_one = TOUCH_DOLLY_PAN
    controls.touch_two = TOUCH_ROTATE
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera, _frame()))
    _touch(controls, camera, POINTER_DOWN, 2, 60, 50)
    _touch(controls, camera, POINTER_MOVE, 2, 90, 80)
    assert_false(controls.update(camera, _frame()))
    controls.touch_one = NO_TOUCH_ACTION
    _touch(controls, camera, POINTER_UP, 2, 90, 80)
    _touch(controls, camera, POINTER_MOVE, 1, 20, 50)
    assert_false(controls.update(camera, _frame()))


def test_a_reset_ends_a_touch() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.save_state(camera)
    _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    controls.reset(camera)
    _touch(controls, camera, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera, _frame()))
    _near(camera.position, 0, 0, 5)


def test_invalid_touches_are_refused() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.touch_one = TouchAction(9)
    with assert_raises(contains="touch action"):
        _touch(controls, camera, POINTER_DOWN, 1, 50, 50)
    controls.touch_one = TOUCH_ROTATE
    controls.touch_two = TouchAction(-1)
    with assert_raises(contains="touch action"):
        _touch(controls, camera, POINTER_DOWN, 2, 50, 50)
    controls.touch_two = TOUCH_DOLLY_PAN
    with assert_raises(contains="pointer type"):
        controls.handle(
            InputEvent(POINTER_DOWN, pointer_type=PointerType(2)),
            camera,
            SIZE,
        )
    with assert_raises(contains="pointer id"):
        controls.handle(
            InputEvent(POINTER_DOWN, pointer_id=PointerId(-1)), camera, SIZE
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
