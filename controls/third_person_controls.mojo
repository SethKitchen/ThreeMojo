# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera that follows a character from behind and above, as a game's
third-person camera does.

three.js has no such control. Games put it together from the same parts:

1. **The focus.** The camera looks at a point above the character's feet.
   The focus follows that point with a spring, so a step or a jump does
   not shake the view. `follow` sets how fast it catches up.
2. **The orbit.** A yaw and a pitch say where the camera stands round the
   focus, `distance` away. A look stick turns them: full right turns the
   yaw at `yaw_speed`, and full up turns the pitch at `pitch_speed`. The
   pitch stays from `lowest_pitch` to `highest_pitch`.
3. **The trail.** While the character moves and the look stick rests, the
   yaw turns toward the character's heading at `trail_speed`, so the
   camera comes round behind it.
4. **The floor.** The eye never goes below `clearance` above the ground
   under it. The caller gives that height, because only the scene knows
   it. The camera then still looks at the focus.

The yaw is the way the camera looks, about +y. Yaw 0 looks toward -z, and
a positive yaw turns toward -x, as `Object3D.rotate_y` turns. So the
camera looks along `(-sin yaw, 0, -cos yaw)`, and its right is
`(cos yaw, 0, -sin yaw)`. A character moves along the same two axes:
see `ground_direction`.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.finite import require_finite, require_positive_finite
from math.utils import clamp
from math.vector3 import Vector3
from std.math import atan2, cos, exp, floor, pi, sin
from units.si import (
    DEGREE,
    DEGREE_PER_SECOND,
    METER,
    PER_SECOND,
    RADIAN,
    RADIAN_PER_SECOND,
    SECOND,
    Angle,
    AngularVelocity,
    Duration,
    Frequency,
    Length,
)


def ground_direction(yaw: Angle, forward: Float32, right: Float32) -> Vector3:
    """Return a direction on the ground, from a yaw and two amounts.

    Args:
        yaw: The way to look, about +y. Yaw 0 looks toward -z.
        forward: How far along the yaw's way.
        right: How far to its right.

    Returns:
        `forward` times `(-sin yaw, 0, -cos yaw)` plus `right` times
        `(cos yaw, 0, -sin yaw)`. It is not normalized.
    """
    var a = yaw.to(RADIAN)
    var s = sin(a)
    var c = cos(a)
    return Vector3(-s * forward + c * right, 0, -c * forward - s * right)


def yaw_of(direction: Vector3) -> Angle:
    """Return the yaw that looks along a direction on the ground.

    Args:
        direction: The direction. Its y is not used.

    Returns:
        The yaw, from -pi to pi radians. Zero for no direction.
    """
    return Angle(atan2(-direction.x, -direction.z), RADIAN)


def wrap_angle(angle: Angle) -> Angle:
    """Return the same turn as an angle from -pi to pi radians.

    Args:
        angle: The angle. It must be finite.

    Returns:
        The angle plus or minus whole turns, from -pi to pi.
    """
    var a = angle.to(RADIAN)
    return Angle(a - floor((a + pi) / (2 * pi)) * 2 * pi, RADIAN)


def turn_toward(start: Angle, goal: Angle, most: Angle) -> Angle:
    """Return `start` turned toward `goal` the short way, by at most `most`.

    Args:
        start: The angle now.
        goal: The angle to turn toward.
        most: The largest turn. It must not be negative.

    Returns:
        The turned angle, wrapped from -pi to pi radians.
    """
    var gap = wrap_angle(Angle(goal.to(RADIAN) - start.to(RADIAN), RADIAN))
    var step = clamp(gap.to(RADIAN), -most.to(RADIAN), most.to(RADIAN))
    return wrap_angle(Angle(start.to(RADIAN) + step, RADIAN))


