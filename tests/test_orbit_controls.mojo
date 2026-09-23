# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.orbit_controls`.

Every test starts from a camera five meters up +z from the origin, with a
field of view of 90 degrees and a view 100 pixels high. At that distance
the view covers ten meters top to bottom, so a pixel of pan is a tenth of
a meter, and a drag of 25 pixels is a quarter turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    InputEvent,
    InputKind,
    KEY_DOWN,
    Key,
    MIDDLE,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
    WHEEL,
)
from controls.orbit_controls import (
    DOLLY,
    NO_ACTION,
    OrbitAction,
    OrbitControls,
    PAN,
    ROTATE,
)
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime HEIGHT = 100
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


def _at(camera: PerspectiveCamera, x: Float32, y: Float32, z: Float32) raises:
    """Assert where the camera is.

    Args:
        camera: The camera.
        x: The expected x.
        y: The expected y.
        z: The expected z.

    Raises:
        Error: If it is elsewhere.
    """
    assert_almost_equal(camera.position.x, x, atol=TOLERANCE)
    assert_almost_equal(camera.position.y, y, atol=TOLERANCE)
    assert_almost_equal(camera.position.z, z, atol=TOLERANCE)


def _drag(
    mut controls: OrbitControls,
    camera: PerspectiveCamera,
    button: PointerButton,
    dx: Int,
    dy: Int,
    *,
    shift: Bool = False,
    ctrl: Bool = False,
) raises:
    """Press a button at (50, 50), move by (dx, dy), and let go.

    Args:
        controls: The controls.
        camera: The camera.
        button: The button.
        dx: Pixels right.
        dy: Pixels down.
        shift: Whether Shift is held at the press.
        ctrl: Whether Ctrl is held at the press.

    Raises:
        Error: If an event is refused.
    """
    controls.handle(
        InputEvent(
            POINTER_DOWN, button=button, x=50, y=50, shift=shift, ctrl=ctrl
        ),
        camera,
        HEIGHT,
    )
    controls.handle(
        InputEvent(POINTER_MOVE, button=button, x=50 + dx, y=50 + dy),
        camera,
        HEIGHT,
    )
    controls.handle(
        InputEvent(POINTER_UP, button=button, x=50 + dx, y=50 + dy),
        camera,
        HEIGHT,
    )


def _key(
    mut controls: OrbitControls,
    camera: PerspectiveCamera,
    key: Key,
    *,
    shift: Bool = False,
    ctrl: Bool = False,
) raises:
    """Press a key.

    Args:
        controls: The controls.
        camera: The camera.
        key: The key.
        shift: Whether Shift is held.
        ctrl: Whether Ctrl is held.

    Raises:
        Error: If the event is refused.
    """
    controls.handle(
        InputEvent(KEY_DOWN, key=key, shift=shift, ctrl=ctrl), camera, HEIGHT
    )


def test_an_action_knows_its_values() raises:
    assert_true(NO_ACTION.is_valid())
    assert_true(PAN.is_valid())
    assert_false(OrbitAction(-1).is_valid())
    assert_false(OrbitAction(4).is_valid())


def test_nothing_pending_moves_nothing() raises:
    var camera = _camera()
    var controls = OrbitControls()
    assert_false(controls.update(camera, _frame()))
    _at(camera, 0, 0, 5)


def test_a_drag_the_height_of_a_quarter_turn_rotates_a_quarter() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _drag(controls, camera, PRIMARY, 25, 0)
    assert_true(controls.update(camera, _frame()))
    # Dragging right swings the camera to the left of the target.
    _at(camera, -5, 0, 0)
    assert_almost_equal(camera.target.x, Float32(0), atol=TOLERANCE)


def test_a_drag_down_rotates_the_camera_up() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _drag(controls, camera, PRIMARY, 0, 10)
    _ = controls.update(camera, _frame())
    # A drag down a tenth of the height lifts the camera a tenth of a turn.
    var lifted = Float32(2 * pi / 10)
    _at(camera, 0, 5 * sin(lifted), 5 * cos(lifted))


