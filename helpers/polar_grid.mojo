# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A round grid on the ground, from three.js
`src/helpers/PolarGridHelper.js`.

Spokes from the origin out to `radius`, and rings around it, all in the
xz plane. The spokes and the rings alternate between two colors: the
first of each takes the second color, as three.js's `i & 1` test decides.
A single sector is no sector: three.js draws spokes only when there are
two or more, and so does this.

The colors are authored bytes and are decoded to linear light, as the
square grid's are. See `helpers.grid`.
"""

from core.buffer_geometry import BufferGeometry
from helpers.segments import Segments
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import cos, pi, sin
from units.si import Length, METER

# three.js's defaults.
comptime DEFAULT_POLAR_RADIUS = Length(10.0, METER)
comptime DEFAULT_POLAR_SECTORS = 16
comptime DEFAULT_POLAR_RINGS = 8
comptime DEFAULT_POLAR_DIVISIONS = 64
comptime DEFAULT_POLAR_COLOR1 = Color(0x44, 0x44, 0x44)
comptime DEFAULT_POLAR_COLOR2 = Color(0x88, 0x88, 0x88)


def _around(radius: Float32, step: Int, steps: Int) -> Vector3:
    """Return the point `step` of `steps` around a circle in the xz plane,
    starting on +z and turning toward +x, as three.js places them."""
    var angle = Float32(step) / Float32(steps) * 2 * pi
    return Vector3(sin(angle) * radius, 0, cos(angle) * radius)


def polar_grid_helper(
    radius: Length = DEFAULT_POLAR_RADIUS,
    sectors: Int = DEFAULT_POLAR_SECTORS,
    rings: Int = DEFAULT_POLAR_RINGS,
    divisions: Int = DEFAULT_POLAR_DIVISIONS,
    color1: Color = DEFAULT_POLAR_COLOR1,
    color2: Color = DEFAULT_POLAR_COLOR2,
) raises -> BufferGeometry:
    """Return a round grid in the xz plane, for a `Line` in `SEGMENTS` mode.

    Args:
        radius: How far the grid reaches from the origin. Must be positive.
        sectors: How many spokes. Zero or one draws none. Not negative.
        rings: How many rings, the outermost at `radius`. Not negative.
        divisions: How many segments make each ring. Not negative.
        color1: The color of the odd spokes and rings, as authored in sRGB.
        color2: The color of the even ones, the first included.

    Returns:
        The spokes first, then each ring from the outside in, two points
        per segment, with a `color` attribute in linear light.

    Raises:
        Error: If `radius` is not positive, or a count is negative.
    """
    var reach = radius.to(METER)
    if reach <= 0:
        raise Error("A polar grid helper needs a positive radius")
    if sectors < 0 or rings < 0 or divisions < 0:
        raise Error("A polar grid helper cannot have a negative count")
    var odd = FloatColor(srgb=color1)
    var even = FloatColor(srgb=color2)
    var segments = Segments()
    if sectors > 1:
        for sector in range(sectors):  # pragma: no branch
            var color = even
            if sector % 2 == 1:
                color = odd
            segments.add(
                Vector3(0, 0, 0), _around(reach, sector, sectors), color
            )
    for ring in range(rings):
        var color = even
        if ring % 2 == 1:
            color = odd
        var r = reach - reach / Float32(rings) * Float32(ring)
        for step in range(divisions):
            segments.add(
                _around(r, step, divisions),
                _around(r, step + 1, divisions),
                color,
            )
    return segments.geometry()
