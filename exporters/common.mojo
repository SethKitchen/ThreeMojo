# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the four exporters share: numbers written so they read back
exactly, bytes in either order, a geometry checked before it is written,
and a scene's meshes carried into world space.

**A number is written so it reads back to the same `Float32`.** The
shortest text that does so is what three.js writes, and it is what
`String(Float32)` aims for. It misses by one unit in the last place for
about one number in two hundred, so `format_float32` reads its own answer
back and, when it is wrong, writes the number's exact `Float64` form
instead, which always reads back. A number that is not finite is refused:
no text format here can hold one, and every loader here refuses one.

**A mesh is written in world space** by OBJ, STL and PLY, as three.js's
`OBJExporter`, `STLExporter` and `PLYExporter` write it: every position
through its node's world matrix, and every normal through the normal
matrix of it, made unit length again. `world_meshes` does that once for
all three. The scene must be current: `Scene.world_matrix` refuses a
scene changed since `update`.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from core.scene import Scene
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


def check_geometry(geometry: BufferGeometry) raises -> Int:
    """Refuse a geometry no exporter can write, and return its vertex
    count.

    Args:
        geometry: The geometry.

    Returns:
        How many vertices its `position` holds.

    Raises:
        Error: If it has no `position`, or one of other than three
            numbers a vertex; a `normal` of other than three, a `uv` of
            other than two, or a `color` of other than three or four, or
            any of them with a count other than the positions'; an index
            entry past the last vertex; or no index and a vertex count
            that is not a whole number of triangles.
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
    for slot in range(len(geometry.index)):
        if geometry.index[slot] >= count:
            raise Error("An index entry points past the last vertex")
    if not geometry.is_indexed() and count % 3 != 0:
        raise Error(
            "A geometry without an index must hold whole triangles to be"
            " exported"
        )
    return count


struct WorldMesh(Copyable, Movable):
    """One mesh carried into world space: what OBJ, STL and PLY write."""

    # The name of the mesh's node, three.js's `mesh.name`.
    var name: String
    # Three numbers a vertex, through the node's world matrix.
    var positions: List[Float32]
    # Three a vertex, through the normal matrix and made unit length,
    # when the geometry has normals.
    var normals: List[Float32]
    var with_normals: Bool
    # Two a vertex, as the geometry has them, when it has any.
    var uvs: List[Float32]
    var with_uvs: Bool
    # Three or four a vertex, linear, as the geometry has them.
    var colors: List[Float32]
    var color_size: Int
    # Three vertices a triangle: the index, or every vertex in order.
    var triangles: List[Int]

    def __init__(out self, var name: String):
        """Start a mesh with no vertices.

        Args:
            name: Its name.
        """
        self.name = name^
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.with_normals = False
        self.uvs = List[Float32]()
        self.with_uvs = False
        self.colors = List[Float32]()
        self.color_size = 0
        self.triangles = List[Int]()

    def vertex_count(self) -> Int:
        """Return how many vertices the mesh has."""
        return len(self.positions) // 3


def world_meshes(scene: Scene, assets: Assets) raises -> List[WorldMesh]:
    """Return every mesh of a scene in world space, in `scene.meshes`
    order.

    Args:
        scene: The scene. It must be current.
        assets: Where its geometries are.

    Returns:
        One `WorldMesh` a mesh.

    Raises:
        Error: If the scene is stale, a mesh names a node or a geometry
            that is not there, a geometry is refused by `check_geometry`,
            or a node that carries normals has a world matrix that
            flattens an axis, which leaves no normal matrix.
    """
    var found = List[WorldMesh]()
    for mesh in scene.meshes:
        ref geometry = assets.geometries.get(mesh.geometry)
        var count = check_geometry(geometry)
        var matrix = scene.world_matrix(mesh.node)
        var world = WorldMesh(scene.get(mesh.node).name)
        ref position = geometry.attribute_view(POSITION)
        for vertex in range(count):
            var point = matrix.transform_point(position.vector3(vertex))
            world.positions.append(point.x)
            world.positions.append(point.y)
            world.positions.append(point.z)
        if geometry.has_attribute(NORMAL):
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
            world.uvs = geometry.attribute_view(UV).data.copy()
            world.with_uvs = True
        if geometry.has_attribute(COLOR):
            ref color = geometry.attribute_view(COLOR)
            world.colors = color.data.copy()
            world.color_size = color.item_size
        if geometry.is_indexed():
            world.triangles = geometry.index.copy()
        else:
            for vertex in range(count):
                world.triangles.append(vertex)
        found.append(world^)
    return found^
