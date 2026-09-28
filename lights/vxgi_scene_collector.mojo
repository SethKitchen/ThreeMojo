# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene's triangles as flat world-space records for voxelization:
three.js r186's `examples/jsm/lighting/vxgi/VXGISceneCollector.js`.

**What is collected.** Every mesh, instanced mesh and skinned mesh on a
visible node whose layers pass the volume's `layers`. A mesh of a batch is
not collected, as three.js skips `isBatchedMesh`. An instanced mesh gives
each instance's triangles. A skinned mesh gives its triangles at rest, as
three.js reads its `position` attribute. The triangles of each group and
draw range are read as three.js reads them.

**A record.** `TRIANGLE_STRIDE` floats a triangle: the three corners, four
floats each with the fourth unused, the albedo and the side, and the
emissive color with the fourth unused. The side is zero for the front,
one for the back and two for both.

**The colors.** The albedo is the material's color times its `map` read at
the triangle's centroid, three.js's nearest texel of the image. A basic
material is unlit: its color is emissive and its albedo is black.
Otherwise the emissive color is the material's `emissive` times its
`emissive_intensity`, times its `emissive_map` read at the centroid.

**What is skipped.** A triangle whose box misses the volume's bounds, a
triangle of no size, and a triangle whose opacity is below `min_opacity`
or below its material's `alpha_test`. The opacity is the material's
`opacity` when it is transparent, times the map's alpha.

**Subdivision.** A triangle with an edge longer than `max_edge` sub-voxels
is split at the middle of its longest edge, again and again, so that no
record covers more than a few voxels.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, POSITION, UV, UV1
from core.layers import Layers
from core.object3d import NodeId
from core.scene import Scene
from materials.material import (
    BACK_SIDE,
    BASIC,
    DEPTH,
    DISTANCE,
    DOUBLE_SIDE,
    GOURAUD,
    LAMBERT,
    Material,
    MaterialId,
    NORMALS,
    PHONG,
    PHYSICAL,
    STANDARD,
    TOON,
)
from math.bounds import Box3
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear
from render.texture import (
    CLAMP,
    REPEAT,
    Texture,
    UV_CHANNEL_0,
    Wrap,
    fetch_row,
    row_coordinate,
)
from render.texture_store import NO_TEXTURE, TextureId
from std.math import ceil, floor


# Floats a triangle record holds: three corners, the albedo and side, and
# the emissive color, four floats each. three.js's `TRIANGLE_STRIDE`.
comptime TRIANGLE_STRIDE = 20

# The longest edge a record keeps, in sub-voxels, three.js's
# `MAX_EDGE_SUBVOXELS`.
comptime MAX_EDGE_SUBVOXELS = 16

# The squared box diagonal below which a triangle has no size, three.js's
# `1e-14`.
comptime DEGENERATE = Float32(1e-14)


def _linear(color: Color) -> Vector3:
    """Return a stored color as the linear color three.js keeps."""
    return Vector3(
        srgb_to_linear(Float32(color.r) / 255),
        srgb_to_linear(Float32(color.g) / 255),
        srgb_to_linear(Float32(color.b) / 255),
    )


struct _MaterialInfo(ImplicitlyCopyable):
    """What the collector reads of a material: three.js's
    `getMaterialInfo`."""

    var unlit: Bool
    var side: Float32
    var opacity: Float32
    var alpha_test: Float32
    var color: Vector3
    var emissive: Vector3
    var map: TextureId
    var emissive_map: TextureId

    def __init__(out self, material: Material):
        """Read a material."""
        self.unlit = material.kind == BASIC
        self.side = 0
        if material.side == BACK_SIDE:
            self.side = 1
        elif material.side == DOUBLE_SIDE:
            self.side = 2
        self.opacity = 1
        if material.transparent:
            self.opacity = material.opacity
        self.alpha_test = material.alpha_test
        # A normal, depth or distance material has no color, and reads as
        # white, as three.js's `color` is missing there.
        var colorless = (
            material.kind == NORMALS
            or material.kind == DEPTH
            or material.kind == DISTANCE
        )
        self.color = Vector3(1, 1, 1)
        if not colorless:
            self.color = _linear(material.color)
        # Only the lit materials with an `emissive` field glow.
        var glows = (
            material.kind == LAMBERT
            or material.kind == PHONG
            or material.kind == TOON
            or material.kind == STANDARD
            or material.kind == PHYSICAL
            or material.kind == GOURAUD
        )
        self.emissive = Vector3(0, 0, 0)
        self.emissive_map = NO_TEXTURE
        if glows:
            self.emissive = _linear(material.emissive) * (
                material.emissive_intensity
            )
            self.emissive_map = material.emissive_map
        self.map = material.map


