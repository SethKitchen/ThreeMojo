# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera that orbits a target, from three.js
`examples/jsm/controls/OrbitControls.js`.

The controls hold a target and turn input into three changes to the
camera: a rotation about the target, a dolly toward it or away, and a pan
that moves the target and the camera together. `handle` takes one input
event and adds its change to what is pending. `update` applies what is
pending, once a frame, and places the camera.

The arithmetic is three.js's. The camera's offset from the target is a
radius and two angles: `theta` about the y axis from +z, and `phi` down
from +y. A drag the height of the view turns the camera a whole turn. A
wheel notch scales the radius by 0.95. A pan moves the target by the
distance a drag covers at the target's depth, so the point under the
pointer stays under it.

Differences from three.js:

- The camera's up must be +y, its default. three.js turns the offset into
  a frame whose y is the camera's up, and this port does not.
- Only a `PerspectiveCamera` is driven. An orthographic camera zooms
  rather than dollies, and that is not ported.
- Touch, the zoom-to-cursor option and a target radius limit are not
  ported. Panning is always in screen space, three.js's default.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    InputEvent,
    MIDDLE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
    WHEEL,
)
from math.spherical import Spherical
from math.vector3 import Vector3
from std.math import inf, isfinite, pi, tan
from units.si import Angle, Duration, Length, METER, RADIAN, SECOND

# A change smaller than this, squared, is no change. three.js: `_EPS`.
comptime EPSILON = Float32(1e-6)
# The browser's wheel moves by about a hundred pixels a notch, and three.js
# scales a dolly by 0.95 for each hundred.
comptime ZOOM_BASE = Float32(0.95)
comptime WHEEL_PIXELS = Float32(100)
# three.js turns an automatic rotation at `auto_rotate_speed` turns per
# minute, so the default of 2 is one turn in 30 seconds.
comptime SECONDS_PER_MINUTE = Float32(60)
comptime TAU = Float32(2 * pi)


@fieldwise_init
struct OrbitAction(Equatable, ImplicitlyCopyable, Writable):
    """What a pointer button does to the camera, as a type rather than a
    bare int. three.js: `MOUSE.ROTATE`, `MOUSE.DOLLY` and `MOUSE.PAN`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three actions, or none.

        Returns:
            Whether the value names an action.
        """
        return self.value >= 0 and self.value <= 3


comptime NO_ACTION = OrbitAction(0)
comptime ROTATE = OrbitAction(1)
comptime DOLLY = OrbitAction(2)
comptime PAN = OrbitAction(3)


