# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A square grid on the ground, from three.js `src/helpers/GridHelper.js`.

A square of `size` on a side in the xz plane, centered on the origin and
cut into `divisions` cells each way. The two lines through the center are
drawn in one color and the rest in another, so the origin can be found.

three.js finds the center line by `i === divisions / 2`, a float
comparison that no integer `i` satisfies when the division count is odd.
An odd grid has no center line to color, and here it has none either:
the grid's lines straddle the origin rather than crossing it.

The colors are authored bytes, as three.js's `Color(0x444444)` is, and
are decoded to linear light on the way in; see `Why color is linear`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from render.framebuffer import Color, FloatColor
from units.si import Length, METER

# three.js's defaults: ten meters, ten cells, and two grays.
comptime DEFAULT_GRID_SIZE = Length(10.0, METER)
comptime DEFAULT_GRID_DIVISIONS = 10
comptime DEFAULT_CENTER_COLOR = Color(0x44, 0x44, 0x44)
comptime DEFAULT_GRID_COLOR = Color(0x88, 0x88, 0x88)


def _push_color(mut colors: List[Float32], color: FloatColor):
    """Append one linear color, three floats, to a color attribute."""
    colors.append(color.r)
    colors.append(color.g)
    colors.append(color.b)


def grid_helper(
    size: Length = DEFAULT_GRID_SIZE,
    divisions: Int = DEFAULT_GRID_DIVISIONS,
    center_color: Color = DEFAULT_CENTER_COLOR,
    grid_color: Color = DEFAULT_GRID_COLOR,
) raises -> BufferGeometry:
    """Return a grid in the xz plane, for a `Line` in `SEGMENTS` mode.

    Args:
        size: How long the square is on a side. Must be positive.
        divisions: How many cells across and how many deep. At least one.
        center_color: The color of the two lines through the origin, as
            authored in sRGB. three.js's `colorCenterLine`.
        grid_color: The color of every other line. three.js's `colorGrid`.

    Returns:
        `divisions + 1` lines each way, two points each, with a `color`
        attribute in linear light. The lines run along x first and then
        along z at each step, in the order three.js writes them.

    Raises:
        Error: If `size` is not positive or `divisions` is below one.
    """
    var side = size.to(METER)
    if side <= 0:
        raise Error("A grid helper needs a positive size")
    if divisions < 1:
        raise Error("A grid helper needs at least one division")
    var half = side / 2
    var step = side / Float32(divisions)
    var middle = FloatColor(srgb=center_color)
    var plain = FloatColor(srgb=grid_color)
    var positions = List[Float32]()
    var colors = List[Float32]()
    for index in range(divisions + 1):  # pragma: no branch
        var k = -half + step * Float32(index)
        # Along x at this depth, then along z at this offset.
        for number in [
            -half,
            0,
            k,
            half,
            0,
            k,
            k,
            0,
            -half,
            k,
            0,
            half,
        ]:  # pragma: no branch
            positions.append(number)
        # A center line exists only when the division count is even, as
        # three.js's float comparison decides; see the module docstring.
        var color = plain
        if divisions % 2 == 0 and index == divisions // 2:
            color = middle
        for _ in range(4):  # pragma: no branch
            _push_color(colors, color)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^
