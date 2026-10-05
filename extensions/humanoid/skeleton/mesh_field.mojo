# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A distance field of a triangle mesh.

The humanoid's layers are distance fields: the hair lies on the skin's,
and the body's skin is joined to the head's in a smooth union of
fields. A scanned head is a mesh. `MeshField` turns a mesh into a field
so it can take the sculpted skin's place.

The distance is to the nearest triangle, found through a bounding
volume hierarchy: a tree of boxes round runs of triangles, walked
nearest box first, with every box farther than the best triangle so far
left out. The sign is the side of the surface the point is on, read
against the normal at the nearest point, blended from the three
corners' normals so an edge or a corner has no wrong side. A closed or
nearly closed mesh has a clean inside; far from an open edge the sign
means little.

This is not a three.js port. See Extensions.

    var field = MeshField(points, triangles)
    var d = field.distance(Vector3(0, 0.1, 0.2))
"""

from extensions.humanoid.skeleton.field import DistanceField
from math.vector3 import Vector3
from std.collections import Dict
from std.math import acos, iota, max, min
from std.atomic import Atomic, Ordering
from std.memory import ArcPointer, bitcast

# How many triangles a leaf of the tree holds, at most.
comptime LEAF_SIZE = 16
# How many triangles a leaf tests at once: one lane each.
comptime LANES = 16
comptime Lanes = SIMD[DType.float32, LANES]
# A lane with no triangle holds one this far off, with no area.
comptime FAR = Float32(1.0e18)
# The most nodes a walk of the tree holds waiting: two a level, for a
# tree deeper than any mesh that fits in memory.
comptime STACK_SIZE = 128
# Which part of a triangle a nearest point lies on: its face, a corner,
# or an edge. An edge's index among a triangle's normals is its code
# less `ON_AB`.
comptime ON_FACE = 0
comptime ON_A = 1
comptime ON_B = 2
comptime ON_C = 3
comptime ON_AB = 4
comptime ON_BC = 5
comptime ON_CA = 6


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of `a` and `b`."""
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _closest_on_flat_triangle(
    p: Vector3, a: Vector3, b: Vector3, c: Vector3
) -> Tuple[Vector3, Float32, Float32, Int]:
    """Reduce a zero-area triangle to its longest segment, or a point."""
    var ab = b - a
    var ac = c - a
    var bc = c - b
    var ab2 = ab.dot(ab)
    var ac2 = ac.dot(ac)
    var bc2 = bc.dot(bc)
    if max(ab2, max(ac2, bc2)) == 0:
        return (a, Float32(0), Float32(0), ON_A)
    if ab2 >= ac2 and ab2 >= bc2:
        var t = min(Float32(1), max(Float32(0), (p - a).dot(ab) / ab2))
        var part = ON_AB
        if t == 0:
            part = ON_A
        elif t == 1:
            part = ON_B
        return (a + ab * t, t, Float32(0), part)
    if ac2 >= bc2:
        var t = min(Float32(1), max(Float32(0), (p - a).dot(ac) / ac2))
        var part = ON_CA
        if t == 0:
            part = ON_A
        elif t == 1:
            part = ON_C
        return (a + ac * t, Float32(0), t, part)
    var t = min(Float32(1), max(Float32(0), (p - b).dot(bc) / bc2))
    var part = ON_BC
    if t == 0:
        part = ON_B
    elif t == 1:
        part = ON_C
    return (b + bc * t, 1 - t, t, part)


