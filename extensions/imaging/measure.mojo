# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure labels and distances in physical units.

`label_statistics` counts the voxels of a label, and gives its volume,
centroid, bounding box and the mean, minimum and maximum of the volume's
values inside it. The volume of a label is its voxel count times the
volume of one voxel. It is not the volume inside a smooth surface.

`voxel_distance` gives the length between two points in voxel units,
with the spacing of each axis. A point in voxel units can lie between
voxel centers.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.sdf.vector import V3, length, v3
from std.math import max, min
from units.si import Length64, METER, Volume64, CUBIC_METER


struct LabelStatistics(ImplicitlyCopyable):
    """The size, place and values of one label."""

    var voxels: Int
    """How many voxels have the label."""
    var volume: Volume64
    """The voxel count times the volume of one voxel."""
    var centroid: V3
    """The mean voxel center in the volume frame, in meters."""
    var low_i: Int
    """The smallest `i` of the label."""
    var low_j: Int
    """The smallest `j` of the label."""
    var low_k: Int
    """The smallest `k` of the label."""
    var high_i: Int
    """The largest `i` of the label."""
    var high_j: Int
    """The largest `j` of the label."""
    var high_k: Int
    """The largest `k` of the label."""
    var mean: Float64
    """The mean value inside the label."""
    var minimum: Float64
    """The smallest value inside the label."""
    var maximum: Float64
    """The largest value inside the label."""

    def __init__(out self):
        """Create the statistics of an empty label."""
        self.voxels = 0
        self.volume = Volume64(0, CUBIC_METER)
        self.centroid = v3(0, 0, 0)
        self.low_i = 0
        self.low_j = 0
        self.low_k = 0
        self.high_i = 0
        self.high_j = 0
        self.high_k = 0
        self.mean = 0
        self.minimum = 0
        self.maximum = 0


def label_statistics(
    map: LabelMap, volume: ImageVolume, label: LabelId
) raises -> LabelStatistics:
    """Return the size, place and values of one label.

    Args:
        map: The label map.
        volume: The volume the map was made for. Its spacing applies.
        label: The label. Not the background.

    Returns:
        The statistics.

    Raises:
        Error: If the grids differ, the label is not valid or is the
            background, or the label has no voxels.
    """
    require_same_grid(map, volume)
    require_label(label)
    if label == BACKGROUND:
        raise Error("Statistics need a label other than the background")
    var mark = UInt8(label.value)
    var out = LabelStatistics()
    out.low_i = volume.nx
    out.low_j = volume.ny
    out.low_k = volume.nz
    out.high_i = -1
    out.high_j = -1
    out.high_k = -1
    var sum_i = 0.0
    var sum_j = 0.0
    var sum_k = 0.0
    var total = 0.0
    var low = 0.0
    var high = 0.0
    for k in range(volume.nz):  # pragma: no branch
        for j in range(volume.ny):  # pragma: no branch
            for i in range(volume.nx):  # pragma: no branch
                var at = volume.index(i, j, k)
                if map.labels[at] != mark:
                    continue
                var value = Float64(volume.values[at])
                if out.voxels == 0:
                    low = value
                    high = value
                low = min(low, value)
                high = max(high, value)
                out.voxels += 1
                total += value
                sum_i += Float64(i)
                sum_j += Float64(j)
                sum_k += Float64(k)
                out.low_i = min(out.low_i, i)
                out.low_j = min(out.low_j, j)
                out.low_k = min(out.low_k, k)
                out.high_i = max(out.high_i, i)
                out.high_j = max(out.high_j, j)
                out.high_k = max(out.high_k, k)
    if out.voxels == 0:
        raise Error("The label has no voxels")
    var n = Float64(out.voxels)
    var sx = volume.spacing_x.to(METER)
    var sy = volume.spacing_y.to(METER)
    var sz = volume.spacing_z.to(METER)
    out.volume = Volume64(n * sx * sy * sz, CUBIC_METER)
    out.centroid = v3(sum_i / n * sx, sum_j / n * sy, sum_k / n * sz)
    out.mean = total / n
    out.minimum = low
    out.maximum = high
    return out


def voxel_distance(volume: ImageVolume, a: V3, b: V3) -> Length64:
    """Return the length between two points given in voxel units.

    Args:
        volume: The volume whose spacing applies.
        a: The first point, in voxel units.
        b: The second point, in voxel units.

    Returns:
        The length.
    """
    var d = b - a
    var physical = v3(
        d.x * volume.spacing_x.to(METER),
        d.y * volume.spacing_y.to(METER),
        d.z * volume.spacing_z.to(METER),
    )
    return Length64(length(physical), METER)
