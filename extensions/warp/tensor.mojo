# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rank-two tensor fields on a spacetime grid.

A `TensorField` holds the 16 components of a 4 by 4 tensor at each point
of a grid, with the position of its indices and the frame they are
measured in. WarpFactory holds the same thing as a 4 by 4 cell array of
4D arrays.

A `Metric` is a covariant tensor field in the coordinate frame, with a
name. Its components are dimensionless, because x⁰ = c t.

`change_index` raises or lowers the indices of a tensor. It uses the
metric for a tensor in the coordinate frame and the Minkowski metric for
a tensor in the Eulerian frame.

## Differences from WarpFactory

- WarpFactory's `changeTensorIndex` changes nothing between the two mixed
  positions, and labels the result with the new position. Here a mixed
  tensor changes to the other mixed position correctly.
- WarpFactory lowers a tensor in the Eulerian frame with the metric of
  the coordinate frame. The Eulerian frame is orthonormal, so this port
  lowers it with the Minkowski metric. See `conditions`.
- A metric here is always covariant. `Metric.inverse` gives the
  contravariant components.
"""

from std.math import isfinite

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    EULERIAN_FRAME,
    Frame,
    MIXED_DOWN_UP,
    MIXED_UP_DOWN,
    TensorIndex,
)

comptime Matrix4 = SIMD[DType.float64, 16]
"""A 4 by 4 matrix in row-major order: entry (a, b) is at 4 a + b."""
comptime Vector4 = SIMD[DType.float64, 4]
"""A 4-vector: the t, x, y and z components."""

comptime MINKOWSKI = Matrix4(-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
"""The Minkowski metric, diag(-1, 1, 1, 1). It is its own inverse."""


def multiply4(a: Matrix4, b: Matrix4) -> Matrix4:
    """Return the matrix product a b.

    Args:
        a: The left factor.
        b: The right factor.

    Returns:
        The product.
    """
    var out = Matrix4(0)
    for row in range(4):
        for col in range(4):
            var total = 0.0
            for k in range(4):
                total += a[4 * row + k] * b[4 * k + col]
            out[4 * row + col] = total
    return out


def transpose4(a: Matrix4) -> Matrix4:
    """Return the transpose of a matrix.

    Args:
        a: The matrix.

    Returns:
        The matrix with rows and columns swapped.
    """
    var out = Matrix4(0)
    for row in range(4):
        for col in range(4):
            out[4 * col + row] = a[4 * row + col]
    return out


def apply4(a: Matrix4, v: Vector4) -> Vector4:
    """Return the product of a matrix and a column vector.

    Args:
        a: The matrix.
        v: The vector.

    Returns:
        The product a v.
    """
    var out = Vector4(0)
    for row in range(4):
        var total = 0.0
        for k in range(4):
            total += a[4 * row + k] * v[k]
        out[row] = total
    return out


def _minor3(
    a: Matrix4, r0: Int, r1: Int, r2: Int, c0: Int, c1: Int, c2: Int
) -> Float64:
    """Return the determinant of the 3 by 3 part of `a` at the given rows
    and columns."""
    return (
        a[4 * r0 + c0]
        * (a[4 * r1 + c1] * a[4 * r2 + c2] - a[4 * r1 + c2] * a[4 * r2 + c1])
        - a[4 * r0 + c1]
        * (a[4 * r1 + c0] * a[4 * r2 + c2] - a[4 * r1 + c2] * a[4 * r2 + c0])
        + a[4 * r0 + c2]
        * (a[4 * r1 + c0] * a[4 * r2 + c1] - a[4 * r1 + c1] * a[4 * r2 + c0])
    )


def _others(skip: Int) -> SIMD[DType.int64, 4]:
    """Return the three indexes of 0 to 3 other than `skip`, in order."""
    var out = SIMD[DType.int64, 4](0)
    var next = 0
    for index in range(4):
        if index != skip:
            out[next] = Int64(index)
            next += 1
    return out


def cofactors4(a: Matrix4) -> Matrix4:
    """Return the matrix of cofactors of a 4 by 4 matrix.

    Args:
        a: The matrix.

    Returns:
        Entry (i, j) is (-1)^(i + j) times the minor without row i and
        column j.
    """
    var out = Matrix4(0)
    for row in range(4):
        var r = _others(row)
        for col in range(4):
            var c = _others(col)
            var minor = _minor3(
                a,
                Int(r[0]),
                Int(r[1]),
                Int(r[2]),
                Int(c[0]),
                Int(c[1]),
                Int(c[2]),
            )
            var sign = 1.0 - 2.0 * Float64((row + col) % 2)
            out[4 * row + col] = sign * minor
    return out


def determinant4(a: Matrix4) -> Float64:
    """Return the determinant of a 4 by 4 matrix.

    This is WarpFactory's `cDet`: the expansion along the first row.

    Args:
        a: The matrix.

    Returns:
        The determinant.
    """
    var cof = cofactors4(a)
    return a[0] * cof[0] + a[1] * cof[1] + a[2] * cof[2] + a[3] * cof[3]


def inverse4(a: Matrix4) raises -> Matrix4:
    """Return the inverse of a 4 by 4 matrix, by cofactors.

    This is WarpFactory's `c4Inv`.

    Args:
        a: The matrix.

    Returns:
        The inverse.

    Raises:
        Error: If the determinant is zero or not finite.
    """
    var cof = cofactors4(a)
    var det = a[0] * cof[0] + a[1] * cof[1] + a[2] * cof[2] + a[3] * cof[3]
    if det == 0.0 or not isfinite(det):
        raise Error("A metric is singular at a grid point")
    return transpose4(cof) / det


struct TensorField(Copyable, Movable):
    """The 16 components of a rank-two tensor at each point of a grid."""

    var grid: SpacetimeGrid
    """The grid the tensor is sampled on."""
    var index: TensorIndex
    """Where the two indices sit."""
    var frame: Frame
    """The frame the components are measured in."""
    var data: List[Float64]
    """Component (a, b) at point p is at (4 a + b) times the point count,
    plus p."""

    def __init__(
        out self, grid: SpacetimeGrid, index: TensorIndex, frame: Frame
    ) raises:
        """Create a tensor field of zeros.

        Args:
            grid: The grid.
            index: The position of the indices.
            frame: The frame of the components.

        Raises:
            Error: If the index position or the frame is not valid.
        """
        if not index.is_valid():
            raise Error("A tensor index position is not valid")
        if not frame.is_valid():
            raise Error("A tensor frame is not valid")
        self.grid = grid
        self.index = index
        self.frame = frame
        self.data = List[Float64](length=16 * grid.points(), fill=0.0)

    def get(self, a: Int, b: Int, point: Int) -> Float64:
        """Return one component at one point. The indexes must be in range.

        Args:
            a: The first index, 0 to 3.
            b: The second index, 0 to 3.
            point: The flat index of the point.

        Returns:
            The component.
        """
        return self.data[(4 * a + b) * self.grid.points() + point]

    def set(mut self, a: Int, b: Int, point: Int, value: Float64):
        """Set one component at one point. The indexes must be in range.

        Args:
            a: The first index, 0 to 3.
            b: The second index, 0 to 3.
            point: The flat index of the point.
            value: The new component.
        """
        self.data[(4 * a + b) * self.grid.points() + point] = value

    def set_symmetric(mut self, a: Int, b: Int, point: Int, value: Float64):
        """Set components (a, b) and (b, a) at one point.

        Args:
            a: The first index, 0 to 3.
            b: The second index, 0 to 3.
            point: The flat index of the point.
            value: The new component.
        """
        self.set(a, b, point, value)
        self.set(b, a, point, value)

    def matrix(self, point: Int) -> Matrix4:
        """Return the 16 components at one point.

        Args:
            point: The flat index of the point.

        Returns:
            The components, in row-major order.
        """
        var out = Matrix4(0)
        var n = self.grid.points()
        for k in range(16):
            out[k] = self.data[k * n + point]
        return out

    def set_matrix(mut self, point: Int, value: Matrix4):
        """Set the 16 components at one point.

        Args:
            point: The flat index of the point.
            value: The components, in row-major order.
        """
        var n = self.grid.points()
        for k in range(16):
            self.data[k * n + point] = value[k]

    def component(self, a: Int, b: Int) -> List[Float64]:
        """Return one component at every point.

        Args:
            a: The first index, 0 to 3.
            b: The second index, 0 to 3.

        Returns:
            One value for each point, in the grid's order.
        """
        var n = self.grid.points()
        var start = (4 * a + b) * n
        var out = List[Float64](capacity=n)
        for point in range(n):  # pragma: no branch
            out.append(self.data[start + point])
        return out^

    def require_finite(self) raises:
        """Raise unless every component is finite.

        Raises:
            Error: If a component is NaN or infinite.
        """
        for k in range(len(self.data)):  # pragma: no branch
            if not isfinite(self.data[k]):
                raise Error("A tensor component is not finite")


struct Metric(Copyable, Movable):
    """A covariant metric tensor field g_ab in the coordinate frame."""

    var tensor: TensorField
    """The components g_ab. They are dimensionless."""
    var name: String
    """WarpFactory's name of the metric, such as "Alcubierre"."""

    def __init__(out self, var tensor: TensorField, name: String) raises:
        """Create a metric from its covariant components.

        Args:
            tensor: The components g_ab.
            name: The name of the metric.

        Raises:
            Error: If the tensor is not covariant, is not in the coordinate
                frame, has a component that is not finite, or is not
                symmetric.
        """
        if tensor.index != COVARIANT:
            raise Error("A metric must be covariant")
        if tensor.frame != COORDINATE_FRAME:
            raise Error("A metric must be in the coordinate frame")
        tensor.require_finite()
        for a in range(4):
            for b in range(a + 1, 4):
                for point in range(tensor.grid.points()):  # pragma: no branch
                    if tensor.get(a, b, point) != tensor.get(b, a, point):
                        raise Error("A metric must be symmetric")
        self.tensor = tensor^
        self.name = name

    def grid(self) -> SpacetimeGrid:
        """Return the grid of the metric.

        Returns:
            The grid.
        """
        return self.tensor.grid

    def at(self, point: Int) -> Matrix4:
        """Return g_ab at one point.

        Args:
            point: The flat index of the point.

        Returns:
            The components, in row-major order.
        """
        return self.tensor.matrix(point)

    def inverse(self) raises -> TensorField:
        """Return the contravariant metric g^ab.

        Returns:
            The inverse at every point.

        Raises:
            Error: If the metric is singular at a point.
        """
        var out = TensorField(self.tensor.grid, CONTRAVARIANT, COORDINATE_FRAME)
        for point in range(self.tensor.grid.points()):  # pragma: no branch
            out.set_matrix(point, inverse4(self.tensor.matrix(point)))
        return out^


