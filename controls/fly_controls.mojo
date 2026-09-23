# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera that flies, from three.js
`examples/jsm/controls/FlyControls.js`.

Keys move the camera along its own axes and turn it about them. `W` and
`S` move forward and back, `A` and `D` left and right, `R` and `F` up and
down. The arrows pitch and yaw, and `Q` and `E` roll. The pointer's
distance from the middle of the view yaws and pitches too, and the primary
and secondary buttons move forward and back.

`handle` takes one event and changes what is held. `update` moves and
turns the camera by what is held, for the time the frame took. A key is
held from its last repeat until `key_timeout` goes by, or until a
`KEY_UP`. See `controls.held_keys`.

The arithmetic is three.js's. A move is `movement_speed` times the time,
along each axis held. A turn is the quaternion three.js builds, (x, y, z,
1) normalized, with x, y and z the pitch, yaw and roll held, each times
half of `roll_speed` and the time. three.js's `rollSpeed` is that half:
its default of 0.005 is 0.01 radians a second here, the same turn.

Differences from three.js: Shift does not set a speed multiplier, which
three.js sets and never reads. A terminal sends no key for Shift alone.
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
from math.quaternion import Quaternion
from math.vector3 import Vector3
from units.si import (
    AngularVelocity,
    Duration,
    METER_PER_SECOND,
    RADIAN_PER_SECOND,
    SECOND,
    Velocity,
)

# The keys, as three.js's `event.code` names them.
comptime KEY_W = Key(119)
comptime KEY_S = Key(115)
comptime KEY_A = Key(97)
comptime KEY_D = Key(100)
comptime KEY_R = Key(114)
comptime KEY_F = Key(102)
comptime KEY_Q = Key(113)
comptime KEY_E = Key(101)
# A move or a turn smaller than this, squared, is no change. three.js:
# `_EPS`.
comptime EPSILON = Float32(1e-6)


def _check_size(width: Int, height: Int) raises:
    """Refuse a view with no area.

    Args:
        width: The view's width, in pixels.
        height: The view's height, in pixels.

    Raises:
        Error: If a size is not positive.
    """
    if width <= 0 or height <= 0:
        raise Error(
            "A viewport's size must be positive, got ", width, "x", height
        )


