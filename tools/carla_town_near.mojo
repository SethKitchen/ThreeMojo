# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find the triangles nearest a simplified face.

    carla_town_near FILE

`FILE` is JSON with `centers`, `count`, and either `queries` or
`corners`. The centers are the original triangles. `corners` are the new
triangles, and each query is their mean. The program builds the same tree
SciPy's `cKDTree` builds with its default leaf size, and it returns the
`count` nearest centers of each query. The nearest center is first. An
equal distance keeps the center the tree found first.
"""

from std.ffi import external_call
from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import MISSING, PY_DICT, PY_INT, PY_LIST, PyJson
from tools._town_json import json_number, json_vec3


comptime LEAF = 16
"""The default leaf size of SciPy's `cKDTree`."""


@fieldwise_init
struct _Node(ImplicitlyCopyable, Movable):
    var split_dim: Int
    var split: Float64
    var start: Int
    var end: Int
    var less: Int
    var greater: Int


@fieldwise_init
struct _Item(ImplicitlyCopyable, Movable):
    var priority: Float64
    var index: Int


@fieldwise_init
struct _Far(ImplicitlyCopyable, Movable):
    var node: Int
    var s0: Float64
    var s1: Float64
    var s2: Float64
    var distance: Float64


def near_text(text: String) raises -> String:
    """Return the nearest centers of each query as JSON.

    Args:
        text: A JSON object with `centers`, `count`, and `queries` or
            `corners`.

    Returns:
        `near`, a list of index lists. Each list has `count` indexes.
        `queries` is included when `corners` was given.

    Raises:
        Error: If the JSON is not that request, or `count` is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("near request is not an object")
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var qx = List[Float64]()
    var qy = List[Float64]()
    var qz = List[Float64]()
    json_vec3(doc, doc.at(root, "centers"), xs, ys, zs)
    var corners = doc.get(root, "corners")
    var report = False
    if corners != MISSING:
        _means(doc, corners, qx, qy, qz)
        report = True
    else:
        json_vec3(doc, doc.at(root, "queries"), qx, qy, qz)
    var count = _whole(doc, doc.at(root, "count"))
    if count < 1:
        raise Error("count is not positive")
    if len(qx) > 0 and count > len(xs):
        raise Error("count is past the centers")
    if len(qx) == 0:
        return '{"near":[]}'
    var indices = List[Int]()
    for index in range(len(xs)):
        indices.append(index)
    var nodes = List[_Node]()
    var work_min = List[Float64]()
    var work_max = List[Float64]()
    work_min.append(0.0)
    work_min.append(0.0)
    work_min.append(0.0)
    work_max.append(0.0)
    work_max.append(0.0)
    work_max.append(0.0)
    _ = _build(xs, ys, zs, indices, nodes, work_min, work_max, 0, len(xs))
    var minx = xs[0]
    var miny = ys[0]
    var minz = zs[0]
    var maxx = xs[0]
    var maxy = ys[0]
    var maxz = zs[0]
    for index in range(1, len(xs)):
        minx = _keep_min(minx, xs[index])
        miny = _keep_min(miny, ys[index])
        minz = _keep_min(minz, zs[index])
        maxx = _keep_max(maxx, xs[index])
        maxy = _keep_max(maxy, ys[index])
        maxz = _keep_max(maxz, zs[index])
    var out = String('{"near":[')
    for query in range(len(qx)):
        if query > 0:
            out += ","
        out += "["
        var found = _query(
            xs,
            ys,
            zs,
            indices,
            nodes,
            qx[query],
            qy[query],
            qz[query],
            count,
            minx,
            miny,
            minz,
            maxx,
            maxy,
            maxz,
        )
        if len(found) != count:
            raise Error("neighbor search missed a center")
        for slot in range(count):
            if slot > 0:
                out += ","
            out += String(found[slot])
        out += "]"
    out += "]"
    if report:
        out += ',"queries":['
        for query in range(len(qx)):
            if query > 0:
                out += ","
            out += "["
            out += python_repr(qx[query])
            out += ","
            out += python_repr(qy[query])
            out += ","
            out += python_repr(qz[query])
            out += "]"
        out += "]"
    out += "}"
    return out^


def _build(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    mut nodes: List[_Node],
    mut work_min: List[Float64],
    mut work_max: List[Float64],
    start: Int,
    end: Int,
) -> Int:
    """Build one tree node and return its index."""
    var node_index = len(nodes)
    nodes.append(_Node(-1, 0.0, start, end, -1, -1))
    if end - start <= LEAF:
        return node_index
    var point = indices[start]
    work_max[0] = xs[point]
    work_min[0] = xs[point]
    work_max[1] = ys[point]
    work_min[1] = ys[point]
    work_max[2] = zs[point]
    work_min[2] = zs[point]
    for slot in range(start + 1, end):
        var at = indices[slot]
        work_max[0] = _keep_max(work_max[0], xs[at])
        work_min[0] = _keep_min(work_min[0], xs[at])
        work_max[1] = _keep_max(work_max[1], ys[at])
        work_min[1] = _keep_min(work_min[1], ys[at])
        work_max[2] = _keep_max(work_max[2], zs[at])
        work_min[2] = _keep_min(work_min[2], zs[at])
    var dim = 0
    var size = 0.0
    for axis in range(3):
        var spread = work_max[axis] - work_min[axis]
        if spread > size:
            dim = axis
            size = spread
    if work_max[dim] == work_min[dim]:
        return node_index
    var mid = start + (end - start) // 2
    _nth_element(xs, ys, zs, indices, start, mid, end, dim)
    var split = _coord(xs, ys, zs, indices[mid], dim)
    var cut = _partition(xs, ys, zs, indices, start, mid, dim, split)
    if cut == start:
        var least = _min_index(xs, ys, zs, indices, start, end, dim)
        split = _nextafter(_coord(xs, ys, zs, indices[least], dim), _inf())
        cut = _partition(xs, ys, zs, indices, start, end, dim, split)
    elif cut == end:
        var most = _max_index(xs, ys, zs, indices, start, end, dim)
        split = _coord(xs, ys, zs, indices[most], dim)
        cut = _partition(xs, ys, zs, indices, start, end, dim, split)
    var less = _build(
        xs, ys, zs, indices, nodes, work_min, work_max, start, cut
    )
    var greater = _build(
        xs, ys, zs, indices, nodes, work_min, work_max, cut, end
    )
    var node = nodes[node_index]
    node.less = less
    node.greater = greater
    node.split_dim = dim
    node.split = split
    nodes[node_index] = node
    return node_index


def _query(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    indices: List[Int],
    nodes: List[_Node],
    qx: Float64,
    qy: Float64,
    qz: Float64,
    count: Int,
    minx: Float64,
    miny: Float64,
    minz: Float64,
    maxx: Float64,
    maxy: Float64,
    maxz: Float64,
) -> List[Int]:
    """Return `count` nearest indexes, nearest first."""
    var upper = _inf()
    var neighbor_p = List[Float64]()
    var neighbor_i = List[Int]()
    var queue_p = List[Float64]()
    var queue_i = List[Int]()
    var far = List[_Far]()
    var s0 = 0.0
    var s1 = 0.0
    var s2 = 0.0
    var min_distance = 0.0
    var box = _side(qx, minx, maxx)
    min_distance = _fadd(min_distance, _fsub(box, s0))
    s0 = box
    box = _side(qy, miny, maxy)
    min_distance = _fadd(min_distance, _fsub(box, s1))
    s1 = box
    box = _side(qz, minz, maxz)
    min_distance = _fadd(min_distance, _fsub(box, s2))
    s2 = box
    var node = 0
    while True:
        var current = nodes[node]
        if current.split_dim == -1:
            for slot in range(current.start, current.end):
                var at = indices[slot]
                var dist = _sq(xs[at], ys[at], zs[at], qx, qy, qz)
                if dist < upper:
                    if len(neighbor_p) == count:
                        _heap_remove(neighbor_p, neighbor_i)
                    _heap_push(neighbor_p, neighbor_i, -dist, at)
                    if len(neighbor_p) == count:
                        upper = -neighbor_p[0]
            if len(queue_p) == 0:
                break
            var picked = _heap_pop(queue_p, queue_i)
            var state = far[picked]
            node = state.node
            s0 = state.s0
            s1 = state.s1
            s2 = state.s2
            min_distance = state.distance
        else:
            if min_distance > upper:
                break
            var near = current.less
            var away = current.greater
            var gap: Float64
            var axis = _axis(qx, qy, qz, current.split_dim)
            if axis < current.split:
                gap = _fsub(current.split, axis)
            else:
                near = current.greater
                away = current.less
                gap = _fsub(axis, current.split)
            gap = _fmul(gap, gap)
            var f0 = s0
            var f1 = s1
            var f2 = s2
            var far_distance = min_distance
            if current.split_dim == 0:
                far_distance = _fadd(far_distance, _fsub(gap, f0))
                f0 = gap
            elif current.split_dim == 1:
                far_distance = _fadd(far_distance, _fsub(gap, f1))
                f1 = gap
            else:
                far_distance = _fadd(far_distance, _fsub(gap, f2))
                f2 = gap
            var n0 = s0
            var n1 = s1
            var n2 = s2
            var near_distance = min_distance
            if near_distance > far_distance:
                near, away = away, near
                n0 = f0
                n1 = f1
                n2 = f2
                f0 = s0
                f1 = s1
                f2 = s2
                near_distance = far_distance
                far_distance = min_distance
            if far_distance <= upper:
                _heap_push(queue_p, queue_i, far_distance, len(far))
                far.append(_Far(away, f0, f1, f2, far_distance))
            node = near
            s0 = n0
            s1 = n1
            s2 = n2
            min_distance = near_distance
    var ranked = List[_Item]()
    var total = len(neighbor_p)
    for _ in range(total):
        ranked.append(_Item(0.0, 0))
    for slot in range(total - 1, -1, -1):
        var priority = neighbor_p[0]
        var index = _heap_pop(neighbor_p, neighbor_i)
        ranked[slot] = _Item(priority, index)
    var out = List[Int]()
    for slot in range(total):
        out.append(ranked[slot].index)
    return out^


def _nth_element(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    nth: Int,
    last: Int,
    dim: Int,
):
    """Place the median the way libstdc++ `nth_element` does."""
    if first == last or nth == last:
        return
    var depth = _lg(last - first) * 2
    var left = first
    var right = last
    while right - left > 3:
        if depth == 0:
            _heap_select(xs, ys, zs, indices, left, nth + 1, right, dim)
            _swap(indices, left, nth)
            return
        depth -= 1
        var cut = _partition_pivot(xs, ys, zs, indices, left, right, dim)
        if cut <= nth:
            left = cut
        else:
            right = cut
    _insertion_sort(xs, ys, zs, indices, left, right, dim)


def _partition_pivot(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    last: Int,
    dim: Int,
) -> Int:
    """Return Hoare's cut after moving the median of three to `first`."""
    var mid = first + (last - first) // 2
    _median_first(xs, ys, zs, indices, first, first + 1, mid, last - 1, dim)
    return _hoare(xs, ys, zs, indices, first + 1, last, first, dim)


