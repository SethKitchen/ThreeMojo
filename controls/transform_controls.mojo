# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gizmo that moves, turns and scales one node, from three.js
`examples/jsm/controls/TransformControls.js`.

`attach` gives the controls a node. `mode` says what a drag does:
`TRANSLATE_MODE`, `ROTATE_MODE` or `SCALE_MODE`. The gizmo has a handle
for each axis and for each plane, and a handle for all three axes at once.
Rotation has a ring about each axis, a ring that faces the eye (`E`), and
a ball that turns freely (`XYZE`).

**Picking.** A move with no drag on raycasts the handles of the current
mode, and the handle nearest along the ray becomes `axis`. The handles are
three.js's invisible picker shapes: cones along the axes, flat squares for
the planes, an octahedron, a box, tori and a sphere, built with this
project's geometries. They are placed at the node's world position, turned
to the node's frame in `LOCAL_SPACE`, and scaled so that they keep their
size on the screen, as three.js scales them.

**Dragging.** A press with the left button over a handle starts a drag.
The pointer is followed on a plane through the node: the plane that holds
the axis and faces the eye best, the plane of a plane handle, or the plane
that faces the camera. The arithmetic of each mode is three.js's, snapping
included. `SCALE_MODE` always works in the node's own frame. `XYZ`, `E`
and `XYZE` always work in the world's.

**Events.** A browser dispatches `axis-changed`, `dragging-changed`,
`mouseDown`, `objectChange` and `mouseUp`. Here `handle` returns them as
`TransformEvent` records, in three.js's order. three.js also dispatches
`change` with each of them, to ask for a render. That one is left out.

**Drawing.** `gizmo` returns the handles of the current mode as line
segments in world space, with a `color` attribute: red for x, green for y,
blue for z, and yellow for the handle under the pointer. Draw them with a
`Line` in `SEGMENTS` mode on a node at the origin, and `helper_material`.
three.js draws solid arrows and boxes with materials that ignore depth.
Here each shape is drawn by its edges.

The plane and the handles are worked out from the scene at each event,
as a render between two events works them out in three.js.

Differences from three.js: the helper lines shown during a drag, the
limits `minX` to `maxZ`, `setColors`, and touch input are not ported. A
scale whose start point has no length along an axis keeps that axis's
scale, where three.js divides by zero. The `E` picker is a flat ring, the
shape of three.js's torus with two segments around its tube, and the
pickers are tested from both sides.
"""

from cameras.camera import Camera
from controls.input import (
    InputEvent,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
)
from core.buffer_geometry import BufferGeometry
from core.object3d import NO_PARENT, NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from geometries.box import box
from geometries.circle import ring
from geometries.cylinder import cylinder
from geometries.polyhedron import octahedron
from geometries.sphere import sphere
from geometries.torus import torus
from helpers.segments import Segments
from math.bounds import Plane
from math.euler import Euler, XYZ
from math.matrix4 import Matrix4, scaling, translation
from math.quaternion import Quaternion
from math.ray import Ray
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import acos, atan2, cos, floor, inf, pi, sin, sqrt
from units.si import Angle, Length, METER, RADIAN

# An axis this close to the line of sight is hidden, and a plane this close
# to edge-on is hidden. three.js: `AXIS_HIDE_THRESHOLD` and
# `PLANE_HIDE_THRESHOLD`.
comptime AXIS_HIDE_THRESHOLD = Float32(0.99)
comptime PLANE_HIDE_THRESHOLD = Float32(0.2)
# A handle's size on the screen: the gizmo spans this share of the view's
# height at `size` one, and no more than this many meters a meter away.
comptime SCREEN_SHARE = Float32(1.9)
comptime MOST_SHARE = Float32(7)
# three.js: `ROTATION_SPEED` is this many radians a meter, over the
# distance from the camera.
comptime ROTATION_REACH = Float32(20)
# How many segments a drawn circle has, and a drawn cone.
comptime CIRCLE_SEGMENTS = 32
comptime CONE_SIDES = 8
comptime HALF_TURN = Float32(pi)
comptime QUARTER_TURN = Float32(pi / 2)


@fieldwise_init
struct TransformMode(Equatable, ImplicitlyCopyable, Writable):
    """What a drag does to the node, as a type rather than a bare int.
    three.js: `mode`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three modes.

        Returns:
            Whether the value names a mode.
        """
        return self.value >= 0 and self.value <= 2


# three.js: `'translate'`.
comptime TRANSLATE_MODE = TransformMode(0)
# three.js: `'rotate'`.
comptime ROTATE_MODE = TransformMode(1)
# three.js: `'scale'`.
comptime SCALE_MODE = TransformMode(2)


@fieldwise_init
struct TransformSpace(Equatable, ImplicitlyCopyable, Writable):
    """Whose axes the handles follow, as a type rather than a bare int.
    three.js: `space`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two spaces.

        Returns:
            Whether the value names a space.
        """
        return self.value == 0 or self.value == 1


# The world's axes. three.js: `'world'`.
comptime WORLD_SPACE = TransformSpace(0)
# The node's own axes. three.js: `'local'`.
comptime LOCAL_SPACE = TransformSpace(1)


@fieldwise_init
struct TransformAxis(Equatable, ImplicitlyCopyable, Writable):
    """Which handle is under the pointer or being dragged, as a type rather
    than a bare int. three.js: `axis`, a string of the axes it moves
    along."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the nine handles, or none.

        Returns:
            Whether the value names a handle.
        """
        return self.value >= 0 and self.value <= 9

    def name(self) raises -> String:
        """Return three.js's name for this handle.

        Returns:
            `X`, `Y`, `Z`, `XY`, `YZ`, `XZ`, `XYZ`, `E` or `XYZE`, or empty
            for no handle.

        Raises:
            Error: If the handle is invalid.
        """
        if not self.is_valid():
            raise Error("Invalid transform axis: ", self.value)
        var names: List[String] = [
            "",
            "X",
            "Y",
            "Z",
            "XY",
            "YZ",
            "XZ",
            "XYZ",
            "E",
            "XYZE",
        ]
        return names[self.value]

    def has(self, letter: String) raises -> Bool:
        """Return True if this handle's name holds `letter`. three.js:
        `axis.indexOf(letter) !== -1`.

        Args:
            letter: `X`, `Y`, `Z` or `E`.

        Returns:
            Whether the handle works along that axis.

        Raises:
            Error: If the handle is invalid.
        """
        return self.name().find(letter) != -1


comptime NO_HANDLE = TransformAxis(0)
comptime HANDLE_X = TransformAxis(1)
comptime HANDLE_Y = TransformAxis(2)
comptime HANDLE_Z = TransformAxis(3)
comptime HANDLE_XY = TransformAxis(4)
comptime HANDLE_YZ = TransformAxis(5)
comptime HANDLE_XZ = TransformAxis(6)
comptime HANDLE_XYZ = TransformAxis(7)
# The ring that faces the eye: a turn about the line of sight.
comptime HANDLE_E = TransformAxis(8)
# The ball: a turn about any axis, like a trackball.
comptime HANDLE_XYZE = TransformAxis(9)


@fieldwise_init
struct TransformEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What a transform event reports, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five kinds.

        Returns:
            Whether the value names a kind.
        """
        return self.value >= 0 and self.value <= 4


