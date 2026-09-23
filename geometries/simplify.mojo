# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Take vertices away from a surface one edge at a time, from three.js
`examples/jsm/modifiers/SimplifyModifier.js`.

This is Stan Melax's progressive mesh reduction, as three.js has it. Each
vertex has a cost: how far it is to a neighbor, times how much the
surface bends there. The cost of a vertex is the average over its
neighbors, and it remembers the cheapest neighbor. Each step takes the
vertex of least cost, moves it onto that neighbor, drops the triangles
on the edge between them and joins the rest to the neighbor. Then the
costs round about are worked out again.

## As three.js does it

The geometry is welded first with `merge_vertices`, on `position`, `uv`,
`normal`, `tangent` and `color`, and every other attribute and the morph
targets are dropped. When a vertex is moved onto its neighbor, the
neighbor's normal and tangent become the unit sum of the two. Its
texture coordinate and color stay as they were.

Every search is a walk down a list, as in three.js, so the cost of a step
grows with the size of the surface. Ties go to the vertex met first, and
the lists keep three.js's order, so the result is three.js's, vertex for
vertex.

A vertex that no triangle uses costs minus a hundredth, and is taken
first. Removing one takes a step, as in three.js.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    COLOR,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
)
from geometries.utils import merge_vertices
from std.math import sqrt

# The cost of a vertex that has no neighbors: three.js's `-0.01`.
comptime LONE_COST = -0.01
# The cost a vertex starts at before its neighbors are measured.
comptime START_COST = 100000.0


struct _Vertex(Copyable, Movable):
    """One vertex of the surface as the reduction sees it: three.js's
    `Vertex`."""

    var position: SIMD[DType.float64, 4]
    var uv: SIMD[DType.float64, 2]
    var normal: SIMD[DType.float64, 4]
    var tangent: SIMD[DType.float64, 4]
    var color: SIMD[DType.float64, 4]
    var faces: List[Int]
    var neighbors: List[Int]
    var collapse_cost: Float64
    # The neighbor to move onto, or -1 for none.
    var collapse_neighbor: Int
    var min_cost: Float64
    var total_cost: Float64
    var cost_count: Int
    var id: Int

    def __init__(out self, position: SIMD[DType.float64, 4]):
        """Create a vertex at `position` with no faces yet.

        Args:
            position: Where it is, fourth number unused.
        """
        self.position = position
        self.uv = SIMD[DType.float64, 2](0)
        self.normal = SIMD[DType.float64, 4](0)
        self.tangent = SIMD[DType.float64, 4](0)
        self.color = SIMD[DType.float64, 4](0)
        self.faces = List[Int]()
        self.neighbors = List[Int]()
        self.collapse_cost = 0
        self.collapse_neighbor = -1
        self.min_cost = 0
        self.total_cost = 0
        self.cost_count = 0
        self.id = -1


@fieldwise_init
struct _Face(Copyable, Movable):
    """One triangle as the reduction sees it: three.js's `Triangle`."""

    var v1: Int
    var v2: Int
    var v3: Int
    var normal: SIMD[DType.float64, 4]

    def has_vertex(self, v: Int) -> Bool:
        """Return True if `v` is one of the corners."""
        return v == self.v1 or v == self.v2 or v == self.v3


def _dot(a: SIMD[DType.float64, 4], b: SIMD[DType.float64, 4]) -> Float64:
    """Return the dot product of the first three numbers."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _unit3(a: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 4]:
    """Return a three-number vector scaled to unit length, or itself if it
    is zero long, as three.js's `Vector3.normalize` does."""
    var length = sqrt(_dot(a, a))
    return a * (1.0 / (length if length != 0 else 1.0))


def _unit4(a: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 4]:
    """Return a four-number vector scaled to unit length, or itself if it
    is zero long, as three.js's `Vector4.normalize` does."""
    var length = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    return a * (1.0 / (length if length != 0 else 1.0))


