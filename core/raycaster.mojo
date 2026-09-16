# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Picking, from three.js `src/core/Raycaster.js` and `Mesh.raycast`.

A raycaster carries a `Ray` through a scene and reports every mesh it
meets, nearest first: which thing a click landed on, and where. It is the
question a renderer answers backwards. The renderer takes every triangle
to the screen and asks which pixels it covers; the raycaster takes one
pixel back into the world and asks which triangles it passes through.

**Set it from a camera.** `set_from_camera` takes a point on the image in
normalized device coordinates, -1 to 1 each way with y up, as three.js's
does, and `set_from_pixel` takes a pixel of an image of a given size, y
counted down from the top as `Framebuffer` counts it. A perspective
camera's ray leaves the camera's own position toward the point, so that
distances are measured from the eye; an orthographic camera's leaves the
point's place on the camera's own plane down the view direction, so that
every ray is parallel. Both are three.js's. Which the camera is, is read
off its projection matrix: one that keeps `w` at one does not diverge.

**How a mesh is tested.** The geometry's bounding sphere, carried to
world space, is tested first, and a mesh the ray misses wholly costs
nothing more. The ray is then carried into the mesh's own space by the
inverse of its world matrix, tested against the local bounding box, and
then against every triangle, honoring the material's side: what the
renderer would draw, the raycaster hits, and a `FRONT_SIDE` mesh is not
picked through its back. A mirrored mesh needs no special case here,
where the renderer needed one: the inverse of a reflection reflects the
ray, and the triangles are met as they were wound. A hit's point and
distance are in world space, and a hit nearer than `near` or further than
`far` is dropped. three.js's `Mesh.raycast`, step for step.

**Layers.** A raycaster has layers as a camera has, three.js's
`Raycaster.layers`, and a mesh whose node shares none is not tested.
Layer zero alone by default, as everywhere.

The two distances are `Length`s: this is the edge of the API, where the
units live, and a bare number here does not compile. The ray inside holds
meters, as the math does.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.layers import Layers
from core.scene import Scene
from math.matrix4 import Matrix4
from math.ray import Ray
from math.vector2 import Vector2
from math.vector3 import Vector3
from materials.material import BACK_SIDE, FRONT_SIDE
from objects.mesh import Mesh
from std.math import inf
from units.si import Length, METER


@fieldwise_init
struct Hit(ImplicitlyCopyable):
    """One place a ray meets a mesh, three.js's intersection record."""

    # How far along the ray, from its origin, in meters. What the hits are
    # sorted by.
    var distance: Float32
    # Where, in world space.
    var point: Vector3
    # The face's front, in world space and unit length: the normal of the
    # triangle as wound, whichever side the ray came from. A mirrored
    # mesh's is turned back, as the renderer turns its geometric normal.
    var normal: Vector3
    # Which mesh, as its position in `scene.meshes`, and the mesh itself:
    # its node, its geometry and its material.
    var index: Int
    var mesh: Mesh
    # Which of the geometry's triangles, from zero.
    var triangle: Int


