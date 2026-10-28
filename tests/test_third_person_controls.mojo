# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The third-person camera: its orbit, its trail, its spring and its
floor."""

from cameras.perspective_camera import PerspectiveCamera
from controls.third_person_controls import (
    ThirdPersonControls,
    ground_direction,
    turn_toward,
    wrap_angle,
    yaw_of,
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
    DEGREE,
    DEGREE_PER_SECOND,
    METER,
    PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    AngularVelocity,
    Duration,
    Frequency,
    Length,
)


def _camera() raises -> PerspectiveCamera:
    """Return a camera of a 16 by 9 view."""
    return PerspectiveCamera(
        Angle(50.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(100.0, METER),
    )


def test_a_yaw_points_along_the_ground() raises:
    var ahead = ground_direction(Angle(0.0, RADIAN), 1, 0)
    assert_almost_equal(ahead.z, -1, atol=1e-6)
    var right = ground_direction(Angle(0.0, RADIAN), 0, 1)
    assert_almost_equal(right.x, 1, atol=1e-6)
    var turned = ground_direction(Angle(90.0, DEGREE), 1, 0)
    assert_almost_equal(turned.x, -1, atol=1e-6)
    assert_almost_equal(yaw_of(turned).to(DEGREE), 90, atol=1e-3)
    assert_almost_equal(yaw_of(Vector3(0, 0, -2)).to(DEGREE), 0, atol=1e-3)


def test_angles_wrap_and_turn_the_short_way() raises:
    assert_almost_equal(
        wrap_angle(Angle(270.0, DEGREE)).to(DEGREE), -90, atol=1e-3
    )
    assert_almost_equal(
        wrap_angle(Angle(-200.0, DEGREE)).to(DEGREE), 160, atol=1e-3
    )
    var most = Angle(10.0, DEGREE)
    var turned = turn_toward(Angle(170.0, DEGREE), Angle(-170.0, DEGREE), most)
    assert_almost_equal(turned.to(DEGREE), 180, atol=1e-2)
    var near = turn_toward(Angle(0.0, DEGREE), Angle(4.0, DEGREE), most)
    assert_almost_equal(near.to(DEGREE), 4, atol=1e-3)
    var back = turn_toward(Angle(0.0, DEGREE), Angle(-90.0, DEGREE), most)
    assert_almost_equal(back.to(DEGREE), -10, atol=1e-3)


def test_the_look_stick_turns_the_orbit_within_its_pitches() raises:
    var view = ThirdPersonControls()
    view.yaw_speed = AngularVelocity(90.0, DEGREE_PER_SECOND)
    view.turn(1, 0, Duration(1.0, SECOND))
    assert_almost_equal(view.yaw.to(DEGREE), -90, atol=1e-3)
    view.turn(0, 1, Duration(10.0, SECOND))
    assert_almost_equal(view.pitch.to(DEGREE), 25, atol=1e-3)
    view.turn(0, -5, Duration(10.0, SECOND))
    assert_almost_equal(view.pitch.to(DEGREE), -70, atol=1e-3)
    with assert_raises(contains="negative"):
        view.turn(0, 0, Duration(-1.0, SECOND))


def test_the_camera_trails_behind_a_moving_character() raises:
    var view = ThirdPersonControls()
    view.trail(Angle(90.0, DEGREE), 0.5, Duration(1.0, SECOND))
    assert_almost_equal(view.yaw.to(DEGREE), 30, atol=1e-3)
    view.trail(Angle(90.0, DEGREE), 0, Duration(1.0, SECOND))
    assert_almost_equal(view.yaw.to(DEGREE), 30, atol=1e-3)


def test_the_focus_springs_toward_its_target() raises:
    var view = ThirdPersonControls()
    assert_false(view.focused)
    view.follow_target(Vector3(1, 2, 3), Duration(0.1, SECOND))
    assert_true(view.focused)
    assert_almost_equal(view.focus.x, 1, atol=1e-6)
    view.follow = Frequency(1.0, PER_SECOND)
    view.follow_target(Vector3(3, 2, 3), Duration(1.0, SECOND))
    # 1 - exp(-1) of the gap of 2 meters.
    assert_almost_equal(view.focus.x, 1 + 2 * 0.6321206, atol=1e-4)


def test_the_eye_stands_behind_and_above_the_focus() raises:
    var view = ThirdPersonControls(
        Angle(0.0, RADIAN), Angle(-30.0, DEGREE), Length(4.0, METER)
    )
    view.follow_target(Vector3(0, 1, 0), Duration(0.0, SECOND))
    var look = view.look()
    assert_almost_equal(look.length(), 1, atol=1e-5)
    var eye = view.eye()
    assert_almost_equal(eye.z, 4 * 0.8660254, atol=1e-4)
    assert_almost_equal(eye.y, 1 + 2, atol=1e-4)
    var camera = _camera()
    view.place(camera, Length(0.0, METER))
    assert_almost_equal(camera.position.y, 3, atol=1e-4)
    # A hill under the eye lifts it, and the camera still looks at the
    # focus.
    view.place(camera, Length(5.0, METER))
    assert_almost_equal(camera.position.y, 5.3, atol=1e-4)
    with assert_raises(contains="floor"):
        view.place(camera, Length(Float32.MAX * 2, METER))


def test_a_camera_comes_in_before_a_wall_and_stays_under_a_ceiling() raises:
    var view = ThirdPersonControls(
        Angle(0.0, RADIAN), Angle(-30.0, DEGREE), Length(4.0, METER)
    )
    view.follow_target(Vector3(0, 1, 0), Duration(0.0, SECOND))
    var camera = _camera()
    var sky = Length(1.0e30, METER)
    # The whole way, under the open sky: as `place` stands it.
    view.place_within(camera, Length(0.0, METER), sky, 1)
    assert_almost_equal(camera.position.y, 3, atol=1e-4)
    assert_almost_equal(camera.position.z, 4 * 0.8660254, atol=1e-4)
    # Half the way, before a wall.
    view.place_within(camera, Length(0.0, METER), sky, 0.5)
    assert_almost_equal(camera.position.y, 2, atol=1e-4)
    assert_almost_equal(camera.position.z, 2 * 0.8660254, atol=1e-4)
    # Under a ceiling at 2.5 meters, the eye stays a clearance below it.
    view.place_within(camera, Length(0.0, METER), Length(2.5, METER), 1)
    assert_almost_equal(camera.position.y, 2.2, atol=1e-4)
    # Over a floor at 2.9 meters, the floor wins.
    view.place_within(camera, Length(2.9, METER), Length(2.5, METER), 0.5)
    assert_almost_equal(camera.position.y, 3.2, atol=1e-4)
    with assert_raises(contains="floor"):
        view.place_within(camera, Length(Float32.MAX * 2, METER), sky, 1)
    var nan = Float32(0) / Float32(0)
    with assert_raises(contains="ceiling"):
        view.place_within(camera, Length(0.0, METER), Length(nan, METER), 1)
    with assert_raises(contains="reach"):
        view.place_within(camera, Length(0.0, METER), sky, -0.1)
    with assert_raises(contains="reach"):
        view.place_within(camera, Length(0.0, METER), sky, 1.5)


def test_a_camera_that_cannot_follow_is_refused() raises:
    var view = ThirdPersonControls()
    view.check()
    view.distance = Length(0.0, METER)
    with assert_raises(contains="distance"):
        view.check()
    view = ThirdPersonControls()
    view.lowest_pitch = Angle(30.0, DEGREE)
    with assert_raises(contains="pitches"):
        view.check()
    view = ThirdPersonControls()
    view.highest_pitch = Angle(95.0, DEGREE)
    with assert_raises(contains="pitches"):
        view.check()
    view = ThirdPersonControls()
    view.lowest_pitch = Angle(-95.0, DEGREE)
    with assert_raises(contains="pitches"):
        view.check()
    view = ThirdPersonControls()
    view.trail_speed = AngularVelocity(-1.0, DEGREE_PER_SECOND)
    with assert_raises(contains="speed"):
        view.check()
    view = ThirdPersonControls()
    view.yaw_speed = AngularVelocity(1.0e9, DEGREE_PER_SECOND)
    with assert_raises(contains="million"):
        view.check()
    view = ThirdPersonControls()
    view.follow = Frequency(0.0, PER_SECOND)
    with assert_raises(contains="follow"):
        view.check()
    view = ThirdPersonControls()
    view.clearance = Length(-1.0, METER)
    with assert_raises(contains="clearance"):
        view.check()
    view = ThirdPersonControls()
    view.yaw = Angle(Float32.MAX * 2, RADIAN)
    with assert_raises(contains="yaw"):
        view.check()
    view = ThirdPersonControls()
    view.pitch = Angle(Float32.MAX * 2, RADIAN)
    with assert_raises(contains="pitch"):
        view.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
