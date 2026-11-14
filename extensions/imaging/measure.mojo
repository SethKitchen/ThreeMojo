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

`line_profile` samples the volume along a line in patient space, and
`full_width_half_maximum` measures the width of its peak: the distance
between the two places where the profile falls to halfway between its
peak and a baseline. It is the usual measure of the diameter of a
vessel with contrast, and of how sharp an image is.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.sdf.vector import V3, distance, length, v3
from std.math import isfinite, max, min
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


# A point is inside the box of voxel centers to this many voxels.
comptime INSIDE = 1.0e-9


struct LineProfile(Copyable, Movable):
    """The values of a volume at evenly spaced points along a line."""

    var distances: List[Length64]
    """The distance of each point from the start of the line."""
    var values: List[Float32]
    """The value at each point."""

    def __init__(out self):
        """Create an empty profile."""
        self.distances = List[Length64]()
        self.values = List[Float32]()


def line_profile(
    volume: ImageVolume, start: V3, end: V3, samples: Int, outside: Float32
) raises -> LineProfile:
    """Sample a volume at evenly spaced points from `start` to `end`.

    Args:
        volume: The volume.
        start: The first point, in patient space, in meters.
        end: The last point, in patient space, in meters.
        samples: The points, from 2 to 65536, the ends included.
        outside: The value of a point outside the box of voxel centers.

    Returns:
        The distance and the trilinear value of each point.

    Raises:
        Error: If a point is not finite, the two points are the same, or
            the samples are out of range.
    """
    if not isfinite(start.x + start.y + start.z + end.x + end.y + end.z):
        raise Error("A line profile needs finite points")
    if not (distance(start, end) > 0):
        raise Error("A line profile needs two different points")
    if samples < 2 or samples > 65536:
        raise Error("A line profile has from 2 to 65536 points")
    var out = LineProfile()
    var span = distance(start, end)
    var top = v3(
        Float64(volume.nx - 1) + INSIDE,
        Float64(volume.ny - 1) + INSIDE,
        Float64(volume.nz - 1) + INSIDE,
    )
    for k in range(samples):  # pragma: no branch
        var t = Float64(k) / Float64(samples - 1)
        var q = volume.voxel_point(start + (end - start) * t)
        var inside = (
            q.x >= -INSIDE
            and q.y >= -INSIDE
            and q.z >= -INSIDE
            and q.x <= top.x
            and q.y <= top.y
            and q.z <= top.z
        )
        out.distances.append(Length64(span * t, METER))
        if inside:
            out.values.append(volume.trilinear(q.x, q.y, q.z))
        else:
            out.values.append(outside)
    return out^


def _crossing(profile: LineProfile, a: Int, b: Int, half: Float64) -> Float64:
    """Return the distance, in meters, where the profile meets `half`
    between two neighbor points."""
    var da = profile.distances[a].to(METER)
    var db = profile.distances[b].to(METER)
    var va = Float64(profile.values[a])
    var vb = Float64(profile.values[b])
    return da + (db - da) * (half - va) / (vb - va)


def full_width_half_maximum(
    profile: LineProfile, baseline: Float64
) raises -> Length64:
    """Return the width of the highest peak of a profile at half its height.

    The half level lies halfway between the peak and `baseline`. On each
    side of the peak, the width runs to the first place where the profile
    falls to the half level, between two points by linear interpolation.

    Args:
        profile: The profile.
        baseline: The level of the background, such as 0 or -1000.

    Returns:
        The width.

    Raises:
        Error: If the peak is not above the baseline, or the profile does
            not fall to the half level on both sides of the peak.
    """
    var count = len(profile.values)
    var peak = 0
    for k in range(count):
        if profile.values[k] > profile.values[peak]:
            peak = k
    var top = Float64(profile.values[peak]) if count > 0 else baseline
    if not (top > baseline):
        raise Error("A profile's peak must be above its baseline")
    var half = baseline + (top - baseline) / 2
    var left = peak
    while left > 0 and Float64(profile.values[left - 1]) > half:
        left -= 1
    var right = peak
    while right < count - 1 and Float64(profile.values[right + 1]) > half:
        right += 1
    if left == 0 or right == count - 1:
        raise Error(
            "A profile must fall to half its peak on both sides of the peak"
        )
    var low = _crossing(profile, left - 1, left, half)
    var high = _crossing(profile, right, right + 1, half)
    return Length64(high - low, METER)