def closest_on_triangle(
    p: Vector3, a: Vector3, b: Vector3, c: Vector3
) -> Tuple[Vector3, Float32, Float32, Int]:
    """Return the nearest point of a triangle to `p`, its weights on `b`
    and `c`, and which part of the triangle it lies on.

    Ericson's "Real-Time Collision Detection", 5.1.5: the regions of the
    three corners, then the three edges, then the face.

    Args:
        p: The point.
        a: One corner.
        b: The next.
        c: The last.

    Returns:
        The nearest point; the barycentric weights of `b` and `c`, the
        weight of `a` being one less the two; and the part: `ON_FACE`,
        `ON_A`, `ON_B`, `ON_C`, `ON_AB`, `ON_BC` or `ON_CA`.
    """
    var ab = b - a
    var ac = c - a
    var area = _cross(ab, ac)
    if area.dot(area) == 0:
        return _closest_on_flat_triangle(p, a, b, c)
    var ap = p - a
    var d1 = ab.dot(ap)
    var d2 = ac.dot(ap)
    if d1 <= 0 and d2 <= 0:
        return (a, Float32(0), Float32(0), ON_A)
    var bp = p - b
    var d3 = ab.dot(bp)
    var d4 = ac.dot(bp)
    if d3 >= 0 and d4 <= d3:
        return (b, Float32(1), Float32(0), ON_B)
    var vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        var v = d1 / (d1 - d3)
        return (a + ab * v, v, Float32(0), ON_AB)
    var cp = p - c
    var d5 = ab.dot(cp)
    var d6 = ac.dot(cp)
    if d6 >= 0 and d5 <= d6:
        return (c, Float32(0), Float32(1), ON_C)
    var vb = d5 * d2 - d1 * d6
    # Past the tests above, d2 >= 0 here, and on the BC test below both
    # edge terms are too; the weights are clamped against rounding.
    if vb <= 0 and d6 <= 0:
        var w = min(Float32(1), max(Float32(0), d2 / (d2 - d6)))
        return (a + ac * w, Float32(0), w, ON_CA)
    var va = d3 * d6 - d5 * d4
    if va <= 0:
        var w = min(
            Float32(1), max(Float32(0), (d4 - d3) / ((d4 - d3) + (d5 - d6)))
        )
        return (b + (c - b) * w, 1 - w, w, ON_BC)
    var denom = 1 / (va + vb + vc)
    var v = vb * denom
    var w = vc * denom
    return (a + ab * v + ac * w, v, w, ON_FACE)


def _box_gap(low: Vector3, high: Vector3, p: Vector3) -> Float32:
    """Return the squared distance from `p` to a box, zero inside."""
    var dx = max(max(low.x - p.x, p.x - high.x), 0)
    var dy = max(max(low.y - p.y, p.y - high.y), 0)
    var dz = max(max(low.z - p.z, p.z - high.z), 0)
    return dx * dx + dy * dy + dz * dz


@fieldwise_init
struct _Leaf(Copyable, Movable):
    """A leaf's triangles, one a lane, ready to measure against a point.

    For each triangle: its first corner `a`; its edges `ab = b - a`,
    `bc = c - b` and `ca = a - c`; each edge's inward normal in the
    triangle's plane; the plane's normal `n`; and the reciprocal squared
    lengths of the three edges and of `n`, zero where one is zero.
    """

    var ids: SIMD[DType.int32, LANES]
    var ax: Lanes
    var ay: Lanes
    var az: Lanes
    var abx: Lanes
    var aby: Lanes
    var abz: Lanes
    var bcx: Lanes
    var bcy: Lanes
    var bcz: Lanes
    var cax: Lanes
    var cay: Lanes
    var caz: Lanes
    var iabx: Lanes
    var iaby: Lanes
    var iabz: Lanes
    var ibcx: Lanes
    var ibcy: Lanes
    var ibcz: Lanes
    var icax: Lanes
    var icay: Lanes
    var icaz: Lanes
    var nx: Lanes
    var ny: Lanes
    var nz: Lanes
    var sab: Lanes
    var sbc: Lanes
    var sca: Lanes
    var sn: Lanes

    def nearest(self, p: Vector3) -> Tuple[Float32, Int]:
        """Return the least squared distance from `p` to the leaf's
        triangles, and the lane it is in.

        A point whose foot on a triangle's plane lies inside all three
        edges is its plane's distance away; any other is its nearest
        edge's. The test is Inigo Quilez's, on every lane at once.
        """
        var pax = p.x - self.ax
        var pay = p.y - self.ay
        var paz = p.z - self.az
        var pbx = pax - self.abx
        var pby = pay - self.aby
        var pbz = paz - self.abz
        var pcx = pbx - self.bcx
        var pcy = pby - self.bcy
        var pcz = pbz - self.bcz
        var inside = (
            (self.iabx * pax + self.iaby * pay + self.iabz * paz).gt(0)
            & (self.ibcx * pbx + self.ibcy * pby + self.ibcz * pbz).gt(0)
            & (self.icax * pcx + self.icay * pcy + self.icaz * pcz).gt(0)
        )
        var plane = self.nx * pax + self.ny * pay + self.nz * paz
        var t1 = (
            (self.abx * pax + self.aby * pay + self.abz * paz) * self.sab
        ).clamp(0, 1)
        var t2 = (
            (self.bcx * pbx + self.bcy * pby + self.bcz * pbz) * self.sbc
        ).clamp(0, 1)
        var t3 = (
            (self.cax * pcx + self.cay * pcy + self.caz * pcz) * self.sca
        ).clamp(0, 1)
        var e1 = _square(
            self.abx * t1 - pax, self.aby * t1 - pay, self.abz * t1 - paz
        )
        var e2 = _square(
            self.bcx * t2 - pbx, self.bcy * t2 - pby, self.bcz * t2 - pbz
        )
        var e3 = _square(
            self.cax * t3 - pcx, self.cay * t3 - pcy, self.caz * t3 - pcz
        )
        var d = inside.select(plane * plane * self.sn, min(e1, min(e2, e3)))
        var least = d.reduce_min()
        var lane = (
            d.eq(least)
            .select(iota[DType.int32, LANES](), SIMD[DType.int32, LANES](LANES))
            .reduce_min()
        )
        return (least, Int(lane))