# `axis` changed. three.js: `axis-changed`.
comptime AXIS_CHANGED = TransformEventKind(0)
# `dragging` changed. three.js: `dragging-changed`.
comptime DRAGGING_CHANGED = TransformEventKind(1)
# A press on a handle started a drag. three.js: `mouseDown`.
comptime MOUSE_DOWN = TransformEventKind(2)
# A drag moved, turned or scaled the node. three.js: `objectChange`.
comptime OBJECT_CHANGE = TransformEventKind(3)
# A release ended a drag. three.js: `mouseUp`.
comptime MOUSE_UP = TransformEventKind(4)


@fieldwise_init
struct TransformEvent(ImplicitlyCopyable):
    """One thing that happened, with the controls' state after it."""

    var kind: TransformEventKind
    var mode: TransformMode
    var axis: TransformAxis
    var dragging: Bool


@fieldwise_init
struct Pose(ImplicitlyCopyable):
    """A transform taken apart: a position, a rotation and a scale.
    three.js: `Matrix4.decompose`."""

    var position: Vector3
    var quaternion: Quaternion
    var scale: Vector3


def decompose(matrix: Matrix4) raises -> Pose:
    """Take a transform apart, three.js's `Matrix4.decompose`.

    Args:
        matrix: A translation times a rotation times a scale.

    Returns:
        The three. A mirrored matrix gives a negative x scale, as in
        three.js.

    Raises:
        Error: If the matrix flattens an axis, which leaves no rotation.
    """
    var sx = Vector3(matrix.get(0, 0), matrix.get(1, 0), matrix.get(2, 0))
    var sy = Vector3(matrix.get(0, 1), matrix.get(1, 1), matrix.get(2, 1))
    var sz = Vector3(matrix.get(0, 2), matrix.get(1, 2), matrix.get(2, 2))
    var x = sx.length()
    var y = sy.length()
    var z = sz.length()
    if x * y * z == 0:
        raise Error("A transform that flattens an axis has no rotation")
    if matrix.determinant() < 0:
        x = -x
    var rotation = Matrix4()
    rotation.set(
        sx.x / x,
        sy.x / y,
        sz.x / z,
        0,
        sx.y / x,
        sy.y / y,
        sz.y / z,
        0,
        sx.z / x,
        sy.z / y,
        sz.z / z,
        0,
        0,
        0,
        0,
        1,
    )
    return Pose(
        Vector3(matrix.get(0, 3), matrix.get(1, 3), matrix.get(2, 3)),
        Quaternion.from_matrix(rotation),
        Vector3(x, y, z),
    )


struct TransformFrame(ImplicitlyCopyable):
    """Where a node and a camera are, as three.js's
    `TransformControlsRoot.updateMatrixWorld` works it out."""

    # The node's world transform, taken apart.
    var world: Pose
    # Its parent's world transform. The identity for a root node.
    var parent: Pose
    # The camera's world transform.
    var camera: Pose
    # The unit direction toward the eye: from the node to a perspective
    # camera, or back along an orthographic camera's view.
    var eye: Vector3
    # How big a handle is at `size` four, in meters, so that it keeps its
    # size on the screen.
    var factor: Float32

    def __init__[
        C: Camera
    ](out self, camera: C, scene: Scene, node: NodeId) raises:
        """Work out where a node and a camera are.

        Args:
            camera: The camera.
            scene: The scene, updated.
            node: The node the gizmo is on.

        Raises:
            Error: If the node or its parent is not in the scene, the scene
                is stale, a transform flattens an axis, or the camera cannot
                be read.
        """
        self.world = decompose(scene.world_matrix(node))
        self.parent = Pose(
            Vector3(0, 0, 0), Quaternion.identity(), Vector3(1, 1, 1)
        )
        var parent = scene.get(node).parent
        if parent != NO_PARENT:
            self.parent = decompose(scene.world_matrix(parent))
        var view = camera.view_matrix_in(scene)
        view.invert()
        self.camera = decompose(view)
        var projection = camera.projection_matrix()
        var zoom = projection.get(1, 1)
        if projection.is_affine():
            # three.js: `(top - bottom) / zoom`, which is 2 over this.
            self.eye = self.camera.quaternion.rotate(Vector3(0, 0, 1))
            self.factor = 2 / zoom
        else:
            # three.js: `tan(fov / 2) / zoom`, which is 1 over this.
            var offset = self.camera.position - self.world.position
            self.eye = offset
            self.eye.normalize()
            self.factor = offset.length() * min(SCREEN_SHARE / zoom, MOST_SHARE)


