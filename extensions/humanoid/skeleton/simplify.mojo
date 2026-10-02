# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Merge the triangles a humanoid does not need, down to a budget.

A marching-tetrahedra surface has many more triangles than its shape
needs: a flat stretch of a muscle is cut as finely as a condyle. This
module merges them. `fit_triangle_budget` shares one triangle budget
between the meshes of a body by surface area, then decimates each mesh
to its share. `simplify` decimates one geometry.

The merge is quadric-error edge collapse (Garland and Heckbert, 1997).
Each vertex keeps the sum of the squared-distance quadrics of the
planes around it. The edge whose collapse moves the surface least goes
first. A collapse is refused if it would turn a face over or pinch the
surface, so a thin part keeps its volume.

    var first = len(scene.meshes)
    _ = add_body(scene, assets, parent, person, ...)
    fit_triangle_budget(scene, assets, first, 90000)

The vertices are welded first. A mesh whose triangles each carry their
own three corners is joined where the corners meet, to within
`WELD_STEP`. The normals are the area-weighted mean of the faces around
each vertex. A vertex keeps its own texture coordinates.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.scene import Scene
from math.vector3 import Vector3
from render.tasks import TaskGroup
from std.collections import Dict
from std.math import max, min

# The fewest triangles a mesh is decimated to. Below this a small part
# stops looking like its shape.
comptime MIN_PART_TRIANGLES = 32
# How close two corners must be to be welded into one vertex, in meters.
comptime WELD_STEP = Float32(1e-5)
# The most integer steps one axis of a weld key holds.
comptime _WELD_LEVELS = 1 << 21
# A collapse is refused if a face around it would turn by more than
# this: the cosine between its normal before and after.
comptime FLIP_LIMIT = Float64(0.2)
# How much more an open edge resists moving than the surface does.
comptime BOUNDARY_WEIGHT = Float64(1000)


@fieldwise_init
struct _Quadric(ImplicitlyCopyable):
    """The sum of squared distances to a set of planes, as ten numbers.

    The upper triangle of the symmetric 4x4 matrix, row by row:
    `xx xy xz xw yy yz yw zz zw ww`.
    """

    var q: SIMD[DType.float64, 16]

    @staticmethod
    def plane(nx: Float64, ny: Float64, nz: Float64, d: Float64) -> Self:
        """Return the quadric of the plane `n . p + d = 0`, unscaled.

        Args:
            nx: The plane normal's x.
            ny: Its y.
            nz: Its z.
            d: The plane's offset.

        Returns:
            The quadric of the squared distance, times `|n|` squared.
        """
        var q = SIMD[DType.float64, 16](0)
        q[0] = nx * nx
        q[1] = nx * ny
        q[2] = nx * nz
        q[3] = nx * d
        q[4] = ny * ny
        q[5] = ny * nz
        q[6] = ny * d
        q[7] = nz * nz
        q[8] = nz * d
        q[9] = d * d
        return Self(q)

    def error(self, x: Float64, y: Float64, z: Float64) -> Float64:
        """Return the summed squared distance of `(x, y, z)`.

        Args:
            x: The point's x.
            y: Its y.
            z: Its z.

        Returns:
            The quadric's value at the point.
        """
        var q = self.q
        return (
            q[0] * x * x
            + 2 * q[1] * x * y
            + 2 * q[2] * x * z
            + 2 * q[3] * x
            + q[4] * y * y
            + 2 * q[5] * y * z
            + 2 * q[6] * y
            + q[7] * z * z
            + 2 * q[8] * z
            + q[9]
        )


@fieldwise_init
struct _Entry(ImplicitlyCopyable):
    """One candidate collapse in the heap."""

    var cost: Float64
    var u: Int
    var v: Int
    # The two vertices' versions when the entry was made. A vertex that
    # has moved since makes the entry stale.
    var stamp_u: Int
    var stamp_v: Int
    var x: Float64
    var y: Float64
    var z: Float64


