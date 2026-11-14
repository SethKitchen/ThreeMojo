# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Crop a volume and its label map to a box of voxels.

An analysis often needs only the region around one structure. A crop
keeps that region and drops the rest, so every later step runs on fewer
voxels. A `VoxelBox` holds the first and the last voxel of the region
along each axis, both kept.

`crop_volume` and `crop_labels` copy the voxels of a box. The cropped
volume keeps its place in patient space: its origin is the center of the
box's first voxel, with the same axes and spacing, so a point has the
same patient position before and after. It keeps the window and the
photometric interpretation. `label_box` gives the box of one label, with
a margin of voxels on each side, cut at the grid's edge.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from std.math import max, min


@fieldwise_init
struct VoxelBox(Copyable, Movable):
    """The first and the last voxel of a region along each axis."""

    var low_i: Int
    """The first column."""
    var low_j: Int
    """The first row."""
    var low_k: Int
    """The first slice."""
    var high_i: Int
    """The last column, kept."""
    var high_j: Int
    """The last row, kept."""
    var high_k: Int
    """The last slice, kept."""


def _require_box(box: VoxelBox, nx: Int, ny: Int, nz: Int) raises:
    """Refuse a box that is empty or that leaves the grid."""
    var inside = (
        box.low_i >= 0
        and box.low_j >= 0
        and box.low_k >= 0
        and box.high_i < nx
        and box.high_j < ny
        and box.high_k < nz
    )
    if not inside:
        raise Error("A crop box must lie inside the grid")
    if (
        box.low_i > box.high_i
        or box.low_j > box.high_j
        or box.low_k > box.high_k
    ):
        raise Error("A crop box must hold at least one voxel")


def crop_volume(volume: ImageVolume, box: VoxelBox) raises -> ImageVolume:
    """Return the voxels of a box as a volume, in the same place.

    Args:
        volume: The volume.
        box: The box. Inside the grid, with at least one voxel.

    Returns:
        The cropped volume.

    Raises:
        Error: If the box leaves the grid or holds no voxel.
    """
    _require_box(box, volume.nx, volume.ny, volume.nz)
    var nx = box.high_i - box.low_i + 1
    var ny = box.high_j - box.low_j + 1
    var nz = box.high_k - box.low_k + 1
    var out = ImageVolume(
        nx, ny, nz, volume.spacing_x, volume.spacing_y, volume.spacing_z
    )
    out.origin = volume.patient_point(
        Float64(box.low_i), Float64(box.low_j), Float64(box.low_k)
    )
    out.axis_x = volume.axis_x
    out.axis_y = volume.axis_y
    out.axis_z = volume.axis_z
    out.window_center = volume.window_center
    out.window_width = volume.window_width
    out.photometric = volume.photometric
    for k in range(nz):  # pragma: no branch
        for j in range(ny):  # pragma: no branch
            for i in range(nx):  # pragma: no branch
                out.values[out.index(i, j, k)] = volume.values[
                    volume.index(box.low_i + i, box.low_j + j, box.low_k + k)
                ]
    return out^


def crop_labels(map: LabelMap, box: VoxelBox) raises -> LabelMap:
    """Return the labels of a box as a label map.

    Args:
        map: The label map.
        box: The box. Inside the grid, with at least one voxel.

    Returns:
        The cropped map, on the grid of `crop_volume` of the same box.

    Raises:
        Error: If the box leaves the grid or holds no voxel.
    """
    _require_box(box, map.nx, map.ny, map.nz)
    var shape = ImageVolume(
        box.high_i - box.low_i + 1,
        box.high_j - box.low_j + 1,
        box.high_k - box.low_k + 1,
        map.spacing_x,
        map.spacing_y,
        map.spacing_z,
    )
    var out = LabelMap(shape)
    for k in range(out.nz):  # pragma: no branch
        for j in range(out.ny):  # pragma: no branch
            for i in range(out.nx):  # pragma: no branch
                out.labels[out.index(i, j, k)] = map.labels[
                    map.index(box.low_i + i, box.low_j + j, box.low_k + k)
                ]
    return out^


def label_box(map: LabelMap, label: LabelId, margin: Int) raises -> VoxelBox:
    """Return the box of a label, grown by a margin and cut at the grid.

    Args:
        map: The label map.
        label: The label. Not the background.
        margin: The voxels to add on each side. Zero or more.

    Returns:
        The box.

    Raises:
        Error: If the label is not valid, is the background, or has no
            voxels, or the margin is negative.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A label box needs a label other than the background")
    if margin < 0:
        raise Error("A crop margin must be zero or more")
    var mark = UInt8(label.value)
    var box = VoxelBox(map.nx, map.ny, map.nz, -1, -1, -1)
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                if map.labels[map.index(i, j, k)] != mark:
                    continue
                box.low_i = min(box.low_i, i)
                box.low_j = min(box.low_j, j)
                box.low_k = min(box.low_k, k)
                box.high_i = max(box.high_i, i)
                box.high_j = max(box.high_j, j)
                box.high_k = max(box.high_k, k)
    if box.high_i < 0:
        raise Error("The label has no voxels")
    return VoxelBox(
        max(0, box.low_i - margin),
        max(0, box.low_j - margin),
        max(0, box.low_k - margin),
        min(map.nx - 1, box.high_i + margin),
        min(map.ny - 1, box.high_j + margin),
        min(map.nz - 1, box.high_k + margin),
    )
