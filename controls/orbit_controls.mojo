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

The offset is turned into a frame whose y is the camera's up first, as
three.js turns it, so the poles are along the camera's up. A
`PerspectiveCamera` dollies; an `OrthographicCamera` zooms, between
`min_zoom` and `max_zoom`, and pans by the extent its volume covers. With
`zoom_to_cursor` a dolly or a zoom goes toward the point under the
pointer, as three.js's does.

Differences from three.js: touch input and a target radius limit are not
ported, and panning is always in screen space, three.js's default.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    KEY_DOWN,
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
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
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
    # How far an orthographic camera can zoom out and in, three.js's
    # `minZoom` and `maxZoom`. Zero and infinity by default.
    var min_zoom: Float32
    var max_zoom: Float32
    # True to dolly toward the point under the pointer rather than toward
    # the target, three.js's `zoomToCursor`. False by default.
    var zoom_to_cursor: Bool

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
    # A zoom toward the cursor waiting for `update`: where the pointer was
    # in normalized device coordinates, and the ray through it.
    var _cursor: Bool
    var _cursor_x: Float32
    var _cursor_y: Float32
    var _dolly_direction: Vector3

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
        self.min_zoom = 0
        self.max_zoom = inf[DType.float32]()
        self.zoom_to_cursor = False
        self._cursor = False
        self._cursor_x = 0
        self._cursor_y = 0
        self._dolly_direction = Vector3(0, 0, 0)

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
        self._pan_by(
            delta_x,
            delta_y,
            _perspective_view(camera, self.target, viewport_height),
        )

    def pan(
        mut self,
        delta_x: Float32,
        delta_y: Float32,
        camera: OrthographicCamera,
        viewport_width: Int,
        viewport_height: Int,
    ) raises:
        """Move the target and an orthographic camera across the view.

        A pan by the width of the view moves them by the width the view
        covers at its zoom, as three.js's `panLeft` and `panUp` measure an
        orthographic camera.

        Args:
            delta_x: Pixels to the right the view content moves.
            delta_y: Pixels down the view content moves.
            camera: The camera, for its direction, extents and zoom.
            viewport_width: The view's width, in pixels.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If a size is not positive.
        """
        self._pan_by(
            delta_x,
            delta_y,
            _orthographic_view(
                camera, self.target, viewport_width, viewport_height
            ),
        )

    def _pan_by(mut self, delta_x: Float32, delta_y: Float32, view: _View):
        """Move the target by pixels, at a view's meters a pixel.

        Args:
            delta_x: Pixels to the right the view content moves.
            delta_y: Pixels down the view content moves.
            view: The camera, as the controls see it.
        """
        var axes = _camera_axes(view.offset, view.up)
        # The content follows the pointer, so the camera moves the other
        # way across the view and the same way up it.
        self._pan = self._pan + axes[0] * (-delta_x * view.per_x)
        self._pan = self._pan + axes[1] * (delta_y * view.per_y)

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
        pans by `key_pan_speed` pixels, or with Shift or Ctrl rotates. A
        resize changes nothing here.

        Args:
            event: The event, with its position in pixels.
            camera: The camera, which a pan moves across. The view is as
                wide as its aspect makes it.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, an
                action is invalid, or the height is not positive.
        """
        self._handle(
            event, _perspective_view(camera, self.target, viewport_height)
        )

    def handle(
        mut self,
        event: InputEvent,
        camera: OrthographicCamera,
        viewport_width: Int,
        viewport_height: Int,
    ) raises:
        """Add the change one input event asks for, for an orthographic
        camera. A dolly changes its zoom rather than its distance.

        Args:
            event: The event, with its position in pixels.
            camera: The camera, which a pan moves across.
            viewport_width: The view's width, in pixels.
            viewport_height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, an
                action is invalid, or a size is not positive.
        """
        self._handle(
            event,
            _orthographic_view(
                camera, self.target, viewport_width, viewport_height
            ),
        )

    def _handle(mut self, event: InputEvent, view: _View) raises:
        """Add the change one input event asks for, for any camera.

        Args:
            event: The event, with its position in pixels.
            view: The camera, as the controls see it.

        Raises:
            Error: If the event's kind, button or key is invalid, or an
                action is invalid.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        if not self.enabled:
            return
        if event.kind == POINTER_DOWN:
            self._press(event, view)
        elif event.kind == POINTER_MOVE:
            self._move(event, view)
        elif event.kind == POINTER_UP:
            self._action = NO_ACTION
        elif event.kind == WHEEL:
            self._wheel(event, view)
        elif event.kind == KEY_DOWN:
            self._key(event, view)

    def _aim_at_cursor(mut self, event: InputEvent, view: _View):
        """Remember where the pointer is for a zoom toward it, three.js's
        `_updateZoomParameters`.

        Nothing is remembered unless `zoom_to_cursor` is set. The ray
        through the pointer is taken now, from where the camera is now, as
        three.js takes it.

        Args:
            event: A wheel notch or the press that starts a dolly.
            view: The camera, as the controls see it.
        """
        if not self.zoom_to_cursor:
            return
        self._cursor = True
        self._cursor_x = (Float32(event.x) + 0.5) / Float32(view.width) * 2 - 1
        self._cursor_y = 1 - (Float32(event.y) + 0.5) / Float32(view.height) * 2
        var through = view.inverse.transform_point(
            Vector3(self._cursor_x, self._cursor_y, 0.5)
        )
        var direction = through - view.eye
        direction.normalize()
        self._dolly_direction = direction

    def _press(mut self, event: InputEvent, view: _View) raises:
        """Start the action of the button pressed.

        Args:
            event: A pointer press.
            view: The camera, as the controls see it.

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
        if self._action == DOLLY:
            self._aim_at_cursor(event, view)

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

    def _move(mut self, event: InputEvent, view: _View):
        """Rotate, dolly or pan by how far the pointer moved.

        Args:
            event: A pointer move.
            view: The camera, as the controls see it.
        """
        var dx = Float32(event.x - self._last_x)
        var dy = Float32(event.y - self._last_y)
        self._last_x = event.x
        self._last_y = event.y
        var height = Float32(view.height)
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
            self._pan_by(dx * self.pan_speed, dy * self.pan_speed, view)

    def _zoom_scale(self, pixels: Float32) -> Float32:
        """Return the dolly factor for a drag or a wheel of `pixels`.

        Args:
            pixels: How far, either way.

        Returns:
            0.95 for each hundred pixels at the default speed.
        """
        return ZOOM_BASE ** (self.zoom_speed * abs(pixels) / WHEEL_PIXELS)

    def _wheel(mut self, event: InputEvent, view: _View):
        """Dolly by a wheel notch, unless a button's action is going.

        A notch away from the user moves nearer, as in three.js.

        Args:
            event: A wheel notch.
            view: The camera, as the controls see it.
        """
        if not self.enable_zoom or self._action != NO_ACTION:
            return
        self._aim_at_cursor(event, view)
        var factor = self._zoom_scale(Float32(event.wheel) * WHEEL_PIXELS)
        if event.wheel < 0:
            self._scale *= factor
        else:
            self._scale /= factor

    def _key(mut self, event: InputEvent, view: _View):
        """Pan by an arrow, or rotate by one with Shift or Ctrl.

        Args:
            event: A key.
            view: The camera, as the controls see it.
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
                var step = TAU * self.rotate_speed / Float32(view.height)
                self.rotate_left(Angle(x * step, RADIAN))
                self.rotate_up(Angle(y * step, RADIAN))
        elif self.enable_pan:
            self._pan_by(x * self.key_pan_speed, y * self.key_pan_speed, view)

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
        var cursor = self.zoom_to_cursor and self._cursor
        var placed = self._orbit(camera.position, camera.up, delta, not cursor)
        if cursor:
            # three.js's zoom to the cursor: the camera moves down the ray
            # through the pointer by what the dolly takes off the distance,
            # and the target follows along the view direction.
            var reach = placed[0] - placed[1]
            var before = reach.length()
            var after = _clamp(
                before * self._scale,
                self.min_distance.to(METER),
                self.max_distance.to(METER),
            )
            var forward = placed[1] - placed[0]
            forward.normalize()
            var position = placed[0] + self._dolly_direction * (before - after)
            placed = [position, position + forward * after]
            self._cursor = False
        self._scale = 1
        var changed = self._settle(camera.position, placed[0], placed[1])
        camera.place(placed[0], placed[1])
        return changed

    def update(
        mut self, mut camera: OrthographicCamera, delta: Duration
    ) raises -> Bool:
        """Apply what is pending to an orthographic camera and place it.

        A dolly changes the camera's zoom, kept between `min_zoom` and
        `max_zoom`, rather than its distance.

        Args:
            camera: The camera to place and zoom.
            delta: The time since the last frame, for an automatic rotation.

        Returns:
            True if the camera moved, turned or zoomed.

        Raises:
            Error: If the camera's zoom or volume is refused.
        """
        var cursor = self.zoom_to_cursor and self._cursor
        var placed = self._orbit(camera.position, camera.up, delta, False)
        var old_zoom = camera.zoom
        var new_zoom = _clamp(
            old_zoom / self._scale, self.min_zoom, self.max_zoom
        )
        self._scale = 1
        if cursor:
            # three.js: the point under the pointer before the zoom is kept
            # under it after, by moving the camera the difference.
            camera.place(placed[0], placed[1])
            var before = _unproject(camera, self._cursor_x, self._cursor_y)
            camera.zoom = new_zoom
            var after = _unproject(camera, self._cursor_x, self._cursor_y)
            var shift = before - after
            placed = [placed[0] + shift, placed[1] + shift]
            self._cursor = False
        camera.zoom = new_zoom
        var changed = self._settle(camera.position, placed[0], placed[1])
        camera.place(placed[0], placed[1])
        return changed or new_zoom != old_zoom

    def _settle(
        mut self, was: Vector3, position: Vector3, target: Vector3
    ) -> Bool:
        """Keep a new target, and say whether anything moved.

        Args:
            was: Where the camera was.
            position: Where it goes.
            target: What it looks at.

        Returns:
            True if the camera or the target moved.
        """
        var moved = position - was
        var shifted = target - self.target
        self.target = target
        return moved.dot(moved) > EPSILON or shifted.dot(shifted) > EPSILON

    def _orbit(
        mut self,
        position: Vector3,
        up: Vector3,
        delta: Duration,
        scale_radius: Bool,
    ) -> List[Vector3]:
        """Apply the pending rotation and pan, and the dolly when asked.

        The offset from the target is turned into a frame whose y is the
        camera's up, as three.js's `quat` turns it, so that the polar
        angle is measured from the camera's up.

        Args:
            position: Where the camera is.
            up: The camera's up.
            delta: The time since the last frame.
            scale_radius: Whether the pending dolly scales the distance.
                The distance is kept within its limits either way.

        Returns:
            The new position, then the new target.
        """
        var upward = up
        upward.normalize()
        var to_y = Quaternion.from_unit_vectors(upward, Vector3(0, 1, 0))
        var back = to_y.conjugate()
        var spherical = Spherical.from_vector3(
            to_y.rotate(position - self.target)
        )
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
        var factor = self._scale if scale_radius else Float32(1)
        radius = _clamp(
            radius * factor,
            self.min_distance.to(METER),
            self.max_distance.to(METER),
        )
        var target = self.target + self._pan * share

        var placed = Spherical(radius, Angle(phi, RADIAN), Angle(theta, RADIAN))
        placed.make_safe()
        var moved_to = target + back.rotate(placed.to_vector3())

        var keep = 1 - share
        self._delta_theta *= keep
        self._delta_phi *= keep
        self._pan = self._pan * keep
        return [moved_to, target]


