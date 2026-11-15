# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Vesselness: how much each voxel looks like a bright tube, after Frangi
and others (1998).

The Hessian of a volume, smoothed at a scale sigma, has three eigenvalues
at each voxel. Sort them by magnitude: `|l1| <= |l2| <= |l3|`. Inside a
bright tube, l1 is near 0 along the tube, and l2 and l3 are large and
negative across it. A blob has three large eigenvalues, and a plate one.

- `hessian_eigenvalues(volume, sigma)` gives the three eigenvalues of each
  voxel, sorted by magnitude, in the unit of the values per square
  millimeter. The Hessian is that of scikit-image's `hessian_matrix` with
  Gaussian derivatives: two first derivatives of a Gaussian of
  `sigma / sqrt(2)`, as scipy's `gaussian_filter` gives them, with the
  values reflected past each edge. Each kernel reaches 8 of its sigmas, or
  100 when a sigma is 1 voxel or less.
- `vesselness(volume, sigmas, alpha, beta, gamma)` gives, for bright tubes,

      V = (1 - exp(-Ra^2 / (2 alpha^2))) exp(-Rb^2 / (2 beta^2))
          (1 - exp(-S^2 / (2 gamma^2)))

  with `Ra = l2 / l3`, `Rb = |l1| / sqrt(l2 l3)` and S the norm of the
  eigenvalues, from the eigenvalues of the negated volume, with l2 and l3
  held at 1e-10 or more. It takes the largest V over the scales. Without
  a gamma, gamma is half the largest S at the first scale, as
  scikit-image's `frangi` takes it.

