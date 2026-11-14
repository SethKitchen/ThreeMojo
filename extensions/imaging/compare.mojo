# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare two segmentations of one volume.

A study that segments a structure two ways, such as by hand and by a
threshold, or by two readers, must say how well the two agree.
`compare_labels` gives the measures that segmentation studies report:

- The Dice coefficient `2 |A and B| / (|A| + |B|)` and the Jaccard index
  `|A and B| / |A or B|`, from 0 for no overlap to 1 for the same voxels.
- The surface distances. The surface of a label is each of its voxels
  with a face neighbor outside it, or on the grid's edge. Each surface
  voxel of one label has a distance to the nearest surface voxel of the
  other, center to center, with the spacing of each axis, and exact.

The Hausdorff distance is the largest of all those distances. The 95th
percentile Hausdorff distance (HD95) is the 95th percentile of the
distances of both labels together, with linear interpolation between
ranks. The average symmetric surface distance (ASSD) is their mean.
These are the definitions of the MedPy library. Some tools take the
larger of the two directed 95th percentiles instead, which is never
less.

`label_overlaps` compares two maps of many labels at once, such as two
segmentations of several organs. It gives the voxel counts, the Dice
coefficient and the Jaccard index of every label that either map holds,
in one pass over the grid.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.labels import LabelMap
from extensions.imaging.thickness import seed_distances
from std.math import floor
from units.si import CUBIC_METER, Length64, METER, Volume64


struct LabelComparison(Copyable, Movable):
    """How two labels on one grid agree."""

    var first_voxels: Int
    """The voxels of the first label."""
    var second_voxels: Int
    """The voxels of the second label."""
    var shared_voxels: Int
    """The voxels in both."""
    var dice: Float64
    """The Dice coefficient, from 0 to 1."""
    var jaccard: Float64
    """The Jaccard index, from 0 to 1."""
    var hausdorff: Length64
    """The largest distance from a surface voxel to the other surface."""
    var hausdorff_95: Length64
    """The 95th percentile of the surface distances of both labels."""
    var mean_surface_distance: Length64
    """The mean distance over the surface voxels of both labels."""
    var first_volume: Volume64
    """The volume of the first label."""
    var second_volume: Volume64
    """The volume of the second label."""

    def __init__(out self):
        """Create an empty comparison."""
        self.first_voxels = 0
        self.second_voxels = 0
        self.shared_voxels = 0
        self.dice = 0
        self.jaccard = 0
        self.hausdorff = Length64(0, METER)
        self.hausdorff_95 = Length64(0, METER)
        self.mean_surface_distance = Length64(0, METER)
        self.first_volume = Volume64(0, CUBIC_METER)
        self.second_volume = Volume64(0, CUBIC_METER)


def _mask(map: LabelMap, label: LabelId) raises -> List[Bool]:
    """Return the voxels of a label, refusing the background."""
    require_label(label)
    if label == BACKGROUND:
        raise Error("A comparison needs labels other than the background")
    var mark = UInt8(label.value)
    var out = List[Bool](capacity=map.count())
    var any = False
    for index in range(map.count()):  # pragma: no branch
        var inside = map.labels[index] == mark
        any = any or inside
        out.append(inside)
    if not any:
        raise Error("A label to compare has no voxels")
    return out^


def surface_voxels(map: LabelMap, mask: List[Bool]) raises -> List[Bool]:
    """Return the voxels of a mask with a face neighbor outside it.

    A voxel on the grid's edge counts as one of the surface.

    Args:
        map: The label map whose grid counts.
        mask: One flag per voxel, `i` fastest.

    Returns:
        One flag per voxel.

    Raises:
        Error: If the mask does not hold one flag per voxel.
    """
    if len(mask) != map.count():
        raise Error("A mask needs one flag per voxel")
    var out = List[Bool](length=map.count(), fill=False)
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                var at = map.index(i, j, k)
                if not mask[at]:
                    continue
                var edge = (
                    i == 0
                    or j == 0
                    or k == 0
                    or i == map.nx - 1
                    or j == map.ny - 1
                    or k == map.nz - 1
                )
                out[at] = (
                    edge
                    or not mask[at - 1]
                    or not mask[at + 1]
                    or not mask[at - map.nx]
                    or not mask[at + map.nx]
                    or not mask[at - map.nx * map.ny]
                    or not mask[at + map.nx * map.ny]
                )
    return out^


def percentile(values: List[Float64], q: Float64) raises -> Float64:
    """Return a percentile, with linear interpolation between ranks.

    This is the default method of numpy's `percentile`: the value at rank
    `q / 100 * (n - 1)` of the sorted values.

    Args:
        values: The values. At least one.
        q: The percentile, from 0 to 100.

    Returns:
        The percentile.

    Raises:
        Error: If there is no value, or `q` is out of range.
    """
    if len(values) == 0:
        raise Error("A percentile needs at least one value")
    if not (q >= 0 and q <= 100):
        raise Error("A percentile is from 0 to 100")
    var sorted = values.copy()
    sort(sorted)
    var rank = q / 100.0 * Float64(len(sorted) - 1)
    var low = Int(floor(rank))
    if low + 1 >= len(sorted):
        return sorted[len(sorted) - 1]
    var t = rank - Float64(low)
    return sorted[low] + (sorted[low + 1] - sorted[low]) * t