def test_the_poles_are_never_reached() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _drag(controls, camera, PRIMARY, 0, 200)
    _ = controls.update(camera, _frame())
    # Straight above, and still on the side it started: it did not go over
    # the top.
    assert_true(camera.position.y > Float32(4.99))
    assert_true(camera.position.z > 0)


def test_a_camera_on_its_target_stays_there() raises:
    var camera = _camera()
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, 0))
    var controls = OrbitControls()
    assert_false(controls.update(camera, _frame()))
    _at(camera, 0, 0, 0)


def test_a_wheel_notch_dollies_by_a_twentieth() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, HEIGHT)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 4.75)
    controls.handle(InputEvent(WHEEL, wheel=1), camera, HEIGHT)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5)


def test_the_wheel_waits_for_a_drag_and_for_zoom() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.handle(
        InputEvent(POINTER_DOWN, button=PRIMARY, x=1, y=1), camera, HEIGHT
    )
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, HEIGHT)
    assert_false(controls.update(camera, _frame()))
    controls.handle(
        InputEvent(POINTER_UP, button=PRIMARY, x=1, y=1), camera, HEIGHT
    )
    controls.enable_zoom = False
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, HEIGHT)
    assert_false(controls.update(camera, _frame()))


def test_a_middle_drag_dollies() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _drag(controls, camera, MIDDLE, 0, 100)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, Float32(5) / Float32(0.95))
    _drag(controls, camera, MIDDLE, 0, -100)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5)
    # A sideways drag does not dolly.
    _drag(controls, camera, MIDDLE, 30, 0)
    assert_false(controls.update(camera, _frame()))


def test_a_right_drag_pans_the_target_with_the_camera() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _drag(controls, camera, SECONDARY, 10, 20)
    _ = controls.update(camera, _frame())
    # The content follows the pointer right and down, so the view moves
    # left and up: a meter left, two meters up.
    _at(camera, -1, 2, 5)
    assert_almost_equal(controls.target.x, Float32(-1), atol=TOLERANCE)
    assert_almost_equal(controls.target.y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(camera.target.y, Float32(2), atol=TOLERANCE)


def test_shift_or_ctrl_swaps_rotate_and_pan() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _drag(controls, camera, PRIMARY, 10, 0, shift=True)
    _ = controls.update(camera, _frame())
    _at(camera, -1, 0, 5)
    camera = _camera()
    controls = OrbitControls()
    _drag(controls, camera, SECONDARY, 25, 0, ctrl=True)
    _ = controls.update(camera, _frame())
    _at(camera, -5, 0, 0)
    # A dolly is not swapped.
    camera = _camera()
    controls = OrbitControls()
    _drag(controls, camera, MIDDLE, 0, 100, shift=True)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, Float32(5) / Float32(0.95))


def test_a_disabled_action_does_nothing() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.enable_rotate = False
    controls.enable_zoom = False
    controls.enable_pan = False
    _drag(controls, camera, PRIMARY, 25, 0)
    _drag(controls, camera, MIDDLE, 0, 100)
    _drag(controls, camera, SECONDARY, 10, 10)
    assert_false(controls.update(camera, _frame()))
    controls = OrbitControls()
    controls.enabled = False
    _drag(controls, camera, PRIMARY, 25, 0)
    assert_false(controls.update(camera, _frame()))


def test_a_move_with_no_button_held_does_nothing() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.handle(
        InputEvent(POINTER_MOVE, button=NO_BUTTON, x=80, y=80), camera, HEIGHT
    )
    # A press with no button starts nothing either.
    _drag(controls, camera, NO_BUTTON, 25, 0)
    assert_false(controls.update(camera, _frame()))


