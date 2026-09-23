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

## What it sees

The mesh as it is drawn, not as it was modelled. A mesh wearing a morph
target is picked where the target has carried it, because both this and
`Renderer.prepare` ask `core.deform` the same question. They did not always:
rendering wore the targets and picking did not, so the drawn shape could
not be hit and the modelled one could be hit where nothing was.

**Groups and levels.** An instanced mesh is picked instance by instance,
each at the node's transform times its own, and the hit says which in
`instance`, three.js's `instanceId`; a batched mesh the same, with each
instance's own geometry, three.js's `batchId`. An LOD is picked on the
level its distance from the ray's origin picks with no memory, three.js's
`LOD.raycast` through `getObjectForDistance`, and `instance` says which
level. A hit's `kind` says which of the scene's lists `index` counts in,
and `mesh` is the shape struck as a `Mesh`: its node, geometry and
material, whatever list it came from.

**Rigs.** A skinned mesh is picked where its bones have carried it, as
the renderer draws it: `core.deform.skin_pose` reads the posed bones and
`skin_carriers` moves each vertex, in both. three.js's
`SkinnedMesh.raycast` does the same.

**Lines, points and sprites.** A line is met where the ray passes within
`line_threshold` of one of its segments, three.js's `params.Line.threshold`,
and points where it passes within `points_threshold` of a point,
`params.Points.threshold`. Both are a meter by default, as in three.js, so
set them to what a pointer should reach. The gap is measured in world
space, where three.js divides the threshold by the object's average scale;
the two agree under an even scale, and this one is exact under an uneven
one. A sprite is met on its two triangles, laid flat to the camera as the
renderer lays them, so a sprite needs the camera that `set_from_camera`
records. None of the three has a face, so a hit's `normal` is zero, as
three.js gives no `face`. `triangle` says which segment, point or half of
the sprite was struck.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.deform import (
    morphed_positions,
    skin_carriers,
    skin_pose,
    sphere_of,
)
from core.layers import Layers
from core.scene import Scene
from math.bounds import Sphere
from math.matrix4 import Matrix4
from math.ray import Ray
from math.vector2 import Vector2
from math.vector3 import Vector3
from core.geometry_store import GeometryId
from materials.material import BACK_SIDE, FRONT_SIDE
from objects.line import segment_count, segment_ends
from objects.mesh import Mesh
from std.math import cos, inf, isnan, sin
from units.si import Length, METER, RADIAN