struct TransformControls(Copyable, Movable):
    """Turns pointer input into a node moved, turned or scaled by a
    gizmo."""

    # The node the gizmo is on, if any. three.js: `object`.
    var node: Optional[NodeId]
    # False to ignore all input.
    var enabled: Bool
    # The handle under the pointer, or being dragged.
    var axis: TransformAxis
    var mode: TransformMode
    var space: TransformSpace
    # A drag moves by whole steps of this, if set. Positive.
    var translation_snap: Optional[Length]
    # A drag turns by whole steps of this, if set. Positive.
    var rotation_snap: Optional[Angle]
    # A drag scales to whole steps of this, if set. Positive.
    var scale_snap: Optional[Float32]
    # A factor on the gizmo's size. Positive.
    var size: Float32
    # True while a drag is on.
    var dragging: Bool
    # False to hide and ignore the handles along an axis.
    var show_x: Bool
    var show_y: Bool
    var show_z: Bool
    # What picks the handles and finds the pointer on the drag plane.
    var raycaster: Raycaster
    # The box a moved node's position is kept in, three.js's `minX` to
    # `maxZ`: the node's own position, in its parent's frame. No limit by
    # default.
    var min_x: Length
    var max_x: Length
    var min_y: Length
    var max_y: Length
    var min_z: Length
    var max_z: Length
    # The handles' colors, three.js's `setColors`: the x, y and z handles,
    # and the handle under the pointer and the eye's ring.
    var x_color: Color
    var y_color: Color
    var z_color: Color
    var active_color: Color
    # The axis the last turn was about, in the world, three.js's
    # `rotationAxis`, for the helper line of a free turn.
    var _rotation_axis: Vector3

    # The node's own transform when the drag started.
    var _position_start: Vector3
    var _quaternion_start: Quaternion
    var _scale_start: Vector3
    # Its world position when the drag started.
    var _world_position_start: Vector3
    # Where the press and the last move met the drag plane, from
    # `_world_position_start`.
    var _point_start: Vector3
    var _point_end: Vector3

    def __init__(out self) raises:
        """Create controls with no node, and three.js's defaults.

        Raises:
            Error: Never; the raycaster's default range is valid.
        """
        self.node = None
        self.enabled = True
        self.axis = NO_HANDLE
        self.mode = TRANSLATE_MODE
        self.space = WORLD_SPACE
        self.translation_snap = None
        self.rotation_snap = None
        self.scale_snap = None
        self.size = 1.0
        self.dragging = False
        self.show_x = True
        self.show_y = True
        self.show_z = True
        self.raycaster = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1))
        var unbounded = Length(inf[DType.float32](), METER)
        self.min_x = -unbounded
        self.max_x = unbounded
        self.min_y = -unbounded
        self.max_y = unbounded
        self.min_z = -unbounded
        self.max_z = unbounded
        self.x_color = RED
        self.y_color = GREEN
        self.z_color = BLUE
        self.active_color = ACTIVE_COLOR
        self._rotation_axis = Vector3(0, 0, 0)
        self._position_start = Vector3(0, 0, 0)
        self._quaternion_start = Quaternion.identity()
        self._scale_start = Vector3(1, 1, 1)
        self._world_position_start = Vector3(0, 0, 0)
        self._point_start = Vector3(0, 0, 0)
        self._point_end = Vector3(0, 0, 0)

    def attach(mut self, node: NodeId):
        """Put the gizmo on a node.

        Args:
            node: The node to move, turn and scale.
        """
        self.node = node

    def detach(mut self):
        """Take the gizmo off its node."""
        self.node = None
        self.axis = NO_HANDLE

    def check(self) raises:
        """Refuse settings the controls cannot use.

        Raises:
            Error: If the mode, the space or the axis is invalid, the axis
                is not a handle of the mode, the size is not positive, or a
                snap is set and not positive.
        """
        if not self.mode.is_valid():
            raise Error("Invalid transform mode: ", self.mode.value)
        if not self.space.is_valid():
            raise Error("Invalid transform space: ", self.space.value)
        if not self.axis.is_valid():
            raise Error("Invalid transform axis: ", self.axis.value)
        if self.axis != NO_HANDLE and not _has_handle(self.mode, self.axis):
            raise Error("The mode has no handle ", self.axis.name())
        if not (self.size > 0):
            raise Error("A gizmo's size must be positive")
        var translation = self.translation_snap.or_else(Length(1.0, METER))
        if not (translation.value > 0):
            raise Error("A translation snap must be positive")
        var rotation = self.rotation_snap.or_else(Angle(1.0, RADIAN))
        if not (rotation.value > 0):
            raise Error("A rotation snap must be positive")
        if not (self.scale_snap.or_else(1.0) > 0):
            raise Error("A scale snap must be positive")

    def handle[
        C: Camera
    ](
        mut self,
        event: InputEvent,
        camera: C,
        mut scene: Scene,
        width: Int,
        height: Int,
    ) raises -> List[TransformEvent]:
        """Take one event: a move picks a handle or drags it, a press
        starts a drag, and a release ends it.

        Args:
            event: The event, with its position in pixels.
            camera: The camera the view is seen through.
            scene: The scene. It is updated first, and a drag moves, turns
                or scales the node.
            width: The view's width, in pixels.
            height: The view's height, in pixels.

        Returns:
            What happened, in three.js's order.

        Raises:
            Error: If the event's kind, button or key is invalid, a setting
                is refused by `check`, the view has no size, the node is
                not in the scene, or the camera or the scene cannot be
                read.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        self.check()
        var events = List[TransformEvent]()
        if not self.enabled:
            return events^
        if event.kind == POINTER_UP:
            # three.js lets go even with no node attached.
            if event.button == PRIMARY:
                self._release(events)
            return events^
        if not Bool(self.node):
            return events^
        if width <= 0 or height <= 0:
            raise Error("A view must have a positive width and height")
        scene.update()
        var frame = TransformFrame(camera, scene, self.node.value())
        self.raycaster.set_from_camera(
            Vector2(
                (Float32(event.x) + 0.5) / Float32(width) * 2 - 1,
                1 - (Float32(event.y) + 0.5) / Float32(height) * 2,
            ),
            camera,
            scene,
        )
        if event.kind == POINTER_DOWN:
            self._hover(frame, events)
            if event.button == PRIMARY:
                self._press(frame, scene, events)
        elif event.kind == POINTER_MOVE:
            self._hover(frame, events)
            self._drag(frame, scene, events)
        return events^

    def reset(mut self, mut scene: Scene) raises -> List[TransformEvent]:
        """Put the node back where the drag started, three.js's `reset`.
        The drag goes on from where the pointer is.

        Args:
            scene: The scene the node is in.

        Returns:
            `OBJECT_CHANGE`, or nothing when no drag is on.

        Raises:
            Error: If the node is not in the scene.
        """
        var events = List[TransformEvent]()
        var on = self.enabled and self.dragging and Bool(self.node)
        if not on:
            return events^
        ref node = scene.node(self.node.value())
        node.position = self._position_start
        node.quaternion = self._quaternion_start
        node.scale = self._scale_start
        self._point_start = self._point_end
        events.append(self._event(OBJECT_CHANGE))
        return events^

    def plane(self, frame: TransformFrame) raises -> Plane:
        """Return the plane a drag follows the pointer on. three.js:
        `TransformControlsPlane.updateMatrixWorld`.

        Args:
            frame: Where the node and the camera are.

        Returns:
            The plane through the node that holds the axis and faces the
            eye best, the plane of a plane handle, or the plane that faces
            the camera.

        Raises:
            Error: If the axis is invalid.
        """
        var turn = self._turn(frame)
        var v1 = turn.rotate(Vector3(1, 0, 0))
        var v2 = turn.rotate(Vector3(0, 1, 0))
        var v3 = turn.rotate(Vector3(0, 0, 1))
        var direction = Vector3(0, 0, 0)
        if self.mode != ROTATE_MODE:
            direction = _plane_direction(self.axis, v1, v2, v3, frame.eye)
        if direction.length() == 0:
            direction = frame.camera.quaternion.rotate(Vector3(0, 0, 1))
        return Plane.from_normal_and_point(direction, frame.world.position)

    def pick(self, frame: TransformFrame, ray: Ray) raises -> TransformAxis:
        """Return the handle a ray meets first. three.js: `pointerHover`.

        Args:
            frame: Where the node and the camera are.
            ray: The ray, in world space.

        Returns:
            The nearest handle of the mode that is shown, or `NO_HANDLE`.

        Raises:
            Error: If a setting is invalid.
        """
        var found = NO_HANDLE
        var nearest = inf[DType.float32]()
        for handle in _handles(self.mode):  # pragma: no branch
            if self._hidden(frame, handle):
                continue
            var place = self._place(frame, handle)
            var corners = _picker(self.mode, handle)
            for first in range(0, len(corners), 3):  # pragma: no branch
                var met = ray.intersect_triangle(
                    place.transform_point(corners[first]),
                    place.transform_point(corners[first + 1]),
                    place.transform_point(corners[first + 2]),
                    False,
                )
                if not Bool(met):
                    continue
                var distance = (met.value() - ray.origin).length()
                if distance < nearest:
                    nearest = distance
                    found = handle
        return found

    def gizmo[
        C: Camera
    ](self, camera: C, scene: Scene) raises -> BufferGeometry:
        """Return the handles of the mode as line segments in world space.
        three.js: `TransformControlsGizmo`.

        Args:
            camera: The camera the gizmo is seen through.
            scene: The scene, updated.

        Returns:
            Two points a segment, with a `color` attribute in linear light,
            for a `Line` in `SEGMENTS` mode on a node at the origin. None
            with no node attached.

        Raises:
            Error: If a setting is refused by `check`, the node is not in
                the scene, the scene is stale, or the camera cannot be
                read.
        """
        self.check()
        var segments = Segments()
        if not Bool(self.node):
            return segments.geometry()
        var frame = TransformFrame(camera, scene, self.node.value())
        for handle in _handles(self.mode):  # pragma: no branch
            if self._hidden(frame, handle):
                continue
            _draw(
                segments,
                self.mode,
                handle,
                self._place(frame, handle),
                self._color(handle),
            )
        return segments.geometry()

    def set_colors(mut self, x: Color, y: Color, z: Color, active: Color):
        """Recolor the handles, three.js's `setColors`.

        Args:
            x: The x handles' color, red by default.
            y: The y handles', green by default.
            z: The z handles', blue by default.
            active: The handle under the pointer, and the eye's ring,
                yellow by default.
        """
        self.x_color = x
        self.y_color = y
        self.z_color = z
        self.active_color = active

    def helper[
        C: Camera
    ](self, camera: C, scene: Scene) raises -> BufferGeometry:
        """Return the helper lines as segments in world space, three.js's
        helper objects in `TransformControlsGizmo`.

        For a move or a scale: a long line along each axis of the picked
        handle, through where a drag began, or through the node while none
        is on; and while a move is dragged, the line from where it began to
        where the node is. Around a turn: a long line along the
        handle's axis whenever one is picked, unless it points at the eye,
        or along the turn's axis while a free turn is dragged. White, as
        three.js's helper material is. The lines run as three.js's do,
        from minus a thousand to a million less a thousand times the
        handle's size.

        Args:
            camera: The camera the gizmo is seen through.
            scene: The scene, updated.

        Returns:
            Two points a segment, with a `color` attribute in linear light.
            None with no node attached.

        Raises:
            Error: If a setting is refused by `check`, the node is not in
                the scene, the scene is stale, or the camera cannot be
                read.
        """
        self.check()
        var segments = Segments()
        if not Bool(self.node) or self.axis == NO_HANDLE:
            return segments.geometry()
        var frame = TransformFrame(camera, scene, self.node.value())
        var white = FloatColor(1, 1, 1)
        var reach = frame.factor * self.size / 4
        var turn = self._turn(frame)
        if self.mode == ROTATE_MODE:
            var along = Vector3(0, 0, 0)
            var shown = False
            if self.axis == HANDLE_XYZE:
                along = self._rotation_axis
                shown = self.dragging
            elif self.axis != HANDLE_E:
                along = turn.rotate(_unit(self.axis))
                shown = abs(along.dot(frame.eye)) <= AXIS_FACING
            if shown:
                _long_line(segments, frame.world.position, along, reach, white)
            return segments.geometry()
        # The axis lines run through where a drag began, or through the
        # node while none is on. A move's drag also shows the line it
        # has made, three.js's `DELTA`.
        var start = (
            self._world_position_start if self.dragging else frame.world.position
        )
        if self.dragging and self.mode == TRANSLATE_MODE:
            segments.add(start, frame.world.position, white)
        var name = self.axis.name()
        var letters: List[String] = ["X", "Y", "Z"]
        var units: List[Vector3] = [
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
        ]
        for at in range(3):  # pragma: no branch
            if name.find(letters[at]) >= 0:
                _long_line(
                    segments, start, turn.rotate(units[at]), reach, white
                )
        return segments.geometry()

    def _event(self, kind: TransformEventKind) -> TransformEvent:
        """Return an event of `kind` with the controls' state.

        Args:
            kind: What happened.

        Returns:
            The event.
        """
        return TransformEvent(kind, self.mode, self.axis, self.dragging)

    def _set_axis(
        mut self, axis: TransformAxis, mut events: List[TransformEvent]
    ):
        """Set `axis`, reporting a change.

        Args:
            axis: The new handle.
            events: Where `AXIS_CHANGED` is appended.
        """
        if axis != self.axis:
            self.axis = axis
            events.append(self._event(AXIS_CHANGED))

    def _set_dragging(
        mut self, dragging: Bool, mut events: List[TransformEvent]
    ):
        """Set `dragging`, reporting a change.

        Args:
            dragging: Whether a drag is on.
            events: Where `DRAGGING_CHANGED` is appended.
        """
        if dragging != self.dragging:
            self.dragging = dragging
            events.append(self._event(DRAGGING_CHANGED))

    def _hover(
        mut self, frame: TransformFrame, mut events: List[TransformEvent]
    ) raises:
        """Pick the handle under the pointer, when no drag is on.

        Args:
            frame: Where the node and the camera are.
            events: Where `AXIS_CHANGED` is appended.

        Raises:
            Error: If a setting is invalid.
        """
        if self.dragging:
            return
        self._set_axis(self.pick(frame, self.raycaster.ray), events)

    def _press(
        mut self,
        frame: TransformFrame,
        scene: Scene,
        mut events: List[TransformEvent],
    ) raises:
        """Start a drag on the handle under the pointer. three.js:
        `pointerDown`.

        Args:
            frame: Where the node and the camera are.
            scene: The scene, updated.
            events: Where the events are appended.

        Raises:
            Error: If the node is not in the scene.
        """
        if self.dragging:
            return
        if self.axis == NO_HANDLE:
            return
        var node = scene.get(self.node.value())
        self._position_start = node.position
        self._quaternion_start = node.quaternion
        self._scale_start = node.scale
        self._world_position_start = frame.world.position
        # three.js keeps the last start point when the ray misses the plane.
        # A ray that meets a handle meets the plane through the node too,
        # so that keeps nothing in practice.
        var met = self.raycaster.ray.intersect_plane(self.plane(frame))
        var origin = frame.world.position
        self._point_start = met.or_else(origin + self._point_start) - origin
        self._set_dragging(True, events)
        events.append(self._event(MOUSE_DOWN))

    def _drag(
        mut self,
        frame: TransformFrame,
        mut scene: Scene,
        mut events: List[TransformEvent],
    ) raises:
        """Move, turn or scale the node by the pointer. three.js:
        `pointerMove`.

        Args:
            frame: Where the node and the camera are.
            scene: The scene, updated.
            events: Where `OBJECT_CHANGE` is appended.

        Raises:
            Error: If the node is not in the scene.
        """
        if not self.dragging or self.axis == NO_HANDLE:
            return
        var met = self.raycaster.ray.intersect_plane(self.plane(frame))
        if not Bool(met):
            return
        self._point_end = met.value() - self._world_position_start
        ref node = scene.node(self.node.value())
        if self.mode == TRANSLATE_MODE:
            self._translate(frame, node)
        elif self.mode == SCALE_MODE:
            self._scale(frame, node)
        else:
            self._rotate(frame, node)
        events.append(self._event(OBJECT_CHANGE))

    def _release(mut self, mut events: List[TransformEvent]):
        """End a drag. three.js: `pointerUp`.

        Args:
            events: Where the events are appended.
        """
        if self.dragging and self.axis != NO_HANDLE:
            events.append(self._event(MOUSE_UP))
        self._set_dragging(False, events)
        self._set_axis(NO_HANDLE, events)

    def _drag_space(self) -> TransformSpace:
        """Return the space a drag works in. Scaling is always local, and
        the handles for all axes are always in the world.

        Returns:
            The space.
        """
        var whole = (
            self.axis == HANDLE_E
            or self.axis == HANDLE_XYZE
            or self.axis == HANDLE_XYZ
        )
        return LOCAL_SPACE if self.mode == SCALE_MODE else (
            WORLD_SPACE if whole else self.space
        )

    def _translate(self, frame: TransformFrame, mut node: Object3D) raises:
        """Move the node by the pointer's movement on the plane.

        Args:
            frame: Where the node and the camera are.
            node: The node.

        Raises:
            Error: If the axis is invalid.
        """
        var local = self._drag_space() == LOCAL_SPACE
        var offset = self._point_end - self._point_start
        if local:
            offset = frame.world.quaternion.conjugate().rotate(offset)
        offset = _masked(offset, self.axis)
        var turn = frame.parent.quaternion.conjugate()
        if local:
            turn = self._quaternion_start
        node.position = (
            _divided(turn.rotate(offset), frame.parent.scale)
            + self._position_start
        )
        if Bool(self.translation_snap):
            var step = self.translation_snap.value().to(METER)
            if local:
                var along = self._quaternion_start.conjugate().rotate(
                    node.position
                )
                along = _snapped(along, step, self.axis)
                node.position = self._quaternion_start.rotate(along)
            else:
                var world = node.position + frame.parent.position
                world = _snapped(world, step, self.axis)
                node.position = world - frame.parent.position
        # three.js's `minX` to `maxZ`, after the snap.
        node.position = Vector3(
            _within(node.position.x, self.min_x, self.max_x),
            _within(node.position.y, self.min_y, self.max_y),
            _within(node.position.z, self.min_z, self.max_z),
        )

    def _scale(self, frame: TransformFrame, mut node: Object3D) raises:
        """Scale the node by the pointer's distance from its origin.

        Args:
            frame: Where the node and the camera are.
            node: The node.

        Raises:
            Error: If the axis is invalid.
        """
        var start = self._point_start
        var end = self._point_end
        var factor: Vector3
        if self.axis == HANDLE_XYZ:
            var ratio = _ratio(end.length(), start.length())
            if end.dot(start) < 0:
                ratio = -ratio
            factor = Vector3(ratio, ratio, ratio)
        else:
            var undo = frame.world.quaternion.conjugate()
            var from_ = undo.rotate(start)
            var to = undo.rotate(end)
            factor = Vector3(
                _ratio(to.x, from_.x) if self.axis.has("X") else 1,
                _ratio(to.y, from_.y) if self.axis.has("Y") else 1,
                _ratio(to.z, from_.z) if self.axis.has("Z") else 1,
            )
        node.scale = Vector3(
            self._scale_start.x * factor.x,
            self._scale_start.y * factor.y,
            self._scale_start.z * factor.z,
        )
        if not Bool(self.scale_snap):
            return
        var step = self.scale_snap.value()
        var scale = node.scale
        node.scale = Vector3(
            _scale_step(scale.x, step) if self.axis.has("X") else scale.x,
            _scale_step(scale.y, step) if self.axis.has("Y") else scale.y,
            _scale_step(scale.z, step) if self.axis.has("Z") else scale.z,
        )

    def _rotate(mut self, frame: TransformFrame, mut node: Object3D) raises:
        """Turn the node by the pointer's movement on the plane.

        Args:
            frame: Where the node and the camera are.
            node: The node.

        Raises:
            Error: If the axis is invalid.
        """
        var local = self._drag_space() == LOCAL_SPACE
        var eye = frame.eye
        var offset = self._point_end - self._point_start
        var speed = ROTATION_REACH / (
            (frame.world.position - frame.camera.position).length()
        )
        var axis = Vector3(0, 0, 0)
        var angle = Float32(0)
        var in_plane = False
        if self.axis == HANDLE_XYZE:
            axis = offset
            axis.cross(eye)
            axis.normalize()
            var across = axis
            across.cross(eye)
            angle = offset.dot(across) * speed
        elif self.axis != HANDLE_E:
            axis = _unit(self.axis)
            var across = axis
            if local:
                across = frame.world.quaternion.rotate(across)
            across.cross(eye)
            if across.length() == 0:
                # The axis is along the line of sight: turn in the plane.
                in_plane = True
            else:
                across.normalize()
                angle = offset.dot(across) * speed
        if self.axis == HANDLE_E or in_plane:
            axis = eye
            angle = _angle_between(self._point_end, self._point_start)
            var start = self._point_start
            var end = self._point_end
            start.normalize()
            end.normalize()
            end.cross(start)
            angle = angle if end.dot(eye) < 0 else -angle
        # three.js's `rotationAxis`, before it is taken into the parent.
        self._rotation_axis = axis
        if Bool(self.rotation_snap):
            var step = self.rotation_snap.value().to(RADIAN)
            angle = _js_round(angle / step) * step
        var turned: Quaternion
        if local:
            turned = self._quaternion_start
            turned.multiply(
                Quaternion.from_axis_angle(axis, Angle(angle, RADIAN))
            )
        else:
            axis = frame.parent.quaternion.conjugate().rotate(axis)
            turned = Quaternion.from_axis_angle(axis, Angle(angle, RADIAN))
            turned.multiply(self._quaternion_start)
        turned.normalize()
        node.quaternion = turned

    def _turn(self, frame: TransformFrame) -> Quaternion:
        """Return the rotation of the handles: the node's in `LOCAL_SPACE`
        or in `SCALE_MODE`, and none in `WORLD_SPACE`.

        Args:
            frame: Where the node is.

        Returns:
            The rotation.
        """
        var local = self.mode == SCALE_MODE or self.space == LOCAL_SPACE
        return frame.world.quaternion if local else Quaternion.identity()

    def _handle_turn(
        self, frame: TransformFrame, handle: TransformAxis
    ) raises -> Quaternion:
        """Return how one handle is turned. The rings of `ROTATE_MODE`
        turn to show their near half to the eye, and the `E` and `XYZE`
        rings face it.

        Args:
            frame: Where the node and the camera are.
            handle: The handle.

        Returns:
            The rotation.

        Raises:
            Error: If the handle is invalid.
        """
        var turn = self._turn(frame)
        if self.mode != ROTATE_MODE:
            return turn
        if handle.has("E"):
            # three.js: `lookAt(eye, zero, unitY)`. A ring is round, so any
            # turn that takes +z to the eye draws and picks the same ring.
            return Quaternion.from_unit_vectors(Vector3(0, 0, 1), frame.eye)
        var align = turn.conjugate().rotate(frame.eye)
        var spin: Quaternion
        if handle == HANDLE_X:
            spin = Quaternion.from_axis_angle(
                Vector3(1, 0, 0), Angle(atan2(-align.y, align.z), RADIAN)
            )
        elif handle == HANDLE_Y:
            spin = Quaternion.from_axis_angle(
                Vector3(0, 1, 0), Angle(atan2(align.x, align.z), RADIAN)
            )
        else:
            spin = Quaternion.from_axis_angle(
                Vector3(0, 0, 1), Angle(atan2(align.y, align.x), RADIAN)
            )
        turn.multiply(spin)
        return turn

    def _place(
        self, frame: TransformFrame, handle: TransformAxis
    ) raises -> Matrix4:
        """Return the transform from a handle's own space to the world.

        Args:
            frame: Where the node and the camera are.
            handle: The handle.

        Returns:
            At the node's world position, turned, and scaled to keep its
            size on the screen.

        Raises:
            Error: If the handle is invalid.
        """
        var position = frame.world.position
        var place = translation(position.x, position.y, position.z)
        place.multiply(self._handle_turn(frame, handle).to_matrix())
        var reach = frame.factor * self.size / 4
        place.multiply(scaling(reach, reach, reach))
        return place^

    def _hidden(
        self, frame: TransformFrame, handle: TransformAxis
    ) raises -> Bool:
        """Return True if a handle is neither drawn nor picked: an axis
        along the line of sight, a plane seen edge-on, or an axis that
        `show_x`, `show_y` or `show_z` turns off.

        Args:
            frame: Where the node and the camera are.
            handle: The handle.

        Returns:
            Whether the handle is hidden.

        Raises:
            Error: If the handle is invalid.
        """
        var along = abs(self._turn(frame).rotate(_unit(handle)).dot(frame.eye))
        var single = (
            handle == HANDLE_X or handle == HANDLE_Y or (handle == HANDLE_Z)
        )
        var flat = (
            handle == HANDLE_XY or handle == HANDLE_YZ or (handle == HANDLE_XZ)
        )
        var facing = self.mode != ROTATE_MODE and (
            (single and along > AXIS_HIDE_THRESHOLD)
            or (flat and along < PLANE_HIDE_THRESHOLD)
        )
        var every = self.show_x and self.show_y and self.show_z
        return (
            facing
            or (handle.has("X") and not self.show_x)
            or (handle.has("Y") and not self.show_y)
            or (handle.has("Z") and not self.show_z)
            or (handle.has("E") and not every)
        )

    def _color(self, handle: TransformAxis) raises -> FloatColor:
        """Return a handle's color: yellow when it is `axis` or one of its
        letters, else its own.

        Args:
            handle: The handle.

        Returns:
            The color, in linear light.

        Raises:
            Error: If the handle or `axis` is invalid.
        """
        var name = handle.name()
        var active = (
            self.enabled
            and self.axis != NO_HANDLE
            and (
                handle == self.axis
                or (name.byte_length() == 1 and self.axis.has(name))
            )
        )
        var own = _handle_color(handle)
        # three.js's `setColors` recolors the red, green and blue
        # materials, and the yellow of the eye's ring with the active one.
        if _same(own, RED):
            own = self.x_color
        elif _same(own, GREEN):
            own = self.y_color
        elif _same(own, BLUE):
            own = self.z_color
        elif _same(own, YELLOW):
            own = self.active_color
        return FloatColor(srgb=self.active_color) if active else FloatColor(
            srgb=own
        )


comptime RED = Color(0xFF, 0x00, 0x00)
comptime GREEN = Color(0x00, 0xFF, 0x00)
comptime BLUE = Color(0x00, 0x00, 0xFF)
comptime WHITE = Color(0xFF, 0xFF, 0xFF)
comptime YELLOW = Color(0xFF, 0xFF, 0x00)
comptime GRAY = Color(0x78, 0x78, 0x78)
# The color of the handle under the pointer. three.js: `materialLib.active`.
comptime ACTIVE_COLOR = YELLOW


# How nearly a rotation handle's axis may point at the eye and still show
# its helper line, three.js's 0.9.
comptime AXIS_FACING = Float32(0.9)


def _same(a: Color, b: Color) -> Bool:
    """Return whether two colors are one: every channel equal."""
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a


def _within(value: Float32, low: Length, high: Length) -> Float32:
    """Return a coordinate kept between two limits, three.js's
    `Math.max( min, Math.min( max, value ) )`."""
    return max(low.to(METER), min(high.to(METER), value))


def _long_line(
    mut segments: Segments,
    at: Vector3,
    along: Vector3,
    reach: Float32,
    color: FloatColor,
):
    """Add three.js's helper line through a point: its `lineGeometry` moved
    a thousand back and stretched a millionfold along `along`, then scaled
    by the handle's size."""
    segments.add(
        at + along * (-1000 * reach), at + along * (999000 * reach), color
    )


