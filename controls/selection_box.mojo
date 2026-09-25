# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Select what a rectangle on the screen covers, from three.js
`examples/jsm/interactive/SelectionBox.js`.

`SelectionBox.select` takes two corners of a rectangle in normalized device
coordinates, x and y from minus one to one and a z, and returns what lies
in the frustum the rectangle cuts out of the camera's view. An object is
in it when the center of its geometry's bounding sphere, carried to the
world, is: three.js's test. An instanced mesh is tested instance by
instance, each at its matrix's position.

The frustum is three.js's. Through a perspective camera, four planes run
from the eye through the rectangle's edges, one lies on the rectangle at
its corners' depth, and the far plane lies `deep` along the rays from the
eye. Through an orthographic camera, the four sides run through the
rectangle at the near and far depths, and the two ends lie there.

**The far plane.** three.js's `deep` is `Number.MAX_VALUE` by default, and
the far plane's normal then overflows to NaN, so it leaves nothing out.
Here `deep` is optional: none, the default, has no far plane, which is
what three.js's default does. three.js also turns the far plane round by
its normal alone, `normal.multiplyScalar( -1 )`, keeping its constant.
This does the same, so a `deep` gives three.js's plane.

**Where this port differs.** three.js returns one list of objects in the
order it walks the scene. A scene here keeps a list per kind, so the
selection holds one list per kind, each in the order the scene's nodes
are walked. A batched mesh is left out: three.js tests the center of its
one shared buffer, which this port does not hold. A rectangle with no
width or height is widened by a hair, as three.js widens it by
`Number.EPSILON`; here by a `Float32`'s step at that place, since a double's
step is lost in a `Float32`.