def _wrapped(coordinate: Float32, mode: Wrap) -> Float32:
    """Return a coordinate kept inside zero to one by a wrap mode, as
    three.js's `Texture.transformUv` keeps it: only a coordinate outside
    is moved."""
    if coordinate >= 0 and coordinate <= 1:
        return coordinate
    if mode == REPEAT:
        return coordinate - floor(coordinate)
    if mode == CLAMP:
        return 0 if coordinate < 0 else 1
    # A mirrored repeat: an odd tile runs backward.
    var tile = Int(floor(coordinate))
    if abs(tile) % 2 == 1:
        return ceil(coordinate) - coordinate
    return coordinate - floor(coordinate)


def sample_texture(texture: Texture, u: Float32, v: Float32) -> FloatColor:
    """Return the texel of a texture at a coordinate, as three.js's
    `sampleTexture` reads the collector's image: moved by the texture's
    transform, wrapped, and read at the texel it falls in.

    Args:
        texture: The texture.
        u: Across.
        v: Up.

    Returns:
        The texel's linear color and its alpha.
    """
    if texture.is_blank():
        return FloatColor(1, 1, 1, 1)
    var to_uv = texture.uv_transform()
    ref e = to_uv.elements
    var mu = e[0] * u + e[3] * v + e[6]
    var mv = e[1] * u + e[4] * v + e[7]
    mu = _wrapped(mu, texture.wrap_s)
    mv = _wrapped(mv, texture.wrap_t)
    var width = texture.width
    var height = texture.height
    var column = max(0, min(width - 1, Int(floor(mu * Float32(width)))))
    var row = max(
        0,
        min(
            height - 1,
            Int(floor(row_coordinate(mv, texture.flip_y) * Float32(height))),
        ),
    )
    # `fetch` counts its row as `v` counts, so the stored row is turned
    # back first.
    return texture.fetch(column, fetch_row(row, height, texture.flip_y), 0)


struct _Collector(Movable):
    """The records being written, and what every triangle is tested
    against."""

    var records: List[Float32]
    var bounds: Box3
    var max_edge_sq: Float32
    var min_opacity: Float32

    def __init__(
        out self,
        bounds: Box3,
        sub_voxel_size: Float32,
        max_edge: Int,
        min_opacity: Float32,
    ):
        """Start with no records."""
        self.records = List[Float32]()
        self.bounds = bounds
        var edge = Float32(max_edge) * sub_voxel_size
        self.max_edge_sq = edge * edge
        self.min_opacity = min_opacity

    def emit(
        mut self,
        a: Vector3,
        b: Vector3,
        c: Vector3,
        albedo: Vector3,
        emissive: Vector3,
        side: Float32,
    ):
        """Write one triangle, split along its longest edge until every
        edge is short enough: three.js's `emit`, with its stack."""
        var stack: List[Vector3] = [a, b, c]
        while len(stack) > 0:
            var pc = stack.pop()
            var pb = stack.pop()
            var pa = stack.pop()
            var ab = pa.distance_to_squared(pb)
            var bc = pb.distance_to_squared(pc)
            var ca = pc.distance_to_squared(pa)
            var longest = max(ab, max(bc, ca))
            if longest > self.max_edge_sq:
                if longest == ab:
                    var middle = (pa + pb) * 0.5
                    stack.extend([pa, middle, pc, middle, pb, pc])
                elif longest == bc:
                    var middle = (pb + pc) * 0.5
                    stack.extend([pa, pb, middle, pa, middle, pc])
                else:
                    var middle = (pc + pa) * 0.5
                    stack.extend([pa, pb, middle, middle, pb, pc])
                continue
            for corner in [pa, pb, pc]:  # pragma: no branch
                self.records.extend([corner.x, corner.y, corner.z, 0])
            self.records.extend([albedo.x, albedo.y, albedo.z, side])
            self.records.extend([emissive.x, emissive.y, emissive.z, 0])