The scales are lengths, so a volume of voxels that are not cubes has its
sigma in voxels along each axis.
"""

from extensions.imaging.image_volume import ImageVolume
from extensions.numerics.dense import DenseMatrix, symmetric_eigen
from std.collections import Optional
from std.math import expm1, isfinite, sqrt
from units.si import MILLIMETER64, Length64
from extensions.numerics.elementary import precise_exp

comptime MAX_SIGMA_VOXELS = 100.0
"""The largest scale, in voxels along an axis."""
comptime _LEAST = 1e-10
comptime _SQRT_HALF = 0.7071067811865476


def _kernel(sigma: Float64, order: Int, radius: Int) -> List[Float64]:
    """Return scipy's Gaussian kernel of an order 0 or 1, from -radius to
    radius."""
    var weights = List[Float64]()
    var total = 0.0
    for t in range(-radius, radius + 1):  # pragma: no branch
        var x = Float64(t)
        var w = precise_exp(-0.5 * x * x / (sigma * sigma))
        weights.append(w)
        total += w
    for at in range(len(weights)):  # pragma: no branch
        weights[at] /= total
        if order == 1:
            weights[at] *= -Float64(at - radius) / (sigma * sigma)
    return weights^


def _reflect(i: Int, n: Int) -> Int:
    """Return the index of a point past an edge, reflected about the edge:
    `d c b a | a b c d | d c b a`."""
    # The modulo of a positive divisor is 0 or more in Mojo, as in Python.
    var m = i % (2 * n)
    if m >= n:
        m = 2 * n - 1 - m
    return m


def _convolve(
    values: List[Float64],
    shape: List[Int],
    axis: Int,
    sigma: Float64,
    order: Int,
    truncate: Float64,
) -> List[Float64]:
    """Convolve the values along one axis of `(nx, ny, nz)` with scipy's
    Gaussian kernel, with the values reflected past each edge."""
    var radius = Int(truncate * sigma + 0.5)
    var kernel = _kernel(sigma, order, radius)
    var n = shape[axis]
    var stride = 1
    for a in range(axis):
        stride *= shape[a]
    # The source index of each offset from each place along the axis.
    var source = List[Int]()
    for i in range(n):  # pragma: no branch
        for t in range(-radius, radius + 1):  # pragma: no branch
            source.append(_reflect(i - t, n))
    var width = 2 * radius + 1
    var out = List[Float64](length=len(values), fill=0.0)
    for start in range(len(values)):  # pragma: no branch
        # Only the first place of each line starts it.
        if (start // stride) % n != 0:
            continue
        for i in range(n):  # pragma: no branch
            # Mirrored pairs, as scipy's `correlate1d` sums a symmetric or
            # an antisymmetric kernel: `k(t) (f[i - t] +- f[i + t])`.
            var row = i * width
            var total = (
                kernel[radius] * values[start + source[row + radius] * stride]
            )
            var sign = 1.0 if order == 0 else -1.0
            for t in range(1, radius + 1):  # pragma: no branch
                var before = values[start + source[row + radius + t] * stride]
                var after = values[start + source[row + radius - t] * stride]
                total += kernel[radius + t] * (before + sign * after)
            out[start + i * stride] = total
    return out^


def _gaussian(
    values: List[Float64],
    shape: List[Int],
    sigmas: List[Float64],
    orders: List[Int],
    truncate: Float64,
) -> List[Float64]:
    """Filter along z, then y, then x, as scipy's `gaussian_filter` does
    along the axes of a `(z, y, x)` array."""
    var out = values.copy()
    for axis in range(2, -1, -1):  # pragma: no branch
        out = _convolve(out, shape, axis, sigmas[axis], orders[axis], truncate)
    return out^


def _eigen(
    a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64
) raises -> Tuple[Float64, Float64, Float64]:
    """Return the eigenvalues of `[[a, d, e], [d, b, f], [e, f, c]]`,
    sorted by magnitude."""
    var m = DenseMatrix(3, 3)
    var entries: List[Float64] = [a, d, e, d, b, f, e, f, c]
    for at in range(9):  # pragma: no branch
        m.data[at] = entries[at]
    var values = symmetric_eigen(m).values.copy()
    var l1 = values[0]
    var l2 = values[1]
    var l3 = values[2]
    # Three compare-and-swaps sort them by magnitude.
    if abs(l2) < abs(l1):
        l1, l2 = l2, l1
    if abs(l3) < abs(l2):
        l2, l3 = l3, l2
    if abs(l2) < abs(l1):
        l1, l2 = l2, l1
    return (l1, l2, l3)


def hessian_eigenvalues(
    volume: ImageVolume, sigma: Length64
) raises -> List[Float64]:
    """Return the eigenvalues of the Hessian of a volume at a scale.

    Args:
        volume: The volume.
        sigma: The scale, positive, at most 100 voxels along each axis.

    Returns:
        Three values for each voxel, in the order of the voxels, sorted by
        magnitude, in the unit of the values per square millimeter.

    Raises:
        Error: If the scale is not positive and finite, or is more than 100
            voxels along an axis.
    """
    var s = sigma.to(MILLIMETER64)
    if not (s > 0) or not isfinite(s):
        raise Error("A Hessian scale must be positive and finite")
    var spacing: List[Float64] = [
        volume.spacing_x.to(MILLIMETER64),
        volume.spacing_y.to(MILLIMETER64),
        volume.spacing_z.to(MILLIMETER64),
    ]
    var shape: List[Int] = [volume.nx, volume.ny, volume.nz]
    var voxels = List[Float64]()
    var above_one = True
    for a in range(3):  # pragma: no branch
        var v = s / spacing[a]
        if v > MAX_SIGMA_VOXELS:
            raise Error("A Hessian scale is at most 100 voxels on each axis")
        above_one = above_one and v > 1.0
        voxels.append(v * _SQRT_HALF)
    var truncate = 8.0 if above_one else 100.0
    var values = List[Float64]()
    for v in volume.values:  # pragma: no branch
        values.append(Float64(v))
    var gradients = List[List[Float64]]()
    for a in range(3):  # pragma: no branch
        var orders = List[Int](length=3, fill=0)
        orders[a] = 1
        gradients.append(_gaussian(values, shape, voxels, orders, truncate))
    # The six parts, in mm^-2: xx, yy, zz, xy, xz, yz. With the values
    # reflected past the edges, the two passes do not commute there. Each
    # cross part takes its gradient along the later axis of x, y and z,
    # as scikit-image takes it along the earlier axis of (z, y, x).
    var pairs: List[Tuple[Int, Int]] = [
        (0, 0),
        (1, 1),
        (2, 2),
        (1, 0),
        (2, 0),
        (2, 1),
    ]
    var parts = List[List[Float64]]()
    for pair in pairs:  # pragma: no branch
        var orders = List[Int](length=3, fill=0)
        orders[pair[1]] = 1
        var part = _gaussian(
            gradients[pair[0]], shape, voxels, orders, truncate
        )
        var scale = 1.0 / (spacing[pair[0]] * spacing[pair[1]])
        for at in range(len(part)):  # pragma: no branch
            part[at] *= scale
        parts.append(part^)
    var out = List[Float64]()
    for at in range(len(values)):  # pragma: no branch
        var found = _eigen(
            parts[0][at],
            parts[1][at],
            parts[2][at],
            parts[3][at],
            parts[4][at],
            parts[5][at],
        )
        out.append(found[0])
        out.append(found[1])
        out.append(found[2])
    return out^


def vesselness(
    volume: ImageVolume,
    sigmas: List[Length64],
    alpha: Float64,
    beta: Float64,
    gamma: Optional[Float64],
) raises -> ImageVolume:
    """Return the Frangi vesselness of each voxel, for bright tubes.

    Args:
        volume: The volume, with bright vessels, such as a CT angiogram.
        sigmas: The scales, one or more, each as for `hessian_eigenvalues`.
            Take scales near the radii of the vessels.
        alpha: The weight of the plate measure Ra, positive, such as 0.5.
        beta: The weight of the blob measure Rb, positive, such as 0.5.
        gamma: The weight of the structure S, positive, in the unit of
            the values per square millimeter. None takes half the largest S
            at the first scale.

    Returns:
        A volume on the grid of the input, with the vesselness from 0 to 1
        and a window from 0 to 1.

    Raises:
        Error: If there is no scale, a scale is out of range, or alpha,
            beta or gamma is not positive and finite.
    """
    if len(sigmas) == 0:
        raise Error("Vesselness needs one scale or more")
    if not (alpha > 0) or not isfinite(alpha):
        raise Error("A vesselness alpha must be positive and finite")
    if not (beta > 0) or not isfinite(beta):
        raise Error("A vesselness beta must be positive and finite")
    var g = 0.0
    if gamma:
        g = gamma.value()
        if not (g > 0) or not isfinite(g):
            raise Error("A vesselness gamma must be positive and finite")
    var n = volume.count()
    var best = List[Float64](length=n, fill=0.0)
    for sigma in sigmas:  # pragma: no branch
        var eigen = hessian_eigenvalues(volume, sigma)
        if not (g > 0):
            # Half the largest norm of the eigenvalues, or 1 for a flat
            # volume.
            var top = 0.0
            for at in range(n):  # pragma: no branch
                var norm = sqrt(
                    eigen[3 * at] * eigen[3 * at]
                    + eigen[3 * at + 1] * eigen[3 * at + 1]
                    + eigen[3 * at + 2] * eigen[3 * at + 2]
                )
                top = max(top, norm)
            g = top / 2.0 if top > 0 else 1.0
        for at in range(n):  # pragma: no branch
            # The eigenvalues of the negated volume, for bright tubes.
            var l1 = -eigen[3 * at]
            var l2 = max(-eigen[3 * at + 1], _LEAST)
            var l3 = max(-eigen[3 * at + 2], _LEAST)
            var s2 = (
                l1 * l1
                + eigen[3 * at + 1] * eigen[3 * at + 1]
                + eigen[3 * at + 2] * eigen[3 * at + 2]
            )
            var ra = l2 / l3
            var rb2 = l1 * l1 / (l2 * l3)
            var v = (
                (1.0 - precise_exp(-ra * ra / (2.0 * alpha * alpha)))
                * precise_exp(-rb2 / (2.0 * beta * beta))
                * (1.0 - precise_exp(-s2 / (2.0 * g * g)))
            )
            best[at] = max(best[at], v)
    var out = volume.copy()
    for at in range(n):  # pragma: no branch
        out.values[at] = Float32(best[at])
    out.window_center = 0.5
    out.window_width = 1.0
    return out^
