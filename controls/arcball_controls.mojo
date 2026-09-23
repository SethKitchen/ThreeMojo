# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera moved by a virtual trackball, from three.js
`examples/jsm/controls/ArcballControls.js`.

The pointer is read on a trackball: a sphere about a center, joined to a
hyperboloid away from it, as three.js reads it. A drag turns the camera
about the center by the angle between the start and the point now, so a
drag that comes back to where it started puts the camera back too. A pan
moves the camera and the center across the view. A zoom moves the camera
toward the center, or changes an orthographic camera's zoom. With Shift, a
zoom changes a perspective camera's field of view instead and keeps what
is at the center the same size: three.js's vertigo effect.

A double click on a mesh moves the center there and zooms in by
`scale_factor`, over `focus_animation_time` when `enable_animations` is
set. A turn let go while the pointer still moves goes on and slows down
by `damping_factor`, from at most `w_max`.

`handle` applies each event at once, as three.js does. `update` moves the
clock and runs the animations, and then does what three.js's `update`
does: it follows a changed `target`, keeps the camera within its limits,
and turns it to the center. Call it once a frame. Every time the controls
read is the clock's: an event happens at the time of the last `update`.

The camera is read at each call and written back, with its own y axis as
its `up`. `update` turns it to the center with three.js's `up`: the
camera's first one, and after a turn the camera's own y. three.js turns
the first `up` by the camera's rotation instead, which is the same for a
first `up` of +y and points along the view for a first `up` of +z.

The trackball is drawn by `gizmo`: three circles about the center as line
segments, for a `Line` in `SEGMENTS` mode. `grid` is the grid three.js
shows during a pan with `enable_grid`. `copy_state` returns the state as
an `ArcballSnapshot` value, and `paste_state` takes one: three.js writes
the same fields to the clipboard as JSON.

Differences from three.js: touch input is not ported, and so there is no
turn about the view axis. `enable_gizmos` hides the gizmo; three.js has
the member but does not read it. The grid has 60 cells each way, the
number three.js works out in floating point. A pointer is read at the
center of its pixel.
"""

from cameras.camera import Camera
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from controls.input import (
    InputEvent,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    RESIZE,
    WHEEL,
)
from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NO_PARENT, NodeId
from core.raycaster import (
    BATCHED_HIT,
    HitKind,
    INSTANCED_HIT,
    LOD_HIT,
    MESH_HIT,
    Raycaster,
    SKINNED_HIT,
)
from core.scene import Scene
from helpers.segments import Segments
from math.matrix4 import Matrix4, scaling, translation
from math.projection import look_at
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import acos, atan, atan2, cos, inf, pi, sin, sqrt, tan
from units.si import (
    Angle,
    AngularAcceleration,
    AngularVelocity,
    DEGREE,
    Duration,
    Length,
    METER,
    MILLISECOND,
    RADIAN,
    RADIAN_PER_SECOND,
    RADIAN_PER_SECOND_SQUARED,
    SECOND,
)

# A change smaller than this is no change. three.js: `_EPS`.
comptime EPSILON = Float32(1e-6)
# The browser's wheel moves by about a hundred pixels a notch, and three.js
# counts a notch as 125.
comptime WHEEL_PIXELS = Float32(100)
comptime NOTCH_PIXELS = Float32(125)
# A drag the height of the view zooms by this many wheel notches.
comptime SCREEN_NOTCHES = Float32(8)
# A press longer than this, in milliseconds, is no click; two clicks
# further apart than this are no double click. three.js: `_maxDownTime`
# and `_maxInterval`.
comptime MAX_DOWN_TIME = Float64(250)
comptime MAX_INTERVAL = Float64(300)
# A click that moves further than this, in pixels, is no click, and two
# clicks further apart are no double click. three.js: `_movementThreshold`
# and `_posThreshold`.
comptime MOVEMENT_THRESHOLD = Float32(24)
comptime POSITION_THRESHOLD = Float32(24)
# A turn let go later than this after the pointer last moved, in
# milliseconds, stops at once.
comptime INERTIA_WINDOW = Float64(120)
# The points on each circle of the gizmo, less one. three.js: `_curvePts`.
comptime CURVE_POINTS = 128
# The gizmo's opacity at rest and during a turn.
comptime GIZMO_OPACITY = Float32(0.6)
comptime ACTIVE_GIZMO_OPACITY = Float32(1)
# The grid is three times the view and has 20 cells across the view.
comptime GRID_MULTIPLIER = Float32(3)
comptime GRID_DIVISIONS = 60
# The time a frame takes, when `update` is not told.
comptime FRAME = Duration(1.0 / 60.0, SECOND)
comptime DEGREES_PER_RADIAN = Float32(180 / pi)
comptime HALF_TURN = Float32(pi)
comptime SQRT_3 = Float32(1.7320508075688772)


@fieldwise_init
struct ArcballState(Equatable, ImplicitlyCopyable, Writable):
    """What the controls are doing, as a type rather than a bare int.
    three.js: `STATE`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight states.

        Returns:
            Whether the value names a state.
        """
        return self.value >= 0 and self.value <= 7


comptime STATE_IDLE = ArcballState(0)
comptime STATE_ROTATE = ArcballState(1)
comptime STATE_PAN = ArcballState(2)
# A zoom. three.js: `SCALE`.
comptime STATE_SCALE = ArcballState(3)
comptime STATE_FOV = ArcballState(4)
comptime STATE_FOCUS = ArcballState(5)
comptime STATE_ANIMATION_FOCUS = ArcballState(6)
comptime STATE_ANIMATION_ROTATE = ArcballState(7)


@fieldwise_init
struct ArcballOperation(Equatable, ImplicitlyCopyable, Writable):
    """What a button or the wheel does, as a type rather than a bare int.
    three.js: the strings `'PAN'`, `'ROTATE'`, `'ZOOM'` and `'FOV'`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four operations, or none.

        Returns:
            Whether the value names an operation.
        """
        return self.value >= 0 and self.value <= 4


# No operation. three.js: `null`.
comptime NO_OPERATION = ArcballOperation(0)
comptime PAN_OPERATION = ArcballOperation(1)
comptime ROTATE_OPERATION = ArcballOperation(2)
comptime ZOOM_OPERATION = ArcballOperation(3)
comptime FOV_OPERATION = ArcballOperation(4)


@fieldwise_init
struct ArcballMouse(Equatable, ImplicitlyCopyable, Writable):
    """A mouse button or the wheel, as a type rather than a bare int.
    three.js: `0`, `1`, `2` and `'WHEEL'`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three buttons or the wheel.

        Returns:
            Whether the value names a button or the wheel.
        """
        return self.value >= 0 and self.value <= 3


comptime MOUSE_PRIMARY = ArcballMouse(0)
comptime MOUSE_MIDDLE = ArcballMouse(1)
comptime MOUSE_SECONDARY = ArcballMouse(2)
comptime MOUSE_WHEEL = ArcballMouse(3)


@fieldwise_init
struct ArcballModifier(Equatable, ImplicitlyCopyable, Writable):
    """The modifier key a mouse action needs, as a type rather than a bare
    int. three.js: `'CTRL'`, `'SHIFT'` and `null`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is Ctrl, Shift or no key.

        Returns:
            Whether the value names a modifier.
        """
        return self.value >= 0 and self.value <= 2


comptime NO_MODIFIER = ArcballModifier(0)
comptime CTRL_MODIFIER = ArcballModifier(1)
comptime SHIFT_MODIFIER = ArcballModifier(2)


@fieldwise_init
struct MouseAction(ImplicitlyCopyable):
    """An operation, and the button or wheel and the key that start it.
    three.js: an entry of `mouseActions`."""

    var operation: ArcballOperation
    var mouse: ArcballMouse
    var key: ArcballModifier


@fieldwise_init
struct ArcballSnapshot(ImplicitlyCopyable):
    """The state `copy_state` returns and `paste_state` takes. three.js:
    the `arcballState` JSON that `copyState` writes to the clipboard."""

    # The camera's world transform, its up, and its lens.
    var camera_matrix: Matrix4
    var camera_up: Vector3
    var camera_near: Length
    var camera_far: Length
    var camera_zoom: Float32
    # A perspective camera's field of view. An orthographic camera's
    # snapshot holds the field of view of the controls' last perspective
    # camera, which `paste_state` does not read.
    var camera_fov: Angle
    # The gizmo's world transform.
    var gizmo_matrix: Matrix4
    var target: Vector3


@fieldwise_init
struct _Down(ImplicitlyCopyable):
    """A press of the primary button: where, and when in milliseconds."""

    var x: Float32
    var y: Float32
    var time: Float64


@fieldwise_init
struct _Transformation(ImplicitlyCopyable):
    """What an operation does to the camera and, if `has_gizmos`, to the
    gizmo. three.js: `_transformation`."""

    var camera: Matrix4
    var gizmos: Matrix4
    var has_gizmos: Bool


def _position(matrix: Matrix4) -> Vector3:
    """Return a transform's translation. three.js: `setFromMatrixPosition`.

    Args:
        matrix: The transform.

    Returns:
        The translation.
    """
    return Vector3(
        matrix.elements[12], matrix.elements[13], matrix.elements[14]
    )


def _moved(offset: Vector3) -> Matrix4:
    """Return a translation. three.js: `makeTranslation`.

    Args:
        offset: How far.

    Returns:
        The matrix.
    """
    return translation(offset.x, offset.y, offset.z)


def _clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return a value limited to a range. three.js: `MathUtils.clamp`.

    Args:
        value: The value.
        low: The least it can be.
        high: The most it can be.

    Returns:
        The value within the range.
    """
    return max(low, min(high, value))


def _angle_to(a: Vector3, b: Vector3) -> Float32:
    """Return the angle between two vectors. three.js: `angleTo`.

    Args:
        a: One vector.
        b: The other.

    Returns:
        The angle in radians, or a quarter turn if either has no length.
    """
    var denominator = sqrt(a.dot(a) * b.dot(b))
    var cosine = _clamp(a.dot(b) / denominator, -1, 1)
    return Float32(pi / 2) if denominator == 0 else acos(cosine)


def _distance(a: Vector3, b: Vector3) -> Float32:
    """Return the distance between two points.

    Args:
        a: One point.
        b: The other.

    Returns:
        The distance.
    """
    return (a - b).length()


