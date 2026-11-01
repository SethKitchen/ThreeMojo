# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stress-energy tensor that a metric needs, by the Einstein equations.

`stress_energy` is WarpFactory's `getEnergyTensor`. It takes finite
differences of the metric, and from them gets the Ricci tensor, the Ricci
scalar, the Einstein tensor G_ab and then

    T^ab = c⁴ / (8 π G) g^ac G_cd g^db

in joules per cubic meter. `curvature` gives the steps before the last.

The Ricci tensor is the coordinate form in terms of the metric and its
first and second derivatives, from the introduction of the Wikipedia
article "Ricci curvature", as WarpFactory uses it. Each point is
computed alone, so the derivatives of the metric are not stored.

## Differences from WarpFactory

- The second-order solver uses the same G and c as the fourth-order one.
  WarpFactory's `einE2` uses G = 6.674e-11 and c = 2.99792e8, so its
  second-order energy densities are larger by about 2 parts in 10⁵.
- No GPU path. WarpFactory moves the arrays to a GPU with MATLAB's
  Parallel Computing Toolbox.
"""

from extensions.warp.derivatives import Stencil
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    DifferenceOrder,
    FOURTH_ORDER,
)
from extensions.warp.quantities import EnergyDensity64, einstein_coupling
from extensions.warp.tensor import (
    Matrix4,
    Metric,
    TensorField,
    inverse4,
    multiply4,
)
from units.si import InverseArea64


struct Curvature(Copyable, Movable):
    """The Ricci tensor, the Ricci scalar and the Einstein tensor."""

    var ricci: TensorField
    """R_ab, covariant, per square meter."""
    var scalar: List[Float64]
    """R = g^ab R_ab at each point, per square meter."""
    var einstein: TensorField
    """G_ab = R_ab - g_ab R / 2, covariant, per square meter."""

    def __init__(
        out self,
        var ricci: TensorField,
        var scalar: List[Float64],
        var einstein: TensorField,
    ):
        """Hold the three curvatures.

        Args:
            ricci: R_ab.
            scalar: R.
            einstein: G_ab.
        """
        self.ricci = ricci^
        self.scalar = scalar^
        self.einstein = einstein^

    def scalar_at(self, point: Int) -> InverseArea64:
        """Return the Ricci scalar at one point.

        Args:
            point: The flat index of the point.

        Returns:
            R.
        """
        return InverseArea64(self.scalar[point])


struct StressEnergy(Copyable, Movable):
    """A stress-energy tensor field, with the metric it came from."""

    var tensor: TensorField
    """The components, in joules per cubic meter."""
    var name: String
    """The name of the metric."""
    var order: DifferenceOrder
    """The order of the finite differences."""

    def __init__(
        out self, var tensor: TensorField, name: String, order: DifferenceOrder
    ):
        """Hold a stress-energy tensor.

        Args:
            tensor: The components, in joules per cubic meter.
            name: The name of the metric.
            order: The order of the finite differences.
        """
        self.tensor = tensor^
        self.name = name
        self.order = order

    def component(self, a: Int, b: Int, point: Int) -> EnergyDensity64:
        """Return one component at one point.

        Args:
            a: The first index, 0 to 3.
            b: The second index, 0 to 3.
            point: The flat index of the point.

        Returns:
            The component. T^00 is the energy density.
        """
        return EnergyDensity64(self.tensor.get(a, b, point))


@always_inline
def _d1(d1: List[Float64], i: Int, j: Int, k: Int) -> Float64:
    """Return ∂_k g_ij from the scratch storage."""
    return d1[(4 * i + j) * 4 + k]


@always_inline
def _d2(d2: List[Float64], i: Int, j: Int, k: Int, n: Int) -> Float64:
    """Return ∂_k ∂_n g_ij from the scratch storage."""
    return d2[((4 * i + j) * 4 + k) * 4 + n]


def _metric_derivatives(
    metric: Metric,
    stencil: Stencil,
    point: Int,
    mut d1: List[Float64],
    mut d2: List[Float64],
):
    """Fill the first and second derivatives of g_ij at one point.

    Both are symmetric in i and j, and the second is symmetric in its two
    derivative axes, so each value is computed once and copied.
    """
    var n = metric.tensor.grid.points()
    var at = metric.tensor.grid.position(point)
    for i in range(4):
        for j in range(i, 4):  # pragma: no branch
            var base = (4 * i + j) * n
            for k in range(4):
                var first = stencil.first(
                    metric.tensor.data, base, point, at, k
                )
                d1[(4 * i + j) * 4 + k] = first
                d1[(4 * j + i) * 4 + k] = first
                for m in range(k, 4):  # pragma: no branch
                    var second = stencil.second(
                        metric.tensor.data, base, point, at, k, m
                    )
                    d2[((4 * i + j) * 4 + k) * 4 + m] = second
                    d2[((4 * i + j) * 4 + m) * 4 + k] = second
                    d2[((4 * j + i) * 4 + k) * 4 + m] = second
                    d2[((4 * j + i) * 4 + m) * 4 + k] = second


def _ricci(gu: Matrix4, d1: List[Float64], d2: List[Float64]) -> Matrix4:
    """Return R_ij at one point from g^ab and the derivatives of g_ab.

    This is WarpFactory's `ricciT`, term for term.
    """
    var out = Matrix4(0)
    for i in range(4):
        for j in range(i, 4):  # pragma: no branch
            var total = 0.0
            for a in range(4):
                for b in range(4):
                    var term = -(
                        _d2(d2, i, j, a, b)
                        + _d2(d2, a, b, i, j)
                        - _d2(d2, i, b, j, a)
                        - _d2(d2, j, b, i, a)
                    )
                    for r in range(4):
                        var t3 = 0.0
                        var t4 = 0.0
                        var t5 = 0.0
                        for d in range(4):
                            var up = gu[4 * r + d]
                            t3 += _d1(d1, b, d, j) * up
                            t4 += (_d1(d1, j, d, b) - _d1(d1, j, b, d)) * up
                            t5 -= (
                                2.0 * _d1(d1, b, d, a) - _d1(d1, a, b, d)
                            ) * up
                        term += t4 * _d1(d1, i, r, a) + 0.5 * (
                            t3 * _d1(d1, a, r, i)
                            + t5
                            * (
                                _d1(d1, j, r, i)
                                + _d1(d1, i, r, j)
                                - _d1(d1, j, i, r)
                            )
                        )
                    total += gu[4 * a + b] * term
            out[4 * i + j] = 0.5 * total
            out[4 * j + i] = 0.5 * total
    return out


def _sum_products(a: Matrix4, b: Matrix4) -> Float64:
    """Return Σ a_ij b_ij."""
    return (a * b).reduce_add()


def curvature(
    metric: Metric, order: DifferenceOrder = FOURTH_ORDER
) raises -> Curvature:
    """Return the Ricci tensor, the Ricci scalar and the Einstein tensor.

    These are WarpFactory's `ricciT`, `ricciS` and `einT`.

    Args:
        metric: The metric.
        order: The order of the finite differences.

    Returns:
        The three curvatures at each point.

    Raises:
        Error: If the order is not valid or the metric is singular at a
            point.
    """
    var grid = metric.grid()
    var stencil = Stencil(grid, order)
    var ricci = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var einstein = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var scalar = List[Float64](capacity=grid.points())
    var d1 = List[Float64](length=64, fill=0.0)
    var d2 = List[Float64](length=256, fill=0.0)
    for point in range(grid.points()):  # pragma: no branch
        var g = metric.at(point)
        var gu = inverse4(g)
        _metric_derivatives(metric, stencil, point, d1, d2)
        var r = _ricci(gu, d1, d2)
        var s = _sum_products(gu, r)
        ricci.set_matrix(point, r)
        scalar.append(s)
        einstein.set_matrix(point, r - 0.5 * s * g)
    return Curvature(ricci^, scalar^, einstein^)


def stress_energy(
    metric: Metric, order: DifferenceOrder = FOURTH_ORDER
) raises -> StressEnergy:
    """Return the stress-energy tensor T^ab that a metric needs.

    This is WarpFactory's `getEnergyTensor` on the CPU. The tensor is
    contravariant and in the coordinate frame.

    Args:
        metric: The metric.
        order: The order of the finite differences. The fourth order
            needs 5 points along an axis, the second order 3, for that
            axis to have derivatives.

    Returns:
        The tensor, in joules per cubic meter.

    Raises:
        Error: If the order is not valid or the metric is singular at a
            point.
    """
    var grid = metric.grid()
    var stencil = Stencil(grid, order)
    var out = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    var kappa = einstein_coupling()
    var d1 = List[Float64](length=64, fill=0.0)
    var d2 = List[Float64](length=256, fill=0.0)
    for point in range(grid.points()):  # pragma: no branch
        var g = metric.at(point)
        var gu = inverse4(g)
        _metric_derivatives(metric, stencil, point, d1, d2)
        var r = _ricci(gu, d1, d2)
        var e = r - 0.5 * _sum_products(gu, r) * g
        out.set_matrix(point, kappa * multiply4(multiply4(gu, e), gu))
    return StressEnergy(out^, metric.name, order)