def _handle_color(handle: TransformAxis) -> Color:
    """Return a handle's own color, three.js's material for it.

    Args:
        handle: A valid handle.

    Returns:
        Red for x and the plane across it, green for y, blue for z, white
        for all three, yellow for the eye's ring and gray for the ball.
    """
    var colors: List[Color] = [
        WHITE,
        RED,
        GREEN,
        BLUE,
        BLUE,
        RED,
        GREEN,
        WHITE,
        YELLOW,
        GRAY,
    ]
    return colors[handle.value]


def _handles(mode: TransformMode) -> List[TransformAxis]:
    """Return the handles of a mode, in three.js's order.

    Args:
        mode: A valid mode.

    Returns:
        The handles.
    """
    if mode == ROTATE_MODE:
        return [HANDLE_XYZE, HANDLE_X, HANDLE_Y, HANDLE_Z, HANDLE_E]
    if mode == TRANSLATE_MODE:
        return [
            HANDLE_X,
            HANDLE_Y,
            HANDLE_Z,
            HANDLE_XYZ,
            HANDLE_XY,
            HANDLE_YZ,
            HANDLE_XZ,
        ]
    return [
        HANDLE_X,
        HANDLE_Y,
        HANDLE_Z,
        HANDLE_XY,
        HANDLE_YZ,
        HANDLE_XZ,
        HANDLE_XYZ,
    ]


