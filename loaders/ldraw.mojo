# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""LDraw models built into groups of meshes and lines, from three.js
`examples/jsm/loaders/LDrawLoader.js`: its `LDrawPartsGeometryCache`,
`smoothNormals`, `createObject` and `applyMaterialsToMesh`.

`parse_ldraw` builds a model as three.js's `LDrawLoader.parse` does, and
`read_ldraw` reads a file as its `load` does, with the default colors 16
and 24. Each part becomes a group, placed by its matrix. A primitive or a
subpart is merged into the part that places it: its faces and edges are
carried through the matrix, recolored and, for a mirrored placement,
wound the other way. Each group then holds up to three objects: a mesh of
its faces, its edges, and its conditional edges, each sorted by color and
split into groups by it. Color 16 in a part is the color it is placed
with, and 24 its edge color; a color no file defines is three.js's
magenta `__DEFAULT`.

`smooth_normals`, on by default, is three.js's: faces that meet at an edge
that is not a drawn line, at less than about 75 degrees, share their
normals. `LDrawNode` holds what three.js's objects hold. `load_ldraw` puts
a model into a scene: a group is a node, a mesh a `Mesh`, and edges and
conditional edges one `Line` a color group, the conditional ones
`conditional`.

**Where three.js's quirks are kept.** The colors of a file's own faces are
not counted when deciding whether to split normals at the ends of lines,
as three.js's loop over them never runs. A part built once is kept and
copied for each placement. A group's last run is as long as there is.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry, MaterialIndex
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.ldraw_parse import (
    LDrawFace,
    LDrawInfo,
    LDrawLoader,
    LDrawMaterial,
    LDrawSegment,
    LDrawSubobject,
    MAIN_COLOUR_CODE,
    MAIN_EDGE_COLOUR_CODE,
    Vec,
    is_part_type,
    is_primitive_type,
)
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    Material,
    MaterialId,
    STANDARD,
)
from math.quaternion import Quaternion
from objects.line import CONTROL0, CONTROL1, DIRECTION, Line, SEGMENTS
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.srgb import linear_to_srgb
from std.math import sqrt
from std.pathlib import Path

# A group that runs to the end, three.js's `Infinity`.
comptime TO_THE_END = -1
# A material slot three.js leaves null: a missing color's conditional edge.
comptime NO_MATERIAL = -2


struct LDrawGroup(Copyable, Movable):
    """A run of an object's vertices that wears one material."""

    var start: Int
    # How many vertices, or `TO_THE_END`.
    var count: Int
    var material_index: Int

    def __init__(out self, start: Int, count: Int, material_index: Int):
        """Hold a group.

        Args:
            start: Its first vertex.
            count: How many, or `TO_THE_END`.
            material_index: Which material.
        """
        self.start = start
        self.count = count
        self.material_index = material_index


struct LDrawNode(Copyable, Movable):
    """A group or an object three.js's LDraw loader makes."""

    # `Group`, `Mesh`, `LineSegments` or `ConditionalLineSegments`.
    var type: String
    var name: String
    var children: List[Int]
    var position: Vec
    # x, y, z, w.
    var quaternion: Vec
    var scale: Vec
    # three.js's `userData`.
    var category: Optional[String]
    var keywords: Optional[List[String]]
    var author: Optional[String]
    var part_type: Optional[String]
    var file_name: Optional[String]
    var color_code: Optional[String]
    var starting_building_step: Optional[Bool]
    var building_step: Int
    var is_group_data: Bool
    # An object's geometry.
    var positions: List[Float32]
    var normals: List[Float32]
    var control0: List[Float32]
    var control1: List[Float32]
    var direction: List[Float32]
    var groups: List[LDrawGroup]
    # Each material: an index into `LDrawLoader.all`, -1 for a color not
    # yet known, whose code `codes` holds, or `NO_MATERIAL`. `single` when three.js gave
    # the object one material rather than a list.
    var slots: List[Int]
    var codes: List[String]
    var single: Bool

    def __init__(out self, var type: String):
        """Make a node at the origin.

        Args:
            type: Its class.
        """
        self.type = type^
        self.name = String()
        self.children = List[Int]()
        self.position = Vec(0)
        self.quaternion = Vec(0, 0, 0, 1)
        self.scale = Vec(1, 1, 1, 0)
        self.category = None
        self.keywords = None
        self.author = None
        self.part_type = None
        self.file_name = None
        self.color_code = None
        self.starting_building_step = None
        self.building_step = 0
        self.is_group_data = False
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.control0 = List[Float32]()
        self.control1 = List[Float32]()
        self.direction = List[Float32]()
        self.groups = List[LDrawGroup]()
        self.slots = List[Int]()
        self.codes = List[String]()
        self.single = True

    def is_lines(self) -> Bool:
        """Return three.js's `isLineSegments`, which conditional edges are.

        Returns:
            Whether it is.
        """
        return (
            self.type == "LineSegments"
            or self.type == "ConditionalLineSegments"
        )


struct LDrawModel(Movable):
    """A built model: the loader, with every material, and the nodes."""

    var loader: LDrawLoader
    var nodes: List[LDrawNode]
    var root: Int
    # three.js's `numBuildingSteps`.
    var building_steps: Int
    # Each node's scene node, after `load_ldraw`.
    var scene_nodes: List[NodeId]

    def __init__(out self, var loader: LDrawLoader):
        """Start with no nodes.

        Args:
            loader: The loader.
        """
        self.loader = loader^
        self.nodes = List[LDrawNode]()
        self.root = -1
        self.building_steps = 1
        self.scene_nodes = List[NodeId]()


