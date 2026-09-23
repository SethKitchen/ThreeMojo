# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.trackball_controls`.

The expected numbers come from three.js r180's own `TrackballControls`,
run headless in Node with the same camera, a view 100 pixels square, and
the same input. A wheel notch is a `deltaY` of 100 pixels.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    InputKind,
    KEY_DOWN,
    KEY_UP,
    Key,
    MIDDLE,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    RESIZE,
    SECONDARY,
    WHEEL,
)
from controls.orbit_controls import DOLLY, OrbitAction, PAN, ROTATE
from controls.trackball_controls import TrackballControls
from math.vector3 import Vector3
from std.math import inf
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
    mut controls: TrackballControls,
    button: PointerButton,
    x: Int,
    y: Int,
    *,
    release: Bool = False,
) raises:
    """Press a button at (50, 50) and move to (x, y).

    Args:
        controls: The controls.
        button: The button.
        x: The column the pointer goes to.
        y: The row the pointer goes to.
        release: Whether to let the button go after.

    Raises:
        Error: If an event is refused.
    """
    controls.handle(
        InputEvent(POINTER_DOWN, button=button, x=50, y=50), SIZE, SIZE
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=button, x=x, y=y), SIZE, SIZE
    )
    if release:
        controls.handle(
            InputEvent(POINTER_UP, button=button, x=x, y=y), SIZE, SIZE
        )


def _key(mut controls: TrackballControls, code: Int) raises:
    """Press a key.

    Args:
        controls: The controls.
        code: The key's code.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(InputEvent(KEY_DOWN, key=Key(code)), SIZE, SIZE)


def _let_go(mut controls: TrackballControls) raises:
    """Let every key go.

    Args:
        controls: The controls.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(InputEvent(KEY_UP, key=Key(97)), SIZE, SIZE)


def test_the_defaults_are_three_js() raises:
    var controls = TrackballControls(_camera())
    assert_almost_equal(controls.rotate_speed, Float32(1), atol=TOLERANCE)
    assert_almost_equal(controls.zoom_speed, Float32(1.2), atol=TOLERANCE)
    assert_almost_equal(controls.pan_speed, Float32(0.3), atol=TOLERANCE)
    assert_almost_equal(
        controls.dynamic_damping_factor, Float32(0.2), atol=TOLERANCE
    )
    assert_false(controls.static_moving)
    assert_true(controls.primary_action == ROTATE)
    assert_true(controls.middle_action == DOLLY)
    assert_true(controls.secondary_action == PAN)


def test_a_drag_rotates_and_coasts_as_three_js_does() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _drag(controls, PRIMARY, 60, 40)
    assert_true(controls.update(camera))
    _near(camera.position, -0.986720, -0.986720, 4.801330)
    _near(camera.up, -0.019867, 0.980133, 0.197344)
    controls.handle(InputEvent(POINTER_UP, button=PRIMARY), SIZE, SIZE)
    _ = controls.update(camera)
    _near(camera.position, -1.805069, -1.805069, 4.299239)
    _near(camera.up, -0.070076, 0.929924, 0.361014)


def test_a_wheel_zooms_as_three_js_does() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5.15)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5.2736)


def test_a_drag_pans_as_three_js_does() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _drag(controls, SECONDARY, 60, 70)
    _ = controls.update(camera)
    _near(camera.position, -0.15, 0.3, 5)
    _near(controls.target, -0.15, 0.3, 0)
    _ = controls.update(camera)
    _near(camera.position, -0.27, 0.54, 5)
    _near(controls.target, -0.27, 0.54, 0)