def _clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return `value` limited to the range from `low` to `high`."""
    return max(low, min(high, value))


struct OrbitControls(Copyable, Movable):
    """Turns pointer, wheel and key input into a camera orbiting a target."""

    # The point the camera orbits and looks at.
    var target: Vector3
    # False to ignore all input. `update` still applies what is pending.
    var enabled: Bool
    # How near the camera can dolly to the target, and how far from it.
    var min_distance: Length
    var max_distance: Length
    # How far down from straight above the camera can go, and how far.
    # Zero and a half turn are the poles.
    var min_polar_angle: Angle
    var max_polar_angle: Angle
    # The limits of the angle about y. Infinite, the default, is no limit.
    var min_azimuth_angle: Angle
    var max_azimuth_angle: Angle
    # True to let a change die away over frames instead of stopping.
    var enable_damping: Bool
    # How much of what is pending each frame applies, with damping.
    var damping_factor: Float32
    var enable_rotate: Bool
    var rotate_speed: Float32
    var enable_zoom: Bool
    var zoom_speed: Float32
    var enable_pan: Bool
    var pan_speed: Float32
    # How many pixels an arrow key pans by.
    var key_pan_speed: Float32
    # True to turn about the target by itself while no button is held.
    var auto_rotate: Bool
    # Turns per minute.
    var auto_rotate_speed: Float32
    # What each button does. three.js: `mouseButtons`.
    var primary_action: OrbitAction
    var middle_action: OrbitAction
    var secondary_action: OrbitAction

    # The action of the button held, and where the pointer last was.
    var _action: OrbitAction
    var _last_x: Int
    var _last_y: Int
    # What is pending: radians about y, radians down, a factor on the
    # radius and a move of the target.
    var _delta_theta: Float32
    var _delta_phi: Float32
    var _scale: Float32
    var _pan: Vector3

    def __init__(out self, target: Vector3 = Vector3(0, 0, 0)):
        """Create controls about `target`, with three.js's defaults.

        Args:
            target: The point to orbit.
        """
        self.target = target
        self.enabled = True
        self.min_distance = Length(0.0, METER)
        self.max_distance = Length(inf[DType.float32](), METER)
        self.min_polar_angle = Angle(0.0, RADIAN)
        self.max_polar_angle = Angle(Float32(pi), RADIAN)
        self.min_azimuth_angle = Angle(-inf[DType.float32](), RADIAN)
        self.max_azimuth_angle = Angle(inf[DType.float32](), RADIAN)
        self.enable_damping = False
        self.damping_factor = 0.05
        self.enable_rotate = True
        self.rotate_speed = 1.0
        self.enable_zoom = True
        self.zoom_speed = 1.0
        self.enable_pan = True
        self.pan_speed = 1.0
        self.key_pan_speed = 7.0
        self.auto_rotate = False
        self.auto_rotate_speed = 2.0
        self.primary_action = ROTATE
        self.middle_action = DOLLY
        self.secondary_action = PAN
        self._action = NO_ACTION
        self._last_x = 0
        self._last_y = 0
        self._delta_theta = 0
        self._delta_phi = 0
        self._scale = 1
        self._pan = Vector3(0, 0, 0)

    # --- the three changes -------------------------------------------------

    def rotate_left(mut self, angle: Angle):
        """Turn the camera about the target's y axis, to the left.

        Args:
            angle: How far. Negative turns to the right.
        """
        self._delta_theta -= angle.to(RADIAN)

    def rotate_up(mut self, angle: Angle):
        """Turn the camera up over the target.

        Args:
            angle: How far. Negative turns down.
        """
        self._delta_phi -= angle.to(RADIAN)

    def dolly_in(mut self, scale: Float32) raises:
        """Move the camera toward the target.

        Args:
            scale: The factor on the distance, between zero and one.

        Raises:
            Error: If the factor is not between zero and one.
        """
        if not (scale > 0 and scale <= 1):
            raise Error("A dolly factor must be in (0, 1], got ", scale)
        self._scale *= scale

    def dolly_out(mut self, scale: Float32) raises:
        """Move the camera away from the target.

        Args:
            scale: The factor the distance is divided by, between zero and
                one.

        Raises:
            Error: If the factor is not between zero and one.
        """
        if not (scale > 0 and scale <= 1):
            raise Error("A dolly factor must be in (0, 1], got ", scale)
        self._scale /= scale

    def pan(
        mut self,
        delta_x: Float32,
        delta_y: Float32,
        camera: PerspectiveCamera,
        viewport_height: Int,
    ) raises:
        """Move the target and the camera across the view.

        A pan by the height of the view moves them by the height the view
        covers at the target's distance.

        Args:
            delta_x: Pixels to the right the view content moves.
            delta_y: Pixels down the view content moves.
            camera: The camera, for its direction and its field of view.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the height is not positive.
        """
        _check_height(viewport_height)
        var offset = camera.position - self.target
        var half = camera.fov.to(RADIAN) / 2
        var covered = offset.length() * tan(half)
        var scale = 2 * covered / Float32(viewport_height)
        var axes = _camera_axes(offset)
        # The content follows the pointer, so the camera moves the other
        # way across the view and the same way up it.
        self._pan = self._pan + axes[0] * (-delta_x * scale)
        self._pan = self._pan + axes[1] * (delta_y * scale)

    # --- input -------------------------------------------------------------

    def handle(
        mut self,
        event: InputEvent,
        camera: PerspectiveCamera,
        viewport_height: Int,
    ) raises:
        """Add the change one input event asks for to what is pending.

        A button press starts its action and a release ends it. A move
        with an action going rotates, dollies or pans by how far the
        pointer went. Shift or Ctrl swaps a rotation for a pan and a pan
        for a rotation, as in three.js. A wheel notch dollies. An arrow
        pans by `key_pan_speed` pixels, or with Shift or Ctrl rotates.

        Args:
            event: The event, with its position in pixels.
            camera: The camera, which a pan moves across.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, an
                action is invalid, or the height is not positive.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        _check_height(viewport_height)
        if not self.enabled:
            return
        if event.kind == POINTER_DOWN:
            self._press(event)
        elif event.kind == POINTER_MOVE:
            self._move(event, camera, viewport_height)
        elif event.kind == POINTER_UP:
            self._action = NO_ACTION
        elif event.kind == WHEEL:
            self._wheel(event)
        else:
            self._key(event, camera, viewport_height)

    def _press(mut self, event: InputEvent) raises:
        """Start the action of the button pressed.

        Args:
            event: A pointer press.

        Raises:
            Error: If the button's action is invalid.
        """
        var action = self.action_of(event.button)
        if event.shift or event.ctrl:
            if action == ROTATE:
                action = PAN
            elif action == PAN:
                action = ROTATE
        var allowed = False
        if action == ROTATE:
            allowed = self.enable_rotate
        elif action == DOLLY:
            allowed = self.enable_zoom
        elif action == PAN:
            allowed = self.enable_pan
        self._action = action if allowed else NO_ACTION
        self._last_x = event.x
        self._last_y = event.y

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
            raise Error("Invalid orbit action: ", action.value)
        return action

    def _move(
        mut self,
        event: InputEvent,
        camera: PerspectiveCamera,
        viewport_height: Int,
    ) raises:
        """Rotate, dolly or pan by how far the pointer moved.

        Args:
            event: A pointer move.
            camera: The camera, for a pan.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the height is not positive.
        """
        var dx = Float32(event.x - self._last_x)
        var dy = Float32(event.y - self._last_y)
        self._last_x = event.x
        self._last_y = event.y
        var height = Float32(viewport_height)
        if self._action == ROTATE:
            self.rotate_left(
                Angle(TAU * dx * self.rotate_speed / height, RADIAN)
            )
            self.rotate_up(Angle(TAU * dy * self.rotate_speed / height, RADIAN))
        elif self._action == DOLLY:
            # Down moves away, up moves nearer.
            if dy > 0:
                self._scale /= self._zoom_scale(dy)
            elif dy < 0:
                self._scale *= self._zoom_scale(dy)
        elif self._action == PAN:
            self.pan(
                dx * self.pan_speed,
                dy * self.pan_speed,
                camera,
                viewport_height,
            )

    def _zoom_scale(self, pixels: Float32) -> Float32:
        """Return the dolly factor for a drag or a wheel of `pixels`.

        Args:
            pixels: How far, either way.

        Returns:
            0.95 for each hundred pixels at the default speed.
        """
        return ZOOM_BASE ** (self.zoom_speed * abs(pixels) / WHEEL_PIXELS)

    def _wheel(mut self, event: InputEvent):
        """Dolly by a wheel notch, unless a button's action is going.

        A notch away from the user moves nearer, as in three.js.

        Args:
            event: A wheel notch.
        """
        if not self.enable_zoom or self._action != NO_ACTION:
            return
        var factor = self._zoom_scale(Float32(event.wheel) * WHEEL_PIXELS)
        if event.wheel < 0:
            self._scale *= factor
        else:
            self._scale /= factor

    def _key(
        mut self,
        event: InputEvent,
        camera: PerspectiveCamera,
        viewport_height: Int,
    ) raises:
        """Pan by an arrow, or rotate by one with Shift or Ctrl.

        Args:
            event: A key.
            camera: The camera, for a pan.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the height is not positive.
        """
        var x = Float32(0)
        var y = Float32(0)
        if event.key == ARROW_UP:
            y = 1
        elif event.key == ARROW_DOWN:
            y = -1
        elif event.key == ARROW_LEFT:
            x = 1
        elif event.key == ARROW_RIGHT:
            x = -1
        else:
            return
        if event.shift or event.ctrl:
            if self.enable_rotate:
                var step = TAU * self.rotate_speed / Float32(viewport_height)
                self.rotate_left(Angle(x * step, RADIAN))
                self.rotate_up(Angle(y * step, RADIAN))
        elif self.enable_pan:
            self.pan(
                x * self.key_pan_speed,
                y * self.key_pan_speed,
                camera,
                viewport_height,
            )

    # --- the frame ---------------------------------------------------------

    def update(
        mut self, mut camera: PerspectiveCamera, delta: Duration
    ) -> Bool:
        """Apply what is pending and place the camera.

        Call it once a frame, after the frame's events. With damping, a
        part of each change applies and the rest waits for later frames.

        Args:
            camera: The camera to place. Its position is read, then set.
            delta: The time since the last frame, for an automatic rotation.

        Returns:
            True if the camera moved or turned.
        """
        var spherical = Spherical.from_vector3(camera.position - self.target)
        var radius = spherical.radius
        var theta = spherical.theta.to(RADIAN)
        var phi = spherical.phi.to(RADIAN)

        if self.auto_rotate and self._action == NO_ACTION:
            var turns = self.auto_rotate_speed * delta.to(SECOND)
            self.rotate_left(Angle(TAU * turns / SECONDS_PER_MINUTE, RADIAN))

        var share = self.damping_factor if self.enable_damping else Float32(1)
        theta += self._delta_theta * share
        phi += self._delta_phi * share
        theta = _limit_azimuth(
            theta,
            self.min_azimuth_angle.to(RADIAN),
            self.max_azimuth_angle.to(RADIAN),
        )
        phi = _clamp(
            phi,
            self.min_polar_angle.to(RADIAN),
            self.max_polar_angle.to(RADIAN),
        )
        radius = _clamp(
            radius * self._scale,
            self.min_distance.to(METER),
            self.max_distance.to(METER),
        )
        var target = self.target + self._pan * share

        var placed = Spherical(radius, Angle(phi, RADIAN), Angle(theta, RADIAN))
        placed.make_safe()
        var position = target + placed.to_vector3()

        var keep = 1 - share
        self._delta_theta *= keep
        self._delta_phi *= keep
        self._pan = self._pan * keep
        self._scale = 1

        var moved = position - camera.position
        var shifted = target - self.target
        self.target = target
        camera.place(position, target)
        return moved.dot(moved) > EPSILON or shifted.dot(shifted) > EPSILON