def _has_handle(mode: TransformMode, axis: TransformAxis) -> Bool:
    """Return True if a mode has a handle.

    Args:
        mode: A valid mode.
        axis: A valid handle.

    Returns:
        Whether the mode's gizmo has it.
    """
    # Every mode has handles, so the loop always runs.
    for handle in _handles(mode):  # pragma: no branch
        if handle == axis:
            return True
    return False


def _unit(handle: TransformAxis) -> Vector3:
    """Return the axis of a handle, or the axis across a plane handle.

    Args:
        handle: A handle.

    Returns:
        +x for `X` and `YZ`, +y for `Y` and `XZ`, +z for `Z` and `XY`, and
        zero for the others.
    """
    var units: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
    ]
    return units[handle.value]


def _plane_direction(
    axis: TransformAxis, v1: Vector3, v2: Vector3, v3: Vector3, eye: Vector3
) -> Vector3:
    """Return which way the drag plane of a translate or scale handle faces.

    Args:
        axis: The handle.
        v1: The handles' x.
        v2: Their y.
        v3: Their z.
        eye: The direction toward the eye.

    Returns:
        For an axis, the part of the eye's direction at right angles to it;
        across the plane for a plane handle; zero for the others, which
        drag on the plane that faces the camera.
    """
    if axis == HANDLE_X:
        return _across(v1, eye)
    if axis == HANDLE_Y:
        return _across(v2, eye)
    if axis == HANDLE_Z:
        return _across(v3, eye)
    if axis == HANDLE_XY:
        return v3
    if axis == HANDLE_YZ:
        return v1
    if axis == HANDLE_XZ:
        return v2
    return Vector3(0, 0, 0)