# --- geometry helpers ---------------------------------------------------------


def _apply(matrix: List[Float64], v: Vec) -> Vec:
    """Return three.js's `Vector3.applyMatrix4`."""
    var w = 1 / (
        matrix[3] * v[0] + matrix[7] * v[1] + matrix[11] * v[2] + matrix[15]
    )
    return Vec(
        (matrix[0] * v[0] + matrix[4] * v[1] + matrix[8] * v[2] + matrix[12])
        * w,
        (matrix[1] * v[0] + matrix[5] * v[1] + matrix[9] * v[2] + matrix[13])
        * w,
        (matrix[2] * v[0] + matrix[6] * v[1] + matrix[10] * v[2] + matrix[14])
        * w,
        0,
    )


def _determinant(te: List[Float64]) -> Float64:
    """Return three.js's `Matrix4.determinant`."""
    var n11 = te[0]
    var n12 = te[4]
    var n13 = te[8]
    var n14 = te[12]
    var n21 = te[1]
    var n22 = te[5]
    var n23 = te[9]
    var n24 = te[13]
    var n31 = te[2]
    var n32 = te[6]
    var n33 = te[10]
    var n34 = te[14]
    var n41 = te[3]
    var n42 = te[7]
    var n43 = te[11]
    var n44 = te[15]
    return (
        n41
        * (
            +n14 * n23 * n32
            - n13 * n24 * n32
            - n14 * n22 * n33
            + n12 * n24 * n33
            + n13 * n22 * n34
            - n12 * n23 * n34
        )
        + n42
        * (
            +n11 * n23 * n34
            - n11 * n24 * n33
            + n14 * n21 * n33
            - n13 * n21 * n34
            + n13 * n24 * n31
            - n14 * n23 * n31
        )
        + n43
        * (
            +n11 * n24 * n32
            - n11 * n22 * n34
            - n14 * n21 * n32
            + n12 * n21 * n34
            + n14 * n22 * n31
            - n12 * n24 * n31
        )
        + n44
        * (
            -n13 * n22 * n31
            - n11 * n23 * n32
            + n11 * n22 * n33
            + n13 * n21 * n32
            - n12 * n21 * n33
            + n12 * n23 * n31
        )
    )


def _length(x: Float64, y: Float64, z: Float64) -> Float64:
    return sqrt(x * x + y * y + z * z)


def _decompose(te: List[Float64], mut node: LDrawNode):
    """Set a node's place from a matrix, three.js's `Matrix4.decompose`."""
    var sx = _length(te[0], te[1], te[2])
    var sy = _length(te[4], te[5], te[6])
    var sz = _length(te[8], te[9], te[10])
    if _determinant(te) < 0:
        sx = -sx
    node.position = Vec(te[12], te[13], te[14], 0)
    var m11 = te[0] / sx
    var m21 = te[1] / sx
    var m31 = te[2] / sx
    var m12 = te[4] / sy
    var m22 = te[5] / sy
    var m32 = te[6] / sy
    var m13 = te[8] / sz
    var m23 = te[9] / sz
    var m33 = te[10] / sz
    var trace = m11 + m22 + m33
    var q: Vec
    if trace > 0:
        var s = 0.5 / sqrt(trace + 1.0)
        q = Vec((m32 - m23) * s, (m13 - m31) * s, (m21 - m12) * s, 0.25 / s)
    elif m11 > m22 and m11 > m33:
        var s = 2.0 * sqrt(1.0 + m11 - m22 - m33)
        q = Vec(0.25 * s, (m12 + m21) / s, (m13 + m31) / s, (m32 - m23) / s)
    elif m22 > m33:
        var s = 2.0 * sqrt(1.0 + m22 - m11 - m33)
        q = Vec((m12 + m21) / s, 0.25 * s, (m23 + m32) / s, (m13 - m31) / s)
    else:
        var s = 2.0 * sqrt(1.0 + m33 - m11 - m22)
        q = Vec((m13 + m31) / s, (m23 + m32) / s, 0.25 * s, (m21 - m12) / s)
    node.quaternion = q
    node.scale = Vec(sx, sy, sz, 0)


def _unit(v: Vec) -> Vec:
    """Return three.js's `normalize`: divided by its length, or by one."""
    var length = _length(v[0], v[1], v[2])
    return v * (1 / (length if length != 0 and length == length else 1))


def _cross(a: Vec, b: Vec) -> Vec:
    return Vec(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
        0,
    )


def _dot(a: Vec, b: Vec) -> Float64:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _face_normal(vertices: List[Vec]) -> Vec:
    """Port three.js's face normal: the cross product of the first two edges,
    normalized."""
    return _unit(_cross(vertices[1] - vertices[0], vertices[2] - vertices[1]))


# --- smooth normals -------------------------------------------------------------


def _int32(v: Float64) -> Int:
    """Return JavaScript's `~~v`: truncated, as a 32-bit integer."""
    if not (v == v) or v > 1e300 or v < -1e300:
        return 0
    var t = Int(v)
    var m = t % 4294967296
    return m - 4294967296 if m >= 2147483648 else m


