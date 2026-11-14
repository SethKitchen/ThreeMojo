# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Smooth a volume, or remove its noise, before a threshold.

`gaussian_filter` blurs a volume with a Gaussian of one width in
millimeters. The spacing of each axis turns the width into voxels, so a
volume with thick slices gets a narrower kernel along `k`. The filter is
separable: one pass along each axis. Each kernel stops at three
standard deviations, and its weights sum to one.

`median_filter` gives each voxel the median of the cube of voxels around
it. A median removes single noisy voxels and keeps the edges between
regions, where a Gaussian blurs them.

At the edge of the grid, both filters take the value of the nearest
voxel inside it.
"""

from extensions.imaging.image_volume import ImageVolume
from std.math import ceil, exp, isfinite, max, min
from units.si import Length64, METER

# The most voxels a Gaussian kernel reaches on each side of its center.
comptime MAX_KERNEL_RADIUS = 128
# The most voxels a median reaches on each side of its center.
comptime MAX_MEDIAN_RADIUS = 3


def gaussian_kernel(sigma_voxels: Float64) raises -> List[Float64]:
    """Return the weights of a Gaussian, from `-r` to `r` voxels.

    `r` is three standard deviations, rounded up.

    Args:
        sigma_voxels: The standard deviation, in voxels. Positive.

    Returns:
        `2 r + 1` weights that sum to one.

    Raises:
        Error: If the width is not positive and finite, or `r` is above
            128 voxels.
    """
    if not (sigma_voxels > 0) or not isfinite(sigma_voxels):
        raise Error("A Gaussian width must be positive and finite")
    var radius_float = ceil(3.0 * sigma_voxels)
    if radius_float > Float64(MAX_KERNEL_RADIUS):
        raise Error("A Gaussian kernel reaches at most 128 voxels")
    var radius = Int(radius_float)
    var weights = List[Float64]()
    var total = 0.0
    for t in range(-radius, radius + 1):  # pragma: no branch
        var x = Float64(t) / sigma_voxels
        var w = exp(-0.5 * x * x)
        weights.append(w)
        total += w
    for index in range(len(weights)):  # pragma: no branch
        weights[index] /= total
    return weights^


def _pass(
    volume: ImageVolume,
    values: List[Float32],
    axis: Int,
    weights: List[Float64],
) -> List[Float32]:
    """Convolve along one axis, with the nearest voxel past the edges."""
    var sizes = [volume.nx, volume.ny, volume.nz]
    var strides = [1, volume.nx, volume.nx * volume.ny]
    var size = sizes[axis]
    var stride = strides[axis]
    var radius = len(weights) // 2
    var out = List[Float32](length=len(values), fill=0)
    for index in range(len(values)):  # pragma: no branch
        var at = (index // stride) % size
        var sum = 0.0
        for t in range(len(weights)):  # pragma: no branch
            var c = min(max(at + t - radius, 0), size - 1)
            sum += weights[t] * Float64(values[index + (c - at) * stride])
        out[index] = Float32(sum)
    return out^


def gaussian_filter(volume: ImageVolume, sigma: Length64) raises -> ImageVolume:
    """Return a volume blurred by a Gaussian.

    Args:
        volume: The volume.
        sigma: The standard deviation of the Gaussian, as a length.

    Returns:
        A volume on the same grid, with the same placement and window.

    Raises:
        Error: If `sigma` is not positive and finite, or the kernel of an
            axis reaches more than 128 voxels.
    """
    var spacings = [
        volume.spacing_x.to(METER),
        volume.spacing_y.to(METER),
        volume.spacing_z.to(METER),
    ]
    var width = sigma.to(METER)
    if not (width > 0) or not isfinite(width):
        raise Error("A Gaussian width must be positive and finite")
    var kernels = List[List[Float64]]()
    for axis in range(3):  # pragma: no branch
        kernels.append(gaussian_kernel(width / spacings[axis]))
    var values = volume.values.copy()
    for axis in range(3):  # pragma: no branch
        values = _pass(volume, values, axis, kernels[axis])
    var out = volume.copy()
    out.values = values^
    return out^


def median_filter(volume: ImageVolume, radius: Int) raises -> ImageVolume:
    """Return a volume with each voxel the median of the cube around it.

    The cube reaches `radius` voxels on each side, so it holds
    `(2 radius + 1)^3` voxels.

    Args:
        volume: The volume.
        radius: From 1 to 3 voxels.

    Returns:
        A volume on the same grid, with the same placement and window.

    Raises:
        Error: If `radius` is not from 1 to 3.
    """
    if radius < 1 or radius > MAX_MEDIAN_RADIUS:
        raise Error("A median reaches from 1 to 3 voxels")
    var out = volume.copy()
    var side = 2 * radius + 1
    var window = List[Float32](capacity=side**3)
    for index in range(volume.count()):  # pragma: no branch
        var i = index % volume.nx
        var j = (index // volume.nx) % volume.ny
        var k = index // (volume.nx * volume.ny)
        window.clear()
        for offset in range(side**3):  # pragma: no branch
            var di = offset % side - radius
            var dj = (offset // side) % side - radius
            var dk = offset // (side * side) - radius
            var ii = min(max(i + di, 0), volume.nx - 1)
            var jj = min(max(j + dj, 0), volume.ny - 1)
            var kk = min(max(k + dk, 0), volume.nz - 1)
            window.append(volume.values[volume.index(ii, jj, kk)])
        sort(window)
        out.values[index] = window[len(window) // 2]
    return out^