**A drag.** `SelectionBox.handle` takes the pointer events a window gives,
as three.js's example drives it. A press of the primary button starts a
rectangle, and each move and the release select through it. A pixel's
center gives the corner, at a depth of one half, as in three.js's example.
"""

from cameras.camera import Camera, unproject_point
from controls.input import (
    InputEvent,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
)
from core.geometry_store import GeometryId
from core.scene import Scene
from math.bounds import Plane
from math.frustum import Frustum
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from core.assets import Assets
from std.math import inf
from units.si import Length, METER

# A `Float32`'s step at one: the least a coordinate of about one moves by.
comptime _STEP = Float32(1.1920929e-07)
# The depth three.js's example gives a dragged corner.
comptime DRAG_DEPTH = Float32(0.5)


struct Selection(Movable):
    """What a rectangle covers: indices into the scene's lists, each kind in
    the order the scene's nodes are walked. three.js's `collection` and
    `instances`."""

    var meshes: List[Int]
    var skinned_meshes: List[Int]
    var lines: List[Int]
    var points: List[Int]
    # Every instanced mesh walked, and for each the instances inside,
    # three.js's `instances[ uuid ]`.
    var instanced_meshes: List[Int]
    var instances: List[List[Int]]

    def __init__(out self):
        """Start with nothing selected."""
        self.meshes = List[Int]()
        self.skinned_meshes = List[Int]()
        self.lines = List[Int]()
        self.points = List[Int]()
        self.instanced_meshes = List[Int]()
        self.instances = List[List[Int]]()


struct SelectionBox(Copyable, Movable):
    """Selects by a rectangle on the screen, three.js's `SelectionBox`."""

    # How far along the rays from the eye the far plane lies, through a
    # perspective camera. None for no far plane, three.js's default.
    var deep: Optional[Length]
    # The corners of the rectangle being dragged, three.js's `startPoint`
    # and `endPoint`, in normalized device coordinates.
    var start_point: Vector3
    var end_point: Vector3
    # Whether the primary button is down and a rectangle is being dragged.
    var dragging: Bool

    def __init__(out self, deep: Optional[Length] = None):
        """Create a selection box.

        Args:
            deep: How far the far plane lies, or none for none.
        """
        self.deep = deep
        self.start_point = Vector3(0, 0, 0)
        self.end_point = Vector3(0, 0, 0)
        self.dragging = False

    def handle[
        C: Camera
    ](
        mut self,
        event: InputEvent,
        camera: C,
        scene: Scene,
        assets: Assets,
        width: Int,
        height: Int,
    ) raises -> Optional[Selection]:
        """Take one pointer event of a drag, as three.js's example does.

        Args:
            event: The event, with its position in pixels.
            camera: The camera the view is seen through.
            scene: The scene, updated.
            assets: Where the geometries are.
            width: The view's width, in pixels.
            height: The view's height, in pixels.

        Returns:
            What the rectangle covers, after a move or the release of a
            drag. None for any other event.

        Raises:
            Error: If the event's kind or button is invalid, the view has
                no size, or for anything `select` raises for.
        """
        if not event.kind.is_valid():
            raise Error("Invalid input kind: ", event.kind.value)
        if not event.button.is_valid():
            raise Error("Invalid pointer button: ", event.button.value)
        if width <= 0 or height <= 0:
            raise Error("A view must have a positive width and height")
        var corner = Vector3(
            (Float32(event.x) + 0.5) / Float32(width) * 2 - 1,
            1 - (Float32(event.y) + 0.5) / Float32(height) * 2,
            DRAG_DEPTH,
        )
        if event.kind == POINTER_DOWN and event.button == PRIMARY:
            self.start_point = corner
            self.end_point = corner
            self.dragging = True
            return None
        if not self.dragging:
            return None
        if event.kind == POINTER_MOVE:
            self.end_point = corner
        elif event.kind == POINTER_UP:
            self.end_point = corner
            self.dragging = False
        else:
            return None
        return self.select(
            camera, scene, assets, self.start_point, self.end_point
        )

    def frustum[
        C: Camera
    ](
        self, camera: C, scene: Scene, start: Vector3, end: Vector3
    ) raises -> Frustum:
        """Return the frustum a rectangle cuts out of a camera's view,
        three.js's `_updateFrustum`.

        Args:
            camera: The camera.
            scene: The scene, updated, whose node the camera can ride.
            start: One corner, in normalized device coordinates.
            end: The other corner.

        Returns:
            The six planes, facing in.

        Raises:
            Error: If the camera's volume is degenerate, it rides a node the
                scene does not have, or the scene is stale.
        """
        var first = start
        var last = end
        if first.x == last.x:
            last.x += _STEP * max(abs(last.x), Float32(1))
        if first.y == last.y:
            last.y += _STEP * max(abs(last.y), Float32(1))
        if not camera.projection_matrix().is_affine():
            return self._perspective(camera, scene, first, last)
        var left = min(first.x, last.x)
        var top = max(first.y, last.y)
        var right = max(first.x, last.x)
        var down = min(first.y, last.y)
        var top_left = unproject_point(Vector3(left, top, -1), camera, scene)
        var top_right = unproject_point(Vector3(right, top, -1), camera, scene)
        var down_right = unproject_point(
            Vector3(right, down, -1), camera, scene
        )
        var down_left = unproject_point(Vector3(left, down, -1), camera, scene)
        var far_top_left = unproject_point(Vector3(left, top, 1), camera, scene)
        var far_top_right = unproject_point(
            Vector3(right, top, 1), camera, scene
        )
        var far_down_right = unproject_point(
            Vector3(right, down, 1), camera, scene
        )
        var far_down_left = unproject_point(
            Vector3(left, down, 1), camera, scene
        )
        var back = Plane.from_coplanar_points(
            far_down_right, far_top_right, far_top_left
        )
        var planes: Array[Plane, 6] = [
            Plane.from_coplanar_points(top_left, far_top_left, far_top_right),
            Plane.from_coplanar_points(
                top_right, far_top_right, far_down_right
            ),
            Plane.from_coplanar_points(
                far_down_right, far_down_left, down_left
            ),
            Plane.from_coplanar_points(far_down_left, far_top_left, top_left),
            Plane.from_coplanar_points(top_right, down_right, down_left),
            _turned(back),
        ]
        return Frustum(planes^)

    def _perspective[
        C: Camera
    ](
        self, camera: C, scene: Scene, start: Vector3, end: Vector3
    ) raises -> Frustum:
        """Return the frustum through a perspective camera."""
        # three.js's corners: the top left takes the start's depth and the
        # bottom right the end's, and the other two lie at zero.
        var top_left = Vector3(
            min(start.x, end.x), max(start.y, end.y), start.z
        )
        var down_right = Vector3(
            max(start.x, end.x), min(start.y, end.y), end.z
        )
        var top_right = Vector3(down_right.x, top_left.y, 0)
        var down_left = Vector3(top_left.x, down_right.y, 0)
        var view = camera.view_matrix_in(scene)
        view.invert()
        var near = view.transform_point(Vector3(0, 0, 0))
        top_left = unproject_point(top_left, camera, scene)
        top_right = unproject_point(top_right, camera, scene)
        down_right = unproject_point(down_right, camera, scene)
        down_left = unproject_point(down_left, camera, scene)
        var far: Plane
        if Bool(self.deep):
            var reach = self.deep.value().to(METER)
            var ray1 = top_left - near
            var ray2 = top_right - near
            var ray3 = down_right - near
            ray1.normalize()
            ray2.normalize()
            ray3.normalize()
            far = _turned(
                Plane.from_coplanar_points(
                    ray3 * reach + near,
                    ray2 * reach + near,
                    ray1 * reach + near,
                )
            )
        else:
            # No far plane: one nothing lies behind.
            far = Plane(Vector3(0, 0, 1), inf[DType.float32]())
        var planes: Array[Plane, 6] = [
            Plane.from_coplanar_points(near, top_left, top_right),
            Plane.from_coplanar_points(near, top_right, down_right),
            Plane.from_coplanar_points(down_right, down_left, near),
            Plane.from_coplanar_points(down_left, top_left, near),
            Plane.from_coplanar_points(top_right, down_right, down_left),
            far,
        ]
        return Frustum(planes^)

    def select[
        C: Camera
    ](
        self,
        camera: C,
        scene: Scene,
        assets: Assets,
        start: Vector3,
        end: Vector3,
    ) raises -> Selection:
        """Return what a rectangle covers, three.js's `select`.

        Args:
            camera: The camera the rectangle is drawn on.
            scene: The scene, updated.
            assets: Where the geometries are.
            start: One corner, in normalized device coordinates. three.js's
                examples give a z of one half.
            end: The other corner.

        Returns:
            What is covered, kind by kind.

        Raises:
            Error: For anything `frustum` raises for, or if an object names
                a node or a geometry that is not there.
        """
        var frustum = self.frustum(camera, scene, start, end)
        var picked = Selection()
        var order = scene.traverse()
        for at in range(len(order)):
            var node = order[at]
            var world = scene.world_matrix(node)
            for index in range(len(scene.meshes)):
                ref mesh = scene.meshes[index]
                if mesh.node == node and _centered(
                    frustum, assets, mesh.geometry, world
                ):
                    picked.meshes.append(index)
            for index in range(len(scene.skinned_meshes)):
                ref skinned = scene.skinned_meshes[index]
                if skinned.node == node and _centered(
                    frustum, assets, skinned.geometry, world
                ):
                    picked.skinned_meshes.append(index)
            for index in range(len(scene.lines)):
                ref line = scene.lines[index]
                if line.node == node and _centered(
                    frustum, assets, line.geometry, world
                ):
                    picked.lines.append(index)
            for index in range(len(scene.points)):
                ref dots = scene.points[index]
                if dots.node == node and _centered(
                    frustum, assets, dots.geometry, world
                ):
                    picked.points.append(index)
            for index in range(len(scene.instanced_meshes)):
                ref group = scene.instanced_meshes[index]
                if group.node != node:
                    continue
                var inside = List[Int]()
                for instance in range(group.count()):
                    var placed = group.matrix_at(instance)
                    var center = Vector3(
                        placed.elements[12],
                        placed.elements[13],
                        placed.elements[14],
                    )
                    if frustum.contains_point(world.transform_point(center)):
                        inside.append(instance)
                picked.instanced_meshes.append(index)
                picked.instances.append(inside^)
        return picked^


def _turned(plane: Plane) raises -> Plane:
    """Return a plane with its normal turned round and its constant kept,
    three.js's `plane.normal.multiplyScalar( -1 )`."""
    return Plane(plane.normal * -1, plane.constant)


def _centered(
    frustum: Frustum, assets: Assets, geometry: GeometryId, world: Matrix4
) raises -> Bool:
    """Return whether a geometry's bounding sphere center, carried by a
    node's world matrix, lies in a frustum."""
    var center = assets.geometries.get(geometry).bounding_sphere().center
    return frustum.contains_point(world.transform_point(center))