def _across(along: Vector3, eye: Vector3) -> Vector3:
    """Return `along x (eye x along)`, three.js's `_dirVector` for an axis.

    Args:
        along: The axis.
        eye: The direction toward the eye.

    Returns:
        The direction.
    """
    var align = eye
    align.cross(along)
    var direction = along
    direction.cross(align)
    return direction


def _masked(offset: Vector3, axis: TransformAxis) raises -> Vector3:
    """Return `offset` with the parts along axes the handle lacks zeroed.

    Args:
        offset: The movement.
        axis: The handle.

    Returns:
        The movement along the handle's axes.

    Raises:
        Error: If the handle is invalid.
    """
    return Vector3(
        offset.x if axis.has("X") else 0,
        offset.y if axis.has("Y") else 0,
        offset.z if axis.has("Z") else 0,
    )


def _divided(value: Vector3, by: Vector3) -> Vector3:
    """Return `value` divided by `by`, part by part.

    Args:
        value: The dividend.
        by: The divisor.

    Returns:
        The quotient.
    """
    return Vector3(value.x / by.x, value.y / by.y, value.z / by.z)


def _js_round(value: Float32) -> Float32:
    """Return the nearest whole number, halves up, as JavaScript's
    `Math.round` rounds.

    Args:
        value: The number.

    Returns:
        The whole number.
    """
    return floor(value + 0.5)