struct Raycaster(ImplicitlyCopyable):
    """A ray with a range, that asks a scene what it meets."""

    var ray: Ray
    # Hits nearer than `near` or further than `far` are dropped.
    var near: Length
    var far: Length
    # Which layers this raycaster tests. A mesh on none of them is skipped.
    var layers: Layers

    def __init__(
        out self,
        origin: Vector3,
        direction: Vector3,
        near: Length = Length(0.0, METER),
        far: Length = Length(inf[DType.float32](), METER),
    ) raises:
        """Create a raycaster from an origin and a direction, on layer zero.

        Args:
            origin: Where the ray starts, in world space.
            direction: Which way it goes; any length but zero.
            near: How far from the origin hits start to count. Zero by
                default, so they count from the origin.
            far: How far they stop counting. Unbounded by default.

        Raises:
            Error: If the direction has no length, `near` is negative, or
                `far` is below `near`.
        """
        if near.value < 0:
            raise Error("A raycaster's near distance cannot be negative")
        if far.value < near.value:
            raise Error("A raycaster's far distance cannot be below its near")
        self.ray = Ray(origin, direction)
        self.near = near
        self.far = far
        self.layers = Layers()

    def set(mut self, origin: Vector3, direction: Vector3) raises:
        """Point this raycaster somewhere else, three.js's `set`.

        Args:
            origin: Where the ray starts, in world space.
            direction: Which way it goes; any length but zero.

        Raises:
            Error: If the direction has no length.
        """
        self.ray = Ray(origin, direction)

    def set_from_camera[
        C: Camera
    ](mut self, coords: Vector2, camera: C, scene: Scene) raises:
        """Aim this raycaster through a point of a camera's image,
        three.js's `setFromCamera`.

        Args:
            coords: The point in normalized device coordinates: -1 to 1
                each way, with x to the right and y up, as three.js takes
                a mouse position.
            camera: The camera, perspective or orthographic, placed or
                riding a node of `scene`.
            scene: The scene the camera looks at, updated.

        Raises:
            Error: If the camera's view cannot be read; see
                `Camera.view_matrix_in`.
        """
        var view = camera.view_matrix_in(scene)
        var projection = camera.projection_matrix()
        # NDC back to the world: the inverse of what the renderer applies.
        var unproject = Matrix4(copy=projection)
        unproject.multiply(view)
        unproject.invert()
        # The camera's own place and facing, in the world.
        var world = Matrix4(copy=view)
        world.invert()
        if projection.is_affine():
            # Orthographic. The origin sits on the camera's own plane, the
            # NDC depth that camera-space zero projects to, and every ray
            # goes the way the camera looks.
            var near = camera.near_distance()
            var far = camera.far_distance()
            var origin = unproject.transform_point(
                Vector3(coords.x, coords.y, (near + far) / (near - far))
            )
            self.ray = Ray(origin, world.transform_direction(Vector3(0, 0, -1)))
            return
        # Perspective. From the eye, toward where the point is in the
        # world at any depth in front of it.
        var eye = world.transform_point(Vector3(0, 0, 0))
        var toward = unproject.transform_point(Vector3(coords.x, coords.y, 0.5))
        self.ray = Ray(eye, toward - eye)

    def set_from_pixel[
        C: Camera
    ](
        mut self,
        x: Float32,
        y: Float32,
        width: Int,
        height: Int,
        camera: C,
        scene: Scene,
    ) raises:
        """Aim this raycaster through a pixel of an image the camera would
        render at `width` by `height`.

        The undoing of `PerspectiveCamera.project`: x runs from zero at the
        left edge, y from zero at the top, and the center of pixel (i, j)
        is at (i + 0.5, j + 0.5).

        Args:
            x: How far across the image, in pixels.
            y: How far down it, in pixels.
            width: The image's width in pixels.
            height: Its height in pixels.
            camera: The camera the image is seen through.
            scene: The scene the camera looks at, updated.

        Raises:
            Error: If either dimension is not positive, or the camera's
                view cannot be read.
        """
        if width <= 0 or height <= 0:
            raise Error("An image has a positive width and height")
        self.set_from_camera(
            Vector2(
                x / Float32(width) * 2 - 1,
                1 - y / Float32(height) * 2,
            ),
            camera,
            scene,
        )

    def intersect_mesh(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every place this ray meets one mesh, nearest first,
        three.js's `intersectObject` without the recursion.

        Args:
            scene: The scene the mesh is in, updated.
            assets: The geometry and materials the mesh names.
            index: Which mesh, as its position in `scene.meshes`.

        Returns:
            The hits, nearest first. None for a mesh on a layer this
            raycaster does not test, or whose bounds the ray misses.

        Raises:
            Error: If no mesh has that index, the mesh names a node, a
                geometry or a material that is not there, its geometry has
                no positions, the scene is stale, or its world transform
                flattens a dimension, which leaves no inverse to carry the
                ray through.
        """
        var hits = List[Hit]()
        if index < 0 or index >= len(scene.meshes):
            raise Error("No mesh has that index")
        var mesh = scene.meshes[index]
        if not scene.get(mesh.node).layers.test(self.layers):
            return hits^
        ref geometry = assets.geometries.get(mesh.geometry)
        var material = assets.materials.get(mesh.material)
        var world = scene.world_matrix(mesh.node)
        # The whole mesh first, in world space: a miss here is the common
        # case and costs six multiplies. An empty sphere, of a geometry
        # with no vertices, is met nowhere.
        var bound = geometry.bounding_sphere()
        bound.apply_matrix4(world)
        if not self.ray.intersects_sphere(bound):
            return hits^
        # Then into the mesh's own space, where its triangles are.
        var into = Matrix4(copy=world)
        into.invert()
        var local = self.ray
        local.apply_matrix4(into)
        if not local.intersects_box(geometry.bounding_box()):
            return hits^
        var mirrored = world.determinant() < 0
        var near = self.near.value
        var far = self.far.value
        for triangle in range(geometry.triangle_count()):
            var a = geometry.corner(triangle, 0)
            var b = geometry.corner(triangle, 1)
            var c = geometry.corner(triangle, 2)
            var met: Optional[Vector3]
            if material.side == BACK_SIDE:
                # Wound the other way, so the back is the side that counts.
                met = local.intersect_triangle(c, b, a, True)
            else:
                met = local.intersect_triangle(
                    a, b, c, material.side == FRONT_SIDE
                )
            if not Bool(met):
                continue
            var point = world.transform_point(met.value())
            var distance = (point - self.ray.origin).length()
            if distance < near or distance > far:
                continue
            # The face's front in the world, from its world corners, as the
            # renderer finds a geometric normal; turned back for a mirrored
            # mesh, whose winding the reflection reversed.
            var first = world.transform_point(a)
            var normal = world.transform_point(b) - first
            normal.cross(world.transform_point(c) - first)
            normal.normalize()
            if mirrored:
                normal = -normal
            hits.append(Hit(distance, point, normal, index, mesh, triangle))
        _sort_by_distance(hits)
        return hits^

    def intersect_scene(self, scene: Scene, assets: Assets) raises -> List[Hit]:
        """Return every place this ray meets any mesh of the scene, nearest
        first, three.js's `intersectObjects`.

        Args:
            scene: The scene, updated.
            assets: The geometry and materials its meshes name.

        Returns:
            The hits, nearest first, across every mesh on a layer this
            raycaster tests.

        Raises:
            Error: For anything `intersect_mesh` raises for.
        """
        var hits = List[Hit]()
        for index in range(len(scene.meshes)):
            var found = self.intersect_mesh(scene, assets, index)
            for position in range(len(found)):
                hits.append(found[position])
        _sort_by_distance(hits)
        return hits^


def _sort_by_distance(mut hits: List[Hit]):
    """Sort `hits` by distance, ascending, in place and stably.

    Insertion sort, as the renderer's draw order uses: a pick meets a
    handful of triangles, and a stable order keeps two hits at one distance
    in the order they were found.
    """
    for position in range(len(hits)):
        var hit = hits[position]
        var slot = position
        while slot > 0 and hits[slot - 1].distance > hit.distance:
            hits[slot] = hits[slot - 1]
            slot -= 1
        hits[slot] = hit
