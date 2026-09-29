# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's mesh simplification, `geom::Simplification`, from
`LibCarla/source/carla/geom/Simplification.cpp`.

CARLA hands the mesh to Sven Forstmann's Fast Quadric Mesh
Simplification (MIT, 2014), which CARLA keeps as
`LibCarla/source/third-party/simplify/Simplify.h`. This module ports its
`simplify_mesh`: each vertex gets the quadric of the planes of its
triangles, and edges collapse, cheapest first by rounds, until few enough
triangles are left. The threshold of round i is 1e-9 (i + 3)^7. An edge on
the border of the mesh does not collapse, and neither does one whose
collapse would flip a neighbor or make a sliver. The work is in `Float64`,
as there, and each product is rounded before it is summed, as the C++
rounds it, so the same edges collapse.

ThreeMojo's `geometries.simplify.simplify` is three.js's
`SimplifyModifier`, which is Melax's algorithm and gives another mesh. So
it is not reused here.

**Differences from CARLA.** CARLA leaves each triangle's attribute flags
unset, so a triangle may or may not carry texture coordinates by chance.
This port gives every triangle none, as CARLA's mesh has none to give. A
mesh with fewer than two indices, or an index that names no vertex, is
refused: CARLA reads out of bounds there. So is a negative or infinite
rate, which asks for no number of triangles.
"""

from extensions.carla.mesh import CarlaMesh
from loaders.js_number import js_pow
from math.vector3 import Vector3
from std.benchmark import black_box
from std.math import isfinite, isnan, sqrt


def _m(a: Float64, b: Float64) -> Float64:
    """Return a product rounded on its own, before a sum uses it.

    Mojo contracts `a * b + c` into one fused multiply-add, which rounds
    once where the C++ rounds twice. A quadric's determinant is a
    difference of near-equal products, so that last bit decides whether it
    is zero, and so which edges collapse. The barrier keeps each product a
    value of its own, as in `math.noise`.
    """
    return black_box(a * b)


@fieldwise_init
struct _P(ImplicitlyCopyable):
    var x: Float64
    var y: Float64
    var z: Float64

    def __add__(self, o: Self) -> Self:
        return _P(self.x + o.x, self.y + o.y, self.z + o.z)

    def __sub__(self, o: Self) -> Self:
        return _P(self.x - o.x, self.y - o.y, self.z - o.z)

    def half(self) -> Self:
        return _P(self.x / 2, self.y / 2, self.z / 2)

    def dot(self, o: Self) -> Float64:
        return _m(o.x, self.x) + _m(o.y, self.y) + _m(o.z, self.z)

    def cross(self, b: Self) -> Self:
        return _P(
            _m(self.y, b.z) - _m(self.z, b.y),
            _m(self.z, b.x) - _m(self.x, b.z),
            _m(self.x, b.y) - _m(self.y, b.x),
        )

    def normalized(self) -> Self:
        var square = sqrt(
            _m(self.x, self.x) + _m(self.y, self.y) + _m(self.z, self.z)
        )
        return _P(self.x / square, self.y / square, self.z / square)


comptime _Q = SIMD[DType.float64, 16]


def _fmin(a: Float64, b: Float64) -> Float64:
    """C's `fmin`: a NaN loses to a number."""
    if isnan(a):
        return b
    if isnan(b):
        return a
    return min(a, b)


def _plane(a: Float64, b: Float64, c: Float64, d: Float64) -> _Q:
    return _Q(
        a * a, a * b, a * c, a * d, b * b, b * c, b * d, c * c, c * d, d * d,
        0, 0, 0, 0, 0, 0,
    )  # fmt: skip


def _det(
    m: _Q,
    a11: Int,
    a12: Int,
    a13: Int,
    a21: Int,
    a22: Int,
    a23: Int,
    a31: Int,
    a32: Int,
    a33: Int,
) -> Float64:
    return (
        _m(m[a11] * m[a22], m[a33])
        + _m(m[a13] * m[a21], m[a32])
        + _m(m[a12] * m[a23], m[a31])
        - _m(m[a13] * m[a22], m[a31])
        - _m(m[a11] * m[a23], m[a32])
        - _m(m[a12] * m[a21], m[a33])
    )


