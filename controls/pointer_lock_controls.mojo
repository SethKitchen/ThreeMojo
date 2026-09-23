# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera turned by the pointer's movement, from three.js
`examples/jsm/controls/PointerLockControls.js`.

While the controls are locked, each pointer move turns the camera: right
and left about the world's y, up and down about the camera's right. The
turn is 0.002 radians a pixel, times `pointer_speed`, as in three.js. The
angle down from straight up stays between `min_polar_angle` and
`max_polar_angle`.

A browser locks the pointer and reports how far it moved. A terminal
reports where the pointer is, and only while a button is held. So a turn
here is the difference between two positions, and the first position
after a press or after `lock` only sets where the pointer is.

`lock` and `unlock` set `is_locked`. There is no browser to ask, so they
always succeed.

`move_forward` and `move_right` move the camera as three.js's do: forward
along the level ground, and right along the camera's right. three.js
leaves the keys that call them to its example. Here `update` calls them
for `W`, `A`, `S`, `D` and the arrows, at `movement_speed`, while a key is
held. A key is held from its last repeat until `key_timeout` goes by, or
until a `KEY_UP`. See `controls.held_keys`.

As in three.js, the camera's up must be +y. The camera keeps its up and
its distance to its target.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.held_keys import HOLD_TIMEOUT, HeldKeys
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
)
from math.euler import Euler, YXZ
from math.vector3 import Vector3
from std.math import pi
from units.si import (
    Angle,
    Duration,
    Length,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Velocity,
)

comptime KEY_W = Key(119)
comptime KEY_S = Key(115)
comptime KEY_A = Key(97)
comptime KEY_D = Key(100)
# Radians a pixel of movement turns. three.js: `_MOUSE_SENSITIVITY`.
comptime MOUSE_SENSITIVITY = Float32(0.002)
comptime QUARTER_TURN = Float32(pi / 2)