def _world(eye: Vector3, target: Vector3, up: Vector3) raises -> Matrix4:
    """Return a camera's world transform, three.js's `lookAt` and
    `updateMatrix`.

    Args:
        eye: Where the camera is.
        target: What it looks at.
        up: Which way is up.

    Returns:
        The rotation that `look_at` undoes, then the move to `eye`.

    Raises:
        Error: If `look_at` refuses the placement.
    """
    var view = look_at(eye, target, up)
    var world = Matrix4()
    world.set(
        view.get(0, 0),
        view.get(1, 0),
        view.get(2, 0),
        eye.x,
        view.get(0, 1),
        view.get(1, 1),
        view.get(2, 1),
        eye.y,
        view.get(0, 2),
        view.get(1, 2),
        view.get(2, 2),
        eye.z,
        0,
        0,
        0,
        1,
    )
    return world^


struct _Lens(ImplicitlyCopyable):
    """What the controls read of a camera and write back: three.js's
    `object`, whichever kind it is."""

    var perspective: Bool
    # The world transform. three.js: `object.matrix`.
    var matrix: Matrix4
    # A perspective camera's vertical field of view, in radians, its
    # aspect ratio and its shift.
    var fov: Float32
    var aspect: Float32
    var shift: Float32
    # An orthographic camera's volume and zoom. One for a perspective
    # camera, as in three.js.
    var zoom: Float32
    var left: Float32
    var right: Float32
    var top: Float32
    var bottom: Float32
    var near: Float32
    var far: Float32

    def __init__(out self, camera: PerspectiveCamera) raises:
        """Read a perspective camera.

        Args:
            camera: The camera, placed.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        _check_placed(camera.node)
        self.perspective = True
        self.matrix = _world(camera.position, camera.target, camera.up)
        self.fov = camera.fov.to(RADIAN)
        self.aspect = camera.aspect
        self.shift = camera.view_shift.to(METER)
        self.zoom = 1
        self.left = 0
        self.right = 0
        self.top = 0
        self.bottom = 0
        self.near = camera.near.to(METER)
        self.far = camera.far.to(METER)

    def __init__(out self, camera: OrthographicCamera) raises:
        """Read an orthographic camera.

        Args:
            camera: The camera, placed.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        _check_placed(camera.node)
        self.perspective = False
        self.matrix = _world(camera.position, camera.target, camera.up)
        self.fov = 0
        self.aspect = 1
        self.shift = 0
        self.zoom = camera.zoom
        self.left = camera.left.to(METER)
        self.right = camera.right.to(METER)
        self.top = camera.top.to(METER)
        self.bottom = camera.bottom.to(METER)
        self.near = camera.near.to(METER)
        self.far = camera.far.to(METER)

    def position(self) -> Vector3:
        """Return where the camera is.

        Returns:
            The position.
        """
        return _position(self.matrix)

    def quaternion(self) -> Quaternion:
        """Return the camera's rotation. three.js: `object.quaternion`.

        Returns:
            The rotation.
        """
        return Quaternion.from_matrix(self.matrix)

    def _pose(self, center: Vector3) -> List[Vector3]:
        """Return the camera's position, a point straight ahead and its up.

        Args:
            center: The trackball's center, whose distance sets how far
                ahead the point is.

        Returns:
            The position, the point ahead and the up.
        """
        var e = self.matrix.elements.copy()
        var position = self.position()
        var reach = max(_distance(position, center), Float32(1e-3))
        var ahead = Vector3(-e[8], -e[9], -e[10])
        ahead.normalize()
        var up = Vector3(e[4], e[5], e[6])
        up.normalize()
        return [position, position + ahead * reach, up]

    def put(self, mut camera: PerspectiveCamera, center: Vector3):
        """Write this lens to a perspective camera.

        Args:
            camera: The camera.
            center: The trackball's center.
        """
        var pose = self._pose(center)
        camera.up = pose[2]
        camera.place(pose[0], pose[1])
        camera.fov = Angle(self.fov, RADIAN)
        camera.near = Length(self.near, METER)
        camera.far = Length(self.far, METER)

    def put(self, mut camera: OrthographicCamera, center: Vector3):
        """Write this lens to an orthographic camera.

        Args:
            camera: The camera.
            center: The trackball's center.
        """
        var pose = self._pose(center)
        camera.up = pose[2]
        camera.place(pose[0], pose[1])
        camera.zoom = self.zoom
        camera.near = Length(self.near, METER)
        camera.far = Length(self.far, METER)

    def near_point(self, ndc: Vector2) -> Vector3:
        """Return a point of the near plane, in the camera's axes. three.js:
        `(x, y, -1).applyMatrix4(projectionMatrixInverse)`.

        Args:
            ndc: The point in normalized device coordinates.

        Returns:
            The point.
        """
        var top = self.near * tan(self.fov / 2)
        return Vector3(
            ndc.x * top * self.aspect + self.shift, ndc.y * top, -self.near
        )


