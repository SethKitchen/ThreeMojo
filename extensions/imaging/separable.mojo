# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Separable Gaussian filters of a volume, one axis at a time.

- `GaussianKernel.smoothing(sigma, radius)` gives the weights of a
  Gaussian from `-radius` to `radius` voxels, with a sum of 1.
  `GaussianKernel.derivative(sigma, radius)` gives those of its first
  derivative, `-t / sigma^2` times the Gaussian weights. These are the
  kernels of scipy's `_gaussian_kernel1d`.
- `convolve_axis(values, shape, axis, kernel, edge)` convolves the values
  of a volume along one axis. An `EdgeMode` says which values it reads
  past each edge.

Each output sums mirrored pairs, `k(t) (f[i - t] +- f[i + t])`, as
scipy's `correlate1d` sums a symmetric or an antisymmetric kernel.
"""

from extensions.imaging.ids import EDGE_NEAREST, EdgeMode, require_edge_mode
from extensions.numerics.elementary import precise_exp
from std.math import isfinite


struct GaussianKernel(Copyable, Movable):
    """The weights of a Gaussian or of its first derivative."""

    var weights: List[Float64]
    """The weight of each offset from `-radius` to `radius`."""
    var radius: Int
    """The most voxels the kernel reaches on each side of its center."""
    var odd: Bool
    """True for the derivative, whose weights change sign with the
    offset."""

    def __init__(out self, sigma: Float64, radius: Int, odd: Bool) raises:
        """Create the weights of a Gaussian, or of its first derivative.

        Args:
            sigma: The standard deviation, in voxels. Positive and finite.
            radius: The most voxels the kernel reaches on each side, 0 or
                more.
            odd: True for the first derivative.

        Raises:
            Error: If `sigma` is not positive and finite, or the radius is
                negative.
        """
        if not (sigma > 0) or not isfinite(sigma):
            raise Error("A Gaussian width must be positive and finite")
        if radius < 0:
            raise Error("A Gaussian kernel radius must be 0 or more")
        self.radius = radius
        self.odd = odd
        self.weights = List[Float64]()
        var total = 0.0
        var variance = sigma * sigma
        for t in range(-radius, radius + 1):  # pragma: no branch
            var x = Float64(t)
            var w = precise_exp(-0.5 * x * x / variance)
            self.weights.append(w)
            total += w
        for at in range(len(self.weights)):  # pragma: no branch
            self.weights[at] /= total
            if odd:
                self.weights[at] *= -Float64(at - radius) / variance

    @staticmethod
    def smoothing(sigma: Float64, radius: Int) raises -> GaussianKernel:
        """Return the weights of a Gaussian.

        Args:
            sigma: The standard deviation, in voxels. Positive and finite.
            radius: The most voxels the kernel reaches on each side.

        Returns:
            `2 radius + 1` weights that sum to 1.

        Raises:
            Error: If `sigma` is not positive and finite, or the radius is
                negative.
        """
        return GaussianKernel(sigma, radius, False)

    @staticmethod
    def derivative(sigma: Float64, radius: Int) raises -> GaussianKernel:
        """Return the weights of the first derivative of a Gaussian.

        Args:
            sigma: The standard deviation, in voxels. Positive and finite.
            radius: The most voxels the kernel reaches on each side.

        Returns:
            `2 radius + 1` weights, `-t / sigma^2` times those of the
            Gaussian.

        Raises:
            Error: If `sigma` is not positive and finite, or the radius is
                negative.
        """
        return GaussianKernel(sigma, radius, True)


def _edge_index(i: Int, n: Int, edge: EdgeMode) -> Int:
    """Return the index that the place `i` of a line of `n` reads."""
    if edge == EDGE_NEAREST:
        return min(max(i, 0), n - 1)
    # The modulo of a positive divisor is 0 or more in Mojo, as in Python.
    var m = i % (2 * n)
    if m >= n:
        m = 2 * n - 1 - m
    return m


def convolve_axis(
    values: List[Float64],
    shape: List[Int],
    axis: Int,
    kernel: GaussianKernel,
    edge: EdgeMode,
) raises -> List[Float64]:
    """Convolve the values of a volume along one axis.

    Args:
        values: The values of an `(nx, ny, nz)` volume, x fastest.
        shape: The sizes `nx`, `ny` and `nz`, each 1 or more.
        axis: The axis, 0 for x, 1 for y and 2 for z.
        kernel: The kernel.
        edge: Which values it reads past each edge.

    Returns:
        `sum_t k(t) f[i - t]` at each place, on the same grid.

    Raises:
        Error: If the edge mode or the axis is not valid, or the sizes do
            not hold the values.
    """
    require_edge_mode(edge)
    if axis < 0 or axis > 2:
        raise Error("A convolution axis must be 0, 1 or 2")
    if (
        len(shape) != 3
        or shape[0] < 1
        or shape[1] < 1
        or shape[2] < 1
        or shape[0] * shape[1] * shape[2] != len(values)
    ):
        raise Error("A convolution needs three sizes that hold the values")
    var radius = kernel.radius
    var n = shape[axis]
    var stride = 1
    for a in range(axis):
        stride *= shape[a]
    # The source index of each offset from each place along the axis.
    var source = List[Int]()
    for i in range(n):  # pragma: no branch
        for t in range(-radius, radius + 1):  # pragma: no branch
            source.append(_edge_index(i - t, n, edge))
    var width = 2 * radius + 1
    var sign = -1.0 if kernel.odd else 1.0
    var out = List[Float64](length=len(values), fill=0.0)
    for start in range(len(values)):  # pragma: no branch
        # Only the first place of each line starts it.
        if (start // stride) % n != 0:
            continue
        for i in range(n):  # pragma: no branch
            var row = i * width
            var total = (
                kernel.weights[radius]
                * values[start + source[row + radius] * stride]
            )
            for t in range(1, radius + 1):
                var before = values[start + source[row + radius + t] * stride]
                var after = values[start + source[row + radius - t] * stride]
                total += kernel.weights[radius + t] * (before + sign * after)
            out[start + i * stride] = total
    return out^