def _vertex_error(q: _Q, x: Float64, y: Float64, z: Float64) -> Float64:
    return (
        _m(q[0] * x, x)
        + _m(2 * q[1] * x, y)
        + _m(2 * q[2] * x, z)
        + _m(2 * q[3], x)
        + _m(q[4] * y, y)
        + _m(2 * q[5] * y, z)
        + _m(2 * q[6], y)
        + _m(q[7] * z, z)
        + _m(2 * q[8], z)
        + q[9]
    )


@fieldwise_init
struct _Triangle(Copyable, Movable):
    var v: SIMD[DType.int64, 4]
    var err: SIMD[DType.float64, 4]
    var deleted: Bool
    var dirty: Bool
    var n: _P


@fieldwise_init
struct _Vertex(Copyable, Movable):
    var p: _P
    var tstart: Int
    var tcount: Int
    var q: _Q
    var border: Bool


@fieldwise_init
struct _Ref(ImplicitlyCopyable):
    var tid: Int
    var tvertex: Int


struct _Simplifier(Movable):
    var triangles: List[_Triangle]
    var vertices: List[_Vertex]
    var refs: List[_Ref]

    def __init__(out self):
        self.triangles = List[_Triangle]()
        self.vertices = List[_Vertex]()
        self.refs = List[_Ref]()

    def tv(self, t: Int, j: Int) -> Int:
        return Int(self.triangles[t].v[j])

    def calculate_error(self, id_v1: Int, id_v2: Int) -> Tuple[Float64, _P]:
        var q = self.vertices[id_v1].q + self.vertices[id_v2].q
        var border = self.vertices[id_v1].border and self.vertices[id_v2].border
        var det = _det(q, 0, 1, 2, 1, 4, 5, 2, 5, 7)
        if det != 0 and not border:
            var p = _P(
                -1 / det * _det(q, 1, 2, 3, 4, 5, 6, 5, 7, 8),
                1 / det * _det(q, 0, 2, 3, 1, 5, 6, 2, 7, 8),
                -1 / det * _det(q, 0, 1, 3, 1, 4, 6, 2, 5, 8),
            )
            return (_vertex_error(q, p.x, p.y, p.z), p)
        var p1 = self.vertices[id_v1].p
        var p2 = self.vertices[id_v2].p
        var p3 = (p1 + p2).half()
        var error1 = _vertex_error(q, p1.x, p1.y, p1.z)
        var error2 = _vertex_error(q, p2.x, p2.y, p2.z)
        var error3 = _vertex_error(q, p3.x, p3.y, p3.z)
        var error = _fmin(error1, _fmin(error2, error3))
        # CARLA keeps the last of the three that gives the least error.
        var p = p1
        if error2 == error:
            p = p2
        if error3 == error:
            p = p3
        return (error, p)

    def set_errors(mut self, t: Int):
        var e0 = self.calculate_error(self.tv(t, 0), self.tv(t, 1))[0]
        var e1 = self.calculate_error(self.tv(t, 1), self.tv(t, 2))[0]
        var e2 = self.calculate_error(self.tv(t, 2), self.tv(t, 0))[0]
        self.triangles[t].err = SIMD[DType.float64, 4](
            e0, e1, e2, _fmin(e0, _fmin(e1, e2))
        )

    def flipped(self, p: _P, i1: Int, v0: Int, mut deleted: List[Int]) -> Bool:
        ref vertex = self.vertices[v0]
        for k in range(vertex.tcount):  # pragma: no branch
            var r = self.refs[vertex.tstart + k]
            ref t = self.triangles[r.tid]
            if t.deleted:
                continue
            var s = r.tvertex
            var id1 = Int(t.v[(s + 1) % 3])
            var id2 = Int(t.v[(s + 2) % 3])
            if id1 == i1 or id2 == i1:
                deleted[k] = 1
                continue
            var d1 = (self.vertices[id1].p - p).normalized()
            var d2 = (self.vertices[id2].p - p).normalized()
            if abs(d1.dot(d2)) > 0.999:
                return True
            var n = d1.cross(d2).normalized()
            deleted[k] = 0
            if n.dot(t.n) < 0.2:
                return True
        return False

    def update_triangles(
        mut self,
        i0: Int,
        v: Int,
        deleted: List[Int],
        mut deleted_triangles: Int,
    ):
        var tstart = self.vertices[v].tstart
        var tcount = self.vertices[v].tcount
        for k in range(tcount):  # pragma: no branch
            var r = self.refs[tstart + k]
            if self.triangles[r.tid].deleted:
                continue
            if deleted[k] != 0:
                self.triangles[r.tid].deleted = True
                deleted_triangles += 1
                continue
            self.triangles[r.tid].v[r.tvertex] = Int64(i0)
            self.triangles[r.tid].dirty = True
            self.set_errors(r.tid)
            self.refs.append(r)

    def update_mesh(mut self, iteration: Int):
        if iteration > 0:
            var kept = List[_Triangle]()
            for t in self.triangles:  # pragma: no branch
                if not t.deleted:
                    kept.append(t.copy())
            self.triangles = kept^
        for i in range(len(self.vertices)):  # pragma: no branch
            self.vertices[i].tstart = 0
            self.vertices[i].tcount = 0
        for t in range(len(self.triangles)):  # pragma: no branch
            for j in range(3):  # pragma: no branch
                self.vertices[self.tv(t, j)].tcount += 1
        var tstart = 0
        for i in range(len(self.vertices)):  # pragma: no branch
            self.vertices[i].tstart = tstart
            tstart += self.vertices[i].tcount
            self.vertices[i].tcount = 0
        self.refs = List[_Ref](length=len(self.triangles) * 3, fill=_Ref(0, 0))
        for t in range(len(self.triangles)):  # pragma: no branch
            for j in range(3):  # pragma: no branch
                var v = self.tv(t, j)
                self.refs[
                    self.vertices[v].tstart + self.vertices[v].tcount
                ] = _Ref(t, j)
                self.vertices[v].tcount += 1
        if iteration != 0:
            return
        # The border: a vertex that only one triangle of a neighbor shares.
        for i in range(len(self.vertices)):  # pragma: no branch
            self.vertices[i].border = False
        for i in range(len(self.vertices)):  # pragma: no branch
            var vcount = List[Int]()
            var vids = List[Int]()
            for j in range(self.vertices[i].tcount):
                var t = self.refs[self.vertices[i].tstart + j].tid
                for k in range(3):  # pragma: no branch
                    var id = self.tv(t, k)
                    var ofs = 0
                    while ofs < len(vcount) and vids[ofs] != id:
                        ofs += 1
                    if ofs == len(vcount):
                        vcount.append(1)
                        vids.append(id)
                    else:
                        vcount[ofs] += 1
            for j in range(len(vcount)):
                if vcount[j] == 1:
                    self.vertices[vids[j]].border = True
        for i in range(len(self.vertices)):  # pragma: no branch
            self.vertices[i].q = _Q(0)
        for t in range(len(self.triangles)):  # pragma: no branch
            var p0 = self.vertices[self.tv(t, 0)].p
            var p1 = self.vertices[self.tv(t, 1)].p
            var p2 = self.vertices[self.tv(t, 2)].p
            var n = (p1 - p0).cross(p2 - p0).normalized()
            self.triangles[t].n = n
            var plane = _plane(n.x, n.y, n.z, -n.dot(p0))
            for j in range(3):  # pragma: no branch
                self.vertices[self.tv(t, j)].q += plane
        for t in range(len(self.triangles)):  # pragma: no branch
            self.set_errors(t)

    def compact_mesh(mut self):
        for i in range(len(self.vertices)):
            self.vertices[i].tcount = 0
        var kept = List[_Triangle]()
        for t in self.triangles:
            if not t.deleted:
                for j in range(3):  # pragma: no branch
                    self.vertices[Int(t.v[j])].tcount = 1
                kept.append(t.copy())
        self.triangles = kept^
        var dst = 0
        for i in range(len(self.vertices)):
            if self.vertices[i].tcount != 0:
                self.vertices[i].tstart = dst
                self.vertices[dst].p = self.vertices[i].p
                dst += 1
        for t in range(len(self.triangles)):
            for j in range(3):  # pragma: no branch
                self.triangles[t].v[j] = Int64(
                    self.vertices[self.tv(t, j)].tstart
                )
        while len(self.vertices) > dst:
            _ = self.vertices.pop()

    def simplify_mesh(mut self, target_count: Int, agressiveness: Float64 = 7):
        for t in range(len(self.triangles)):
            self.triangles[t].deleted = False
        var deleted_triangles = 0
        var deleted0 = List[Int]()
        var deleted1 = List[Int]()
        var triangle_count = len(self.triangles)
        for iteration in range(100):  # pragma: no branch
            if triangle_count - deleted_triangles <= target_count:
                break
            if iteration % 5 == 0:
                self.update_mesh(iteration)
            for t in range(len(self.triangles)):  # pragma: no branch
                self.triangles[t].dirty = False
            var threshold = 0.000000001 * js_pow(
                Float64(iteration + 3), agressiveness
            )
            # The loop runs only while triangles are left.
            for i in range(len(self.triangles)):  # pragma: no branch
                if self.triangles[i].err[3] > threshold:
                    continue
                if self.triangles[i].deleted:
                    continue
                if self.triangles[i].dirty:
                    continue
                for j in range(3):  # pragma: no branch
                    if not (self.triangles[i].err[j] < threshold):
                        continue
                    var i0 = self.tv(i, j)
                    var i1 = self.tv(i, (j + 1) % 3)
                    if self.vertices[i0].border or self.vertices[i1].border:
                        continue
                    var p = self.calculate_error(i0, i1)[1]
                    deleted0.resize(self.vertices[i0].tcount, 0)
                    deleted1.resize(self.vertices[i1].tcount, 0)
                    if self.flipped(p, i1, i0, deleted0):
                        continue
                    if self.flipped(p, i0, i1, deleted1):
                        continue
                    self.vertices[i0].p = p
                    self.vertices[i0].q = (
                        self.vertices[i1].q + self.vertices[i0].q
                    )
                    var tstart = len(self.refs)
                    self.update_triangles(i0, i0, deleted0, deleted_triangles)
                    self.update_triangles(i0, i1, deleted1, deleted_triangles)
                    var tcount = len(self.refs) - tstart
                    if tcount <= self.vertices[i0].tcount:
                        var base = self.vertices[i0].tstart
                        # A collapsed vertex keeps a triangle: every
                        # vertex that may collapse is inside a closed fan,
                        # and only two of its triangles hold the edge.
                        for k in range(tcount):  # pragma: no branch
                            self.refs[base + k] = self.refs[tstart + k]
                    else:
                        self.vertices[i0].tstart = tstart
                    self.vertices[i0].tcount = tcount
                    break
                if triangle_count - deleted_triangles <= target_count:
                    break
        self.compact_mesh()