struct _Heap(Movable):
    """A binary min-heap of candidate collapses, cheapest first."""

    var entries: List[_Entry]

    def __init__(out self):
        """Make an empty heap."""
        self.entries = List[_Entry]()

    def push(mut self, entry: _Entry):
        """Add one candidate.

        Args:
            entry: The candidate.
        """
        self.entries.append(entry)
        var child = len(self.entries) - 1
        while child > 0:
            var parent = (child - 1) // 2
            if self.entries[parent].cost <= self.entries[child].cost:
                return
            var held = self.entries[parent]
            self.entries[parent] = self.entries[child]
            self.entries[child] = held
            child = parent

    def pop(mut self) -> _Entry:
        """Remove and return the cheapest candidate. The heap must not be
        empty.

        Returns:
            The candidate with the least cost.
        """
        var top = self.entries[0]
        var last = self.entries.pop()
        var count = len(self.entries)
        if count == 0:
            return top
        self.entries[0] = last
        var parent = 0
        while True:
            var least = parent
            var left = parent * 2 + 1
            var right = left + 1
            if (
                left < count
                and self.entries[left].cost < self.entries[least].cost
            ):
                least = left
            if (
                right < count
                and self.entries[right].cost < self.entries[least].cost
            ):
                least = right
            if least == parent:
                return top
            var held = self.entries[parent]
            self.entries[parent] = self.entries[least]
            self.entries[least] = held
            parent = least


struct WeldedMesh(Movable):
    """A triangle mesh whose corners are shared between its faces.

    What `weld` returns and `simplify` works on. It holds no normals:
    `to_geometry` works them out from the faces.
    """

    var positions: List[Vector3]
    # Two per vertex, or empty if the source had none.
    var uvs: List[Float32]
    # Three vertex numbers per face.
    var faces: List[Int]

    def __init__(
        out self,
        var positions: List[Vector3],
        var uvs: List[Float32],
        var faces: List[Int],
    ):
        """Hold a welded mesh.

        Args:
            positions: Each vertex, in meters.
            uvs: Two texture coordinates per vertex, or none.
            faces: Three vertex numbers per face.
        """
        self.positions = positions^
        self.uvs = uvs^
        self.faces = faces^

    def triangle_count(self) -> Int:
        """Return how many faces the mesh holds.

        Returns:
            One third of the face list's length.
        """
        return len(self.faces) // 3

    def area(self) -> Float64:
        """Return the mesh's surface area.

        Returns:
            The summed area of its faces, in square meters.
        """
        var total = Float64(0)
        for face in range(self.triangle_count()):
            var a = self.positions[self.faces[face * 3]]
            var edge = self.positions[self.faces[face * 3 + 1]] - a
            edge.cross(self.positions[self.faces[face * 3 + 2]] - a)
            total += Float64(edge.length()) * 0.5
        return total

    def to_geometry(self) raises -> BufferGeometry:
        """Return the mesh as an indexed geometry with normals.

        Each normal is the area-weighted mean of the faces around its
        vertex. Texture coordinates are kept if the mesh has them.

        Returns:
            A geometry with `position`, `normal` and, if there are
            texture coordinates, `uv`.

        Raises:
            Error: If the geometry refuses an attribute or the index.
        """
        var count = len(self.positions)
        var sums = List[Vector3](length=count, fill=Vector3(0, 0, 0))
        for face in range(self.triangle_count()):
            var i0 = self.faces[face * 3]
            var i1 = self.faces[face * 3 + 1]
            var i2 = self.faces[face * 3 + 2]
            var edge = self.positions[i1] - self.positions[i0]
            edge.cross(self.positions[i2] - self.positions[i0])
            sums[i0] = sums[i0] + edge
            sums[i1] = sums[i1] + edge
            sums[i2] = sums[i2] + edge
        var positions = List[Float32](capacity=count * 3)
        var normals = List[Float32](capacity=count * 3)
        for vertex in range(count):
            var point = self.positions[vertex]
            positions.append(point.x)
            positions.append(point.y)
            positions.append(point.z)
            var normal = sums[vertex]
            if normal.length() == 0:
                normal = Vector3(0, 1, 0)
            normal.normalize()
            normals.append(normal.x)
            normals.append(normal.y)
            normals.append(normal.z)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
        if len(self.uvs) > 0:
            geometry.set_attribute(
                String(UV), BufferAttribute(self.uvs.copy(), 2)
            )
        geometry.set_index(self.faces.copy())
        return geometry^