comptime _HASH_MULTIPLIER = (1 + 1e-10) * 1e2


def _hash_vertex(v: Vec) -> String:
    return (
        String(_int32(v[0] * _HASH_MULTIPLIER))
        + ","
        + String(_int32(v[1] * _HASH_MULTIPLIER))
        + ","
        + String(_int32(v[2] * _HASH_MULTIPLIER))
    )


def _hash_edge(a: Vec, b: Vec) -> String:
    return _hash_vertex(a) + "_" + _hash_vertex(b)


def _ray(a: Vec, b: Vec) -> Tuple[Vec, Vec]:
    """Return three.js's `toNormalizedRay`: the line's direction, and its
    point nearest the origin."""
    var direction = _unit(b - a)
    var scalar = _dot(a, direction)
    return (a + direction * (-scalar), direction)


struct _Ordered(Movable):
    """A JavaScript object used as a map from string keys: insertion order,
    a key set again kept in its place, a deleted key gone from the order."""

    var keys: List[String]
    var values: List[Int]
    var alive: List[Bool]
    var index: Dict[String, Int]
    var first: Int

    def __init__(out self):
        self.keys = List[String]()
        self.values = List[Int]()
        self.alive = List[Bool]()
        self.index = Dict[String, Int]()
        self.first = 0

    def set(mut self, key: String, value: Int):
        var at = self.index.get(key, -1)
        if at >= 0:
            self.values[at] = value
            return
        self.index[key] = len(self.keys)
        self.keys.append(key)
        self.values.append(value)
        self.alive.append(True)

    def get(self, key: String) -> Int:
        """Return the value, or -1."""
        var at = self.index.get(key, -1)
        return self.values[at] if at >= 0 else -1

    def delete(mut self, key: String):
        var at = self.index.get(key, -1)
        if at >= 0:
            self.alive[at] = False
            _ = self.index.pop(key, -1)

    def front(mut self) -> Int:
        """Return the value of the first key left, or -1."""
        while self.first < len(self.keys) and not self.alive[self.first]:
            self.first += 1
        if self.first < len(self.keys):
            return self.values[self.first]
        return -1


def smooth_normals(
    mut faces: List[LDrawFace],
    lines: List[LDrawSegment],
    check_sub_segments: Bool,
) -> List[Vec]:
    """Share normals between faces, three.js's `smoothNormals`: across an
    edge that no line marks as hard, where the faces are within about 75
    degrees of each other. With `check_sub_segments`, an edge that lies
    within a line is hard too.

    Each face's `normals` become indices into the returned list, which
    holds each shared normal, normalized. As in three.js, merging two
    shared normals adds one into the other and points the first at it.

    Args:
        faces: The faces, with their face normals.
        lines: The edges.
        check_sub_segments: Whether an edge along a line is hard.

    Returns:
        The shared normals.
    """
    var hard = Dict[String, Bool]()
    var ray_index = Dict[String, Int]()
    var ray_lines = List[Tuple[Vec, Vec]]()
    var ray_distances = List[List[Float64]]()
    for line in lines:
        var v0 = line.vertices[0]
        var v1 = line.vertices[1]
        hard[_hash_edge(v0, v1)] = True
        hard[_hash_edge(v1, v0)] = True
        if check_sub_segments:
            var ray = _ray(v0, v1)
            var rh1 = _hash_edge(ray[0], ray[1])
            if rh1 not in ray_index:
                var back = _ray(v1, v0)
                var rh2 = _hash_edge(back[0], back[1])
                ray_index[rh1] = len(ray_lines)
                ray_index[rh2] = len(ray_lines)
                # three.js keeps the second ray: `toNormalizedRay` writes
                # into the one object.
                ray_lines.append(back)
                ray_distances.append(List[Float64]())
            var at = ray_index.get(rh1, 0)
            var direction = ray_lines[at][1]
            var d0 = _dot(direction, v0)
            var d1 = _dot(direction, v1)
            if d0 > d1:
                var t = d0
                d0 = d1
                d1 = t
            ray_distances[at].append(d0)
            ray_distances[at].append(d1)
    # The half edges not on a hard edge: which face, which corner.
    var half = _Ordered()
    var half_faces = List[Int]()
    var half_corners = List[Int]()
    for f in range(len(faces)):  # pragma: no branch
        var count = len(faces[f].vertices)
        for i in range(count):  # pragma: no branch
            var v0 = faces[f].vertices[i]
            var v1 = faces[f].vertices[(i + 1) % count]
            var hash = _hash_edge(v0, v1)
            if hash in hard:
                continue
            if check_sub_segments:
                var ray = _ray(v0, v1)
                var key = _hash_edge(ray[0], ray[1])
                if key in ray_index:
                    var at = ray_index.get(key, 0)
                    var direction = ray_lines[at][1]
                    var d0 = _dot(direction, v0)
                    var d1 = _dot(direction, v1)
                    if d0 > d1:
                        var t = d0
                        d0 = d1
                        d1 = t
                    var found = False
                    ref distances = ray_distances[at]
                    for k in range(0, len(distances), 2):  # pragma: no branch
                        if d0 >= distances[k] and d1 <= distances[k + 1]:
                            found = True
                            break
                    if found:
                        continue
            half_faces.append(f)
            half_corners.append(i)
            half.set(hash, len(half_faces) - 1)
    # Shared normals: each face corner holds a holder, and a holder points
    # at a vector, as three.js's `{ norm }` objects do.
    var holders = List[Int]()
    var vectors = List[Vec]()
    var made = List[Int]()
    while True:
        var start = half.front()
        if start < 0:
            break
        var queue: List[Int] = [start]
        while len(queue) > 0:
            var f = half_faces[queue.pop()]
            var count = len(faces[f].vertices)
            var face_normal = faces[f].face_normal
            for i in range(count):  # pragma: no branch
                var next = (i + 1) % count
                var v0 = faces[f].vertices[i]
                var v1 = faces[f].vertices[next]
                half.delete(_hash_edge(v0, v1))
                var reverse = _hash_edge(v1, v0)
                var other = half.get(reverse)
                if other < 0:
                    continue
                var g = half_faces[other]
                var other_index = half_corners[other]
                var other_count = len(faces[g].normals)
                var other_normal = faces[g].face_normal
                if abs(_dot(other_normal, face_normal)) < 0.25:
                    continue
                queue.append(other)
                half.delete(reverse)
                var other_next = (other_index + 1) % other_count
                _join(
                    faces,
                    holders,
                    vectors,
                    made,
                    f,
                    i,
                    g,
                    other_next,
                    face_normal,
                    other_normal,
                )
                _join(
                    faces,
                    holders,
                    vectors,
                    made,
                    f,
                    next,
                    g,
                    other_index,
                    face_normal,
                    other_normal,
                )
    for v in made:  # pragma: no branch
        vectors[v] = _unit(vectors[v])
    var out = List[Vec]()
    for h in holders:  # pragma: no branch
        out.append(vectors[h])
    return out^