def _uv_name(texture: Texture) -> String:
    """Return the attribute a texture is read through, three.js's
    `'uv' + channel`."""
    if texture.channel == UV_CHANNEL_0:
        return UV
    return UV1


def _centroid_uv(
    geometry: BufferGeometry, name: String, ia: Int, ib: Int, ic: Int
) raises -> Tuple[Float32, Float32]:
    """Return the mean of a triangle's three texture coordinates."""
    ref uvs = geometry.attribute_view(name)
    var u = uvs.component(ia, 0) + uvs.component(ib, 0) + uvs.component(ic, 0)
    var v = uvs.component(ia, 1) + uvs.component(ib, 1) + uvs.component(ic, 1)
    var third = Float32(1) / 3
    return (u * third, v * third)


def _add_run(
    mut collector: _Collector,
    geometry: BufferGeometry,
    assets: Assets,
    info: _MaterialInfo,
    matrix: Matrix4,
    start: Int,
    end: Int,
) raises:
    """Write the triangles of one group, `start` to `end` slots."""
    ref positions = geometry.attribute_view(POSITION)
    var indexed = geometry.is_indexed()
    var with_map = info.map != NO_TEXTURE
    var map_uv = String(UV)
    if with_map:
        map_uv = _uv_name(assets.textures.get(info.map))
        with_map = geometry.has_attribute(map_uv)
    var with_glow = info.emissive_map != NO_TEXTURE
    var glow_uv = String(UV)
    if with_glow:
        glow_uv = _uv_name(assets.textures.get(info.emissive_map))
        with_glow = geometry.has_attribute(glow_uv)
    var slot = start
    while slot + 2 < end:
        var ia = slot
        var ib = slot + 1
        var ic = slot + 2
        if indexed:
            ia = geometry.index[slot]
            ib = geometry.index[slot + 1]
            ic = geometry.index[slot + 2]
        slot += 3
        var a = matrix.transform_point(positions.vector3(ia))
        var b = matrix.transform_point(positions.vector3(ib))
        var c = matrix.transform_point(positions.vector3(ic))
        var box = Box3.from_points([a, b, c])
        if not collector.bounds.intersects_box(box):
            continue
        if box.min.distance_to_squared(box.max) < DEGENERATE:
            continue
        var alpha = info.opacity
        var albedo = info.color
        if with_map:
            var at = _centroid_uv(geometry, map_uv, ia, ib, ic)
            var texel = sample_texture(
                assets.textures.get(info.map), at[0], at[1]
            )
            alpha *= texel.a
            albedo = Vector3(
                albedo.x * texel.r, albedo.y * texel.g, albedo.z * texel.b
            )
        if info.alpha_test > 0 and alpha < info.alpha_test:
            continue
        if alpha < collector.min_opacity:
            continue
        var emissive = info.emissive
        if info.unlit:
            emissive = albedo
            albedo = Vector3(0, 0, 0)
        elif with_glow:
            var at = _centroid_uv(geometry, glow_uv, ia, ib, ic)
            var texel = sample_texture(
                assets.textures.get(info.emissive_map), at[0], at[1]
            )
            emissive = Vector3(
                emissive.x * texel.r, emissive.y * texel.g, emissive.z * texel.b
            )
        collector.emit(a, b, c, albedo, emissive, info.side)


