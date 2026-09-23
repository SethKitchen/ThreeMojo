# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera turned like a trackball about a target, from three.js
`examples/jsm/controls/TrackballControls.js`.

Unlike `OrbitControls`, a trackball has no poles. A drag turns the camera
and its up about the axis at right angles to the drag, so the camera can
roll over the top. The primary button rotates, the middle button zooms,
and the secondary button pans. The wheel zooms. Holding `A`, `S` or `D`
makes any button rotate, zoom or pan.

`handle` takes one event and records where the pointer went. `update`
applies it, once a frame, and places the camera.

The arithmetic is three.js's. A pointer position is read on a circle as
wide as the view, and the turn is the distance the pointer moved on it,
times `rotate_speed`. A zoom scales the distance to the target by one plus
the fraction of the view the drag covered, times `zoom_speed`. A wheel
notch counts as 0.025 of the view. A pan moves by the fraction of the view
dragged, times the distance and `pan_speed`.

Unless `static_moving` is set, a change dies away over frames: each frame
applies what is left and then keeps `1 - dynamic_damping_factor` of it. A
turn keeps the square root of that, as three.js keeps it.

A key is held from its last repeat until `key_timeout` goes by, or until a
`KEY_UP`. See `controls.held_keys`.

Differences from three.js: touch input is not ported. `update` takes the
time the frame took only to age the keys held; three.js's takes none.
An orthographic camera's pan measures both directions by the view's width,
as three.js's does.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.held_keys import HOLD_TIMEOUT, HeldKeys, physical_key
from controls.input import (
    InputEvent,
    KEY_DOWN,
    KEY_UP,
    Key,
    MIDDLE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
    WHEEL,
)
from controls.orbit_controls import DOLLY, NO_ACTION, OrbitAction, PAN, ROTATE
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import inf, sqrt
from units.si import Angle, Duration, Length, METER, RADIAN, SECOND

# A move smaller than this, squared, is no change. three.js: `_EPS`.
comptime EPSILON = Float32(1e-6)
# The part of the view one wheel notch zooms by: three.js's 0.00025 a
# pixel, at the browser's hundred pixels a notch.
comptime WHEEL_ZOOM = Float32(0.025)
# The time a frame takes, when `update` is not told: a sixtieth of a
# second. It only ages the keys held.
comptime FRAME = Duration(1.0 / 60.0, SECOND)


def _set_length(vector: Vector3, length: Float32) -> Vector3:
    """Return a vector scaled to a length. three.js: `setLength`.

    Args:
        vector: The vector. A zero vector stays zero.
        length: The length. Negative points the other way.

    Returns:
        The scaled vector.
    """
    var unit = vector
    unit.normalize()
    return unit * length


