# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera that walks and looks toward the pointer, from three.js
`examples/jsm/controls/FirstPersonControls.js`.

`W` or the up arrow moves forward, `S` or the down arrow back, `A` or the
left arrow left, `D` or the right arrow right, and `R` and `F` up and down.
The primary button moves forward and the secondary back. The camera turns
toward the pointer, faster the farther the pointer is from the middle of
the view.

The arithmetic is three.js's. The camera's direction is a latitude and a
longitude. Each frame the longitude goes down by the pointer's pixels to
the right of the middle, times `look_speed` and the time. The latitude goes
down the same way by the pixels below the middle, and stays within 85
degrees of level. `look_speed` is an angle a second for each pixel: three.js
gives the same number in degrees, 0.005 by default.

A key is held from its last repeat until `key_timeout` goes by, or until a
`KEY_UP`. See `controls.held_keys`.

Differences from three.js: the controls read the camera's direction when
they are made, as three.js's constructor does, and again with `look_at`.
A terminal reports the pointer only while a button is held. The camera
keeps turning toward where the pointer last was, as three.js's turns
toward a pointer that rests.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.held_keys import HOLD_TIMEOUT, HeldKeys, physical_key
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    InputEvent,
    KEY_DOWN,
    KEY_UP,
    Key,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    SECONDARY,
)
from math.spherical import Spherical
from math.vector3 import Vector3
from std.math import pi
from units.si import (
    Angle,
    AngularVelocity,
    DEGREE_PER_SECOND,
    Duration,
    Frequency,
    Length,
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    RADIAN,
    RADIAN_PER_SECOND,
    SECOND,
    Velocity,
)

comptime KEY_W = Key(119)
comptime KEY_S = Key(115)
comptime KEY_A = Key(97)
comptime KEY_D = Key(100)
comptime KEY_R = Key(114)
comptime KEY_F = Key(102)
# How far above or below level the camera can look. three.js: 85 degrees.
comptime LATITUDE_LIMIT = Float32(85 * pi / 180)
comptime HALF_TURN = Float32(pi)