def _find(list: List[Int], value: Int) -> Int:
    """Return where `value` first is in `list`, or -1: JavaScript's
    `indexOf`."""
    for index in range(len(list)):
        if list[index] == value:
            return index
    return -1


def _remove(mut list: List[Int], value: Int):
    """Remove the first `value` from `list`: three.js's `removeFromArray`.

    three.js does nothing when the value is not there, and every call here
    names one that is. A face is in its list of faces and in its corners'
    lists, once for each corner, even a corner that repeats. A vertex is
    in the list of vertices until it is removed, once.
    """
    var at = _find(list, value)
    # The value is there; see above.
    if at >= 0:  # pragma: no branch
        _ = list.pop(at)


def _contains(list: List[Int], value: Int) -> Bool:
    """Return True if `value` is in `list`."""
    return _find(list, value) >= 0


struct _Reduction(Movable):
    """The vertices and faces being reduced, and the lists of those still
    alive, in three.js's order."""

    var vertex_data: List[_Vertex]
    var face_data: List[_Face]
    var vertices: List[Int]
    var faces: List[Int]

    def __init__(out self):
        """Create an empty reduction."""
        self.vertex_data = List[_Vertex]()
        self.face_data = List[_Face]()
        self.vertices = List[Int]()
        self.faces = List[Int]()

    def face_normal(self, f: Int) -> SIMD[DType.float64, 4]:
        """Return a face's unit normal, three.js's `computeNormal`."""
        ref face = self.face_data[f]
        var b = self.vertex_data[face.v2].position
        var cb = self.vertex_data[face.v3].position - b
        var ab = self.vertex_data[face.v1].position - b
        var normal = SIMD[DType.float64, 4](
            cb[1] * ab[2] - cb[2] * ab[1],
            cb[2] * ab[0] - cb[0] * ab[2],
            cb[0] * ab[1] - cb[1] * ab[0],
            0,
        )
        return _unit3(normal)

    def add_unique_neighbor(mut self, v: Int, n: Int):
        """Add `n` to `v`'s neighbors unless it is there already."""
        if not _contains(self.vertex_data[v].neighbors, n):
            self.vertex_data[v].neighbors.append(n)

    def remove_if_non_neighbor(mut self, v: Int, n: Int):
        """Take `n` off `v`'s neighbors unless a face of `v` still has it:
        three.js's `removeIfNonNeighbor`."""
        if not _contains(self.vertex_data[v].neighbors, n):
            return
        for index in range(len(self.vertex_data[v].faces)):
            if self.face_data[self.vertex_data[v].faces[index]].has_vertex(n):
                return
        _remove(self.vertex_data[v].neighbors, n)

    def add_face(mut self, a: Int, b: Int, c: Int):
        """Add a triangle and join its corners, three.js's `Triangle`
        constructor."""
        var f = len(self.face_data)
        self.face_data.append(_Face(a, b, c, SIMD[DType.float64, 4](0)))
        self.face_data[f].normal = self.face_normal(f)
        self.faces.append(f)
        self.vertex_data[a].faces.append(f)
        self.add_unique_neighbor(a, b)
        self.add_unique_neighbor(a, c)
        self.vertex_data[b].faces.append(f)
        self.add_unique_neighbor(b, a)
        self.add_unique_neighbor(b, c)
        self.vertex_data[c].faces.append(f)
        self.add_unique_neighbor(c, a)
        self.add_unique_neighbor(c, b)

    def edge_cost(self, u: Int, v: Int) -> Float64:
        """Return the cost of moving `u` onto `v`, three.js's
        `computeEdgeCollapseCost`."""
        var d = self.vertex_data[v].position - self.vertex_data[u].position
        var edge_length = sqrt(_dot(d, d))
        var curvature = 0.0
        var side_faces = List[Int]()
        ref faces = self.vertex_data[u].faces
        # `v` is a neighbor of `u`, so they share a face: none of these
        # three loops can run zero times.
        for index in range(len(faces)):  # pragma: no branch
            if self.face_data[faces[index]].has_vertex(v):
                side_faces.append(faces[index])
        for index in range(len(faces)):  # pragma: no branch
            var min_curvature = 1.0
            ref normal = self.face_data[faces[index]].normal
            for side in range(len(side_faces)):  # pragma: no branch
                var dot = _dot(normal, self.face_data[side_faces[side]].normal)
                min_curvature = min(min_curvature, (1.001 - dot) / 2)
            curvature = max(curvature, min_curvature)
        if len(side_faces) < 2:
            curvature = 1
        return edge_length * curvature + 0

    def vertex_cost(mut self, v: Int):
        """Work out a vertex's cost and cheapest neighbor, three.js's
        `computeEdgeCostAtVertex`."""
        var neighbors = self.vertex_data[v].neighbors.copy()
        if len(neighbors) == 0:
            self.vertex_data[v].collapse_neighbor = -1
            self.vertex_data[v].collapse_cost = LONE_COST
            return
        ref vertex = self.vertex_data[v]
        vertex.collapse_cost = START_COST
        vertex.collapse_neighbor = -1
        for index in range(len(neighbors)):  # pragma: no branch
            # The vertex has a neighbor, so this runs.
            var cost = self.edge_cost(v, neighbors[index])
            ref same = self.vertex_data[v]
            if same.collapse_neighbor < 0:
                same.collapse_neighbor = neighbors[index]
                same.collapse_cost = cost
                same.min_cost = cost
                same.total_cost = 0
                same.cost_count = 0
            same.cost_count += 1
            same.total_cost += cost
            if cost < same.min_cost:
                same.collapse_neighbor = neighbors[index]
                same.min_cost = cost
        ref done = self.vertex_data[v]
        done.collapse_cost = done.total_cost / Float64(done.cost_count)

    def remove_vertex(mut self, v: Int):
        """Take a vertex out, three.js's `removeVertex`.

        three.js first unlinks any neighbors the vertex still has. A vertex
        removed here has none. Two vertices are neighbors only while they
        share a face, and a vertex is removed only once it has no faces:
        either it had no neighbors, or `collapse` has taken its faces away.
        """
        _remove(self.vertices, v)

    def remove_face(mut self, f: Int):
        """Take a triangle out, three.js's `removeFace`."""
        _remove(self.faces, f)
        var corners: List[Int] = [
            self.face_data[f].v1,
            self.face_data[f].v2,
            self.face_data[f].v3,
        ]
        for corner in range(3):  # pragma: no branch
            _remove(self.vertex_data[corners[corner]].faces, f)
        for i in range(3):  # pragma: no branch
            var a = corners[i]
            var b = corners[(i + 1) % 3]
            self.remove_if_non_neighbor(a, b)
            self.remove_if_non_neighbor(b, a)

    def replace_vertex(mut self, f: Int, old: Int, new: Int):
        """Make `new` a corner of a triangle in place of `old`, three.js's
        `replaceVertex`."""
        ref face = self.face_data[f]
        if old == face.v1:
            face.v1 = new
        elif old == face.v2:
            face.v2 = new
        else:
            # `old` is a corner: the face is in its list of faces.
            face.v3 = new
        _remove(self.vertex_data[old].faces, f)
        self.vertex_data[new].faces.append(f)
        var v1 = self.face_data[f].v1
        var v2 = self.face_data[f].v2
        var v3 = self.face_data[f].v3
        self.remove_if_non_neighbor(old, v1)
        self.remove_if_non_neighbor(v1, old)
        self.remove_if_non_neighbor(old, v2)
        self.remove_if_non_neighbor(v2, old)
        self.remove_if_non_neighbor(old, v3)
        self.remove_if_non_neighbor(v3, old)
        self.add_unique_neighbor(v1, v2)
        self.add_unique_neighbor(v1, v3)
        self.add_unique_neighbor(v2, v1)
        self.add_unique_neighbor(v2, v3)
        self.add_unique_neighbor(v3, v1)
        self.add_unique_neighbor(v3, v2)
        self.face_data[f].normal = self.face_normal(f)

    def collapse(mut self, u: Int, v: Int, has_normal: Bool, has_tangent: Bool):
        """Move `u` onto `v`, three.js's `collapse`."""
        if v < 0:
            self.remove_vertex(u)
            return
        if has_normal:
            self.vertex_data[v].normal = _unit3(
                self.vertex_data[v].normal + self.vertex_data[u].normal
            )
        if has_tangent:
            self.vertex_data[v].tangent = _unit4(
                self.vertex_data[v].tangent + self.vertex_data[u].tangent
            )
        var around = self.vertex_data[u].neighbors.copy()
        # A triangle with `u` at two corners is in `u`'s list twice, and
        # removing it takes out both, so entry `i` can be gone.
        var i = len(self.vertex_data[u].faces) - 1
        while i >= 0:
            if i < len(self.vertex_data[u].faces):
                var f = self.vertex_data[u].faces[i]
                if self.face_data[f].has_vertex(v):
                    self.remove_face(f)
            i -= 1
        i = len(self.vertex_data[u].faces) - 1
        while i >= 0:
            self.replace_vertex(self.vertex_data[u].faces[i], u, v)
            i -= 1
        self.remove_vertex(u)
        # `u` had the neighbor `v`, so this runs.
        for index in range(len(around)):  # pragma: no branch
            self.vertex_cost(around[index])

    def cheapest(self) -> Int:
        """Return the living vertex of least cost, the first of equals,
        three.js's `minimumCostEdge`, or -1 if none is left."""
        if len(self.vertices) == 0:
            return -1
        var least = self.vertices[0]
        for index in range(len(self.vertices)):  # pragma: no branch
            # The list is not empty, so this runs.
            var v = self.vertices[index]
            if (
                self.vertex_data[v].collapse_cost
                < self.vertex_data[least].collapse_cost
            ):
                least = v
        return least


