# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.held_keys` and `controls.camera_frame`."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.held_keys import HOLD_TIMEOUT, HeldKeys, physical_key
from controls.input import ARROW_UP, Key
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime TOLERANCE = Float64(1e-5)


def _seconds(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


def test_a_capital_is_its_small_letter() raises:
    assert_equal(physical_key(Key(87)).value, 119)
    assert_equal(physical_key(Key(65)).value, 97)
    assert_equal(physical_key(Key(90)).value, 122)
    assert_equal(physical_key(Key(64)).value, 64)
    assert_equal(physical_key(Key(91)).value, 91)
    assert_equal(physical_key(ARROW_UP).value, ARROW_UP.value)


def test_a_key_is_held_until_its_timeout() raises:
    var held = HeldKeys()
    assert_almost_equal(held.timeout.to(SECOND), Float32(0.3), atol=TOLERANCE)
    assert_equal(len(held.advance(_seconds(0.1))), 0)
    held.press(Key(119))
    held.press(Key(87))
    held.press(ARROW_UP)
    assert_equal(held.count(), 2)
    assert_true(held.is_held(Key(87)))
    assert_false(held.is_held(Key(115)))
    assert_equal(len(held.advance(_seconds(0.2))), 0)
    # A repeat starts the time again.
    held.press(Key(119))
    var gone = held.advance(_seconds(0.2))
    assert_equal(len(gone), 1)
    assert_equal(gone[0].value, ARROW_UP.value)
    assert_true(held.is_held(Key(119)))
    gone = held.advance(_seconds(0.2))
    assert_equal(gone[0].value, 119)
    assert_equal(held.count(), 0)


def test_a_key_up_lets_go_at_once() raises:
    var held = HeldKeys(timeout=_seconds(1))
    held.press(Key(97))
    held.press(Key(100))
    assert_false(held.release(Key(115)))
    assert_true(held.release(Key(65)))
    assert_false(held.is_held(Key(97)))
    assert_true(held.is_held(Key(100)))


def test_the_time_and_the_timeout_are_checked() raises:
    var held = HeldKeys()
    with assert_raises(contains="negative"):
        _ = held.advance(_seconds(-1))
    held.timeout = _seconds(0)
    with assert_raises(contains="timeout"):
        _ = held.advance(_seconds(1))
    assert_almost_equal(HOLD_TIMEOUT.to(SECOND), Float32(0.3), atol=TOLERANCE)


def test_a_frame_holds_the_cameras_axes() raises:
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var frame = CameraFrame.of(camera)
    assert_almost_equal(frame.right.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(frame.above.y, Float32(1), atol=TOLERANCE)
    assert_almost_equal(frame.back.z, Float32(1), atol=TOLERANCE)
    assert_almost_equal(frame.reach, Float32(5), atol=TOLERANCE)
    frame.translate(Vector3(1, 2, -1))
    assert_almost_equal(frame.position.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(frame.position.y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(frame.position.z, Float32(4), atol=TOLERANCE)
    # A quarter turn about the camera's up: it looks along -x.
    frame.turn(
        Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(90.0, DEGREE))
    )
    assert_almost_equal(frame.forward().x, Float32(-1), atol=TOLERANCE)
    var rotation = frame.rotation()
    assert_almost_equal(
        rotation.transform_direction(Vector3(0, 0, -1)).x,
        Float32(-1),
        atol=TOLERANCE,
    )
    frame.place(camera)
    assert_almost_equal(camera.target.x, Float32(-4), atol=TOLERANCE)
    assert_almost_equal(camera.target.z, Float32(4), atol=TOLERANCE)


def test_a_frame_places_an_orthographic_camera() raises:
    var camera = OrthographicCamera(
        Length(-5.0, METER),
        Length(5.0, METER),
        Length(5.0, METER),
        Length(-5.0, METER),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var frame = CameraFrame.of(camera)
    frame.turn(
        Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(90.0, DEGREE))
    )
    frame.place(camera)
    # A roll a quarter turn left: up is now -x.
    assert_almost_equal(camera.up.x, Float32(-1), atol=TOLERANCE)
    assert_almost_equal(camera.target.z, Float32(0), atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
