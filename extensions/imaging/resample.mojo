# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Resample a volume or a label map on a grid of another spacing.

CT slices are often thicker than their pixels are wide. A voxel mesh, a
thickness map and a morphology ball work best on cubic voxels. A new
grid keeps the first voxel center, the axes and the extent of the old
one: along each axis it has `floor(extent / spacing) + 1` voxels.

`resample_volume` takes the trilinear blend of the old voxels at each
new voxel center. `resample_labels` takes the label of the nearest old
voxel center, because labels cannot blend.
"""

from extensions.imaging.image_volume import ImageVolume, require_spacing
from extensions.imaging.labels import LabelMap
from std.math import floor
from units.si import Length64, METER

# A new count is rounded down, after this much of a voxel more, so that
# an extent that is a whole number of steps keeps its last voxel.
comptime ROUNDING = 1.0e-9


def _count(old: Int, old_step: Length64, new_step: Length64) -> Int:
    """Return the voxels along an axis of the new grid."""
    var extent = Float64(old - 1) * old_step.to(METER)
    return Int(floor(extent / new_step.to(METER) + ROUNDING)) + 1


def _grid(
    volume: ImageVolume,
    spacing_x: Length64,
    spacing_y: Length64,
    spacing_z: Length64,
) raises -> ImageVolume:
    """Return an empty volume on the new grid, placed as the old one."""
    require_spacing(spacing_x)
    require_spacing(spacing_y)
    require_spacing(spacing_z)
    var out = ImageVolume(
        _count(volume.nx, volume.spacing_x, spacing_x),
        _count(volume.ny, volume.spacing_y, spacing_y),
        _count(volume.nz, volume.spacing_z, spacing_z),
        spacing_x,
        spacing_y,
        spacing_z,
    )
    out.origin = volume.origin
    out.axis_x = volume.axis_x
    out.axis_y = volume.axis_y
    out.axis_z = volume.axis_z
    out.window_center = volume.window_center
    out.window_width = volume.window_width
    out.photometric = volume.photometric
    return out^


def resample_volume(
    volume: ImageVolume,
    spacing_x: Length64,
    spacing_y: Length64,
    spacing_z: Length64,
) raises -> ImageVolume:
    """Return a volume resampled on a grid of a new spacing.

    Args:
        volume: The volume.
        spacing_x: The new spacing along `i`.
        spacing_y: The new spacing along `j`.
        spacing_z: The new spacing along `k`.

    Returns:
        A volume with the old origin, axes, window and extent, each
        voxel the trilinear blend of the old voxels at its center.

    Raises:
        Error: If a spacing is not positive and finite, or the new grid
            holds more than 2^28 voxels.
    """
    var out = _grid(volume, spacing_x, spacing_y, spacing_z)
    var fx = out.spacing_x.to(METER) / volume.spacing_x.to(METER)
    var fy = out.spacing_y.to(METER) / volume.spacing_y.to(METER)
    var fz = out.spacing_z.to(METER) / volume.spacing_z.to(METER)
    for k in range(out.nz):  # pragma: no branch
        for j in range(out.ny):  # pragma: no branch
            for i in range(out.nx):  # pragma: no branch
                out.values[out.index(i, j, k)] = volume.trilinear(
                    Float64(i) * fx, Float64(j) * fy, Float64(k) * fz
                )
    return out^


def resample_labels(
    map: LabelMap,
    spacing_x: Length64,
    spacing_y: Length64,
    spacing_z: Length64,
) raises -> LabelMap:
    """Return a label map resampled on a grid of a new spacing.

    Args:
        map: The label map.
        spacing_x: The new spacing along `i`.
        spacing_y: The new spacing along `j`.
        spacing_z: The new spacing along `k`.

    Returns:
        A map on the grid that `resample_volume` gives for the same
        spacing, each voxel the label of the nearest old voxel center.

    Raises:
        Error: If a spacing is not positive and finite, or the new grid
            holds more than 2^28 voxels.
    """
    var shape = ImageVolume(
        map.nx, map.ny, map.nz, map.spacing_x, map.spacing_y, map.spacing_z
    )
    var grid = _grid(shape, spacing_x, spacing_y, spacing_z)
    var out = LabelMap(grid)
    var fx = grid.spacing_x.to(METER) / map.spacing_x.to(METER)
    var fy = grid.spacing_y.to(METER) / map.spacing_y.to(METER)
    var fz = grid.spacing_z.to(METER) / map.spacing_z.to(METER)
    for k in range(grid.nz):  # pragma: no branch
        var kk = min(Int(floor(Float64(k) * fz + 0.5)), map.nz - 1)
        for j in range(grid.ny):  # pragma: no branch
            var jj = min(Int(floor(Float64(j) * fy + 0.5)), map.ny - 1)
            for i in range(grid.nx):  # pragma: no branch
                var ii = min(Int(floor(Float64(i) * fx + 0.5)), map.nx - 1)
                out.labels[out.index(i, j, k)] = map.labels[
                    map.index(ii, jj, kk)
                ]
    return out^