def _check_height(viewport_height: Int) raises:
    """Refuse a view with no height.

    Args:
        viewport_height: The view's height, in pixels.

    Raises:
        Error: If it is not positive.
    """
    if viewport_height <= 0:
        raise Error("A viewport height must be positive, got ", viewport_height)


@fieldwise_init
struct _View(ImplicitlyCopyable):
    """What the controls need of a camera to turn input into a change:
    where it is, which way is up, how many meters a pixel of pan moves,
    the view's size, and the matrix that takes a pixel back into space."""

    # The camera's position less the target.
    var offset: Vector3
    var up: Vector3
    # Meters a pixel of pan moves the target, across and up.
    var per_x: Float32
    var per_y: Float32
    var width: Int
    var height: Int
    var eye: Vector3
    # Normalized device space back to world space.
    var inverse: Matrix4


def _perspective_view(
    camera: PerspectiveCamera, target: Vector3, viewport_height: Int
) raises -> _View:
    """Return what the controls need of a perspective camera.

    A pixel pans by the height the view covers at the target's distance,
    over the view's height, across as well as up: three.js's `pan` for a
    perspective camera.

    Args:
        camera: The camera.
        target: The point it orbits.
        viewport_height: The view's height, in pixels.

    Returns:
        The view.

    Raises:
        Error: If the height is not positive, or the camera's matrices are
            refused.
    """
    _check_height(viewport_height)
    var offset = camera.position - target
    var covered = offset.length() * tan(camera.fov.to(RADIAN) / 2)
    var per = 2 * covered / Float32(viewport_height)
    var width = max(1, Int(Float32(viewport_height) * camera.aspect + 0.5))
    var inverse = camera.projection_matrix()
    inverse.multiply(camera.view_matrix())
    inverse.invert()
    return _View(
        offset,
        camera.up,
        per,
        per,
        width,
        viewport_height,
        camera.position,
        inverse,
    )