def _read(
    geometry: BufferGeometry, name: String, size: Int, vertex: Int
) raises -> SIMD[DType.float64, 4]:
    """Return the first `size` numbers of one item of an attribute, as
    doubles."""
    ref attribute = geometry.attribute_view(name)
    var out = SIMD[DType.float64, 4](0)
    for axis in range(size):  # pragma: no branch
        # A size is two or more, so this runs.
        out[axis] = Float64(attribute.component(vertex, axis))
    return out


def _check_size(
    geometry: BufferGeometry, name: String, low: Int, high: Int
) raises -> Bool:
    """Return True if the geometry carries `name`, after checking it holds
    from `low` through `high` numbers an item."""
    if not geometry.has_attribute(name):
        return False
    var size = geometry.attribute_view(name).item_size
    if size < low or size > high:
        raise Error("A simplified attribute has the wrong item size")
    return True


def simplify(geometry: BufferGeometry, count: Int) raises -> BufferGeometry:
    """Return a surface with `count` fewer vertices, three.js's
    `SimplifyModifier.modify`.

    Args:
        geometry: The surface. It must carry positions of three numbers
            an item, and it cannot be instanced.
        count: How many vertices to take away, zero or more. The steps
            stop early if every vertex is gone.

    Returns:
        An indexed geometry with `position`, and `uv`, `normal`,
        `tangent` and `color` if the surface carries them.

    Raises:
        Error: If `count` is negative, the surface is instanced or has no
            positions, one of the attributes it keeps holds the wrong
            number of numbers an item, or an index entry points past the
            last vertex.
    """
    if count < 0:
        raise Error("A simplification cannot take away a negative count")
    var kept = BufferGeometry()
    var names: List[String] = [
        String(POSITION),
        String(UV),
        String(NORMAL),
        String(TANGENT),
        String(COLOR),
    ]
    for slot in range(len(geometry.names)):
        for keep in range(len(names)):  # pragma: no branch
            if geometry.names[slot] == names[keep]:
                kept.set_attribute(
                    geometry.names[slot], geometry.values[slot].copy()
                )
    kept.index = geometry.index.copy()
    kept.instanced = geometry.instanced
    if not _check_size(kept, String(POSITION), 3, 3):
        raise Error("A simplified surface needs positions")
    var has_uv = _check_size(kept, String(UV), 2, 2)
    var has_normal = _check_size(kept, String(NORMAL), 3, 3)
    var has_tangent = _check_size(kept, String(TANGENT), 4, 4)
    var has_color = _check_size(kept, String(COLOR), 3, 4)
    var welded = merge_vertices(kept)

    var work = _Reduction()
    var vertex_count = welded.vertex_count()
    for vertex in range(vertex_count):
        var v = _Vertex(_read(welded, String(POSITION), 3, vertex))
        if has_uv:
            var uv = _read(welded, String(UV), 2, vertex)
            v.uv = SIMD[DType.float64, 2](uv[0], uv[1])
        if has_normal:
            v.normal = _read(welded, String(NORMAL), 3, vertex)
        if has_tangent:
            v.tangent = _read(welded, String(TANGENT), 4, vertex)
        if has_color:
            v.color = _read(welded, String(COLOR), 3, vertex)
        work.vertex_data.append(v^)
        work.vertices.append(vertex)
    for triangle in range(welded.triangle_count()):
        work.add_face(
            welded.corner_index(triangle, 0),
            welded.corner_index(triangle, 1),
            welded.corner_index(triangle, 2),
        )
    for vertex in range(vertex_count):
        work.vertex_cost(vertex)

    for _ in range(count):
        var next = work.cheapest()
        if next < 0:
            break
        work.collapse(
            next,
            work.vertex_data[next].collapse_neighbor,
            has_normal,
            has_tangent,
        )

    var position = List[Float32]()
    var uv = List[Float32]()
    var normal = List[Float32]()
    var tangent = List[Float32]()
    var color = List[Float32]()
    for index in range(len(work.vertices)):
        ref vertex = work.vertex_data[work.vertices[index]]
        for axis in range(3):  # pragma: no branch
            position.append(Float32(vertex.position[axis]))
        if has_uv:
            uv.append(Float32(vertex.uv[0]))
            uv.append(Float32(vertex.uv[1]))
        if has_normal:
            for axis in range(3):  # pragma: no branch
                normal.append(Float32(vertex.normal[axis]))
        if has_tangent:
            for axis in range(4):  # pragma: no branch
                tangent.append(Float32(vertex.tangent[axis]))
        if has_color:
            for axis in range(3):  # pragma: no branch
                color.append(Float32(vertex.color[axis]))
        vertex.id = index
    var index = List[Int]()
    for face in range(len(work.faces)):
        ref triangle = work.face_data[work.faces[face]]
        index.append(work.vertex_data[triangle.v1].id)
        index.append(work.vertex_data[triangle.v2].id)
        index.append(work.vertex_data[triangle.v3].id)

    # As in three.js, an attribute left with no numbers is not set.
    var result = BufferGeometry()
    result.set_attribute(String(POSITION), BufferAttribute(position^, 3))
    if len(uv) > 0:
        result.set_attribute(String(UV), BufferAttribute(uv^, 2))
    if len(normal) > 0:
        result.set_attribute(String(NORMAL), BufferAttribute(normal^, 3))
    if len(tangent) > 0:
        result.set_attribute(String(TANGENT), BufferAttribute(tangent^, 4))
    if len(color) > 0:
        result.set_attribute(String(COLOR), BufferAttribute(color^, 3))
    result.set_index(index^)
    return result^
