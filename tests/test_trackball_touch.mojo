# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the touch input of `controls.trackball_controls`.

Every test starts from a camera five meters up +z, looking at the origin,
in a view 100 pixels square. A finger's rotation is held to the same
drag of the left button. The zoom and the pan are worked out by hand from
the arithmetic of three.js r180's `TrackballControls`: `onTouchStart`,
`onTouchMove`, `onTouchEnd`, `_zoomCamera` and `_panCamera`.
"""

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
    WHEEL,
    touch_event,
)
from controls.trackball_controls import TrackballControls
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER
from tests._cameras import orthographic_above

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


def _same(actual: Vector3, expected: Vector3) raises:
    """Assert that two vectors agree.

    Args:
        actual: The vector.
        expected: The vector it must equal.

    Raises:
        Error: If a component differs.
    """
    _near(actual, expected.x, expected.y, expected.z)


def _touch(
    mut controls: TrackballControls,
    kind: InputKind,
    finger: Int,
    x: Int,
    y: Int,
) raises:
    """Send one finger's event.

    Args:
        controls: The controls.
        kind: What the finger did.
        finger: The finger's pointer id.
        x: The pixel's column.
        y: The pixel's row.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(touch_event(kind, PointerId(finger), x, y), SIZE, SIZE)


def _mouse(
    mut controls: TrackballControls, kind: InputKind, x: Int, y: Int
) raises:
    """Send an event of the left button.

    Args:
        controls: The controls.
        kind: What the button did.
        x: The pixel's column.
        y: The pixel's row.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(InputEvent(kind, button=PRIMARY, x=x, y=y), SIZE, SIZE)


def _pinch(mut controls: TrackballControls) raises:
    """Put finger 1 at (40, 50) and finger 2 at (60, 50).

    Args:
        controls: The controls.

    Raises:
        Error: If an event is refused.
    """
    _touch(controls, POINTER_DOWN, 1, 40, 50)
    _touch(controls, POINTER_DOWN, 2, 60, 50)


def test_one_finger_rotates_as_the_left_button_does() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _touch(controls, POINTER_DOWN, 1, 50, 50)
    _touch(controls, POINTER_MOVE, 1, 60, 40)
    assert_true(controls.update(camera))
    var mouse_camera = _camera()
    var mouse = TrackballControls(mouse_camera)
    _mouse(mouse, POINTER_DOWN, 50, 50)
    _mouse(mouse, POINTER_MOVE, 60, 40)
    _ = mouse.update(mouse_camera)
    _same(camera.position, mouse_camera.position)
    _same(camera.up, mouse_camera.up)
    # The numbers three.js gives the same drag of the left button.
    _near(camera.position, -0.986720, -0.986720, 4.801330)
    # The turn coasts after the finger lifts, as after a release.
    _touch(controls, POINTER_UP, 1, 60, 40)
    _mouse(mouse, POINTER_UP, 60, 40)
    _ = controls.update(camera)
    _ = mouse.update(mouse_camera)
    _same(camera.position, mouse_camera.position)


def test_two_fingers_zoom_by_their_distance_and_pan_by_their_midpoint() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    _pinch(controls)
    _touch(controls, POINTER_MOVE, 2, 80, 50)
    assert_true(controls.update(camera))
    # Twice as far apart is half the distance. The midpoint went a tenth
    # of the view right: 0.1 * 2.5 * 0.3 meters, and the camera the other
    # way.
    _near(camera.position, -0.075, 0, 2.5)
    _near(controls.target, -0.075, 0, 0)
    assert_false(controls.update(camera))


def test_a_touch_pan_dies_away_and_a_touch_zoom_does_not() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _pinch(controls)
    _touch(controls, POINTER_MOVE, 2, 80, 50)
    _ = controls.update(camera)
    _near(camera.position, -0.075, 0, 2.5)
    # A fifth of the pan was used: 0.08 * 2.5 * 0.3 more.
    _ = controls.update(camera)
    _near(camera.position, -0.135, 0, 2.5)


def test_the_zoom_starts_where_the_fingers_went_down() raises:
    # three.js reads the first two fingers where each went down, though
    # the first one has moved since.
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    controls.no_rotate = True
    controls.no_pan = True
    _touch(controls, POINTER_DOWN, 1, 40, 50)
    _touch(controls, POINTER_MOVE, 1, 20, 50)
    _touch(controls, POINTER_DOWN, 2, 60, 50)
    # 20 apart where they went down. They are 40 apart now, and a move
    # of finger 2 to (70, 50) makes it 50.
    _touch(controls, POINTER_MOVE, 2, 70, 50)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 2)


def test_the_finger_left_rotates_and_the_zoom_state_stays() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    _pinch(controls)
    _touch(controls, POINTER_UP, 2, 60, 50)
    # Finger 1 rotates from where it is, at (40, 50).
    _touch(controls, POINTER_MOVE, 1, 65, 50)
    _ = controls.update(camera)
    var mouse_camera = _camera()
    var mouse = TrackballControls(mouse_camera)
    mouse.static_moving = True
    _mouse(mouse, POINTER_DOWN, 40, 50)
    _mouse(mouse, POINTER_MOVE, 65, 50)
    _ = mouse.update(mouse_camera)
    _same(camera.position, mouse_camera.position)
    # three.js keeps the two-finger state until the last finger lifts, so
    # a wheel notch waits.
    var before = camera.position
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    _ = controls.update(camera)
    _same(camera.position, before)
    _touch(controls, POINTER_UP, 1, 65, 50)
    _ = controls.update(camera)
    # The notch is 0.025 of the view at a zoom speed of 1.2: 3 percent
    # farther.
    _near(
        camera.position,
        before.x * 1.03,
        before.y * 1.03,
        before.z * 1.03,
    )


def test_a_third_finger_is_read_with_the_first() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    controls.no_pan = True
    _pinch(controls)
    _touch(controls, POINTER_DOWN, 3, 90, 50)
    # Finger 3 is 50 from finger 1. A move to (80, 50) makes it 40, from
    # the 20 the first two went down at.
    _touch(controls, POINTER_MOVE, 3, 80, 50)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 2.5)
    # One of three that lifts changes nothing.
    _touch(controls, POINTER_UP, 3, 80, 50)
    assert_false(controls.update(camera))


def test_fingers_on_one_pixel_do_not_zoom() raises:
    # three.js divides the distance they were apart by the distance now.
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    controls.no_pan = True
    _touch(controls, POINTER_DOWN, 1, 50, 50)
    _touch(controls, POINTER_DOWN, 2, 50, 50)
    _touch(controls, POINTER_MOVE, 2, 60, 50)
    assert_false(controls.update(camera))
    _touch(controls, POINTER_MOVE, 2, 70, 50)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 2.5)
    _touch(controls, POINTER_MOVE, 2, 50, 50)
    assert_false(controls.update(camera))
    _near(camera.position, 0, 0, 2.5)


def test_a_pinch_zooms_an_orthographic_camera() raises:
    var camera = orthographic_above()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    _pinch(controls)
    _touch(controls, POINTER_MOVE, 2, 80, 50)
    assert_true(controls.update(camera))
    assert_almost_equal(camera.zoom, Float32(2), atol=TOLERANCE)
    # The midpoint went a tenth of the view right, at 10 / 2 / 100 meters
    # a pixel of the width, times the distance and the pan speed.
    _near(controls.target, -0.0075, 0, 0)
    controls.max_zoom = 3
    _touch(controls, POINTER_MOVE, 1, 0, 50)
    _ = controls.update(camera)
    assert_almost_equal(camera.zoom, Float32(3), atol=TOLERANCE)


def test_a_cancel_lets_a_finger_go_even_while_disabled() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _touch(controls, POINTER_DOWN, 1, 50, 50)
    controls.enabled = False
    _touch(controls, POINTER_CANCEL, 1, 50, 50)
    # A finger that is not followed, and a canceled mouse, change nothing.
    _touch(controls, POINTER_CANCEL, 7, 50, 50)
    controls.handle(InputEvent(POINTER_CANCEL), SIZE, SIZE)
    controls.enabled = True
    _touch(controls, POINTER_MOVE, 1, 75, 50)
    assert_false(controls.update(camera))


def test_a_release_while_disabled_is_not_heard() raises:
    # three.js's `onPointerUp` returns when the controls are off, so the
    # finger stays down for them.
    var camera = _camera()
    var controls = TrackballControls(camera)
    _touch(controls, POINTER_DOWN, 1, 50, 50)
    controls.enabled = False
    _touch(controls, POINTER_UP, 1, 50, 50)
    _touch(controls, POINTER_DOWN, 2, 10, 10)
    controls.enabled = True
    _touch(controls, POINTER_MOVE, 1, 60, 40)
    _ = controls.update(camera)
    _near(camera.position, -0.986720, -0.986720, 4.801330)


def test_a_mouse_press_ends_a_two_finger_state_left_by_a_cancel() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    _pinch(controls)
    _touch(controls, POINTER_CANCEL, 1, 40, 50)
    _touch(controls, POINTER_CANCEL, 2, 60, 50)
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    assert_false(controls.update(camera))
    _mouse(controls, POINTER_DOWN, 50, 50)
    _mouse(controls, POINTER_UP, 50, 50)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5.15)


def test_a_finger_and_a_mouse_button_do_not_count_together() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _mouse(controls, POINTER_DOWN, 50, 50)
    # One finger, though a button is held: it rotates.
    _touch(controls, POINTER_DOWN, 1, 50, 50)
    _touch(controls, POINTER_MOVE, 1, 60, 40)
    _ = controls.update(camera)
    _near(camera.position, -0.986720, -0.986720, 4.801330)


def test_a_reset_ends_a_pinch() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    _pinch(controls)
    controls.reset(camera)
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5.15)


def test_an_invalid_pointer_is_refused() raises:
    var controls = TrackballControls(_camera())
    with assert_raises(contains="pointer id"):
        _touch(controls, POINTER_DOWN, -1, 50, 50)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
