# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Texture features of a region of a slice, from its co-occurrence matrix.

Radiomics describes the texture of a region, such as a lesion, by how
often two gray levels sit side by side. `cooccurrence_matrix` counts,
for each pair of pixels of a slice at a fixed offset, the pair of their
gray levels. Both pixels must be in the label. The matrix is symmetric:
each pair counts both ways. It is normed, so its entries `P(i, j)` sum
to one.

The values are first put into `levels` gray levels: level
`floor((value - low) / (high - low) * levels)`, kept from 0 to
`levels - 1`.

`texture_features` gives the measures of Haralick that scikit-image's
`graycoprops` gives:

| Feature | Formula |
|---|---|
| contrast | the sum of `P (i - j)^2` |
| dissimilarity | the sum of `P abs(i - j)` |
| homogeneity | the sum of `P / (1 + (i - j)^2)` |
| ASM | the sum of `P^2`, the angular second moment |
| energy | the square root of ASM |
| correlation | the sum of `P (i - mu_i) (j - mu_j) / (sigma_i sigma_j)`, 1 when a sigma is below 1e-15 |

The offset `(dx, dy)` is in pixels of the slice: `(1, 0)` pairs each
pixel with its neighbor along pixel x, and `(1, 1)` with its diagonal
neighbor.
"""

from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    SliceAxis,
    require_axis,
    require_label,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from extensions.imaging.overlay import slice_size
from std.math import floor, isfinite, sqrt


@fieldwise_init
struct TextureFeatures(Copyable, Movable):
    """The Haralick features of one co-occurrence matrix."""

    var pairs: Int
    """The pixel pairs counted, each once."""
    var contrast: Float64
    """The sum of `P (i - j)^2`."""
    var dissimilarity: Float64
    """The sum of `P abs(i - j)`."""
    var homogeneity: Float64
    """The sum of `P / (1 + (i - j)^2)`."""
    var asm: Float64
    """The angular second moment, the sum of `P^2`."""
    var energy: Float64
    """The square root of the angular second moment."""
    var correlation: Float64
    """The correlation of the two gray levels of a pair."""


def _voxel(axis: SliceAxis, x: Int, y: Int, index: Int) -> Tuple[Int, Int, Int]:
    """Return the voxel of a slice pixel."""
    if axis == K_AXIS:
        return (x, y, index)
    if axis == J_AXIS:
        return (x, index, y)
    return (index, x, y)


def cooccurrence_matrix(
    volume: ImageVolume,
    map: LabelMap,
    label: LabelId,
    axis: SliceAxis,
    index: Int,
    dx: Int,
    dy: Int,
    levels: Int,
    low: Float64,
    high: Float64,
) raises -> Tuple[List[Float64], Int]:
    """Return the normed, symmetric co-occurrence matrix of a region.

    Args:
        volume: The volume.
        map: Its label map.
        label: The region. Not the background.
        axis: The axis that the slice holds constant.
        index: The slice.
        dx: The offset along pixel x.
        dy: The offset along pixel y. Not both zero.
        levels: The gray levels, from 2 to 256.
        low: The value at the bottom of level 0.
        high: The value at the top of the last level. Above `low`.

    Returns:
        The `levels` by `levels` matrix, row by row, and the number of
        pixel pairs.

    Raises:
        Error: If the grids differ, the label is not valid or is the
            background, the axis or slice is out of range, the offset is
            zero, `levels` is out of range, the range is not finite or
            falls, or no pair of the region lies at the offset.
    """
    require_same_grid(map, volume)
    require_label(label)
    if label == BACKGROUND:
        raise Error("A texture needs a label other than the background")
    require_axis(axis)
    var depth = volume.nz
    if axis == J_AXIS:
        depth = volume.ny
    elif axis == I_AXIS:
        depth = volume.nx
    if index < 0 or index >= depth:
        raise Error("The slice index is outside the volume")
    if dx == 0 and dy == 0:
        raise Error("A co-occurrence offset cannot be zero")
    if levels < 2 or levels > 256:
        raise Error("A co-occurrence matrix has from 2 to 256 gray levels")
    if not isfinite(low) or not isfinite(high) or not (high > low):
        raise Error("A gray-level range must be finite and rise")
    var size = slice_size(volume.nx, volume.ny, volume.nz, axis)
    var width = size[0]
    var height = size[1]
    var mark = UInt8(label.value)
    var scale = Float64(levels) / (high - low)
    var gray = List[Int](length=width * height, fill=-1)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var v = _voxel(axis, x, y, index)
            var at = volume.index(v[0], v[1], v[2])
            if map.labels[at] != mark:
                continue
            var level = Int(floor((Float64(volume.values[at]) - low) * scale))
            gray[x + width * y] = max(0, min(levels - 1, level))
    var counts = List[Float64](length=levels * levels, fill=0)
    var pairs = 0
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var a = gray[x + width * y]
            var px = x + dx
            var py = y + dy
            if a < 0 or px < 0 or px >= width or py < 0 or py >= height:
                continue
            var b = gray[px + width * py]
            if b < 0:
                continue
            counts[a * levels + b] += 1
            counts[b * levels + a] += 1
            pairs += 1
    if pairs == 0:
        raise Error("No pair of the region lies at the offset")
    var total = 2.0 * Float64(pairs)
    for k in range(len(counts)):  # pragma: no branch
        counts[k] /= total
    return (counts^, pairs)


def texture_features(
    matrix: List[Float64], pairs: Int
) raises -> TextureFeatures:
    """Return the Haralick features of a normed co-occurrence matrix.

    Args:
        matrix: A square matrix whose entries sum to one, row by row.
        pairs: The pixel pairs it counts.

    Returns:
        The features.

    Raises:
        Error: If the matrix is not square or is empty.
    """
    var levels = Int(sqrt(Float64(len(matrix))) + 0.5)
    if levels == 0 or levels * levels != len(matrix):
        raise Error("A co-occurrence matrix must be square")
    var contrast = 0.0
    var dissimilarity = 0.0
    var homogeneity = 0.0
    var asm = 0.0
    var mean_i = 0.0
    var mean_j = 0.0
    for i in range(levels):  # pragma: no branch
        for j in range(levels):  # pragma: no branch
            var p = matrix[i * levels + j]
            var d = Float64(i - j)
            contrast += p * d * d
            dissimilarity += p * abs(d)
            homogeneity += p / (1.0 + d * d)
            asm += p * p
            mean_i += p * Float64(i)
            mean_j += p * Float64(j)
    var var_i = 0.0
    var var_j = 0.0
    var covariance = 0.0
    for i in range(levels):  # pragma: no branch
        for j in range(levels):  # pragma: no branch
            var p = matrix[i * levels + j]
            var a = Float64(i) - mean_i
            var b = Float64(j) - mean_j
            var_i += p * a * a
            var_j += p * b * b
            covariance += p * a * b
    # As in scikit-image, a deviation below 1e-15 gives a correlation of 1.
    var correlation = 1.0
    if sqrt(var_i) >= 1e-15 and sqrt(var_j) >= 1e-15:
        correlation = covariance / sqrt(var_i * var_j)
    return TextureFeatures(
        pairs,
        contrast,
        dissimilarity,
        homogeneity,
        asm,
        sqrt(asm),
        correlation,
    )
