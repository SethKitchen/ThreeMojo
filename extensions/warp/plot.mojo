# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Planes cut through a field, drawn with WarpFactory's red-blue colors.

`slice_plane` holds two axes at one index each and keeps the other two,
as WarpFactory's `getSliceData` does for `plotTensor`. `red_blue` is the
color map of WarpFactory's `redblue`: white at zero, red for negative
values and blue for positive ones. `draw_plane` fills a frame with a
plane, one square block of pixels for each grid point.

WarpFactory draws with MATLAB figures, titles and axes. This port draws
only the colored plane.
"""

from std.math import isfinite

from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import Axis
from render.framebuffer import Color, Framebuffer, unit_byte


struct PlaneSlice(Copyable, Movable):
    """A plane of values cut from a field on a grid."""

    var columns: Int
    """The number of points along the first free axis."""
    var rows: Int
    """The number of points along the second free axis."""
    var values: List[Float64]
    """Row r, column c is at r times `columns`, plus c."""

    def __init__(out self, columns: Int, rows: Int, var values: List[Float64]):
        """Hold a plane.

        Args:
            columns: The number of points along the first free axis.
            rows: The number of points along the second free axis.
            values: The values, row by row.
        """
        self.columns = columns
        self.rows = rows
        self.values = values^

    def at(self, column: Int, row: Int) -> Float64:
        """Return one value. The indexes must be in range.

        Args:
            column: The index along the first free axis.
            row: The index along the second free axis.

        Returns:
            The value.
        """
        return self.values[row * self.columns + column]

    def bounds(self) -> SIMD[DType.float64, 2]:
        """Return the least and the greatest finite value.

        Returns:
            The two values, or zeros if no value is finite.
        """
        var low = 0.0
        var high = 0.0
        var found = False
        for value in self.values:
            if isfinite(value):
                if not found:
                    low = value
                    high = value
                    found = True
                low = min(low, value)
                high = max(high, value)
        return SIMD[DType.float64, 2](low, high)


def slice_plane(
    field: List[Float64],
    grid: SpacetimeGrid,
    first_fixed: Axis,
    first_index: Int,
    second_fixed: Axis,
    second_index: Int,
) raises -> PlaneSlice:
    """Return the plane of a field where two axes are held at one index.

    The two free axes keep their order: the first is the columns and the
    second the rows. To cut the x-y plane at slice t and height z, hold
    `T_AXIS` and `Z_AXIS`.

    Args:
        field: One value for each grid point, in the grid's order.
        grid: The grid.
        first_fixed: The first axis to hold.
        first_index: The index to hold it at.
        second_fixed: The second axis to hold.
        second_index: The index to hold it at.

    Returns:
        The plane.

    Raises:
        Error: If the field has the wrong length, an axis is not valid,
            the two axes are the same, or an index is out of range.
    """
    if len(field) != grid.points():
        raise Error("A field must have one value for each grid point")
    if not (first_fixed.is_valid() and second_fixed.is_valid()):
        raise Error("An axis is not valid")
    if first_fixed == second_fixed:
        raise Error("A plane needs two different axes to hold")
    if (
        first_index < 0
        or first_index >= grid.count(first_fixed)
        or second_index < 0
        or second_index >= grid.count(second_fixed)
    ):
        raise Error("A slice index is outside the grid")
    var free = List[Int]()
    for axis in range(4):
        if axis != first_fixed.value and axis != second_fixed.value:
            free.append(axis)
    var columns = grid.count(Axis(free[0]))
    var rows = grid.count(Axis(free[1]))
    var at = SIMD[DType.int64, 4](0)
    at[first_fixed.value] = Int64(first_index)
    at[second_fixed.value] = Int64(second_index)
    var values = List[Float64](capacity=columns * rows)
    for row in range(rows):  # pragma: no branch
        at[free[1]] = Int64(row)
        for column in range(columns):  # pragma: no branch
            at[free[0]] = Int64(column)
            values.append(
                field[
                    grid.index(Int(at[0]), Int(at[1]), Int(at[2]), Int(at[3]))
                ]
            )
    return PlaneSlice(columns, rows, values^)


def _blend(t: Float64) -> UInt8:
    """Return a channel byte for a fraction from 0 to 1."""
    return unit_byte(Float32(t))


def _toward_blue(value: Float64, low: Float64, high: Float64) -> Color:
    """Return white at `low`, going to blue at `high`."""
    var t = 0.0
    if high > low:
        t = (value - low) / (high - low)
    var c = _blend(1.0 - t)
    return Color(c, c, 255)


def _from_red(value: Float64, low: Float64, high: Float64) -> Color:
    """Return red at `low`, going to white at `high`."""
    var t = 1.0
    if high > low:
        t = (value - low) / (high - low)
    var c = _blend(t)
    return Color(255, c, c)


def red_blue(value: Float64, low: Float64, high: Float64) -> Color:
    """Return the color of a value on WarpFactory's red-blue map.

    The map spans `low` to `high`. If the span holds zero, zero is white,
    `low` is red and `high` is blue. If no value is negative, the map
    goes from white at `low` to blue at `high`. If no value is positive,
    it goes from red at `low` to white at `high`. A value that is not
    finite is black.

    Args:
        value: The value.
        low: The least value of the map.
        high: The greatest value of the map.

    Returns:
        The opaque color.
    """
    if not isfinite(value):
        return Color(0, 0, 0)
    if low >= 0.0:
        return _toward_blue(value, low, high)
    if high <= 0.0:
        return _from_red(value, low, high)
    if value < 0.0:
        return _from_red(value, low, 0.0)
    return _toward_blue(value, 0.0, high)


def draw_plane(plane: PlaneSlice, scale: Int) raises -> Framebuffer:
    """Return a picture of a plane on the red-blue map of its own range.

    The first row of the plane is drawn at the bottom, so the second free
    axis points up.

    Args:
        plane: The plane.
        scale: The side of the block of pixels for each point. 1 or more.

    Returns:
        The frame, `scale` times the columns wide and the rows high.

    Raises:
        Error: If the scale is less than 1 or the frame is too large.
    """
    var bounds = plane.bounds()
    return draw_plane_range(plane, scale, bounds[0], bounds[1])


def draw_plane_range(
    plane: PlaneSlice, scale: Int, low: Float64, high: Float64
) raises -> Framebuffer:
    """Return a picture of a plane on the red-blue map of a given range.

    Use one range for every frame of an animation, so that a color means
    the same value in each.

    Args:
        plane: The plane.
        scale: The side of the block of pixels for each point. 1 or more.
        low: The value drawn fully red, or white if it is not negative.
        high: The value drawn fully blue, or white if it is not positive.

    Returns:
        The frame, `scale` times the columns wide and the rows high.

    Raises:
        Error: If the scale is less than 1 or the frame is too large.
    """
    if scale < 1:
        raise Error("A plot scale must be 1 or more")
    var frame = Framebuffer(
        plane.columns * scale, plane.rows * scale, Color(255, 255, 255)
    )
    for row in range(plane.rows):  # pragma: no branch
        for column in range(plane.columns):  # pragma: no branch
            var color = red_blue(plane.at(column, row), low, high)
            var top = (plane.rows - 1 - row) * scale
            for dy in range(scale):  # pragma: no branch
                for dx in range(scale):  # pragma: no branch
                    frame.set_pixel(column * scale + dx, top + dy, color)
    return frame^
