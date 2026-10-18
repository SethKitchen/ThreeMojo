# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Order index entries by the center of their bounds.

The primitive index and the CCD index split on this key, and both walk
the tree it builds.
"""

from math.bounds import Box3
from std.math import max


def bounds_center(box: Box3, axis: Int) -> Float64:
    """Return the sum of the low and high coordinates on one axis.

    Args:
        box: The bounds.
        axis: Zero for x, one for y, and any other value for z.

    Returns:
        The sum. It orders boxes by their center on that axis.
    """
    if axis == 0:
        return Float64(box.min.x) + Float64(box.max.x)
    if axis == 1:
        return Float64(box.min.y) + Float64(box.max.y)
    return Float64(box.min.z) + Float64(box.max.z)


def sort_by_center(
    boxes: List[Box3],
    mut order: List[Int],
    mut buffer: List[Int],
    start: Int,
    end: Int,
    axis: Int,
):
    """Order one range of indices by `bounds_center`.

    Args:
        boxes: The bounds each index names.
        order: The indices to order. The sort writes this range.
        buffer: Scratch with the same length as `order`.
        start: The first index of the range.
        end: One past the last index of the range.
        axis: The axis passed to `bounds_center`.
    """
    var width = 1
    while width < end - start:
        # The surrounding condition proves start < end.
        for low in range(start, end, 2 * width):  # pragma: no branch
            var mid = min(low + width, end)
            var high = min(low + 2 * width, end)
            var left = low
            var right = mid
            # A run has at least one entry: low < end and width >= 1.
            for k in range(low, high):  # pragma: no branch
                if right < high and (
                    left >= mid
                    or bounds_center(boxes[order[right]], axis)
                    < bounds_center(boxes[order[left]], axis)
                ):
                    buffer[k] = order[right]
                    right += 1
                else:
                    buffer[k] = order[left]
                    left += 1
            # A run has at least one entry: low < end and width >= 1.
            for k in range(low, high):  # pragma: no branch
                order[k] = buffer[k]
        width *= 2


@fieldwise_init
struct _MedianView(ImplicitlyCopyable):
    """A node's box, leaf entry, and escape link."""

    var box: Box3
    var entry: Int
    var escape: Int


trait _MedianNode(ImplicitlyCopyable, Movable):
    """A tree node with a box, a leaf entry, and an escape link."""

    @staticmethod
    def blank(box: Box3) -> Self:
        """Return an interior node whose box is `box`.

        Args:
            box: The bounds of this node.

        Returns:
            A node with no entry and an unset escape.
        """
        ...

    def set_entry(mut self, entry: Int):
        """Record the leaf's entry.

        Args:
            entry: The index this leaf holds.
        """
        ...

    def set_escape(mut self, escape: Int):
        """Record the index just past this node's subtree.

        Args:
            escape: One past the last node of the subtree.
        """
        ...

    def median_view(self) -> _MedianView:
        """Return this node's box, entry, and escape.

        Returns:
            The view.
        """
        ...


def _longest_axis(box: Box3) -> Int:
    """Return the longest side of `box`: 0, 1, or 2."""
    var dx = Float64(box.max.x) - Float64(box.min.x)
    var dy = Float64(box.max.y) - Float64(box.min.y)
    var dz = Float64(box.max.z) - Float64(box.min.z)
    var axis = 0
    if dy > dx:
        axis = 1
    if dz > max(dx, dy):
        axis = 2
    return axis


def build_median[
    N: _MedianNode
](
    mut nodes: List[N],
    boxes: List[Box3],
    mut order: List[Int],
    mut buffer: List[Int],
    start: Int,
    end: Int,
):
    """Append a median tree of one range of boxes.

    One leaf holds one entry. A wider range splits on its longest axis,
    at the median, and the two halves follow. `start` is less than `end`.

    Args:
        nodes: The tree, appended to.
        boxes: The bounds each index names.
        order: The indices of this range, reordered by the split.
        buffer: Scratch with the same length as `order`.
        start: The first index of the range.
        end: One past the last index of the range.
    """
    var box = boxes[order[start]]
    for i in range(start + 1, end):
        box.expand_by_point(boxes[order[i]].min)
        box.expand_by_point(boxes[order[i]].max)
    var node = len(nodes)
    nodes.append(N.blank(box))
    if end - start == 1:
        nodes[node].set_entry(order[start])
    else:
        sort_by_center(boxes, order, buffer, start, end, _longest_axis(box))
        var middle = start + (end - start) // 2
        build_median(nodes, boxes, order, buffer, start, middle)
        build_median(nodes, boxes, order, buffer, middle, end)
    nodes[node].set_escape(len(nodes))


def collect_median[
    N: _MedianNode,
    Q: ImplicitlyCopyable,
    //,
    misses: def(Q, Box3) thin -> Bool,
](nodes: List[N], query: Q, mut found: List[Int]) -> Int:
    """Walk a median tree and keep every leaf `misses` does not reject.

    Parameters:
        N: The node type.
        Q: The query.
        misses: True when a node's box is outside the query.

    Args:
        nodes: The tree, with escape links.
        query: What `misses` tests each box against.
        found: The leaf entries, replaced.

    Returns:
        How many nodes the walk read.
    """
    found.clear()
    var visited = 0
    var i = 0
    while i < len(nodes):
        visited += 1
        var node = nodes[i].median_view()
        if misses(query, node.box):
            i = node.escape
            continue
        if node.entry >= 0:
            found.append(node.entry)
        i += 1
    return visited
