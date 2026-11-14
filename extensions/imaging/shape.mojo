# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shape of a label: its principal axes, and its area slice by slice.

`label_shape` gives the centroid of a label, its principal axes and the
semi-axes of its equivalent ellipsoid. That is the solid ellipsoid with
the same second moments. Each voxel counts as a small box, not as a
point at its center, so a box label has the exact moments of a box. A
solid ellipsoid with semi-axes `a`, `b` and `c` has the variances
`a^2 / 5`, `b^2 / 5` and `c^2 / 5` along its axes, so each semi-axis is
`sqrt(5 lambda)`, where `lambda` is an eigenvalue of the covariance.

The axes show how an organ lies, and their lengths show whether it is
round, flat or long. The axes are in patient space, longest first. The
sign of an axis is arbitrary.

`slice_areas` gives the area of a label in each slice along a grid axis,
such as the cross-section of a vessel from slice to slice.
"""

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
from extensions.numerics.dense import DenseMatrix, symmetric_eigen
from extensions.sdf.vector import V3, v3
from std.math import max, sqrt
from units.si import (
    Area64,
    CUBIC_METER,
    Length64,
    METER,
    SQUARE_METER,
    Volume64,
)


struct LabelShape(Copyable, Movable):
    """The size, place and principal axes of one label."""

    var voxels: Int
    """The number of voxels."""
    var volume: Volume64
    """The volume of the voxels."""
    var center: V3
    """The centroid in patient space, in meters."""
    var axes: List[V3]
    """The three principal directions in patient space, longest first."""
    var semi_axes: List[Float64]
    """The semi-axes of the equivalent ellipsoid along `axes`, in meters."""

    def __init__(out self):
        """Create an empty shape."""
        self.voxels = 0
        self.volume = Volume64(0, CUBIC_METER)
        self.center = v3(0, 0, 0)
        self.axes = List[V3]()
        self.semi_axes = List[Float64]()

    def semi_axis(self, k: Int) raises -> Length64:
        """Return one semi-axis of the equivalent ellipsoid.

        Args:
            k: 0 for the longest, 1 for the middle and 2 for the shortest.

        Returns:
            The semi-axis.

        Raises:
            Error: If `k` is not from 0 to 2.
        """
        if k < 0 or k >= len(self.semi_axes):
            raise Error("A semi-axis is 0, 1 or 2")
        return Length64(self.semi_axes[k], METER)


def label_shape(
    map: LabelMap, volume: ImageVolume, label: LabelId
) raises -> LabelShape:
    """Return the centroid, principal axes and equivalent ellipsoid of a label.

    Args:
        map: The label map.
        volume: The volume of the map. Its spacing and placement apply.
        label: The label. Not the background.

    Returns:
        The shape.

    Raises:
        Error: If the grids differ, the label is not valid or is the
            background, or the label has no voxels.
    """
    require_same_grid(map, volume)
    require_label(label)
    if label == BACKGROUND:
        raise Error("A shape needs a label other than the background")
    var mark = UInt8(label.value)
    var sx = volume.spacing_x.to(METER)
    var sy = volume.spacing_y.to(METER)
    var sz = volume.spacing_z.to(METER)
    # Sums of the grid-frame centers and their products, in meters.
    var count = 0
    var s = List[Float64](length=3, fill=0)
    var ss = List[Float64](length=9, fill=0)
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                if map.labels[map.index(i, j, k)] != mark:
                    continue
                count += 1
                var p: List[Float64] = [
                    Float64(i) * sx,
                    Float64(j) * sy,
                    Float64(k) * sz,
                ]
                for a in range(3):  # pragma: no branch
                    s[a] += p[a]
                    for b in range(3):  # pragma: no branch
                        ss[3 * a + b] += p[a] * p[b]
    if count == 0:
        raise Error("The label has no voxels")
    var n = Float64(count)
    var mean: List[Float64] = [s[0] / n, s[1] / n, s[2] / n]
    # Each voxel is a box: it adds s^2 / 12 along each of its sides.
    var own: List[Float64] = [sx * sx / 12, sy * sy / 12, sz * sz / 12]
    var covariance = DenseMatrix(3, 3)
    for a in range(3):  # pragma: no branch
        for b in range(3):  # pragma: no branch
            var value = ss[3 * a + b] / n - mean[a] * mean[b]
            if a == b:
                value += own[a]
            covariance.set(a, b, value)
    var pairs = symmetric_eigen(covariance)
    var out = LabelShape()
    out.voxels = count
    out.volume = Volume64(n * sx * sy * sz, CUBIC_METER)
    out.center = volume.patient_point(mean[0] / sx, mean[1] / sy, mean[2] / sz)
    # The eigenvalues come in ascending order: take them from the last.
    for k in range(2, -1, -1):  # pragma: no branch
        var along = (
            volume.axis_x * pairs.vectors.get(0, k)
            + volume.axis_y * pairs.vectors.get(1, k)
            + volume.axis_z * pairs.vectors.get(2, k)
        )
        out.axes.append(along)
        out.semi_axes.append(sqrt(5.0 * max(pairs.values[k], 0.0)))
    return out^


def slice_areas(
    map: LabelMap, label: LabelId, axis: SliceAxis
) raises -> List[Area64]:
    """Return the area of a label in each slice along a grid axis.

    Args:
        map: The label map.
        label: The label. Not the background.
        axis: `I_AXIS`, `J_AXIS` or `K_AXIS`: the axis that the slices
            cross.

    Returns:
        One area per slice, in grid order. A slice without the label has
        zero.

    Raises:
        Error: If the label is not valid or is the background, or the axis
            is not valid.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("Slice areas need a label other than the background")
    require_axis(axis)
    var mark = UInt8(label.value)
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var sz = map.spacing_z.to(METER)
    var slices = map.nz
    var pixel = sx * sy
    if axis == I_AXIS:
        slices = map.nx
        pixel = sy * sz
    elif axis == J_AXIS:
        slices = map.ny
        pixel = sx * sz
    var counts = List[Int](length=slices, fill=0)
    for k in range(map.nz):  # pragma: no branch
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                if map.labels[map.index(i, j, k)] != mark:
                    continue
                var at = k
                if axis == I_AXIS:
                    at = i
                elif axis == J_AXIS:
                    at = j
                counts[at] += 1
    var out = List[Area64]()
    for c in counts:  # pragma: no branch
        out.append(Area64(Float64(c) * pixel, SQUARE_METER))
    return out^
