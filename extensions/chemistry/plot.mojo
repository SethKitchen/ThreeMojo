# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draw charts of process chemistry on a frame.

An `Axes` maps a box of data onto a box of pixels, with y up. It draws its
frame with ticks and their numbers, and it draws lines, bands and the
cells of a `LabelMap` in data units. The chemistry examples draw their
Ellingham diagrams, predominance maps and operating windows with it.

`nice_ticks` picks round tick values: steps of 1, 2 or 5 times a power of
ten. `tick_text` writes a tick value with the decimals its step needs.

The caller keeps the data inside the box: an `Axes` does not clip.
"""

from std.math import ceil, floor, isfinite, log10
from extensions.chemistry.maps import LabelMap
from extensions.visual.overlay import (
    CENTER,
    LEFT,
    Overlay,
    RIGHT,
    fill_rect,
    stroke_line,
)
from render.framebuffer import Color, Framebuffer

# The most ticks along one axis.
comptime MAX_TICKS = 50


def nice_ticks(low: Float64, high: Float64, count: Int) raises -> List[Float64]:
    """Return round tick values from low to high.

    Args:
        low: The lowest value of the axis.
        high: The highest, above the lowest.
        count: About how many ticks to give, from 2 to MAX_TICKS.

    Returns:
        The multiples of the step that lie in the range. The step is 1, 2
        or 5 times a power of ten, the smallest that gives `count` ticks
        or fewer.

    Raises:
        Error: If the range is not finite and ascending, or the count is
            not from 2 to MAX_TICKS.
    """
    if not (isfinite(low) and isfinite(high) and high > low):
        raise Error("A tick range must be finite and ascend")
    if count < 2 or count > MAX_TICKS:
        raise Error("Ask for 2 to 50 ticks")
    var step = _step(low, high, count)
    var out = List[Float64]()
    var first = ceil(low / step - 1e-9)
    var last = floor(high / step + 1e-9)
    var i = first
    while i <= last:
        out.append(i * step)
        i += 1
    return out^


def _step(low: Float64, high: Float64, count: Int) -> Float64:
    """Return the tick step for a range and a tick count."""
    var raw = (high - low) / Float64(count - 1)
    var power = Float64(10) ** floor(log10(raw))
    for factor in [1.0, 2.0, 5.0]:
        if factor * power >= raw * (1 - 1e-9):
            return factor * power
    return 10 * power


def tick_text(value: Float64, step: Float64) -> String:
    """Return a tick value with the decimals its step needs.

    Args:
        value: The value.
        step: The step between ticks, more than zero.

    Returns:
        The value, rounded to the step's last decimal, such as "0.25" for
        a step of 0.05 and "1500" for a step of 500.
    """
    var decimals = 0
    var unit = Float64(1)
    while decimals < 12 and step * unit < 1 - 1e-9:
        decimals += 1
        unit *= 10
    var scaled = Int(round(abs(value) * unit))
    var sign = String("-") if value < 0 and scaled != 0 else String()
    var digits = String(scaled)
    if decimals == 0:
        return sign + digits
    while digits.byte_length() <= decimals:
        digits = "0" + digits
    var cut = digits.byte_length() - decimals
    return String(sign, digits[byte=:cut], ".", digits[byte=cut:])


struct Axes(Copyable, Movable):
    """A box of data on a box of pixels, with y up."""

    var left: Float64
    var top: Float64
    var right: Float64
    var bottom: Float64
    var x_low: Float64
    var x_high: Float64
    var y_low: Float64
    var y_high: Float64

    def __init__(
        out self,
        left: Float64,
        top: Float64,
        right: Float64,
        bottom: Float64,
        x_low: Float64,
        x_high: Float64,
        y_low: Float64,
        y_high: Float64,
    ) raises:
        """Make axes from a pixel box and a data box.

        Args:
            left: The box's left edge, in pixels.
            top: Its top edge, in pixels, with y down.
            right: Its right edge, right of the left.
            bottom: Its bottom edge, below the top.
            x_low: The data at the left edge.
            x_high: The data at the right edge, more than at the left.
            y_low: The data at the bottom edge.
            y_high: The data at the top edge, more than at the bottom.

        Raises:
            Error: If a value is not finite or a box does not ascend.
        """
        var values: List[Float64] = [
            left,
            top,
            right,
            bottom,
            x_low,
            x_high,
            y_low,
            y_high,
        ]
        for value in values:  # pragma: no branch
            if not isfinite(value):
                raise Error("An axes value must be finite")
        if not (right > left and bottom > top):
            raise Error("An axes box must have a size in pixels")
        if not (x_high > x_low and y_high > y_low):
            raise Error("An axes range must ascend")
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.x_low = x_low
        self.x_high = x_high
        self.y_low = y_low
        self.y_high = y_high

    def x(self, value: Float64) -> Float64:
        """Return the pixel column of a data value.

        Args:
            value: A value on the x axis.

        Returns:
            The column, linear in the value.
        """
        var f = (value - self.x_low) / (self.x_high - self.x_low)
        return self.left + f * (self.right - self.left)

    def y(self, value: Float64) -> Float64:
        """Return the pixel row of a data value.

        Args:
            value: A value on the y axis.

        Returns:
            The row, linear in the value, smaller for a higher value.
        """
        var f = (value - self.y_low) / (self.y_high - self.y_low)
        return self.bottom - f * (self.bottom - self.top)

    def frame(
        self,
        mut frame: Framebuffer,
        font: Overlay,
        x_title: String,
        y_title: String,
        size: Float64,
        color: Color,
        ticks: Int = 6,
        y_numbers: Bool = True,
    ) raises:
        """Draw the box, its ticks, their numbers and the axis titles.

        The x title goes under the numbers. The y title goes above the box
        at its left, since the text does not turn.

        Args:
            frame: The frame.
            font: The font.
            x_title: The x axis's title.
            y_title: The y axis's title.
            size: The text's em size, in pixels.
            color: The color of the lines and the text.
            ticks: About how many ticks each axis has.
            y_numbers: Whether the y axis has ticks and numbers. A chart of
                labeled rows has none.

        Raises:
            Error: If the tick count is not valid or the font lacks a
                glyph.
        """
        var line = max(1.0, size / 10)
        var tick = size / 2
        stroke_line(
            frame, self.left, self.bottom, self.right, self.bottom, line, color
        )
        stroke_line(
            frame, self.left, self.top, self.right, self.top, line, color
        )
        stroke_line(
            frame, self.left, self.top, self.left, self.bottom, line, color
        )
        stroke_line(
            frame, self.right, self.top, self.right, self.bottom, line, color
        )
        var x_step = _step(self.x_low, self.x_high, ticks)
        for value in nice_ticks(self.x_low, self.x_high, ticks):
            var px = self.x(value)
            stroke_line(
                frame, px, self.bottom, px, self.bottom - tick, line, color
            )
            font.text(
                frame,
                tick_text(value, x_step),
                px,
                self.bottom + size * 1.2,
                size,
                color,
                CENTER,
            )
        var y_step = _step(self.y_low, self.y_high, ticks)
        var y_ticks = List[Float64]()
        if y_numbers:
            y_ticks = nice_ticks(self.y_low, self.y_high, ticks)
        for value in y_ticks:
            var py = self.y(value)
            stroke_line(frame, self.left, py, self.left + tick, py, line, color)
            font.text(
                frame,
                tick_text(value, y_step),
                self.left - size * 0.4,
                py + size * 0.35,
                size,
                color,
                RIGHT,
            )
        font.text(
            frame,
            x_title,
            (self.left + self.right) / 2,
            self.bottom + size * 2.6,
            size,
            color,
            CENTER,
        )
        font.text(
            frame, y_title, self.left, self.top - size * 0.6, size, color, LEFT
        )

    def line(
        self,
        mut frame: Framebuffer,
        xs: List[Float64],
        ys: List[Float64],
        width: Float64,
        color: Color,
    ) raises:
        """Draw a line through points in data units.

        Args:
            frame: The frame.
            xs: The x values.
            ys: The y values, one per x value.
            width: The line's width, in pixels.
            color: The color.

        Raises:
            Error: If the lists differ in length or a value is not finite.
        """
        if len(xs) != len(ys):
            raise Error("A line needs one y value per x value")
        for i in range(1, len(xs)):
            stroke_line(
                frame,
                self.x(xs[i - 1]),
                self.y(ys[i - 1]),
                self.x(xs[i]),
                self.y(ys[i]),
                width,
                color,
            )

    def band(
        self,
        mut frame: Framebuffer,
        x_low: Float64,
        x_high: Float64,
        y_low: Float64,
        y_high: Float64,
        color: Color,
        opacity: Float64 = 1.0,
    ) raises:
        """Fill a box in data units.

        Args:
            frame: The frame.
            x_low: The box's lowest x value.
            x_high: Its highest x value.
            y_low: Its lowest y value.
            y_high: Its highest y value.
            color: The color.
            opacity: From zero to one.

        Raises:
            Error: If a value is not finite.
        """
        fill_rect(
            frame,
            self.x(x_low),
            self.y(y_high),
            self.x(x_high),
            self.y(y_low),
            color,
            opacity,
        )

    def cells(
        self,
        mut frame: Framebuffer,
        map: LabelMap,
        colors: List[Color],
        opacity: Float64 = 1.0,
    ) raises:
        """Fill each node of a label map with the color of its label.

        A node's cell reaches halfway to its neighbors, and the cells at
        the edges stop at the map's range. A run of nodes with one label
        in a row is one box. The boxes' edges fall on whole pixels, so
        boxes that touch do not blend twice where they meet.

        Args:
            frame: The frame.
            map: The map, in the axes' data units.
            colors: One color for each of the map's names.
            opacity: From zero to one.

        Raises:
            Error: If a label has no color.
        """
        # The pixel edges between columns and between rows, outer edges
        # included.
        var xs = List[Float64]()
        for k in range(map.columns + 1):  # pragma: no branch
            var f = (Float64(k) - 0.5) / Float64(map.columns - 1)
            f = min(1.0, max(0.0, f))
            xs.append(round(self.x(map.x_low + f * (map.x_high - map.x_low))))
        var ys = List[Float64]()
        for k in range(map.rows + 1):  # pragma: no branch
            var f = (Float64(k) - 0.5) / Float64(map.rows - 1)
            f = min(1.0, max(0.0, f))
            ys.append(round(self.y(map.y_low + f * (map.y_high - map.y_low))))
        for row in range(map.rows):  # pragma: no branch
            var start = 0
            # A map has two columns at least, so each row has a run.
            while start < map.columns:
                var label = map.label(start, row)
                if label < 0 or label >= len(colors):
                    raise Error("A map label has no color")
                var end = start + 1
                while end < map.columns and map.label(end, row) == label:
                    end += 1
                fill_rect(
                    frame,
                    xs[start],
                    ys[row + 1],
                    xs[end],
                    ys[row],
                    colors[label],
                    opacity,
                )
                start = end
