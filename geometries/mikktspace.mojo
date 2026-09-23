# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""MikkTSpace tangents, from Morten S. Mikkelsen's `mikktspace.c` and
three.js's `computeMikkTSpaceTangents` in
`examples/jsm/utils/BufferGeometryUtils.js`.

MikkTSpace is the tangent frame that normal map bakers use, so a normal
map baked by one tool shades the same in another. three.js runs it as a
WebAssembly build of a Rust port of the C. This is a port of the C
itself, function for function, in floats as the C has it.

## How it works

The vertices are welded first: two corners that agree on position,
normal and texture coordinate, bit for bit, are one vertex. A triangle
with two corners in one place is degenerate and sits out. Each other
triangle gets the directions in which `u` and `v` grow across it. The
triangles round each vertex are then put in groups: neighbors across an
edge that agree on which way the texture is mirrored. Each group's
directions are made square to the vertex's normal and averaged, each
weighted by the angle of its triangle at the vertex. A degenerate
triangle takes the frame of a good one that shares its vertex.

The tangent is the averaged `u` direction. Its fourth number is one
where the texture is not mirrored and minus one where it is, and three.js
turns the sign round by default for glTF's convention.

## What this port leaves out

The C takes quads as well as triangles and cuts each quad along its
shorter diagonal. three.js only ever gives it triangles, so the quad
paths are left out, and so is the average a quad's shared corner gets.

The C's `genTangSpace` takes an angular threshold, and so does
`generate_tangents`: two triangles in a group whose directions turn by
more than it get frames of their own. three.js uses the default of 180
degrees, which lets every pair through.

## As three.js does it

An indexed geometry is made non-indexed first, as MikkTSpace needs, and
the result replaces it, as three.js's `geometry.copy` does.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
)
from std.math import acos, cos, isfinite, isnan, sqrt
from units.si import Angle, DEGREE

comptime Vec = SIMD[DType.float32, 4]

# Flags on a triangle, as the C names them.
comptime MARK_DEGENERATE = 1
comptime GROUP_WITH_ANY = 4
comptime ORIENT_PRESERVING = 8

# The seed of the C's quicksort, `INTERNAL_RND_SORT_SEED`.
comptime SORT_SEED = UInt32(39871946)
# How many cells the welding grid has, the C's `g_iCells`.
comptime CELLS = 2048
# The smallest normal float, C's `FLT_MIN`.
comptime FLT_MIN = Float32(1.17549435e-38)


def _v(x: Float32, y: Float32, z: Float32) -> Vec:
    """Return a vector of three floats."""
    return Vec(x, y, z, 0)


def _veq(a: Vec, b: Vec) -> Bool:
    """Return True if two vectors are equal, number for number."""
    return a[0] == b[0] and a[1] == b[1] and a[2] == b[2]


def _dot(a: Vec, b: Vec) -> Float32:
    """Return the dot product, the C's `vdot`."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _length(a: Vec) -> Float32:
    """Return the length, the C's `Length`."""
    return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def _normalize(a: Vec) -> Vec:
    """Return the vector over its length, the C's `Normalize`."""
    return a * (1 / _length(a))


def _not_zero(x: Float32) -> Bool:
    """Return True if a number is more than the smallest float, the C's
    `NotZero`."""
    return abs(x) > FLT_MIN


def _vnot_zero(a: Vec) -> Bool:
    """Return True if any number of a vector is not zero, the C's
    `VNotZero`."""
    return _not_zero(a[0]) or _not_zero(a[1]) or _not_zero(a[2])


def _unit_if_not_zero(a: Vec) -> Vec:
    """Return a vector made unit length, unless it is zero."""
    return _normalize(a) if _vnot_zero(a) else a


@fieldwise_init
struct _TriInfo(Copyable, Movable):
    """One triangle, the C's `STriInfo`, without its quad fields."""

    var neighbors: SIMD[DType.int64, 4]
    # The group of each corner, or -1.
    var groups: SIMD[DType.int64, 4]
    var os: Vec
    var ot: Vec
    var mag_s: Float32
    var mag_t: Float32
    var face: Int
    var flag: Int
    var offset: Int


@fieldwise_init
struct _Group(Copyable, Movable):
    """A run of triangles round one vertex, the C's `SGroup`."""

    var count: Int
    # Where in the shared buffer the triangles start.
    var start: Int
    var representative: Int
    var orient_preserving: Bool


