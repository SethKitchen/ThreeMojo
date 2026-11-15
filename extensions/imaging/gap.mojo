# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The distance between two labels, such as a tumor and a vessel.

- `distance_from_label` gives each voxel its distance to the nearest
  voxel of a label, as a volume in millimeters. A voxel of the label is
  0. Draw it on a slice, or read it at the voxels of another label.
- `label_gap` gives the least distance between a voxel of one label and
  a voxel of another, and the two voxels.
- `volume_within` gives the volume of one label within a distance of
  another, such as the part of an organ within 5 mm of a tumor.

Every distance is center to center, with the spacing of each axis, and
exact: `seed_distances` gives it. So two labels that share a face are
one spacing apart. The clear space between the faces of their voxels is
less, by about one voxel.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.thickness import seed_distances
from std.math import isfinite, sqrt
from units.si import CUBIC_METER, METER, MILLIMETER64, Length64, Volume64

# Distances equal to the limit count as within it, to this relative
# rounding.
comptime ROUNDING = 1.0e-9


def _require_region(map: LabelMap, label: LabelId) raises:
    """Refuse a bad label, the background or an empty label."""
    require_label(label)
    if label == BACKGROUND:
        raise Error("A distance is measured from a label, not the background")
    if map.voxels(label) == 0:
        raise Error("The label has no voxels")


def _require_pair(map: LabelMap, first: LabelId, second: LabelId) raises:
    """Refuse a bad pair of labels."""
    _require_region(map, first)
    _require_region(map, second)
    if first == second:
        raise Error("A gap is measured between two different labels")


def _distances(map: LabelMap, label: LabelId) raises -> List[Length64]:
    """Return the distance of each voxel to the nearest voxel of a label."""
    var mark = UInt8(label.value)
    var seeds = List[Bool](capacity=map.count())
    for index in range(map.count()):  # pragma: no branch
        seeds.append(map.labels[index] == mark)
    return seed_distances(map, seeds, False)


def distance_from_label(map: LabelMap, label: LabelId) raises -> ImageVolume:
    """Return the distance of each voxel to the nearest voxel of a label,
    center to center, in millimeters.

    Args:
        map: The label map.
        label: The label. Not the background.

    Returns:
        A volume on the grid of the map. A voxel of the label is 0.

    Raises:
        Error: If the label is not valid, is the background or has no
            voxels.
    """
    _require_region(map, label)
    var distances = _distances(map, label)
    var out = ImageVolume(
        map.nx, map.ny, map.nz, map.spacing_x, map.spacing_y, map.spacing_z
    )
    for index in range(map.count()):  # pragma: no branch
        out.values[index] = Float32(distances[index].to(MILLIMETER64))
    out.fit_window()
    return out^


@fieldwise_init
struct LabelGap(Copyable, Movable):
    """The least distance between two labels, and where it is."""

    var distance: Length64
    """The distance between the centers of the two voxels."""
    var first_voxel: Tuple[Int, Int, Int]
    """The voxel `(i, j, k)` of the first label."""
    var second_voxel: Tuple[Int, Int, Int]
    """The voxel `(i, j, k)` of the second label."""


def label_gap(
    map: LabelMap, first: LabelId, second: LabelId
) raises -> LabelGap:
    """Return the least distance between the voxels of two labels.

    Of the voxels of `second` at the least distance, the one with the
    lowest index counts. Of the voxels of `first` nearest to it, the one
    with the lowest index counts.

    Args:
        map: The label map.
        first: One label. Not the background.
        second: The other label. Not the background, and not `first`.

    Returns:
        The distance and the two voxels.

    Raises:
        Error: If a label is not valid, is the background or has no
            voxels, or the two labels are the same.
    """
    _require_pair(map, first, second)
    var distances = _distances(map, first)
    var to = UInt8(second.value)
    var near = -1
    for index in range(map.count()):  # pragma: no branch
        if map.labels[index] != to:
            continue
        if near < 0 or distances[index].to(METER) < distances[near].to(METER):
            near = index
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var sz = map.spacing_z.to(METER)
    var i = near % map.nx
    var j = (near // map.nx) % map.ny
    var k = near // (map.nx * map.ny)
    var mark = UInt8(first.value)
    var best = -1
    var least = 0.0
    for index in range(map.count()):  # pragma: no branch
        if map.labels[index] != mark:
            continue
        var di = Float64(index % map.nx - i) * sx
        var dj = Float64((index // map.nx) % map.ny - j) * sy
        var dk = Float64(index // (map.nx * map.ny) - k) * sz
        var squared = di * di + dj * dj + dk * dk
        if best < 0 or squared < least:
            best = index
            least = squared
    return LabelGap(
        Length64(sqrt(least), METER),
        (
            best % map.nx,
            (best // map.nx) % map.ny,
            best // (map.nx * map.ny),
        ),
        (i, j, k),
    )


def volume_within(
    map: LabelMap, first: LabelId, second: LabelId, limit: Length64
) raises -> Volume64:
    """Return the volume of the voxels of one label near another.

    A voxel of `second` counts when its center is within `limit` of the
    center of a voxel of `first`.

    Args:
        map: The label map.
        first: The label to measure from. Not the background.
        second: The label to measure. Not the background, and not
            `first`.
        limit: The distance. At least 0 and finite.

    Returns:
        The volume of the voxels of `second` that count.

    Raises:
        Error: If a label is not valid, is the background or has no
            voxels, the two labels are the same, or `limit` is negative
            or not finite.
    """
    _require_pair(map, first, second)
    var reach = limit.to(METER)
    if not isfinite(reach) or reach < 0:
        raise Error("A distance limit must be at least 0 and finite")
    var distances = _distances(map, first)
    var to = UInt8(second.value)
    var count = 0
    for index in range(map.count()):  # pragma: no branch
        if map.labels[index] == to and distances[index].to(METER) <= reach * (
            1.0 + ROUNDING
        ):
            count += 1
    var voxel = (
        map.spacing_x.to(METER)
        * map.spacing_y.to(METER)
        * map.spacing_z.to(METER)
    )
    return Volume64(Float64(count) * voxel, CUBIC_METER)