struct ArcballControls(Copyable, Movable):
    """Turns pointer and wheel input into a camera moved by a virtual
    trackball."""

    # The point the trackball is about. Set it and call `update` to move
    # the trackball there. A pan moves the trackball but not this.
    var target: Vector3
    # False to ignore all input.
    var enabled: Bool
    # The gizmo's size, as a part of the smaller side of the view. Set it
    # with `set_tb_radius`.
    var radius_factor: Float32
    # What each button and the wheel do, with and without a key. three.js:
    # `mouseActions`. Change it with `set_mouse_action`.
    var mouse_actions: List[MouseAction]
    var focus_animation_time: Duration
    # True to move the near and far planes with a zoom, keeping what the
    # first ones showed.
    var adjust_near_far: Bool
    # The factor one wheel notch zooms by.
    var scale_factor: Float32
    # How fast a turn let go slows down, and how fast it can start.
    var damping_factor: AngularAcceleration
    var w_max: AngularVelocity
    # True to let a turn go on after a release, and to move to a double
    # click over time.
    var enable_animations: Bool
    # True to show a grid during a pan. See `grid`.
    var enable_grid: Bool
    # True to zoom toward the pointer.
    var cursor_zoom: Bool
    var min_fov: Angle
    var max_fov: Angle
    var rotate_speed: Float32
    var enable_pan: Bool
    var enable_rotate: Bool
    var enable_zoom: Bool
    var enable_gizmos: Bool
    # True to move to a double click.
    var enable_focus: Bool
    # How near and how far a perspective camera can be from the center.
    var min_distance: Length
    var max_distance: Length
    # How far an orthographic camera can zoom out and in.
    var min_zoom: Float32
    var max_zoom: Float32
    # What a double click is picked with. Its `layers` choose what can be
    # picked. three.js: `getRaycaster()`.
    var raycaster: Raycaster

    var _state: ArcballState
    var _current_target: Vector3
    var _mouse_op: ArcballOperation
    # The camera's and the gizmo's transforms when the operation began, and
    # when the controls began. three.js: `_cameraMatrixState`,
    # `_gizmoMatrixState` and their `0` versions.
    var _camera_state: Matrix4
    var _camera_state0: Matrix4
    var _gizmo_state: Matrix4
    var _gizmo_state0: Matrix4
    # The gizmo's transform now.
    var _gizmo: Matrix4
    var _fov_state: Float32
    var _zoom_state: Float32
    # three.js's `object.up`, which `update` turns the camera with.
    var _up: Vector3
    var _up0: Vector3
    var _zoom0: Float32
    var _fov0: Float32
    var _initial_near: Float32
    var _near_pos0: Float32
    var _near_pos: Float32
    var _initial_far: Float32
    var _far_pos0: Float32
    var _far_pos: Float32
    var _target0: Vector3
    # The button held, and whether a press started an operation. three.js:
    # `_button` and `_input == INPUT.CURSOR`.
    var _button: PointerButton
    var _listening: Bool
    # The clicks toward a double click.
    var _down_valid: Bool
    var _clicks: Int
    var _downs: List[_Down]
    var _click_start: Float64
    # Where the pointer is on the trackball, or its plane, now and when the
    # operation began.
    var _current_cursor: Vector3
    var _start_cursor: Vector3
    # The grid shown during a pan: whether, where, turned how, and how big.
    var _grid_on: Bool
    var _grid_position: Vector3
    var _grid_rotation: Quaternion
    var _grid_size: Float32
    # The gizmo's circles' radius, and whether it is shown and bright.
    var _curve_radius: Float32
    var _gizmos_visible: Bool
    var _gizmos_active: Bool
    # The animation frame asked for. three.js: `_animationId`, which stays
    # set after a focus ends; `_frame` is whether a frame is still to come.
    var _animation_id: Bool
    var _frame: Bool
    # Which animation the frame runs, and whether it is its first frame.
    var _frame_state: ArcballState
    var _frame_first: Bool
    var _time_start: Float64
    var _anim_w0: Float32
    var _anim_axis: Vector3
    var _anim_point: Vector3
    var _anim_gizmo: Matrix4
    # The last two turns of a drag, for the speed of a turn let go.
    var _time_prev: Float64
    var _time_current: Float64
    var _angle_prev: Float32
    var _angle_current: Float32
    var _cursor_pos_prev: Vector3
    var _cursor_pos_curr: Vector3
    var _w_prev: Float32
    var _w_curr: Float32
    var _tb_radius: Float32
    # The clock, in milliseconds. three.js: `performance.now()`.
    var _now: Float64
    # Whether three.js would have sent `change` since the last `update`.
    var _changed: Bool
    # The view's size, and where the pointer is, from the last event.
    var _width: Int
    var _height: Int
    var _center_x: Float32
    var _center_y: Float32

    def __init__(
        out self,
        mut camera: PerspectiveCamera,
        target: Vector3 = Vector3(0, 0, 0),
    ) raises:
        """Create controls about a target, with three.js's defaults.

        The camera is turned to the target. `reset` puts it back here.

        Args:
            camera: The camera, placed.
            target: The trackball's center.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        self = Self(target)
        self.set_camera(camera)

    def __init__(
        out self,
        mut camera: OrthographicCamera,
        target: Vector3 = Vector3(0, 0, 0),
    ) raises:
        """Create controls about a target for an orthographic camera.

        Args:
            camera: The camera, placed.
            target: The trackball's center.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        self = Self(target)
        self.set_camera(camera)

    def __init__(out self, target: Vector3) raises:
        """Create controls with three.js's defaults and no camera yet.

        Args:
            target: The trackball's center.

        Raises:
            Error: Never; the raycaster's range is valid.
        """
        self.target = target
        self.enabled = True
        self.radius_factor = 0.67
        self.mouse_actions = List[MouseAction]()
        self.focus_animation_time = Duration(500.0, MILLISECOND)
        self.adjust_near_far = False
        self.scale_factor = 1.1
        self.damping_factor = AngularAcceleration(
            25.0, RADIAN_PER_SECOND_SQUARED
        )
        self.w_max = AngularVelocity(20.0, RADIAN_PER_SECOND)
        self.enable_animations = True
        self.enable_grid = False
        self.cursor_zoom = False
        self.min_fov = Angle(5.0, DEGREE)
        self.max_fov = Angle(90.0, DEGREE)
        self.rotate_speed = 1
        self.enable_pan = True
        self.enable_rotate = True
        self.enable_zoom = True
        self.enable_gizmos = True
        self.enable_focus = True
        self.min_distance = Length(0.0, METER)
        self.max_distance = Length(inf[DType.float32](), METER)
        self.min_zoom = 0
        self.max_zoom = inf[DType.float32]()
        self.raycaster = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1))
        self._state = STATE_IDLE
        self._current_target = Vector3(0, 0, 0)
        self._mouse_op = NO_OPERATION
        self._camera_state = Matrix4()
        self._camera_state0 = Matrix4()
        self._gizmo_state = Matrix4()
        self._gizmo_state0 = Matrix4()
        self._gizmo = Matrix4()
        self._fov_state = 1
        self._zoom_state = 1
        self._up = Vector3(0, 1, 0)
        self._up0 = Vector3(0, 1, 0)
        self._zoom0 = 1
        self._fov0 = 0
        self._initial_near = 0
        self._near_pos0 = 0
        self._near_pos = 0
        self._initial_far = 0
        self._far_pos0 = 0
        self._far_pos = 0
        self._target0 = Vector3(0, 0, 0)
        self._button = NO_BUTTON
        self._listening = False
        self._down_valid = True
        self._clicks = 0
        self._downs = List[_Down]()
        self._click_start = 0
        self._current_cursor = Vector3(0, 0, 0)
        self._start_cursor = Vector3(0, 0, 0)
        self._grid_on = False
        self._grid_position = Vector3(0, 0, 0)
        self._grid_rotation = Quaternion.identity()
        self._grid_size = 0
        self._curve_radius = 1
        self._gizmos_visible = True
        self._gizmos_active = False
        self._animation_id = False
        self._frame = False
        self._frame_state = STATE_IDLE
        self._frame_first = False
        self._time_start = -1
        self._anim_w0 = 0
        self._anim_axis = Vector3(0, 0, 0)
        self._anim_point = Vector3(0, 0, 0)
        self._anim_gizmo = Matrix4()
        self._time_prev = 0
        self._time_current = 0
        self._angle_prev = 0
        self._angle_current = 0
        self._cursor_pos_prev = Vector3(0, 0, 0)
        self._cursor_pos_curr = Vector3(0, 0, 0)
        self._w_prev = 0
        self._w_curr = 0
        self._tb_radius = 1
        self._now = 0
        self._changed = False
        self._width = 1
        self._height = 1
        self._center_x = 0
        self._center_y = 0
        self._initialize_mouse_actions()

    # --- the camera ----------------------------------------------------------

    def set_camera(mut self, mut camera: PerspectiveCamera) raises:
        """Take a perspective camera, turned to `target`. three.js:
        `setCamera`.

        Args:
            camera: The camera, placed.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        _check_placed(camera.node)
        var position = camera.position
        camera.place(position, self.target)
        var lens = _Lens(camera)
        self._fov0 = lens.fov
        self._fov_state = lens.fov
        self._set_camera(lens, camera.up)
        lens.put(camera, self.center())

    def set_camera(mut self, mut camera: OrthographicCamera) raises:
        """Take an orthographic camera, turned to `target`. three.js:
        `setCamera`.

        Args:
            camera: The camera, placed.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        _check_placed(camera.node)
        var position = camera.position
        camera.place(position, self.target)
        var lens = _Lens(camera)
        self._set_camera(lens, camera.up)
        lens.put(camera, self.center())

    def _set_camera(mut self, lens: _Lens, up: Vector3):
        """Record a camera as the start, and build the gizmo about `target`.

        Args:
            lens: The camera.
            up: The camera's up.
        """
        self._camera_state0 = lens.matrix
        self._camera_state = lens.matrix
        self._zoom0 = lens.zoom
        self._zoom_state = lens.zoom
        var reach = _distance(lens.position(), self.target)
        self._initial_near = lens.near
        self._near_pos0 = reach - lens.near
        self._near_pos = lens.near
        self._initial_far = lens.far
        self._far_pos0 = reach - lens.far
        self._far_pos = lens.far
        self._up = up
        self._up0 = up
        self._tb_radius = self._calculate_tb_radius(lens)
        var target = self.target
        self._make_gizmos(lens, target, self._tb_radius)

    def center(self) -> Vector3:
        """Return the trackball's center: where the gizmo is.

        Returns:
            The center, in world space.
        """
        return _position(self._gizmo)

    def trackball_radius(self) -> Length:
        """Return the trackball's radius. three.js: `_tbRadius`.

        Returns:
            The radius. For an orthographic camera it is at a zoom of one.
        """
        return Length(self._tb_radius, METER)

    def state(self) -> ArcballState:
        """Return what the controls are doing.

        Returns:
            The state.
        """
        return self._state

    # --- mouse actions -------------------------------------------------------

    def _initialize_mouse_actions(mut self):
        """Set three.js's default mouse actions."""
        self.mouse_actions.append(
            MouseAction(PAN_OPERATION, MOUSE_PRIMARY, CTRL_MODIFIER)
        )
        self.mouse_actions.append(
            MouseAction(PAN_OPERATION, MOUSE_SECONDARY, NO_MODIFIER)
        )
        self.mouse_actions.append(
            MouseAction(ROTATE_OPERATION, MOUSE_PRIMARY, NO_MODIFIER)
        )
        self.mouse_actions.append(
            MouseAction(ZOOM_OPERATION, MOUSE_WHEEL, NO_MODIFIER)
        )
        self.mouse_actions.append(
            MouseAction(ZOOM_OPERATION, MOUSE_MIDDLE, NO_MODIFIER)
        )
        self.mouse_actions.append(
            MouseAction(FOV_OPERATION, MOUSE_WHEEL, SHIFT_MODIFIER)
        )
        self.mouse_actions.append(
            MouseAction(FOV_OPERATION, MOUSE_MIDDLE, SHIFT_MODIFIER)
        )

    def set_mouse_action(
        mut self,
        operation: ArcballOperation,
        mouse: ArcballMouse,
        key: ArcballModifier = NO_MODIFIER,
    ) raises -> Bool:
        """Make a button or the wheel, with a key, start an operation. It
        takes the place of the action of the same button and key. three.js:
        `setMouseAction`.

        Args:
            operation: The operation. `NO_OPERATION` is refused.
            mouse: The button, or the wheel.
            key: The key that must be held.

        Returns:
            False for `NO_OPERATION`, and for the wheel with a pan or a
            turn, which need two directions. True otherwise.

        Raises:
            Error: If the operation, the mouse or the key is invalid.
        """
        _check_action(operation, mouse, key)
        if operation == NO_OPERATION:
            return False
        if mouse == MOUSE_WHEEL:
            if operation != ZOOM_OPERATION and operation != FOV_OPERATION:
                return False
        var action = MouseAction(operation, mouse, key)
        for index in range(len(self.mouse_actions)):
            var old = self.mouse_actions[index]
            if old.mouse == mouse and old.key == key:
                self.mouse_actions[index] = action
                return True
        self.mouse_actions.append(action)
        return True

    def unset_mouse_action(
        mut self, mouse: ArcballMouse, key: ArcballModifier = NO_MODIFIER
    ) raises -> Bool:
        """Remove the action of a button or the wheel with a key. three.js:
        `unsetMouseAction`.

        Args:
            mouse: The button, or the wheel.
            key: The key.

        Returns:
            True if there was one.

        Raises:
            Error: If the mouse or the key is invalid.
        """
        _check_action(PAN_OPERATION, mouse, key)
        for index in range(len(self.mouse_actions)):
            var old = self.mouse_actions[index]
            if old.mouse == mouse and old.key == key:
                _ = self.mouse_actions.pop(index)
                return True
        return False

    def operation_of(
        self, mouse: ArcballMouse, key: ArcballModifier = NO_MODIFIER
    ) raises -> ArcballOperation:
        """Return the operation a button or the wheel starts with a key held:
        its own action, else the action with no key. three.js:
        `getOpFromAction`.

        Args:
            mouse: The button, or the wheel.
            key: The key held.

        Returns:
            The operation, or `NO_OPERATION`.

        Raises:
            Error: If the mouse, the key, or a mouse action is invalid.
        """
        _check_action(PAN_OPERATION, mouse, key)
        self.check()
        return self._operation_of(mouse, key)

    def _operation_of(
        self, mouse: ArcballMouse, key: ArcballModifier
    ) -> ArcballOperation:
        """Return the operation of a button or the wheel with a key.

        Args:
            mouse: The button, or the wheel.
            key: The key held.

        Returns:
            The operation, or `NO_OPERATION`.
        """
        for action in self.mouse_actions:
            if action.mouse == mouse and action.key == key:
                return action.operation
        if key != NO_MODIFIER:
            for action in self.mouse_actions:
                if action.mouse == mouse and action.key == NO_MODIFIER:
                    return action.operation
        return NO_OPERATION

    def check(self) raises:
        """Refuse a setting the controls cannot use.

        Raises:
            Error: If a mouse action is invalid, or the radius factor, the
                scale factor or the focus time is not positive.
        """
        for action in self.mouse_actions:
            _check_action(action.operation, action.mouse, action.key)
        if not (self.radius_factor > 0):
            raise Error("The radius factor must be positive")
        if not (self.scale_factor > 0):
            raise Error("The scale factor must be positive")
        if not (self.focus_animation_time.value > 0):
            raise Error("The focus animation time must be positive")

    # --- input -------------------------------------------------------------

    def handle(
        mut self,
        event: InputEvent,
        mut camera: PerspectiveCamera,
        mut scene: Scene,
        assets: Assets,
        width: Int,
        height: Int,
    ) raises:
        """Apply what one input event asks for to a perspective camera.

        Args:
            event: The event, with its position in pixels.
            camera: The camera. It is read, moved, and written back.
            scene: The scene a double click picks in. It is updated first.
            assets: The geometry and materials its objects name.
            width: The view's width, in pixels.
            height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, a setting
                is refused by `check`, a size is not positive, the camera
                rides a node, or the scene cannot be read.
        """
        var lens = _Lens(camera)
        var tap = self._handle(event, lens, width, height)
        lens.put(camera, self.center())
        if tap and self._can_focus():
            var hit = self._pick(camera, scene, assets)
            self._on_double_tap(lens, hit)
            lens.put(camera, self.center())

    def handle(
        mut self,
        event: InputEvent,
        mut camera: OrthographicCamera,
        mut scene: Scene,
        assets: Assets,
        width: Int,
        height: Int,
    ) raises:
        """Apply what one input event asks for to an orthographic camera.

        Args:
            event: The event, with its position in pixels.
            camera: The camera. It is read, moved, and written back.
            scene: The scene a double click picks in. It is updated first.
            assets: The geometry and materials its objects name.
            width: The view's width, in pixels.
            height: The view's height, in pixels.

        Raises:
            Error: If the event's kind, button or key is invalid, a setting
                is refused by `check`, a size is not positive, the camera
                rides a node, or the scene cannot be read.
        """
        var lens = _Lens(camera)
        var tap = self._handle(event, lens, width, height)
        lens.put(camera, self.center())
        if tap and self._can_focus():
            var hit = self._pick(camera, scene, assets)
            self._on_double_tap(lens, hit)
            lens.put(camera, self.center())

    def _can_focus(self) -> Bool:
        """Return whether a double click moves to what it hits.

        Returns:
            Whether the controls are enabled and can pan and focus.
        """
        return self.enabled and self.enable_pan and self.enable_focus

    def _pick[
        C: Camera
    ](mut self, camera: C, mut scene: Scene, assets: Assets) raises -> Optional[
        Vector3
    ]:
        """Return the nearest point of a mesh under the pointer. three.js:
        `unprojectOnObj`.

        Args:
            camera: The camera, written back.
            scene: The scene. It is updated first.
            assets: Its geometry and materials.

        Returns:
            The point, or None. A line, points and a sprite have no face,
            so they are passed over, as in three.js.

        Raises:
            Error: If the camera or the scene cannot be read.
        """
        scene.update()
        self.raycaster.near = Length(camera.near_distance(), METER)
        self.raycaster.far = Length(camera.far_distance(), METER)
        var ndc = self._ndc(self._center_x, self._center_y)
        self.raycaster.set_from_camera(ndc, camera, scene)
        for hit in self.raycaster.intersect_scene(scene, assets):
            if _has_face(hit.kind):
                return hit.point
        return None

    def _handle(
        mut self, event: InputEvent, mut lens: _Lens, width: Int, height: Int
    ) raises -> Bool:
        """Apply one event to the camera.

        Args:
            event: The event, with its position in pixels.
            lens: The camera.
            width: The view's width, in pixels.
            height: The view's height, in pixels.

        Returns:
            True if the event ends a double click.

        Raises:
            Error: If the event's kind, button or key is invalid, a setting
                is refused, or a size is not positive.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        if width <= 0 or height <= 0:
            raise Error("A viewport's size must be positive")
        self.check()
        self._width = width
        self._height = height
        var x = Float32(event.x) + 0.5
        var y = Float32(event.y) + 0.5
        if event.kind == POINTER_DOWN:
            self._pointer_down(event, lens, x, y)
        elif event.kind == POINTER_MOVE:
            if self._listening:
                self._pointer_move(event, lens, x, y)
        elif event.kind == POINTER_UP:
            if self._listening:
                return self._pointer_up(lens, x, y)
        elif event.kind == WHEEL:
            self._wheel(event, lens, x, y)
        elif event.kind == RESIZE:
            self._resize(lens)
        return False

    def _modifier(self, event: InputEvent) -> ArcballModifier:
        """Return the key an event holds, as three.js reads it: Ctrl before
        Shift.

        Args:
            event: The event.

        Returns:
            The modifier.
        """
        if event.ctrl:
            return CTRL_MODIFIER
        if event.shift:
            return SHIFT_MODIFIER
        return NO_MODIFIER

    def _pointer_down(
        mut self, event: InputEvent, mut lens: _Lens, x: Float32, y: Float32
    ):
        """Start the operation of the button pressed. three.js:
        `onPointerDown`.

        Args:
            event: The press.
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
        """
        if event.button == PRIMARY:
            self._down_valid = True
            self._downs.append(_Down(x, y, self._now))
        else:
            self._down_valid = False
        if self._listening:
            return
        self._mouse_op = self._operation_of(
            ArcballMouse(event.button.value), self._modifier(event)
        )
        if self._mouse_op == NO_OPERATION:
            return
        self._listening = True
        self._button = event.button
        var operation = self._mouse_op
        self._single_pan_start(lens, x, y, operation)

    def _pointer_move(
        mut self, event: InputEvent, mut lens: _Lens, x: Float32, y: Float32
    ):
        """Go on with the operation of the button held. three.js:
        `onPointerMove`.

        Args:
            event: The move.
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
        """
        var operation = self._operation_of(
            ArcballMouse(self._button.value), self._modifier(event)
        )
        if operation != NO_OPERATION:
            self._single_pan_move(lens, x, y, _state_of(operation))
        if self._down_valid:
            var last = self._downs[len(self._downs) - 1]
            if _apart(last.x, last.y, x, y) > MOVEMENT_THRESHOLD:
                self._down_valid = False

    def _pointer_up(mut self, mut lens: _Lens, x: Float32, y: Float32) -> Bool:
        """End the operation, and count the click. three.js: `onPointerUp`.

        Args:
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.

        Returns:
            True if the release ends a double click.
        """
        self._listening = False
        self._single_pan_end(lens)
        self._button = NO_BUTTON
        if not self._down_valid:
            self._clicks = 0
            self._downs.clear()
            return False
        var down_time = self._now - self._downs[len(self._downs) - 1].time
        if down_time > MAX_DOWN_TIME:
            self._down_valid = False
            self._clicks = 0
            self._downs.clear()
            return False
        if self._clicks == 0:
            self._clicks = 1
            self._click_start = self._now
            return False
        var interval = self._now - self._click_start
        var first = self._downs[0]
        var second = self._downs[1]
        var movement = _apart(first.x, first.y, second.x, second.y)
        if interval <= MAX_INTERVAL and movement <= POSITION_THRESHOLD:
            self._clicks = 0
            self._downs.clear()
            self._center_x = x
            self._center_y = y
            return True
        self._clicks = 1
        _ = self._downs.pop(0)
        self._click_start = self._now
        return False

    def _single_pan_start(
        mut self,
        mut lens: _Lens,
        x: Float32,
        y: Float32,
        operation: ArcballOperation,
    ):
        """Start an operation where the pointer is. three.js:
        `onSinglePanStart`.

        Args:
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
            operation: The operation.
        """
        if not self.enabled:
            return
        self._center_x = x
        self._center_y = y
        if operation == PAN_OPERATION:
            if not self.enable_pan:
                return
            self._stop_animation(True)
            self._update_tb_state(lens, STATE_PAN, True)
            self._start_cursor = self._on_tb_plane(lens, x, y)
            if self.enable_grid:
                self._draw_grid(lens)
                self._changed = True
        elif operation == ROTATE_OPERATION:
            if not self.enable_rotate:
                return
            self._stop_animation(False)
            self._update_tb_state(lens, STATE_ROTATE, True)
            self._start_cursor = self._on_tb_surface(lens, x, y)
            self.activate_gizmos(True)
            if self.enable_animations:
                self._time_prev = self._now
                self._time_current = self._now
                self._angle_current = 0
                self._angle_prev = 0
                self._cursor_pos_prev = self._start_cursor
                self._cursor_pos_curr = self._start_cursor
                self._w_curr = 0
                self._w_prev = 0
            self._changed = True
        else:
            if not self.enable_zoom:
                return
            var state = STATE_SCALE
            if operation == FOV_OPERATION:
                if not lens.perspective:
                    return
                state = STATE_FOV
            self._stop_animation(True)
            self._update_tb_state(lens, state, True)
            self._start_cursor.y = self._ndc(x, y).y * 0.5
            self._current_cursor = self._start_cursor

    def _stop_animation(mut self, calm: Bool):
        """Cancel the animation frame asked for, if there is one.

        Args:
            calm: Whether to dim the gizmo too, as a pan and a zoom do.
        """
        if not self._animation_id:
            return
        self._animation_id = False
        self._frame = False
        self._time_start = -1
        if calm:
            self.activate_gizmos(False)
            self._changed = True

    def _single_pan_move(
        mut self,
        mut lens: _Lens,
        x: Float32,
        y: Float32,
        op_state: ArcballState,
    ):
        """Go on with an operation, or switch to another. three.js:
        `onSinglePanMove`.

        Args:
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
            op_state: The state of the operation the button and the key
                start now.
        """
        if not self.enabled:
            return
        var restart = op_state != self._state
        self._center_x = x
        self._center_y = y
        if op_state == STATE_PAN:
            if self.enable_pan:
                if restart:
                    self._update_tb_state(lens, op_state, True)
                    self._start_cursor = self._on_tb_plane(lens, x, y)
                    if self.enable_grid:
                        self._draw_grid(lens)
                    self.activate_gizmos(False)
                else:
                    self._current_cursor = self._on_tb_plane(lens, x, y)
                    self._apply(
                        lens,
                        self._pan(
                            lens, self._start_cursor, self._current_cursor
                        ),
                    )
        elif op_state == STATE_ROTATE:
            if self.enable_rotate:
                if restart:
                    self._update_tb_state(lens, op_state, True)
                    self._start_cursor = self._on_tb_surface(lens, x, y)
                    self._grid_on = False
                    self.activate_gizmos(True)
                else:
                    self._rotate_to(lens, x, y)
        elif op_state == STATE_SCALE:
            if self.enable_zoom:
                if restart:
                    self._restart_zoom(lens, op_state, x, y)
                else:
                    self._current_cursor.y = self._ndc(x, y).y * 0.5
                    var size = self._drag_size()
                    self._apply(
                        lens,
                        self._scale(lens, size, _position(self._gizmo_state)),
                    )
        else:
            if self.enable_zoom and lens.perspective:
                if restart:
                    self._restart_zoom(lens, op_state, x, y)
                else:
                    self._current_cursor.y = self._ndc(x, y).y * 0.5
                    self._vertigo(lens, self._drag_size(), self._fov_state)
        self._changed = True

    def _rotate_to(mut self, mut lens: _Lens, x: Float32, y: Float32):
        """Turn the camera from where the drag started to the pointer.

        Args:
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
        """
        self._current_cursor = self._on_tb_surface(lens, x, y)
        var start = self._start_cursor
        var current = self._current_cursor
        var distance = _distance(start, current)
        var angle = _angle_to(start, current)
        var amount = max(distance / self._tb_radius, angle) * self.rotate_speed
        self._apply(
            lens, self._rotate(self._rotation_axis(start, current), amount)
        )
        if self.enable_animations:
            self._time_prev = self._time_current
            self._time_current = self._now
            self._angle_prev = self._angle_current
            self._angle_current = amount
            self._cursor_pos_prev = self._cursor_pos_curr
            self._cursor_pos_curr = current
            self._w_prev = self._w_curr
            self._w_curr = _angular_speed(
                self._angle_prev,
                self._angle_current,
                self._time_prev,
                self._time_current,
            )

    def _restart_zoom(
        mut self, mut lens: _Lens, state: ArcballState, x: Float32, y: Float32
    ):
        """Switch to a zoom or a change of the field of view.

        Args:
            lens: The camera.
            state: `STATE_SCALE` or `STATE_FOV`.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
        """
        self._update_tb_state(lens, state, True)
        self._start_cursor.y = self._ndc(x, y).y * 0.5
        self._current_cursor = self._start_cursor
        self._grid_on = False
        self.activate_gizmos(False)

    def _drag_size(self) -> Float32:
        """Return the zoom a drag up or down the view asks for.

        Returns:
            The factor: `scale_factor` to the power of eight times the part
            of the view dragged up.
        """
        var movement = self._current_cursor.y - self._start_cursor.y
        var size = Float32(1)
        if movement < 0:
            size = 1 / (self.scale_factor ** (-movement * SCREEN_NOTCHES))
        elif movement > 0:
            size = self.scale_factor ** (movement * SCREEN_NOTCHES)
        return size

    def _vertigo(mut self, mut lens: _Lens, size: Float32, fov: Float32):
        """Change the field of view and move the camera so that the center
        keeps its size. three.js's `FOV` operation.

        Args:
            lens: The camera.
            size: The zoom asked for.
            fov: The field of view the size starts from, in radians.
        """
        var center = self.center()
        var x = _distance(_position(self._camera_state), center)
        var x_new = _clamp(
            x / size,
            self.min_distance.to(METER),
            self.max_distance.to(METER),
        )
        var y = x * tan(fov * 0.5)
        var new_fov = _clamp(
            atan(y / x_new) * 2,
            self.min_fov.to(RADIAN),
            self.max_fov.to(RADIAN),
        )
        var new_distance = y / tan(new_fov / 2)
        self._set_fov(lens, new_fov)
        self._apply(
            lens,
            self._scale(
                lens, x / new_distance, _position(self._gizmo_state), False
            ),
        )

    def _single_pan_end(mut self, mut lens: _Lens):
        """End an operation. A turn let go while the pointer moves goes on.
        three.js: `onSinglePanEnd`.

        Args:
            lens: The camera.
        """
        if self._state == STATE_ROTATE:
            if not self.enable_rotate:
                return
            if (
                self.enable_animations
                and self._now - self._time_current < INERTIA_WINDOW
            ):
                var w = abs((self._w_prev + self._w_curr) / 2)
                self._request(STATE_ANIMATION_ROTATE, True)
                self._anim_w0 = min(w, self.w_max.to(RADIAN_PER_SECOND))
                return
            self._update_tb_state(lens, STATE_IDLE, False)
            self.activate_gizmos(False)
            self._changed = True
        elif self._state == STATE_PAN or self._state == STATE_IDLE:
            self._update_tb_state(lens, STATE_IDLE, False)
            self._grid_on = False
            self.activate_gizmos(False)
            self._changed = True

    def _on_double_tap(mut self, mut lens: _Lens, hit: Optional[Vector3]):
        """Move the center to the point double clicked. three.js:
        `onDoubleTap`.

        Args:
            lens: The camera.
            hit: The point of a mesh under the pointer, or None.
        """
        if not Bool(hit):
            return
        var point = hit.value()
        if self.enable_animations:
            self._time_start = -1
            self._request(STATE_ANIMATION_FOCUS, True)
            self._anim_point = point
            return
        self._update_tb_state(lens, STATE_FOCUS, True)
        self._focus(lens, point, self.scale_factor)
        self._update_tb_state(lens, STATE_IDLE, False)
        self._changed = True

    def _request(mut self, state: ArcballState, first: Bool):
        """Ask for an animation frame. three.js: `requestAnimationFrame`.

        Args:
            state: The animation the frame runs.
            first: Whether it is the animation's first frame, which enters
                the state.
        """
        self._animation_id = True
        self._frame = True
        self._frame_state = state
        self._frame_first = first

    def _wheel(
        mut self, event: InputEvent, mut lens: _Lens, x: Float32, y: Float32
    ):
        """Zoom, or change the field of view, by a wheel notch. three.js:
        `onWheel`.

        Args:
            event: The wheel notch.
            lens: The camera.
            x: The pointer's x, in pixels.
            y: The pointer's y, in pixels.
        """
        if not (self.enabled and self.enable_zoom):
            return
        var operation = self._operation_of(MOUSE_WHEEL, self._modifier(event))
        if operation == NO_OPERATION:
            return
        var sign = Float32(event.wheel) * WHEEL_PIXELS / NOTCH_PIXELS
        if operation == ZOOM_OPERATION:
            self._update_tb_state(lens, STATE_SCALE, True)
            var size = Float32(1)
            if sign > 0:
                size = 1 / (self.scale_factor**sign)
            elif sign < 0:
                size = self.scale_factor ** (-sign)
            var point = self.center()
            if self.cursor_zoom and self.enable_pan:
                var at = lens.quaternion().rotate(self._on_tb_plane(lens, x, y))
                point = at * (1 / lens.zoom) + point
            self._apply(lens, self._scale(lens, size, point))
        elif lens.perspective:
            self._update_tb_state(lens, STATE_FOV, True)
            var size = Float32(1)
            if sign > 0:
                size = 1 / self.scale_factor
            elif sign < 0:
                size = self.scale_factor
            self._vertigo(lens, size, lens.fov)
        if self._grid_on:
            self._grid_on = False
            self._draw_grid(lens)
        self._update_tb_state(lens, STATE_IDLE, False)
        self._changed = True

    def _resize(mut self, lens: _Lens):
        """Fit the gizmo to a view of a new size. three.js: `onWindowResize`.

        Args:
            lens: The camera.
        """
        self._tb_radius = self._calculate_tb_radius(lens)
        self._curve_radius = self._tb_radius / self._gizmo_scale()
        self._changed = True

    # --- the trackball -------------------------------------------------------

    def _ndc(self, x: Float32, y: Float32) -> Vector2:
        """Return a place in the view in normalized device coordinates.
        three.js: `getCursorNDC`.

        Args:
            x: Across, in pixels.
            y: Down, in pixels.

        Returns:
            The place, from -1 to 1 each way, y up.
        """
        var width = Float32(self._width)
        var height = Float32(self._height)
        return Vector2(x / width * 2 - 1, (height - y) / height * 2 - 1)

    def _cursor_position(self, lens: _Lens, x: Float32, y: Float32) -> Vector2:
        """Return a place in an orthographic camera's view, from its middle.
        three.js: `getCursorPosition`.

        Args:
            lens: The camera.
            x: Across, in pixels.
            y: Down, in pixels.

        Returns:
            The place, in meters at a zoom of one.
        """
        var ndc = self._ndc(x, y)
        return Vector2(
            ndc.x * (lens.right - lens.left) * 0.5,
            ndc.y * (lens.top - lens.bottom) * 0.5,
        )

    def _on_tb_surface(self, lens: _Lens, x: Float32, y: Float32) -> Vector3:
        """Return where the pointer meets the trackball, in the camera's axes
        from the center. three.js: `unprojectOnTbSurface`.

        Within a radius over the square root of two of the middle, the
        trackball is a sphere. Beyond it, it is a hyperboloid.

        Args:
            lens: The camera.
            x: Across, in pixels.
            y: Down, in pixels.

        Returns:
            The point.
        """
        var r2 = self._tb_radius * self._tb_radius
        if not lens.perspective:
            var at = self._cursor_position(lens, x, y)
            var d2 = at.x * at.x + at.y * at.y
            var z = (r2 * 0.5) / sqrt(d2)
            if d2 <= r2 * 0.5:
                z = sqrt(r2 - d2)
            return Vector3(at.x, at.y, z)
        var near = lens.near_point(self._ndc(x, y))
        var ray = near
        ray.normalize()
        var reach = _distance(lens.position(), self.center())
        var l = sqrt(near.x * near.x + near.y * near.y)
        if l == 0:
            return Vector3(near.x, near.y, self._tb_radius)
        var m = near.z / l
        var q = reach
        var a = m * m + 1
        var b = 2 * m * q
        var c = q * q - r2
        var delta = b * b - 4 * a * c
        if delta >= 0:
            var px = (-b - sqrt(delta)) / (2 * a)
            var py = m * px + q
            var angle = (atan2(-py, -px) + HALF_TURN) * DEGREES_PER_RADIAN
            if angle >= 45:
                return _along(ray, px, py, reach)
        # The hyperboloid y = r^2 / (2 x).
        a = m
        b = q
        c = -r2 * 0.5
        delta = b * b - 4 * a * c
        var px = (-b - sqrt(delta)) / (2 * a)
        var py = m * px + q
        return _along(ray, px, py, reach)

    def _on_tb_plane(self, lens: _Lens, x: Float32, y: Float32) -> Vector3:
        """Return where the pointer meets the plane through the center that
        faces the camera, in the camera's axes from the center. three.js:
        `unprojectOnTbPlane`.

        Args:
            lens: The camera.
            x: Across, in pixels.
            y: Down, in pixels.

        Returns:
            The point, with z zero.
        """
        if not lens.perspective:
            var at = self._cursor_position(lens, x, y)
            return Vector3(at.x, at.y, 0)
        var near = lens.near_point(self._ndc(x, y))
        var ray = near
        ray.normalize()
        var l = sqrt(near.x * near.x + near.y * near.y)
        if l == 0:
            return Vector3(0, 0, 0)
        var q = _distance(lens.position(), self.center())
        var across = -q / (near.z / l)
        var length = sqrt(q * q + across * across)
        return Vector3(ray.x * length, ray.y * length, 0)

    def _calculate_tb_radius(self, lens: _Lens) -> Float32:
        """Return the trackball's radius: `radius_factor` of the smaller
        side of the view at the center. three.js: `calculateTbRadius`.

        Args:
            lens: The camera.

        Returns:
            The radius.
        """
        if lens.perspective:
            var reach = _distance(lens.position(), self.center())
            var half_v = lens.fov * 0.5
            var half_h = atan(lens.aspect * tan(half_v))
            return tan(min(half_v, half_h)) * reach * self.radius_factor
        return min(lens.top, lens.right) * self.radius_factor

    def _rotation_axis(self, a: Vector3, b: Vector3) -> Vector3:
        """Return the world axis a drag from one point of the trackball to
        another turns about. three.js: `calculateRotationAxis`.

        Args:
            a: Where the drag started, in the camera's axes.
            b: Where it is.

        Returns:
            The unit axis.
        """
        var axis = a
        axis.cross(b)
        axis = Quaternion.from_matrix(self._camera_state).rotate(axis)
        axis.normalize()
        return axis

    def _gizmo_scale(self) -> Float32:
        """Return the gizmo's scale, the mean of its three.

        Returns:
            The scale.
        """
        ref e = self._gizmo.elements
        var sx = Vector3(e[0], e[1], e[2]).length()
        var sy = Vector3(e[4], e[5], e[6]).length()
        var sz = Vector3(e[8], e[9], e[10]).length()
        return (sx + sy + sz) / 3

    def _make_gizmos(mut self, lens: _Lens, center: Vector3, radius: Float32):
        """Build the gizmo about a center, dim, at a scale that undoes an
        orthographic camera's zoom. three.js: `makeGizmos`.

        Args:
            lens: The camera.
            center: The center.
            radius: The circles' radius.
        """
        self._curve_radius = radius
        self._gizmos_active = False
        self._gizmo_state0 = _moved(center)
        self._gizmo_state = self._gizmo_state0
        if lens.zoom != 1:
            self._gizmo_state = _about(center, 1 / lens.zoom)
            self._gizmo_state.multiply(self._gizmo_state0)
        self._gizmo = self._gizmo_state

    # --- the operations ------------------------------------------------------

    def _apply(mut self, mut lens: _Lens, transformation: _Transformation):
        """Apply an operation to where the camera and the gizmo were when it
        began. three.js: `applyTransformMatrix`.

        Args:
            lens: The camera.
            transformation: The operation.
        """
        var camera = transformation.camera
        camera.multiply(self._camera_state)
        lens.matrix = camera
        if self._state == STATE_ROTATE or self._state == STATE_ANIMATION_ROTATE:
            # three.js turns the first up; see the module's notes.
            self._up = lens.quaternion().rotate(Vector3(0, 1, 0))
        if transformation.has_gizmos:
            var gizmo = transformation.gizmos
            gizmo.multiply(self._gizmo_state)
            self._gizmo = gizmo
        if (
            self._state == STATE_SCALE
            or self._state == STATE_FOCUS
            or self._state == STATE_ANIMATION_FOCUS
        ):
            self._tb_radius = self._calculate_tb_radius(lens)
            if self.adjust_near_far:
                self._adjust_near_far(lens)
            else:
                lens.near = self._initial_near
                lens.far = self._initial_far

    def _adjust_near_far(self, mut lens: _Lens):
        """Move the near and far planes to keep what the first ones showed,
        and to keep the gizmo in view.

        Args:
            lens: The camera.
        """
        var center = self.center()
        var reach = _distance(lens.position(), center)
        # three.js bounds the gizmo by a box and the box by a sphere.
        var radius = SQRT_3 * self._curve_radius * self._gizmo_scale()
        var outward = center.length()
        var adjusted_near = max(self._near_pos0, radius + outward)
        var regular_near = reach - self._initial_near
        lens.near = reach - min(adjusted_near, regular_near)
        var adjusted_far = min(self._far_pos0, -radius + outward)
        var regular_far = reach - self._initial_far
        lens.far = reach - min(adjusted_far, regular_far)

    def _pan(
        self, lens: _Lens, start: Vector3, end: Vector3
    ) -> _Transformation:
        """Return the move of a pan from one point of the plane to another.
        three.js: `pan`.

        Args:
            lens: The camera.
            start: Where the pan started, in the camera's axes.
            end: Where it is.

        Returns:
            The same move for the camera and the gizmo.
        """
        var movement = (start - end) * (1 / lens.zoom)
        var offset = lens.quaternion().rotate(
            Vector3(movement.x, movement.y, 0)
        )
        var move = _moved(offset)
        return _Transformation(move, move, True)

    def _rotate(self, axis: Vector3, angle: Float32) -> _Transformation:
        """Return a turn of the camera about the center. three.js: `rotate`.

        Args:
            axis: The unit axis.
            angle: The angle, in radians.

        Returns:
            The turn, for the camera alone.
        """
        var point = self.center()
        var turn = _moved(point)
        turn.multiply(
            Quaternion.from_axis_angle(axis, Angle(-angle, RADIAN)).to_matrix()
        )
        turn.multiply(_moved(-point))
        return _Transformation(turn, Matrix4(), False)

    def _scale(
        self,
        mut lens: _Lens,
        size: Float32,
        point: Vector3,
        scale_gizmos: Bool = True,
    ) -> _Transformation:
        """Return a zoom by a factor toward a point. An orthographic camera's
        zoom changes here. three.js: `scale`.

        Args:
            lens: The camera.
            size: The factor. More than one zooms in.
            point: The point zoomed toward.
            scale_gizmos: Whether to scale the gizmo too, to keep its size
                on the screen.

        Returns:
            The move of the camera, and the move and scale of the gizmo.
        """
        var size_inverse = 1 / size
        var gizmo = _position(self._gizmo_state)
        if not lens.perspective:
            lens.zoom = self._zoom_state * size
            if lens.zoom > self.max_zoom:
                lens.zoom = self.max_zoom
                size_inverse = self._zoom_state / self.max_zoom
            elif lens.zoom < self.min_zoom:
                lens.zoom = self.min_zoom
                size_inverse = self._zoom_state / self.min_zoom
            var toward = point - gizmo
            toward = toward - toward * size_inverse
            var move = _moved(toward)
            var gizmos = _about(gizmo, size_inverse)
            gizmos.premultiply(move)
            return _Transformation(move, gizmos, True)
        var eye = _position(self._camera_state)
        var distance = _distance(eye, point)
        var amount = distance - distance * size_inverse
        var new_distance = distance - amount
        var low = self.min_distance.to(METER)
        var high = self.max_distance.to(METER)
        if new_distance < low:
            size_inverse = low / distance
            amount = distance - distance * size_inverse
        elif new_distance > high:
            size_inverse = high / distance
            amount = distance - distance * size_inverse
        var offset = point - eye
        offset.normalize()
        var move = _moved(offset * amount)
        if not scale_gizmos:
            return _Transformation(move, Matrix4(), False)
        distance = _distance(gizmo, point)
        amount = distance - distance * size_inverse
        offset = point - gizmo
        offset.normalize()
        var gizmos = _moved(offset * amount)
        gizmos.multiply(_about(gizmo, size_inverse))
        return _Transformation(move, gizmos, True)

    def _set_fov(self, mut lens: _Lens, value: Float32):
        """Set a perspective camera's field of view, within its limits.
        three.js: `setFov`.

        Args:
            lens: The camera, perspective.
            value: The field of view, in radians.
        """
        lens.fov = _clamp(
            value, self.min_fov.to(RADIAN), self.max_fov.to(RADIAN)
        )

    def _focus(
        mut self,
        mut lens: _Lens,
        point: Vector3,
        size: Float32,
        amount: Float32 = 1,
    ):
        """Move the center a part of the way to a point, and zoom. three.js:
        `focus`.

        Args:
            lens: The camera.
            point: The point.
            size: The zoom.
            amount: How much of the way, from zero to one.
        """
        var move = _moved((point - self.center()) * amount)
        var gizmo_state = self._gizmo_state
        self._gizmo_state.premultiply(move)
        self._gizmo = self._gizmo_state
        var camera_state = self._camera_state
        self._camera_state.premultiply(move)
        lens.matrix = self._camera_state
        if self.enable_zoom:
            self._apply(lens, self._scale(lens, size, self.center()))
        self._gizmo_state = gizmo_state
        self._camera_state = camera_state

    def _update_tb_state(
        mut self, lens: _Lens, state: ArcballState, update_matrices: Bool
    ):
        """Enter a state, and record where the camera and the gizmo are if
        asked. three.js: `updateTbState` and `updateMatrixState`.

        Args:
            lens: The camera.
            state: The state.
            update_matrices: Whether to record them.
        """
        self._state = state
        if update_matrices:
            self._update_matrix_state(lens)

    def _update_matrix_state(mut self, lens: _Lens):
        """Record where the camera and the gizmo are. three.js:
        `updateMatrixState`.

        Args:
            lens: The camera.
        """
        self._camera_state = lens.matrix
        self._gizmo_state = self._gizmo
        if lens.perspective:
            self._fov_state = lens.fov
        else:
            self._zoom_state = lens.zoom

    def activate_gizmos(mut self, active: Bool):
        """Make the gizmo bright or dim. three.js: `activateGizmos`.

        Args:
            active: True for bright, during a turn.
        """
        self._gizmos_active = active

    def set_gizmos_visible(mut self, visible: Bool):
        """Show or hide the gizmo. three.js: `setGizmosVisible`.

        Args:
            visible: True to show it.
        """
        self._gizmos_visible = visible
        self._changed = True

    def set_tb_radius(
        mut self, value: Float32, camera: PerspectiveCamera
    ) raises:
        """Set `radius_factor` and redraw the gizmo. three.js: `setTbRadius`.

        Args:
            value: The factor.
            camera: The camera.

        Raises:
            Error: If the factor is not positive, or the camera rides a
                node.
        """
        self._set_tb_radius(value, _Lens(camera))

    def set_tb_radius(
        mut self, value: Float32, camera: OrthographicCamera
    ) raises:
        """Set `radius_factor` and redraw the gizmo, for an orthographic
        camera. three.js: `setTbRadius`.

        Args:
            value: The factor.
            camera: The camera.

        Raises:
            Error: If the factor is not positive, or the camera rides a
                node.
        """
        self._set_tb_radius(value, _Lens(camera))

    def _set_tb_radius(mut self, value: Float32, lens: _Lens) raises:
        """Set `radius_factor` and redraw the gizmo.

        Args:
            value: The factor.
            lens: The camera.

        Raises:
            Error: If the factor is not positive.
        """
        if not (value > 0):
            raise Error("The radius factor must be positive")
        self.radius_factor = value
        self._tb_radius = self._calculate_tb_radius(lens)
        self._curve_radius = self._tb_radius
        self._changed = True

    # --- the frame -----------------------------------------------------------

    def update(
        mut self, mut camera: PerspectiveCamera, delta: Duration = FRAME
    ) raises -> Bool:
        """Move the clock, run the animation frame asked for, and keep a
        perspective camera within its limits. three.js: the animation
        frames, then `update`.

        Args:
            camera: The camera. It is read, moved, and written back.
            delta: The time since the last frame.

        Returns:
            True if the camera or the gizmo changed since the last call:
            three.js's `change` event.

        Raises:
            Error: If the time is negative, a setting is refused by `check`,
                or the camera rides a node.
        """
        var lens = _Lens(camera)
        self._update(lens, delta)
        lens.put(camera, self.center())
        return self._take_change()

    def update(
        mut self, mut camera: OrthographicCamera, delta: Duration = FRAME
    ) raises -> Bool:
        """Move the clock, run the animation frame asked for, and keep an
        orthographic camera within its limits. three.js: the animation
        frames, then `update`.

        Args:
            camera: The camera. It is read, moved, and written back.
            delta: The time since the last frame.

        Returns:
            True if the camera or the gizmo changed since the last call:
            three.js's `change` event.

        Raises:
            Error: If the time is negative, a setting is refused by `check`,
                or the camera rides a node.
        """
        var lens = _Lens(camera)
        self._update(lens, delta)
        lens.put(camera, self.center())
        return self._take_change()

    def _take_change(mut self) -> Bool:
        """Return whether anything changed, and forget it.

        Returns:
            Whether three.js would have sent `change`.
        """
        var changed = self._changed
        self._changed = False
        return changed

    def _update(mut self, mut lens: _Lens, delta: Duration) raises:
        """Move the clock, run the frame, and do three.js's `update`.

        Args:
            lens: The camera.
            delta: The time since the last frame.

        Raises:
            Error: If the time is negative, a setting is refused, or the
                camera's placement is refused.
        """
        if delta.value < 0:
            raise Error("A frame cannot take a negative time")
        self.check()
        self._now += Float64(delta.to(MILLISECOND))
        if self._frame:
            self._frame = False
            if self._frame_first:
                var state = self._frame_state
                self._update_tb_state(lens, state, True)
                self._frame_first = False
                self._anim_gizmo = self._gizmo_state
                self._anim_axis = self._rotation_axis(
                    self._cursor_pos_prev, self._cursor_pos_curr
                )
            if self._frame_state == STATE_ANIMATION_ROTATE:
                self._on_rotation_anim(lens)
            else:
                self._on_focus_anim(lens)
        self._settle(lens)

    def _on_focus_anim(mut self, mut lens: _Lens):
        """Move the center a frame's part of the way to the point double
        clicked. three.js: `onFocusAnim`.

        Args:
            lens: The camera.
        """
        if self._time_start == -1:
            self._time_start = self._now
        if self._state != STATE_ANIMATION_FOCUS:
            self._animation_id = False
            self._time_start = -1
            return
        var elapsed = self._now - self._time_start
        var total = Float64(self.focus_animation_time.to(MILLISECOND))
        var part = Float32(elapsed / total)
        self._gizmo_state = self._anim_gizmo
        self._gizmo = self._gizmo_state
        if part >= 1:
            var point = self._anim_point
            self._focus(lens, point, self.scale_factor)
            self._time_start = -1
            self._update_tb_state(lens, STATE_IDLE, False)
            self.activate_gizmos(False)
            self._changed = True
            return
        var amount = _ease_out_cubic(part)
        var size = (1 - amount) + self.scale_factor * amount
        var point = self._anim_point
        self._focus(lens, point, size, amount)
        self._changed = True
        self._request(STATE_ANIMATION_FOCUS, False)
        self._anim_gizmo = self._gizmo_state

    def _on_rotation_anim(mut self, mut lens: _Lens):
        """Turn the camera on by a frame of a turn let go, slowing down.
        three.js: `onRotationAnim`.

        Args:
            lens: The camera.
        """
        if self._time_start == -1:
            self._angle_prev = 0
            self._angle_current = 0
            self._time_start = self._now
        if self._state != STATE_ANIMATION_ROTATE:
            self._animation_id = False
            self._time_start = -1
            if self._state != STATE_ROTATE:
                self.activate_gizmos(False)
                self._changed = True
            return
        var elapsed = Float32((self._now - self._time_start) / 1000)
        var damping = self.damping_factor.to(RADIAN_PER_SECOND_SQUARED)
        var w = self._anim_w0 - damping * elapsed
        if w > 0:
            self._angle_current = (
                0.5 * -damping * elapsed * elapsed + self._anim_w0 * elapsed
            )
            self._apply(
                lens, self._rotate(self._anim_axis, self._angle_current)
            )
            self._changed = True
            self._request(STATE_ANIMATION_ROTATE, False)
            return
        self._animation_id = False
        self._time_start = -1
        self._update_tb_state(lens, STATE_IDLE, False)
        self.activate_gizmos(False)
        self._changed = True

    def _settle(mut self, mut lens: _Lens) raises:
        """Follow a changed `target`, keep the camera within its limits, and
        turn it to the center. three.js: `update`.

        Args:
            lens: The camera.

        Raises:
            Error: If the camera's placement is refused.
        """
        var moved = self.target - self._current_target
        if moved.dot(moved) != 0:
            # The gizmo moves first, for the radius.
            self._gizmo = _moved(self.target)
            self._tb_radius = self._calculate_tb_radius(lens)
            var target = self.target
            self._make_gizmos(lens, target, self._tb_radius)
            self._current_target = target
        if not lens.perspective:
            if lens.zoom > self.max_zoom or lens.zoom < self.min_zoom:
                var zoom = _clamp(lens.zoom, self.min_zoom, self.max_zoom)
                self._apply(
                    lens, self._scale(lens, zoom / lens.zoom, self.center())
                )
        else:
            var distance = _distance(lens.position(), self.center())
            var low = self.min_distance.to(METER)
            var high = self.max_distance.to(METER)
            if distance > high + EPSILON or distance < low - EPSILON:
                var reach = _clamp(distance, low, high)
                self._apply(
                    lens, self._scale(lens, reach / distance, self.center())
                )
                self._update_matrix_state(lens)
            self._set_fov(lens, lens.fov)
            var old_radius = self._tb_radius
            self._tb_radius = self._calculate_tb_radius(lens)
            if (
                old_radius < self._tb_radius - EPSILON
                or old_radius > self._tb_radius + EPSILON
            ):
                self._curve_radius = self._tb_radius / self._gizmo_scale()
        self._look_at(lens, self.center())

    def _look_at(self, mut lens: _Lens, point: Vector3) raises:
        """Turn the camera to a point, with three.js's `up`. three.js:
        `lookAt`.

        Args:
            lens: The camera.
            point: The point.

        Raises:
            Error: If `look_at` refuses the placement.
        """
        lens.matrix = _world(lens.position(), point, self._up)

    # --- state -------------------------------------------------------------

    def reset(mut self, mut camera: PerspectiveCamera) raises:
        """Put a perspective camera and the trackball back where they began,
        or where `save_state` recorded. three.js: `reset`.

        Args:
            camera: The camera.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        var lens = _Lens(camera)
        lens.fov = self._fov0
        self._reset(lens)
        lens.put(camera, self.center())

    def reset(mut self, mut camera: OrthographicCamera) raises:
        """Put an orthographic camera and the trackball back where they
        began, or where `save_state` recorded. three.js: `reset`.

        Args:
            camera: The camera.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        var lens = _Lens(camera)
        self._reset(lens)
        lens.put(camera, self.center())

    def _reset(mut self, mut lens: _Lens) raises:
        """Put the camera and the trackball back.

        Args:
            lens: The camera.

        Raises:
            Error: If the camera's placement is refused.
        """
        self.target = self._target0
        lens.zoom = self._zoom0
        lens.near = self._near_pos
        lens.far = self._far_pos
        self._camera_state = self._camera_state0
        lens.matrix = self._camera_state0
        self._up = self._up0
        self._gizmo_state = self._gizmo_state0
        self._gizmo = self._gizmo_state0
        self._tb_radius = self._calculate_tb_radius(lens)
        self._make_gizmos(lens, self.center(), self._tb_radius)
        self._look_at(lens, self.center())
        self._update_tb_state(lens, STATE_IDLE, False)
        self._changed = True

    def save_state(mut self, camera: PerspectiveCamera) raises:
        """Record a perspective camera and the trackball for `reset`.
        three.js: `saveState`.

        Args:
            camera: The camera.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        var lens = _Lens(camera)
        self._fov0 = lens.fov
        self._save_state(lens)

    def save_state(mut self, camera: OrthographicCamera) raises:
        """Record an orthographic camera and the trackball for `reset`.
        three.js: `saveState`.

        Args:
            camera: The camera.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        self._save_state(_Lens(camera))

    def _save_state(mut self, lens: _Lens):
        """Record the camera and the trackball.

        Args:
            lens: The camera.
        """
        self._target0 = self.target
        self._camera_state0 = lens.matrix
        self._gizmo_state0 = self._gizmo
        self._near_pos = lens.near
        self._far_pos = lens.far
        self._zoom0 = lens.zoom
        self._up0 = self._up

    def copy_state(self, camera: PerspectiveCamera) raises -> ArcballSnapshot:
        """Return a perspective camera and the trackball as a value.
        three.js: `copyState`, which writes the same to the clipboard.

        Args:
            camera: The camera.

        Returns:
            The snapshot.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        return self._copy_state(_Lens(camera))

    def copy_state(self, camera: OrthographicCamera) raises -> ArcballSnapshot:
        """Return an orthographic camera and the trackball as a value.
        three.js: `copyState`.

        Args:
            camera: The camera.

        Returns:
            The snapshot.

        Raises:
            Error: If the camera rides a node, or its placement is refused.
        """
        return self._copy_state(_Lens(camera))

    def _copy_state(self, lens: _Lens) -> ArcballSnapshot:
        """Return the camera and the trackball as a value.

        Args:
            lens: The camera.

        Returns:
            The snapshot.
        """
        return ArcballSnapshot(
            lens.matrix,
            self._up,
            Length(lens.near, METER),
            Length(lens.far, METER),
            lens.zoom,
            Angle(lens.fov if lens.perspective else self._fov0, RADIAN),
            self._gizmo,
            self.target,
        )

    def paste_state(
        mut self, mut camera: PerspectiveCamera, snapshot: ArcballSnapshot
    ) raises:
        """Put a perspective camera and the trackball as a snapshot says.
        three.js: `pasteState`, which reads the clipboard.

        Args:
            camera: The camera.
            snapshot: What `copy_state` returned.

        Raises:
            Error: If the snapshot's field of view is not between zero and a
                half turn, its near plane is not in front of the camera, its
                far plane is not beyond the near, or its zoom is not
                positive. Also if the camera rides a node.
        """
        var fov = snapshot.camera_fov.to(RADIAN)
        if not (fov > 0 and fov < HALF_TURN):
            raise Error("A snapshot's field of view must be within a half turn")
        if not (snapshot.camera_near.value > 0):
            raise Error(
                "A snapshot's near plane must be in front of the camera"
            )
        var lens = _Lens(camera)
        lens.fov = fov
        self._paste_state(lens, snapshot)
        lens.put(camera, self.center())

    def paste_state(
        mut self, mut camera: OrthographicCamera, snapshot: ArcballSnapshot
    ) raises:
        """Put an orthographic camera and the trackball as a snapshot says.
        three.js: `pasteState`.

        Args:
            camera: The camera.
            snapshot: What `copy_state` returned.

        Raises:
            Error: If the snapshot's near plane is behind the camera, its far
                plane is not beyond the near, or its zoom is not positive.
                Also if the camera rides a node.
        """
        if snapshot.camera_near.value < 0:
            raise Error("A snapshot's near plane cannot be behind the camera")
        var lens = _Lens(camera)
        self._paste_state(lens, snapshot)
        lens.put(camera, self.center())

    def _paste_state(
        mut self, mut lens: _Lens, snapshot: ArcballSnapshot
    ) raises:
        """Put the camera and the trackball as a snapshot says. three.js:
        `setStateFromJSON`.

        Args:
            lens: The camera.
            snapshot: The snapshot.

        Raises:
            Error: If the far plane is not beyond the near, the zoom is not
                positive, or the camera's placement is refused.
        """
        if not (snapshot.camera_far.value > snapshot.camera_near.value):
            raise Error("A snapshot's far plane must be beyond its near plane")
        if not (snapshot.camera_zoom > 0):
            raise Error("A snapshot's zoom must be positive")
        self.target = snapshot.target
        self._camera_state = snapshot.camera_matrix
        lens.matrix = snapshot.camera_matrix
        self._up = snapshot.camera_up
        lens.near = snapshot.camera_near.to(METER)
        lens.far = snapshot.camera_far.to(METER)
        lens.zoom = snapshot.camera_zoom
        self._gizmo_state = snapshot.gizmo_matrix
        self._gizmo = snapshot.gizmo_matrix
        self._tb_radius = self._calculate_tb_radius(lens)
        var first = self._gizmo_state0
        self._make_gizmos(lens, self.center(), self._tb_radius)
        self._gizmo_state0 = first
        self._look_at(lens, self.center())
        self._update_tb_state(lens, STATE_IDLE, False)
        self._changed = True

    # --- drawing -------------------------------------------------------------

    def gizmo_opacity(self) -> Float32:
        """Return the opacity to draw the gizmo with: 1 during a turn, else
        0.6.

        Returns:
            The opacity.
        """
        return ACTIVE_GIZMO_OPACITY if self._gizmos_active else GIZMO_OPACITY

    def gizmo(self) raises -> BufferGeometry:
        """Return the trackball as line segments in world space. three.js:
        the three `Line`s of `_gizmos`.

        The circles are about the x, y and z axes, in red, green and blue.
        Draw them with a `Line` in `SEGMENTS` mode on a node at the origin,
        and `helper_material(gizmo_opacity(), transparent=True)`.

        Returns:
            Two points a segment, with a `color` attribute in linear light.
            None while the gizmo is hidden.

        Raises:
            Error: Never; the attributes are whole points.
        """
        var segments = Segments()
        if not (self._gizmos_visible and self.enable_gizmos):
            return segments.geometry()
        var circle = List[Vector3]()
        var x_ring = List[Vector3]()
        var y_ring = List[Vector3]()
        for index in range(CURVE_POINTS + 1):  # pragma: no branch
            var theta = Float32(index) / Float32(CURVE_POINTS) * 2 * HALF_TURN
            var a = self._curve_radius * cos(theta)
            var b = self._curve_radius * sin(theta)
            # three.js turns the x circle a quarter about x, and the y
            # circle a quarter about y.
            x_ring.append(Vector3(a, 0, b))
            y_ring.append(Vector3(0, b, -a))
            circle.append(Vector3(a, b, 0))
        segments.add_strip(
            x_ring, self._gizmo, FloatColor(srgb=Color(0xFF, 0x80, 0x80))
        )
        segments.add_strip(
            y_ring, self._gizmo, FloatColor(srgb=Color(0x80, 0xFF, 0x80))
        )
        segments.add_strip(
            circle, self._gizmo, FloatColor(srgb=Color(0x80, 0x80, 0xFF))
        )
        return segments.geometry()

    def grid(self) raises -> BufferGeometry:
        """Return the grid three.js shows during a pan with `enable_grid`,
        as line segments in world space. three.js: `drawGrid`.

        The grid faces the camera, through the center when the pan began.
        It is three times the view, in gray.

        Returns:
            Two points a segment, with a `color` attribute in linear light.
            None when no grid is shown.

        Raises:
            Error: Never; the attributes are whole points.
        """
        var segments = Segments()
        if not self._grid_on:
            return segments.geometry()
        var color = FloatColor(srgb=Color(0x88, 0x88, 0x88))
        var place = _moved(self._grid_position)
        place.multiply(self._grid_rotation.to_matrix())
        var half = self._grid_size / 2
        var step = self._grid_size / Float32(GRID_DIVISIONS)
        for index in range(GRID_DIVISIONS + 1):  # pragma: no branch
            var k = -half + Float32(index) * step
            # three.js's grid lies in xz, turned a quarter about x to face
            # the camera: (x, 0, z) is (x, -z, 0).
            segments.add(
                place.transform_point(Vector3(-half, -k, 0)),
                place.transform_point(Vector3(half, -k, 0)),
                color,
            )
            segments.add(
                place.transform_point(Vector3(k, half, 0)),
                place.transform_point(Vector3(k, -half, 0)),
                color,
            )
        return segments.geometry()

    def _draw_grid(mut self, lens: _Lens):
        """Show the grid, unless it is shown. three.js: `drawGrid`.

        Args:
            lens: The camera.
        """
        if self._grid_on:
            return
        var longest: Float32
        if lens.perspective:
            var reach = _distance(lens.position(), self.center())
            var half_v = lens.fov * 0.5
            var half_h = atan(lens.aspect * tan(half_v))
            longest = tan(max(half_v, half_h)) * reach * 2
            self._grid_size = longest * GRID_MULTIPLIER
        else:
            # three.js takes bottom less top, which is never the larger.
            longest = max(lens.right - lens.left, lens.bottom - lens.top)
            self._grid_size = longest / lens.zoom * GRID_MULTIPLIER
        self._grid_on = True
        self._grid_position = self.center()
        self._grid_rotation = lens.quaternion()