struct FirstPersonControls(Copyable, Movable):
    """Turns keys and the pointer into a camera that walks and looks."""

    # False to ignore all input and leave the camera alone.
    var enabled: Bool
    # How fast the camera moves.
    var movement_speed: Velocity
    # How fast the camera turns, for each pixel the pointer is off the
    # middle of the view.
    var look_speed: AngularVelocity
    # False to turn only left and right.
    var look_vertical: Bool
    # True to move forward with nothing held.
    var auto_forward: Bool
    # False to turn not at all, and to let the buttons not move.
    var active_look: Bool
    # True to move forward faster the higher the camera is, between
    # `height_min` and `height_max`: `height_coef` times the height above
    # `height_min` is added to the speed.
    var height_speed: Bool
    var height_coef: Frequency
    var height_min: Length
    var height_max: Length
    # True to keep the angle down from straight up between
    # `vertical_min` and `vertical_max`.
    var constrain_vertical: Bool
    var vertical_min: Angle
    var vertical_max: Angle
    # True while a button is held.
    var mouse_drag_on: Bool
    # How long a key counts as held after its last repeat.
    var key_timeout: Duration

    var _held: HeldKeys
    var _pointer_x: Float32
    var _pointer_y: Float32
    var _move_forward: Bool
    var _move_backward: Bool
    var _move_left: Bool
    var _move_right: Bool
    var _move_up: Bool
    var _move_down: Bool
    # The direction, in radians: up from level, and about y from +z.
    var _lat: Float32
    var _lon: Float32

    def __init__(out self, camera: PerspectiveCamera) raises:
        """Create controls with three.js's defaults, looking where a
        perspective camera looks.

        Args:
            camera: The camera, placed.

        Raises:
            Error: If the camera's placement is refused.
        """
        self = Self(CameraFrame.of(camera))

    def __init__(out self, camera: OrthographicCamera) raises:
        """Create controls with three.js's defaults, looking where an
        orthographic camera looks.

        Args:
            camera: The camera, placed.

        Raises:
            Error: If the camera's placement is refused.
        """
        self = Self(CameraFrame.of(camera))

    def __init__(out self, frame: CameraFrame):
        """Create controls with three.js's defaults, looking where a frame
        looks.

        Args:
            frame: The camera's frame.
        """
        self.enabled = True
        self.movement_speed = Velocity(1.0, METER_PER_SECOND)
        self.look_speed = AngularVelocity(0.005, DEGREE_PER_SECOND)
        self.look_vertical = True
        self.auto_forward = False
        self.active_look = True
        self.height_speed = False
        self.height_coef = Frequency(1.0, PER_SECOND)
        self.height_min = Length(0.0, METER)
        self.height_max = Length(1.0, METER)
        self.constrain_vertical = False
        self.vertical_min = Angle(0.0, RADIAN)
        self.vertical_max = Angle(HALF_TURN, RADIAN)
        self.mouse_drag_on = False
        self.key_timeout = HOLD_TIMEOUT
        self._held = HeldKeys()
        self._pointer_x = 0
        self._pointer_y = 0
        self._move_forward = False
        self._move_backward = False
        self._move_left = False
        self._move_right = False
        self._move_up = False
        self._move_down = False
        self._lat = 0
        self._lon = 0
        self._set_orientation(frame)

    def _set_orientation(mut self, frame: CameraFrame):
        """Read the latitude and the longitude of where a frame looks.
        three.js: `_setOrientation`.

        Args:
            frame: The camera's frame.
        """
        var look = Spherical.from_vector3(frame.forward())
        self._lat = HALF_TURN / 2 - look.phi.to(RADIAN)
        self._lon = look.theta.to(RADIAN)

    def latitude(self) -> Angle:
        """Return how far above level the camera looks.

        Returns:
            The angle, negative below level.
        """
        return Angle(self._lat, RADIAN)

    def longitude(self) -> Angle:
        """Return how far about y from +z the camera looks.

        Returns:
            The angle.
        """
        return Angle(self._lon, RADIAN)

    def look_at(mut self, mut camera: PerspectiveCamera, point: Vector3) raises:
        """Turn a perspective camera toward a point, and look from there.

        Args:
            camera: The camera.
            point: What to look at.

        Raises:
            Error: If the placement is refused.
        """
        var position = camera.position
        camera.place(position, point)
        self._set_orientation(CameraFrame.of(camera))

    def look_at(
        mut self, mut camera: OrthographicCamera, point: Vector3
    ) raises:
        """Turn an orthographic camera toward a point, and look from there.

        Args:
            camera: The camera.
            point: What to look at.

        Raises:
            Error: If the placement is refused.
        """
        var position = camera.position
        camera.place(position, point)
        self._set_orientation(CameraFrame.of(camera))

    def handle(
        mut self, event: InputEvent, viewport_width: Int, viewport_height: Int
    ) raises:
        """Change what is held, or where the pointer is, by one event.

        Args:
            event: The event, with its position in pixels.
            viewport_width: The view's width, in pixels.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, or a size
                is not positive.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        if viewport_width <= 0 or viewport_height <= 0:
            raise Error("A viewport's size must be positive")
        if not self.enabled:
            return
        if event.kind == KEY_DOWN:
            self._held.press(event.key)
            self._set_key(event.key, True)
        elif event.kind == KEY_UP:
            _ = self._held.release(event.key)
            self._set_key(event.key, False)
        elif event.kind == POINTER_DOWN:
            self._button(event, True)
        elif event.kind == POINTER_UP:
            self._button(event, False)
        elif event.kind == POINTER_MOVE:
            self._pointer_x = Float32(event.x) - Float32(viewport_width) / 2
            self._pointer_y = Float32(event.y) - Float32(viewport_height) / 2

    def _button(mut self, event: InputEvent, down: Bool):
        """Press or let go of a button: forward or back, with `active_look`.

        Args:
            event: A press or a release.
            down: True for a press.
        """
        if self.active_look:
            if event.button == PRIMARY:
                self._move_forward = down
            elif event.button == SECONDARY:
                self._move_backward = down
        self.mouse_drag_on = down

    def _set_key(mut self, key: Key, down: Bool):
        """Hold or let go of what a key does.

        Args:
            key: The key. A capital letter is its small letter.
            down: True to hold.
        """
        var code = physical_key(key)
        if code == KEY_W or code == ARROW_UP:
            self._move_forward = down
        elif code == KEY_A or code == ARROW_LEFT:
            self._move_left = down
        elif code == KEY_S or code == ARROW_DOWN:
            self._move_backward = down
        elif code == KEY_D or code == ARROW_RIGHT:
            self._move_right = down
        elif code == KEY_R:
            self._move_up = down
        elif code == KEY_F:
            self._move_down = down

    def update(mut self, mut camera: PerspectiveCamera, delta: Duration) raises:
        """Move and turn a perspective camera for one frame.

        Args:
            camera: The camera to move. Its up is kept.
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative, the key timeout or the vertical
                range is not positive, or the placement is refused.
        """
        var frame = CameraFrame.of(camera)
        var placed = self._walk(frame, delta)
        camera.place(placed[0], placed[1])

    def update(
        mut self, mut camera: OrthographicCamera, delta: Duration
    ) raises:
        """Move and turn an orthographic camera for one frame.

        Args:
            camera: The camera to move. Its up is kept.
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative, the key timeout or the vertical
                range is not positive, or the placement is refused.
        """
        var frame = CameraFrame.of(camera)
        var placed = self._walk(frame, delta)
        camera.place(placed[0], placed[1])

    def _walk(
        mut self, mut frame: CameraFrame, delta: Duration
    ) raises -> List[Vector3]:
        """Move a frame by what is held and turn it toward the pointer.
        three.js: `update`.

        Args:
            frame: The camera's frame.
            delta: The time since the last frame.

        Returns:
            The new position, then the point it looks at.

        Raises:
            Error: If the time is negative, the key timeout or the vertical
                range is not positive.
        """
        if delta.value < 0:
            raise Error("A frame's time must not be negative")
        if self.constrain_vertical and not (
            self.vertical_max.value > self.vertical_min.value
        ):
            raise Error(
                "A vertical range must have its maximum above its minimum"
            )
        if not self.enabled:
            return [frame.position, frame.target()]
        var seconds = delta.to(SECOND)
        var extra = Float32(0)
        if self.height_speed:
            var floor = self.height_min.to(METER)
            var y = max(floor, min(self.height_max.to(METER), frame.position.y))
            extra = seconds * (y - floor) * self.height_coef.to(PER_SECOND)
        var step = seconds * self.movement_speed.to(METER_PER_SECOND)
        var ahead = self._move_forward or (
            self.auto_forward and not self._move_backward
        )
        if ahead:
            frame.translate(Vector3(0, 0, -(step + extra)))
        if self._move_backward:
            frame.translate(Vector3(0, 0, step))
        if self._move_left:
            frame.translate(Vector3(-step, 0, 0))
        if self._move_right:
            frame.translate(Vector3(step, 0, 0))
        if self._move_up:
            frame.translate(Vector3(0, step, 0))
        if self._move_down:
            frame.translate(Vector3(0, -step, 0))

        var look = seconds * self.look_speed.to(RADIAN_PER_SECOND)
        if not self.active_look:
            look = 0
        var ratio = Float32(1)
        var low = self.vertical_min.to(RADIAN)
        var high = self.vertical_max.to(RADIAN)
        if self.constrain_vertical:
            ratio = HALF_TURN / (high - low)
        self._lon -= self._pointer_x * look
        if self.look_vertical:
            self._lat -= self._pointer_y * look * ratio
        self._lat = max(-LATITUDE_LIMIT, min(LATITUDE_LIMIT, self._lat))
        var phi = HALF_TURN / 2 - self._lat
        if self.constrain_vertical:
            # three.js: `MathUtils.mapLinear(phi, 0, PI, min, max)`.
            phi = low + phi * (high - low) / HALF_TURN
        var direction = Spherical(
            1, Angle(phi, RADIAN), Angle(self._lon, RADIAN)
        ).to_vector3()

        self._held.timeout = self.key_timeout
        for key in self._held.advance(delta):
            self._set_key(key, False)
        return [frame.position, frame.position + direction * frame.reach]
