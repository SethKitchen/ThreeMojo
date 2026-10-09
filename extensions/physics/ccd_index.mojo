# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Conservative candidates for the immutable world-space CCD mesh snapshot.

This private index never owns mutable body state or changes sweep predicates.
Each triangle occurs once. Median splits bound depth by ceil(log2(T)); escape
links bound a query to at most 2*T-1 node visits, without a traversal stack.
"""

from extensions.physics.bvh import median_order, split_axis
from extensions.physics.shape import _wide
from math.bounds import Box3
from math.triangle import Triangle
from std.memory import bitcast


def _up(value: Float64) -> Float64:
    # Query operands are finite in the checked CCD domain. Include both
    # signs of zero; returning the next positive subnormal is conservative.
    if value == 0:
        return bitcast[DType.float64](UInt64(1))
    var bits = bitcast[DType.uint64](value)
    return bitcast[DType.float64](bits + 1 if value > 0 else bits - 1)


def _down(value: Float64) -> Float64:
    return -_up(-value)


def _bounds(
    start: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    reach: Float64,
) -> Tuple[SIMD[DType.float64, 4], SIMD[DType.float64, 4]]:
    # Round each addition outward, before the next operation. There is no
    # Float32 query conversion. Stored Float32 triangle bounds widen exactly
    # to Float64, including thin boxes and large-coordinate endpoint ties.
    var low = SIMD[DType.float64, 4](0)
    var high = SIMD[DType.float64, 4](0)
    for axis in range(3):  # pragma: no branch
        var end = start[axis] + travel[axis]
        low[axis] = _down(min(start[axis], _down(end)) - reach)
        high[axis] = _up(max(start[axis], _up(end)) + reach)
    return (low, high)


@fieldwise_init
struct _CCDNode(ImplicitlyCopyable):
    var box: Box3
    var entry: Int
    var escape: Int


struct _Builder(Movable):
    # These O(T) arrays are build scratch and are not retained by the world.
    var nodes: List[_CCDNode]
    var boxes: List[Box3]
    var order: List[Int]
    var buffer: List[Int]

    def __init__(out self, triangles: List[Triangle]):
        var count = len(triangles)
        self.nodes = List[_CCDNode](capacity=2 * count - 1)
        self.boxes = List[Box3](capacity=count)
        self.order = List[Int](capacity=count)
        # The index selects this builder only above eight triangles.
        for i in range(count):  # pragma: no branch
            var box = Box3(triangles[i].a, triangles[i].a)
            box.expand_by_point(triangles[i].b)
            box.expand_by_point(triangles[i].c)
            self.boxes.append(box)
            self.order.append(i)
        self.buffer = self.order.copy()
        self._build(0, count)

    def _build(mut self, start: Int, end: Int):
        var box = self.boxes[self.order[start]]
        for i in range(start + 1, end):
            box.expand_by_point(self.boxes[self.order[i]].min)
            box.expand_by_point(self.boxes[self.order[i]].max)
        var node = len(self.nodes)
        self.nodes.append(_CCDNode(box, -1, 0))
        if end - start == 1:
            self.nodes[node].entry = self.order[start]
        else:
            median_order(
                self.boxes, self.order, self.buffer, start, end, split_axis(box)
            )
            var middle = start + (end - start) // 2
            self._build(start, middle)
            self._build(middle, end)
        self.nodes[node].escape = len(self.nodes)


struct _CCDIndex(Movable):
    var nodes: List[_CCDNode]
    # -1 is invalid. The snapshot can only append through add_body, which
    # replaces this cache. The complete mesh check must precede rebuild.
    var count: Int

    def __init__(out self):
        self.nodes = List[_CCDNode]()
        self.count = -1

    def rebuild(mut self, triangles: List[Triangle]):
        var count = len(triangles)
        if count <= 8:
            # Linear traversal avoids tree build/query overhead on tiny meshes.
            self.nodes = List[_CCDNode]()
        else:
            var builder = _Builder(triangles)
            swap(self.nodes, builder.nodes)
        self.count = count

    def query(
        self,
        start: SIMD[DType.float64, 4],
        travel: SIMD[DType.float64, 4],
        reach: Float64,
        mut found: List[Int],
    ) -> Int:
        found.clear()
        var bounds = _bounds(start, travel, reach)
        var visited = 0
        var i = 0
        while i < len(self.nodes):
            visited += 1
            ref node = self.nodes[i]
            var low = _wide(node.box.min)
            var high = _wide(node.box.max)
            var overlaps = True
            for axis in range(3):  # pragma: no branch
                if high[axis] < bounds[0][axis] or low[axis] > bounds[1][axis]:
                    overlaps = False
                    break
            if not overlaps:
                i = node.escape
                continue
            if node.entry >= 0:
                found.append(node.entry)
            i += 1
        return visited