def test_the_buttons_can_be_remapped() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.primary_action = PAN
    controls.secondary_action = ROTATE
    controls.middle_action = NO_ACTION
    _drag(controls, camera, PRIMARY, 10, 0)
    _ = controls.update(camera, _frame())
    _at(camera, -1, 0, 5)
    _drag(controls, camera, MIDDLE, 0, 100)
    assert_false(controls.update(camera, _frame()))
    assert_true(controls.action_of(SECONDARY) == ROTATE)
    assert_true(controls.action_of(NO_BUTTON) == NO_ACTION)
    controls.middle_action = DOLLY
    assert_true(controls.action_of(MIDDLE) == DOLLY)


def test_arrows_pan_and_with_a_modifier_rotate() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.key_pan_speed = 10
    _key(controls, camera, ARROW_UP)
    _key(controls, camera, ARROW_LEFT)
    _ = controls.update(camera, _frame())
    # Up moves the content up and the view down; left moves the view right.
    _at(camera, -1, 1, 5)
    _key(controls, camera, ARROW_DOWN)
    _key(controls, camera, ARROW_RIGHT)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5)
    # Twenty-five presses with Shift are a quarter turn at this height.
    for _ in range(25):
        _key(controls, camera, ARROW_LEFT, shift=True)
    _ = controls.update(camera, _frame())
    _at(camera, -5, 0, 0)
    for _ in range(25):
        _key(controls, camera, ARROW_RIGHT, ctrl=True)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5)
    for _ in range(12):
        _key(controls, camera, ARROW_DOWN, shift=True)
        _key(controls, camera, ARROW_UP, shift=True)
    assert_false(controls.update(camera, _frame()))


def test_keys_that_do_nothing() raises:
    var camera = _camera()
    var controls = OrbitControls()
    _key(controls, camera, Key(113))
    controls.enable_rotate = False
    _key(controls, camera, ARROW_LEFT, shift=True)
    controls.enable_pan = False
    _key(controls, camera, ARROW_LEFT)
    assert_false(controls.update(camera, _frame()))


def test_the_distance_is_limited() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.min_distance = Length(4.9, METER)
    controls.max_distance = Length(5.1, METER)
    for _ in range(5):
        controls.handle(InputEvent(WHEEL, wheel=-1), camera, HEIGHT)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 4.9)
    for _ in range(5):
        controls.handle(InputEvent(WHEEL, wheel=1), camera, HEIGHT)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5.1)


def test_the_polar_angle_is_limited() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.min_polar_angle = Angle(90.0, DEGREE)
    controls.max_polar_angle = Angle(90.0, DEGREE)
    _drag(controls, camera, PRIMARY, 0, 20)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5)


def test_the_azimuth_is_limited() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.min_azimuth_angle = Angle(-30.0, DEGREE)
    controls.max_azimuth_angle = Angle(30.0, DEGREE)
    _drag(controls, camera, PRIMARY, 25, 0)
    _ = controls.update(camera, _frame())
    _at(camera, -2.5, 0, Float32(5) * Float32(0.8660254))
    # Only one limit set is no limit.
    camera = _camera()
    controls = OrbitControls()
    controls.min_azimuth_angle = Angle(-30.0, DEGREE)
    _drag(controls, camera, PRIMARY, 25, 0)
    _ = controls.update(camera, _frame())
    _at(camera, -5, 0, 0)


def test_an_azimuth_range_through_a_half_turn() raises:
    # From 170 degrees round through 180 to -170: behind the target. A
    # camera in front goes to the nearer limit.
    var camera = _camera()
    var controls = OrbitControls()
    controls.min_azimuth_angle = Angle(170.0, DEGREE)
    controls.max_azimuth_angle = Angle(-170.0, DEGREE)
    _drag(controls, camera, PRIMARY, -1, 0)
    _ = controls.update(camera, _frame())
    assert_true(camera.position.z < -4.9)
    assert_true(camera.position.x > 0)
    camera = _camera()
    controls = OrbitControls()
    controls.min_azimuth_angle = Angle(170.0, DEGREE)
    controls.max_azimuth_angle = Angle(-170.0, DEGREE)
    _drag(controls, camera, PRIMARY, 1, 0)
    _ = controls.update(camera, _frame())
    assert_true(camera.position.z < -4.9)
    assert_true(camera.position.x < 0)


