# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the four exporters share: numbers written so they read back
exactly, bytes in either order, a geometry checked before it is written,
and a scene's meshes carried into world space.

**A JSON number is written so it reads back to the same `Float32`.**
`format_float32` writes the shortest text that does so, which is what
`String(Float32)` aims for. It misses by one unit in the last place for
about one number in two hundred, so `format_float32` reads its own answer
back and, when it is wrong, writes the number's exact `Float64` form
instead, which always reads back. A number that is not finite is refused:
no text format here can hold one, and every loader here refuses one.

**OBJ, STL and PLY write a number as three.js does.** three.js holds a
vertex value as a double and writes JavaScript's `String` of it:
`0.10000000149011612` for the `Float32` nearest a tenth.
`format_js_float32` writes the exact `Float64` of a `Float32` that way,
so a value passed through as it is has the same text. A value that
three.js works out through a matrix in doubles, and this port in
`Float32`s, has the same text only when both are exact.

**A mesh is written in world space** by OBJ, STL and PLY, as three.js's
`OBJExporter`, `STLExporter` and `PLYExporter` write it: every position
through its node's world matrix, and every normal through the normal
matrix of it, made unit length again. `world_meshes` does that once for
all three. The scene must be current: `Scene.world_matrix` refuses a
scene changed since `update`.