def _check_height(viewport_height: Int) raises:
    """Refuse a view with no height.

    Args:
        viewport_height: The view's height, in pixels.

    Raises:
        Error: If it is not positive.
    """
    if viewport_height <= 0:
        raise Error("A viewport height must be positive, got ", viewport_height)


def _camera_axes(offset: Vector3) -> List[Vector3]:
    """Return the camera's right and up, for a camera at `offset` from the
    point it looks at with +y up.

    Args:
        offset: The camera's position less its target.

    Returns:
        The right, then the up.
    """
    var back = offset
    back.normalize()
    var right = Vector3(0, 1, 0)
    right.cross(back)
    right.normalize()
    var up = back
    up.cross(right)
    return [right, up]


def _limit_azimuth(theta: Float32, low: Float32, high: Float32) -> Float32:
    """Keep an angle about y within its limits, as three.js does.

    Finite limits are brought into a half turn either side of zero first.
    When that puts the low limit above the high one, the allowed range
    passes through a half turn, and the angle goes to the nearer limit.

    Args:
        theta: The angle, in radians.
        low: The low limit, in radians, or minus infinity.
        high: The high limit, in radians, or infinity.

    Returns:
        The angle within the limits.
    """
    if not (isfinite(low) and isfinite(high)):
        return theta
    var lower = _wrap(low)
    var upper = _wrap(high)
    if lower <= upper:
        return _clamp(theta, lower, upper)
    if theta > (lower + upper) / 2:
        return max(lower, theta)
    return min(upper, theta)


def _wrap(angle: Float32) -> Float32:
    """Bring a limit within a half turn of zero by one whole turn.

    Args:
        angle: The limit, in radians.

    Returns:
        The same direction, within a half turn of zero if it was within
        one and a half turns.
    """
    if angle < -Float32(pi):
        return angle + TAU
    if angle > Float32(pi):
        return angle - TAU
    return angle