struct PointerLockControls(Copyable, Movable):
    """Turns pointer movement into a camera that looks about, and keys into
    a camera that walks."""

    # False to ignore all input and leave the camera alone.
    var enabled: Bool
    # True while the pointer is locked: only then does it turn the camera.
    var is_locked: Bool
    # How far down from straight up the camera can look, and how far.
    var min_polar_angle: Angle
    var max_polar_angle: Angle
    # A factor on how far a pixel turns.
    var pointer_speed: Float32
    # How fast a held key moves the camera.
    var movement_speed: Velocity
    # How long a key counts as held after its last repeat.
    var key_timeout: Duration

    var _held: HeldKeys
    # Where the pointer last was, if it has been seen since the last press
    # or lock.
    var _seen: Bool
    var _last_x: Int
    var _last_y: Int

    def __init__(out self):
        """Create unlocked controls with three.js's defaults."""
        self.enabled = True
        self.is_locked = False
        self.min_polar_angle = Angle(0.0, RADIAN)
        self.max_polar_angle = Angle(Float32(pi), RADIAN)
        self.pointer_speed = 1.0
        self.movement_speed = Velocity(1.0, METER_PER_SECOND)
        self.key_timeout = HOLD_TIMEOUT
        self._held = HeldKeys()
        self._seen = False
        self._last_x = 0
        self._last_y = 0

    def lock(mut self):
        """Lock the pointer, so that its movement turns the camera."""
        self.is_locked = True
        self._seen = False

    def unlock(mut self):
        """Let the pointer go, so that its movement does not turn the
        camera."""
        self.is_locked = False

    def get_direction(self, camera: PerspectiveCamera) raises -> Vector3:
        """Return where a perspective camera looks.

        Args:
            camera: The camera.

        Returns:
            The unit direction.

        Raises:
            Error: If the camera's placement is refused.
        """
        return CameraFrame.of(camera).forward()

    def get_direction(self, camera: OrthographicCamera) raises -> Vector3:
        """Return where an orthographic camera looks.

        Args:
            camera: The camera.

        Returns:
            The unit direction.

        Raises:
            Error: If the camera's placement is refused.
        """
        return CameraFrame.of(camera).forward()

    def move_forward(
        self, mut camera: PerspectiveCamera, distance: Length
    ) raises:
        """Move a perspective camera forward along the level ground.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves back.

        Raises:
            Error: If the camera's placement is refused.
        """
        var step = self._forward_step(CameraFrame.of(camera), camera.up)
        _shift(camera, step * distance.to(METER))

    def move_forward(
        self, mut camera: OrthographicCamera, distance: Length
    ) raises:
        """Move an orthographic camera forward along the level ground.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves back.

        Raises:
            Error: If the camera's placement is refused.
        """
        var step = self._forward_step(CameraFrame.of(camera), camera.up)
        _shift(camera, step * distance.to(METER))

    def move_right(
        self, mut camera: PerspectiveCamera, distance: Length
    ) raises:
        """Move a perspective camera along its right.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves left.

        Raises:
            Error: If the camera's placement is refused.
        """
        var step = self._right_step(CameraFrame.of(camera))
        _shift(camera, step * distance.to(METER))

    def move_right(
        self, mut camera: OrthographicCamera, distance: Length
    ) raises:
        """Move an orthographic camera along its right.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves left.

        Raises:
            Error: If the camera's placement is refused.
        """
        var step = self._right_step(CameraFrame.of(camera))
        _shift(camera, step * distance.to(METER))

    def _forward_step(self, frame: CameraFrame, up: Vector3) -> Vector3:
        """Return the move of one meter forward, or none when disabled.
        three.js: the camera's up crossed with its right.

        Args:
            frame: The camera's frame.
            up: The camera's up.

        Returns:
            The move.
        """
        if not self.enabled:
            return Vector3(0, 0, 0)
        var ahead = up
        ahead.cross(frame.right)
        return ahead

    def _right_step(self, frame: CameraFrame) -> Vector3:
        """Return the move of one meter right, or none when disabled.

        Args:
            frame: The camera's frame.

        Returns:
            The move.
        """
        if not self.enabled:
            return Vector3(0, 0, 0)
        return frame.right

    def handle(
        mut self, event: InputEvent, mut camera: PerspectiveCamera
    ) raises:
        """Turn a perspective camera by a pointer move, or hold a key.

        Args:
            event: The event, with its position in pixels.
            camera: The camera, which a move turns at once, as in three.js.

        Raises:
            Error: If the event's kind, button or key is invalid, the polar
                range is empty, or the camera's placement is refused.
        """
        var frame = CameraFrame.of(camera)
        if self._handle(event, frame):
            camera.place(frame.position, frame.target())

    def handle(
        mut self, event: InputEvent, mut camera: OrthographicCamera
    ) raises:
        """Turn an orthographic camera by a pointer move, or hold a key.

        Args:
            event: The event, with its position in pixels.
            camera: The camera, which a move turns at once, as in three.js.

        Raises:
            Error: If the event's kind, button or key is invalid, the polar
                range is empty, or the camera's placement is refused.
        """
        var frame = CameraFrame.of(camera)
        if self._handle(event, frame):
            camera.place(frame.position, frame.target())

    def _handle(
        mut self, event: InputEvent, mut frame: CameraFrame
    ) raises -> Bool:
        """Take one event, turning a frame by a pointer move.

        Args:
            event: The event.
            frame: The camera's frame.

        Returns:
            True if the frame turned.

        Raises:
            Error: If the event's kind, button or key is invalid, or the
                polar range is empty.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        if not (self.max_polar_angle.value >= self.min_polar_angle.value):
            raise Error(
                "A polar range must not have its maximum below its minimum"
            )
        if not self.enabled:
            return False
        if event.kind == KEY_DOWN:
            self._held.press(event.key)
        elif event.kind == KEY_UP:
            _ = self._held.release(event.key)
        elif event.kind == POINTER_DOWN:
            self._seen = True
            self._last_x = event.x
            self._last_y = event.y
        elif event.kind == POINTER_MOVE:
            var seen = self._seen
            var dx = Float32(event.x - self._last_x)
            var dy = Float32(event.y - self._last_y)
            self._seen = True
            self._last_x = event.x
            self._last_y = event.y
            if seen and self.is_locked:
                self._look(dx, dy, frame)
                return True
        return False

    def _look(self, dx: Float32, dy: Float32, mut frame: CameraFrame) raises:
        """Turn a frame by a pointer's movement. three.js: `onMouseMove`.

        Args:
            dx: Pixels right.
            dy: Pixels down.
            frame: The camera's frame. Its direction changes.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        var euler = Euler.from_matrix(frame.rotation(), YXZ)
        var scale = MOUSE_SENSITIVITY * self.pointer_speed
        var yaw = euler.y.to(RADIAN) - dx * scale
        var pitch = euler.x.to(RADIAN) - dy * scale
        pitch = max(
            QUARTER_TURN - self.max_polar_angle.to(RADIAN),
            min(QUARTER_TURN - self.min_polar_angle.to(RADIAN), pitch),
        )
        euler.x = Angle(pitch, RADIAN)
        euler.y = Angle(yaw, RADIAN)
        var turned = euler.to_matrix()
        var back = turned.transform_direction(Vector3(0, 0, 1))
        back.normalize()
        frame.back = back

    def update(mut self, mut camera: PerspectiveCamera, delta: Duration) raises:
        """Move a perspective camera by the keys held.

        Args:
            camera: The camera to move.
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative, the key timeout is not
                positive, or the camera's placement is refused.
        """
        var steps = self._steps(delta)
        self.move_forward(camera, Length(steps[0], METER))
        self.move_right(camera, Length(steps[1], METER))
        self._expire(delta)

    def update(
        mut self, mut camera: OrthographicCamera, delta: Duration
    ) raises:
        """Move an orthographic camera by the keys held.

        Args:
            camera: The camera to move.
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative, the key timeout is not
                positive, or the camera's placement is refused.
        """
        var steps = self._steps(delta)
        self.move_forward(camera, Length(steps[0], METER))
        self.move_right(camera, Length(steps[1], METER))
        self._expire(delta)

    def _steps(self, delta: Duration) raises -> List[Float32]:
        """Return how far the keys held move the camera in one frame.

        Args:
            delta: The time since the last frame.

        Returns:
            Meters forward, then meters right.

        Raises:
            Error: If the time is negative.
        """
        if delta.value < 0:
            raise Error("A frame's time must not be negative")
        var step = self.movement_speed.to(METER_PER_SECOND) * delta.to(SECOND)
        var forward = self._axis(KEY_W, ARROW_UP) - self._axis(
            KEY_S, ARROW_DOWN
        )
        var right = self._axis(KEY_D, ARROW_RIGHT) - self._axis(
            KEY_A, ARROW_LEFT
        )
        return [forward * step, right * step]

    def _axis(self, letter: Key, arrow: Key) -> Float32:
        """Return 1 if either of two keys is held, else 0.

        Args:
            letter: A letter key.
            arrow: An arrow key.

        Returns:
            1 or 0.
        """
        return Float32(1) if (
            self._held.is_held(letter) or self._held.is_held(arrow)
        ) else Float32(0)

    def _expire(mut self, delta: Duration) raises:
        """Let go of each key not repeated within the timeout.

        Args:
            delta: The time since the last frame.

        Raises:
            Error: If the key timeout is not positive.
        """
        self._held.timeout = self.key_timeout
        _ = self._held.advance(delta)


def _shift(mut camera: PerspectiveCamera, move: Vector3):
    """Move a perspective camera and its target together.

    Args:
        camera: The camera.
        move: The move.
    """
    camera.place(camera.position + move, camera.target + move)


def _shift(mut camera: OrthographicCamera, move: Vector3):
    """Move an orthographic camera and its target together.

    Args:
        camera: The camera.
        move: The move.
    """
    camera.place(camera.position + move, camera.target + move)