def _stream_length(geometry: BufferGeometry) raises -> Int:
    """Return how many slots a geometry's triangle stream has: its index,
    or its vertices."""
    if geometry.is_indexed():
        return len(geometry.index)
    return geometry.vertex_count()


def _add_geometry(
    mut collector: _Collector,
    geometry: BufferGeometry,
    assets: Assets,
    materials: List[Optional[MaterialId]],
    whole: Bool,
    matrix: Matrix4,
) raises:
    """Write a geometry's triangles through a world matrix: three.js's
    `processMesh`. `materials` holds one material a group, or none for a
    group whose material the list has not got. A `whole` geometry is one
    run of its whole stream in the first material, whatever its groups."""
    var count = _stream_length(geometry)
    var range_start = geometry.draw_range.start
    var range_end = count
    if Bool(geometry.draw_range.count):
        range_end = min(count, range_start + geometry.draw_range.count.value())
    var runs = 1 if whole else len(geometry.groups)
    # A whole geometry is one run, and any other has groups.
    for run in range(runs):  # pragma: no branch
        var group_start = 0
        var group_end = count
        if not whole:
            group_start = geometry.groups[run].start
            group_end = group_start + geometry.groups[run].count
        var worn = materials[0] if whole else materials[run]
        if not Bool(worn):
            continue
        var material = assets.materials.get(worn.value())
        if not material.visible:
            continue
        var info = _MaterialInfo(material)
        if info.opacity < collector.min_opacity:
            continue
        _add_run(
            collector,
            geometry,
            assets,
            info,
            matrix,
            max(group_start, range_start),
            min(group_end, range_end),
        )


def _mesh_materials(
    scene: Scene, geometry: BufferGeometry, which: Int
) raises -> List[Optional[MaterialId]]:
    """Return the material each group of a mesh wears, or its one material:
    three.js's `materials[group.materialIndex]`, and one group reading
    material zero when the mesh wears one material or its geometry has no
    groups."""
    ref mesh = scene.meshes[which]
    var worn = List[Optional[MaterialId]]()
    if not mesh.is_multi_material():
        worn.append(mesh.material)
        return worn^
    if len(geometry.groups) == 0:
        worn.append(Optional[MaterialId](mesh.materials[0]))
        return worn^
    # The geometry has groups here, so the loop runs.
    for group in geometry.groups:  # pragma: no branch
        worn.append(mesh.group_material(group.material_index))
    return worn^


struct _Placed(Copyable, Movable):
    """The meshes, instanced meshes and skinned meshes on each node."""

    var meshes: List[List[Int]]
    var instanced: List[List[Int]]
    var skinned: List[List[Int]]

    def __init__(out self, scene: Scene):
        """File each mesh under its node."""
        var count = scene.count()
        self.meshes = List[List[Int]](length=count, fill=List[Int]())
        self.instanced = List[List[Int]](length=count, fill=List[Int]())
        self.skinned = List[List[Int]](length=count, fill=List[Int]())
        for which in range(len(scene.meshes)):
            self.meshes[scene.meshes[which].node.value].append(which)
        for which in range(len(scene.instanced_meshes)):
            self.instanced[scene.instanced_meshes[which].node.value].append(
                which
            )
        for which in range(len(scene.skinned_meshes)):
            self.skinned[scene.skinned_meshes[which].node.value].append(which)


def _voxelizable(
    scene: Scene, placed: _Placed, layers: Layers
) raises -> List[NodeId]:
    """Return the visible nodes whose layers pass and that carry a mesh:
    three.js's `isVoxelizable` over `traverseVisible`."""
    var found = List[NodeId]()
    for id in scene.traverse_visible():
        var node = id.value
        var things = (
            len(placed.meshes[node])
            + len(placed.instanced[node])
            + len(placed.skinned[node])
        )
        if things == 0:
            continue
        if not layers.test(scene.get(id).layers):
            continue
        found.append(id)
    return found^