struct ThirdPersonControls(Copyable, Movable):
    """A camera that orbits a focus above a character and follows it."""

    # Where the camera stands round the focus: its yaw and its pitch. A
    # negative pitch looks down.
    var yaw: Angle
    var pitch: Angle
    # How far the eye is from the focus.
    var distance: Length
    # The lowest and the highest pitch.
    var lowest_pitch: Angle
    var highest_pitch: Angle
    # How fast a full look stick turns the yaw and the pitch.
    var yaw_speed: AngularVelocity
    var pitch_speed: AngularVelocity
    # How fast the yaw turns behind a moving character. Zero never turns.
    var trail_speed: AngularVelocity
    # How fast the focus catches up with the character: it closes this
    # share of the gap each second, as `1 - exp(-follow t)`.
    var follow: Frequency
    # How far above the ground the eye must stay.
    var clearance: Length
    # The point the camera looks at, after the spring.
    var focus: Vector3
    # Whether `focus` holds a point yet.
    var focused: Bool

    def __init__(
        out self,
        yaw: Angle = Angle(0.0, RADIAN),
        pitch: Angle = Angle(-15.0, DEGREE),
        distance: Length = Length(4.0, METER),
    ):
        """Create a camera that looks from behind and a little above.

        Args:
            yaw: The way the camera looks, about +y. Yaw 0 looks toward -z.
            pitch: How far it looks down, as a negative angle.
            distance: How far the eye is from the focus.
        """
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        self.lowest_pitch = Angle(-70.0, DEGREE)
        self.highest_pitch = Angle(25.0, DEGREE)
        self.yaw_speed = AngularVelocity(150.0, DEGREE_PER_SECOND)
        self.pitch_speed = AngularVelocity(90.0, DEGREE_PER_SECOND)
        self.trail_speed = AngularVelocity(60.0, DEGREE_PER_SECOND)
        self.follow = Frequency(10.0, PER_SECOND)
        self.clearance = Length(0.3, METER)
        self.focus = Vector3(0, 0, 0)
        self.focused = False

    def check(self) raises:
        """Refuse a camera that cannot follow.

        Raises:
            Error: If the yaw or the pitch is not finite; the distance is
                not positive; the pitches are not from -89 to 89 degrees,
                lowest first; a speed is negative or not finite; the
                follow rate is not positive; or the clearance is negative.
        """
        require_finite(Float64(self.yaw.to(RADIAN)), "A yaw must be finite")
        require_finite(Float64(self.pitch.to(RADIAN)), "A pitch must be finite")
        require_positive_finite(
            Float64(self.distance.to(METER)),
            "A third-person camera's distance must be positive",
        )
        var low = self.lowest_pitch.to(DEGREE)
        var high = self.highest_pitch.to(DEGREE)
        if not (low >= -89 and low <= high and high <= 89):
            raise Error(
                "A third-person camera's pitches must be from -89 to 89"
                " degrees, lowest first"
            )
        for speed in [self.yaw_speed, self.pitch_speed, self.trail_speed]:
            var value = speed.to(RADIAN_PER_SECOND)
            if not (value >= 0 and value < 1.0e6):
                raise Error("A turning speed must not be negative")
        require_positive_finite(
            Float64(self.follow.to(PER_SECOND)),
            "A third-person camera's follow rate must be positive",
        )
        if not (self.clearance.to(METER) >= 0):
            raise Error(
                "A third-person camera's clearance must not be negative"
            )

    def look(self) -> Vector3:
        """Return the way the camera looks, of length one.

        Returns:
            `(-sin yaw cos pitch, sin pitch, -cos yaw cos pitch)`.
        """
        var level = ground_direction(self.yaw, 1, 0)
        var p = self.pitch.to(RADIAN)
        return Vector3(level.x * cos(p), sin(p), level.z * cos(p))

    def turn(
        mut self, look_right: Float32, look_up: Float32, delta: Duration
    ) raises:
        """Turn the orbit by a look stick for one frame.

        Args:
            look_right: How far the stick leans right, from -1 to 1. Right
                turns the view to the right.
            look_up: How far it leans up, from -1 to 1. Up raises the view.
            delta: The frame's time.

        Raises:
            Error: If `check` refuses the camera, or the time is negative.
        """
        self.check()
        var seconds = _seconds(delta)
        var right = clamp(look_right, -1, 1)
        var up = clamp(look_up, -1, 1)
        var yaw = self.yaw.to(RADIAN) - (
            right * self.yaw_speed.to(RADIAN_PER_SECOND) * seconds
        )
        self.yaw = wrap_angle(Angle(yaw, RADIAN))
        var pitch = self.pitch.to(RADIAN) + (
            up * self.pitch_speed.to(RADIAN_PER_SECOND) * seconds
        )
        self.pitch = Angle(
            clamp(
                pitch,
                self.lowest_pitch.to(RADIAN),
                self.highest_pitch.to(RADIAN),
            ),
            RADIAN,
        )

    def trail(mut self, heading: Angle, share: Float32, delta: Duration) raises:
        """Turn the yaw toward a character's heading, for one frame.

        Args:
            heading: The way the character faces, as a yaw.
            share: How much of the trail speed to use, from 0 to 1: the
                character's speed as a share of its top speed, say.
            delta: The frame's time.

        Raises:
            Error: If `check` refuses the camera, or the time is negative.
        """
        self.check()
        var most = (
            self.trail_speed.to(RADIAN_PER_SECOND)
            * clamp(share, 0, 1)
            * _seconds(delta)
        )
        self.yaw = turn_toward(self.yaw, heading, Angle(most, RADIAN))

    def follow_target(mut self, target: Vector3, delta: Duration) raises:
        """Move the focus toward a point for one frame.

        The first call puts the focus on the point.

        Args:
            target: The point to look at: above the character's feet.
            delta: The frame's time.

        Raises:
            Error: If `check` refuses the camera, or the time is negative.
        """
        self.check()
        var seconds = _seconds(delta)
        if not self.focused:
            self.focus = target
            self.focused = True
            return
        var share = 1 - exp(-self.follow.to(PER_SECOND) * seconds)
        self.focus = self.focus + (target - self.focus) * share

    def eye(self) -> Vector3:
        """Return where the eye stands before the floor lifts it.

        Returns:
            The focus, `distance` back along the look.
        """
        return self.focus - self.look() * self.distance.to(METER)

    def place(mut self, mut camera: PerspectiveCamera, floor: Length) raises:
        """Stand the camera at the eye, at least `clearance` above the
        floor, looking at the focus.

        Args:
            camera: The camera.
            floor: The ground's height under the eye: see `eye`.

        Raises:
            Error: If `check` refuses the camera, or the floor is not
                finite.
        """
        self.check()
        require_finite(Float64(floor.to(METER)), "A floor must be finite")
        var eye = self.eye()
        var lowest = floor.to(METER) + self.clearance.to(METER)
        if eye.y < lowest:
            eye = Vector3(eye.x, lowest, eye.z)
        camera.place(eye, self.focus)


def _seconds(delta: Duration) raises -> Float32:
    """Return a frame's time in seconds, refusing a negative time."""
    var seconds = delta.to(SECOND)
    if not (seconds >= 0):
        raise Error("A frame's time must not be negative")
    return seconds