def _join(
    mut faces: List[LDrawFace],
    mut holders: List[Int],
    mut vectors: List[Vec],
    mut made: List[Int],
    f: Int,
    i: Int,
    g: Int,
    j: Int,
    face_normal: Vec,
    other_normal: Vec,
):
    """One corner of three.js's merge: the corner `i` of face `f` and the
    corner `j` of face `g` come to share a normal."""
    var mine = faces[f].normals[i]
    var theirs = faces[g].normals[j]
    if mine >= 0 and theirs >= 0 and mine != theirs:
        vectors[holders[theirs]] = (
            vectors[holders[theirs]] + vectors[holders[mine]]
        )
        holders[mine] = holders[theirs]
    var shared = mine if mine >= 0 else theirs
    if shared < 0:
        vectors.append(Vec(0))
        made.append(len(vectors) - 1)
        holders.append(len(vectors) - 1)
        shared = len(holders) - 1
    if mine < 0:
        faces[f].normals[i] = shared
        vectors[holders[shared]] = vectors[holders[shared]] + face_normal
    if theirs < 0:
        faces[g].normals[j] = shared
        vectors[holders[shared]] = vectors[holders[shared]] + other_normal


# --- building ------------------------------------------------------------------


def _color_order(codes: List[String]) -> List[Int]:
    """Return a stable order of items by their color codes, compared as
    strings: three.js's `sortByMaterial` under `Array.prototype.sort`."""
    var order = List[Int]()
    for i in range(len(codes)):  # pragma: no branch
        var j = len(order)
        order.append(i)
        while j > 0 and codes[order[j - 1]] > codes[i]:
            order[j] = order[j - 1]
            j -= 1
        order[j] = i
    return order^


def _from_code(
    code: String, parent: String, info: LDrawInfo, for_edge: Bool
) -> Int:
    """Port three.js's `getMaterialFromCode`: the main color, or the main edge
    color for an edge, stands for the parent's; then the file's color."""
    var own = code
    if (not for_edge and code == MAIN_COLOUR_CODE) or (
        for_edge and code == MAIN_EDGE_COLOUR_CODE
    ):
        own = parent
    return info.local(own)


def _find(codes: List[String], ids: List[Int], code: String) -> Int:
    for k in range(len(codes)):  # pragma: no branch
        if codes[k] == code:
            return ids[k]
    return -1


def _has(codes: List[String], code: String) -> Bool:
    for c in codes:
        if c == code:
            return True
    return False