@fieldwise_init
struct _Space(Copyable, Movable):
    """One corner's frame, the C's `STSpace`."""

    var os: Vec
    var mag_s: Float32
    var ot: Vec
    var mag_t: Float32
    var counter: Int
    var orient: Bool


def _default_space() -> _Space:
    """Return the frame the C starts every corner with."""
    return _Space(_v(1, 0, 0), 1, _v(0, 1, 0), 1, 0, False)


struct _Context(Movable):
    """The mesh the algorithm reads: three corners a face."""

    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]

    def __init__(
        out self,
        var positions: List[Float32],
        var normals: List[Float32],
        var uvs: List[Float32],
    ):
        """Hold the numbers.

        Args:
            positions: Three numbers a corner.
            normals: Three numbers a corner.
            uvs: Two numbers a corner.
        """
        self.positions = positions^
        self.normals = normals^
        self.uvs = uvs^

    def position(self, index: Int) -> Vec:
        """Return the position of a corner named by `face << 2 | vert`."""
        var at = ((index >> 2) * 3 + (index & 3)) * 3
        return _v(
            self.positions[at], self.positions[at + 1], self.positions[at + 2]
        )

    def normal(self, index: Int) -> Vec:
        """Return the normal of a corner named by `face << 2 | vert`."""
        var at = ((index >> 2) * 3 + (index & 3)) * 3
        return _v(self.normals[at], self.normals[at + 1], self.normals[at + 2])

    def texcoord(self, index: Int) -> Vec:
        """Return the texture coordinate of a corner, with a third number
        of one, as the C's `GetTexCoord` does."""
        var at = ((index >> 2) * 3 + (index & 3)) * 2
        return _v(self.uvs[at], self.uvs[at + 1], 1)

    def same_vertex(self, a: Int, b: Int) -> Bool:
        """Return True if two corners agree on position, normal and
        texture coordinate."""
        return (
            _veq(self.position(a), self.position(b))
            and _veq(self.normal(a), self.normal(b))
            and _veq(self.texcoord(a), self.texcoord(b))
        )


def _make_index(face: Int, vert: Int) -> Int:
    """Return the C's `MakeIndex`: a face and a corner in one number."""
    return (face << 2) | (vert & 3)


def _grid_cell(low: Float32, high: Float32, value: Float32) -> Int:
    """Return the welding cell a value falls in, the C's `FindGridCell`."""
    var index = Float32(CELLS) * ((value - low) / (high - low))
    if isnan(index):
        return 0
    var cell = Int(index)
    return cell if cell < CELLS else CELLS - 1


def _widest(dx: Float32, dy: Float32, dz: Float32) -> Int:
    """Return the axis a box is widest along, as the C chooses it: y if
    it beats both others, else z if it beats x, else x."""
    return 1 if (dy > dx and dy > dz) else (2 if dz > dx else 0)


def _no_room(sep: Float32, low: Float32, high: Float32) -> Bool:
    """Return True if the middle of a range is not strictly inside it."""
    return sep >= high or sep <= low


