# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Grow, shrink, open and close a label by a ball of a given radius.

A threshold leaves small faults in a label: a speck, a thin bridge, a
hole. Morphology cleans them with a ball whose radius is a length, so
that a volume of thick slices gets a ball of the right shape.

- `dilate_label` gives the label to each background voxel within the
  radius of a voxel of the label. Other labels do not change.
- `erode_label` takes the label from each of its voxels within the
  radius of a voxel outside it. The grid counts as surrounded by
  voxels outside the label, so a label also shrinks from the grid's
  edge.
- `open_label` erodes and then dilates: it removes specks and thin
  bridges, and keeps the bulk.
- `close_label` dilates and then erodes: it fills holes and narrow gaps.
  Its erosion does not shrink the label from the grid's edge, so a
  closed label holds every voxel of the label before it.

The distances are center to center, with the spacing of each axis, and
exact: `seed_distances` gives them.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.labels import LabelMap
from extensions.imaging.thickness import seed_distances
from std.math import isfinite
from units.si import Length64, METER

# Distances equal to the radius count as within it, to this relative
# rounding.
comptime ROUNDING = 1.0e-9


def _require(label: LabelId, radius: Length64) raises -> Float64:
    """Refuse the background, a bad label or a bad radius."""
    require_label(label)
    if label == BACKGROUND:
        raise Error("Morphology needs a label other than the background")
    var reach = radius.to(METER)
    if not (reach >= 0) or not isfinite(reach):
        raise Error("A morphology radius must be zero or more, and finite")
    return reach * (1.0 + ROUNDING)


def dilate_label(
    map: LabelMap, label: LabelId, radius: Length64
) raises -> LabelMap:
    """Return a copy with the label grown by a ball.

    Args:
        map: The label map.
        label: The label to grow. Not the background.
        radius: The radius of the ball. Zero or more.

    Returns:
        The map with each background voxel within `radius` of the label
        given the label.

    Raises:
        Error: If the label is not valid or is the background, or the
            radius is negative or not finite.
    """
    var reach = _require(label, radius)
    var mark = UInt8(label.value)
    var seeds = List[Bool](capacity=map.count())
    for index in range(map.count()):  # pragma: no branch
        seeds.append(map.labels[index] == mark)
    var distances = seed_distances(map, seeds, False)
    var out = map.copy()
    for index in range(map.count()):  # pragma: no branch
        var free = map.labels[index] == UInt8(BACKGROUND.value)
        if free and distances[index].to(METER) <= reach:
            out.labels[index] = mark
    return out^


def erode_label(
    map: LabelMap, label: LabelId, radius: Length64
) raises -> LabelMap:
    """Return a copy with the label shrunk by a ball.

    Args:
        map: The label map.
        label: The label to shrink. Not the background.
        radius: The radius of the ball. Zero or more.

    Returns:
        The map with each voxel of the label within `radius` of a voxel
        outside it given to the background.

    Raises:
        Error: If the label is not valid or is the background, or the
            radius is negative or not finite.
    """
    return _erode(map, label, _require(label, radius), True)


def _erode(
    map: LabelMap, label: LabelId, reach: Float64, border: Bool
) raises -> LabelMap:
    """Shrink a label, with or without the grid's edge as its outside."""
    var mark = UInt8(label.value)
    var seeds = List[Bool](capacity=map.count())
    for index in range(map.count()):  # pragma: no branch
        seeds.append(map.labels[index] != mark)
    var distances = seed_distances(map, seeds, border)
    var out = map.copy()
    for index in range(map.count()):  # pragma: no branch
        var inside = map.labels[index] == mark
        if inside and distances[index].to(METER) <= reach:
            out.labels[index] = UInt8(BACKGROUND.value)
    return out^


def open_label(
    map: LabelMap, label: LabelId, radius: Length64
) raises -> LabelMap:
    """Return a copy with the label eroded and then dilated.

    Args:
        map: The label map.
        label: The label. Not the background.
        radius: The radius of the ball. Zero or more.

    Returns:
        The opened map: specks and thin bridges narrower than the ball
        are gone.

    Raises:
        Error: If the label is not valid or is the background, or the
            radius is negative or not finite.
    """
    return dilate_label(erode_label(map, label, radius), label, radius)


def close_label(
    map: LabelMap, label: LabelId, radius: Length64
) raises -> LabelMap:
    """Return a copy with the label dilated and then eroded.

    Args:
        map: The label map.
        label: The label. Not the background.
        radius: The radius of the ball. Zero or more.

    Returns:
        The closed map: holes and gaps narrower than the ball are filled.
        The erosion here does not count the grid's edge as outside, so
        no voxel of the label is lost.

    Raises:
        Error: If the label is not valid or is the background, or the
            radius is negative or not finite.
    """
    var reach = _require(label, radius)
    return _erode(dilate_label(map, label, radius), label, reach, False)