@fieldwise_init
struct Simplification(ImplicitlyCopyable):
    """A simplification rate, CARLA's `geom::Simplification`."""

    # The share of the triangles to keep, from 0 to 1.
    var simplification_percentage: Float32

    def simplificate(self, mut mesh: CarlaMesh) raises:
        """Simplify a mesh in place, `Simplificate`.

        The mesh's vertices and indices are replaced. Its normals, UVs and
        materials are kept as they are, as CARLA keeps them.

        Args:
            mesh: The mesh. Every three indices from the first make a
                triangle, and a remainder is dropped.

        Raises:
            Error: If the rate is negative or not finite, the mesh has
                fewer than two indices or an index names no vertex.
        """
        if not (
            isfinite(self.simplification_percentage)
            and self.simplification_percentage >= 0
        ):
            raise Error("A simplification rate must be finite and not negative")
        if len(mesh.indexes) < 2:
            raise Error("A mesh to simplify needs indices")
        var work = _Simplifier()
        for v in mesh.vertices:
            work.vertices.append(
                _Vertex(
                    _P(Float64(v.x), Float64(v.y), Float64(v.z)),
                    0,
                    0,
                    _Q(0),
                    False,
                )
            )
        var i = 0
        while i < len(mesh.indexes) - 2:
            var corners = SIMD[DType.int64, 4](0)
            for j in range(3):  # pragma: no branch
                var index = mesh.indexes[i + j]
                if index < 1 or index > len(mesh.vertices):
                    raise Error("A mesh index must name a vertex")
                corners[j] = Int64(index - 1)
            work.triangles.append(
                _Triangle(
                    corners,
                    SIMD[DType.float64, 4](0),
                    False,
                    False,
                    _P(0, 0, 0),
                )
            )
            i += 3
        var target_size = Float32(len(work.triangles))
        work.simplify_mesh(Int(target_size * self.simplification_percentage))
        mesh.vertices.clear()
        mesh.indexes.clear()
        for v in work.vertices:
            mesh.add_vertex(
                Vector3(Float32(v.p.x), Float32(v.p.y), Float32(v.p.z))
            )
        for t in work.triangles:
            for j in range(3):  # pragma: no branch
                mesh.indexes.append(Int(t.v[j]) + 1)