def _read_mesh(geometry: BufferGeometry) raises -> WeldedMesh:
    """Return a geometry's triangles as they stand, not yet welded.

    Args:
        geometry: An indexed or unindexed triangle geometry.

    Returns:
        Its corners, its texture coordinates if it has them, and its
        faces.

    Raises:
        Error: If it has no positions, or its triangles are not whole.
    """
    ref points = geometry.attribute_view(String(POSITION))
    var count = points.count()
    var positions = List[Vector3](capacity=count)
    for vertex in range(count):
        positions.append(points.vector3(vertex))
    var uvs = List[Float32]()
    if geometry.has_attribute(String(UV)):
        ref coordinates = geometry.attribute_view(String(UV))
        uvs.reserve(count * 2)
        for vertex in range(count):
            uvs.append(coordinates.component(vertex, 0))
            uvs.append(coordinates.component(vertex, 1))
    var faces: List[Int]
    if geometry.is_indexed():
        faces = geometry.index.copy()
    else:
        faces = List[Int](capacity=count)
        for vertex in range(count):
            faces.append(vertex)
    if len(faces) % 3 != 0:
        raise Error("A mesh to simplify must hold whole triangles")
    for slot in range(len(faces)):
        if faces[slot] < 0 or faces[slot] >= count:
            raise Error("An index entry points past the last vertex")
    return WeldedMesh(positions^, uvs^, faces^)


def weld(mesh: WeldedMesh) -> WeldedMesh:
    """Join the corners that lie within `WELD_STEP` of each other.

    Faces that lose a corner to the join are dropped: they had no area.

    Args:
        mesh: The mesh, welded or not.

    Returns:
        The same surface with each shared corner stored once.
    """
    var count = len(mesh.positions)
    var low = Vector3(0, 0, 0)
    var high = Vector3(0, 0, 0)
    if count > 0:
        low = mesh.positions[0]
        high = mesh.positions[0]
    for vertex in range(count):
        var point = mesh.positions[vertex]
        low = Vector3(
            min(low.x, point.x), min(low.y, point.y), min(low.z, point.z)
        )
        high = Vector3(
            max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)
        )
    var span = max(high.x - low.x, max(high.y - low.y, high.z - low.z))
    # A mesh too wide for the step is welded more coarsely, so each
    # axis fits its bits of the key.
    var step = max(WELD_STEP, span / Float32(_WELD_LEVELS - 2))
    var index = Dict[Int, Int]()
    var remap = List[Int](capacity=count)
    var positions = List[Vector3]()
    var uvs = List[Float32]()
    var has_uv = len(mesh.uvs) > 0
    for vertex in range(count):
        var point = mesh.positions[vertex]
        var qx = Int((point.x - low.x) / step + 0.5)
        var qy = Int((point.y - low.y) / step + 0.5)
        var qz = Int((point.z - low.z) / step + 0.5)
        var key = qx | (qy << 21) | (qz << 42)
        var found = index.get(key)
        if Bool(found):
            remap.append(found.value())
            continue
        var kept = len(positions)
        index[key] = kept
        remap.append(kept)
        positions.append(point)
        if has_uv:
            uvs.append(mesh.uvs[vertex * 2])
            uvs.append(mesh.uvs[vertex * 2 + 1])
    var faces = List[Int](capacity=len(mesh.faces))
    for face in range(mesh.triangle_count()):
        var i0 = remap[mesh.faces[face * 3]]
        var i1 = remap[mesh.faces[face * 3 + 1]]
        var i2 = remap[mesh.faces[face * 3 + 2]]
        if i0 == i1 or i1 == i2 or i0 == i2:
            continue
        faces.append(i0)
        faces.append(i1)
        faces.append(i2)
    return WeldedMesh(positions^, uvs^, faces^)