def _check_placed(node: NodeId) raises:
    """Refuse a camera that rides a scene node.

    Args:
        node: The node the camera rides, or `NO_PARENT`.

    Raises:
        Error: If it rides one: three.js's controls need a camera that is
            not the child of another object.
    """
    if node != NO_PARENT:
        raise Error("ArcballControls need a placed camera, not one on a node")


def _check_action(
    operation: ArcballOperation, mouse: ArcballMouse, key: ArcballModifier
) raises:
    """Refuse an invalid operation, mouse or key.

    Args:
        operation: The operation.
        mouse: The button, or the wheel.
        key: The key.

    Raises:
        Error: If one is invalid.
    """
    if not operation.is_valid():
        raise Error("Invalid arcball operation: ", operation.value)
    if not mouse.is_valid():
        raise Error("Invalid arcball mouse input: ", mouse.value)
    if not key.is_valid():
        raise Error("Invalid arcball modifier: ", key.value)


def _state_of(operation: ArcballOperation) -> ArcballState:
    """Return the state an operation puts the controls in. three.js:
    `getOpStateFromAction`.

    Args:
        operation: A pan, a turn, a zoom or a change of field of view.

    Returns:
        The state.
    """
    if operation == PAN_OPERATION:
        return STATE_PAN
    if operation == ROTATE_OPERATION:
        return STATE_ROTATE
    if operation == ZOOM_OPERATION:
        return STATE_SCALE
    return STATE_FOV