def _snapped(
    value: Vector3, step: Float32, axis: TransformAxis
) raises -> Vector3:
    """Return `value` with the parts along the handle's axes rounded to
    whole steps.

    Args:
        value: The position.
        step: The step, positive.
        axis: The handle.

    Returns:
        The rounded position.

    Raises:
        Error: If the handle is invalid.
    """
    return Vector3(
        _js_round(value.x / step) * step if axis.has("X") else value.x,
        _js_round(value.y / step) * step if axis.has("Y") else value.y,
        _js_round(value.z / step) * step if axis.has("Z") else value.z,
    )


def _scale_step(value: Float32, step: Float32) -> Float32:
    """Return a scale rounded to whole steps, and never zero. three.js:
    `Math.round(scale / snap) * snap || snap`.

    Args:
        value: The scale.
        step: The step, positive.

    Returns:
        The rounded scale, or `step` where it rounds to zero.
    """
    var rounded = _js_round(value / step) * step
    return rounded if rounded != 0 else step


def _ratio(numerator: Float32, denominator: Float32) -> Float32:
    """Return a ratio, or one where the denominator is zero.

    Args:
        numerator: The new length.
        denominator: The old length.

    Returns:
        How many times longer.
    """
    return numerator / denominator if denominator != 0 else 1


def _angle_between(a: Vector3, b: Vector3) -> Float32:
    """Return the angle between two directions, three.js's `angleTo`.

    Args:
        a: One direction.
        b: The other.

    Returns:
        The angle in radians, or a quarter turn when either has no length.
    """
    var denominator = sqrt(a.dot(a) * b.dot(b))
    var cosine = a.dot(b) / denominator if denominator != 0 else Float32(0)
    return acos(max(Float32(-1), min(Float32(1), cosine)))


def _baked(
    geometry: BufferGeometry,
    offset: Vector3,
    x: Float32,
    y: Float32,
    z: Float32,
) raises -> List[Vector3]:
    """Return a picker shape's triangles, moved and turned into place.
    three.js: `setupGizmo`, which bakes each shape's position and rotation
    into its geometry.

    Args:
        geometry: The shape.
        offset: Where it goes.
        x: Its turn about x, in radians.
        y: About y.
        z: About z, in three.js's `XYZ` order.

    Returns:
        Three corners a triangle.

    Raises:
        Error: If the geometry cannot be read.
    """
    var place = translation(offset.x, offset.y, offset.z)
    place.multiply(
        Euler(
            Angle(x, RADIAN), Angle(y, RADIAN), Angle(z, RADIAN), XYZ
        ).to_matrix()
    )
    var corners = List[Vector3]()
    # Every picker shape has triangles, so the loops always run.
    for triangle in range(geometry.triangle_count()):  # pragma: no branch
        for corner in range(3):  # pragma: no branch
            corners.append(
                place.transform_point(geometry.corner(triangle, corner))
            )
    return corners^


def _picker(mode: TransformMode, handle: TransformAxis) raises -> List[Vector3]:
    """Return the triangles of a handle's picker, in the handle's space.
    three.js: `pickerTranslate`, `pickerRotate` and `pickerScale`.

    Args:
        mode: The mode.
        handle: One of its handles.

    Returns:
        Three corners a triangle.

    Raises:
        Error: If a geometry is refused, which none is.
    """
    var m = METER
    if mode == ROTATE_MODE:
        if handle == HANDLE_XYZE:
            return _baked(
                sphere(Length(0.25, m), 10, 8), Vector3(0, 0, 0), 0, 0, 0
            )
        if handle == HANDLE_E:
            return _baked(
                ring(Length(0.65, m), Length(0.85, m), 24),
                Vector3(0, 0, 0),
                0,
                0,
                0,
            )
        var tube = torus(Length(0.5, m), Length(0.1, m), 4, 24)
        if handle == HANDLE_X:
            return _baked(
                tube, Vector3(0, 0, 0), 0, -QUARTER_TURN, -QUARTER_TURN
            )
        if handle == HANDLE_Y:
            return _baked(tube, Vector3(0, 0, 0), QUARTER_TURN, 0, 0)
        return _baked(tube, Vector3(0, 0, 0), 0, 0, -QUARTER_TURN)
    var square = box(Length(0.2, m), Length(0.2, m), Length(0.01, m))
    if handle == HANDLE_XY:
        return _baked(square, Vector3(0.15, 0.15, 0), 0, 0, 0)
    if handle == HANDLE_YZ:
        return _baked(square, Vector3(0, 0.15, 0.15), 0, QUARTER_TURN, 0)
    if handle == HANDLE_XZ:
        return _baked(square, Vector3(0.15, 0, 0.15), -QUARTER_TURN, 0, 0)
    if handle == HANDLE_XYZ:
        if mode == TRANSLATE_MODE:
            return _baked(octahedron(Length(0.2, m)), Vector3(0, 0, 0), 0, 0, 0)
        return _baked(
            box(Length(0.2, m), Length(0.2, m), Length(0.2, m)),
            Vector3(0, 0, 0),
            0,
            0,
            0,
        )
    var cone = cylinder(Length(0.2, m), Length(0.0, m), Length(0.6, m), 4)
    var corners: List[Vector3]
    if handle == HANDLE_X:
        corners = _baked(cone, Vector3(0.3, 0, 0), 0, 0, -QUARTER_TURN)
        corners.extend(_baked(cone, Vector3(-0.3, 0, 0), 0, 0, QUARTER_TURN))
    elif handle == HANDLE_Y:
        corners = _baked(cone, Vector3(0, 0.3, 0), 0, 0, 0)
        corners.extend(_baked(cone, Vector3(0, -0.3, 0), 0, 0, HALF_TURN))
    else:
        corners = _baked(cone, Vector3(0, 0, 0.3), QUARTER_TURN, 0, 0)
        corners.extend(_baked(cone, Vector3(0, 0, -0.3), -QUARTER_TURN, 0, 0))
    return corners^


