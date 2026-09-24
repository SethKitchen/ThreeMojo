# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The KD-tree of a Draco point cloud as Draco's encoder writes it, from
Draco 1.5.6: the other half of `loaders.draco_kd_tree`.

Draco's `DynamicIntegerPointsKdTreeEncoder` splits the points in half
along one axis at a time, and writes how many fall on each side. A group
of one or two points writes their remaining bits. The compression level,
from 0 to 6, picks the coders of these numbers, and at level 6 the axis
that splits the points most evenly.

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.

**Order.** Draco sorts the points of each split with `std::partition`
from the C++ library that its WebAssembly build links, libc++. The order
of the two points of a group changes the bits written, so `_partition`
ports libc++'s algorithm for bidirectional iterators.
"""

from exporters.draco_writer import (
    DirectBitEncoder,
    DracoWriter,
    FoldedBitEncoder,
    RAnsBitEncoder,
)
from loaders.draco_buffer import MASK32, most_significant_bit

# The fewest points for which level 6 picks the axis by the points.
comptime _AXIS_BY_POINTS = 64


struct _Numbers(Movable):
    """The coder of the split counts, which the level picks."""

    var level: Int
    var direct: DirectBitEncoder
    var rans: RAnsBitEncoder
    var folded: FoldedBitEncoder

    def __init__(out self, level: Int):
        self.level = level
        self.direct = DirectBitEncoder()
        self.rans = RAnsBitEncoder()
        self.folded = FoldedBitEncoder()

    def encode(mut self, count: Int, value: Int):
        if self.level < 2:
            self.direct.encode_bits(count, value)
        elif self.level < 4:
            self.rans.encode_bits(count, value)
        else:
            self.folded.encode_bits(count, value)

    def end(self, mut out: DracoWriter):
        if self.level < 2:
            self.direct.end(out)
        elif self.level < 4:
            self.rans.end(out)
        else:
            self.folded.end(out)


def _partition(
    mut order: List[Int],
    var first: Int,
    var last: Int,
    points: List[Int],
    dimension: Int,
    axis: Int,
    split: Int,
) -> Int:
    """libc++'s `std::partition` for bidirectional iterators: the points
    below `split` on `axis` move to the front. Returns where the rest
    start."""
    while True:
        while True:
            if first == last:
                return first
            if points[order[first] * dimension + axis] >= split:
                break
            first += 1
        while True:
            last -= 1
            if first == last:
                return first
            if points[order[last] * dimension + axis] < split:
                break
        var t = order[first]
        order[first] = order[last]
        order[last] = t
        first += 1


struct _Tree(Movable):
    """The state of `DynamicIntegerPointsKdTreeEncoder`."""

    var level: Int
    var bits: Int
    var dimension: Int
    var points: List[Int]
    var order: List[Int]
    var numbers: _Numbers
    var remaining: DirectBitEncoder
    var axes: DirectBitEncoder
    var halves: DirectBitEncoder
    var bases: List[List[Int]]
    var levels: List[List[Int]]

    def __init__(
        out self, level: Int, bits: Int, dimension: Int, var points: List[Int]
    ):
        self.level = level
        self.bits = bits
        self.dimension = dimension
        var count = len(points) // dimension
        self.points = points^
        self.order = List[Int](capacity=count)
        # A point cloud has a point: the loop runs.
        for i in range(count):  # pragma: no branch
            self.order.append(i)
        self.numbers = _Numbers(level)
        self.remaining = DirectBitEncoder()
        self.axes = DirectBitEncoder()
        self.halves = DirectBitEncoder()
        self.bases = List[List[Int]]()
        self.levels = List[List[Int]]()
        # A point has three coordinates or more: the loop runs.
        for _ in range(32 * dimension + 1):  # pragma: no branch
            self.bases.append(List[Int](length=dimension, fill=0))
            self.levels.append(List[Int](length=dimension, fill=0))

    def value(self, at: Int, axis: Int) -> Int:
        """One coordinate of the point at position `at` of the order."""
        return self.points[self.order[at] * self.dimension + axis]

    def axis(
        mut self,
        begin: Int,
        end: Int,
        base: List[Int],
        levels: List[Int],
        last_axis: Int,
    ) -> Int:
        """Draco's `GetAndEncodeAxis`."""
        if self.level < 6:
            return (last_axis + 1) % self.dimension
        var best = 0
        if end - begin < _AXIS_BY_POINTS:
            # A point has three coordinates or more: the loop runs.
            for axis in range(1, self.dimension):  # pragma: no branch
                if levels[best] > levels[axis]:
                    best = axis
            return best
        var size = end - begin
        var most = 0
        # A point has three coordinates or more: the loop runs.
        for i in range(self.dimension):  # pragma: no branch
            var left = self.bits - levels[i]
            if left == 0:
                continue
            var split = (base[i] + (1 << (left - 1))) & MASK32
            var below = 0
            # This group has 64 points or more: the loop runs.
            for at in range(begin, end):  # pragma: no branch
                if self.value(at, i) < split:
                    below += 1
            var deviation = max(size - below, below)
            if most < deviation:
                most = deviation
                best = i
        self.axes.encode_bits(4, best)
        return best

    def encode(mut self):
        """Draco's `EncodeInternal`."""
        var stack = List[Tuple[Int, Int, Int, Int]]()
        stack.append((0, len(self.order), 0, 0))
        while len(stack) > 0:
            var status = stack.pop()
            var begin = status[0]
            var end = status[1]
            var at = status[3]
            var base = self.bases[at].copy()
            var levels = self.levels[at].copy()
            var axis = self.axis(begin, end, base, levels, status[2])
            var level = levels[axis]
            var count = end - begin
            if self.bits - level == 0:
                continue
            if count <= 2:
                # A group holds one point or two, of three coordinates or
                # more: the loops run.
                for i in range(count):  # pragma: no branch
                    var a = axis
                    for _ in range(self.dimension):  # pragma: no branch
                        var left = self.bits - levels[a]
                        if left != 0:
                            self.remaining.encode_bits(
                                left, self.value(begin + i, a)
                            )
                        a = (a + 1) % self.dimension
                continue
            var modifier = 1 << (self.bits - level - 1)
            self.bases[at + 1] = base.copy()
            self.bases[at + 1][axis] = (base[axis] + modifier) & MASK32
            var split = _partition(
                self.order,
                begin,
                end,
                self.points,
                self.dimension,
                axis,
                self.bases[at + 1][axis],
            )
            var required = most_significant_bit(count)
            var first = split - begin
            var second = end - split
            var left = first < second
            if first != second:
                self.halves.encode_bit(left)
            if left:
                self.numbers.encode(required, count // 2 - first)
            else:
                self.numbers.encode(required, count // 2 - second)
            self.levels[at][axis] += 1
            self.levels[at + 1] = self.levels[at].copy()
            if split != begin:
                stack.append((begin, split, axis, at))
            if split != end:
                stack.append((split, end, axis, at + 1))


def encode_kd_tree(
    mut out: DracoWriter, var points: List[Int], dimension: Int, level: Int
):
    """Write points as Draco's KD-tree.

    Draco's `DynamicIntegerPointsKdTreeEncoder::EncodePoints`, after the
    level byte that `KdTreeAttributesEncoder` writes: the bits of the
    widest coordinate, the points, then the four streams.

    Args:
        out: Where to write them.
        points: The unsigned coordinates, `dimension` to each point.
        dimension: The coordinates of each point.
        level: The compression level, from 0 to 6.
    """
    var bits = 0
    # A point cloud has a point: the loop runs.
    for v in points:  # pragma: no branch
        if v > 0:
            bits = max(bits, most_significant_bit(v) + 1)
    var count = len(points) // dimension
    out.u8(level)
    out.u32(bits)
    out.u32(count)
    var tree = _Tree(level, bits, dimension, points^)
    tree.encode()
    tree.numbers.end(out)
    tree.remaining.end(out)
    tree.axes.end(out)
    tree.halves.end(out)