struct LDrawBuilder(Movable):
    """Port three.js's `LDrawPartsGeometryCache`: the loader, the nodes built,
    and the parts built once and copied."""

    var model: LDrawModel
    var cache_names: List[String]
    var cache_roots: List[Int]

    def __init__(out self, var loader: LDrawLoader):
        """Start building.

        Args:
            loader: The loader, with its colors.
        """
        self.model = LDrawModel(loader^)
        self.cache_names = List[String]()
        self.cache_roots = List[Int]()

    def add(mut self, var node: LDrawNode) -> Int:
        """Keep a node.

        Args:
            node: The node.

        Returns:
            Its index.
        """
        self.model.nodes.append(node^)
        return len(self.model.nodes) - 1

    def clone(mut self, root: Int) -> Int:
        """Return a copy of a node and all under it, three.js's `clone`.

        Args:
            root: The node.

        Returns:
            The copy.
        """
        # Copied parents first; each copy's children are re-pointed at the
        # copies of theirs.
        var order = self.walk(root)
        var first = len(self.model.nodes)
        for n in order:  # pragma: no branch
            var copy = self.model.nodes[n].copy()
            self.model.nodes.append(copy^)
        for k in range(len(order)):  # pragma: no branch
            var at = first + k
            for c in range(len(self.model.nodes[at].children)):
                var old = self.model.nodes[at].children[c]
                for j in range(len(order)):  # pragma: no branch
                    if order[j] == old:
                        self.model.nodes[at].children[c] = first + j
        return first

    def walk(self, root: Int) -> List[Int]:
        """Return a node and all under it, parents first, three.js's
        `traverse`.

        Args:
            root: The node.

        Returns:
            The nodes.
        """
        var out = List[Int]()
        var stack: List[Int] = [root]
        while len(stack) > 0:
            var n = stack.pop()
            out.append(n)
            ref children = self.model.nodes[n].children
            for k in range(len(children) - 1, -1, -1):
                stack.append(children[k])
        return out^

    def apply_materials(
        mut self,
        root: Int,
        parent: String,
        codes: List[String],
        ids: List[Int],
        final: Bool,
    ) raises:
        """Port three.js's `applyMaterialsToMesh`: each color not yet known, of
        each object under `root`, looked up in `codes`, the main color
        standing for `parent`.

        Args:
            root: The group.
            parent: The color it is placed with.
            codes: The colors the placing file knows.
            ids: Their materials.
            final: Whether this is the last pass, which asks the library
                and falls back to the missing color.

        Raises:
            Error: Never, for the directives of direct colors.
        """
        for n in self.walk(root):  # pragma: no branch
            if self.model.nodes[n].type == "Group":
                continue
            for k in range(len(self.model.nodes[n].slots)):  # pragma: no branch
                if self.model.nodes[n].slots[k] != -1:
                    continue
                var code = self.model.nodes[n].codes[k]
                if (
                    parent == MAIN_COLOUR_CODE
                    and not _has(codes, code)
                    and not final
                ):
                    continue
                var lines = self.model.nodes[n].is_lines()
                if (not lines and code == MAIN_COLOUR_CODE) or (
                    lines and code == MAIN_EDGE_COLOUR_CODE
                ):
                    code = parent
                var material = _find(codes, ids, code)
                if material < 0:
                    if not final:
                        self.model.nodes[n].codes[k] = code
                        continue
                    material = self.model.loader.get_material(code)
                    if material < 0:
                        material = self.model.loader.missing
                if lines:
                    material = self.model.loader.all[material].edge
                    if self.model.nodes[n].type == "ConditionalLineSegments":
                        material = self.model.loader.all[material].conditional
                self.model.nodes[n].slots[k] = (
                    material if material >= 0 else NO_MATERIAL
                )

    def process(
        mut self,
        mut info: LDrawInfo,
        placed: Optional[LDrawSubobject],
        mut face_codes: List[String],
    ) raises -> Int:
        """Port three.js's `processInfoSubobjects`: build each part a file
        places, merge each primitive it places, and make its group.

        Args:
            info: The file; primitives' faces and edges are added to it.
            placed: How the file itself is placed, when it is a primitive.
            face_codes: The colors of merged faces, three.js's
                `faceMaterials`.

        Returns:
            The group.

        Raises:
            Error: If a file placed is not found, or is refused.
        """
        var built = List[Int]()
        var merged = List[LDrawInfo]()
        var primitive_at = List[Bool]()
        for k in range(len(info.subobjects)):
            var name = info.subobjects[k].file_name
            self.model.loader.ensure_loaded(name)
            var type = self.model.loader.cache[
                self.model.loader.cached(name)
            ].type
            if not is_primitive_type(type):
                # three.js warns and leaves out a part that fails.
                var group: Int
                try:
                    group = self.load_model(name)
                except:
                    group = -1
                built.append(group)
                merged.append(LDrawInfo())
                primitive_at.append(False)
            else:
                var primitive = self.model.loader.data(name)
                var group = self.process(
                    primitive, info.subobjects[k].copy(), face_codes
                )
                built.append(group)
                merged.append(primitive^)
                primitive_at.append(True)
        var group = LDrawNode("Group")
        group.is_group_data = True
        group.category = info.category
        group.keywords = info.keywords.copy()
        group.author = info.author
        group.part_type = info.type
        group.file_name = info.file_name
        var id = self.add(group^)
        for k in range(len(info.subobjects)):
            var sub = info.subobjects[k].copy()
            if built[k] < 0:
                continue
            if not primitive_at[k]:
                var g = built[k]
                _decompose(sub.matrix, self.model.nodes[g])
                self.model.nodes[
                    g
                ].starting_building_step = sub.starting_building_step
                self.model.nodes[g].name = sub.file_name
                self.apply_materials(
                    g,
                    sub.color_code,
                    info.material_codes,
                    info.material_ids,
                    False,
                )
                self.model.nodes[g].color_code = sub.color_code
                self.model.nodes[id].children.append(g)
                continue
            if len(self.model.nodes[built[k]].children) > 0:
                self.model.nodes[id].children.append(built[k])
            var inverted = _determinant(sub.matrix) < 0
            var color = sub.color_code
            var line_color = (
                String(MAIN_EDGE_COLOUR_CODE) if color
                == MAIN_COLOUR_CODE else color
            )
            for segment in merged[k].line_segments:
                var line = segment.copy()
                for v in range(2):  # pragma: no branch
                    line.vertices[v] = _apply(sub.matrix, line.vertices[v])
                if line.color_code == MAIN_EDGE_COLOUR_CODE:
                    line.color_code = line_color
                if line.material < 0:
                    line.material = _from_code(
                        line.color_code, line.color_code, info, True
                    )
                info.line_segments.append(line^)
            for segment in merged[k].conditional_segments:
                var line = segment.copy()
                for v in range(2):  # pragma: no branch
                    line.vertices[v] = _apply(sub.matrix, line.vertices[v])
                    line.controls[v] = _apply(sub.matrix, line.controls[v])
                if line.color_code == MAIN_EDGE_COLOUR_CODE:
                    line.color_code = line_color
                if line.material < 0:
                    line.material = _from_code(
                        line.color_code, line.color_code, info, True
                    )
                info.conditional_segments.append(line^)
            for f in merged[k].faces:  # pragma: no branch
                var face = f.copy()
                for v in range(len(face.vertices)):  # pragma: no branch
                    face.vertices[v] = _apply(sub.matrix, face.vertices[v])
                if face.color_code == MAIN_COLOUR_CODE:
                    face.color_code = color
                if face.material < 0:
                    face.material = _from_code(
                        face.color_code, color, info, False
                    )
                if not _has(face_codes, face.color_code):
                    face_codes.append(face.color_code)
                if inverted != sub.inverted:
                    face.vertices.reverse()
                info.faces.append(face^)
            info.total_faces += merged[k].total_faces
        if Bool(placed):
            ref p = placed.value()
            self.apply_materials(
                id, p.color_code, info.material_codes, info.material_ids, False
            )
            self.model.nodes[id].color_code = p.color_code
        return id

    def process_into_mesh(mut self, mut info: LDrawInfo) raises -> Int:
        """Port three.js's `processIntoMesh`: a file's group, with its mesh, its
        edges and its conditional edges.

        Args:
            info: The file.

        Returns:
            The group.

        Raises:
            Error: If a file placed is not found, or is refused.
        """
        var face_codes = List[String]()
        var group = self.process(info, None, face_codes)
        var normals = List[Vec]()
        if self.model.loader.smooth_normals:
            for k in range(len(info.faces)):  # pragma: no branch
                info.faces[k].face_normal = _face_normal(info.faces[k].vertices)
                info.faces[k].has_face_normal = True
            normals = smooth_normals(
                info.faces, info.line_segments, len(face_codes) > 1
            )
        if len(info.faces) > 0:
            var mesh = self.faces_object(info.faces, info.total_faces, normals)
            var made = self.add(mesh^)
            self.model.nodes[group].children.append(made)
        if len(info.line_segments) > 0:
            var lines = self.lines_object(info.line_segments, False)
            var made = self.add(lines^)
            self.model.nodes[group].children.append(made)
        if len(info.conditional_segments) > 0:
            var lines = self.lines_object(info.conditional_segments, True)
            var made = self.add(lines^)
            self.model.nodes[group].children.append(made)
        return group

    def load_model(mut self, name: String) raises -> Int:
        """Port three.js's `loadModel`: a copy of a part, built once.

        Args:
            name: The file.

        Returns:
            The copy.

        Raises:
            Error: If the file or one it places is not found, or refused.
        """
        var key = name.lower()
        for k in range(len(self.cache_names)):
            if self.cache_names[k] == key:
                return self.clone(self.cache_roots[k])
        self.model.loader.ensure_loaded(name)
        var info = self.model.loader.data(name)
        var group = self.process_into_mesh(info)
        if is_part_type(info.type):
            self.cache_names.append(key)
            self.cache_roots.append(group)
        return self.clone(group)

    def _slot(
        self,
        mut node: LDrawNode,
        material: Int,
        code: String,
        lines: Bool,
        conditional: Bool,
    ):
        """Add a material to an object: the element's own, its edge, or its
        conditional edge, or its code when it has none yet."""
        if material >= 0:
            var m = material
            if lines:
                m = self.model.loader.all[m].edge
                if conditional:
                    m = self.model.loader.all[m].conditional
            node.slots.append(m)
            node.codes.append(code)
        else:
            node.slots.append(-1)
            node.codes.append(code)

    def faces_object(
        self, mut faces: List[LDrawFace], total: Int, normals: List[Vec]
    ) -> LDrawNode:
        """Port three.js's `createObject` for faces: a mesh, sorted by color,
        with a group a color."""
        var codes = List[String]()
        for f in faces:  # pragma: no branch
            codes.append(f.color_code)
        var order = _color_order(codes)
        var node = LDrawNode("Mesh")
        node.positions = List[Float32](length=3 * total * 3, fill=0)
        node.normals = List[Float32](length=3 * total * 3, fill=0)
        var previous = String()
        var has_previous = False
        var start = 0
        var count = 0
        var offset = 0
        for k in order:  # pragma: no branch
            ref face = faces[k]
            var corners: List[Int] = [0, 1, 2]
            if len(face.vertices) == 4:
                corners = [0, 1, 2, 0, 2, 3]
            if not face.has_face_normal:
                face.face_normal = _face_normal(face.vertices)
                face.has_face_normal = True
            for j in range(len(corners)):  # pragma: no branch
                var v = face.vertices[corners[j]]
                var h = face.normals[corners[j]]
                var n = face.face_normal if h < 0 else normals[h]
                for c in range(3):  # pragma: no branch
                    node.positions[offset + j * 3 + c] = Float32(v[c])
                    node.normals[offset + j * 3 + c] = Float32(n[c])
            if not has_previous or previous != face.color_code:
                if has_previous:
                    node.groups.append(
                        LDrawGroup(start, count, len(node.slots) - 1)
                    )
                self._slot(node, face.material, face.color_code, False, False)
                previous = face.color_code
                has_previous = True
                start = offset // 3
                count = len(corners)
            else:
                count += len(corners)
            offset += 3 * len(corners)
        # There is a face, so the last group has a vertex; three.js asks.
        node.groups.append(LDrawGroup(start, TO_THE_END, len(node.slots) - 1))
        node.single = len(node.slots) == 1
        return node^

    def lines_object(
        self, mut segments: List[LDrawSegment], conditional: Bool
    ) -> LDrawNode:
        """Port three.js's `createObject` for edges or conditional edges."""
        var codes = List[String]()
        for s in segments:  # pragma: no branch
            codes.append(s.color_code)
        var order = _color_order(codes)
        var node = LDrawNode(
            "ConditionalLineSegments" if conditional else "LineSegments"
        )
        var previous = String()
        var has_previous = False
        var start = 0
        var count = 0
        for k in order:  # pragma: no branch
            ref segment = segments[k]
            for v in range(2):  # pragma: no branch
                for c in range(3):  # pragma: no branch
                    node.positions.append(Float32(segment.vertices[v][c]))
            if conditional:
                var c0 = segment.controls[0]
                var c1 = segment.controls[1]
                var d = segment.vertices[1] - segment.vertices[0]
                for _ in range(2):  # pragma: no branch
                    for c in range(3):  # pragma: no branch
                        node.control0.append(Float32(c0[c]))
                        node.control1.append(Float32(c1[c]))
                        node.direction.append(Float32(d[c]))
            if not has_previous or previous != segment.color_code:
                if has_previous:
                    node.groups.append(
                        LDrawGroup(start, count, len(node.slots) - 1)
                    )
                self._slot(
                    node,
                    segment.material,
                    segment.color_code,
                    True,
                    conditional,
                )
                previous = segment.color_code
                has_previous = True
                start = (len(node.positions) - 6) // 3
                count = 2
            else:
                count += 2
        # There is a segment, so the last group has a vertex; three.js asks.
        node.groups.append(LDrawGroup(start, TO_THE_END, len(node.slots) - 1))
        node.single = len(node.slots) == 1
        return node^

    def building_steps(mut self, root: Int):
        """Port three.js's `computeBuildingSteps`: each group's step, counting
        the groups that start one, parents first.

        Args:
            root: The model.
        """
        var step = 0
        for n in self.walk(root):  # pragma: no branch
            if self.model.nodes[n].type != "Group":
                continue
            var starts = self.model.nodes[n].starting_building_step
            if Bool(starts) and starts.value():
                step += 1
            self.model.nodes[n].building_step = step
        self.model.building_steps = step + 1

    def take(deinit self) -> LDrawModel:
        return self.model^