struct FlyControls(Copyable, Movable):
    """Turns keys and the pointer into a camera that flies and rolls."""

    # False to ignore all input and leave the camera alone.
    var enabled: Bool
    # How fast the camera moves along each axis held.
    var movement_speed: Velocity
    # How fast the camera turns about each axis held, for small turns.
    var roll_speed: AngularVelocity
    # True to turn only while a button is held. The buttons then do not
    # move.
    var drag_to_look: Bool
    # True to move forward with nothing held.
    var auto_forward: Bool
    # How long a key counts as held after its last repeat.
    var key_timeout: Duration

    var _held: HeldKeys
    # three.js's `_moveState`: each is 0 or 1, except the pointer's yaw
    # and pitch, which run from -1 to 1.
    var _forward: Float32
    var _back: Float32
    var _left: Float32
    var _right: Float32
    var _up: Float32
    var _down: Float32
    var _pitch_up: Float32
    var _pitch_down: Float32
    var _yaw_left: Float32
    var _yaw_right: Float32
    var _roll_left: Float32
    var _roll_right: Float32
    # How many buttons are held, with `drag_to_look`.
    var _status: Int
    var _last_position: Vector3
    var _last_rotation: Quaternion

    def __init__(out self):
        """Create controls with three.js's defaults."""
        self.enabled = True
        self.movement_speed = Velocity(1.0, METER_PER_SECOND)
        self.roll_speed = AngularVelocity(0.01, RADIAN_PER_SECOND)
        self.drag_to_look = False
        self.auto_forward = False
        self.key_timeout = HOLD_TIMEOUT
        self._held = HeldKeys()
        self._forward = 0
        self._back = 0
        self._left = 0
        self._right = 0
        self._up = 0
        self._down = 0
        self._pitch_up = 0
        self._pitch_down = 0
        self._yaw_left = 0
        self._yaw_right = 0
        self._roll_left = 0
        self._roll_right = 0
        self._status = 0
        self._last_position = Vector3(0, 0, 0)
        self._last_rotation = Quaternion.identity()

    def move_vector(self) -> Vector3:
        """Return the move held, along the camera's right, up and back.
        three.js: `_moveVector`.

        Returns:
            Each component -1, 0 or 1.
        """
        var ahead = self._forward != 0 or (
            self.auto_forward and self._back == 0
        )
        var forward = Float32(1) if ahead else Float32(0)
        return Vector3(
            self._right - self._left,
            self._up - self._down,
            self._back - forward,
        )

    def rotation_vector(self) -> Vector3:
        """Return the turn held, about the camera's right, up and back.
        three.js: `_rotationVector`.

        Returns:
            The pitch up, the yaw left and the roll left, each from -1 to 1.
        """
        return Vector3(
            self._pitch_up - self._pitch_down,
            self._yaw_left - self._yaw_right,
            self._roll_left - self._roll_right,
        )

    def handle(
        mut self, event: InputEvent, viewport_width: Int, viewport_height: Int
    ) raises:
        """Change what is held by one input event.

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
        _check_size(viewport_width, viewport_height)
        if not self.enabled:
            return
        if event.kind == KEY_DOWN:
            # three.js ignores a key with Alt held.
            if not event.alt:
                self._held.press(event.key)
                self._set_key(event.key, 1)
        elif event.kind == KEY_UP:
            _ = self._held.release(event.key)
            self._set_key(event.key, 0)
        elif event.kind == POINTER_DOWN:
            self._button(event, 1)
        elif event.kind == POINTER_UP:
            self._button(event, 0)
            if self.drag_to_look:
                self._yaw_left = 0
                self._pitch_down = 0
        elif event.kind == POINTER_MOVE:
            if not self.drag_to_look or self._status > 0:
                var half_width = Float32(viewport_width) / 2
                var half_height = Float32(viewport_height) / 2
                self._yaw_left = -(Float32(event.x) - half_width) / half_width
                self._pitch_down = (
                    Float32(event.y) - half_height
                ) / half_height

    def _button(mut self, event: InputEvent, state: Float32):
        """Press or let go of a button.

        With `drag_to_look` a button counts toward turning. Otherwise the
        primary button moves forward and the secondary back.

        Args:
            event: A press or a release.
            state: 1 for a press, 0 for a release.
        """
        if self.drag_to_look:
            self._status += 1 if state == 1 else -1
        elif event.button == PRIMARY:
            self._forward = state
        elif event.button == SECONDARY:
            self._back = state

    def _set_key(mut self, key: Key, state: Float32):
        """Hold or let go of what a key does.

        Args:
            key: The key. A capital letter is its small letter.
            state: 1 to hold, 0 to let go.
        """
        var code = physical_key(key)
        if code == KEY_W:
            self._forward = state
        elif code == KEY_S:
            self._back = state
        elif code == KEY_A:
            self._left = state
        elif code == KEY_D:
            self._right = state
        elif code == KEY_R:
            self._up = state
        elif code == KEY_F:
            self._down = state
        elif code == ARROW_UP:
            self._pitch_up = state
        elif code == ARROW_DOWN:
            self._pitch_down = state
        elif code == ARROW_LEFT:
            self._yaw_left = state
        elif code == ARROW_RIGHT:
            self._yaw_right = state
        elif code == KEY_Q:
            self._roll_left = state
        elif code == KEY_E:
            self._roll_right = state

    def update(
        mut self, mut camera: PerspectiveCamera, delta: Duration
    ) raises -> Bool:
        """Move and turn a perspective camera by what is held.

        Args:
            camera: The camera to move.
            delta: The time since the last frame.

        Returns:
            True if the camera moved or turned more than three.js's
            threshold since it last said so.

        Raises:
            Error: If the time is negative, the key timeout is not
                positive, or the camera's placement is refused.
        """
        var frame = CameraFrame.of(camera)
        var changed = self._fly(frame, delta)
        frame.place(camera)
        return changed

    def update(
        mut self, mut camera: OrthographicCamera, delta: Duration
    ) raises -> Bool:
        """Move and turn an orthographic camera by what is held.

        Args:
            camera: The camera to move.
            delta: The time since the last frame.

        Returns:
            True if the camera moved or turned more than three.js's
            threshold since it last said so.

        Raises:
            Error: If the time is negative, the key timeout is not
                positive, or the camera's placement is refused.
        """
        var frame = CameraFrame.of(camera)
        var changed = self._fly(frame, delta)
        frame.place(camera)
        return changed

    def _fly(mut self, mut frame: CameraFrame, delta: Duration) raises -> Bool:
        """Move and turn a frame, then let go of each key not repeated.

        Args:
            frame: The camera's frame.
            delta: The time since the last frame.

        Returns:
            True if it moved or turned past the threshold.

        Raises:
            Error: If the time is negative or the key timeout is not
                positive.
        """
        if delta.value < 0:
            raise Error("A frame's time must not be negative")
        if not self.enabled:
            return False
        var seconds = delta.to(SECOND)
        var move = self.movement_speed.to(METER_PER_SECOND) * seconds
        frame.translate(self.move_vector() * move)
        # Half the angular speed: the quaternion's vector part is the sine
        # of half the turn, and this is its tangent before normalizing.
        var half = self.roll_speed.to(RADIAN_PER_SECOND) * seconds / 2
        var spin = self.rotation_vector() * half
        var turn = Quaternion(spin.x, spin.y, spin.z, 1)
        turn.normalize()
        frame.turn(turn)
        self._held.timeout = self.key_timeout
        for key in self._held.advance(delta):
            self._set_key(key, 0)
        var rotation = Quaternion.from_matrix(frame.rotation())
        var moved = frame.position - self._last_position
        var closeness = self._last_rotation.dot(rotation)
        var changed = moved.dot(moved) > EPSILON or (
            8 * (1 - closeness) > EPSILON
        )
        if changed:
            self._last_position = frame.position
            self._last_rotation = rotation
        return changed