def _draw(
    mut segments: Segments,
    mode: TransformMode,
    handle: TransformAxis,
    place: Matrix4,
    color: FloatColor,
):
    """Draw one handle as line segments. three.js: `gizmoTranslate`,
    `gizmoRotate` and `gizmoScale`.

    Args:
        segments: Where the segments are added.
        mode: The mode.
        handle: One of its handles.
        place: From the handle's space to the world.
        color: The handle's color.
    """
    if mode == ROTATE_MODE:
        _draw_ring(segments, handle, place, color)
        return
    if handle == HANDLE_XYZ:
        if mode == TRANSLATE_MODE:
            _draw_octahedron(segments, place, color)
        else:
            _draw_box(
                segments,
                place,
                Vector3(0, 0, 0),
                Vector3(0.05, 0, 0),
                Vector3(0, 0.05, 0),
                Vector3(0, 0, 0.05),
                color,
            )
        return
    var across = _unit(handle)
    var single = handle == HANDLE_X or handle == HANDLE_Y or handle == HANDLE_Z
    if not single:
        # A square of 0.15 at 0.15 along both of the plane's axes, the axis
        # across it left out.
        var one = Vector3(across.y, across.z, across.x)
        var two = Vector3(across.z, across.x, across.y)
        var center = (one + two) * 0.15
        var corners = List[Vector3]()
        corners.append(center + one * 0.075 + two * 0.075)
        corners.append(center - one * 0.075 + two * 0.075)
        corners.append(center - one * 0.075 - two * 0.075)
        corners.append(center + one * 0.075 - two * 0.075)
        corners.append(center + one * 0.075 + two * 0.075)
        segments.add_strip(corners, place, color)
        return
    # An axis: a shaft to 0.5, and an arrow or a box at each end.
    var one = Vector3(across.y, across.z, across.x)
    var two = Vector3(across.z, across.x, across.y)
    segments.add(
        place.transform_point(Vector3(0, 0, 0)),
        place.transform_point(across * 0.5),
        color,
    )
    for sign in [Float32(1), Float32(-1)]:  # pragma: no branch
        var way = across * sign
        if mode == TRANSLATE_MODE:
            _draw_cone(segments, place, way, one, two, color)
        else:
            _draw_box(
                segments,
                place,
                way * 0.54,
                way * 0.04,
                one * 0.04,
                two * 0.04,
                color,
            )


def _draw_cone(
    mut segments: Segments,
    place: Matrix4,
    way: Vector3,
    one: Vector3,
    two: Vector3,
    color: FloatColor,
):
    """Draw an arrowhead from 0.5 to 0.6 along `way`, 0.04 in radius.

    Args:
        segments: Where the segments are added.
        place: From the handle's space to the world.
        way: The axis, signed.
        one: A unit direction across it.
        two: The other.
        color: The color.
    """
    var tip = place.transform_point(way * 0.6)
    var rim = List[Vector3]()
    for side in range(CONE_SIDES + 1):  # pragma: no branch
        var theta = Float32(side) / Float32(CONE_SIDES) * 2 * Float32(pi)
        rim.append(
            way * 0.5 + one * (0.04 * cos(theta)) + two * (0.04 * sin(theta))
        )
    segments.add_strip(rim, place, color)
    for side in range(CONE_SIDES):  # pragma: no branch
        segments.add(place.transform_point(rim[side]), tip, color)


def _draw_box(
    mut segments: Segments,
    place: Matrix4,
    center: Vector3,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    color: FloatColor,
):
    """Draw the twelve edges of a box.

    Args:
        segments: Where the segments are added.
        place: From the handle's space to the world.
        center: The box's center.
        a: Half of one of its edges.
        b: Half of another.
        c: Half of the third.
        color: The color.
    """
    var halves: List[Vector3] = [a, b, c]
    var signs: List[Float32] = [1, -1]
    for axis in range(3):  # pragma: no branch
        var edge = halves[axis]
        var p = halves[(axis + 1) % 3]
        var q = halves[(axis + 2) % 3]
        for sp in signs:  # pragma: no branch
            for sq in signs:  # pragma: no branch
                var middle = center + p * sp + q * sq
                segments.add(
                    place.transform_point(middle - edge),
                    place.transform_point(middle + edge),
                    color,
                )


def _draw_octahedron(mut segments: Segments, place: Matrix4, color: FloatColor):
    """Draw the twelve edges of an octahedron of radius 0.1.

    Args:
        segments: Where the segments are added.
        place: From the handle's space to the world.
        color: The color.
    """
    var axes: List[Vector3] = [
        Vector3(0.1, 0, 0),
        Vector3(0, 0.1, 0),
        Vector3(0, 0, 0.1),
    ]
    var signs: List[Float32] = [1, -1]
    for axis in range(3):  # pragma: no branch
        var next = axes[(axis + 1) % 3]
        for sa in signs:  # pragma: no branch
            for sb in signs:  # pragma: no branch
                segments.add(
                    place.transform_point(axes[axis] * sa),
                    place.transform_point(next * sb),
                    color,
                )


def _draw_ring(
    mut segments: Segments,
    handle: TransformAxis,
    place: Matrix4,
    color: FloatColor,
):
    """Draw a ring of `ROTATE_MODE`: half a circle of 0.5 about an axis,
    or a whole circle of 0.75 for `E` and of 0.5 for `XYZE`, in the xy
    plane.

    Args:
        segments: Where the segments are added.
        handle: The handle.
        place: From the handle's space to the world.
        color: The color.
    """
    # three.js's `CircleGeometry(radius, arc)`: from `start` toward `end`.
    var start = Vector3(0, 1, 0)
    var end = Vector3(1, 0, 0)
    var radius = Float32(0.5)
    var arc = Float32(1)
    if handle == HANDLE_X:
        end = Vector3(0, 0, 1)
        arc = 0.5
    elif handle == HANDLE_Y:
        start = Vector3(1, 0, 0)
        end = Vector3(0, 0, 1)
        arc = 0.5
    elif handle == HANDLE_Z:
        arc = 0.5
    elif handle == HANDLE_E:
        radius = 0.75
    var points = List[Vector3]()
    for step in range(CIRCLE_SEGMENTS + 1):  # pragma: no branch
        var theta = (
            Float32(step) / Float32(CIRCLE_SEGMENTS) * arc * 2 * Float32(pi)
        )
        points.append((start * cos(theta) + end * sin(theta)) * radius)
    segments.add_strip(points, place, color)