def _directed(
    map: LabelMap, from_surface: List[Bool], to_surface: List[Bool]
) raises -> List[Float64]:
    """Return the distance of each surface voxel to the other surface."""
    var distances = seed_distances(map, to_surface, False)
    var out = List[Float64]()
    for index in range(map.count()):  # pragma: no branch
        if from_surface[index]:
            out.append(distances[index].to(METER))
    return out^


def compare_labels(
    first: LabelMap,
    first_label: LabelId,
    second: LabelMap,
    second_label: LabelId,
) raises -> LabelComparison:
    """Return the overlap and the surface distances of two labels.

    The two maps can be one map, to compare two of its labels.

    Args:
        first: The map of the first label, such as the reference.
        first_label: The first label. Not the background.
        second: The map of the second label, on the same grid.
        second_label: The second label. Not the background.

    Returns:
        The comparison.

    Raises:
        Error: If the grids or the spacings differ, a label is not valid
            or is the background, or a label has no voxels.
    """
    var same = (
        first.nx == second.nx
        and first.ny == second.ny
        and first.nz == second.nz
    )
    if not same:
        raise Error("The two label maps have different grids")
    var spaced = (
        first.spacing_x.to(METER) == second.spacing_x.to(METER)
        and first.spacing_y.to(METER) == second.spacing_y.to(METER)
        and first.spacing_z.to(METER) == second.spacing_z.to(METER)
    )
    if not spaced:
        raise Error("The two label maps have different spacings")
    var a = _mask(first, first_label)
    var b = _mask(second, second_label)
    var out = LabelComparison()
    for index in range(first.count()):  # pragma: no branch
        if a[index]:
            out.first_voxels += 1
        if b[index]:
            out.second_voxels += 1
        if a[index] and b[index]:
            out.shared_voxels += 1
    var shared = Float64(out.shared_voxels)
    var total = Float64(out.first_voxels + out.second_voxels)
    out.dice = 2.0 * shared / total
    out.jaccard = shared / (total - shared)
    var voxel = (
        first.spacing_x.to(METER)
        * first.spacing_y.to(METER)
        * first.spacing_z.to(METER)
    )
    out.first_volume = Volume64(Float64(out.first_voxels) * voxel, CUBIC_METER)
    out.second_volume = Volume64(
        Float64(out.second_voxels) * voxel, CUBIC_METER
    )
    var surface_a = surface_voxels(first, a)
    var surface_b = surface_voxels(first, b)
    var ab = _directed(first, surface_a, surface_b)
    var ba = _directed(first, surface_b, surface_a)
    var both = ab^
    both.extend(ba^)
    var largest = 0.0
    var sum = 0.0
    for d in both:  # pragma: no branch
        largest = max(largest, d)
        sum += d
    out.hausdorff = Length64(largest, METER)
    out.hausdorff_95 = Length64(percentile(both, 95), METER)
    out.mean_surface_distance = Length64(sum / Float64(len(both)), METER)
    return out^


@fieldwise_init
struct LabelOverlap(Copyable, Movable):
    """How one label agrees between two maps."""

    var label: LabelId
    """The label."""
    var first_voxels: Int
    """Its voxels in the first map."""
    var second_voxels: Int
    """Its voxels in the second map."""
    var shared_voxels: Int
    """The voxels that hold it in both."""
    var dice: Float64
    """`2 shared / (first + second)`, from 0 to 1."""
    var jaccard: Float64
    """`shared / (first + second - shared)`, from 0 to 1."""


def label_overlaps(
    first: LabelMap, second: LabelMap
) raises -> List[LabelOverlap]:
    """Return the overlap of every label of two maps on one grid.

    Args:
        first: The first map, such as the reference.
        second: The second map, on the same grid.

    Returns:
        One entry for each label other than the background that either
        map holds, in label order.

    Raises:
        Error: If the two grids differ.
    """
    var same = (
        first.nx == second.nx
        and first.ny == second.ny
        and first.nz == second.nz
    )
    if not same:
        raise Error("The two label maps have different grids")
    var a = List[Int](length=256, fill=0)
    var b = List[Int](length=256, fill=0)
    var both = List[Int](length=256, fill=0)
    # A grid has at least one voxel.
    for index in range(first.count()):  # pragma: no branch
        var x = Int(first.labels[index])
        var y = Int(second.labels[index])
        a[x] += 1
        b[y] += 1
        if x == y:
            both[x] += 1
    var out = List[LabelOverlap]()
    for label in range(1, 256):
        var total = a[label] + b[label]
        if total == 0:
            continue
        var shared = Float64(both[label])
        out.append(
            LabelOverlap(
                LabelId(label),
                a[label],
                b[label],
                both[label],
                2.0 * shared / Float64(total),
                shared / (Float64(total) - shared),
            )
        )
    return out^


def mean_dice(overlaps: List[LabelOverlap]) raises -> Float64:
    """Return the mean Dice coefficient of a table of overlaps.

    Args:
        overlaps: The table, such as `label_overlaps` gives.

    Returns:
        The mean over the labels, each with one weight.

    Raises:
        Error: If the table is empty.
    """
    if len(overlaps) == 0:
        raise Error("A mean Dice needs at least one label")
    var sum = 0.0
    for entry in overlaps:  # pragma: no branch
        sum += entry.dice
    return sum / Float64(len(overlaps))