struct TrackballControls(Copyable, Movable):
    """Turns pointer, wheel and key input into a camera turned like a
    trackball about a target."""

    # The point the camera turns about and looks at.
    var target: Vector3
    # False to ignore all input. `update` still applies what is pending.
    var enabled: Bool
    var rotate_speed: Float32
    var zoom_speed: Float32
    var pan_speed: Float32
    var no_rotate: Bool
    var no_zoom: Bool
    var no_pan: Bool
    # True to stop a change at once rather than let it die away.
    var static_moving: Bool
    var dynamic_damping_factor: Float32
    # How near and how far a perspective camera can be from the target.
    var min_distance: Length
    var max_distance: Length
    # How far an orthographic camera can zoom out and in.
    var min_zoom: Float32
    var max_zoom: Float32
    # The keys that make a button rotate, zoom and pan. three.js: `keys`.
    var rotate_key: Key
    var zoom_key: Key
    var pan_key: Key
    # What each button does. three.js: `mouseButtons`.
    var primary_action: OrbitAction
    var middle_action: OrbitAction
    var secondary_action: OrbitAction
    # How long a key counts as held after its last repeat.
    var key_timeout: Duration

    var _held: HeldKeys
    # The action of the button held, and of the key held.
    var _state: OrbitAction
    var _key_state: OrbitAction
    # False after a key goes down, until a key goes up: three.js stops
    # listening for `keydown` then.
    var _listening: Bool
    # The view's size, from the last event.
    var _width: Int
    var _height: Int
    # Where the pointer is on the circle, now and before.
    var _move_prev_x: Float32
    var _move_prev_y: Float32
    var _move_curr_x: Float32
    var _move_curr_y: Float32
    # The last turn, which dies away.
    var _last_axis: Vector3
    var _last_angle: Float32
    # Where a zoom and a pan started and are now, as parts of the view.
    var _zoom_start_y: Float32
    var _zoom_end_y: Float32
    var _pan_start_x: Float32
    var _pan_start_y: Float32
    var _pan_end_x: Float32
    var _pan_end_y: Float32
    var _last_position: Vector3
    var _last_zoom: Float32
    # What `reset` goes back to.
    var _target0: Vector3
    var _position0: Vector3
    var _up0: Vector3
    var _zoom0: Float32

    def __init__(
        out self, camera: PerspectiveCamera, target: Vector3 = Vector3(0, 0, 0)
    ):
        """Create controls about a target, with three.js's defaults.

        Args:
            camera: The camera, placed. `reset` puts it back here.
            target: The point to turn about.
        """
        self = Self(target, camera.position, camera.up, 1)

    def __init__(
        out self, camera: OrthographicCamera, target: Vector3 = Vector3(0, 0, 0)
    ):
        """Create controls about a target for an orthographic camera.

        Args:
            camera: The camera, placed. `reset` puts it back here, and at
                its zoom.
            target: The point to turn about.
        """
        self = Self(target, camera.position, camera.up, camera.zoom)

    def __init__(
        out self, target: Vector3, position: Vector3, up: Vector3, zoom: Float32
    ):
        """Create controls with three.js's defaults.

        Args:
            target: The point to turn about.
            position: Where `reset` puts the camera.
            up: The up `reset` gives the camera.
            zoom: The zoom `reset` gives an orthographic camera.
        """
        self.target = target
        self.enabled = True
        self.rotate_speed = 1.0
        self.zoom_speed = 1.2
        self.pan_speed = 0.3
        self.no_rotate = False
        self.no_zoom = False
        self.no_pan = False
        self.static_moving = False
        self.dynamic_damping_factor = 0.2
        self.min_distance = Length(0.0, METER)
        self.max_distance = Length(inf[DType.float32](), METER)
        self.min_zoom = 0
        self.max_zoom = inf[DType.float32]()
        self.rotate_key = Key(97)
        self.zoom_key = Key(115)
        self.pan_key = Key(100)
        self.primary_action = ROTATE
        self.middle_action = DOLLY
        self.secondary_action = PAN
        self.key_timeout = HOLD_TIMEOUT
        self._held = HeldKeys()
        self._state = NO_ACTION
        self._key_state = NO_ACTION
        self._listening = True
        self._width = 1
        self._height = 1
        self._move_prev_x = 0
        self._move_prev_y = 0
        self._move_curr_x = 0
        self._move_curr_y = 0
        self._last_axis = Vector3(0, 0, 0)
        self._last_angle = 0
        self._zoom_start_y = 0
        self._zoom_end_y = 0
        self._pan_start_x = 0
        self._pan_start_y = 0
        self._pan_end_x = 0
        self._pan_end_y = 0
        self._last_position = position
        self._last_zoom = zoom
        self._target0 = target
        self._position0 = position
        self._up0 = up
        self._zoom0 = zoom

    # --- input -------------------------------------------------------------

    def action_of(self, button: PointerButton) raises -> OrbitAction:
        """Return what a button does.

        Args:
            button: The button.

        Returns:
            Its action, or `NO_ACTION` for no button.

        Raises:
            Error: If the action set for the button is invalid.
        """
        var action = NO_ACTION
        if button == PRIMARY:
            action = self.primary_action
        elif button == MIDDLE:
            action = self.middle_action
        elif button == SECONDARY:
            action = self.secondary_action
        if not action.is_valid():
            raise Error("Invalid trackball action: ", action.value)
        return action

    def handle(
        mut self, event: InputEvent, viewport_width: Int, viewport_height: Int
    ) raises:
        """Record what one input event asks for.

        Args:
            event: The event, with its position in pixels.
            viewport_width: The view's width, in pixels.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, a key or
                an action is invalid, or a size is not positive.
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
        self._width = viewport_width
        self._height = viewport_height
        if event.kind == KEY_DOWN:
            self._held.press(event.key)
            self._key_down(event.key)
        elif event.kind == KEY_UP:
            _ = self._held.release(event.key)
            self._key_up()
        elif event.kind == POINTER_DOWN:
            self._state = self.action_of(event.button)
            self._press(event)
        elif event.kind == POINTER_MOVE:
            self._move(event)
        elif event.kind == POINTER_UP:
            self._state = NO_ACTION
        elif event.kind == WHEEL:
            if not self.no_zoom:
                self._zoom_start_y -= Float32(event.wheel) * WHEEL_ZOOM

    def _key_down(mut self, key: Key) raises:
        """Make the buttons rotate, zoom or pan while a key is held.

        Args:
            key: The key.

        Raises:
            Error: If a key set for an action is invalid.
        """
        if not (
            self.rotate_key.is_valid()
            and self.zoom_key.is_valid()
            and self.pan_key.is_valid()
        ):
            raise Error("Invalid trackball key")
        # three.js also returns while an action's key is held, but a key
        # that chose an action stopped the listening, so that return is
        # this one.
        if not self._listening:
            return
        self._listening = False
        var code = physical_key(key)
        if code == physical_key(self.rotate_key) and not self.no_rotate:
            self._key_state = ROTATE
        elif code == physical_key(self.zoom_key) and not self.no_zoom:
            self._key_state = DOLLY
        elif code == physical_key(self.pan_key) and not self.no_pan:
            self._key_state = PAN

    def _key_up(mut self):
        """Let the buttons do their own actions again."""
        self._key_state = NO_ACTION
        self._listening = True

    def _action(self) -> OrbitAction:
        """Return the action going: the key's, else the button's.

        Returns:
            The action.
        """
        return self._key_state if self._key_state != NO_ACTION else self._state

    def _on_circle(self, event: InputEvent) -> Vector3:
        """Return where the pointer is on the circle as wide as the view.
        three.js: `_getMouseOnCircle`.

        Args:
            event: A pointer event.

        Returns:
            Right and up from the middle, as parts of half the width, in x
            and y.
        """
        var width = Float32(self._width)
        var height = Float32(self._height)
        return Vector3(
            (Float32(event.x) - width * 0.5) / (width * 0.5),
            (height - 2 * Float32(event.y)) / width,
            0,
        )

    def _on_screen(self, event: InputEvent) -> Vector3:
        """Return where the pointer is as parts of the view. three.js:
        `_getMouseOnScreen`.

        Args:
            event: A pointer event.

        Returns:
            Right and down from the top left, in x and y.
        """
        return Vector3(
            Float32(event.x) / Float32(self._width),
            Float32(event.y) / Float32(self._height),
            0,
        )

    def _press(mut self, event: InputEvent):
        """Start the action going where the pointer is.

        Args:
            event: A press.
        """
        var action = self._action()
        if action == ROTATE and not self.no_rotate:
            var at = self._on_circle(event)
            self._move_curr_x = at.x
            self._move_curr_y = at.y
            self._move_prev_x = at.x
            self._move_prev_y = at.y
        elif action == DOLLY and not self.no_zoom:
            self._zoom_start_y = self._on_screen(event).y
            self._zoom_end_y = self._zoom_start_y
        elif action == PAN and not self.no_pan:
            var at = self._on_screen(event)
            self._pan_start_x = at.x
            self._pan_start_y = at.y
            self._pan_end_x = at.x
            self._pan_end_y = at.y

    def _move(mut self, event: InputEvent):
        """Follow the pointer with the action going.

        Args:
            event: A move.
        """
        var action = self._action()
        if action == ROTATE and not self.no_rotate:
            var at = self._on_circle(event)
            self._move_prev_x = self._move_curr_x
            self._move_prev_y = self._move_curr_y
            self._move_curr_x = at.x
            self._move_curr_y = at.y
        elif action == DOLLY and not self.no_zoom:
            self._zoom_end_y = self._on_screen(event).y
        elif action == PAN and not self.no_pan:
            var at = self._on_screen(event)
            self._pan_end_x = at.x
            self._pan_end_y = at.y

    # --- the frame ---------------------------------------------------------

    def update(
        mut self, mut camera: PerspectiveCamera, delta: Duration = FRAME
    ) raises -> Bool:
        """Apply what is pending and place a perspective camera.

        Call it once a frame, after the frame's events.

        Args:
            camera: The camera to place. Its position and up change.
            delta: The time since the last frame, which only ages the keys
                held.

        Returns:
            True if the camera moved more than three.js's threshold since
            it last said so.

        Raises:
            Error: If the time is negative or the key timeout is not
                positive.
        """
        self._expire(delta)
        var eye = camera.position - self.target
        var up = camera.up
        if not self.no_rotate:
            self._rotate(eye, up)
        if not self.no_zoom:
            var factor = self._zoom_factor()
            if factor != 1 and factor > 0:
                eye = eye * factor
        if not self.no_pan:
            self._pan(eye, up, 1, 1)
        var position = self.target + eye
        # three.js's `_checkDistances`.
        if not self.no_zoom or not self.no_pan:
            var low = self.min_distance.to(METER)
            var high = self.max_distance.to(METER)
            if eye.dot(eye) > high * high:
                position = self.target + _set_length(eye, high)
                self._zoom_start_y = self._zoom_end_y
            eye = position - self.target
            if eye.dot(eye) < low * low:
                position = self.target + _set_length(eye, low)
                self._zoom_start_y = self._zoom_end_y
        camera.up = up
        camera.place(position, self.target)
        var moved = position - self._last_position
        if moved.dot(moved) > EPSILON:
            self._last_position = position
            return True
        return False

    def update(
        mut self, mut camera: OrthographicCamera, delta: Duration = FRAME
    ) raises -> Bool:
        """Apply what is pending and place an orthographic camera.

        A zoom changes the camera's zoom, kept between `min_zoom` and
        `max_zoom`, rather than its distance.

        Args:
            camera: The camera to place. Its position, up and zoom change.
            delta: The time since the last frame, which only ages the keys
                held.

        Returns:
            True if the camera moved more than three.js's threshold, or
            zoomed, since it last said so.

        Raises:
            Error: If the time is negative or the key timeout is not
                positive.
        """
        self._expire(delta)
        var eye = camera.position - self.target
        var up = camera.up
        if not self.no_rotate:
            self._rotate(eye, up)
        if not self.no_zoom:
            var factor = self._zoom_factor()
            if factor != 1 and factor > 0:
                camera.zoom = max(
                    self.min_zoom, min(self.max_zoom, camera.zoom / factor)
                )
        if not self.no_pan:
            var wide = (camera.right.value - camera.left.value) / camera.zoom
            var tall = (camera.top.value - camera.bottom.value) / camera.zoom
            # three.js divides both by the view's width.
            var width = Float32(self._width)
            self._pan(eye, up, wide / width, tall / width)
        var position = self.target + eye
        camera.up = up
        camera.place(position, self.target)
        var moved = position - self._last_position
        if moved.dot(moved) > EPSILON or self._last_zoom != camera.zoom:
            self._last_position = position
            self._last_zoom = camera.zoom
            return True
        return False

    def _expire(mut self, delta: Duration) raises:
        """Let go of each key not repeated within the timeout.

        Args:
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative or the key timeout is not
                positive.
        """
        self._held.timeout = self.key_timeout
        var gone = self._held.advance(delta)
        if len(gone) > 0:
            self._key_up()

    def _rotate(mut self, mut eye: Vector3, mut up: Vector3):
        """Turn the offset and the up by the pointer's move on the circle,
        or by what is left of the last turn. three.js: `_rotateCamera`.

        Args:
            eye: The camera's offset from the target.
            up: The camera's up.
        """
        var dx = self._move_curr_x - self._move_prev_x
        var dy = self._move_curr_y - self._move_prev_y
        var angle = sqrt(dx * dx + dy * dy)
        if angle > 0:
            var eye_direction = eye
            eye_direction.normalize()
            var up_direction = up
            up_direction.normalize()
            var sideways = up_direction
            sideways.cross(eye_direction)
            sideways.normalize()
            var move = _set_length(up_direction, dy) + _set_length(sideways, dx)
            var axis = move
            axis.cross(eye)
            axis.normalize()
            angle *= self.rotate_speed
            var turn = Quaternion.from_axis_angle(axis, Angle(angle, RADIAN))
            eye = turn.rotate(eye)
            up = turn.rotate(up)
            self._last_axis = axis
            self._last_angle = angle
        elif not self.static_moving and self._last_angle != 0:
            self._last_angle *= sqrt(1 - self.dynamic_damping_factor)
            var turn = Quaternion.from_axis_angle(
                self._last_axis, Angle(self._last_angle, RADIAN)
            )
            eye = turn.rotate(eye)
            up = turn.rotate(up)
        self._move_prev_x = self._move_curr_x
        self._move_prev_y = self._move_curr_y

    def _zoom_factor(mut self) -> Float32:
        """Return the factor on the distance the pending zoom asks for, and
        let what is left of it die away. three.js: `_zoomCamera`.

        Returns:
            The factor. One, or not positive, is no zoom.
        """
        var factor = (
            1 + (self._zoom_end_y - self._zoom_start_y) * self.zoom_speed
        )
        if self.static_moving:
            self._zoom_start_y = self._zoom_end_y
        else:
            self._zoom_start_y += (
                self._zoom_end_y - self._zoom_start_y
            ) * self.dynamic_damping_factor
        return factor

    def _pan(
        mut self, eye: Vector3, up: Vector3, scale_x: Float32, scale_y: Float32
    ):
        """Move the target by the pointer's pan across the view, and let
        what is left of it die away. three.js: `_panCamera`.

        Args:
            eye: The camera's offset from the target.
            up: The camera's up.
            scale_x: A factor on the pan across: one for a perspective
                camera, meters a pixel for an orthographic one.
            scale_y: A factor on the pan down.
        """
        var change_x = self._pan_end_x - self._pan_start_x
        var change_y = self._pan_end_y - self._pan_start_y
        if change_x * change_x + change_y * change_y == 0:
            return
        var reach = eye.length() * self.pan_speed
        var sideways = eye
        sideways.cross(up)
        var pan = _set_length(sideways, change_x * scale_x * reach)
        pan = pan + _set_length(up, change_y * scale_y * reach)
        self.target = self.target + pan
        if self.static_moving:
            self._pan_start_x = self._pan_end_x
            self._pan_start_y = self._pan_end_y
        else:
            self._pan_start_x += change_x * self.dynamic_damping_factor
            self._pan_start_y += change_y * self.dynamic_damping_factor

    def reset(mut self, mut camera: PerspectiveCamera):
        """Put the target and a perspective camera back where they began.

        Args:
            camera: The camera.
        """
        self._restore()
        camera.up = self._up0
        camera.place(self._position0, self.target)

    def reset(mut self, mut camera: OrthographicCamera):
        """Put the target and an orthographic camera back where they began,
        at the zoom it began with.

        Args:
            camera: The camera.
        """
        self._restore()
        camera.up = self._up0
        camera.zoom = self._zoom0
        self._last_zoom = self._zoom0
        camera.place(self._position0, self.target)

    def _restore(mut self):
        """Stop every action and put the target back."""
        self._state = NO_ACTION
        self._key_state = NO_ACTION
        self._listening = True
        self.target = self._target0
        self._last_position = self._position0
