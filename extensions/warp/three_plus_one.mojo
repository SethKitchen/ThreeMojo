# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The 3+1 split of a metric into a lapse, a shift and a spatial metric.

The line element is

    ds² = -α² c² dt² + γ_ij (dxⁱ + βⁱ c dt)(dxʲ + βʲ c dt)

with the lapse α, the shift βⁱ and the spatial metric γ_ij. So
g_00 = -α² + β_i βⁱ, g_0i = β_i and g_ij = γ_ij.

`ThreePlusOne.metric` is WarpFactory's `threePlusOneBuilder`, and
`decompose` is its `threePlusOneDecomposer`. The shift is stored
covariant, β_i, as WarpFactory stores it.
"""

from std.math import isfinite, sqrt

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import COORDINATE_FRAME, COVARIANT
from extensions.warp.tensor import Metric, TensorField

comptime Matrix3 = SIMD[DType.float64, 16]
"""A 3 by 3 matrix in row-major order, in the first 9 lanes."""


def inverse3(a: Matrix3) raises -> Matrix3:
    """Return the inverse of a 3 by 3 matrix, by cofactors.

    This is WarpFactory's `c3Inv`.

    Args:
        a: The matrix, in the first 9 lanes, row-major.

    Returns:
        The inverse, in the same layout.

    Raises:
        Error: If the determinant is zero or not finite.
    """
    var det = (
        a[0] * (a[4] * a[8] - a[5] * a[7])
        - a[1] * (a[3] * a[8] - a[5] * a[6])
        + a[2] * (a[3] * a[7] - a[4] * a[6])
    )
    if det == 0.0 or not isfinite(det):
        raise Error("A spatial metric is singular at a grid point")
    var out = Matrix3(0)
    out[0] = a[4] * a[8] - a[5] * a[7]
    out[1] = a[2] * a[7] - a[1] * a[8]
    out[2] = a[1] * a[5] - a[2] * a[4]
    out[3] = a[5] * a[6] - a[3] * a[8]
    out[4] = a[0] * a[8] - a[2] * a[6]
    out[5] = a[2] * a[3] - a[0] * a[5]
    out[6] = a[3] * a[7] - a[4] * a[6]
    out[7] = a[1] * a[6] - a[0] * a[7]
    out[8] = a[0] * a[4] - a[1] * a[3]
    return out / det


struct ThreePlusOne(Copyable, Movable):
    """A lapse, a covariant shift and a covariant spatial metric on a grid."""

    var grid: SpacetimeGrid
    """The grid."""
    var lapse: List[Float64]
    """α at each point."""
    var shift: List[Float64]
    """β_i: component i at point p is at i times the point count, plus p.
    """
    var spatial: List[Float64]
    """γ_ij: component (i, j) at point p is at 3 i + j times the point
    count, plus p."""

    def __init__(out self, grid: SpacetimeGrid):
        """Create the split of flat space: α = 1, β = 0 and γ = δ.

        This is WarpFactory's `setMinkowskiThreePlusOne`.

        Args:
            grid: The grid.
        """
        var n = grid.points()
        self.grid = grid
        self.lapse = List[Float64](length=n, fill=1.0)
        self.shift = List[Float64](length=3 * n, fill=0.0)
        self.spatial = List[Float64](length=9 * n, fill=0.0)
        for i in range(3):
            for point in range(n):  # pragma: no branch
                self.spatial[(4 * i) * n + point] = 1.0

    def shift_at(self, i: Int, point: Int) -> Float64:
        """Return β_i at one point.

        Args:
            i: The space index, 0 for x to 2 for z.
            point: The flat index of the point.

        Returns:
            The covariant shift component.
        """
        return self.shift[i * self.grid.points() + point]

    def set_shift(mut self, i: Int, point: Int, value: Float64):
        """Set β_i at one point.

        Args:
            i: The space index, 0 for x to 2 for z.
            point: The flat index of the point.
            value: The covariant shift component.
        """
        self.shift[i * self.grid.points() + point] = value

    def spatial_at(self, i: Int, j: Int, point: Int) -> Float64:
        """Return γ_ij at one point.

        Args:
            i: The first space index.
            j: The second space index.
            point: The flat index of the point.

        Returns:
            The spatial metric component.
        """
        return self.spatial[(3 * i + j) * self.grid.points() + point]

    def set_spatial(mut self, i: Int, j: Int, point: Int, value: Float64):
        """Set γ_ij and γ_ji at one point.

        Args:
            i: The first space index.
            j: The second space index.
            point: The flat index of the point.
            value: The spatial metric component.
        """
        var n = self.grid.points()
        self.spatial[(3 * i + j) * n + point] = value
        self.spatial[(3 * j + i) * n + point] = value

    def spatial_matrix(self, point: Int) -> Matrix3:
        """Return γ_ij at one point.

        Args:
            point: The flat index of the point.

        Returns:
            The matrix, in the first 9 lanes.
        """
        var out = Matrix3(0)
        var n = self.grid.points()
        for k in range(9):
            out[k] = self.spatial[k * n + point]
        return out

    def metric(self, name: String) raises -> Metric:
        """Return the metric that this split describes.

        This is WarpFactory's `threePlusOneBuilder`.

        Args:
            name: The name of the metric.

        Returns:
            The covariant metric.

        Raises:
            Error: If γ is singular at a point, or a component is not
                finite or not symmetric.
        """
        var n = self.grid.points()
        var out = TensorField(self.grid, COVARIANT, COORDINATE_FRAME)
        for point in range(n):  # pragma: no branch
            var gamma_up = inverse3(self.spatial_matrix(point))
            var g00 = -self.lapse[point] * self.lapse[point]
            for i in range(3):
                var beta_up = 0.0
                for j in range(3):
                    beta_up += gamma_up[3 * i + j] * self.shift_at(j, point)
                g00 += beta_up * self.shift_at(i, point)
            out.set(0, 0, point, g00)
            for i in range(3):
                out.set_symmetric(0, i + 1, point, self.shift_at(i, point))
                for j in range(3):
                    out.set(i + 1, j + 1, point, self.spatial_at(i, j, point))
        return Metric(out^, name)


struct Decomposition(Copyable, Movable):
    """The 3+1 split of a metric, with the raised shift and spatial metric."""

    var parts: ThreePlusOne
    """α, β_i and γ_ij."""
    var shift_up: List[Float64]
    """βⁱ, in the layout of `ThreePlusOne.shift`."""
    var spatial_up: List[Float64]
    """γⁱʲ, in the layout of `ThreePlusOne.spatial`."""

    def __init__(
        out self,
        var parts: ThreePlusOne,
        var shift_up: List[Float64],
        var spatial_up: List[Float64],
    ):
        """Hold the parts of a split.

        Args:
            parts: α, β_i and γ_ij.
            shift_up: βⁱ.
            spatial_up: γⁱʲ.
        """
        self.parts = parts^
        self.shift_up = shift_up^
        self.spatial_up = spatial_up^


def decompose(metric: Metric) raises -> Decomposition:
    """Return the lapse, the shift and the spatial metric of a metric.

    This is WarpFactory's `threePlusOneDecomposer`.

    Args:
        metric: The metric.

    Returns:
        The split.

    Raises:
        Error: If γ is singular at a point, or if β_i βⁱ - g_00 is not
            positive at a point, where the lapse is not real.
    """
    var grid = metric.grid()
    var n = grid.points()
    var parts = ThreePlusOne(grid)
    var shift_up = List[Float64](length=3 * n, fill=0.0)
    var spatial_up = List[Float64](length=9 * n, fill=0.0)
    for point in range(n):  # pragma: no branch
        var g = metric.at(point)
        for i in range(3):
            parts.set_shift(i, point, g[i + 1])
            for j in range(3):
                parts.spatial[(3 * i + j) * n + point] = g[4 * (i + 1) + j + 1]
        var gamma_up = inverse3(parts.spatial_matrix(point))
        var square = -g[0]
        for i in range(3):
            var beta_up = 0.0
            for j in range(3):
                spatial_up[(3 * i + j) * n + point] = gamma_up[3 * i + j]
                beta_up += gamma_up[3 * i + j] * g[j + 1]
            shift_up[i * n + point] = beta_up
            square += beta_up * g[i + 1]
        if not (square > 0.0 and isfinite(square)):
            raise Error("A metric has no real lapse at a grid point")
        parts.lapse[point] = sqrt(square)
    return Decomposition(parts^, shift_up^, spatial_up^)