def test_an_orthographic_camera_pans_and_zooms_as_three_js_does() raises:
    var camera = _ortho()
    var controls = TrackballControls(camera)
    _drag(controls, SECONDARY, 60, 70, release=True)
    assert_true(controls.update(camera))
    _near(camera.position, -0.015, 0.03, 5)
    _near(controls.target, -0.015, 0.03, 0)
    _drag(controls, MIDDLE, 50, 40)
    _ = controls.update(camera)
    assert_almost_equal(camera.zoom, Float32(1.136364), atol=TOLERANCE)
    # The zoom is kept within its limits, and a change of zoom alone is a
    # change.
    controls.max_zoom = 1.2
    _drag(controls, MIDDLE, 50, 0, release=True)
    controls.static_moving = True
    controls.no_pan = True
    assert_true(controls.update(camera))
    assert_almost_equal(camera.zoom, Float32(1.2), atol=TOLERANCE)
    assert_false(controls.update(camera))
    # A zoom that would turn the camera inside out is no zoom.
    controls.max_zoom = inf[DType.float32]()
    _drag(controls, MIDDLE, 50, 99, release=True)
    controls.handle(
        InputEvent(POINTER_DOWN, button=MIDDLE, x=50, y=99), SIZE, SIZE
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=MIDDLE, x=50, y=0), SIZE, SIZE
    )
    _ = controls.update(camera)
    assert_almost_equal(camera.zoom, Float32(1.2), atol=TOLERANCE)
    controls.reset(camera)
    assert_almost_equal(camera.zoom, Float32(1), atol=TOLERANCE)
    _near(camera.position, 0, 0, 5)
    _near(controls.target, 0, 0, 0)


def test_the_distance_is_kept_in_range() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    controls.max_distance = Length(5.1, METER)
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5.1)
    controls.min_distance = Length(5.0, METER)
    for _ in range(3):
        controls.handle(InputEvent(WHEEL, wheel=-1), SIZE, SIZE)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5)
    # With both zoom and pan off, the limits are not read.
    controls.no_zoom = True
    controls.no_pan = True
    controls.min_distance = Length(8.0, METER)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 5)
    controls.no_zoom = False
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 8)
    controls.no_zoom = True
    controls.no_pan = False
    controls.min_distance = Length(9.0, METER)
    _ = controls.update(camera)
    _near(camera.position, 0, 0, 9)


def test_a_zoom_past_the_target_is_no_zoom() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    controls.handle(
        InputEvent(POINTER_DOWN, button=MIDDLE, x=50, y=99), SIZE, SIZE
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=MIDDLE, x=50, y=0), SIZE, SIZE
    )
    assert_false(controls.update(camera))
    _near(camera.position, 0, 0, 5)


def test_an_orthographic_camera_with_every_action_off_stays() raises:
    var camera = _ortho()
    var controls = TrackballControls(camera)
    controls.no_rotate = True
    controls.no_zoom = True
    controls.no_pan = True
    assert_false(controls.update(camera))
    controls.reset(camera)
    _near(camera.position, 0, 0, 5)


def test_static_moving_stops_at_once() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.static_moving = True
    _drag(controls, PRIMARY, 60, 40, release=True)
    _ = controls.update(camera)
    var after = camera.position
    assert_false(controls.update(camera))
    _near(camera.position, after.x, after.y, after.z)
    _drag(controls, SECONDARY, 60, 50, release=True)
    _ = controls.update(camera)
    assert_false(controls.update(camera))


def test_keys_choose_the_action() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    # Holding D makes the primary button pan.
    _key(controls, 100)
    _drag(controls, PRIMARY, 60, 50, release=True)
    _ = controls.update(camera)
    _near(controls.target, -0.15, 0, 0)
    _let_go(controls)
    # Holding S makes it zoom, and a capital is its small letter.
    _key(controls, 83)
    _drag(controls, PRIMARY, 50, 60, release=True)
    controls.static_moving = True
    _ = controls.update(camera)
    # What was left of the pan applies too: 0.08 of the view at 5.6 meters.
    _near(camera.position, -0.2844, 0, 5.6)
    _let_go(controls)
    # Holding A makes the secondary button rotate.
    _key(controls, 97)
    _drag(controls, SECONDARY, 60, 50, release=True)
    _ = controls.update(camera)
    assert_true(camera.position.x < -0.5)