def _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return the unnormalized normal of triangle `a`, `b`, `c`."""
    var edge = b - a
    edge.cross(c - a)
    return edge


def _cosine(a: Vector3, b: Vector3) -> Float64:
    """Return the cosine between two vectors, or -1 if either is zero."""
    var la = Float64(a.length())
    var lb = Float64(b.length())
    if la == 0 or lb == 0:
        return -1
    return Float64(a.dot(b)) / (la * lb)


struct _Collapser(Movable):
    """The working state of one decimation."""

    var positions: List[Vector3]
    var uvs: List[Float32]
    var faces: List[Int]
    var face_alive: List[Bool]
    var vertex_faces: List[List[Int]]
    var vertex_alive: List[Bool]
    var version: List[Int]
    var quadrics: List[_Quadric]
    var heap: _Heap
    var alive: Int

    def __init__(out self, mesh: WeldedMesh):
        """Build the quadrics, the adjacency and the first candidates.

        Args:
            mesh: A welded mesh.
        """
        var count = len(mesh.positions)
        self.positions = mesh.positions.copy()
        self.uvs = mesh.uvs.copy()
        self.faces = mesh.faces.copy()
        var triangles = mesh.triangle_count()
        self.face_alive = List[Bool](length=triangles, fill=True)
        self.vertex_faces = List[List[Int]](length=count, fill=List[Int]())
        self.vertex_alive = List[Bool](length=count, fill=True)
        self.version = List[Int](length=count, fill=0)
        self.quadrics = List[_Quadric](
            length=count, fill=_Quadric(SIMD[DType.float64, 16](0))
        )
        self.heap = _Heap()
        self.alive = triangles
        for face in range(triangles):  # pragma: no branch
            var i0 = self.faces[face * 3]
            var i1 = self.faces[face * 3 + 1]
            var i2 = self.faces[face * 3 + 2]
            self.vertex_faces[i0].append(face)
            self.vertex_faces[i1].append(face)
            self.vertex_faces[i2].append(face)
            var a = self.positions[i0]
            var normal = _face_normal(a, self.positions[i1], self.positions[i2])
            var length = Float64(normal.length())
            if length == 0:
                continue
            # The unit plane, weighted by the face's area.
            var nx = Float64(normal.x) / length
            var ny = Float64(normal.y) / length
            var nz = Float64(normal.z) / length
            var d = -(nx * Float64(a.x) + ny * Float64(a.y) + nz * Float64(a.z))
            var plane = _Quadric.plane(nx, ny, nz, d)
            var weighted = _Quadric(plane.q * (length * 0.5))
            for corner in range(3):  # pragma: no branch
                var vertex = self.faces[face * 3 + corner]
                self.quadrics[vertex] = _Quadric(
                    self.quadrics[vertex].q + weighted.q
                )
        self._hold_open_edges(triangles)
        for face in range(triangles):  # pragma: no branch
            for corner in range(3):  # pragma: no branch
                var u = self.faces[face * 3 + corner]
                var v = self.faces[face * 3 + (corner + 1) % 3]
                # Each edge is offered once, from its lower vertex.
                if u < v:
                    self._offer(u, v)

    def _hold_open_edges(mut self, triangles: Int):
        """Add a stiff plane along each edge that only one face has.

        The plane holds the edge and stands at right angles to its face,
        so the edge's vertices resist moving off the mesh's border.

        Args:
            triangles: How many faces the mesh holds.
        """
        for face in range(triangles):  # pragma: no branch
            for corner in range(3):  # pragma: no branch
                var u = self.faces[face * 3 + corner]
                var v = self.faces[face * 3 + (corner + 1) % 3]
                if self._faces_on_edge(u, v) != 1:
                    continue
                var w = self.faces[face * 3 + (corner + 2) % 3]
                var along = self.positions[v] - self.positions[u]
                var normal = _face_normal(
                    self.positions[u], self.positions[v], self.positions[w]
                )
                var side = along
                side.cross(normal)
                var length = Float64(side.length())
                if length == 0:
                    continue
                var nx = Float64(side.x) / length
                var ny = Float64(side.y) / length
                var nz = Float64(side.z) / length
                var a = self.positions[u]
                var d = -(
                    nx * Float64(a.x) + ny * Float64(a.y) + nz * Float64(a.z)
                )
                var plane = _Quadric.plane(nx, ny, nz, d)
                var weight = BOUNDARY_WEIGHT * Float64(along.length_sq())
                self.quadrics[u] = _Quadric(
                    self.quadrics[u].q + plane.q * weight
                )
                self.quadrics[v] = _Quadric(
                    self.quadrics[v].q + plane.q * weight
                )

    def _faces_on_edge(self, u: Int, v: Int) -> Int:
        """Return how many live faces hold both `u` and `v`."""
        var count = 0
        ref around = self.vertex_faces[u]
        for slot in range(len(around)):  # pragma: no branch
            var face = around[slot]
            if not self.face_alive[face]:
                continue
            if self._holds(face, v):
                count += 1
        return count

    def _holds(self, face: Int, vertex: Int) -> Bool:
        """Return True if `face` has `vertex` as a corner."""
        return (
            self.faces[face * 3] == vertex
            or self.faces[face * 3 + 1] == vertex
            or self.faces[face * 3 + 2] == vertex
        )

    def _offer(mut self, u: Int, v: Int):
        """Push the collapse of edge `u`-`v` at its best point.

        Args:
            u: One end.
            v: The other.
        """
        var sum = _Quadric(self.quadrics[u].q + self.quadrics[v].q)
        var q = sum.q
        var pu = self.positions[u]
        var pv = self.positions[v]
        # The point that minimizes the sum, if the plane system has one.
        var a = q[0]
        var b = q[1]
        var c = q[2]
        var e = q[4]
        var f = q[5]
        var h = q[7]
        var det = (
            a * (e * h - f * f) - b * (b * h - f * c) + c * (b * f - e * c)
        )
        var scale = abs(a) + abs(e) + abs(h)
        var bx = -q[3]
        var by = -q[6]
        var bz = -q[8]
        var x = Float64(pu.x + pv.x) * 0.5
        var y = Float64(pu.y + pv.y) * 0.5
        var z = Float64(pu.z + pv.z) * 0.5
        var best = sum.error(x, y, z)
        if abs(det) > 1e-9 * scale * scale * scale:
            var sx = (
                bx * (e * h - f * f)
                - b * (by * h - f * bz)
                + c * (by * f - e * bz)
            ) / det
            var sy = (
                a * (by * h - bz * f)
                - bx * (b * h - f * c)
                + c * (b * bz - by * c)
            ) / det
            var sz = (
                a * (e * bz - f * by)
                - b * (b * bz - by * c)
                + bx * (b * f - e * c)
            ) / det
            var cost = sum.error(sx, sy, sz)
            # Kept only near the edge: far off it, a nearly flat system
            # can put the point anywhere.
            var mx = Float64(pu.x + pv.x) * 0.5
            var my = Float64(pu.y + pv.y) * 0.5
            var mz = Float64(pu.z + pv.z) * 0.5
            var reach = Float64((pv - pu).length_sq())
            var off = (
                (sx - mx) * (sx - mx)
                + (sy - my) * (sy - my)
                + (sz - mz) * (sz - mz)
            )
            if cost < best and off <= reach:
                best = cost
                x = sx
                y = sy
                z = sz
        var at_u = sum.error(Float64(pu.x), Float64(pu.y), Float64(pu.z))
        if at_u < best:
            best = at_u
            x = Float64(pu.x)
            y = Float64(pu.y)
            z = Float64(pu.z)
        var at_v = sum.error(Float64(pv.x), Float64(pv.y), Float64(pv.z))
        if at_v < best:
            best = at_v
            x = Float64(pv.x)
            y = Float64(pv.y)
            z = Float64(pv.z)
        self.heap.push(
            _Entry(
                max(best, Float64(0)),
                u,
                v,
                self.version[u],
                self.version[v],
                x,
                y,
                z,
            )
        )

    def _neighbors(self, vertex: Int) -> List[Int]:
        """Return the vertices that share a live face with `vertex`."""
        var found = List[Int]()
        ref around = self.vertex_faces[vertex]
        for slot in range(len(around)):  # pragma: no branch
            var face = around[slot]
            if not self.face_alive[face]:
                continue
            for corner in range(3):  # pragma: no branch
                var other = self.faces[face * 3 + corner]
                if other == vertex:
                    continue
                var seen = False
                for index in range(len(found)):
                    if found[index] == other:
                        seen = True
                        break
                if not seen:
                    found.append(other)
        return found^

    def _turns_over(self, vertex: Int, other: Int, point: Vector3) -> Bool:
        """Return True if moving `vertex` to `point` turns a face over.

        The faces that also hold `other` are left out: the collapse
        removes them.
        """
        ref around = self.vertex_faces[vertex]
        for slot in range(len(around)):  # pragma: no branch
            var face = around[slot]
            if not self.face_alive[face] or self._holds(face, other):
                continue
            var corners: List[Vector3] = [
                self.positions[self.faces[face * 3]],
                self.positions[self.faces[face * 3 + 1]],
                self.positions[self.faces[face * 3 + 2]],
            ]
            var before = _face_normal(corners[0], corners[1], corners[2])
            for corner in range(3):  # pragma: no branch
                if self.faces[face * 3 + corner] == vertex:
                    corners[corner] = point
            var after = _face_normal(corners[0], corners[1], corners[2])
            if _cosine(before, after) < FLIP_LIMIT:
                return True
        return False

    def collapse(mut self, entry: _Entry, minimum: Int = 0) -> Bool:
        """Merge `entry.v` into `entry.u` at the entry's point, if allowed.

        Args:
            entry: A candidate from the heap.
            minimum: The fewest faces a collapse may leave.

        Returns:
            True if the edge was collapsed.
        """
        var u = entry.u
        var v = entry.v
        if not self.vertex_alive[u] or not self.vertex_alive[v]:
            return False
        if self.version[u] != entry.stamp_u or self.version[v] != entry.stamp_v:
            return False
        var shared = self._faces_on_edge(u, v)
        # No face: the edge is gone. More than two: it is not a surface
        # edge, and merging it would tear the surface.
        if shared == 0 or shared > 2:
            return False
        if self.alive - shared < minimum:
            return False
        # The link condition: the ends may share no neighbor but the far
        # corners of their shared faces, or the collapse pinches.
        var near_u = self._neighbors(u)
        var near_v = self._neighbors(v)
        var common = 0
        for i in range(len(near_u)):  # pragma: no branch
            for j in range(len(near_v)):  # pragma: no branch
                if near_u[i] == near_v[j]:
                    common += 1
        if common != shared:
            return False
        var point = Vector3(
            Float32(entry.x), Float32(entry.y), Float32(entry.z)
        )
        if self._turns_over(u, v, point) or self._turns_over(v, u, point):
            return False
        self.positions[u] = point
        self.quadrics[u] = _Quadric(self.quadrics[u].q + self.quadrics[v].q)
        ref moved = self.vertex_faces[v]
        for slot in range(len(moved)):  # pragma: no branch
            var face = moved[slot]
            if not self.face_alive[face]:
                continue
            if self._holds(face, u):
                self.face_alive[face] = False
                self.alive -= 1
                continue
            for corner in range(3):  # pragma: no branch
                if self.faces[face * 3 + corner] == v:
                    self.faces[face * 3 + corner] = u
            self.vertex_faces[u].append(face)
        self.vertex_alive[v] = False
        self.version[u] += 1
        var near = self._neighbors(u)
        for index in range(len(near)):
            self._offer(u, near[index])
        return True

    def run(mut self, target: Int, minimum: Int = 0):
        """Collapse the cheapest edges until `target` faces are left, or
        no edge can go.

        Args:
            target: How many faces to keep.
            minimum: The fewest faces a collapse may leave.
        """
        while self.alive > target and len(self.heap.entries) > 0:
            _ = self.collapse(self.heap.pop(), minimum)

    def result(self) -> WeldedMesh:
        """Return the live faces over the vertices they use.

        Returns:
            The decimated mesh, its vertices renumbered.
        """
        var remap = List[Int](length=len(self.positions), fill=-1)
        var positions = List[Vector3]()
        var uvs = List[Float32]()
        var has_uv = len(self.uvs) > 0
        var faces = List[Int]()
        for face in range(len(self.face_alive)):  # pragma: no branch
            if not self.face_alive[face]:
                continue
            for corner in range(3):  # pragma: no branch
                var vertex = self.faces[face * 3 + corner]
                if remap[vertex] < 0:
                    remap[vertex] = len(positions)
                    positions.append(self.positions[vertex])
                    if has_uv:
                        uvs.append(self.uvs[vertex * 2])
                        uvs.append(self.uvs[vertex * 2 + 1])
                faces.append(remap[vertex])
        return WeldedMesh(positions^, uvs^, faces^)


def simplify_welded(
    mesh: WeldedMesh, target: Int, minimum: Int = 0
) -> WeldedMesh:
    """Decimate a welded mesh to at most `target` faces, where it can.

    Args:
        mesh: A welded mesh.
        target: How many faces to keep.
        minimum: The fewest faces a collapse may leave.

    Returns:
        The mesh with its cheapest edges collapsed. It keeps more than
        `target` faces if every edge left would turn a face over or
        pinch the surface, or would leave fewer than `minimum` faces.
    """
    if mesh.triangle_count() <= target:
        return WeldedMesh(
            mesh.positions.copy(), mesh.uvs.copy(), mesh.faces.copy()
        )
    var collapser = _Collapser(mesh)
    collapser.run(target, minimum)
    return collapser.result()


def simplify(geometry: BufferGeometry, target: Int) raises -> BufferGeometry:
    """Weld a geometry and decimate it toward `target` triangles.

    Args:
        geometry: An indexed or unindexed triangle geometry.
        target: How many triangles to keep, at least one.

    Returns:
        An indexed geometry with `position`, `normal` and, if the source
        had them, `uv`. It can exceed `target` if no safe collapse remains.

    Raises:
        Error: If `target` is less than one, or the geometry has no
            positions or holds a partial triangle.
    """
    if target < 1:
        raise Error("A simplified mesh must keep at least one triangle")
    var welded = weld(_read_mesh(geometry))
    return simplify_welded(welded, target).to_geometry()


def share_budget(
    areas: List[Float64], counts: List[Int], budget: Int
) -> List[Int]:
    """Share a triangle budget between meshes by their surface area.

    A mesh's share is the budget times its fraction of the area, and at
    least `MIN_PART_TRIANGLES`. A mesh never gets more than it holds; what
    it cannot use is shared again between the others. Minimum shares are
    reserved before larger shares are assigned. If the budget cannot
    cover the minimum shares, they take priority over the budget.

    Args:
        areas: Each mesh's surface area.
        counts: Each mesh's triangles now.
        budget: The triangles all the meshes may hold together.

    Returns:
        Each mesh's share, in the same order, rounded down. Their sum is
        at most the budget or the sum of the minimum shares, whichever
        is larger. A zero-area mesh receives only its minimum share.
    """
    var count = len(areas)
    var shares = List[Int](capacity=count)
    var least = 0
    for index in range(count):
        var minimum = min(MIN_PART_TRIANGLES, counts[index])
        shares.append(minimum)
        least += minimum
    if budget <= least:
        return shares^
    var settled = List[Bool](length=count, fill=False)
    var left = budget
    while True:
        var area = Float64(0)
        for index in range(count):
            if not settled[index]:
                area += areas[index]
        if area <= 0:
            return shares^
        # Test both bounds before fixing either one. Fixing a small
        # source first could spend the minimum of a small-area mesh.
        var wanted = List[Float64](length=count, fill=0)
        var total = Float64(0)
        # Positive remaining area requires at least one mesh, so count > 0.
        for index in range(count):  # pragma: no branch
            if settled[index]:
                continue
            wanted[index] = Float64(left) * areas[index] / area
            var minimum = min(MIN_PART_TRIANGLES, counts[index])
            total += min(
                Float64(counts[index]),
                max(Float64(minimum), wanted[index]),
            )
        var fix_minimum = total > Float64(left)
        var changed = False
        # Positive remaining area requires at least one mesh, so count > 0.
        for index in range(count):  # pragma: no branch
            if settled[index]:
                continue
            var minimum = min(MIN_PART_TRIANGLES, counts[index])
            shares[index] = max(
                minimum, Int(min(Float64(counts[index]), wanted[index]))
            )
            # An excess means the lower bounds must be reserved first.
            # A shortfall means upper bounds release unused triangles.
            if (fix_minimum and wanted[index] <= Float64(minimum)) or (
                not fix_minimum and wanted[index] >= Float64(counts[index])
            ):
                settled[index] = True
                left -= shares[index]
                changed = True
        if not changed:
            return shares^


async def _weld_task(
    meshes: MutPointer[WeldedMesh, MutAnyOrigin],
    areas: MutPointer[Float64, MutAnyOrigin],
    count: Int,
    task: Int,
    tasks: Int,
):
    """Weld every `tasks`-th mesh from `task`, and measure its area.

    Args:
        meshes: The meshes, welded in place.
        areas: Each mesh's area, written.
        count: How many meshes there are.
        task: This task's first mesh.
        tasks: How many tasks share the meshes.
    """
    var index = task
    while index < count:
        # Built into a local first: assigning a call that reads the
        # slot straight back into the slot crashes in a task.
        var welded = weld(meshes[unsafe_offset=index])
        areas[unsafe_offset=index] = welded.area()
        meshes[unsafe_offset=index] = welded^
        index += tasks


async def _simplify_task(
    meshes: MutPointer[WeldedMesh, MutAnyOrigin],
    targets: MutPointer[Int, MutAnyOrigin],
    count: Int,
    task: Int,
    tasks: Int,
):
    """Decimate every `tasks`-th mesh from `task` to its target.

    Args:
        meshes: The welded meshes, decimated in place.
        targets: Each mesh's share of the budget.
        count: How many meshes there are.
        task: This task's first mesh.
        tasks: How many tasks share the meshes.
    """
    var index = task
    while index < count:
        var decimated = simplify_welded(
            meshes[unsafe_offset=index],
            targets[unsafe_offset=index],
            MIN_PART_TRIANGLES,
        )
        meshes[unsafe_offset=index] = decimated^
        index += tasks


def fit_triangle_budget(
    scene: Scene,
    mut assets: Assets,
    first_mesh: Int,
    budget: Int,
    workers: Int = 1,
) raises:
    """Decimate the meshes from `first_mesh` on toward one triangle budget.

    Each geometry the meshes name is welded, then decimated to its share
    of the budget; see `share_budget`. A geometry two meshes name is
    decimated once. The geometries are replaced in `assets`. Each keeps
    at least 32 triangles, or its count after welding if that is smaller.
    The result can exceed the budget when these minimums or the safe
    collapse rules prevent more reduction.

    Args:
        scene: The scene whose meshes to read.
        assets: The store that holds their geometries, changed in place.
        first_mesh: The first mesh to decimate, such as the scene's mesh
            count before a body was added.
        budget: The target triangle count across unique geometries,
            at least one. This is not a hard maximum.
        workers: How many threads may weld and decimate.

    Raises:
        Error: If `budget` or `workers` is less than one, `first_mesh` is
            out of range, or a geometry has no positions or holds a
            partial triangle.
    """
    if budget < 1:
        raise Error("A triangle budget must be at least one")
    if workers < 1:
        raise Error("Simplifying needs at least one worker")
    if first_mesh < 0 or first_mesh > len(scene.meshes):
        raise Error("The first mesh to simplify is not in the scene")
    var ids = List[GeometryId]()
    var seen = Dict[Int, Bool]()
    for index in range(first_mesh, len(scene.meshes)):
        var id = scene.meshes[index].geometry
        if id.value in seen:
            continue
        seen[id.value] = True
        ids.append(id)
    var meshes = List[WeldedMesh]()
    for index in range(len(ids)):
        meshes.append(_read_mesh(assets.geometries.get(ids[index])))
    var count = len(meshes)
    var areas = List[Float64](length=count, fill=0)
    var tasks = max(1, min(workers, count))
    var welds = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        welds.create_task(
            _weld_task(
                meshes.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                areas.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                count,
                task,
                tasks,
            )
        )
    welds.wait()
    var counts = List[Int](capacity=count)
    for index in range(count):
        counts.append(meshes[index].triangle_count())
    var targets = share_budget(areas, counts, budget)
    var cuts = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        cuts.create_task(
            _simplify_task(
                meshes.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                targets.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                count,
                task,
                tasks,
            )
        )
    cuts.wait()
    # The tasks read the targets through pointers the compiler cannot
    # see, and Mojo destroys a value after its last use: this read keeps
    # them alive until every task has finished.
    _ = len(targets)
    for index in range(count):
        assets.geometries.replace(ids[index], meshes[index].to_geometry())
