# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ear clipping of one polygon, from three.js `src/extras/lib/earcut.js`,
mapbox's earcut 3.0.1, as `ShapeUtils.triangulateShape` calls it.

`earcut` gives the same triangles, in the same order, as three.js's
`Earcut.triangulate( data, holeIndices )`. The points are
put in a ring in clockwise order, and the ring is cut one ear at a time.
When no ear is left, the ring is filtered of repeated and collinear
points, then small self-intersections are cured, then the ring is split
in two along a diagonal, as earcut does. A polygon of more than 80
points is searched through a z-order curve, as earcut searches it.

Each hole is joined to the outline by a bridge from its leftmost point,
the holes from left to right, as earcut joins them.

`triangulate_shape` is three.js's `ShapeUtils.triangulateShape`: it drops
a last point that repeats the first, of the outline and of each hole.

**Where this port differs.** earcut reads a
missing coordinate of a list of odd length as `undefined`; this refuses
such a list. Each product that feeds a sum is rounded on its own, as
JavaScript rounds it, so a nearly flat corner is judged as three.js
judges it.
"""

from std.math import isfinite, trunc


struct _EarNode(ImplicitlyCopyable):
    """One point of the ring, earcut's `createNode`. A link of -1 is
    earcut's `null`."""

    var i: Int
    var x: Float64
    var y: Float64
    var prev: Int
    var next: Int
    var z: Int
    var prev_z: Int
    var next_z: Int
    # A hole of one point, which filtering leaves, earcut's `steiner`.
    var steiner: Bool

    def __init__(out self, i: Int, x: Float64, y: Float64):
        """Make an unlinked point."""
        self.i = i
        self.x = x
        self.y = y
        self.prev = -1
        self.next = -1
        self.z = 0
        self.prev_z = -1
        self.next_z = -1
        self.steiner = False


