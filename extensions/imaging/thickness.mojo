# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The distance to the edge of a label, and its local thickness.

`label_distance` gives each voxel of a label its distance to the
nearest voxel outside the label, center to center, in physical units.
The grid counts as surrounded by voxels outside every label. The
transform is exact: it is the method of Felzenszwalb and Huttenlocher,
with the spacing of each axis in its pass.

`local_thickness` gives each voxel of a label the diameter of the
largest sphere that holds the voxel and fits in the label, after
Hildebrand and Rüegsegger (1997). The sphere at a voxel has the radius
of the distance there. Only the spheres that no neighbor's sphere holds,
the ridge of the distance, can be the largest, so only they are drawn.
Bone research uses this map for the thickness of cortical walls and of
trabeculae.

Both give a volume on the grid of the label map, in millimeters, ready
for `render_slice` and `label_statistics`. `thickness_statistics` gives
the mean and the largest thickness of a label as lengths.
"""

from extensions.imaging.ids import LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.numerics.distance import NO_SEED, distance_transform
from std.math import inf, max, min, sqrt
from units.si import METER, MILLIMETER64, Length64


# A squared distance larger than any grid holds.
def _squared_distances(
    map: LabelMap, seeds: List[Bool], border_is_seed: Bool
) raises -> List[Float64]:
    """Return the squared distance of each voxel to the nearest seed, in
    square meters, on a grid padded by one voxel, or `NO_SEED` without
    one."""
    var px = map.nx + 2
    var py = map.ny + 2
    var pz = map.nz + 2
    var padded = List[Bool](length=px * py * pz, fill=border_is_seed)
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                var at = (i + 1) + px * ((j + 1) + py * (k + 1))
                padded[at] = seeds[map.index(i, j, k)]
    return distance_transform(
        padded,
        px,
        py,
        pz,
        map.spacing_x.to(METER),
        map.spacing_y.to(METER),
        map.spacing_z.to(METER),
    )[0].copy()


def seed_distances(
    map: LabelMap, seeds: List[Bool], border_is_seed: Bool
) raises -> List[Length64]:
    """Return the distance of each voxel to the nearest seed voxel.

    The distance is center to center, with the spacing of each axis, and
    exact. A seed is 0 from itself.

    Args:
        map: The label map whose grid and spacing count.
        seeds: One flag per voxel of the grid, `i` fastest.
        border_is_seed: Whether the voxels just past the grid count as
            seeds, as the outside of a label does.

    Returns:
        One distance per voxel. A voxel with no seed anywhere has an
        infinite distance.

    Raises:
        Error: If `seeds` does not hold one flag per voxel.
    """
    if len(seeds) != map.count():
        raise Error("A seed mask needs one flag per voxel")
    var squared = _squared_distances(map, seeds, border_is_seed)
    var px = map.nx + 2
    var py = map.ny + 2
    var out = List[Length64](capacity=map.count())
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                var s = squared[(i + 1) + px * ((j + 1) + py * (k + 1))]
                var d = sqrt(s) if s < NO_SEED else inf[DType.float64]()
                out.append(Length64(d, METER))
    return out^


def _volume_of(map: LabelMap) raises -> ImageVolume:
    """Return a volume of zeros on the grid of a label map."""
    return ImageVolume(
        map.nx, map.ny, map.nz, map.spacing_x, map.spacing_y, map.spacing_z
    )


def label_distance(map: LabelMap, label: LabelId) raises -> ImageVolume:
    """Return the distance of each voxel of a label to the nearest voxel
    outside it, center to center, in millimeters.

    Args:
        map: The label map.
        label: The label.

    Returns:
        A volume on the grid of the map. A voxel outside the label is 0.

    Raises:
        Error: If the label is not valid or has no voxels.
    """
    require_label(label)
    if map.voxels(label) == 0:
        raise Error("The label has no voxels")
    var mark = UInt8(label.value)
    var outside = List[Bool](capacity=map.count())
    for index in range(map.count()):  # pragma: no branch
        outside.append(map.labels[index] != mark)
    var distances = seed_distances(map, outside, True)
    var out = _volume_of(map)
    for index in range(map.count()):  # pragma: no branch
        # A voxel outside the label is its own nearest one.
        if outside[index]:
            continue
        out.values[index] = Float32(distances[index].to(MILLIMETER64))
    out.fit_window()
    return out^


def local_thickness(map: LabelMap, label: LabelId) raises -> ImageVolume:
    """Return the local thickness of each voxel of a label, in millimeters.

    The thickness of a voxel is the diameter of the largest sphere that
    holds it and fits in the label. A sphere fits when its radius is the
    distance from its center to the nearest voxel outside the label.

    Args:
        map: The label map.
        label: The label.

    Returns:
        A volume on the grid of the map. A voxel outside the label is 0.

    Raises:
        Error: If the label is not valid or has no voxels.
    """
    var distance = label_distance(map, label)
    var sx = map.spacing_x.to(MILLIMETER64)
    var sy = map.spacing_y.to(MILLIMETER64)
    var sz = map.spacing_z.to(MILLIMETER64)
    var mark = UInt8(label.value)
    # The ridge: the voxels whose sphere no neighbor's sphere holds.
    var centers = List[Int]()
    for index in range(map.count()):  # pragma: no branch
        if map.labels[index] != mark:
            continue
        var i = index % map.nx
        var j = (index // map.nx) % map.ny
        var k = index // (map.nx * map.ny)
        var r = Float64(distance.values[index])
        var ridge = True
        for offset in range(27):  # pragma: no branch
            var di = offset % 3 - 1
            var dj = (offset // 3) % 3 - 1
            var dk = offset // 9 - 1
            if not map.contains(i + di, j + dj, k + dk) or offset == 13:
                continue
            var other = Float64(
                distance.values[distance.index(i + di, j + dj, k + dk)]
            )
            var gap = sqrt(
                (Float64(di) * sx) ** 2
                + (Float64(dj) * sy) ** 2
                + (Float64(dk) * sz) ** 2
            )
            # The neighbor's sphere holds this one.
            if other - gap >= r:
                ridge = False
                break
        if ridge:
            centers.append(index)
    var out = _volume_of(map)
    # The deepest voxel is always on the ridge.
    for center in centers:  # pragma: no branch
        var ci = center % map.nx
        var cj = (center // map.nx) % map.ny
        var ck = center // (map.nx * map.ny)
        var r = Float64(distance.values[center])
        var reach_i = Int(r / sx)
        var reach_j = Int(r / sy)
        var reach_k = Int(r / sz)
        var diameter = Float32(2.0 * r)
        for k in range(
            max(ck - reach_k, 0), min(ck + reach_k + 1, map.nz)
        ):  # pragma: no branch
            for j in range(
                max(cj - reach_j, 0), min(cj + reach_j + 1, map.ny)
            ):  # pragma: no branch
                for i in range(
                    max(ci - reach_i, 0), min(ci + reach_i + 1, map.nx)
                ):  # pragma: no branch
                    var at = map.index(i, j, k)
                    if map.labels[at] != mark or out.values[at] >= diameter:
                        continue
                    var d2 = (
                        (Float64(i - ci) * sx) ** 2
                        + (Float64(j - cj) * sy) ** 2
                        + (Float64(k - ck) * sz) ** 2
                    )
                    if d2 <= r * r:
                        out.values[at] = diameter
    out.fit_window()
    return out^


struct ThicknessStatistics(Copyable, Movable):
    """The mean and the largest thickness of a label."""

    var mean: Length64
    """The mean over the voxels of the label."""
    var maximum: Length64
    """The largest thickness of a voxel of the label."""

    def __init__(out self, mean: Length64, maximum: Length64):
        """Hold the statistics.

        Args:
            mean: The mean thickness.
            maximum: The largest thickness.
        """
        self.mean = mean
        self.maximum = maximum


def thickness_statistics(
    thickness: ImageVolume, map: LabelMap, label: LabelId
) raises -> ThicknessStatistics:
    """Return the mean and the largest local thickness of a label.

    Args:
        thickness: The map of `local_thickness`, in millimeters.
        map: The label map, on the same grid.
        label: The label.

    Returns:
        The statistics, as lengths.

    Raises:
        Error: If the grids differ, the label is not valid, or it has no
            voxels.
    """
    require_same_grid(map, thickness)
    require_label(label)
    var mark = UInt8(label.value)
    var total = 0.0
    var count = 0
    var largest = 0.0
    for index in range(map.count()):  # pragma: no branch
        if map.labels[index] == mark:
            var t = Float64(thickness.values[index])
            total += t
            count += 1
            largest = max(largest, t)
    if count == 0:
        raise Error("The label has no voxels")
    return ThicknessStatistics(
        Length64(total / Float64(count), MILLIMETER64),
        Length64(largest, MILLIMETER64),
    )
