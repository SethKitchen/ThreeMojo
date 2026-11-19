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

`resample_onto` and `resample_labels_onto` instead take the grid of
another volume, in patient space: its size, spacing, origin and axes.
Use them to bring a PET volume onto the grid of a CT, so the two can be
drawn together. A voxel of the new grid whose center falls outside the
box of the old voxel centers gets the `outside` value, or the
background.
"""

from extensions.imaging.image_volume import ImageVolume, require_spacing
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.imaging.reformat import sample_point
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


def resample_onto(
    volume: ImageVolume, target: ImageVolume, outside: Float32
) raises -> ImageVolume:
    """Return a volume resampled onto the grid of another volume.

    Each voxel of the result takes the trilinear value of `volume` at the
    patient position of the same voxel of `target`.

    Args:
        volume: The volume to resample, such as a PET volume.
        target: The volume whose size, spacing, origin and axes the result
            takes, such as a CT volume. Its values do not count.
        outside: The value of a voxel whose center is outside the box of
            the voxel centers of `volume`.

    Returns:
        The resampled volume, with the window of `volume`.

    Raises:
        Error: If the target's grid cannot be made.
    """
    var out = ImageVolume(
        target.nx,
        target.ny,
        target.nz,
        target.spacing_x,
        target.spacing_y,
        target.spacing_z,
    )
    out.origin = target.origin
    out.axis_x = target.axis_x
    out.axis_y = target.axis_y
    out.axis_z = target.axis_z
    out.window_center = volume.window_center
    out.window_width = volume.window_width
    for k in range(out.nz):  # pragma: no branch
        for j in range(out.ny):  # pragma: no branch
            for i in range(out.nx):  # pragma: no branch
                var p = out.patient_point(Float64(i), Float64(j), Float64(k))
                out.values[out.index(i, j, k)] = sample_point(
                    volume, p, outside
                )
    return out^


def resample_labels_onto(
    map: LabelMap, placed: ImageVolume, target: ImageVolume
) raises -> LabelMap:
    """Return a label map resampled onto the grid of another volume.

    Each voxel of the result takes the label of the voxel of `map` whose
    center is nearest its patient position, rounded half up along each
    axis.

    Args:
        map: The label map.
        placed: The volume of the map, which places it in patient space.
        target: The volume whose grid the result takes.

    Returns:
        A label map on the grid of `target`. A voxel whose nearest center
        is outside the grid of `map` is background.

    Raises:
        Error: If `map` and `placed` differ in grid or spacing.
    """
    require_same_grid(map, placed)
    var out = LabelMap(target)
    for k in range(target.nz):  # pragma: no branch
        for j in range(target.ny):  # pragma: no branch
            for i in range(target.nx):  # pragma: no branch
                var p = target.patient_point(Float64(i), Float64(j), Float64(k))
                var q = placed.voxel_point(p)
                var x = Int(floor(q.x + 0.5))
                var y = Int(floor(q.y + 0.5))
                var z = Int(floor(q.z + 0.5))
                if map.contains(x, y, z):
                    out.labels[out.index(i, j, k)] = map.labels[
                        map.index(x, y, z)
                    ]
    return out^