def _grow(mut bounds: Box3, geometry: BufferGeometry, matrix: Matrix4) raises:
    """Grow a box by every vertex of a geometry through a matrix: three.js's
    `expandByObject` with `precise`."""
    ref positions = geometry.attribute_view(POSITION)
    for vertex in range(positions.count()):
        bounds.expand_by_point(
            matrix.transform_point(positions.vector3(vertex))
        )


def compute_scene_bounds(
    scene: Scene, assets: Assets, layers: Layers
) raises -> Box3:
    """Return the world box around every mesh the collector reads: three.js's
    `computeSceneBounds`.

    A mesh and a skinned mesh grow the box by each vertex. An instanced
    mesh grows it by its geometry's box, moved by each instance, then by
    the node: three.js's `boundingBox` of the instances.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.
        layers: The layers a node must share one of.

    Returns:
        The box, empty when no mesh is read.

    Raises:
        Error: If the scene is stale or a mesh names a geometry that is not
            there.
    """
    var bounds = Box3.empty()
    var placed = _Placed(scene)
    for id in _voxelizable(scene, placed, layers):
        var matrix = scene.world_matrix(id)
        for which in placed.meshes[id.value]:
            _grow(
                bounds,
                assets.geometries.get(scene.meshes[which].geometry),
                matrix,
            )
        for which in placed.skinned[id.value]:
            _grow(
                bounds,
                assets.geometries.get(scene.skinned_meshes[which].geometry),
                matrix,
            )
        for which in placed.instanced[id.value]:
            ref group = scene.instanced_meshes[which]
            var shape = assets.geometries.get(group.geometry).bounding_box()
            var instances = Box3.empty()
            for instance in group.matrices:
                var moved = shape
                moved.apply_matrix4(instance)
                instances.union(moved)
            instances.apply_matrix4(matrix)
            bounds.union(instances)
    return bounds


def collect_scene_triangles(
    scene: Scene,
    assets: Assets,
    bounds: Box3,
    layers: Layers,
    sub_voxel_size: Float32,
    max_edge: Int,
    min_opacity: Float32,
) raises -> List[Float32]:
    """Return the triangle records of every mesh the collector reads:
    three.js's `collectSceneTriangles`. See the module docstring.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries, materials and textures are.
        bounds: A triangle whose box misses these is skipped.
        layers: The layers a node must share one of.
        sub_voxel_size: The edge of a sub-voxel, in meters.
        max_edge: The longest edge a record keeps, in sub-voxels.
        min_opacity: A triangle less opaque than this is skipped.

    Returns:
        `TRIANGLE_STRIDE` floats a triangle.

    Raises:
        Error: If the scene is stale, or a mesh names a geometry, a
            material or a texture that is not there, or an index past its
            positions.
    """
    var collector = _Collector(bounds, sub_voxel_size, max_edge, min_opacity)
    var placed = _Placed(scene)
    for id in _voxelizable(scene, placed, layers):
        var matrix = scene.world_matrix(id)
        for which in placed.meshes[id.value]:
            ref geometry = assets.geometries.get(scene.meshes[which].geometry)
            var whole = (
                not scene.meshes[which].is_multi_material()
                or len(geometry.groups) == 0
            )
            _add_geometry(
                collector,
                geometry,
                assets,
                _mesh_materials(scene, geometry, which),
                whole,
                matrix,
            )
        for which in placed.skinned[id.value]:
            ref skinned = scene.skinned_meshes[which]
            var worn: List[Optional[MaterialId]] = [
                Optional[MaterialId](skinned.material)
            ]
            _add_geometry(
                collector,
                assets.geometries.get(skinned.geometry),
                assets,
                worn,
                True,
                matrix,
            )
        for which in placed.instanced[id.value]:
            ref group = scene.instanced_meshes[which]
            var worn: List[Optional[MaterialId]] = [
                Optional[MaterialId](group.material)
            ]
            for instance in group.matrices:
                _add_geometry(
                    collector,
                    assets.geometries.get(group.geometry),
                    assets,
                    worn,
                    True,
                    matrix * instance,
                )
    return collector.records.copy()
