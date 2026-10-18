# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Order index entries by the center of their bounds.

The primitive index and the CCD index split on this key.
"""

from math.bounds import Box3


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