def _orthographic_view(
    camera: OrthographicCamera,
    target: Vector3,
    viewport_width: Int,
    viewport_height: Int,
) raises -> _View:
    """Return what the controls need of an orthographic camera.

    A pixel pans by the width or the height the volume covers at the
    camera's zoom, over the view's width or height: three.js's `pan` for
    an orthographic camera.

    Args:
        camera: The camera.
        target: The point it orbits.
        viewport_width: The view's width, in pixels.
        viewport_height: The view's height, in pixels.

    Returns:
        The view.

    Raises:
        Error: If a size is not positive, or the camera's matrices are
            refused.
    """
    _check_height(viewport_height)
    if viewport_width <= 0:
        raise Error("A viewport width must be positive, got ", viewport_width)
    var wide = (camera.right.value - camera.left.value) / camera.zoom
    var tall = (camera.top.value - camera.bottom.value) / camera.zoom
    var inverse = camera.projection_matrix()
    inverse.multiply(camera.view_matrix())
    inverse.invert()
    return _View(
        camera.position - target,
        camera.up,
        wide / Float32(viewport_width),
        tall / Float32(viewport_height),
        viewport_width,
        viewport_height,
        camera.position,
        inverse,
    )


def _unproject(
    camera: OrthographicCamera, x: Float32, y: Float32
) raises -> Vector3:
    """Return the world point at a place on an orthographic camera's view,
    three.js's `Vector3.unproject` at depth zero.

    Args:
        camera: The camera, as placed and zoomed now.
        x: Across, in normalized device coordinates.
        y: Up, in normalized device coordinates.

    Returns:
        The point.

    Raises:
        Error: If the camera's matrices are refused.
    """
    var inverse = camera.projection_matrix()
    inverse.multiply(camera.view_matrix())
    inverse.invert()
    return inverse.transform_point(Vector3(x, y, 0))


def _camera_axes(offset: Vector3, up: Vector3) -> List[Vector3]:
    """Return the camera's right and up, for a camera at `offset` from the
    point it looks at.

    Args:
        offset: The camera's position less its target.
        up: The camera's up.

    Returns:
        The right, then the up.
    """
    var back = offset
    back.normalize()
    var right = up
    right.cross(back)
    right.normalize()
    var above = back
    above.cross(right)
    return [right, above]


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
