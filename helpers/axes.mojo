# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The three axes of a frame, from three.js `src/helpers/AxesHelper.js`.

Three sticks from the origin: x red, y green, z blue, each fading toward
a paler tint at its far end so the direction reads. The colors are the
linear floats three.js writes straight into the attribute, not authored
bytes, so they are not decoded on the way in.

A helper is a geometry here and an object there. three.js's helpers are
`LineSegments` that own a geometry and a material; here the geometry is
built and the caller draws it with a `Line` in `SEGMENTS` mode and
`helper_material`, so a helper is stored, shared and placed exactly as
any other line is. See `objects.line`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from units.si import Length, METER

# three.js's default: one unit along each axis.
comptime DEFAULT_AXES_SIZE = Length(1.0, METER)


def axes_helper(size: Length = DEFAULT_AXES_SIZE) raises -> BufferGeometry:
    """Return three sticks along the axes, for a `Line` in `SEGMENTS` mode.

    Args:
        size: How far along each axis the stick reaches. Must be positive.

    Returns:
        Six points, two per axis, with a `color` attribute: red for x,
        green for y and blue for z, each paler at the far end, as
        three.js colors them.

    Raises:
        Error: If `size` is not positive.
    """
    var reach = size.to(METER)
    if reach <= 0:
        raise Error("An axes helper needs a positive size")
    var positions: List[Float32] = [
        0,
        0,
        0,
        reach,
        0,
        0,
        0,
        0,
        0,
        0,
        reach,
        0,
        0,
        0,
        0,
        0,
        0,
        reach,
    ]
    var colors: List[Float32] = [
        1,
        0,
        0,
        1,
        0.6,
        0,
        0,
        1,
        0,
        0.6,
        1,
        0,
        0,
        0,
        1,
        0,
        0.6,
        1,
    ]
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^
