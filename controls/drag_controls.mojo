# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Objects picked up and moved by the pointer, from three.js
`examples/jsm/controls/DragControls.js`.

A press over one of `objects` picks it with a `Raycaster`, and later moves
drag it. A translating drag keeps the object on the plane through its
origin that faces the camera, at the offset the press found: the point
under the pointer stays under it. A rotating drag turns the object about
the camera's up and right, by the pointer's movement in normalized device
coordinates times `rotate_speed`, as three.js turns it. The left and middle
buttons translate and the right button rotates, three.js's
`mouseButtons`.

A browser dispatches `hoveron`, `hoveroff`, `dragstart`, `drag` and
`dragend`. Here `handle` returns them as `DragEvent` records, in the order
three.js dispatches them.

An object is a node of the scene. A hit on a mesh, an instanced mesh or a
batched mesh counts when its node is one of `objects`, or, with
`recursive` set, when one of its ancestors is: three.js's
`intersectObjects(objects, recursive)`. An LOD's level is a node under
the LOD's node, so a hit on it counts as a hit on a mesh does. The
object moved is the node struck. With `transform_group` set it is the outermost of `objects` above
the node struck. three.js moves the outermost `Group` instead; there is no
`Group` here.

The press and the moves read the pointer at the center of its pixel. The
scene is brought up to date at each event, as a render between two events
brings it up to date in three.js.

Differences from three.js: touch input and the cursor style are not
ported.
"""

from cameras.camera import Camera
from controls.input import (
    InputEvent,
    MIDDLE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    SECONDARY,
)
from core.assets import Assets
from core.object3d import NO_PARENT, NodeId
from core.raycaster import Raycaster
from core.scene import Scene
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from units.si import Angle, RADIAN


@fieldwise_init
struct DragAction(Equatable, ImplicitlyCopyable, Writable):
    """What a drag with a pointer button does to the object, as a type
    rather than a bare int. three.js: `MOUSE.PAN` and `MOUSE.ROTATE` in
    `mouseButtons`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two actions, or none.

        Returns:
            Whether the value names an action.
        """
        return self.value >= 0 and self.value <= 2


# The button picks an object and moves it nowhere. three.js: `STATE.NONE`.
comptime NO_DRAG = DragAction(0)
# The object moves on the plane that faces the camera. three.js:
# `MOUSE.PAN`.
comptime DRAG_TRANSLATE = DragAction(1)
# The object turns about the camera's up and right. three.js:
# `MOUSE.ROTATE`.
comptime DRAG_ROTATE = DragAction(2)


@fieldwise_init
struct DragEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What a drag event reports, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five kinds.

        Returns:
            Whether the value names a kind.
        """
        return self.value >= 0 and self.value <= 4


# The pointer came over an object. three.js: `hoveron`.
comptime HOVER_ON = DragEventKind(0)
# The pointer left an object. three.js: `hoveroff`.
comptime HOVER_OFF = DragEventKind(1)
# A press picked an object up. three.js: `dragstart`.
comptime DRAG_START = DragEventKind(2)
# A move dragged the object. three.js: `drag`.
comptime DRAG_MOVE = DragEventKind(3)
# A release let the object go. three.js: `dragend`.
comptime DRAG_END = DragEventKind(4)


@fieldwise_init
struct DragEvent(ImplicitlyCopyable):
    """One thing that happened to one object, three.js's event with its
    `type` and `object`."""

    var kind: DragEventKind
    # The node the event is about.
    var node: NodeId