def _finish(
    var builder: LDrawBuilder, root: Int, file_name: String
) raises -> LDrawModel:
    """Port three.js's end of `parse` and `load`: the library's colors for what
    is left, and the building steps."""
    var codes = builder.model.loader.library_codes.copy()
    var ids = builder.model.loader.library_ids.copy()
    builder.apply_materials(root, MAIN_COLOUR_CODE, codes, ids, True)
    builder.building_steps(root)
    builder.model.nodes[root].file_name = file_name
    builder.model.root = root
    return builder^.take()


def parse_ldraw(text: String, var loader: LDrawLoader) raises -> LDrawModel:
    """Build a model from LDraw text, three.js's `LDrawLoader.parse`: with
    only the colors the loader and the text define.

    Args:
        text: The model.
        loader: The loader: its parts library path, file map and colors.

    Returns:
        The model.

    Raises:
        Error: For a file placed that is not found, and for what
            `LDrawLoader.parse_text` refuses.
    """
    var builder = LDrawBuilder(loader^)
    var info = builder.model.loader.parse_text(text, None)
    var root = builder.process_into_mesh(info)
    return _finish(builder^, root, "")


def read_ldraw(path: String, var loader: LDrawLoader) raises -> LDrawModel:
    """Read an LDraw file, three.js's `LDrawLoader.load`: the default
    colors 16 and 24 first.

    Args:
        path: The file.
        loader: The loader.

    Returns:
        The model.

    Raises:
        Error: If the file cannot be read, and for what `parse_ldraw`
            refuses.
    """
    var builder = LDrawBuilder(loader^)
    builder.model.loader.add_default_materials()
    var text = Path(path).read_text()
    var info = builder.model.loader.parse_text(text, None)
    var root = builder.process_into_mesh(info)
    return _finish(builder^, root, path)