def _first_up(index: TensorIndex) -> Bool:
    """Return True if the first index of a position is up."""
    return index == CONTRAVARIANT or index == MIXED_UP_DOWN


def _second_up(index: TensorIndex) -> Bool:
    """Return True if the second index of a position is up."""
    return index == CONTRAVARIANT or index == MIXED_DOWN_UP


def change_index(
    tensor: TensorField, target: TensorIndex, metric: Metric
) raises -> TensorField:
    """Return a tensor with its indices moved to another position.

    This is WarpFactory's `changeTensorIndex`. To lower an index the
    tensor is contracted with g_ab, and to raise one with g^ab. A tensor
    in the Eulerian frame uses the Minkowski metric.

    Args:
        tensor: The tensor.
        target: The position to move the indices to.
        metric: The metric of the spacetime. It must have the same grid.

    Returns:
        The tensor at `target`, in the same frame.

    Raises:
        Error: If `target` is not valid, the grids differ, or the metric
            is singular at a point.
    """
    if not target.is_valid():
        raise Error("A tensor index position is not valid")
    if tensor.grid != metric.tensor.grid:
        raise Error("A tensor and its metric must share one grid")
    var out = TensorField(tensor.grid, target, tensor.frame)
    var raise_first = not _first_up(tensor.index) and _first_up(target)
    var lower_first = _first_up(tensor.index) and not _first_up(target)
    var raise_second = not _second_up(tensor.index) and _second_up(target)
    var lower_second = _second_up(tensor.index) and not _second_up(target)
    var eulerian = tensor.frame == EULERIAN_FRAME
    for point in range(tensor.grid.points()):  # pragma: no branch
        var down = MINKOWSKI
        if not eulerian:
            down = metric.at(point)
        var up = MINKOWSKI
        if not eulerian and (raise_first or raise_second):
            up = inverse4(down)
        var value = tensor.matrix(point)
        if raise_first:
            value = multiply4(up, value)
        if lower_first:
            value = multiply4(down, value)
        if raise_second:
            value = multiply4(value, up)
        if lower_second:
            value = multiply4(value, down)
        out.set_matrix(point, value)
    return out^


def trace(tensor: TensorField, metric: Metric) raises -> List[Float64]:
    """Return the trace of a tensor at every point.

    This is WarpFactory's `getTrace`. A covariant tensor is contracted
    with g^ab, a contravariant one with g_ab, and a mixed one is summed
    along its diagonal. A tensor in the Eulerian frame uses the Minkowski
    metric.

    Args:
        tensor: The tensor.
        metric: The metric of the spacetime. It must have the same grid.

    Returns:
        One trace for each point, in the units of the tensor.

    Raises:
        Error: If the grids differ or the metric is singular at a point.
    """
    var mixed = change_index(tensor, MIXED_UP_DOWN, metric)
    var out = List[Float64](capacity=tensor.grid.points())
    for point in range(tensor.grid.points()):  # pragma: no branch
        var value = mixed.matrix(point)
        out.append(value[0] + value[5] + value[10] + value[15])
    return out^