@fieldwise_init
struct HitKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of the scene's lists a hit's `index` counts in, as a type
    rather than a bare int.

    The same argument as `objects.line.LineMode`: eight small integers
    that mean eight different lists must not be interchangeable, and the
    type stops a bare integer at compile time. `is_valid` stops
    `HitKind(9)`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eight named kinds."""
        return self.value >= MESH_HIT.value and self.value <= SPRITE_HIT.value


# `index` counts in `scene.meshes`, and `instance` is -1.
comptime MESH_HIT = HitKind(0)
# `index` counts in `scene.instanced_meshes`, and `instance` is which
# instance: three.js's `instanceId`.
comptime INSTANCED_HIT = HitKind(1)
# `index` counts in `scene.batched_meshes`, and `instance` is which
# instance: three.js's `batchId`.
comptime BATCHED_HIT = HitKind(2)
# `index` counts in `scene.lods`, and `instance` is which level was struck.
comptime LOD_HIT = HitKind(3)
# `index` counts in `scene.skinned_meshes`, and `instance` is -1.
comptime SKINNED_HIT = HitKind(4)
# `index` counts in `scene.lines`, `instance` is -1, and `triangle` is
# which segment.
comptime LINE_HIT = HitKind(5)
# `index` counts in `scene.points`, `instance` is -1, and `triangle` is
# which point: three.js's `index`.
comptime POINTS_HIT = HitKind(6)
# `index` counts in `scene.sprites`, `instance` is -1, and `triangle` is
# which of the two halves.
comptime SPRITE_HIT = HitKind(7)


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
    # Zero for a line, points or a sprite, which have no face.
    var normal: Vector3
    # Which of the scene's lists `index` counts in, and what `instance`
    # means there.
    var kind: HitKind
    var index: Int
    # Which instance of an instanced or batched mesh, or which level of an
    # LOD, was struck; -1 for a plain mesh.
    var instance: Int
    # The shape struck as a mesh: its node, its geometry and its material.
    # For a plain mesh, the mesh itself. A sprite names no geometry: its
    # `geometry` is -1.
    var mesh: Mesh
    # Which of the geometry's triangles, from zero; for a line, points or
    # a sprite, which segment, point or half.
    var triangle: Int


def _worn_corner(
    geometry: BufferGeometry,
    worn: List[Vector3],
    triangle: Int,
    corner: Int,
) raises -> Vector3:
    """Return one corner of one triangle, worn targets included.

    `worn` is empty for a mesh wearing nothing, and then this is
    `BufferGeometry.corner` exactly. It exists so the triangle loop reads
    the same whichever the mesh is.

    Args:
        geometry: The geometry being picked.
        worn: Every vertex once its targets are worn, or empty.
        triangle: Which triangle.
        corner: Which of its three corners.

    Returns:
        The corner, in the geometry's own space.

    Raises:
        Error: If either index is out of range.
    """
    if len(worn) == 0:
        return geometry.corner(triangle, corner)
    return worn[geometry.corner_index(triangle, corner)]


struct Raycaster(ImplicitlyCopyable):
    """A ray with a range, that asks a scene what it meets."""

    var ray: Ray
    # Hits nearer than `near` or further than `far` are dropped.
    var near: Length
    var far: Length
    # Which layers this raycaster tests. A mesh on none of them is skipped.
    var layers: Layers
    # How near a line or a point the ray must pass to meet it, three.js's
    # `params.Line.threshold` and `params.Points.threshold`.
    var line_threshold: Length
    var points_threshold: Length
    # The camera `set_from_camera` last aimed through, three.js's
    # `Raycaster.camera`: its world matrix and whether its rays converge.
    # A sprite faces it, so a sprite is picked only once one is set.
    var has_camera: Bool
    var camera_world: Matrix4
    var camera_perspective: Bool

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
                `far` is below `near`, or either is not a number: a NaN
                passes both of the other tests and then stops the range
                filtering anything, silently.
        """
        if isnan(near.value) or isnan(far.value):
            raise Error("A raycaster's range must be made of numbers")
        if near.value < 0:
            raise Error("A raycaster's near distance cannot be negative")
        if far.value < near.value:
            raise Error("A raycaster's far distance cannot be below its near")
        self.ray = Ray(origin, direction)
        self.near = near
        self.far = far
        self.layers = Layers()
        self.line_threshold = Length(1.0, METER)
        self.points_threshold = Length(1.0, METER)
        self.has_camera = False
        self.camera_world = Matrix4()
        self.camera_perspective = False

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
        # NDC back to camera space, and camera space back to the world,
        # kept apart. One inverse of their product mixes a camera meters
        # away with a near plane millimeters deep, and a Float32 has digits
        # for one of them: from ten kilometers out, a ray built that way
        # landed a meter and a half wide at ten meters. In camera space the
        # point sits at the eye's own scale, and it goes to the world as a
        # direction, through the rotation alone, with no translation added
        # and taken away again.
        var unproject = Matrix4(copy=projection)
        unproject.invert()
        # The camera's own place and facing, in the world.
        var world = Matrix4(copy=view)
        world.invert()
        self.has_camera = True
        self.camera_world = Matrix4(copy=world)
        self.camera_perspective = not projection.is_affine()
        if projection.is_affine():
            # Orthographic. The origin sits on the camera's own plane, the
            # NDC depth that camera-space zero projects to, and every ray
            # goes the way the camera looks.
            var near = camera.near_distance()
            var far = camera.far_distance()
            var origin = unproject.transform_point(
                Vector3(coords.x, coords.y, (near + far) / (near - far))
            )
            self.ray = Ray(
                world.transform_point(origin),
                world.transform_direction(Vector3(0, 0, -1)),
            )
            return
        # Perspective. From the eye, which is camera space's origin, toward
        # where the point is at any depth in front of it: a direction.
        var toward = unproject.transform_point(Vector3(coords.x, coords.y, 0.5))
        self.ray = Ray(
            world.transform_point(Vector3(0, 0, 0)),
            world.transform_direction(toward),
        )

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
        if index < 0 or index >= len(scene.meshes):
            raise Error("No mesh has that index")
        var mesh = scene.meshes[index]
        return self._intersect_shape(
            scene,
            assets,
            mesh,
            scene.world_matrix(mesh.node),
            MESH_HIT,
            index,
            -1,
        )

    def intersect_instanced_mesh(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every place this ray meets one instanced mesh, nearest
        first, three.js's `InstancedMesh.raycast`: each instance is tested
        at the node's transform times its own, and a hit's `instance` says
        which was struck.

        Args:
            scene: The scene the instanced mesh is in, updated.
            assets: The geometry and material it names.
            index: Which, as its position in `scene.instanced_meshes`.

        Returns:
            The hits, nearest first, across every instance.

        Raises:
            Error: If no instanced mesh has that index, or for anything
                `intersect_mesh` raises for, per instance.
        """
        if index < 0 or index >= len(scene.instanced_meshes):
            raise Error("No instanced mesh has that index")
        ref group = scene.instanced_meshes[index]
        var mesh = Mesh(group.geometry, group.material, group.node)
        var world = scene.world_matrix(group.node)
        var hits = List[Hit]()
        for instance in range(group.count()):
            var placed = Matrix4(copy=world)
            placed.multiply(group.matrix_at(instance))
            hits.extend(
                self._intersect_shape(
                    scene, assets, mesh, placed, INSTANCED_HIT, index, instance
                )
            )
        _sort_by_distance(hits)
        return hits^

    def intersect_batched_mesh(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every place this ray meets one batched mesh, nearest
        first, three.js's `BatchedMesh.raycast`: each instance is tested
        with its own geometry at the node's transform times its own, and
        a hit's `instance` says which was struck.

        Args:
            scene: The scene the batched mesh is in, updated.
            assets: The geometries and material it names.
            index: Which, as its position in `scene.batched_meshes`.

        Returns:
            The hits, nearest first, across every instance.

        Raises:
            Error: If no batched mesh has that index, or for anything
                `intersect_mesh` raises for, per instance.
        """
        if index < 0 or index >= len(scene.batched_meshes):
            raise Error("No batched mesh has that index")
        ref batch = scene.batched_meshes[index]
        var world = scene.world_matrix(batch.node)
        var hits = List[Hit]()
        for instance in range(batch.count()):
            var mesh = Mesh(
                batch.geometry_at(instance), batch.material, batch.node
            )
            var placed = Matrix4(copy=world)
            placed.multiply(batch.matrix_at(instance))
            hits.extend(
                self._intersect_shape(
                    scene, assets, mesh, placed, BATCHED_HIT, index, instance
                )
            )
        _sort_by_distance(hits)
        return hits^

    def intersect_lod(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every place this ray meets one LOD, nearest first,
        three.js's `LOD.raycast`: the level tested is the one the distance
        from the ray's origin to the node picks with no memory, and a
        hit's `instance` says which level that was.

        Args:
            scene: The scene the LOD is in, updated.
            assets: The geometries and materials its levels name.
            index: Which, as its position in `scene.lods`.

        Returns:
            The hits, nearest first. None for an LOD with no levels.

        Raises:
            Error: If no LOD has that index, or for anything
                `intersect_mesh` raises for.
        """
        if index < 0 or index >= len(scene.lods):
            raise Error("No LOD has that index")
        ref lod = scene.lods[index]
        var world = scene.world_matrix(lod.node)
        var origin = world.transform_point(Vector3(0, 0, 0))
        var level = lod.level_for(
            Length((self.ray.origin - origin).length(), METER)
        )
        if level < 0:
            return List[Hit]()
        var shown = lod.levels[level]
        return self._intersect_shape(
            scene,
            assets,
            Mesh(shown.geometry, shown.material, lod.node),
            world,
            LOD_HIT,
            index,
            level,
        )

    def intersect_skinned_mesh(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every place this ray meets one skinned mesh, nearest
        first, three.js's `SkinnedMesh.raycast`: the mesh is tested where
        its bones have carried it, and its morph targets before that.

        Args:
            scene: The scene the mesh is in, updated.
            assets: The geometry and material it names.
            index: Which, as its position in `scene.skinned_meshes`.

        Returns:
            The hits, nearest first.

        Raises:
            Error: If no skinned mesh has that index, its bones cannot be
                posed or its skin attributes are refused (see
                `core.deform.skin_carriers`), or for anything
                `intersect_mesh` raises for.
        """
        var pose = skin_pose(scene, index)
        ref skinned = scene.skinned_meshes[index]
        var mesh = Mesh(skinned.geometry, skinned.material, skinned.node)
        mesh.morph_influences = skinned.morph_influences
        ref geometry = assets.geometries.get(skinned.geometry)
        var carriers = skin_carriers(geometry, pose, geometry.vertex_count())
        return self._intersect_shape(
            scene,
            assets,
            mesh,
            scene.world_matrix(skinned.node),
            SKINNED_HIT,
            index,
            -1,
            carriers,
        )

    def intersect_line(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every place this ray passes within `line_threshold` of
        one line, nearest first, three.js's `Line.raycast`.

        Each segment is met at its point nearest the ray. The hit's
        `distance` is along the ray to the ray's nearest point, and its
        `point` is on the segment, as three.js reports them.

        Args:
            scene: The scene the line is in, updated.
            assets: The geometry the line names.
            index: Which, as its position in `scene.lines`.

        Returns:
            The hits, nearest first. None for a line on a layer this
            raycaster does not test, or whose bounds the ray misses.

        Raises:
            Error: If no line has that index, it names a node or a geometry
                that is not there, its geometry has no positions or is
                indexed, the point count does not suit the mode, or the
                threshold is negative or not a number.
        """
        if index < 0 or index >= len(scene.lines):
            raise Error("No line has that index")
        var line = scene.lines[index]
        var reach = self._reach(self.line_threshold)
        var hits = List[Hit]()
        if not scene.shows(line.node, self.layers):
            return hits^
        ref geometry = assets.geometries.get(line.geometry)
        if geometry.is_indexed():
            raise Error("A line geometry cannot be indexed")
        var world = scene.world_matrix(line.node)
        if not self._near_bound(geometry.bounding_sphere(), world, reach):
            return hits^
        var vertices = geometry.vertex_count()
        ref positions = geometry.attribute_view(String("position"))
        var mesh = Mesh(line.geometry, line.material, line.node)
        for segment in range(segment_count(line.mode, vertices)):
            var ends = segment_ends(line.mode, vertices, segment)
            var met = self.ray.distance_sq_to_segment(
                world.transform_point(positions.vector3(ends[0])),
                world.transform_point(positions.vector3(ends[1])),
            )
            if met.distance_sq > reach * reach:
                continue
            var distance = (met.on_ray - self.ray.origin).length()
            if distance < self.near.value or distance > self.far.value:
                continue
            hits.append(
                Hit(
                    distance,
                    met.on_segment,
                    Vector3(0, 0, 0),
                    LINE_HIT,
                    index,
                    -1,
                    mesh,
                    segment,
                )
            )
        _sort_by_distance(hits)
        return hits^

    def intersect_points(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return every point of one points object the ray passes within
        `points_threshold` of, nearest first, three.js's `Points.raycast`.

        A hit's `point` is the ray's point nearest the vertex, and its
        `triangle` is which vertex, as three.js reports them.

        Args:
            scene: The scene the points are in, updated.
            assets: The geometry they name.
            index: Which, as its position in `scene.points`.

        Returns:
            The hits, nearest first. None for points on a layer this
            raycaster does not test, or whose bounds the ray misses.

        Raises:
            Error: If no points object has that index, it names a node or
                a geometry that is not there, its geometry has no positions
                or is indexed, or the threshold is negative or not a
                number.
        """
        if index < 0 or index >= len(scene.points):
            raise Error("No points object has that index")
        var cloud = scene.points[index]
        var reach = self._reach(self.points_threshold)
        var hits = List[Hit]()
        if not scene.shows(cloud.node, self.layers):
            return hits^
        ref geometry = assets.geometries.get(cloud.geometry)
        if geometry.is_indexed():
            raise Error("A points geometry cannot be indexed")
        var world = scene.world_matrix(cloud.node)
        if not self._near_bound(geometry.bounding_sphere(), world, reach):
            return hits^
        ref positions = geometry.attribute_view(String("position"))
        var mesh = Mesh(cloud.geometry, cloud.material, cloud.node)
        # Not empty: an empty geometry's bound is empty, and the test above
        # returned for it.
        for vertex in range(positions.count()):  # pragma: no branch
            var place = world.transform_point(positions.vector3(vertex))
            # Strictly inside, as three.js's test is.
            if not (self.ray.distance_sq_to_point(place) < reach * reach):
                continue
            var point = self.ray.closest_point_to_point(place)
            var distance = (point - self.ray.origin).length()
            if distance < self.near.value or distance > self.far.value:
                continue
            hits.append(
                Hit(
                    distance,
                    point,
                    Vector3(0, 0, 0),
                    POINTS_HIT,
                    index,
                    -1,
                    mesh,
                    vertex,
                )
            )
        _sort_by_distance(hits)
        return hits^

    def intersect_sprite(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> List[Hit]:
        """Return where this ray meets one sprite, three.js's
        `Sprite.raycast`: its two triangles, laid flat to the camera
        `set_from_camera` last aimed through, as the renderer lays them.

        Args:
            scene: The scene the sprite is in, updated.
            assets: The material the sprite names.
            index: Which, as its position in `scene.sprites`.

        Returns:
            One hit, or none.

        Raises:
            Error: If no sprite has that index, it names a node or a
                material that is not there, or no camera has been set.
        """
        if index < 0 or index >= len(scene.sprites):
            raise Error("No sprite has that index")
        if not self.has_camera:
            raise Error(
                "A sprite faces a camera: set_from_camera must set one"
                " before a sprite is picked"
            )
        var sprite = scene.sprites[index]
        var hits = List[Hit]()
        if not scene.shows(sprite.node, self.layers):
            return hits^
        var material = assets.materials.get(sprite.material)
        var world = scene.world_matrix(sprite.node)
        var view = Matrix4(copy=self.camera_world)
        view.invert()
        var center = view.transform_point(
            Vector3(world.elements[12], world.elements[13], world.elements[14])
        )
        var scale_x = _column_length(world, 0)
        var scale_y = _column_length(world, 1)
        if not material.size_attenuation and self.camera_perspective:
            scale_x *= -center.z
            scale_y *= -center.z
        var turn = material.rotation.to(RADIAN)
        var turned_x = cos(turn)
        var turned_y = sin(turn)
        # The unit square's corners, counterclockwise from the bottom
        # left, carried to the world: three.js's `transformVertex`.
        var xs: List[Float32] = [-0.5, 0.5, 0.5, -0.5]
        var ys: List[Float32] = [-0.5, -0.5, 0.5, 0.5]
        var corners = List[Vector3]()
        for corner in range(4):  # pragma: no branch
            var aligned_x = (xs[corner] - (sprite.center.x - 0.5)) * scale_x
            var aligned_y = (ys[corner] - (sprite.center.y - 0.5)) * scale_y
            corners.append(
                self.camera_world.transform_point(
                    Vector3(
                        center.x + turned_x * aligned_x - turned_y * aligned_y,
                        center.y + turned_y * aligned_x + turned_x * aligned_y,
                        center.z,
                    )
                )
            )
        var half = 0
        var met = self.ray.intersect_triangle(
            corners[0], corners[1], corners[2], False
        )
        if not Bool(met):
            half = 1
            met = self.ray.intersect_triangle(
                corners[0], corners[2], corners[3], False
            )
            if not Bool(met):
                return hits^
        var point = met.value()
        var distance = (point - self.ray.origin).length()
        if distance < self.near.value or distance > self.far.value:
            return hits^
        # A sprite names no geometry, as its draw names none.
        var mesh = Mesh(GeometryId(0), sprite.material, sprite.node)
        mesh.geometry = GeometryId(-1)
        hits.append(
            Hit(
                distance,
                point,
                Vector3(0, 0, 0),
                SPRITE_HIT,
                index,
                -1,
                mesh,
                half,
            )
        )
        return hits^

    def _reach(self, threshold: Length) raises -> Float32:
        """Return a line or points threshold in meters, checked.

        Args:
            threshold: The threshold.

        Returns:
            It, in meters.

        Raises:
            Error: If it is negative or not a number.
        """
        var reach = threshold.value
        if not (reach >= 0):
            raise Error("A raycaster's threshold must be a number, not below 0")
        return reach

    def _near_bound(
        self, bound: Sphere, world: Matrix4, reach: Float32
    ) raises -> Bool:
        """Return whether the ray passes within `reach` of a bound.

        Args:
            bound: The geometry's bounding sphere, in its own space.
            world: Where the geometry is.
            reach: How near counts.

        Returns:
            False when nothing of the geometry can be met.

        Raises:
            Error: If the bound cannot be carried by the matrix.
        """
        var sphere = bound
        if sphere.is_empty():
            return False
        sphere.apply_matrix4(world)
        sphere.radius += reach
        return self.ray.intersects_sphere(sphere)

    def _intersect_shape(
        self,
        scene: Scene,
        assets: Assets,
        mesh: Mesh,
        world: Matrix4,
        kind: HitKind,
        index: Int,
        instance: Int,
        carriers: List[Matrix4] = List[Matrix4](),
    ) raises -> List[Hit]:
        """Return every place this ray meets one shape at one transform,
        nearest first: three.js's `Mesh.raycast`, which every picker above
        comes down to.

        Args:
            scene: The scene, for the node's layers.
            assets: The geometry and materials the mesh names.
            mesh: The shape: its node, geometry, material and worn targets.
            world: Where it is, in world space.
            kind: Which list the hits say `index` counts in.
            index: The position in that list.
            instance: Which instance or level, or -1 for a plain mesh.
            carriers: One matrix per vertex that the bones carry it by, or
                none for a mesh no skeleton moves.

        Returns:
            The hits, nearest first. None for a node on a layer this
            raycaster does not test, or a shape whose bounds the ray
            misses.

        Raises:
            Error: If the mesh names a node, a geometry or a material that
                is not there, its geometry has no positions, or `world`
                flattens a dimension, which leaves no inverse to carry the
                ray through.
        """
        var hits = List[Hit]()
        if not scene.shows(mesh.node, self.layers):
            return hits^
        ref geometry = assets.geometries.get(mesh.geometry)
        var material = assets.materials.get(mesh.material)
        # The whole mesh first, in world space: a miss here is the common
        # case and costs six multiplies. An empty sphere, of a geometry
        # with no vertices, is met nowhere.
        # Where the vertices actually are. A mesh wearing a morph target
        # is not where its geometry says it is, and picking the geometry
        # instead answered for a shape nobody could see: the drawn one was
        # missed, and the modelled one was hit where nothing was. Only a
        # morphed mesh pays for this; an unmorphed one keeps the bound the
        # geometry already worked out, and never touches a vertex when the
        # ray misses it.
        var worn = List[Vector3]()
        var skinned = len(carriers) > 0
        if mesh.is_morphed() or skinned:
            worn = morphed_positions(geometry, mesh.morph_influences)
        # Then where the bones carry them, after the targets, as three.js's
        # `skinning_vertex` follows `morphtarget_vertex`.
        if skinned:
            # Not empty: there is a carrier for every vertex, and there
            # are some.
            for vertex in range(len(worn)):  # pragma: no branch
                worn[vertex] = carriers[vertex].transform_point(worn[vertex])
        var bound = geometry.bounding_sphere()
        if len(worn) > 0:
            bound = sphere_of(worn)
        bound.apply_matrix4(world)
        if not self.ray.intersects_sphere(bound):
            return hits^
        # Then into the mesh's own space, where its triangles are.
        var into = Matrix4(copy=world)
        into.invert()
        var local = self.ray
        local.apply_matrix4(into)
        # The box is skipped for a morphed mesh: the sphere above was built
        # from the same worn vertices and has already done the rejecting,
        # and the geometry's own box describes the shape it has left.
        if len(worn) == 0:
            if not local.intersects_box(geometry.bounding_box()):
                return hits^
        var mirrored = world.determinant() < 0
        var near = self.near.value
        var far = self.far.value
        for triangle in range(geometry.triangle_count()):
            var a = _worn_corner(geometry, worn, triangle, 0)
            var b = _worn_corner(geometry, worn, triangle, 1)
            var c = _worn_corner(geometry, worn, triangle, 2)
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
            hits.append(
                Hit(
                    distance,
                    point,
                    normal,
                    kind,
                    index,
                    instance,
                    mesh,
                    triangle,
                )
            )
        _sort_by_distance(hits)
        return hits^

    def intersect_scene(self, scene: Scene, assets: Assets) raises -> List[Hit]:
        """Return every place this ray meets anything of the scene it can
        pick, nearest first, three.js's `intersectObjects`: meshes,
        skinned, instanced and batched meshes, LODs, lines, points and
        sprites. Sprites are left out until a camera is set.

        Args:
            scene: The scene, updated.
            assets: The geometry and materials its objects name.

        Returns:
            The hits, nearest first, across every object on a layer this
            raycaster tests.

        Raises:
            Error: For anything the pickers above raise for.
        """
        var hits = List[Hit]()
        for index in range(len(scene.meshes)):
            hits.extend(self.intersect_mesh(scene, assets, index))
        for index in range(len(scene.instanced_meshes)):
            hits.extend(self.intersect_instanced_mesh(scene, assets, index))
        for index in range(len(scene.batched_meshes)):
            hits.extend(self.intersect_batched_mesh(scene, assets, index))
        for index in range(len(scene.lods)):
            hits.extend(self.intersect_lod(scene, assets, index))
        for index in range(len(scene.skinned_meshes)):
            hits.extend(self.intersect_skinned_mesh(scene, assets, index))
        for index in range(len(scene.lines)):
            hits.extend(self.intersect_line(scene, assets, index))
        for index in range(len(scene.points)):
            hits.extend(self.intersect_points(scene, assets, index))
        if self.has_camera:
            for index in range(len(scene.sprites)):
                hits.extend(self.intersect_sprite(scene, assets, index))
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


def _column_length(matrix: Matrix4, axis: Int) -> Float32:
    """Return the length of one of a matrix's three axis columns: how much
    it scales along that axis, as the renderer measures a sprite.

    Args:
        matrix: The transform.
        axis: Which column, zero for x through two for z.

    Returns:
        The length.
    """
    ref e = matrix.elements
    var start = axis * 4
    return Vector3(e[start], e[start + 1], e[start + 2]).length()