struct DragControls(Copyable, Movable):
    """Turns pointer input into objects picked up, moved and turned."""

    # The nodes that can be dragged. three.js: `objects`.
    var objects: List[NodeId]
    # False to ignore all input.
    var enabled: Bool
    # True to pick a node below one of `objects` too.
    var recursive: Bool
    # True to move the outermost of `objects` above the node struck.
    var transform_group: Bool
    # Radians a drag across the whole view turns, over two. three.js:
    # `rotateSpeed`, a factor on the pointer's movement in normalized device
    # coordinates.
    var rotate_speed: Float32
    # What picks the objects. Its layers say which nodes can be picked.
    var raycaster: Raycaster
    # What each button does. three.js: `mouseButtons`.
    var primary_action: DragAction
    var middle_action: DragAction
    var secondary_action: DragAction

    # The action of the button that picked the object up.
    var _action: DragAction
    # The object picked up, and the object under the pointer.
    var _selected: Optional[NodeId]
    var _hovered: Optional[NodeId]
    # The plane a translating drag keeps the object on, and the offset from
    # the object's origin to the point the press found on it.
    var _plane: Plane
    var _offset: Vector3
    # From the world to the frame of the object's parent.
    var _inverse: Matrix4
    # The camera's up and right, which a rotating drag turns about.
    var _up: Vector3
    var _right: Vector3
    # Where the pointer was, in normalized device coordinates.
    var _previous: Vector2

    def __init__(out self, var objects: List[NodeId]) raises:
        """Create controls over `objects`, with three.js's defaults.

        Args:
            objects: The nodes that can be dragged.

        Raises:
            Error: Never; the raycaster's default range is valid.
        """
        self.objects = objects^
        self.enabled = True
        self.recursive = True
        self.transform_group = False
        self.rotate_speed = 1.0
        self.raycaster = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1))
        self.primary_action = DRAG_TRANSLATE
        self.middle_action = DRAG_TRANSLATE
        self.secondary_action = DRAG_ROTATE
        self._action = NO_DRAG
        self._selected = None
        self._hovered = None
        self._plane = Plane(Vector3(0, 0, 1), 0)
        self._offset = Vector3(0, 0, 0)
        self._inverse = Matrix4()
        self._up = Vector3(0, 1, 0)
        self._right = Vector3(1, 0, 0)
        self._previous = Vector2(0, 0)

    def selected(self) -> Optional[NodeId]:
        """Return the object picked up, if a drag is on.

        Returns:
            The node, or None.
        """
        return self._selected

    def hovered(self) -> Optional[NodeId]:
        """Return the object under the pointer, if any.

        Returns:
            The node, or None.
        """
        return self._hovered

    def action_of(self, button: PointerButton) raises -> DragAction:
        """Return what a drag with a button does. three.js:
        `_updateState`.

        Args:
            button: The button pressed.

        Returns:
            Its action, or `NO_DRAG` for no button.

        Raises:
            Error: If the button, or the action it maps to, is invalid.
        """
        if not button.is_valid():
            raise Error("Invalid pointer button: ", button.value)
        var action = NO_DRAG
        if button == PRIMARY:
            action = self.primary_action
        elif button == MIDDLE:
            action = self.middle_action
        elif button == SECONDARY:
            action = self.secondary_action
        if not action.is_valid():
            raise Error("Invalid drag action: ", action.value)
        return action

    def handle[
        C: Camera
    ](
        mut self,
        event: InputEvent,
        camera: C,
        mut scene: Scene,
        assets: Assets,
        width: Int,
        height: Int,
    ) raises -> List[DragEvent]:
        """Take one event: a press picks an object up, a move drags it or
        hovers, and a release lets it go.

        Args:
            event: The event, with its position in pixels.
            camera: The camera the view is seen through.
            scene: The scene. It is updated first, and a drag moves or
                turns one of its nodes.
            assets: The geometry and materials its objects name.
            width: The view's width, in pixels.
            height: The view's height, in pixels.

        Returns:
            What happened, in three.js's order.

        Raises:
            Error: If the event's kind, button or key is invalid, a button's
                action is invalid, the view has no size, one of `objects`
                is not in the scene, or the camera or the scene cannot be
                read.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.key.is_valid():
            raise Error("Invalid key: ", event.key.value)
        var action = self.action_of(event.button)
        var events = List[DragEvent]()
        if not self.enabled:
            return events^
        if width <= 0 or height <= 0:
            raise Error("A view must have a positive width and height")
        scene.update()
        for node in self.objects:
            _ = scene.get(node)
        var pointer = Vector2(
            (Float32(event.x) + 0.5) / Float32(width) * 2 - 1,
            1 - (Float32(event.y) + 0.5) / Float32(height) * 2,
        )
        self.raycaster.set_from_camera(pointer, camera, scene)
        if event.kind == POINTER_DOWN:
            self._action = action
            self._press(camera, scene, assets, events)
            self._previous = pointer
        elif event.kind == POINTER_MOVE:
            self._move(pointer, camera, scene, assets, events)
            self._previous = pointer
        elif event.kind == POINTER_UP:
            self._release(events)
        return events^

    def _press[
        C: Camera
    ](
        mut self,
        camera: C,
        mut scene: Scene,
        assets: Assets,
        mut events: List[DragEvent],
    ) raises:
        """Pick up the object under the pointer. three.js:
        `onPointerDown`.

        Args:
            camera: The camera.
            scene: The scene, updated.
            assets: Its geometry and materials.
            events: Where `DRAG_START` is appended.

        Raises:
            Error: If the camera or the scene cannot be read.
        """
        var struck = self._first_hit(scene, assets)
        if not Bool(struck):
            return
        var node = struck.value()
        if self.transform_group:
            node = self._outermost(scene, node)
        self._selected = node
        var origin = scene.world_position(node)
        self._plane = Plane.from_normal_and_point(
            _camera_axis(camera, scene, Vector3(0, 0, -1)), origin
        )
        var met = self.raycaster.ray.intersect_plane(self._plane)
        if not Bool(met):
            return
        if self._action == DRAG_TRANSLATE:
            var parent = scene.get(node).parent
            self._inverse = Matrix4()
            if parent != NO_PARENT:
                self._inverse = scene.world_matrix(parent)
                self._inverse.invert()
            self._offset = met.value() - origin
            events.append(DragEvent(DRAG_START, node))
        elif self._action == DRAG_ROTATE:
            # three.js turns about the camera's own up and right, and says
            # its controls support only +y up.
            self._up = _camera_axis(camera, scene, Vector3(0, 1, 0))
            self._right = _camera_axis(camera, scene, Vector3(1, 0, 0))
            events.append(DragEvent(DRAG_START, node))

    def _move[
        C: Camera
    ](
        mut self,
        pointer: Vector2,
        camera: C,
        mut scene: Scene,
        assets: Assets,
        mut events: List[DragEvent],
    ) raises:
        """Drag the object picked up, or find the object under the pointer.
        three.js: `onPointerMove`.

        Args:
            pointer: Where the pointer is, in normalized device
                coordinates.
            camera: The camera.
            scene: The scene, updated.
            assets: Its geometry and materials.
            events: Where the events are appended.

        Raises:
            Error: If the camera or the scene cannot be read.
        """
        if Bool(self._selected):
            var node = self._selected.value()
            if self._action == DRAG_TRANSLATE:
                var met = self.raycaster.ray.intersect_plane(self._plane)
                if Bool(met):
                    scene.node(node).position = self._inverse.transform_point(
                        met.value() - self._offset
                    )
                    events.append(DragEvent(DRAG_MOVE, node))
            elif self._action == DRAG_ROTATE:
                var diff = (pointer - self._previous) * self.rotate_speed
                ref moved = scene.node(node)
                moved.rotate_on_world_axis(self._up, Angle(diff.x, RADIAN))
                moved.rotate_on_world_axis(self._right, Angle(-diff.y, RADIAN))
                events.append(DragEvent(DRAG_MOVE, node))
            return
        var struck = self._first_hit(scene, assets)
        if Bool(struck):
            var node = struck.value()
            self._plane = Plane.from_normal_and_point(
                _camera_axis(camera, scene, Vector3(0, 0, -1)),
                scene.world_position(node),
            )
            var other = Bool(self._hovered) and self._hovered.value() != node
            if other:
                events.append(DragEvent(HOVER_OFF, self._hovered.value()))
                self._hovered = None
            if not Bool(self._hovered):
                events.append(DragEvent(HOVER_ON, node))
                self._hovered = node
        elif Bool(self._hovered):
            events.append(DragEvent(HOVER_OFF, self._hovered.value()))
            self._hovered = None

    def _release(mut self, mut events: List[DragEvent]):
        """Let the object go. three.js: `onPointerCancel`.

        Args:
            events: Where `DRAG_END` is appended.
        """
        if Bool(self._selected):
            events.append(DragEvent(DRAG_END, self._selected.value()))
            self._selected = None
        self._action = NO_DRAG

    def _first_hit(
        self, scene: Scene, assets: Assets
    ) raises -> Optional[NodeId]:
        """Return the node of the nearest hit on one of `objects`.

        Args:
            scene: The scene, updated.
            assets: Its geometry and materials.

        Returns:
            The node struck, or None.

        Raises:
            Error: If the scene cannot be read.
        """
        for hit in self.raycaster.intersect_scene(scene, assets):
            if self._counts(scene, hit.mesh.node):
                return hit.mesh.node
        return None

    def _counts(self, scene: Scene, node: NodeId) raises -> Bool:
        """Return True if a hit on `node` picks something.

        Args:
            scene: The scene.
            node: The node struck.

        Returns:
            Whether `node` is one of `objects`, or below one when
            `recursive` is set.

        Raises:
            Error: If a parent is not in the scene.
        """
        var current = node
        while current != NO_PARENT:
            if self._listed(current):
                return True
            if not self.recursive:
                return False
            current = scene.get(current).parent
        return False

    def _outermost(self, scene: Scene, node: NodeId) raises -> NodeId:
        """Return the outermost of `objects` at or above `node`.

        Args:
            scene: The scene.
            node: The node struck.

        Returns:
            That node, or `node` when none above it is listed.

        Raises:
            Error: If a parent is not in the scene.
        """
        var chosen = node
        var current = scene.get(node).parent
        while current != NO_PARENT:
            if self._listed(current):
                chosen = current
            current = scene.get(current).parent
        return chosen

    def _listed(self, node: NodeId) -> Bool:
        """Return True if `node` is one of `objects`.

        Args:
            node: The node.

        Returns:
            Whether it is listed.
        """
        for listed in self.objects:
            if listed == node:
                return True
        return False


def _camera_axis[
    C: Camera
](camera: C, scene: Scene, local: Vector3) raises -> Vector3:
    """Return one of a camera's own directions in the world.

    Args:
        camera: The camera.
        scene: The scene it may ride a node of, updated.
        local: The direction in the camera's own axes.

    Returns:
        The direction in the world, unit length.

    Raises:
        Error: If the camera's view cannot be read.
    """
    var world = camera.view_matrix_in(scene)
    world.invert()
    var direction = world.transform_direction(local)
    direction.normalize()
    return direction
