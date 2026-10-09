# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Median BVH partition shared by the physics indexes.

The primitive index and the CCD mesh index both split boxes on the
longest axis and sort that range by center. The node type stays with
each index. This module owns only the partition.
"""

from math.bounds import Box3


def box_center_key(box: Box3, axis: Int) -> Float64:
    """Return the center of `box` on `axis`, as the sum of its ends.

    Args:
        box: One indexed box.
        axis: `0` for x, `1` for y, and any other value for z.

    Returns:
        The sum of the low and high coordinates on that axis.
    """
    if axis == 0:
        return Float64(box.min.x) + Float64(box.max.x)
    if axis == 1:
        return Float64(box.min.y) + Float64(box.max.y)
    return Float64(box.min.z) + Float64(box.max.z)


def split_axis(box: Box3) -> Int:
    """Return the longest axis of `box`.

    Args:
        box: The bounds of one partition.

    Returns:
        `0` for x, `1` for y, or `2` for z. An equal length keeps the
        earlier axis.
    """
    var dx = Float64(box.max.x) - Float64(box.min.x)
    var dy = Float64(box.max.y) - Float64(box.min.y)
    var dz = Float64(box.max.z) - Float64(box.min.z)
    var axis = 0
    if dy > dx:
        axis = 1
    if dz > max(dx, dy):
        axis = 2
    return axis


def median_order(
    boxes: List[Box3],
    mut order: List[Int],
    mut buffer: List[Int],
    start: Int,
    end: Int,
    axis: Int,
):
    """Sort `order[start:end]` by box center on `axis`.

    The sort is stable. `buffer` must hold at least as many entries as
    `order`.

    Args:
        boxes: Bounds addressed by the indices in `order`.
        order: The permutation to sort.
        buffer: Scratch with the same length as `order`.
        start: First index of the range.
        end: One past the last index of the range.
        axis: The axis from `split_axis` or a caller-chosen axis.
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
                    or box_center_key(boxes[order[right]], axis)
                    < box_center_key(boxes[order[left]], axis)
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
