# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The KD-tree coding of a Draco point cloud, from Draco 1.5.6.

Draco's `DynamicIntegerPointsKdTreeDecoder`. The points are unsigned
integers of `dimension` components. The tree splits the box of the
points in half along one axis at a time, and stores how many points fall
in each half. A box of one or two points stores their remaining bits.

The compression level, from 0 to 6, picks the bit coders:

| Levels | Counts | Axis |
|---|---|---|
| 0 and 1 | Raw bits | The next axis. |
| 2 and 3 | Binary rANS | The next axis. |
| 4 and 5 | Binary rANS, one stream for each bit | The next axis. |
| 6 | Binary rANS, one stream for each bit | The least split axis, or a stored one. |

Draco is Copyright 2016 The Draco Authors, under the Apache License 2.0.
See THIRD-PARTY-NOTICES.md.
"""

from loaders.draco_buffer import (
    DirectBitDecoder,
    DracoBuffer,
    FoldedBitDecoder,
    RAnsBitDecoder,
    draco_require,
    most_significant_bit,
)


struct _Numbers(Movable):
    """The coder of the counts, which depends on the level."""

    var level: Int
    var direct: DirectBitDecoder
    var rans: RAnsBitDecoder
    var folded: FoldedBitDecoder

    def __init__(out self, level: Int):
        self.level = level
        self.direct = DirectBitDecoder()
        self.rans = RAnsBitDecoder()
        self.folded = FoldedBitDecoder()

    def start(mut self, mut buffer: DracoBuffer) raises:
        if self.level < 2:
            self.direct.start(buffer)
        elif self.level < 4:
            self.rans.start(buffer)
        else:
            self.folded.start(buffer)

    def bits(mut self, count: Int) raises -> Int:
        if self.level < 2:
            return self.direct.bits(count)
        if self.level < 4:
            return self.rans.bits(count)
        return self.folded.bits(count)


@fieldwise_init
struct _Box(Copyable, Movable):
    """A box still to decode: its points, the axis split last and where
    its base and levels are kept."""

    var points: Int
    var last_axis: Int
    var at: Int


def decode_kd_tree(
    mut buffer: DracoBuffer, level: Int, dimension: Int, expected: Int
) raises -> List[Int]:
    """Read the points of a KD-tree.

    Args:
        buffer: The cursor, at the 32-bit bit length.
        level: The compression level, from 0 to 6.
        dimension: The components of each point.
        expected: The points the file declares.

    Returns:
        The points, `dimension` components each, in the order they are
        decoded, which is the order of the point ids.

    Raises:
        Error: If the level is not from 0 to 6, the tree holds other than
            `expected` points, or its bits run out.
    """
    draco_require(
        level >= 0 and level <= 6, "a KD-tree level is not from 0 to 6"
    )
    var out = List[Int]()
    var bit_length = buffer.u32()
    draco_require(bit_length <= 32, "a KD-tree is wider than 32 bits")
    var count = buffer.u32()
    draco_require(count == expected, "a KD-tree holds the wrong points")
    if count == 0:
        return out^
    var numbers = _Numbers(level)
    numbers.start(buffer)
    var remaining = DirectBitDecoder()
    remaining.start(buffer)
    var axes = DirectBitDecoder()
    axes.start(buffer)
    var halves = DirectBitDecoder()
    halves.start(buffer)
    var depth = 32 * dimension + 1
    var bases = List[List[Int]]()
    var levels = List[List[Int]]()
    for _ in range(depth):  # pragma: no branch
        bases.append(List[Int](length=dimension, fill=0))
        levels.append(List[Int](length=dimension, fill=0))
    var stack = List[_Box]()
    stack.append(_Box(count, 0, 0))
    while len(stack) > 0:
        var box = stack.pop()
        var base = bases[box.at].copy()
        var axis: Int
        if level < 6:
            axis = (box.last_axis + 1) % dimension
        elif box.points < 64:
            axis = 0
            for k in range(1, dimension):
                if levels[box.at][axis] > levels[box.at][k]:
                    axis = k
        else:
            axis = axes.bits(4)
        draco_require(axis < dimension, "a KD-tree axis is not valid")
        var split = levels[box.at][axis]
        draco_require(split <= bit_length, "a KD-tree is split too deep")
        if split == bit_length:
            for _ in range(box.points):  # pragma: no branch
                out.extend(base.copy())
            continue
        if box.points <= 2:
            for _ in range(box.points):  # pragma: no branch
                var point = List[Int](length=dimension, fill=0)
                for j in range(dimension):  # pragma: no branch
                    var k = (axis + j) % dimension
                    var bits = bit_length - levels[box.at][k]
                    var value = 0
                    if bits > 0:
                        value = remaining.bits(bits)
                    point[k] = base[k] | value
                out.extend(point^)
            continue
        draco_require(box.at + 1 < depth, "a KD-tree is too deep")
        bases[box.at + 1] = base.copy()
        bases[box.at + 1][axis] += 1 << (bit_length - split - 1)
        var number = numbers.bits(most_significant_bit(box.points))
        var first = box.points // 2
        draco_require(number <= first, "a KD-tree count is not valid")
        first -= number
        var second = box.points - first
        if first != second and not halves.bit():
            var swap = first
            first = second
            second = swap
        levels[box.at][axis] += 1
        levels[box.at + 1] = levels[box.at].copy()
        if first > 0:
            stack.append(_Box(first, axis, box.at))
        if second > 0:
            stack.append(_Box(second, axis, box.at + 1))
    return out^
