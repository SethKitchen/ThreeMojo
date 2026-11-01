# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite differences of a field on a spacetime grid.

These are WarpFactory's `takeFiniteDifference1` and
`takeFiniteDifference2`, and their second-order forms. The derivative
along t is taken with respect to x⁰ = c t.

The fourth-order stencils read two points on each side:

    ∂f   ≈ (-(f₊₂ - f₋₂) + 8 (f₊₁ - f₋₁)) / (12 h)
    ∂²f  ≈ (-(f₊₂ + f₋₂) + 16 (f₊₁ + f₋₁) - 30 f₀) / (12 h²)

The second-order stencils read one point on each side. A mixed second
derivative is the product of the two first-derivative stencils.

At the edge of the grid, WarpFactory copies the nearest derivative that
the stencil can reach. A mixed derivative is zero there. An axis with
fewer points than the stencil needs, 5 or 3, has a derivative of zero.
So a grid with one time slice is static.
"""

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import Axis, DifferenceOrder, FOURTH_ORDER


def _clamp(value: Int, low: Int, high: Int) -> Int:
    """Return `value` limited to the closed range from `low` to `high`."""
    return min(max(value, low), high)


struct Stencil(ImplicitlyCopyable, Movable):
    """The counts, strides and steps that a stencil reads a grid with."""

    var counts: SIMD[DType.int64, 4]
    """The number of points along each axis."""
    var strides: SIMD[DType.int64, 4]
    """The distance between neighbors along each axis, in storage."""
    var steps: SIMD[DType.float64, 4]
    """The coordinate step along each axis, in meters."""
    var reach: Int
    """How many points the stencil reads on each side."""

    def __init__(out self, grid: SpacetimeGrid, order: DifferenceOrder) raises:
        """Prepare to take differences on a grid.

        Args:
            grid: The grid.
            order: The order of the stencils.

        Raises:
            Error: If the order is not valid.
        """
        if not order.is_valid():
            raise Error("A finite-difference order is not valid")
        self.counts = grid.counts
        self.strides = SIMD[DType.int64, 4](0)
        self.steps = SIMD[DType.float64, 4](0)
        for axis in range(4):
            self.strides[axis] = Int64(grid.stride(Axis(axis)))
            self.steps[axis] = grid.coordinate_step(Axis(axis))
        self.reach = order.reach()

    def first(
        self,
        data: List[Float64],
        base: Int,
        point: Int,
        at: SIMD[DType.int64, 4],
        axis: Int,
    ) -> Float64:
        """Return the first derivative of a field along one axis.

        Args:
            data: The storage that holds the field.
            base: Where the field starts in `data`.
            point: The flat index of the point.
            at: The four indexes of the point.
            axis: The axis, 0 to 3.

        Returns:
            The derivative, per meter.
        """
        var n = Int(self.counts[axis])
        var reach = self.reach
        if n < 2 * reach + 1:
            return 0.0
        var s = Int(self.strides[axis])
        var here = Int(at[axis])
        var p = base + point + (_clamp(here, reach, n - 1 - reach) - here) * s
        var h = self.steps[axis]
        if reach == 2:
            return (
                -(data[p + 2 * s] - data[p - 2 * s])
                + 8.0 * (data[p + s] - data[p - s])
            ) / (12.0 * h)
        return (data[p + s] - data[p - s]) / (2.0 * h)

    def _cross_first(
        self, data: List[Float64], p: Int, s: Int, h: Float64
    ) -> Float64:
        """Return the first-difference stencil at storage index `p`, without
        the clamp."""
        if self.reach == 2:
            return (
                -(data[p + 2 * s] - data[p - 2 * s])
                + 8.0 * (data[p + s] - data[p - s])
            ) / (12.0 * h)
        return (data[p + s] - data[p - s]) / (2.0 * h)

    def second(
        self,
        data: List[Float64],
        base: Int,
        point: Int,
        at: SIMD[DType.int64, 4],
        first_axis: Int,
        second_axis: Int,
    ) -> Float64:
        """Return the second derivative of a field along two axes.

        Args:
            data: The storage that holds the field.
            base: Where the field starts in `data`.
            point: The flat index of the point.
            at: The four indexes of the point.
            first_axis: The first axis, 0 to 3.
            second_axis: The second axis, 0 to 3.

        Returns:
            The derivative, per square meter.
        """
        var reach = self.reach
        var n1 = Int(self.counts[first_axis])
        var n2 = Int(self.counts[second_axis])
        if n1 < 2 * reach + 1 or n2 < 2 * reach + 1:
            return 0.0
        var s1 = Int(self.strides[first_axis])
        var h1 = self.steps[first_axis]
        var here1 = Int(at[first_axis])
        if first_axis == second_axis:
            var p = (
                base
                + point
                + (_clamp(here1, reach, n1 - 1 - reach) - here1) * s1
            )
            if reach == 2:
                return (
                    -(data[p + 2 * s1] + data[p - 2 * s1])
                    + 16.0 * (data[p + s1] + data[p - s1])
                    - 30.0 * data[p]
                ) / (12.0 * h1 * h1)
            return (data[p + s1] - 2.0 * data[p] + data[p - s1]) / (h1 * h1)
        var here2 = Int(at[second_axis])
        if (
            here1 < reach
            or here1 > n1 - 1 - reach
            or here2 < reach
            or here2 > n2 - 1 - reach
        ):
            return 0.0
        var s2 = Int(self.strides[second_axis])
        var h2 = self.steps[second_axis]
        var p = base + point
        if reach == 2:
            return (
                -self._cross_first(data, p + 2 * s2, s1, h1)
                + self._cross_first(data, p - 2 * s2, s1, h1)
                + 8.0 * self._cross_first(data, p + s2, s1, h1)
                - 8.0 * self._cross_first(data, p - s2, s1, h1)
            ) / (12.0 * h2)
        return (
            self._cross_first(data, p + s2, s1, h1)
            - self._cross_first(data, p - s2, s1, h1)
        ) / (2.0 * h2)


def _require_field(field: List[Float64], grid: SpacetimeGrid) raises:
    """Raise unless a field has one value for each grid point."""
    if len(field) != grid.points():
        raise Error("A field must have one value for each grid point")


def derivative(
    field: List[Float64],
    grid: SpacetimeGrid,
    axis: Axis,
    order: DifferenceOrder = FOURTH_ORDER,
) raises -> List[Float64]:
    """Return the first derivative of a field along one axis.

    This is WarpFactory's `takeFiniteDifference1`, or its second-order
    form. Along t, the derivative is with respect to c t.

    Args:
        field: One value for each grid point, in the grid's order.
        grid: The grid.
        axis: The axis.
        order: The order of the stencil.

    Returns:
        The derivative at each point, per meter.

    Raises:
        Error: If the field has the wrong length, or the axis or the
            order is not valid.
    """
    _require_field(field, grid)
    if not axis.is_valid():
        raise Error("An axis is not valid")
    var stencil = Stencil(grid, order)
    var out = List[Float64](capacity=grid.points())
    for point in range(grid.points()):  # pragma: no branch
        out.append(
            stencil.first(field, 0, point, grid.position(point), axis.value)
        )
    return out^


def second_derivative(
    field: List[Float64],
    grid: SpacetimeGrid,
    first_axis: Axis,
    second_axis: Axis,
    order: DifferenceOrder = FOURTH_ORDER,
) raises -> List[Float64]:
    """Return the second derivative of a field along two axes.

    This is WarpFactory's `takeFiniteDifference2`, or its second-order
    form.

    Args:
        field: One value for each grid point, in the grid's order.
        grid: The grid.
        first_axis: The first axis.
        second_axis: The second axis. It can be the first axis.
        order: The order of the stencil.

    Returns:
        The derivative at each point, per square meter.

    Raises:
        Error: If the field has the wrong length, or an axis or the order
            is not valid.
    """
    _require_field(field, grid)
    if not (first_axis.is_valid() and second_axis.is_valid()):
        raise Error("An axis is not valid")
    var stencil = Stencil(grid, order)
    var out = List[Float64](capacity=grid.points())
    for point in range(grid.points()):  # pragma: no branch
        out.append(
            stencil.second(
                field,
                0,
                point,
                grid.position(point),
                first_axis.value,
                second_axis.value,
            )
        )
    return out^