def _median_first(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    result: Int,
    a: Int,
    b: Int,
    c: Int,
    dim: Int,
):
    """Swap the median of `a`, `b` and `c` into `result`."""
    if _before(xs, ys, zs, indices, a, b, dim):
        if _before(xs, ys, zs, indices, b, c, dim):
            _swap(indices, result, b)
        elif _before(xs, ys, zs, indices, a, c, dim):
            _swap(indices, result, c)
        else:
            _swap(indices, result, a)
    elif _before(xs, ys, zs, indices, a, c, dim):
        _swap(indices, result, a)
    elif _before(xs, ys, zs, indices, b, c, dim):
        _swap(indices, result, c)
    else:
        _swap(indices, result, b)


def _hoare(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    last: Int,
    pivot: Int,
    dim: Int,
) -> Int:
    """Return the right side of an unguarded Hoare partition."""
    var left = first
    var right = last
    while True:
        while _before(xs, ys, zs, indices, left, pivot, dim):
            left += 1
        right -= 1
        while _before(xs, ys, zs, indices, pivot, right, dim):
            right -= 1
        if not (left < right):
            return left
        _swap(indices, left, right)
        left += 1


def _insertion_sort(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    last: Int,
    dim: Int,
):
    """Sort a short range the way libstdc++ insertion sort does."""
    if first == last:
        return
    var cursor = first + 1
    while cursor != last:
        if _before(xs, ys, zs, indices, cursor, first, dim):
            var value = indices[cursor]
            var slot = cursor
            while slot != first:
                indices[slot] = indices[slot - 1]
                slot -= 1
            indices[first] = value
        else:
            _linear_insert(xs, ys, zs, indices, cursor, dim)
        cursor += 1


