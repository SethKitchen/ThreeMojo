# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Density measures of CT, for lung and body composition research.

The values of a CT volume are Hounsfield units (HU) after the rescale of
its files: -1000 for air, 0 for water.

- `low_attenuation_fraction(volume, map, label, threshold)` is the part of
  a label's voxels below a threshold. Emphysema research takes the lungs
  below -950 HU, the LAA-950.
- `attenuation_percentile(volume, map, label, percent)` is a percentile of
  a label's values, with linear interpolation between ranks, as numpy
  takes it. Perc15, the 15th percentile of the lungs, falls as emphysema
  grows.
- `tissue_area(volume, map, label, axis, index, low, high)` is the area of
  the pixels of a label on one slice whose values are from `low` to
  `high`. Body composition research takes the skeletal muscle from -29 to
  150 HU and the fat from -190 to -30 HU, on the slice of the third lumbar
  vertebra.
"""

from extensions.imaging.compare import percentile
from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    LabelId,
    SliceAxis,
    require_axis,
    require_label,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from std.math import isfinite
from units.si import Area64, METER, SQUARE_METER


def _values(
    volume: ImageVolume, map: LabelMap, label: LabelId
) raises -> List[Float64]:
    """Return the values of a label's voxels, after the checks."""
    require_label(label)
    if label == BACKGROUND:
        raise Error("A density measure needs a label, not the background")
    require_same_grid(map, volume)
    var mark = UInt8(label.value)
    var out = List[Float64]()
    for at in range(map.count()):  # pragma: no branch
        if map.labels[at] == mark:
            out.append(Float64(volume.values[at]))
    if len(out) == 0:
        raise Error("A density measure needs a label with voxels")
    return out^


def low_attenuation_fraction(
    volume: ImageVolume, map: LabelMap, label: LabelId, threshold: Float64
) raises -> Float64:
    """Return the part of a label's voxels below a threshold.

    Args:
        volume: The CT, in HU.
        map: The label map, on the grid of the volume.
        label: The label, such as the lungs. Not the background.
        threshold: The threshold, such as -950 HU. Finite.

    Returns:
        The part, from 0 to 1, of the voxels whose values are below the
        threshold.

    Raises:
        Error: If the label is not valid, is the background or has no
            voxel, the map is on another grid, or the threshold is not
            finite.
    """
    if not isfinite(threshold):
        raise Error("A density threshold must be finite")
    var values = _values(volume, map, label)
    var below = 0
    for v in values:  # pragma: no branch
        if v < threshold:
            below += 1
    return Float64(below) / Float64(len(values))


def attenuation_percentile(
    volume: ImageVolume, map: LabelMap, label: LabelId, percent: Float64
) raises -> Float64:
    """Return a percentile of a label's values.

    Args:
        volume: The CT, in HU.
        map: The label map, on the grid of the volume.
        label: The label. Not the background.
        percent: The percentile, from 0 to 100, such as 15.

    Returns:
        The value at rank `percent / 100 * (n - 1)` of the sorted values,
        between ranks by linear interpolation.

    Raises:
        Error: If the label is not valid, is the background or has no
            voxel, the map is on another grid, or the percentile is out of
            range.
    """
    return percentile(_values(volume, map, label), percent)


def tissue_area(
    volume: ImageVolume,
    map: LabelMap,
    label: LabelId,
    axis: SliceAxis,
    index: Int,
    low: Float64,
    high: Float64,
) raises -> Area64:
    """Return the area of a label's pixels on a slice in a range of values.

    Args:
        volume: The CT, in HU.
        map: The label map, on the grid of the volume.
        label: The label, such as the body. Not the background.
        axis: The axis that the slice holds constant.
        index: The slice, from 0.
        low: The least value, such as -29 HU. Finite.
        high: The largest value, such as 150 HU. Finite, and not below
            `low`.

    Returns:
        The number of pixels times the area of one pixel.

    Raises:
        Error: If the label is not valid or is the background, the map is
            on another grid, the axis or the slice is out of range, or the
            range is not finite or falls.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A tissue area needs a label, not the background")
    require_same_grid(map, volume)
    require_axis(axis)
    if not isfinite(low) or not isfinite(high) or not (low <= high):
        raise Error("A tissue range needs finite ends that do not fall")
    var sizes: List[Int] = [volume.nx, volume.ny, volume.nz]
    var steps: List[Float64] = [
        volume.spacing_x.to(METER),
        volume.spacing_y.to(METER),
        volume.spacing_z.to(METER),
    ]
    if index < 0 or index >= sizes[axis.value]:
        raise Error("The slice is outside the volume")
    var pixel = 1.0
    for a in range(3):  # pragma: no branch
        if a != axis.value:
            pixel *= steps[a]
    var mark = UInt8(label.value)
    var count = 0
    for k in range(volume.nz):  # pragma: no branch
        for j in range(volume.ny):  # pragma: no branch
            for i in range(volume.nx):  # pragma: no branch
                var place = k
                if axis == I_AXIS:
                    place = i
                elif axis == J_AXIS:
                    place = j
                if place != index:
                    continue
                var at = volume.index(i, j, k)
                if map.labels[at] != mark:
                    continue
                var v = Float64(volume.values[at])
                if v >= low and v <= high:
                    count += 1
    return Area64(Float64(count) * pixel, SQUARE_METER)