def _merge_verts_fast(
    ctx: _Context,
    mut tri_list: List[Int],
    mut tmp_verts: List[Vec],
    mut tmp_index: List[Int],
    left: Int,
    right: Int,
):
    """Weld the corners of one grid cell, the C's `MergeVertsFast`."""
    var lo = tmp_verts[left]
    var hi = tmp_verts[left]
    # A run to weld holds two corners at least: the caller and each call
    # below pass one only when `left` is less than `right`.
    for l in range(left + 1, right + 1):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            if lo[c] > tmp_verts[l][c]:
                lo[c] = tmp_verts[l][c]
            if hi[c] < tmp_verts[l][c]:
                hi[c] = tmp_verts[l][c]
    var channel = _widest(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    var sep = Float32(0.5) * (hi[channel] + lo[channel])
    if not isfinite(sep):
        return
    if _no_room(sep, lo[channel], hi[channel]):
        for l in range(left, right + 1):  # pragma: no branch
            var i = tmp_index[l]
            var index = tri_list[i]
            var l2 = left
            var found = -1
            while l2 < l and found < 0:
                var i2 = tmp_index[l2]
                if ctx.same_vertex(index, tri_list[i2]):
                    found = i2
                else:
                    l2 += 1
            if found >= 0:
                tri_list[i] = tri_list[found]
        return
    var il = left
    var ir = right
    while il < ir:
        var ready_left = False
        var ready_right = False
        while not ready_left and il < ir:
            ready_left = not (tmp_verts[il][channel] < sep)
            if not ready_left:
                il += 1
        while not ready_right and il < ir:
            ready_right = tmp_verts[ir][channel] < sep
            if not ready_right:
                ir -= 1
        if ready_left and ready_right:
            var swap_vert = tmp_verts[il]
            tmp_verts[il] = tmp_verts[ir]
            tmp_verts[ir] = swap_vert
            var swap_index = tmp_index[il]
            tmp_index[il] = tmp_index[ir]
            tmp_index[ir] = swap_index
            il += 1
            ir -= 1
    if il == ir:
        if tmp_verts[ir][channel] < sep:
            il += 1
        else:
            ir -= 1
    if left < ir:
        _merge_verts_fast(ctx, tri_list, tmp_verts, tmp_index, left, ir)
    if il < right:
        _merge_verts_fast(ctx, tri_list, tmp_verts, tmp_index, il, right)


def _weld(ctx: _Context, mut tri_list: List[Int], triangles: Int):
    """Point every corner at the first corner equal to it, the C's
    `GenerateSharedVerticesIndexList`."""
    var corners = triangles * 3
    var lo = ctx.position(tri_list[0])
    var hi = lo
    # A triangle has three corners, so this runs.
    for i in range(1, corners):  # pragma: no branch
        var p = ctx.position(tri_list[i])
        for c in range(3):  # pragma: no branch
            if lo[c] > p[c]:
                lo[c] = p[c]
            elif hi[c] < p[c]:
                hi[c] = p[c]
    var dim = hi - lo
    var channel = _widest(dim[0], dim[1], dim[2])
    var low = lo[channel]
    var high = hi[channel]
    var cells = List[Int](length=corners, fill=0)
    var counts = List[Int](length=CELLS, fill=0)
    for i in range(corners):  # pragma: no branch
        var cell = _grid_cell(low, high, ctx.position(tri_list[i])[channel])
        cells[i] = cell
        counts[cell] += 1
    var offsets = List[Int](length=CELLS, fill=0)
    for k in range(1, CELLS):  # pragma: no branch
        offsets[k] = offsets[k - 1] + counts[k - 1]
    var table = List[Int](length=corners, fill=0)
    var filled = List[Int](length=CELLS, fill=0)
    for i in range(corners):  # pragma: no branch
        var cell = cells[i]
        table[offsets[cell] + filled[cell]] = i
        filled[cell] += 1
    for k in range(CELLS):  # pragma: no branch
        var entries = counts[k]
        if entries < 2:
            continue
        var tmp_verts = List[Vec]()
        var tmp_index = List[Int]()
        for e in range(entries):  # pragma: no branch
            var i = table[offsets[k] + e]
            tmp_verts.append(ctx.position(tri_list[i]))
            tmp_index.append(i)
        _merge_verts_fast(ctx, tri_list, tmp_verts, tmp_index, 0, entries - 1)


def _degen_prologue(
    mut infos: List[_TriInfo], mut tri_list: List[Int], good: Int
):
    """Move the degenerate triangles to the back, keeping the order of the
    good ones, the C's `DegenPrologue` without its quad part.

    The C also stops if it runs out of good triangles to bring forward,
    which it says is not supposed to happen. It cannot: there are `good`
    good triangles, so one is always found ahead of a degenerate one that
    sits among the first `good`.
    """
    var next_good = 1
    for t in range(good):
        if (infos[t].flag & MARK_DEGENERATE) == 0:
            # The C keeps the larger of the two. Once a degenerate
            # triangle is met, every later `t` holds one, so a good `t`
            # comes only before it, when `next_good` is `t + 1`.
            next_good = t + 2
            continue
        while (infos[next_good].flag & MARK_DEGENERATE) != 0:
            next_good += 1
        var t1 = next_good
        next_good += 1
        for i in range(3):  # pragma: no branch
            var swap = tri_list[t * 3 + i]
            tri_list[t * 3 + i] = tri_list[t1 * 3 + i]
            tri_list[t1 * 3 + i] = swap
        var info = infos[t].copy()
        infos[t] = infos[t1].copy()
        infos[t1] = info^


def _healthy(mag_s: Float32, mag_t: Float32) -> Bool:
    """Return True if both of a triangle's magnitudes are not zero: a good
    triangle, in the C's words."""
    return _not_zero(mag_s) and _not_zero(mag_t)


def _init_tri_info(
    ctx: _Context, mut infos: List[_TriInfo], tri_list: List[Int], count: Int
):
    """Work out each good triangle's directions and flags, the C's
    `InitTriInfo` without its quad part."""
    for f in range(count):
        infos[f].neighbors = SIMD[DType.int64, 4](-1)
        infos[f].groups = SIMD[DType.int64, 4](-1)
        infos[f].os = _v(0, 0, 0)
        infos[f].ot = _v(0, 0, 0)
        infos[f].mag_s = 0
        infos[f].mag_t = 0
        infos[f].flag |= GROUP_WITH_ANY
    for f in range(count):
        var v1 = ctx.position(tri_list[f * 3])
        var v2 = ctx.position(tri_list[f * 3 + 1])
        var v3 = ctx.position(tri_list[f * 3 + 2])
        var t1 = ctx.texcoord(tri_list[f * 3])
        var t2 = ctx.texcoord(tri_list[f * 3 + 1])
        var t3 = ctx.texcoord(tri_list[f * 3 + 2])
        var t21x = t2[0] - t1[0]
        var t21y = t2[1] - t1[1]
        var t31x = t3[0] - t1[0]
        var t31y = t3[1] - t1[1]
        var d1 = v2 - v1
        var d2 = v3 - v1
        var signed_area = t21x * t31y - t21y * t31x
        var os = d1 * t31y - d2 * t21y
        var ot = d1 * (-t31x) + d2 * t21x
        if signed_area > 0:
            infos[f].flag |= ORIENT_PRESERVING
        if _not_zero(signed_area):
            var area = abs(signed_area)
            var len_os = _length(os)
            var len_ot = _length(ot)
            var sign = Float32(1)
            if (infos[f].flag & ORIENT_PRESERVING) == 0:
                sign = -1
            if _not_zero(len_os):
                infos[f].os = os * (sign / len_os)
            if _not_zero(len_ot):
                infos[f].ot = ot * (sign / len_ot)
            infos[f].mag_s = len_os / area
            infos[f].mag_t = len_ot / area
            if _healthy(infos[f].mag_s, infos[f].mag_t):
                infos[f].flag &= ~GROUP_WITH_ANY
    _build_neighbors(infos, tri_list, count)


@fieldwise_init
struct _Edge(Copyable, Movable):
    """One edge of a triangle, the C's `SEdge`: its two vertices, least
    first, and its face."""

    var i0: Int
    var i1: Int
    var f: Int

    def key(self, channel: Int) -> Int:
        """Return the number the C sorts on in `channel`."""
        if channel == 0:
            return self.i0
        if channel == 1:
            return self.i1
        return self.f


def _next_seed(seed: UInt32) -> UInt32:
    """Return the C's quicksort seed after one step."""
    var t = seed & 31
    var turned = (seed << t) | (seed >> ((32 - t) & 31))
    return seed + turned + 3


def _quick_sort_edges(
    mut edges: List[_Edge], left: Int, right: Int, channel: Int, seed: UInt32
):
    """Sort a run of edges on one channel, the C's `QuickSortEdges`."""
    var elements = right - left + 1
    if elements < 2:
        return
    if elements == 2:
        if edges[left].key(channel) > edges[right].key(channel):
            var swap = edges[left].copy()
            edges[left] = edges[right].copy()
            edges[right] = swap^
        return
    var next_seed = _next_seed(seed)
    var il = left
    var ir = right
    var pick = Int(next_seed % UInt32(elements))
    var mid = edges[pick + il].key(channel)
    while True:
        while edges[il].key(channel) < mid:
            il += 1
        while edges[ir].key(channel) > mid:
            ir -= 1
        if il <= ir:
            var swap = edges[il].copy()
            edges[il] = edges[ir].copy()
            edges[ir] = swap^
            il += 1
            ir -= 1
        if not (il <= ir):
            break
    if left < ir:
        _quick_sort_edges(edges, left, ir, channel, next_seed)
    if il < right:
        _quick_sort_edges(edges, il, right, channel, next_seed)


@fieldwise_init
struct _EdgeNumber(Copyable, Movable):
    """Where an edge sits in its triangle, the C's `GetEdge` result."""

    var i0: Int
    var i1: Int
    var edge: Int


def _get_edge(tri_list: List[Int], f: Int, i0: Int, i1: Int) -> _EdgeNumber:
    """Return the ordering and number of an edge in a triangle, the C's
    `GetEdge`."""
    var a = tri_list[f * 3]
    var b = tri_list[f * 3 + 1]
    var c = tri_list[f * 3 + 2]
    if a == i0 or a == i1:
        if b == i0 or b == i1:
            return _EdgeNumber(a, b, 0)
        return _EdgeNumber(c, a, 2)
    return _EdgeNumber(b, c, 1)


def _same_edge(edges: List[_Edge], j: Int, i0: Int, i1: Int) -> Bool:
    """Return True if edge `j` is there and joins the vertices `i0` and
    `i1`."""
    return j < len(edges) and edges[j].i0 == i0 and edges[j].i1 == i1


def _pairs(a: _EdgeNumber, b: _EdgeNumber, unassigned: Bool) -> Bool:
    """Return True if two triangles meet along an edge the way two
    neighbors do: the edge runs one way in the first and the other way in
    the second, which the C writes as swapping the second's two ends. The
    second triangle must have no neighbor on that edge yet."""
    return a.i0 == b.i1 and a.i1 == b.i0 and unassigned


def _build_neighbors(
    mut infos: List[_TriInfo], tri_list: List[Int], count: Int
):
    """Pair the triangles across their edges, the C's
    `BuildNeighborsFast`."""
    var edges = List[_Edge]()
    for f in range(count):
        for i in range(3):  # pragma: no branch
            var i0 = tri_list[f * 3 + i]
            var i1 = tri_list[f * 3 + (i + 1 if i < 2 else 0)]
            edges.append(_Edge(min(i0, i1), max(i0, i1), f))
    var entries = count * 3
    _quick_sort_edges(edges, 0, entries - 1, 0, SORT_SEED)
    var start = 0
    for i in range(1, entries):
        if edges[start].i0 != edges[i].i0:
            _quick_sort_edges(edges, start, i - 1, 1, SORT_SEED)
            start = i
    start = 0
    for i in range(1, entries):
        if edges[start].i0 != edges[i].i0 or edges[start].i1 != edges[i].i1:
            _quick_sort_edges(edges, start, i - 1, 2, SORT_SEED)
            start = i
    for i in range(entries):
        var i0 = edges[i].i0
        var i1 = edges[i].i1
        var f = edges[i].f
        var a = _get_edge(tri_list, f, i0, i1)
        if infos[f].neighbors[a.edge] != -1:
            continue
        var j = i + 1
        var found = False
        var b = _EdgeNumber(0, 0, 0)
        while not found and _same_edge(edges, j, i0, i1):
            var t = edges[j].f
            b = _get_edge(tri_list, t, edges[j].i0, edges[j].i1)
            if _pairs(a, b, infos[t].neighbors[b.edge] == -1):
                found = True
            else:
                j += 1
        if found:
            var t = edges[j].f
            infos[f].neighbors[a.edge] = Int64(t)
            infos[t].neighbors[b.edge] = Int64(f)


def _corner_of(tri_list: List[Int], f: Int, vertex: Int) -> Int:
    """Return which corner of triangle `f` is `vertex`."""
    if tri_list[f * 3] == vertex:
        return 0
    if tri_list[f * 3 + 1] == vertex:
        return 1
    return 2


def _ungrouped(groups: SIMD[DType.int64, 4]) -> Bool:
    """Return True if no corner of a triangle is in a group yet."""
    return groups[0] == -1 and groups[1] == -1 and groups[2] == -1


def _assign_recur(
    tri_list: List[Int],
    mut infos: List[_TriInfo],
    mut groups: List[_Group],
    mut buffer: List[Int],
    my_tri: Int,
    group: Int,
) -> Bool:
    """Grow a group across a triangle and its neighbors, the C's
    `AssignRecur`."""
    var representative = groups[group].representative
    var i = _corner_of(tri_list, my_tri, representative)
    if Int(infos[my_tri].groups[i]) == group:
        return True
    if infos[my_tri].groups[i] != -1:
        return False
    if (infos[my_tri].flag & GROUP_WITH_ANY) != 0:
        if _ungrouped(infos[my_tri].groups):
            infos[my_tri].flag &= ~ORIENT_PRESERVING
            if groups[group].orient_preserving:
                infos[my_tri].flag |= ORIENT_PRESERVING
    var orient = (infos[my_tri].flag & ORIENT_PRESERVING) != 0
    if orient != groups[group].orient_preserving:
        return False
    buffer[groups[group].start + groups[group].count] = my_tri
    groups[group].count += 1
    infos[my_tri].groups[i] = Int64(group)
    var left = Int(infos[my_tri].neighbors[i])
    var right = Int(infos[my_tri].neighbors[i - 1 if i > 0 else 2])
    if left >= 0:
        _ = _assign_recur(tri_list, infos, groups, buffer, left, group)
    if right >= 0:
        _ = _assign_recur(tri_list, infos, groups, buffer, right, group)
    return True


def _build_groups(
    mut infos: List[_TriInfo],
    mut groups: List[_Group],
    mut buffer: List[Int],
    tri_list: List[Int],
    count: Int,
):
    """Put the triangles round each vertex in groups, the C's
    `Build4RuleGroups`."""
    var offset = 0
    for f in range(count):
        for i in range(3):  # pragma: no branch
            if (infos[f].flag & GROUP_WITH_ANY) != 0:
                continue
            if infos[f].groups[i] != -1:
                continue
            var vertex = tri_list[f * 3 + i]
            var group = len(groups)
            var orient = (infos[f].flag & ORIENT_PRESERVING) != 0
            groups.append(_Group(0, offset, vertex, orient))
            infos[f].groups[i] = Int64(group)
            buffer[offset] = f
            groups[group].count = 1
            var left = Int(infos[f].neighbors[i])
            var right = Int(infos[f].neighbors[i - 1 if i > 0 else 2])
            if left >= 0:
                _ = _assign_recur(tri_list, infos, groups, buffer, left, group)
            if right >= 0:
                _ = _assign_recur(tri_list, infos, groups, buffer, right, group)
            offset += groups[group].count


def _quick_sort(mut values: List[Int], left: Int, right: Int, seed: UInt32):
    """Sort a run of whole numbers, the C's `QuickSort`."""
    var next_seed = _next_seed(seed)
    var il = left
    var ir = right
    var n = ir - il + 1
    var pick = Int(next_seed % UInt32(n))
    var mid = values[pick + il]
    while True:
        while values[il] < mid:
            il += 1
        while values[ir] > mid:
            ir -= 1
        if il <= ir:
            var swap = values[il]
            values[il] = values[ir]
            values[ir] = swap
            il += 1
            ir -= 1
        if not (il <= ir):
            break
    if left < ir:
        _quick_sort(values, left, ir, next_seed)
    if il < right:
        _quick_sort(values, il, right, next_seed)


def _projected(v: Vec, n: Vec) -> Vec:
    """Return `v` made square to the normal `n` and unit length, unless it
    is left with nothing."""
    return _unit_if_not_zero(v - n * _dot(n, v))


def _averaged(total: Float32, weight: Float32) -> Float32:
    """Return a weighted sum over its weight, or the sum if there is no
    weight."""
    return total / weight if weight > 0 else total


def _eval_space(
    ctx: _Context,
    members: List[Int],
    tri_list: List[Int],
    infos: List[_TriInfo],
    representative: Int,
) -> _Space:
    """Average the frames of a subgroup's triangles at one vertex, each
    weighted by its angle there, the C's `EvalTspace`."""
    var res = _Space(_v(0, 0, 0), 0, _v(0, 0, 0), 0, 0, False)
    var angle_sum = Float32(0)
    for face in range(len(members)):  # pragma: no branch
        var f = members[face]
        if (infos[f].flag & GROUP_WITH_ANY) != 0:
            continue
        var i = _corner_of(tri_list, f, representative)
        var index = tri_list[f * 3 + i]
        var n = ctx.normal(index)
        var os = _projected(infos[f].os, n)
        var ot = _projected(infos[f].ot, n)
        var i2 = tri_list[f * 3 + (i + 1 if i < 2 else 0)]
        var i1 = tri_list[f * 3 + i]
        var i0 = tri_list[f * 3 + (i - 1 if i > 0 else 2)]
        var p0 = ctx.position(i0)
        var p1 = ctx.position(i1)
        var p2 = ctx.position(i2)
        var v1 = _projected(p0 - p1, n)
        var v2 = _projected(p2 - p1, n)
        var cosine = _dot(v1, v2)
        cosine = max(Float32(-1), min(Float32(1), cosine))
        var angle = Float32(acos(Float64(cosine)))
        res.os = res.os + os * angle
        res.ot = res.ot + ot * angle
        res.mag_s += angle * infos[f].mag_s
        res.mag_t += angle * infos[f].mag_t
        angle_sum += angle
    res.os = _unit_if_not_zero(res.os)
    res.ot = _unit_if_not_zero(res.ot)
    res.mag_s = _averaged(res.mag_s, angle_sum)
    res.mag_t = _averaged(res.mag_t, angle_sum)
    return res^


def _same_members(a: List[Int], b: List[Int]) -> Bool:
    """Return True if two sorted subgroups hold the same triangles, the
    C's `CompareSubGroups`."""
    if len(a) != len(b):
        return False
    # A subgroup holds the triangle it was made for, so this runs.
    for i in range(len(a)):  # pragma: no branch
        if a[i] != b[i]:
            return False
    return True


def _joins(
    f: _TriInfo,
    t: _TriInfo,
    os: Vec,
    ot: Vec,
    os2: Vec,
    ot2: Vec,
    threshold: Float32,
) -> Bool:
    """Return True if triangle `t` joins triangle `f`'s subgroup: either
    may group with anything, they are one face, or both of their
    directions turn from `f`'s by less than the threshold."""
    return (
        ((f.flag | t.flag) & GROUP_WITH_ANY) != 0
        or f.face == t.face
        or (_dot(os, os2) > threshold and _dot(ot, ot2) > threshold)
    )


def _generate_spaces(
    ctx: _Context,
    mut spaces: List[_Space],
    infos: List[_TriInfo],
    groups: List[_Group],
    buffer: List[Int],
    tri_list: List[Int],
    threshold: Float32,
):
    """Make a frame for every corner of every good triangle, the C's
    `GenerateTSpaces`."""
    for g in range(len(groups)):
        ref group = groups[g]
        var unique = List[List[Int]]()
        var unique_spaces = List[_Space]()
        for i in range(group.count):  # pragma: no branch
            var f = buffer[group.start + i]
            var index = 2
            if Int(infos[f].groups[0]) == g:
                index = 0
            elif Int(infos[f].groups[1]) == g:
                index = 1
            var vertex = tri_list[f * 3 + index]
            var n = ctx.normal(vertex)
            var os = _projected(infos[f].os, n)
            var ot = _projected(infos[f].ot, n)
            var members = List[Int]()
            for j in range(group.count):  # pragma: no branch
                var t = buffer[group.start + j]
                var os2 = _projected(infos[t].os, n)
                var ot2 = _projected(infos[t].ot, n)
                if _joins(infos[f], infos[t], os, ot, os2, ot2, threshold):
                    members.append(t)
            if len(members) > 1:
                _quick_sort(members, 0, len(members) - 1, SORT_SEED)
            var l = 0
            while l < len(unique) and not _same_members(members, unique[l]):
                l += 1
            if l == len(unique):
                unique_spaces.append(
                    _eval_space(ctx, members, tri_list, infos, vertex)
                )
                unique.append(members^)
            # A corner of a triangle is in one group, so it is written
            # once. The C averages a second write, which only the corner
            # a quad's two triangles share can get.
            var at = infos[f].offset + index
            spaces[at] = unique_spaces[l].copy()
            spaces[at].counter = 1
            spaces[at].orient = group.orient_preserving


def _degen_epilogue(
    mut spaces: List[_Space],
    infos: List[_TriInfo],
    tri_list: List[Int],
    good: Int,
    total: Int,
):
    """Give each corner of a degenerate triangle the frame of a good
    corner on the same vertex, the C's `DegenEpilogue` without its quad
    part."""
    for t in range(good, total):
        for i in range(3):  # pragma: no branch
            var index = tri_list[t * 3 + i]
            var j = 0
            while j < 3 * good and tri_list[j] != index:
                j += 1
            if j < 3 * good:
                var source = infos[j // 3].offset + j % 3
                spaces[infos[t].offset + i] = spaces[source].copy()


def _degenerate(p0: Vec, p1: Vec, p2: Vec) -> Bool:
    """Return True if two corners of a triangle are in one place."""
    return _veq(p0, p1) or _veq(p0, p2) or _veq(p1, p2)


def generate_tangents(
    var positions: List[Float32],
    var normals: List[Float32],
    var uvs: List[Float32],
    angular_threshold: Angle = Angle(180, DEGREE),
) raises -> List[Float32]:
    """Return a MikkTSpace tangent for every corner of a list of
    triangles: the WebAssembly `generateTangents` three.js calls.

    Args:
        positions: Three numbers a corner, three corners a triangle.
        normals: Three numbers a corner, unit length.
        uvs: Two numbers a corner.
        angular_threshold: How far two triangles' directions can turn and
            still share a frame, the C's `fAngularThreshold`. 180 degrees
            by default, as `genTangSpaceDefault` has it.

    Returns:
        Four numbers a corner: the tangent, and one or minus one for
        whether the texture is mirrored there.

    Raises:
        Error: If the three lists do not describe the same whole
            triangles, or the threshold is not finite.
    """
    if not isfinite(angular_threshold.value):
        raise Error("MikkTSpace needs a finite angular threshold")
    var corners = len(positions) // 3
    if len(positions) % 9 != 0:
        raise Error("MikkTSpace needs whole triangles")
    if len(normals) != corners * 3 or len(uvs) != corners * 2:
        raise Error("MikkTSpace needs a normal and a uv for every corner")
    var out = List[Float32](length=corners * 4, fill=0)
    var total = corners // 3
    if total == 0:
        return out^
    var ctx = _Context(positions^, normals^, uvs^)
    var tri_list = List[Int](capacity=total * 3)
    var infos = List[_TriInfo]()
    # There is a triangle at least, so this loop and the next run.
    for f in range(total):  # pragma: no branch
        for vert in range(3):  # pragma: no branch
            tri_list.append(_make_index(f, vert))
        infos.append(
            _TriInfo(
                SIMD[DType.int64, 4](-1),
                SIMD[DType.int64, 4](-1),
                _v(0, 0, 0),
                _v(0, 0, 0),
                0,
                0,
                f,
                0,
                f * 3,
            )
        )
    _weld(ctx, tri_list, total)
    var degenerate = 0
    for t in range(total):  # pragma: no branch
        var p0 = ctx.position(tri_list[t * 3])
        var p1 = ctx.position(tri_list[t * 3 + 1])
        var p2 = ctx.position(tri_list[t * 3 + 2])
        if _degenerate(p0, p1, p2):
            infos[t].flag |= MARK_DEGENERATE
            degenerate += 1
    var good = total - degenerate
    _degen_prologue(infos, tri_list, good)
    _init_tri_info(ctx, infos, tri_list, good)
    var groups = List[_Group]()
    var buffer = List[Int](length=good * 3, fill=0)
    _build_groups(infos, groups, buffer, tri_list, good)
    var spaces = List[_Space](length=corners, fill=_default_space())
    var threshold = Float32(cos(Float64(angular_threshold.value)))
    _generate_spaces(ctx, spaces, infos, groups, buffer, tri_list, threshold)
    _degen_epilogue(spaces, infos, tri_list, good, total)
    for corner in range(corners):  # pragma: no branch
        ref space = spaces[corner]
        out[corner * 4] = space.os[0]
        out[corner * 4 + 1] = space.os[1]
        out[corner * 4 + 2] = space.os[2]
        out[corner * 4 + 3] = Float32(1) if space.orient else Float32(-1)
    return out^


def compute_mikktspace_tangents(
    mut geometry: BufferGeometry, negate_sign: Bool = True
) raises:
    """Give a geometry MikkTSpace tangents, three.js's
    `computeMikkTSpaceTangents`.

    Args:
        geometry: The geometry, with `position`, `normal` and `uv`. An
            indexed one is made non-indexed, as in three.js.
        negate_sign: Whether to turn the fourth number of each tangent
            round, as glTF's convention needs. True by default, as in
            three.js.

    Raises:
        Error: If the geometry lacks one of the three attributes, they
            hold the wrong number of numbers a vertex, or its vertices are
            not whole triangles.
    """
    if not (
        geometry.has_attribute(String(POSITION))
        and geometry.has_attribute(String(NORMAL))
        and geometry.has_attribute(String(UV))
    ):
        raise Error("Tangents need position, normal and uv")
    if geometry.is_indexed():
        geometry = geometry.to_non_indexed()
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    ref uvs = geometry.attribute_view(String(UV))
    if positions.item_size != 3 or normals.item_size != 3:
        raise Error("Tangents need three numbers a position and a normal")
    if uvs.item_size != 2:
        raise Error("Tangents need two numbers a uv")
    var tangents = generate_tangents(
        positions.packed(), normals.packed(), uvs.packed()
    )
    if negate_sign:
        for corner in range(len(tangents) // 4):
            tangents[corner * 4 + 3] *= -1
    geometry.set_attribute(String(TANGENT), BufferAttribute(tangents^, 4))
