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

On the azimuth φ of a spherical or cylindrical grid whose points cover a
whole turn, the neighbors wrap around the circle, and there is no edge.

A `Stencil` reads a field through a `FieldPointer` of any address space, so
the CPU solver and the GPU kernel of `extensions/warp/gpu.mojo` take the
same differences.
"""

from std.memory import AddressSpace

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import Axis, DifferenceOrder, FOURTH_ORDER

comptime FieldPointer[space: AddressSpace] = MutPointer[
    Float64, MutAnyOrigin, address_space=space
]
"""Storage of Float64 values in an address space: host memory, or a device's.
"""


def field_pointer(data: List[Float64]) -> FieldPointer[AddressSpace.GENERIC]:
    """Return a pointer to the values of a list on the host.

    Args:
        data: The values. The list must outlive the pointer.

    Returns:
        The pointer.
    """
    return (
        data.unsafe_ptr()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[MutAnyOrigin]()
    )


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
    """The coordinate step along each axis, in meters or radians."""
    var wraps: SIMD[DType.int64, 4]
    """1 for an axis whose points cover a whole turn, so its neighbors
    wrap around; 0 otherwise."""
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
        if not order.is_stencil():
            raise Error("A finite-difference order is not valid")
        self.counts = grid.counts
        self.strides = SIMD[DType.int64, 4](0)
        self.steps = SIMD[DType.float64, 4](0)
        self.wraps = SIMD[DType.int64, 4](0)
        for axis in range(4):
            self.strides[axis] = Int64(grid.stride(Axis(axis)))
            self.steps[axis] = grid.coordinate_step(Axis(axis))
            self.wraps[axis] = Int64(Int(grid.periodic(axis)))
        self.reach = order.reach()

    def __init__(
        out self,
        *,
        counts: SIMD[DType.int64, 4],
        strides: SIMD[DType.int64, 4],
        steps: SIMD[DType.float64, 4],
        wraps: SIMD[DType.int64, 4],
        reach: Int,
    ):
        """Rebuild a stencil from its fields, as a GPU kernel receives them.

        Args:
            counts: The number of points along each axis.
            strides: The distance between neighbors along each axis.
            steps: The coordinate step along each axis.
            wraps: 1 for an axis whose neighbors wrap around, 0 otherwise.
            reach: How many points the stencil reads on each side.
        """
        self.counts = counts
        self.strides = strides
        self.steps = steps
        self.wraps = wraps
        self.reach = reach

    def position(self, point: Int) -> SIMD[DType.int64, 4]:
        """Return the four indexes of a flat index, as the grid does.

        Args:
            point: The flat index. It must be in range.

        Returns:
            The indexes along t, x, y and z.
        """
        var out = SIMD[DType.int64, 4](0)
        var rest = point
        for axis in range(3, -1, -1):  # pragma: no branch
            var count = Int(self.counts[axis])
            out[axis] = Int64(rest % count)
            rest //= count
        return out

    def _center(self, point: Int, at: SIMD[DType.int64, 4], axis: Int) -> Int:
        """Return the point the stencil along an axis is centered on.

        On an axis that does not wrap, a point near an edge moves inward
        until the stencil fits, which copies the nearest derivative.
        """
        if self.wraps[axis] != 0:
            return point
        var here = Int(at[axis])
        var n = Int(self.counts[axis])
        var moved = _clamp(here, self.reach, n - 1 - self.reach)
        return point + (moved - here) * Int(self.strides[axis])

    def _offset(self, at: SIMD[DType.int64, 4], axis: Int, k: Int) -> Int:
        """Return the storage offset of the neighbor `k` steps along an
        axis from a stencil center. On an axis that wraps, it wraps."""
        var s = Int(self.strides[axis])
        if self.wraps[axis] == 0:
            return k * s
        var n = Int(self.counts[axis])
        var here = Int(at[axis])
        var to = ((here + k) % n + n) % n
        return (to - here) * s

    def _difference[
        space: AddressSpace
    ](
        self,
        data: FieldPointer[space],
        p: Int,
        at: SIMD[DType.int64, 4],
        axis: Int,
    ) -> Float64:
        """Return the first-difference stencil centered at storage index
        `p`, whose indexes are `at`."""
        var h = self.steps[axis]
        var o1 = self._offset(at, axis, 1)
        var m1 = self._offset(at, axis, -1)
        if self.reach == 2:
            var o2 = self._offset(at, axis, 2)
            var m2 = self._offset(at, axis, -2)
            return (
                -(data[unsafe_offset=p + o2] - data[unsafe_offset=p + m2])
                + 8.0
                * (data[unsafe_offset=p + o1] - data[unsafe_offset=p + m1])
            ) / (12.0 * h)
        return (data[unsafe_offset=p + o1] - data[unsafe_offset=p + m1]) / (
            2.0 * h
        )

    def first(
        self,
        data: List[Float64],
        base: Int,
        point: Int,
        at: SIMD[DType.int64, 4],
        axis: Int,
    ) -> Float64:
        """Return the first derivative of a field on the host along one axis.

        Args:
            data: The storage that holds the field.
            base: Where the field starts in `data`.
            point: The flat index of the point.
            at: The four indexes of the point.
            axis: The axis, 0 to 3.

        Returns:
            The derivative, per meter or per radian.
        """
        return self.first(field_pointer(data), base, point, at, axis)

    def first[
        space: AddressSpace
    ](
        self,
        data: FieldPointer[space],
        base: Int,
        point: Int,
        at: SIMD[DType.int64, 4],
        axis: Int,
    ) -> Float64:
        """Return the first derivative of a field along one axis.

        Parameters:
            space: The address space of the storage.

        Args:
            data: The storage that holds the field.
            base: Where the field starts in `data`.
            point: The flat index of the point.
            at: The four indexes of the point.
            axis: The axis, 0 to 3.

        Returns:
            The derivative, per meter or per radian.
        """
        var n = Int(self.counts[axis])
        if n < 2 * self.reach + 1:
            return 0.0
        var center = self._center(point, at, axis)
        var moved = at
        moved[axis] = Int64(
            Int(at[axis]) + (center - point) // Int(self.strides[axis])
        )
        return self._difference(data, base + center, moved, axis)

    def second(
        self,
        data: List[Float64],
        base: Int,
        point: Int,
        at: SIMD[DType.int64, 4],
        first_axis: Int,
        second_axis: Int,
    ) -> Float64:
        """Return the second derivative of a field on the host along two axes.

        Args:
            data: The storage that holds the field.
            base: Where the field starts in `data`.
            point: The flat index of the point.
            at: The four indexes of the point.
            first_axis: The first axis, 0 to 3.
            second_axis: The second axis, 0 to 3.

        Returns:
            The derivative, per square meter or radian.
        """
        return self.second(
            field_pointer(data), base, point, at, first_axis, second_axis
        )

    def second[
        space: AddressSpace
    ](
        self,
        data: FieldPointer[space],
        base: Int,
        point: Int,
        at: SIMD[DType.int64, 4],
        first_axis: Int,
        second_axis: Int,
    ) -> Float64:
        """Return the second derivative of a field along two axes.

        Parameters:
            space: The address space of the storage.

        Args:
            data: The storage that holds the field.
            base: Where the field starts in `data`.
            point: The flat index of the point.
            at: The four indexes of the point.
            first_axis: The first axis, 0 to 3.
            second_axis: The second axis, 0 to 3.

        Returns:
            The derivative, per square meter or radian.
        """
        var reach = self.reach
        var n1 = Int(self.counts[first_axis])
        var n2 = Int(self.counts[second_axis])
        if n1 < 2 * reach + 1 or n2 < 2 * reach + 1:
            return 0.0
        var h1 = self.steps[first_axis]
        if first_axis == second_axis:
            var center = self._center(point, at, first_axis)
            var moved = at
            moved[first_axis] = Int64(
                Int(at[first_axis])
                + (center - point) // Int(self.strides[first_axis])
            )
            var p = base + center
            var o1 = self._offset(moved, first_axis, 1)
            var m1 = self._offset(moved, first_axis, -1)
            if reach == 2:
                var o2 = self._offset(moved, first_axis, 2)
                var m2 = self._offset(moved, first_axis, -2)
                return (
                    -(data[unsafe_offset=p + o2] + data[unsafe_offset=p + m2])
                    + 16.0
                    * (data[unsafe_offset=p + o1] + data[unsafe_offset=p + m1])
                    - 30.0 * data[unsafe_offset=p]
                ) / (12.0 * h1 * h1)
            return (
                data[unsafe_offset=p + o1]
                - 2.0 * data[unsafe_offset=p]
                + data[unsafe_offset=p + m1]
            ) / (h1 * h1)
        if not (self._inside(at, first_axis) and self._inside(at, second_axis)):
            return 0.0
        var h2 = self.steps[second_axis]
        var p = base + point
        var o1 = self._offset(at, second_axis, 1)
        var m1 = self._offset(at, second_axis, -1)
        if reach == 2:
            var o2 = self._offset(at, second_axis, 2)
            var m2 = self._offset(at, second_axis, -2)
            return (
                -self._difference(data, p + o2, at, first_axis)
                + self._difference(data, p + m2, at, first_axis)
                + 8.0 * self._difference(data, p + o1, at, first_axis)
                - 8.0 * self._difference(data, p + m1, at, first_axis)
            ) / (12.0 * h2)
        return (
            self._difference(data, p + o1, at, first_axis)
            - self._difference(data, p + m1, at, first_axis)
        ) / (2.0 * h2)

    def _inside(self, at: SIMD[DType.int64, 4], axis: Int) -> Bool:
        """Return True if a mixed stencil fits along an axis at a point."""
        var here = Int(at[axis])
        var n = Int(self.counts[axis])
        return self.wraps[axis] != 0 or (
            here >= self.reach and here <= n - 1 - self.reach
        )


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