def _has_face(kind: HitKind) -> Bool:
    """Return whether a hit is on a face, as three.js asks of a focus.

    Args:
        kind: What was hit.

    Returns:
        True for a mesh of any kind, False for a line, points or a sprite.
    """
    return (
        kind == MESH_HIT
        or kind == INSTANCED_HIT
        or kind == BATCHED_HIT
        or kind == LOD_HIT
        or kind == SKINNED_HIT
    )


def _apart(ax: Float32, ay: Float32, bx: Float32, by: Float32) -> Float32:
    """Return the distance between two places in the view. three.js:
    `calculatePointersDistance`.

    Args:
        ax: One place's x.
        ay: Its y.
        bx: The other's x.
        by: Its y.

    Returns:
        The distance, in pixels.
    """
    return sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))


def _angular_speed(
    p0: Float32, p1: Float32, t0: Float64, t1: Float64
) -> Float32:
    """Return how fast an angle changed. three.js: `calculateAngularSpeed`.

    Args:
        p0: The angle before, in radians.
        p1: The angle after.
        t0: When it was before, in milliseconds.
        t1: When it was after.

    Returns:
        Radians a second, or zero for no time.
    """
    var seconds = Float32((t1 - t0) / 1000)
    return 0 if seconds == 0 else (p1 - p0) / seconds


def _ease_out_cubic(t: Float32) -> Float32:
    """Return three.js's `easeOutCubic`.

    Args:
        t: The part of the time gone, from zero to one.

    Returns:
        The part of the way gone.
    """
    return 1 - (1 - t) * (1 - t) * (1 - t)


def _along(ray: Vector3, px: Float32, py: Float32, reach: Float32) -> Vector3:
    """Return a point of the trackball along a ray from the camera, from
    the center.

    Args:
        ray: The unit ray, in the camera's axes.
        px: The point's distance from the view axis.
        py: Its height above the center along the view axis, toward the
            camera, as three.js measures it.
        reach: The center's distance from the camera.

    Returns:
        The point, in the camera's axes from the center.
    """
    var length = sqrt(px * px + (reach - py) * (reach - py))
    var point = ray * length
    point.z += reach
    return point


def _about(center: Vector3, size: Float32) -> Matrix4:
    """Return a uniform scale about a point.

    Args:
        center: The point that stays.
        size: The scale.

    Returns:
        The matrix.
    """
    var matrix = _moved(center)
    matrix.multiply(scaling(size, size, size))
    matrix.multiply(_moved(-center))
    return matrix^