def _linear_insert(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    last: Int,
    dim: Int,
):
    """Insert `indices[last]` into the sorted values before it."""
    var value = indices[last]
    var nxt = last - 1
    var at = last
    while _coord(xs, ys, zs, value, dim) < _coord(
        xs, ys, zs, indices[nxt], dim
    ):
        indices[at] = indices[nxt]
        at = nxt
        nxt -= 1
    indices[at] = value


def _heap_select(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    middle: Int,
    last: Int,
    dim: Int,
):
    """Keep the smallest `middle - first` values in a max-heap."""
    _make_heap(xs, ys, zs, indices, first, middle, dim)
    var cursor = middle
    while cursor < last:
        if _before(xs, ys, zs, indices, cursor, first, dim):
            var value = indices[cursor]
            indices[cursor] = indices[first]
            _adjust(xs, ys, zs, indices, first, 0, middle - first, value, dim)
        cursor += 1


def _make_heap(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    last: Int,
    dim: Int,
):
    """Make a max-heap on `[first, last)`."""
    if last - first < 2:
        return
    var length = last - first
    var parent = (length - 2) // 2
    while True:
        var value = indices[first + parent]
        _adjust(xs, ys, zs, indices, first, parent, length, value, dim)
        if parent == 0:
            return
        parent -= 1