def test_a_key_waits_for_the_last_to_go_up() raises:
    var controls = TrackballControls(_camera())
    # A key that chooses nothing stops the listening, as in three.js, so a
    # later D does nothing until a key goes up.
    _key(controls, 120)
    _key(controls, 100)
    _drag(controls, PRIMARY, 60, 50, release=True)
    var camera = _camera()
    _ = controls.update(camera)
    _near(controls.target, 0, 0, 0)
    _let_go(controls)
    _key(controls, 100)
    _let_go(controls)
    # A key while one is held does not change the action.
    _key(controls, 97)
    controls.handle(InputEvent(KEY_UP, key=Key(120)), SIZE, SIZE)
    _key(controls, 97)
    _key(controls, 100)


def test_a_key_goes_up_after_its_timeout() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.key_timeout = Duration(0.1, SECOND)
    _key(controls, 100)
    _ = controls.update(camera, Duration(0.2, SECOND))
    # D is no longer held, so the primary button rotates.
    _drag(controls, PRIMARY, 60, 50, release=True)
    _ = controls.update(camera)
    _near(controls.target, 0, 0, 0)
    assert_true(camera.position.x < -0.5)


def test_an_action_turned_off_does_nothing() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.no_rotate = True
    controls.no_zoom = True
    controls.no_pan = True
    for code in [97, 115, 100]:
        _key(controls, code)
        _let_go(controls)
    _drag(controls, PRIMARY, 60, 40, release=True)
    _drag(controls, MIDDLE, 60, 40, release=True)
    _drag(controls, SECONDARY, 60, 40, release=True)
    controls.handle(InputEvent(WHEEL, wheel=1), SIZE, SIZE)
    assert_false(controls.update(camera))
    _near(camera.position, 0, 0, 5)
    # A move with no button held does nothing either.
    controls.no_rotate = False
    controls.handle(InputEvent(POINTER_DOWN, button=NO_BUTTON), SIZE, SIZE)
    controls.handle(InputEvent(POINTER_MOVE, x=10, y=10), SIZE, SIZE)
    controls.handle(InputEvent(RESIZE, x=10, y=10), SIZE, SIZE)
    assert_false(controls.update(camera))


def test_disabled_controls_ignore_input() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    controls.enabled = False
    _drag(controls, PRIMARY, 60, 40, release=True)
    assert_false(controls.update(camera))


def test_reset_puts_the_camera_back() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    _drag(controls, PRIMARY, 60, 40, release=True)
    _ = controls.update(camera)
    controls.reset(camera)
    _near(camera.position, 0, 0, 5)
    _near(camera.up, 0, 1, 0)
    # A turn still dying away goes on after a reset, as in three.js.
    controls.static_moving = True
    assert_false(controls.update(camera))


def test_bad_input_is_refused() raises:
    var camera = _camera()
    var controls = TrackballControls(camera)
    with assert_raises(contains="kind"):
        controls.handle(InputEvent(InputKind(9)), SIZE, SIZE)
    with assert_raises(contains="button"):
        controls.handle(
            InputEvent(POINTER_DOWN, button=PointerButton(5)), SIZE, SIZE
        )
    with assert_raises(contains="key"):
        controls.handle(InputEvent(KEY_DOWN, key=Key(200)), SIZE, SIZE)
    with assert_raises(contains="size"):
        controls.handle(InputEvent(WHEEL), 0, SIZE)
    with assert_raises(contains="size"):
        controls.handle(InputEvent(WHEEL), SIZE, 0)
    controls.primary_action = OrbitAction(7)
    with assert_raises(contains="action"):
        controls.handle(InputEvent(POINTER_DOWN, button=PRIMARY), SIZE, SIZE)
    controls.rotate_key = Key(-5)
    with assert_raises(contains="key"):
        _key(controls, 97)
    controls.rotate_key = Key(97)
    controls.zoom_key = Key(-5)
    with assert_raises(contains="key"):
        _key(controls, 97)
    controls.zoom_key = Key(115)
    controls.pan_key = Key(-5)
    with assert_raises(contains="key"):
        _key(controls, 97)
    with assert_raises(contains="negative"):
        _ = controls.update(camera, Duration(-1.0, SECOND))
    var ortho = _ortho()
    with assert_raises(contains="negative"):
        _ = controls.update(ortho, Duration(-1.0, SECOND))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
