# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A square on a plane, from three.js `src/helpers/PlaneHelper.js`.

three.js draws a `Line` strip of eight points on the square from -1 to 1
in x and y: the outline and its two diagonals. It scales the square to
half of `size` each way, turns its +z onto the plane's normal with
`lookAt`, and moves it along that normal by minus the plane's constant,
which puts its center on the point of the plane nearest the origin.

Here the strip is written as its seven segments, and the points are
carried through that same transform, so the `Line` belongs on a node at
the origin. three.js also fills the square with a faint mesh. That fill
is not a line and is not built here.
"""

from core.buffer_geometry import BufferGeometry
from core.object3d import facing
from helpers.segments import Segments
from math.bounds import Plane
from math.matrix4 import scaling, translation
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from units.si import Length, METER

# three.js's defaults: one unit on a side, and yellow.
comptime DEFAULT_PLANE_SIZE = Length(1.0, METER)
comptime DEFAULT_PLANE_COLOR = Color(0xFF, 0xFF, 0x00)


def plane_helper(
    plane: Plane,
    size: Length = DEFAULT_PLANE_SIZE,
    color: Color = DEFAULT_PLANE_COLOR,
) raises -> BufferGeometry:
    """Return a square on `plane`, for a `Line` in `SEGMENTS` mode on a
    node at the origin.

    Args:
        plane: The plane to show.
        size: How long the square is on a side. Must be positive.
        color: The color of every line, as authored in sRGB.

    Returns:
        Fourteen points, two per segment, in three.js's strip order: the
        square's outline and its two diagonals. A `color` attribute in
        linear light.

    Raises:
        Error: If `size` is not positive.
    """
    var side = size.to(METER)
    if side <= 0:
        raise Error("A plane helper needs a positive size")
    # three.js's `translateZ(-constant)` along the turned z, which is the
    # normal: the plane's point nearest the origin.
    var center = plane.normal * -plane.constant
    var place = translation(center.x, center.y, center.z)
    place.multiply(
        facing(
            Vector3(0, 0, 0), plane.normal, Vector3(0, 1, 0), False
        ).to_matrix()
    )
    place.multiply(scaling(side / 2, side / 2, 1))
    var strip: List[Vector3] = [
        Vector3(1, -1, 0),
        Vector3(-1, 1, 0),
        Vector3(-1, -1, 0),
        Vector3(1, 1, 0),
        Vector3(-1, 1, 0),
        Vector3(-1, -1, 0),
        Vector3(1, -1, 0),
        Vector3(1, 1, 0),
    ]
    var segments = Segments()
    segments.add_strip(strip, place, FloatColor(srgb=color))
    return segments.geometry()