@no_inline
def _product(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded before any sum uses it, as JavaScript
    rounds it."""
    return a * b


def _area(nodes: List[_EarNode], p: Int, q: Int, r: Int) -> Float64:
    """Return earcut's signed `area` of a triangle."""
    ref a = nodes[p]
    ref b = nodes[q]
    ref c = nodes[r]
    return _product(b.y - a.y, c.x - b.x) - _product(b.x - a.x, c.y - b.y)


def _equals(nodes: List[_EarNode], p: Int, q: Int) -> Bool:
    """Return True if two points are at one place."""
    return nodes[p].x == nodes[q].x and nodes[p].y == nodes[q].y


def _signed_area(data: List[Float64], start: Int, end: Int) -> Float64:
    """Return earcut's `signedArea` of the points from `start` to `end`."""
    var total = Float64(0)
    var j = end - 2
    # A ring holds a point at least: the loop always runs.
    for i in range(start, end, 2):  # pragma: no branch
        total += _product(data[j] - data[i], data[i + 1] + data[j + 1])
        j = i
    return total


def _insert_node(
    mut nodes: List[_EarNode], i: Int, x: Float64, y: Float64, last: Int
) -> Int:
    """Add a point after `last`, earcut's `insertNode`."""
    var p = len(nodes)
    nodes.append(_EarNode(i, x, y))
    if last < 0:
        nodes[p].prev = p
        nodes[p].next = p
    else:
        nodes[p].next = nodes[last].next
        nodes[p].prev = last
        nodes[nodes[last].next].prev = p
        nodes[last].next = p
    return p


def _remove_node(mut nodes: List[_EarNode], p: Int):
    """Take a point out of both rings, earcut's `removeNode`."""
    var prev = nodes[p].prev
    var next = nodes[p].next
    nodes[next].prev = prev
    nodes[prev].next = next
    var prev_z = nodes[p].prev_z
    var next_z = nodes[p].next_z
    if prev_z >= 0:
        nodes[prev_z].next_z = next_z
    if next_z >= 0:
        nodes[next_z].prev_z = prev_z


def _linked_list(
    mut nodes: List[_EarNode],
    data: List[Float64],
    start: Int,
    end: Int,
    clockwise: Bool,
) -> Int:
    """Make a ring of the points from `start` to `end`, clockwise or
    not, earcut's `linkedList`."""
    var last = -1
    if clockwise == (_signed_area(data, start, end) > 0):
        # A ring holds a point at least: the loops always run.
        for i in range(start, end, 2):  # pragma: no branch
            last = _insert_node(nodes, i // 2, data[i], data[i + 1], last)
    else:
        for i in range(end - 2, start - 1, -2):  # pragma: no branch
            last = _insert_node(nodes, i // 2, data[i], data[i + 1], last)
    if _equals(nodes, last, nodes[last].next):
        _remove_node(nodes, last)
        last = nodes[last].next
    return last


def _drops(nodes: List[_EarNode], p: Int) -> Bool:
    """Return True for a point that repeats the next or lies on a line."""
    var prev = nodes[p].prev
    var next = nodes[p].next
    return not nodes[p].steiner and (
        _equals(nodes, p, next) or _area(nodes, prev, p, next) == 0
    )


def _filter_points(mut nodes: List[_EarNode], start: Int, end_at: Int) -> Int:
    """Take out repeated and collinear points, earcut's `filterPoints`.
    An `end_at` of -1 is `start`."""
    var end = start if end_at < 0 else end_at
    var p = start
    var looping = True
    while looping:
        var again = False
        if _drops(nodes, p):
            _remove_node(nodes, p)
            p = nodes[p].prev
            end = p
            if p == nodes[p].next:
                break
            again = True
        else:
            p = nodes[p].next
        looping = again or p != end
    return end


def _point_in_triangle(
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
    cx: Float64,
    cy: Float64,
    px: Float64,
    py: Float64,
) -> Bool:
    """Return True if a point is in a triangle, edges included."""
    return (
        _product(cx - px, ay - py) >= _product(ax - px, cy - py)
        and _product(ax - px, by - py) >= _product(bx - px, ay - py)
        and _product(bx - px, cy - py) >= _product(cx - px, by - py)
    )


def _in_ear(nodes: List[_EarNode], ear: Int, p: Int) -> Bool:
    """Return True if a point that is not a corner of the ear blocks it:
    in its box and its triangle, not at its first corner, and not a
    reflex corner itself."""
    var a = nodes[ear].prev
    var c = nodes[ear].next
    ref pa = nodes[a]
    ref pb = nodes[ear]
    ref pc = nodes[c]
    ref q = nodes[p]
    var in_box = (
        q.x >= min(min(pa.x, pb.x), pc.x)
        and q.x <= max(max(pa.x, pb.x), pc.x)
        and q.y >= min(min(pa.y, pb.y), pc.y)
        and q.y <= max(max(pa.y, pb.y), pc.y)
    )
    var at_first = pa.x == q.x and pa.y == q.y
    return (
        in_box
        and not at_first
        and _point_in_triangle(pa.x, pa.y, pb.x, pb.y, pc.x, pc.y, q.x, q.y)
        and _area(nodes, q.prev, p, q.next) >= 0
    )


def _is_ear(nodes: List[_EarNode], ear: Int) -> Bool:
    """Return True if a corner is an ear, earcut's `isEar`."""
    var a = nodes[ear].prev
    var c = nodes[ear].next
    if _area(nodes, a, ear, c) >= 0:
        return False
    var p = nodes[c].next
    while p != a:
        if _in_ear(nodes, ear, p):
            return False
        p = nodes[p].next
    return True


def _to_int32(value: Float64) -> Int:
    """Return JavaScript's `value | 0`."""
    if not isfinite(value):
        return 0
    var wrapped = trunc(value) % 4294967296.0
    if wrapped >= 2147483648.0:
        wrapped -= 4294967296.0
    return Int(wrapped)


def _spread(value: Int) -> Int:
    """Spread the bits of a 32-bit integer as earcut's `zOrder` does."""
    var v = (value | (value << 8)) & 0x00FF00FF
    v = (v | (v << 4)) & 0x0F0F0F0F
    v = (v | (v << 2)) & 0x33333333
    return (v | (v << 1)) & 0x55555555


def _z_order(
    x: Float64, y: Float64, min_x: Float64, min_y: Float64, inv_size: Float64
) -> Int:
    """Return earcut's `zOrder`, as a 32-bit signed integer."""
    var z = _spread(_to_int32((x - min_x) * inv_size) & 0xFFFFFFFF) | (
        _spread(_to_int32((y - min_y) * inv_size) & 0xFFFFFFFF) << 1
    )
    if z >= 2147483648:
        z -= 4294967296
    return z


def _hashed_blocks(nodes: List[_EarNode], ear: Int, p: Int) -> Bool:
    """Return True if a point found by z-order blocks the ear."""
    var not_corner = p != nodes[ear].prev and p != nodes[ear].next
    return not_corner and _in_ear(nodes, ear, p)


def _both_in_range(
    nodes: List[_EarNode], p: Int, n: Int, min_z: Int, max_z: Int
) -> Bool:
    """Return True while both z-order walks are inside the range."""
    return _down_in_range(nodes, p, min_z) and _up_in_range(nodes, n, max_z)


def _down_in_range(nodes: List[_EarNode], p: Int, min_z: Int) -> Bool:
    """Return True while the walk down in z-order is inside the range."""
    return p >= 0 and nodes[p].z >= min_z


def _up_in_range(nodes: List[_EarNode], n: Int, max_z: Int) -> Bool:
    """Return True while the walk up in z-order is inside the range."""
    return n >= 0 and nodes[n].z <= max_z


def _is_ear_hashed(
    nodes: List[_EarNode],
    ear: Int,
    min_x: Float64,
    min_y: Float64,
    inv_size: Float64,
) -> Bool:
    """Return True if a corner is an ear, earcut's `isEarHashed`."""
    var a = nodes[ear].prev
    var c = nodes[ear].next
    if _area(nodes, a, ear, c) >= 0:
        return False
    ref pa = nodes[a]
    ref pb = nodes[ear]
    ref pc = nodes[c]
    var min_z = _z_order(
        min(min(pa.x, pb.x), pc.x),
        min(min(pa.y, pb.y), pc.y),
        min_x,
        min_y,
        inv_size,
    )
    var max_z = _z_order(
        max(max(pa.x, pb.x), pc.x),
        max(max(pa.y, pb.y), pc.y),
        min_x,
        min_y,
        inv_size,
    )
    var p = nodes[ear].prev_z
    var n = nodes[ear].next_z
    while _both_in_range(nodes, p, n, min_z, max_z):
        if _hashed_blocks(nodes, ear, p):
            return False
        p = nodes[p].prev_z
        if _hashed_blocks(nodes, ear, n):
            return False
        n = nodes[n].next_z
    while _down_in_range(nodes, p, min_z):
        if _hashed_blocks(nodes, ear, p):
            return False
        p = nodes[p].prev_z
    while _up_in_range(nodes, n, max_z):
        if _hashed_blocks(nodes, ear, n):
            return False
        n = nodes[n].next_z
    return True


def _sign(value: Float64) -> Int:
    """Return earcut's `sign`."""
    return 1 if value > 0 else (-1 if value < 0 else 0)


def _on_segment(nodes: List[_EarNode], p: Int, q: Int, r: Int) -> Bool:
    """Return True if collinear `q` lies on the segment from `p` to `r`."""
    ref a = nodes[p]
    ref b = nodes[q]
    ref c = nodes[r]
    return (
        b.x <= max(a.x, c.x)
        and b.x >= min(a.x, c.x)
        and b.y <= max(a.y, c.y)
        and b.y >= min(a.y, c.y)
    )


def _intersects(
    nodes: List[_EarNode], p1: Int, q1: Int, p2: Int, q2: Int
) -> Bool:
    """Return True if two segments meet, earcut's `intersects`."""
    var o1 = _sign(_area(nodes, p1, q1, p2))
    var o2 = _sign(_area(nodes, p1, q1, q2))
    var o3 = _sign(_area(nodes, p2, q2, p1))
    var o4 = _sign(_area(nodes, p2, q2, q1))
    return (
        (o1 != o2 and o3 != o4)
        or (o1 == 0 and _on_segment(nodes, p1, p2, q1))
        or (o2 == 0 and _on_segment(nodes, p1, q2, q1))
        or (o3 == 0 and _on_segment(nodes, p2, p1, q2))
        or (o4 == 0 and _on_segment(nodes, p2, q1, q2))
    )


def _locally_inside(nodes: List[_EarNode], a: Int, b: Int) -> Bool:
    """Return True if a diagonal starts inside the polygon at `a`."""
    var prev = nodes[a].prev
    var next = nodes[a].next
    var convex = _area(nodes, prev, a, next) < 0
    var inside_convex = (
        _area(nodes, a, b, next) >= 0 and _area(nodes, a, prev, b) >= 0
    )
    var inside_reflex = (
        _area(nodes, a, b, prev) < 0 or _area(nodes, a, next, b) < 0
    )
    return inside_convex if convex else inside_reflex


def _cures(nodes: List[_EarNode], p: Int) -> Bool:
    """Return True where a small self-intersection can be cut off."""
    var a = nodes[p].prev
    var next = nodes[p].next
    var b = nodes[next].next
    return (
        not _equals(nodes, a, b)
        and _intersects(nodes, a, p, next, b)
        and _locally_inside(nodes, a, b)
        and _locally_inside(nodes, b, a)
    )


def _cure_local_intersections(
    mut nodes: List[_EarNode], first: Int, mut triangles: List[Int]
) -> Int:
    """Cut off each small self-intersection, earcut's
    `cureLocalIntersections`."""
    var start = first
    var p = start
    var looping = True
    while looping:
        if _cures(nodes, p):
            var a = nodes[p].prev
            var b = nodes[nodes[p].next].next
            triangles.append(nodes[a].i)
            triangles.append(nodes[p].i)
            triangles.append(nodes[b].i)
            _remove_node(nodes, p)
            _remove_node(nodes, nodes[p].next)
            p = b
            start = b
        p = nodes[p].next
        looping = p != start
    return _filter_points(nodes, p, -1)


def _intersects_polygon(nodes: List[_EarNode], a: Int, b: Int) -> Bool:
    """Return True if a diagonal crosses an edge of the ring."""
    var p = a
    var looping = True
    while looping:
        if _crosses_edge(nodes, p, a, b):
            return True
        p = nodes[p].next
        looping = p != a
    return False


def _crosses_edge(nodes: List[_EarNode], p: Int, a: Int, b: Int) -> Bool:
    """Return True if the edge after `p`, which does not touch the
    diagonal's ends, crosses it."""
    var next = nodes[p].next
    var ia = nodes[a].i
    var ib = nodes[b].i
    var apart = (
        nodes[p].i != ia
        and nodes[next].i != ia
        and nodes[p].i != ib
        and nodes[next].i != ib
    )
    return apart and _intersects(nodes, p, next, a, b)


def _flips(nodes: List[_EarNode], p: Int, px: Float64, py: Float64) -> Bool:
    """Return True where the edge after `p` crosses the ray from the
    middle point, earcut's test in `middleInside`."""
    ref q = nodes[p]
    ref n = nodes[q.next]
    var straddles = (q.y > py) != (n.y > py)
    return (
        straddles
        and n.y != q.y
        and px < _product(n.x - q.x, py - q.y) / (n.y - q.y) + q.x
    )


def _middle_inside(nodes: List[_EarNode], a: Int, b: Int) -> Bool:
    """Return True if a diagonal's middle is inside the ring."""
    var p = a
    var inside = False
    var px = (nodes[a].x + nodes[b].x) / 2
    var py = (nodes[a].y + nodes[b].y) / 2
    var looping = True
    while looping:
        if _flips(nodes, p, px, py):
            inside = not inside
        p = nodes[p].next
        looping = p != a
    return inside


def _is_valid_diagonal(nodes: List[_EarNode], a: Int, b: Int) -> Bool:
    """Return True if a diagonal lies inside the ring, earcut's
    `isValidDiagonal`."""
    var not_neighbor = (
        nodes[nodes[a].next].i != nodes[b].i
        and nodes[nodes[a].prev].i != nodes[b].i
    )
    return (
        not_neighbor
        and not _intersects_polygon(nodes, a, b)
        and (
            (
                _locally_inside(nodes, a, b)
                and _locally_inside(nodes, b, a)
                and _middle_inside(nodes, a, b)
                and (
                    _area(nodes, nodes[a].prev, a, nodes[b].prev) != 0
                    or _area(nodes, a, nodes[b].prev, b) != 0
                )
            )
            or (
                _equals(nodes, a, b)
                and _area(nodes, nodes[a].prev, a, nodes[a].next) > 0
                and _area(nodes, nodes[b].prev, b, nodes[b].next) > 0
            )
        )
    )


def _split_polygon(mut nodes: List[_EarNode], a: Int, b: Int) -> Int:
    """Join two points by a bridge and split the ring in two, earcut's
    `splitPolygon`."""
    var a2 = len(nodes)
    nodes.append(_EarNode(nodes[a].i, nodes[a].x, nodes[a].y))
    var b2 = len(nodes)
    nodes.append(_EarNode(nodes[b].i, nodes[b].x, nodes[b].y))
    var an = nodes[a].next
    var bp = nodes[b].prev
    nodes[a].next = b
    nodes[b].prev = a
    nodes[a2].next = an
    nodes[an].prev = a2
    nodes[b2].next = a2
    nodes[a2].prev = b2
    nodes[bp].next = b2
    nodes[b2].prev = bp
    return b2


def _splits(nodes: List[_EarNode], a: Int, b: Int) -> Bool:
    """Return True if the ring can be split along a diagonal."""
    return nodes[a].i != nodes[b].i and _is_valid_diagonal(nodes, a, b)


def _split_earcut(
    mut nodes: List[_EarNode],
    start: Int,
    mut triangles: List[Int],
    min_x: Float64,
    min_y: Float64,
    inv_size: Float64,
):
    """Split the ring in two and cut each half, earcut's `splitEarcut`."""
    var a = start
    var looping = True
    while looping:
        var b = nodes[nodes[a].next].next
        while b != nodes[a].prev:
            if _splits(nodes, a, b):
                var c = _split_polygon(nodes, a, b)
                a = _filter_points(nodes, a, nodes[a].next)
                c = _filter_points(nodes, c, nodes[c].next)
                _earcut_linked(nodes, a, triangles, min_x, min_y, inv_size, 0)
                _earcut_linked(nodes, c, triangles, min_x, min_y, inv_size, 0)
                return
            b = nodes[b].next
        a = nodes[a].next
        looping = a != start


def _get_leftmost(nodes: List[_EarNode], start: Int) -> Int:
    """Return the ring's leftmost point, the lowest of those, earcut's
    `getLeftmost`."""
    var p = start
    var leftmost = start
    var looping = True
    while looping:
        ref q = nodes[p]
        ref best = nodes[leftmost]
        if q.x < best.x or (q.x == best.x and q.y < best.y):
            leftmost = p
        p = nodes[p].next
        looping = p != start
    return leftmost


def _compare_xy_slope(nodes: List[_EarNode], a: Int, b: Int) -> Float64:
    """Return earcut's `compareXYSlope`: below zero when hole `a` comes
    first."""
    var result = nodes[a].x - nodes[b].x
    if result == 0:
        result = nodes[a].y - nodes[b].y
        if result == 0:
            ref an = nodes[nodes[a].next]
            ref bn = nodes[nodes[b].next]
            var a_slope = (an.y - nodes[a].y) / (an.x - nodes[a].x)
            var b_slope = (bn.y - nodes[b].y) / (bn.x - nodes[b].x)
            result = a_slope - b_slope
    return result


def _sector_contains_sector(nodes: List[_EarNode], m: Int, p: Int) -> Bool:
    """Return whether the sector at `m` holds the sector at `p`, earcut's
    `sectorContainsSector`."""
    return (
        _area(nodes, nodes[m].prev, m, nodes[p].prev) < 0
        and _area(nodes, nodes[p].next, m, nodes[m].next) < 0
    )


def _find_hole_bridge(nodes: List[_EarNode], hole: Int, outer: Int) -> Int:
    """Return the outline's point a hole's leftmost point joins, David
    Eberly's search as earcut's `findHoleBridge` makes it, or -1."""
    var p = outer
    var hx = nodes[hole].x
    var hy = nodes[hole].y
    var qx = -Float64.MAX
    var infinite = True
    var m = -1
    if _equals(nodes, hole, p):
        return p
    var looping = True
    while looping:
        var n = nodes[p].next
        if _equals(nodes, hole, n):
            return n
        if hy <= nodes[p].y and hy >= nodes[n].y and nodes[n].y != nodes[p].y:
            var x = nodes[p].x + _product(
                hy - nodes[p].y, nodes[n].x - nodes[p].x
            ) / (nodes[n].y - nodes[p].y)
            if x <= hx and (infinite or x > qx):
                qx = x
                infinite = False
                m = p if nodes[p].x < nodes[n].x else n
                if x == hx:
                    return m
        p = n
        looping = p != outer
    if m < 0:
        return -1
    var stop = m
    var mx = nodes[m].x
    var my = nodes[m].y
    var tan_min = Float64.MAX
    var unbounded = True
    p = m
    looping = True
    while looping:
        ref q = nodes[p]
        if (
            hx >= q.x
            and q.x >= mx
            and hx != q.x
            and _point_in_triangle(
                hx if hy < my else qx,
                hy,
                mx,
                my,
                qx if hy < my else hx,
                hy,
                q.x,
                q.y,
            )
        ):
            var tan = abs(hy - q.y) / (hx - q.x)
            if _locally_inside(nodes, p, hole) and (
                unbounded
                or tan < tan_min
                or (
                    tan == tan_min
                    and (
                        q.x > nodes[m].x
                        or (
                            q.x == nodes[m].x
                            and _sector_contains_sector(nodes, m, p)
                        )
                    )
                )
            ):
                m = p
                tan_min = tan
                unbounded = False
        p = nodes[p].next
        looping = p != stop
    return m


def _eliminate_hole(mut nodes: List[_EarNode], hole: Int, outer: Int) -> Int:
    """Join a hole to the outline by a bridge, earcut's `eliminateHole`."""
    var bridge = _find_hole_bridge(nodes, hole, outer)
    if bridge < 0:
        return outer
    var bridge_reverse = _split_polygon(nodes, bridge, hole)
    _ = _filter_points(nodes, bridge_reverse, nodes[bridge_reverse].next)
    return _filter_points(nodes, bridge, nodes[bridge].next)


def _eliminate_holes(
    mut nodes: List[_EarNode],
    data: List[Float64],
    hole_indices: List[Int],
    outer: Int,
) -> Int:
    """Join every hole to the outline, from left to right, earcut's
    `eliminateHoles`."""
    var queue = List[Int]()
    # Called with a hole at least, so this loop runs.
    for at in range(len(hole_indices)):  # pragma: no branch
        var start = hole_indices[at] * 2
        var end = hole_indices[at + 1] * 2 if at < len(
            hole_indices
        ) - 1 else len(data)
        var list = _linked_list(nodes, data, start, end, False)
        if list == nodes[list].next:
            nodes[list].steiner = True
        queue.append(_get_leftmost(nodes, list))
    # A stable insertion sort, as JavaScript's sort is stable: a hole goes
    # before another only when the comparison says it comes first.
    for at in range(1, len(queue)):
        var hole = queue[at]
        var j = at
        while j > 0 and _compare_xy_slope(nodes, hole, queue[j - 1]) < 0:
            queue[j] = queue[j - 1]
            j -= 1
        queue[j] = hole
    var joined = outer
    for at in range(len(queue)):  # pragma: no branch
        joined = _eliminate_hole(nodes, queue[at], joined)
    return joined


def _takes_first(
    nodes: List[_EarNode], p: Int, p_size: Int, q: Int, q_size: Int
) -> Bool:
    """Return True where the merge takes from the first run."""
    return p_size != 0 and (q_size == 0 or q < 0 or nodes[p].z <= nodes[q].z)


def _merging(p_size: Int, q: Int, q_size: Int) -> Bool:
    """Return True while either run has points left."""
    return p_size > 0 or (q_size > 0 and q >= 0)


def _sort_linked(mut nodes: List[_EarNode], first: Int):
    """Sort the ring by z-order, Simon Tatham's merge sort as earcut's
    `sortLinked` does it."""
    var list = first
    var in_size = 1
    var merges = 2
    while merges > 1:
        var p = list
        list = -1
        var tail = -1
        merges = 0
        while p >= 0:
            merges += 1
            var q = p
            var p_size = 0
            for _ in range(in_size):  # pragma: no branch
                p_size += 1
                q = nodes[q].next_z
                if q < 0:
                    break
            var q_size = in_size
            while _merging(p_size, q, q_size):
                var e: Int
                if _takes_first(nodes, p, p_size, q, q_size):
                    e = p
                    p = nodes[p].next_z
                    p_size -= 1
                else:
                    e = q
                    q = nodes[q].next_z
                    q_size -= 1
                if tail >= 0:
                    nodes[tail].next_z = e
                else:
                    list = e
                nodes[e].prev_z = tail
                tail = e
            p = q
        nodes[tail].next_z = -1
        in_size *= 2


def _index_curve(
    mut nodes: List[_EarNode],
    start: Int,
    min_x: Float64,
    min_y: Float64,
    inv_size: Float64,
):
    """Link the ring in z-order, earcut's `indexCurve`."""
    var p = start
    var looping = True
    while looping:
        if nodes[p].z == 0:
            nodes[p].z = _z_order(
                nodes[p].x, nodes[p].y, min_x, min_y, inv_size
            )
        nodes[p].prev_z = nodes[p].prev
        nodes[p].next_z = nodes[p].next
        p = nodes[p].next
        looping = p != start
    nodes[nodes[p].prev_z].next_z = -1
    nodes[p].prev_z = -1
    _sort_linked(nodes, p)


def _earcut_linked(
    mut nodes: List[_EarNode],
    first: Int,
    mut triangles: List[Int],
    min_x: Float64,
    min_y: Float64,
    inv_size: Float64,
    pass_number: Int,
):
    """Cut ears off the ring, earcut's `earcutLinked`."""
    var ear = first
    var index_first = pass_number == 0 and inv_size != 0
    if index_first:
        _index_curve(nodes, ear, min_x, min_y, inv_size)
    var stop = ear
    while nodes[ear].prev != nodes[ear].next:
        var prev = nodes[ear].prev
        var next = nodes[ear].next
        var cut = _is_ear_hashed(
            nodes, ear, min_x, min_y, inv_size
        ) if inv_size != 0 else _is_ear(nodes, ear)
        if cut:
            triangles.append(nodes[prev].i)
            triangles.append(nodes[ear].i)
            triangles.append(nodes[next].i)
            _remove_node(nodes, ear)
            ear = nodes[next].next
            stop = nodes[next].next
            continue
        ear = next
        if ear == stop:
            if pass_number == 0:
                var filtered = _filter_points(nodes, ear, -1)
                _earcut_linked(
                    nodes, filtered, triangles, min_x, min_y, inv_size, 1
                )
            elif pass_number == 1:
                var cured = _cure_local_intersections(
                    nodes, _filter_points(nodes, ear, -1), triangles
                )
                _earcut_linked(
                    nodes, cured, triangles, min_x, min_y, inv_size, 2
                )
            else:
                _split_earcut(nodes, ear, triangles, min_x, min_y, inv_size)
            break


def earcut(
    data: List[Float64], hole_indices: List[Int] = List[Int]()
) raises -> List[Int]:
    """Cut a polygon into triangles, three.js's
    `Earcut.triangulate( data, holeIndices )`.

    Args:
        data: The points, x then y for each, in either winding order:
            the outline, then each hole.
        hole_indices: Where each hole starts, as a point's number.

    Returns:
        Three point indices for each triangle, in earcut's order. It is
        empty for fewer than three points.

    Raises:
        Error: If the list has an odd length, or a hole starts outside
            it, before the one before it, or where the outline would
            have no point.
    """
    if len(data) % 2 != 0:
        raise Error("earcut: a point list of odd length")
    var points = len(data) // 2
    for at in range(len(hole_indices)):
        var low = 1 if at == 0 else hole_indices[at - 1] + 1
        if hole_indices[at] < low or hole_indices[at] >= points:
            raise Error("earcut: a hole must start after the last, in the list")
    var triangles = List[Int]()
    if len(data) == 0:
        return triangles^
    var outer_len = hole_indices[0] * 2 if len(hole_indices) > 0 else len(data)
    var nodes = List[_EarNode]()
    var outer = _linked_list(nodes, data, 0, outer_len, True)
    if nodes[outer].next == nodes[outer].prev:
        return triangles^
    if len(hole_indices) > 0:
        outer = _eliminate_holes(nodes, data, hole_indices, outer)
    var min_x = Float64(0)
    var min_y = Float64(0)
    var inv_size = Float64(0)
    if len(data) > 160:
        min_x = Float64.MAX
        min_y = Float64.MAX
        var max_x = -Float64.MAX
        var max_y = -Float64.MAX
        # earcut starts at the outline's second point, and so does this.
        # The outline holds three points at least here: the loop runs.
        for i in range(2, outer_len, 2):  # pragma: no branch
            min_x = min(min_x, data[i])
            min_y = min(min_y, data[i + 1])
            max_x = max(max_x, data[i])
            max_y = max(max_y, data[i + 1])
        var size = max(max_x - min_x, max_y - min_y)
        inv_size = 32767 / size if size != 0 else Float64(0)
    _earcut_linked(nodes, outer, triangles, min_x, min_y, inv_size, 0)
    return triangles^


def drop_closing_point(mut points: List[Float64]) raises:
    """Drop a last point equal to the first, when there are more than two
    points, three.js's `removeDupEndPts`.

    Args:
        points: The points, x then y for each. Changed in place, as
            three.js changes its array.

    Raises:
        Error: If the list has an odd length.
    """
    if len(points) % 2 != 0:
        raise Error("earcut: a point list of odd length")
    var n = len(points)
    var repeats = (
        n > 4 and points[n - 2] == points[0] and points[n - 1] == (points[1])
    )
    if repeats:
        _ = points.pop()
        _ = points.pop()


def triangulate_shape(
    contour: List[Float64], holes: List[List[Float64]] = List[List[Float64]]()
) raises -> List[Int]:
    """Cut an outline with holes into triangles, three.js's
    `ShapeUtils.triangulateShape( contour, holes )`.

    Args:
        contour: The outline's points, x then y for each. A last point
            equal to the first is dropped, when there are more than two.
        holes: Each hole's points, likewise.

    Returns:
        Three point indices for each triangle: the outline's points
        first, then each hole's.

    Raises:
        Error: If a list has an odd length.
    """
    var points = contour.copy()
    drop_closing_point(points)
    var hole_indices = List[Int]()
    for at in range(len(holes)):
        var hole = holes[at].copy()
        drop_closing_point(hole)
        hole_indices.append(len(points) // 2)
        points.extend(hole^)
    return earcut(points, hole_indices)