def _adjust(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    hole: Int,
    length: Int,
    value: Int,
    dim: Int,
):
    """Restore a max-heap after removing the value at `hole`."""
    var top = hole
    var second = hole
    var at = hole
    while second < (length - 1) // 2:
        second = 2 * (second + 1)
        if _before(
            xs, ys, zs, indices, first + second, first + second - 1, dim
        ):
            second -= 1
        indices[first + at] = indices[first + second]
        at = second
    if (length & 1) == 0 and second == (length - 2) // 2:
        second = 2 * (second + 1)
        indices[first + at] = indices[first + second - 1]
        at = second - 1
    var parent = (at - 1) // 2
    while at > top and _coord(
        xs, ys, zs, indices[first + parent], dim
    ) < _coord(xs, ys, zs, value, dim):
        indices[first + at] = indices[first + parent]
        at = parent
        parent = (at - 1) // 2
    indices[first + at] = value


def _partition(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    mut indices: List[Int],
    first: Int,
    last: Int,
    dim: Int,
    pivot: Float64,
) -> Int:
    """Return libstdc++'s bidirectional partition on `value < pivot`."""
    var left = first
    var right = last
    while True:
        while True:
            if left == right:
                return left
            if _coord(xs, ys, zs, indices[left], dim) < pivot:
                left += 1
            else:
                break
        right -= 1
        while True:
            if left == right:
                return left
            if not (_coord(xs, ys, zs, indices[right], dim) < pivot):
                right -= 1
            else:
                break
        _swap(indices, left, right)
        left += 1


def _min_index(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    indices: List[Int],
    first: Int,
    last: Int,
    dim: Int,
) -> Int:
    """Return the first smallest index in `[first, last)`."""
    var best = first
    for slot in range(first + 1, last):
        if _before(xs, ys, zs, indices, slot, best, dim):
            best = slot
    return best


def _max_index(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    indices: List[Int],
    first: Int,
    last: Int,
    dim: Int,
) -> Int:
    """Return the first largest index in `[first, last)`."""
    var best = first
    for slot in range(first + 1, last):
        if _before(xs, ys, zs, indices, best, slot, dim):
            best = slot
    return best