# --- into a scene ------------------------------------------------------------


def _authored(color: Vec) -> Color:
    """Return linear light as the sRGB bytes a material holds."""
    return FloatColor(
        linear_to_srgb(Float32(color[0])),
        linear_to_srgb(Float32(color[1])),
        linear_to_srgb(Float32(color[2])),
        1,
    ).quantize()


def _material(m: LDrawMaterial) raises -> Material:
    """Return the `Material` of an LDraw material: a standard surface, or a
    basic line."""
    if m.type == "MeshStandardMaterial":
        var out = Material(
            _authored(m.color),
            kind=STANDARD,
            opacity=Float32(m.opacity),
            transparent=m.transparent,
            emissive=_authored(m.emissive),
            roughness=Float32(m.roughness),
            metalness=Float32(m.metalness),
        )
        out.depth_write = m.depth_write
        out.premultiplied_alpha = m.premultiplied_alpha
        out.polygon_offset = m.polygon_offset
        out.polygon_offset_factor = Float32(m.polygon_offset_factor)
        return out^
    var out = Material(
        _authored(m.color),
        kind=BASIC,
        opacity=Float32(m.opacity),
        transparent=m.transparent,
    )
    out.depth_write = m.depth_write
    return out^


def _part(values: List[Float32], start: Int, end: Int) -> List[Float32]:
    var out = List[Float32](capacity=end - start)
    for k in range(start, end):  # pragma: no branch
        out.append(values[k])
    return out^