def _square(x: Lanes, y: Lanes, z: Lanes) -> Lanes:
    """Return the squared length of each lane's vector."""
    return x * x + y * y + z * z


def _inverse(value: Float32) -> Float32:
    """Return one over `value`, or zero for zero."""
    return 1 / value if value > 0 else Float32(0)


struct MeshTree(Movable):
    """A triangle mesh and the bounding volume hierarchy over it."""

    var points: List[Vector3]
    var triangles: List[Int]
    # The pseudo-normals that sign the distance, after Baerentzen and
    # Aanaes: each triangle's face normal; the sum of the two faces'
    # normals at each of its edges, three a triangle; and at each vertex
    # the faces' normals weighted by their angles there. Whichever part
    # of a triangle the nearest point lies on, its normal says the side.
    var faces: List[Vector3]
    var edges: List[Vector3]
    var normals: List[Vector3]
    # The tree: each node's box, its children or its run of triangles.
    # A leaf has no children; its run is `order[first:end]`.
    var low: List[Vector3]
    var high: List[Vector3]
    var left: List[Int]
    var right: List[Int]
    var first: List[Int]
    var end: List[Int]
    var order: List[Int]
    # Each leaf's triangles, ready to measure, and each node's leaf, or
    # minus one for a node with children.
    var leaves: List[_Leaf]
    var leaf: List[Int]
    # The whole mesh's box.
    var box_low: Vector3
    var box_high: Vector3

    def __init__(
        out self, var points: List[Vector3], var triangles: List[Int]
    ) raises:
        """Build the tree over a mesh.

        Args:
            points: The vertices, in meters.
            triangles: Three vertex indices a triangle, wound counter-
                clockwise seen from outside.

        Raises:
            Error: If there are no triangles, or an index is out of range.
        """
        if len(triangles) == 0 or len(triangles) % 3 != 0:
            raise Error("A mesh field needs whole triangles")
        for index in range(len(triangles)):  # pragma: no branch
            if triangles[index] < 0 or triangles[index] >= len(points):
                raise Error("A mesh field's triangle names no vertex")
        var count = len(triangles) // 3
        self.faces = List[Vector3](capacity=count)
        self.normals = List[Vector3](length=len(points), fill=Vector3(0, 0, 0))
        for t in range(count):  # pragma: no branch
            var n = _cross(
                points[triangles[t * 3 + 1]] - points[triangles[t * 3]],
                points[triangles[t * 3 + 2]] - points[triangles[t * 3]],
            )
            n.normalize()
            self.faces.append(n)
            for c in range(3):  # pragma: no branch
                var v = triangles[t * 3 + c]
                var e1 = points[triangles[t * 3 + (c + 1) % 3]] - points[v]
                var e2 = points[triangles[t * 3 + (c + 2) % 3]] - points[v]
                e1.normalize()
                e2.normalize()
                var angle = acos(max(Float32(-1), min(Float32(1), e1.dot(e2))))
                self.normals[v] = self.normals[v] + n * angle
        # Each edge's two faces, found through a key of its two ends. An
        # edge with one face is an open edge: its normal is that face's.
        self.edges = List[Vector3](length=count * 3, fill=Vector3(0, 0, 0))
        var seen = Dict[Int, Int]()
        for t in range(count):  # pragma: no branch
            for k in range(3):  # pragma: no branch
                var a = triangles[t * 3 + k]
                var b = triangles[t * 3 + (k + 1) % 3]
                var key = min(a, b) * len(points) + max(a, b)
                var slot = t * 3 + k
                self.edges[slot] = self.faces[t] * 2
                var other = seen.get(key, -1)
                if other < 0:
                    seen[key] = slot
                else:
                    var both = self.faces[t] + self.faces[other // 3]
                    self.edges[slot] = both
                    self.edges[other] = both
        self.points = points^
        self.triangles = triangles^
        self.low = List[Vector3]()
        self.high = List[Vector3]()
        self.left = List[Int]()
        self.right = List[Int]()
        self.first = List[Int]()
        self.end = List[Int]()
        self.order = List[Int](capacity=count)
        for t in range(count):  # pragma: no branch
            self.order.append(t)
        var centers = List[Vector3](capacity=count)
        for t in range(count):  # pragma: no branch
            centers.append(
                (
                    self.points[self.triangles[t * 3]]
                    + self.points[self.triangles[t * 3 + 1]]
                    + self.points[self.triangles[t * 3 + 2]]
                )
                / 3
            )
        self.box_low = Vector3(0, 0, 0)
        self.box_high = Vector3(0, 0, 0)
        self.leaves = List[_Leaf]()
        self.leaf = List[Int]()
        # Split runs in half until each is a leaf, with no recursion: a
        # run is sorted along its box's longest side and cut at its
        # median, so each half is a compact cluster.
        _ = self._node(0, count)
        var pending: List[Int] = [0]
        while len(pending) > 0:
            var node = pending.pop()
            var first = self.first[node]
            var end = self.end[node]
            if end - first <= LEAF_SIZE:
                continue
            _sort_run(self.order, centers, first, end, self._axis(node))
            var middle = (first + end) // 2
            var l = self._node(first, middle)
            var r = self._node(middle, end)
            self.left[node] = l
            self.right[node] = r
            pending.append(l)
            pending.append(r)
        self.leaf = List[Int](length=len(self.low), fill=-1)
        for node in range(len(self.low)):  # pragma: no branch
            if self.left[node] < 0:
                self.leaf[node] = len(self.leaves)
                self.leaves.append(self._pack(node))
        self.box_low = self.low[0]
        self.box_high = self.high[0]

    def _node(mut self, first: Int, end: Int) -> Int:
        """Add a node over `order[first:end]` and return its index."""
        var low = Vector3(3.0e38, 3.0e38, 3.0e38)
        var high = Vector3(-3.0e38, -3.0e38, -3.0e38)
        for i in range(first * 3, end * 3):  # pragma: no branch
            var p = self.points[self.triangles[self.order[i // 3] * 3 + i % 3]]
            low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        self.low.append(low)
        self.high.append(high)
        self.left.append(-1)
        self.right.append(-1)
        self.first.append(first)
        self.end.append(end)
        return len(self.low) - 1

    def _pack(self, node: Int) -> _Leaf:
        """Return a leaf's triangles, one a lane; the lanes past its run
        hold far triangles with no area."""
        var ids = SIMD[DType.int32, LANES](0)
        var v = List[Lanes](length=28, fill=Lanes(0))
        for lane in range(LANES):  # pragma: no branch
            var a = Vector3(FAR, FAR, FAR)
            var b = a
            var c = a
            var i = self.first[node] + lane
            if i < self.end[node]:
                var t = self.order[i]
                ids[lane] = Int32(t)
                a = self.points[self.triangles[t * 3]]
                b = self.points[self.triangles[t * 3 + 1]]
                c = self.points[self.triangles[t * 3 + 2]]
            var ab = b - a
            var bc = c - b
            var ca = a - c
            var n = _cross(ab, c - a)
            var sides: List[Vector3] = [
                a,
                ab,
                bc,
                ca,
                _cross(n, ab),
                _cross(n, bc),
                _cross(n, ca),
                n,
            ]
            for k in range(8):  # pragma: no branch
                v[k * 3][lane] = sides[k].x
                v[k * 3 + 1][lane] = sides[k].y
                v[k * 3 + 2][lane] = sides[k].z
            v[24][lane] = _inverse(ab.dot(ab))
            v[25][lane] = _inverse(bc.dot(bc))
            v[26][lane] = _inverse(ca.dot(ca))
            v[27][lane] = _inverse(n.dot(n))
        return _Leaf(
            ids,
            v[0],
            v[1],
            v[2],
            v[3],
            v[4],
            v[5],
            v[6],
            v[7],
            v[8],
            v[9],
            v[10],
            v[11],
            v[12],
            v[13],
            v[14],
            v[15],
            v[16],
            v[17],
            v[18],
            v[19],
            v[20],
            v[21],
            v[22],
            v[23],
            v[24],
            v[25],
            v[26],
            v[27],
        )

    def pseudo_normal(self, t: Int, part: Int) -> Vector3:
        """Return the normal that signs a distance to part of a triangle.

        Args:
            t: The triangle.
            part: Which part of it, from `closest_on_triangle`.

        Returns:
            The face's normal, an edge's or a corner's; not unit length.
        """
        if part == ON_FACE:
            return self.faces[t]
        if part >= ON_AB:
            return self.edges[t * 3 + part - ON_AB]
        return self.normals[self.triangles[t * 3 + part - ON_A]]

    def _axis(self, node: Int) -> Int:
        """Return the longest side of a node's box: 0, 1 or 2."""
        var size = self.high[node] - self.low[node]
        if size.y > size.x and size.y >= size.z:
            return 1
        if size.z > size.x:
            return 2
        return 0

    def nearest(
        self, p: Vector3, start: Int
    ) -> Tuple[Int, Vector3, Float32, Float32, Int]:
        """Return the nearest triangle to `p`, the nearest point on it, the
        point's weights on the triangle's second and third corners, and
        the part of the triangle it lies on.

        The search starts from triangle `start`: a triangle near `p`
        bounds the search at once, and the walk leaves out every box
        farther than it.

        Args:
            p: The point.
            start: A triangle to start from, any one.

        Returns:
            The triangle's index, the point, two weights and the part; see
            `closest_on_triangle`.
        """
        var first = closest_on_triangle(
            p,
            self.points[self.triangles[start * 3]],
            self.points[self.triangles[start * 3 + 1]],
            self.points[self.triangles[start * 3 + 2]],
        )
        var gap = first[0] - p
        var best = gap.dot(gap)
        var found = start
        # The walk holds at most two nodes a level of the tree.
        # This is a scalar-indexed stack, not a vector calculation. An array
        # avoids copying a wide SIMD value for each dynamic push and pop.
        var stack = Array[Int32, STACK_SIZE](fill=0)
        var top = 1
        while top > 0:
            top -= 1
            var node = Int(stack[top])
            if _box_gap(self.low[node], self.high[node], p) >= best:
                continue
            if self.left[node] < 0:
                var hit = self.leaves[self.leaf[node]].nearest(p)
                if hit[0] < best:
                    best = hit[0]
                    found = Int(self.leaves[self.leaf[node]].ids[hit[1]])
                continue
            # The nearer child last, so it is walked first.
            var l = self.left[node]
            var r = self.right[node]
            if _box_gap(self.low[l], self.high[l], p) < _box_gap(
                self.low[r], self.high[r], p
            ):
                stack[top] = Int32(r)
                stack[top + 1] = Int32(l)
            else:
                stack[top] = Int32(l)
                stack[top + 1] = Int32(r)
            top += 2
        var hit = closest_on_triangle(
            p,
            self.points[self.triangles[found * 3]],
            self.points[self.triangles[found * 3 + 1]],
            self.points[self.triangles[found * 3 + 2]],
        )
        return (found, hit[0], hit[1], hit[2], hit[3])


struct MeshField(Copyable, DistanceField, Movable):
    """The signed distance to a triangle mesh.

    Copies share one tree, so a copy for each thread costs nothing.
    """

    var tree: ArcPointer[MeshTree]
    # The triangle the last search found. Searches near one another
    # start from it; copies and threads share it, as a hint.
    var hint: ArcPointer[Atomic[Int64]]
    var box_low: Vector3
    var box_high: Vector3

    def __init__(
        out self, var points: List[Vector3], var triangles: List[Int]
    ) raises:
        """Build the tree over a mesh.

        Args:
            points: The vertices, in meters.
            triangles: Three vertex indices a triangle, wound counter-
                clockwise seen from outside.

        Raises:
            Error: If there are no triangles, or an index is out of range.
        """
        var tree = MeshTree(points^, triangles^)
        self.box_low = tree.box_low
        self.box_high = tree.box_high
        self.tree = ArcPointer(tree^)
        self.hint = ArcPointer(Atomic[Int64](0))

    def count(self) -> Int:
        """Return how many vertices the mesh has."""
        return len(self.tree[].points)

    def point(self, index: Int) -> Vector3:
        """Return one vertex, in meters.

        Args:
            index: Which vertex, from zero.

        Returns:
            Its position.
        """
        return self.tree[].points[index]

    def nearest(self, p: Vector3) -> Tuple[Int, Vector3, Float32, Float32, Int]:
        """Return the nearest triangle to `p`, the nearest point on it, the
        point's weights on the triangle's second and third corners, and
        the part of the triangle it lies on.

        Args:
            p: The point.

        Returns:
            The triangle's index, the point, two weights and the part; see
            `closest_on_triangle`.
        """
        var hit = self.tree[].nearest(
            p, Int(self.hint[].load[ordering=Ordering.RELAXED]())
        )
        self.hint[].store[ordering=Ordering.RELAXED](Int64(hit[0]))
        return hit

    def distance(self, point: Vector3) -> Float32:
        """Return the signed distance to the mesh, in meters: negative on
        the side its normals point away from."""
        var hit = self.nearest(point)
        var n = self.tree[].pseudo_normal(hit[0], hit[4])
        var d = point - hit[1]
        var gap = d.length()
        return gap if d.dot(n) >= 0 else -gap


def _sort_run(
    mut order: List[Int],
    centers: List[Vector3],
    first: Int,
    end: Int,
    axis: Int,
):
    """Sort `order[first:end]` by the triangles' centers along `axis`.

    Each triangle's key and index are packed into one integer that sorts
    as the key does: the key's bits, turned so a negative float sorts
    below a positive one, above the index.
    """
    var packed = List[UInt64](capacity=end - first)
    for i in range(first, end):  # pragma: no branch
        var c = centers[order[i]]
        var k = c.x
        if axis == 1:
            k = c.y
        elif axis == 2:
            k = c.z
        var bits = bitcast[DType.uint32](k)
        if bits >> 31 == 1:
            bits = ~bits
        else:
            bits = bits | 0x80000000
        packed.append((UInt64(bits) << 32) | UInt64(order[i]))
    sort(packed)
    for i in range(len(packed)):  # pragma: no branch
        order[first + i] = Int(packed[i] & 0xFFFFFFFF)
