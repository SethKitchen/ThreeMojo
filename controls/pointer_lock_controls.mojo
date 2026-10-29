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

The controls keep the camera's turn themselves, as three.js keeps it in
`camera.quaternion`. A camera that looks straight down cannot hold its
heading in its target: the target lies straight below it, and `Float32`
rounds the rest away. The kept turn holds the heading, so a look back up
faces the same way, and a walk goes the way the camera faced. The turn is
read again from the camera only when the camera was moved from outside:
when its position, its target or its up is not what the controls last
placed.

A camera that looks exactly straight down is drawn through `look_at`. Its
view has no right, so `look_at` nudges it, and the image turns about the
view to that nudge. three.js's image keeps the heading's turn. That is the
one difference left.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.camera_frame import CameraFrame
from controls.held_keys import HOLD_TIMEOUT, HeldKeys, require_frame_time
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    InputEvent,
    KEY_A,
    KEY_D,
    KEY_DOWN,
    KEY_S,
    KEY_UP,
    KEY_W,
    Key,
    require_input,
    POINTER_DOWN,
    POINTER_MOVE,
)
from math.euler import Euler, YXZ
from math.vector3 import Vector3
from std.math import pi
from units.measure import angle_radians
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
    # The camera's turn as the controls last left it, three.js's
    # `camera.quaternion` read as a `YXZ` Euler: the pitch, the heading and
    # the roll. It holds the heading where the camera's target cannot.
    var _turn: Euler
    # The position, the target and the up that the controls last placed
    # the camera at. Empty until they first place it. A camera with other
    # values was moved from outside, and its turn is read again.
    var _placed: List[Vector3]

    def __init__(out self):
        """Create unlocked controls with three.js's defaults."""
        self.enabled = True
        self.is_locked = False
        self.min_polar_angle = Angle(0.0, RADIAN)
        self.max_polar_angle = angle_radians(pi)
        self.pointer_speed = 1.0
        self.movement_speed = Velocity(1.0, METER_PER_SECOND)
        self.key_timeout = HOLD_TIMEOUT
        self._held = HeldKeys()
        self._seen = False
        self._last_x = 0
        self._last_y = 0
        self._turn = Euler(
            Angle(0.0, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN), YXZ
        )
        self._placed = List[Vector3]()

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
        mut self, mut camera: PerspectiveCamera, distance: Length
    ) raises:
        """Move a perspective camera forward along the level ground.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves back.

        Raises:
            Error: If the camera's placement is refused.
        """
        var turn = self._turn_of(CameraFrame.of(camera), camera)
        var step = self._forward_step(turn, camera.up)
        _shift(camera, step * distance.to(METER))
        self._remember(turn, camera)

    def move_forward(
        mut self, mut camera: OrthographicCamera, distance: Length
    ) raises:
        """Move an orthographic camera forward along the level ground.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves back.

        Raises:
            Error: If the camera's placement is refused.
        """
        var turn = self._turn_of(CameraFrame.of(camera), camera)
        var step = self._forward_step(turn, camera.up)
        _shift(camera, step * distance.to(METER))
        self._remember(turn, camera)

    def move_right(
        mut self, mut camera: PerspectiveCamera, distance: Length
    ) raises:
        """Move a perspective camera along its right.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves left.

        Raises:
            Error: If the camera's placement is refused.
        """
        var turn = self._turn_of(CameraFrame.of(camera), camera)
        var step = self._right_step(turn)
        _shift(camera, step * distance.to(METER))
        self._remember(turn, camera)

    def move_right(
        mut self, mut camera: OrthographicCamera, distance: Length
    ) raises:
        """Move an orthographic camera along its right.

        Args:
            camera: The camera. Its target moves with it.
            distance: How far. Negative moves left.

        Raises:
            Error: If the camera's placement is refused.
        """
        var turn = self._turn_of(CameraFrame.of(camera), camera)
        var step = self._right_step(turn)
        _shift(camera, step * distance.to(METER))
        self._remember(turn, camera)

    def _forward_step(self, turn: Euler, up: Vector3) raises -> Vector3:
        """Return the move of one meter forward, or none when disabled.
        three.js: the camera's up crossed with its right.

        Args:
            turn: The camera's turn.
            up: The camera's up.

        Returns:
            The move.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        if not self.enabled:
            return Vector3(0, 0, 0)
        var ahead = up
        ahead.cross(_right(turn))
        return ahead

    def _right_step(self, turn: Euler) raises -> Vector3:
        """Return the move of one meter right, or none when disabled.

        Args:
            turn: The camera's turn.

        Returns:
            The move.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        if not self.enabled:
            return Vector3(0, 0, 0)
        return _right(turn)

    def _turn_of(
        self, frame: CameraFrame, camera: PerspectiveCamera
    ) raises -> Euler:
        """Return a perspective camera's turn: the one the controls keep,
        unless the camera was moved from outside.

        Args:
            frame: The camera's frame, read for a camera moved from outside.
            camera: The camera.

        Returns:
            The turn, as a `YXZ` Euler.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        return self._kept_or_read(
            frame, [camera.position, camera.target, camera.up]
        )

    def _turn_of(
        self, frame: CameraFrame, camera: OrthographicCamera
    ) raises -> Euler:
        """Return an orthographic camera's turn: the one the controls keep,
        unless the camera was moved from outside.

        Args:
            frame: The camera's frame, read for a camera moved from outside.
            camera: The camera.

        Returns:
            The turn, as a `YXZ` Euler.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        return self._kept_or_read(
            frame, [camera.position, camera.target, camera.up]
        )

    def _kept_or_read(
        self, frame: CameraFrame, placed: List[Vector3]
    ) raises -> Euler:
        """Return the turn the controls keep if the camera holds what they
        last placed, else the turn read from its frame.

        Args:
            frame: The camera's frame.
            placed: The camera's position, target and up.

        Returns:
            The turn, as a `YXZ` Euler.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        if self._placed == placed:
            return self._turn
        return Euler.from_matrix(frame.rotation(), YXZ)

    def _remember(mut self, turn: Euler, camera: PerspectiveCamera):
        """Keep a turn, and what the controls placed a perspective camera
        at.

        Args:
            turn: The camera's turn.
            camera: The camera, as the controls placed it.
        """
        self._turn = turn
        self._placed = [camera.position, camera.target, camera.up]

    def _remember(mut self, turn: Euler, camera: OrthographicCamera):
        """Keep a turn, and what the controls placed an orthographic camera
        at.

        Args:
            turn: The camera's turn.
            camera: The camera, as the controls placed it.
        """
        self._turn = turn
        self._placed = [camera.position, camera.target, camera.up]

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
        var turn = self._turn_of(frame, camera)
        if self._handle(event, frame, turn):
            camera.place(frame.position, frame.target())
            self._remember(turn, camera)

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
        var turn = self._turn_of(frame, camera)
        if self._handle(event, frame, turn):
            camera.place(frame.position, frame.target())
            self._remember(turn, camera)

    def _handle(
        mut self, event: InputEvent, mut frame: CameraFrame, mut turn: Euler
    ) raises -> Bool:
        """Take one event, turning a frame by a pointer move.

        Args:
            event: The event.
            frame: The camera's frame.
            turn: The camera's turn. A pointer move changes it.

        Returns:
            True if the frame turned.

        Raises:
            Error: If the event's kind, button or key is invalid, or the
                polar range is empty.
        """
        require_input(event)
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
                self._look(dx, dy, frame, turn)
                return True
        return False

    def _look(
        self,
        dx: Float32,
        dy: Float32,
        mut frame: CameraFrame,
        mut turn: Euler,
    ) raises:
        """Turn a frame by a pointer's movement. three.js: `onMouseMove`.

        Args:
            dx: Pixels right.
            dy: Pixels down.
            frame: The camera's frame. Its direction changes.
            turn: The camera's turn. Its heading and pitch change.

        Raises:
            Error: Never: the Euler order is fixed.
        """
        var scale = MOUSE_SENSITIVITY * self.pointer_speed
        var yaw = turn.y.to(RADIAN) - dx * scale
        var pitch = turn.x.to(RADIAN) - dy * scale
        pitch = max(
            QUARTER_TURN - self.max_polar_angle.to(RADIAN),
            min(QUARTER_TURN - self.min_polar_angle.to(RADIAN), pitch),
        )
        turn.x = Angle(pitch, RADIAN)
        turn.y = Angle(yaw, RADIAN)
        var turned = turn.to_matrix()
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
        require_frame_time(delta)
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


def _right(turn: Euler) raises -> Vector3:
    """Return a camera's right from its turn, three.js's column 0 of
    `camera.matrix`.

    Args:
        turn: The camera's turn.

    Returns:
        The unit right: (cos yaw, 0, -sin yaw) for a camera with no roll.

    Raises:
        Error: Never: the Euler order is fixed.
    """
    return turn.to_matrix().transform_direction(Vector3(1, 0, 0))


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