def _heap_push(
    mut priority: List[Float64], mut index: List[Int], value: Float64, at: Int
):
    """Push one item onto a minimum heap."""
    priority.append(value)
    index.append(at)
    var slot = len(priority) - 1
    while slot > 0 and priority[slot] < priority[(slot - 1) // 2]:
        var parent = (slot - 1) // 2
        _swap_float(priority, slot, parent)
        _swap(index, slot, parent)
        slot = parent


def _heap_remove(mut priority: List[Float64], mut index: List[Int]):
    """Remove the minimum item of a non-empty heap."""
    var last = len(priority) - 1
    priority[0] = priority[last]
    index[0] = index[last]
    _ = priority.pop()
    _ = index.pop()
    var count = len(priority)
    var slot = 0
    while True:
        var left = 2 * slot + 1
        var right = 2 * slot + 2
        var go_left = left < count and priority[slot] > priority[left]
        var go_right = right < count and priority[slot] > priority[right]
        if go_left or go_right:
            var child = left
            if right < count and priority[left] > priority[right]:
                child = right
            _swap_float(priority, slot, child)
            _swap(index, slot, child)
            slot = child
        else:
            break


def _heap_pop(mut priority: List[Float64], mut index: List[Int]) -> Int:
    """Remove the minimum item and return its index."""
    var at = index[0]
    _heap_remove(priority, index)
    return at


def _before(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    indices: List[Int],
    left: Int,
    right: Int,
    dim: Int,
) -> Bool:
    """Return whether the center at `left` is below the one at `right`."""
    return _coord(xs, ys, zs, indices[left], dim) < _coord(
        xs, ys, zs, indices[right], dim
    )


def _coord(
    xs: List[Float64],
    ys: List[Float64],
    zs: List[Float64],
    index: Int,
    dim: Int,
) -> Float64:
    """Return one coordinate of center `index`."""
    if dim == 0:
        return xs[index]
    if dim == 1:
        return ys[index]
    return zs[index]


def _axis(x: Float64, y: Float64, z: Float64, dim: Int) -> Float64:
    """Return one coordinate of a query."""
    if dim == 0:
        return x
    if dim == 1:
        return y
    return z


def _side(value: Float64, low: Float64, high: Float64) -> Float64:
    """Return the squared distance from `value` to `[low, high]`."""
    var gap = 0.0
    var above = _fsub(value, high)
    if above > gap:
        gap = above
    else:
        var below = _fsub(low, value)
        if below > gap:
            gap = below
    return _fmul(gap, gap)


def _sq(
    x: Float64,
    y: Float64,
    z: Float64,
    qx: Float64,
    qy: Float64,
    qz: Float64,
) -> Float64:
    """Return a squared Euclidean distance, each product rounded first."""
    var dx = _fsub(x, qx)
    var dy = _fsub(y, qy)
    var dz = _fsub(z, qz)
    return _fadd(_fadd(_fmul(dx, dx), _fmul(dy, dy)), _fmul(dz, dz))


def _keep_min(current: Float64, value: Float64) -> Float64:
    """Return `value` unless `current` is strictly smaller."""
    if current < value:
        return current
    return value


def _keep_max(current: Float64, value: Float64) -> Float64:
    """Return `value` unless `current` is strictly larger."""
    if current > value:
        return current
    return value


def _swap(mut values: List[Int], left: Int, right: Int):
    """Exchange two indexes."""
    var value = values[left]
    values[left] = values[right]
    values[right] = value


def _swap_float(mut values: List[Float64], left: Int, right: Int):
    """Exchange two heap priorities."""
    var value = values[left]
    values[left] = values[right]
    values[right] = value


def _lg(value: Int) -> Int:
    """Return the floor of the base-2 logarithm."""
    var bits = 0
    var rest = value
    while rest > 1:
        rest = rest // 2
        bits += 1
    return bits


def _inf() -> Float64:
    """Return positive infinity."""
    return bitcast[DType.float64](UInt64(0x7FF0000000000000))


def _nextafter(value: Float64, toward: Float64) -> Float64:
    """Return the next double after `value` toward `toward`."""
    return external_call["nextafter", Float64](value, toward)


def _means(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Append the mean of each triangle's three corners."""
    if doc.kind(node) != PY_LIST:
        raise Error("corners are not a list")
    for index in range(doc.length(node)):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("corner triangle is not 3 points")
        var x0 = json_number(doc, _corner(doc, triangle, 0, 0))
        var y0 = json_number(doc, _corner(doc, triangle, 0, 1))
        var z0 = json_number(doc, _corner(doc, triangle, 0, 2))
        var x1 = json_number(doc, _corner(doc, triangle, 1, 0))
        var y1 = json_number(doc, _corner(doc, triangle, 1, 1))
        var z1 = json_number(doc, _corner(doc, triangle, 1, 2))
        var x2 = json_number(doc, _corner(doc, triangle, 2, 0))
        var y2 = json_number(doc, _corner(doc, triangle, 2, 1))
        var z2 = json_number(doc, _corner(doc, triangle, 2, 2))
        xs.append(_fdiv(_fadd(_fadd(x0, x1), x2), 3.0))
        ys.append(_fdiv(_fadd(_fadd(y0, y1), y2), 3.0))
        zs.append(_fdiv(_fadd(_fadd(z0, z1), z2), 3.0))


def _corner(doc: PyJson, triangle: Int, point: Int, axis: Int) raises -> Int:
    """Return one coordinate node of a corner triangle."""
    var vertex = doc.item(triangle, point)
    if doc.kind(vertex) != PY_LIST or doc.length(vertex) != 3:
        raise Error("corner is not 3 numbers")
    return doc.item(vertex, axis)


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("count is not an integer")
    return Int(parse_float(doc.text(node)))


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fadd(left: Float64, right: Float64) -> Float64:
    """Return one sum, rounded before the next operation."""
    return left + right


@no_inline
def _fsub(left: Float64, right: Float64) -> Float64:
    """Return one difference, rounded before the next operation."""
    return left - right


def main() raises:
    """Print the nearest centers for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_near FILE", file=stderr)
        exit(2)
    try:
        print(near_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_near:", error, file=stderr)
        exit(1)