**Every mesh is written, in the order three.js reaches it.** three.js's
exporters walk the scene with `traverse` and write each object that
`isMesh`. A `SkinnedMesh` and an `InstancedMesh` are both meshes there.
So `world_meshes` walks `Scene.traverse` and gathers the meshes, the
skinned meshes and the instanced meshes of each node, and the lines and
points when an exporter asks for them. A skinned mesh is at rest, and
posed by its bones only for STL, as three.js's `STLExporter` alone calls
`applyBoneTransform`. An instanced mesh is its one geometry at its node:
three.js's exporters read `matrixWorld` and never `instanceMatrix`.
Batched meshes, LODs, sprites and wide lines are not written.
"""

from core.assets import Assets
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    GeometryGroup,
)
from core.deform import skin_carriers, skin_pose
from core.object3d import NodeId
from materials.material import MaterialId
from math.matrix4 import Matrix4
from core.scene import Scene
from loaders.js_number import js_number_text
from objects.line import LineMode, STRIP
from std.math import isfinite
from std.memory import bitcast


def format_float32(value: Float32) raises -> String:
    """Return the text of a number that reads back to the same `Float32`.

    Args:
        value: The number.

    Returns:
        The shortest text when it reads back exactly, else the number's
        exact `Float64` text. Both are JSON numbers, and both read as
        numbers in OBJ, STL and PLY.

    Raises:
        Error: If the number is not finite.
    """
    if not isfinite(value):
        raise Error("A number to write must be finite: " + String(value))
    var short = String(value)
    if Float32(Float64(short)) == value:
        return short
    # `Float64(value)` is exact, and its shortest text reads back to it.
    return String(Float64(value))


def format_js_float32(value: Float32) raises -> String:
    """Return the text three.js writes for a `Float32` it holds as a
    double: JavaScript's `String` of the number's exact `Float64`.

    Args:
        value: The number.

    Returns:
        `1` for one, `0.5` for a half, and `0.10000000149011612` for the
        `Float32` nearest a tenth, as three.js writes each. It reads back
        to the same `Float32`.

    Raises:
        Error: If the number is not finite.
    """
    if not isfinite(value):
        raise Error("A number to write must be finite: " + String(value))
    return js_number_text(Float64(value))


def push_word(mut out: List[UInt8], value: Int, size: Int, little: Bool):
    """Append the low `size` bytes of an integer in one byte order.

    Args:
        out: Where the bytes go.
        value: The integer. Only its low `size` bytes are written.
        size: How many bytes: 1, 2 or 4.
        little: True for least significant first, False for most.
    """
    # Every caller passes a size of one, two or four: the loop always runs.
    for step in range(size):  # pragma: no branch
        var shift = step * 8 if little else (size - 1 - step) * 8
        out.append(UInt8((value >> shift) & 0xFF))


def push_f32(mut out: List[UInt8], value: Float32, little: Bool) raises:
    """Append a `Float32`'s four bytes in one byte order.

    Args:
        out: Where the bytes go.
        value: The number.
        little: True for least significant first, False for most.

    Raises:
        Error: If the number is not finite. Every loader here refuses
            one, so no file is written with one.
    """
    if not isfinite(value):
        raise Error("A number to write must be finite: " + String(value))
    push_word(out, Int(bitcast[DType.uint32](value)), 4, little)


def _check_attribute(
    geometry: BufferGeometry, name: String, least: Int, most: Int, count: Int
) raises:
    """Refuse an attribute that is there with the wrong item size or the
    wrong vertex count."""
    if not geometry.has_attribute(name):
        return
    ref found = geometry.attribute_view(name)
    if found.item_size < least or found.item_size > most:
        raise Error(
            "An exported "
            + name
            + " must hold "
            + String(least)
            + " to "
            + String(most)
            + " numbers a vertex"
        )
    if found.count() != count:
        raise Error("An exported " + name + " must have one item per position")


def check_geometry(
    geometry: BufferGeometry, triangles: Bool = True
) raises -> Int:
    """Refuse a geometry no exporter can write, and return its vertex
    count.

    Args:
        geometry: The geometry.
        triangles: True for a geometry drawn as triangles, False for one
            drawn as lines or points, whose vertices need not come three
            to a triangle.

    Returns:
        How many vertices its `position` holds.

    Raises:
        Error: If it has no `position`, or one of other than three
            numbers a vertex; a `normal` of other than three, a `uv` of
            other than two, or a `color` of other than three or four, or
            any of them with a count other than the positions'; an index
            entry that is negative or past the last vertex; or, for
            triangles, an index that is not whole triangles, or no index
            and a vertex count that is not a whole number of triangles.
    """
    if not geometry.has_attribute(POSITION):
        raise Error("An exported geometry needs a position attribute")
    ref position = geometry.attribute_view(POSITION)
    if position.item_size != 3:
        raise Error("An exported position must hold three numbers a vertex")
    var count = position.count()
    _check_attribute(geometry, NORMAL, 3, 3, count)
    _check_attribute(geometry, UV, 2, 2, count)
    _check_attribute(geometry, COLOR, 3, 4, count)
    # The index is an open field, so what `set_index` refuses is refused
    # again here: a negative entry would read before the first position.
    if triangles and len(geometry.index) % 3 != 0:
        raise Error("An exported index must hold whole triangles")
    for slot in range(len(geometry.index)):
        if geometry.index[slot] < 0:
            raise Error("An index entry cannot be negative")
        if geometry.index[slot] >= count:
            raise Error("An index entry points past the last vertex")
    if triangles and not geometry.is_indexed() and count % 3 != 0:
        raise Error(
            "A geometry without an index must hold whole triangles to be"
            " exported"
        )
    return count


@fieldwise_init
struct WorldKind(Equatable, ImplicitlyCopyable, Writable):
    """What a `WorldMesh` is drawn as, as a type rather than a bare int.

    three.js's exporters ask `isMesh`, `isLine` and `isPoints` of each
    object. This is that answer. `world_meshes` sets it, and each exporter
    reads it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `WORLD_MESH`, `WORLD_LINE` or
        `WORLD_POINTS`."""
        return self == WORLD_MESH or self == WORLD_LINE or self == WORLD_POINTS


# Triangles: a `Mesh`, a `SkinnedMesh` or an `InstancedMesh`.
comptime WORLD_MESH = WorldKind(0)
# A `Line`, in any `LineMode`.
comptime WORLD_LINE = WorldKind(1)
# A `Points`.
comptime WORLD_POINTS = WorldKind(2)


struct WorldMesh(Copyable, Movable):
    """One mesh, line or points carried into world space: what OBJ, STL
    and PLY write."""

    # The name of the node, three.js's `object.name`.
    var name: String
    # Whether it is triangles, a line or points, and how a line pairs its
    # points. `line_mode` is `STRIP` for everything but a line.
    var kind: WorldKind
    var line_mode: LineMode
    # Three numbers a vertex, through the node's world matrix.
    var positions: List[Float32]
    # Three a vertex, through the normal matrix and made unit length,
    # when the geometry has normals and the vertices are not posed.
    var normals: List[Float32]
    var with_normals: Bool
    # Two a vertex, as the geometry has them, when it has any.
    var uvs: List[Float32]
    var with_uvs: Bool
    # Three or four a vertex, linear, as the geometry has them.
    var colors: List[Float32]
    var color_size: Int
    # Three vertices a triangle: the index, or every vertex in order. For
    # a line or points: every vertex in order, as three.js's `OBJExporter`
    # and `PLYExporter` read them, whatever the index says.
    var triangles: List[Int]
    # Whether the mesh wears a material list. If it does, `runs` are the
    # groups it draws, each beside the material it wears: `runs[i]`
    # counts in `triangles` and wears `run_materials[i]`. A group whose
    # material the list does not have is left out, as it is not drawn.
    var multi_material: Bool
    var runs: List[GeometryGroup]
    var run_materials: List[MaterialId]

    def __init__(
        out self,
        var name: String,
        kind: WorldKind = WORLD_MESH,
        line_mode: LineMode = STRIP,
    ):
        """Start a mesh, a line or points with no vertices.

        Args:
            name: Its name.
            kind: What it is drawn as.
            line_mode: How a line pairs its points.
        """
        self.name = name^
        self.kind = kind
        self.line_mode = line_mode
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.with_normals = False
        self.uvs = List[Float32]()
        self.with_uvs = False
        self.colors = List[Float32]()
        self.color_size = 0
        self.triangles = List[Int]()
        self.multi_material = False
        self.runs = List[GeometryGroup]()
        self.run_materials = List[MaterialId]()

    def vertex_count(self) -> Int:
        """Return how many vertices the mesh has."""
        return len(self.positions) // 3


struct WorldOptions(ImplicitlyCopyable):
    """What `world_meshes` gathers, by the exporter that asks."""

    # Carry a skinned mesh's vertices by its bones, as three.js's
    # `STLExporter` does with `applyBoneTransform`. The other exporters
    # write the mesh at rest, as three.js's do.
    var posed: Bool
    # Gather lines, as three.js's `OBJExporter` does.
    var lines: Bool
    # Gather points, as three.js's `OBJExporter` and `PLYExporter` do.
    var points: Bool
    # Refuse a mesh that is not whole triangles. Off for a PLY file that
    # writes no faces, which three.js writes whatever the vertex count.
    var whole_triangles: Bool

    def __init__(
        out self,
        *,
        posed: Bool = False,
        lines: Bool = False,
        points: Bool = False,
        whole_triangles: Bool = True,
    ):
        """Choose what to gather. The defaults gather meshes at rest.

        Args:
            posed: Carry skinned vertices by their bones.
            lines: Gather lines.
            points: Gather points.
            whole_triangles: Refuse a mesh that is not whole triangles.
        """
        self.posed = posed
        self.lines = lines
        self.points = points
        self.whole_triangles = whole_triangles


def _bucket(
    mut buckets: List[List[Int]], node: NodeId, which: Int, what: String
) raises:
    """File one object under the node it rides, refusing a node the scene
    has not got."""
    if node.value < 0 or node.value >= len(buckets):
        raise Error(what + " names a node that is not in the scene")
    buckets[node.value].append(which)


def _carry(
    mut world: WorldMesh,
    geometry: BufferGeometry,
    matrix: Matrix4,
    carriers: List[Matrix4],
    whole_triangles: Bool,
) raises:
    """Fill a world mesh from its geometry, through its node's world
    matrix, and first through one carrier a vertex when there are any."""
    var count = check_geometry(
        geometry, whole_triangles and world.kind == WORLD_MESH
    )
    var posed = len(carriers) > 0
    ref position = geometry.attribute_view(POSITION)
    for vertex in range(count):
        var point = position.vector3(vertex)
        if posed:
            point = carriers[vertex].transform_point(point)
        point = matrix.transform_point(point)
        world.positions.append(point.x)
        world.positions.append(point.y)
        world.positions.append(point.z)
        world.triangles.append(vertex)
    if world.kind == WORLD_LINE:
        return
    # A posed vertex's normal would need its own carrier's normal matrix,
    # and STL, the one exporter that poses, writes face normals only.
    if geometry.has_attribute(NORMAL) and not posed:
        var turn = matrix.normal_matrix()
        ref normal = geometry.attribute_view(NORMAL)
        for vertex in range(count):
            var direction = turn.transform_direction(normal.vector3(vertex))
            direction.normalize()
            world.normals.append(direction.x)
            world.normals.append(direction.y)
            world.normals.append(direction.z)
        world.with_normals = True
    if geometry.has_attribute(UV):
        world.uvs = geometry.attribute_view(UV).packed()
        world.with_uvs = True
    if geometry.has_attribute(COLOR):
        ref color = geometry.attribute_view(COLOR)
        world.colors = color.packed()
        world.color_size = color.item_size
    if world.kind == WORLD_MESH and geometry.is_indexed():
        world.triangles = geometry.index.copy()


def world_meshes(
    scene: Scene, assets: Assets, options: WorldOptions = WorldOptions()
) raises -> List[WorldMesh]:
    """Return what a scene draws in world space, in the order three.js's
    `traverse` reaches it.

    Nodes come in `Scene.traverse` order. On one node come its meshes,
    its skinned meshes and its instanced meshes, then its lines and its
    points when `options` asks for them, each in its list's order. A
    removed node and all under it are left out: they are not in the
    scene. A skinned mesh is written at rest unless `options.posed`, and
    an instanced mesh is its one geometry at its node, as three.js's
    exporters write any `isMesh`: its instances are not written.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.
        options: What to gather.

    Returns:
        One `WorldMesh` a mesh, a line or points.

    Raises:
        Error: If the scene is stale, a mesh names a node or a geometry
            that is not there, a geometry is refused by `check_geometry`,
            or a node that carries normals has a world matrix that
            flattens an axis, which leaves no normal matrix. For a posed
            skinned mesh, anything `core.deform.skin_pose` or
            `core.deform.skin_carriers` raises.
    """
    var count = scene.count()
    var meshes = List[List[Int]](length=count, fill=List[Int]())
    var skinned = List[List[Int]](length=count, fill=List[Int]())
    var instanced = List[List[Int]](length=count, fill=List[Int]())
    var lines = List[List[Int]](length=count, fill=List[Int]())
    var points = List[List[Int]](length=count, fill=List[Int]())
    for which in range(len(scene.meshes)):
        _bucket(meshes, scene.meshes[which].node, which, "A mesh")
    for which in range(len(scene.skinned_meshes)):
        _bucket(skinned, scene.skinned_meshes[which].node, which, "A mesh")
    for which in range(len(scene.instanced_meshes)):
        _bucket(instanced, scene.instanced_meshes[which].node, which, "A mesh")
    if options.lines:
        for which in range(len(scene.lines)):
            _bucket(lines, scene.lines[which].node, which, "A line")
    if options.points:
        for which in range(len(scene.points)):
            _bucket(points, scene.points[which].node, which, "Points")
    var found = List[WorldMesh]()
    var still = List[Matrix4]()
    for id in scene.traverse():
        var node = id.value
        var things = (
            len(meshes[node])
            + len(skinned[node])
            + len(instanced[node])
            + len(lines[node])
            + len(points[node])
        )
        if things == 0:
            continue
        var matrix = scene.world_matrix(id)
        var name = scene.get(id).name
        for which in meshes[node]:
            ref mesh = scene.meshes[which]
            ref geometry = assets.geometries.get(mesh.geometry)
            var world = WorldMesh(name)
            _carry(world, geometry, matrix, still, options.whole_triangles)
            world.multi_material = mesh.is_multi_material()
            if world.multi_material:
                for group in geometry.groups:
                    var worn = mesh.group_material(group.material_index)
                    if Bool(worn):
                        world.runs.append(group)
                        world.run_materials.append(worn.value())
            found.append(world^)
        for which in skinned[node]:
            ref geometry = assets.geometries.get(
                scene.skinned_meshes[which].geometry
            )
            var carriers = List[Matrix4]()
            if options.posed:
                var vertices = check_geometry(geometry, options.whole_triangles)
                carriers = skin_carriers(
                    geometry, skin_pose(scene, which), vertices
                )
            var world = WorldMesh(name)
            _carry(world, geometry, matrix, carriers, options.whole_triangles)
            found.append(world^)
        for which in instanced[node]:
            var world = WorldMesh(name)
            _carry(
                world,
                assets.geometries.get(scene.instanced_meshes[which].geometry),
                matrix,
                still,
                options.whole_triangles,
            )
            found.append(world^)
        for which in lines[node]:
            ref line = scene.lines[which]
            var world = WorldMesh(name, WORLD_LINE, line.mode)
            _carry(
                world,
                assets.geometries.get(line.geometry),
                matrix,
                still,
                False,
            )
            found.append(world^)
        for which in points[node]:
            var world = WorldMesh(name, WORLD_POINTS)
            _carry(
                world,
                assets.geometries.get(scene.points[which].geometry),
                matrix,
                still,
                False,
            )
            found.append(world^)
    return found^