def test_limits_past_a_half_turn_are_wrapped() raises:
    # -200 degrees is 160, and 200 is -160: the range behind the target.
    var camera = _camera()
    var controls = OrbitControls()
    controls.min_azimuth_angle = Angle(-200.0, DEGREE)
    controls.max_azimuth_angle = Angle(200.0, DEGREE)
    _drag(controls, camera, PRIMARY, 1, 0)
    _ = controls.update(camera, _frame())
    assert_true(camera.position.z < -4.6)


def test_damping_spreads_a_change_over_frames() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.enable_damping = True
    controls.damping_factor = 0.5
    controls.handle(InputEvent(WHEEL, wheel=-1), camera, HEIGHT)
    controls.rotate_left(Angle(-90.0, DEGREE))
    _ = controls.update(camera, _frame())
    # Half the turn, and the whole dolly: three.js damps no dolly.
    var radius = Float32(4.75)
    var side = radius / sqrt(Float32(2))
    _at(camera, side, 0, side)
    _ = controls.update(camera, _frame())
    # A quarter more.
    assert_true(camera.position.x > side)
    for _ in range(40):
        _ = controls.update(camera, _frame())
    _at(camera, radius, 0, 0)


def test_auto_rotate_turns_while_no_button_is_held() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.auto_rotate = True
    # Two turns a minute is half a turn in fifteen seconds.
    _ = controls.update(camera, Duration(15.0, SECOND))
    _at(camera, 0, 0, -5)
    controls.handle(
        InputEvent(POINTER_DOWN, button=PRIMARY, x=1, y=1), camera, HEIGHT
    )
    assert_false(controls.update(camera, Duration(15.0, SECOND)))


def test_rotate_up_and_left_by_an_angle() raises:
    var camera = _camera()
    var controls = OrbitControls(Vector3(0, 0, 0))
    controls.rotate_left(Angle(90.0, DEGREE))
    _ = controls.update(camera, _frame())
    _at(camera, -5, 0, 0)
    controls.rotate_up(Angle(-45.0, DEGREE))
    _ = controls.update(camera, _frame())
    var side = Float32(5) / sqrt(Float32(2))
    _at(camera, -side, -side, 0)


def test_dolly_by_a_factor() raises:
    var camera = _camera()
    var controls = OrbitControls()
    controls.dolly_in(0.5)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 2.5)
    controls.dolly_out(0.5)
    _ = controls.update(camera, _frame())
    _at(camera, 0, 0, 5)
    with assert_raises(contains="dolly factor"):
        controls.dolly_in(0)
    with assert_raises(contains="dolly factor"):
        controls.dolly_in(2)
    with assert_raises(contains="dolly factor"):
        controls.dolly_out(0)
    with assert_raises(contains="dolly factor"):
        controls.dolly_out(2)


def test_invalid_input_is_refused() raises:
    var camera = _camera()
    var controls = OrbitControls()
    with assert_raises(contains="input kind"):
        controls.handle(InputEvent(InputKind(9)), camera, HEIGHT)
    with assert_raises(contains="pointer button"):
        controls.handle(
            InputEvent(POINTER_DOWN, button=PointerButton(7)), camera, HEIGHT
        )
    with assert_raises(contains="Invalid key"):
        controls.handle(InputEvent(KEY_DOWN, key=Key(500)), camera, HEIGHT)
    with assert_raises(contains="viewport height"):
        controls.handle(InputEvent(WHEEL, wheel=1), camera, 0)
    with assert_raises(contains="viewport height"):
        controls.pan(1, 1, camera, -1)
    controls.primary_action = OrbitAction(8)
    with assert_raises(contains="orbit action"):
        controls.handle(
            InputEvent(POINTER_DOWN, button=PRIMARY), camera, HEIGHT
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