def load_ldraw(
    mut model: LDrawModel,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises:
    """Put a built model into a scene: each group a node, each mesh a
    `Mesh` with its material groups, and each color group of edges or
    conditional edges a `Line` of `SEGMENTS`, `conditional` for the
    latter, as a line here draws one material. A group with no material,
    which three.js's renderer skips, is left out.

    Args:
        model: The model; `scene_nodes` is set, one for each node.
        scene: Where the nodes and objects go.
        assets: Where the geometries and materials go.
        parent: The node the model goes under.

    Raises:
        Error: If the scene refuses a node or an object, or cannot be
            updated.
    """
    var ids = List[Int](length=len(model.loader.all), fill=-1)
    model.scene_nodes = List[NodeId](
        length=len(model.nodes), fill=NodeId(NO_PARENT.value)
    )
    var stack: List[Int] = [model.root]
    var above: List[NodeId] = [parent]
    while len(stack) > 0:
        var n = stack.pop()
        var up = above.pop()
        ref node = model.nodes[n]
        var holder = Object3D()
        holder.name = node.name
        holder.set_position(
            Float32(node.position[0]),
            Float32(node.position[1]),
            Float32(node.position[2]),
        )
        holder.set_quaternion(
            Quaternion(
                Float32(node.quaternion[0]),
                Float32(node.quaternion[1]),
                Float32(node.quaternion[2]),
                Float32(node.quaternion[3]),
            )
        )
        holder.set_scale(
            Float32(node.scale[0]),
            Float32(node.scale[1]),
            Float32(node.scale[2]),
        )
        var id: NodeId
        if up == NO_PARENT:
            id = scene.add(holder^)
        else:
            id = scene.attach(holder^, up)
        model.scene_nodes[n] = id
        for k in range(len(node.children) - 1, -1, -1):
            stack.append(node.children[k])
            above.append(id)
        if node.type == "Group":
            continue
        var worn = List[MaterialId]()
        for s in node.slots:  # pragma: no branch
            if s < 0:
                worn.append(MaterialId(-1))
                continue
            if ids[s] < 0:
                ids[s] = assets.materials.add(
                    _material(model.loader.all[s])
                ).value
            worn.append(MaterialId(ids[s]))
        var count = len(node.positions) // 3
        if node.type == "Mesh":
            var geometry = BufferGeometry()
            geometry.set_attribute(
                String(POSITION), BufferAttribute(node.positions.copy(), 3)
            )
            geometry.set_attribute(
                String(NORMAL), BufferAttribute(node.normals.copy(), 3)
            )
            for g in node.groups:  # pragma: no branch
                var end = count if g.count == TO_THE_END else g.start + g.count
                geometry.add_group(
                    g.start, end - g.start, MaterialIndex(g.material_index)
                )
            var shape = assets.geometries.add(geometry^)
            if node.single:
                scene.add_mesh(Mesh(shape, worn[0], id))
            else:
                scene.add_mesh(Mesh(shape, worn, id))
            continue
        var conditional = node.type == "ConditionalLineSegments"
        for g in node.groups:  # pragma: no branch
            var material = worn[g.material_index]
            if material.value < 0:
                continue
            var end = count if g.count == TO_THE_END else g.start + g.count
            var geometry = BufferGeometry()
            geometry.set_attribute(
                String(POSITION),
                BufferAttribute(_part(node.positions, g.start * 3, end * 3), 3),
            )
            if conditional:
                geometry.set_attribute(
                    String(CONTROL0),
                    BufferAttribute(
                        _part(node.control0, g.start * 3, end * 3), 3
                    ),
                )
                geometry.set_attribute(
                    String(CONTROL1),
                    BufferAttribute(
                        _part(node.control1, g.start * 3, end * 3), 3
                    ),
                )
                geometry.set_attribute(
                    String(DIRECTION),
                    BufferAttribute(
                        _part(node.direction, g.start * 3, end * 3), 3
                    ),
                )
            scene.add_line(
                Line(
                    assets.geometries.add(geometry^),
                    material,
                    id,
                    mode=SEGMENTS,
                    conditional=conditional,
                )
            )
    scene.update()
