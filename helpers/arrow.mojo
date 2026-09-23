# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arrow from a point along a direction, from three.js
`src/helpers/ArrowHelper.js`.

three.js builds the arrow as two children: a line for the shaft, one unit
up +y and scaled to `length - headLength`, and a cone for the head, a
`CylinderGeometry(0, 0.5, 1, 5, 1)` moved down half a unit, scaled to
`headWidth` by `headLength` and set on top at `length`. `setDirection`
turns +y onto the direction. The head is a solid cone there.

Here the arrow is one line geometry, so the head is the ten edges of that
same cone: the five sides of its base and the five edges from the base to
the tip. The points are three.js's points, turned by three.js's rotation,
and moved to the origin.
"""

from core.buffer_geometry import BufferGeometry
from helpers.segments import Segments
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import acos, cos, pi, sin
from units.si import Angle, Length, METER, RADIAN

# three.js's defaults: one unit long, yellow, and a head a fifth of the
# length, a fifth as wide as it is long.
comptime DEFAULT_ARROW_LENGTH = Length(1.0, METER)
comptime DEFAULT_ARROW_COLOR = Color(0xFF, 0xFF, 0x00)
comptime HEAD_LENGTH_RATIO = Float32(0.2)
comptime HEAD_WIDTH_RATIO = Float32(0.2)
# How many sides the cone has, three.js's `radialSegments`.
comptime HEAD_SIDES = 5
# The shortest shaft three.js draws, when the head is the whole arrow.
comptime SHORTEST_SHAFT = Float32(0.0001)
# How close to +y or -y a direction is taken to be exactly along it,
# three.js's threshold in `setDirection`.
comptime ALONG_Y = Float32(0.99999)


def arrow_turn(direction: Vector3) -> Quaternion:
    """Return the rotation that turns +y onto `direction`, as three.js's
    `ArrowHelper.setDirection` builds it.

    Args:
        direction: Which way the arrow points. Must be unit length.

    Returns:
        The identity near +y, a half turn about x near -y, and otherwise a
        turn about `(z, 0, -x)` by the angle between +y and `direction`.
    """
    if direction.y > ALONG_Y:
        return Quaternion.identity()
    if direction.y < -ALONG_Y:
        return Quaternion(1, 0, 0, 0)
    var axis = Vector3(direction.z, 0, -direction.x)
    axis.normalize()
    return Quaternion.from_axis_angle(axis, Angle(acos(direction.y), RADIAN))


def arrow_helper(
    direction: Vector3 = Vector3(0, 0, 1),
    origin: Vector3 = Vector3(0, 0, 0),
    length: Length = DEFAULT_ARROW_LENGTH,
    color: Color = DEFAULT_ARROW_COLOR,
    head_length: Optional[Length] = None,
    head_width: Optional[Length] = None,
) raises -> BufferGeometry:
    """Return an arrow from `origin` along `direction`, for a `Line` in
    `SEGMENTS` mode.

    Args:
        direction: Which way the arrow points. Any length but zero; it is
            made unit length, where three.js requires a unit vector. +z by
            default, as in three.js.
        origin: Where the arrow starts, in the frame of the node the
            `Line` is on.
        length: How long the arrow is, tip included. Must be positive.
        color: The color of the whole arrow, as authored in sRGB.
        head_length: How long the head is. A fifth of `length` when unset,
            as in three.js. Must be positive.
        head_width: How wide the head's base is. A fifth of `head_length`
            when unset. Must be positive.

    Returns:
        Twenty-two points, two per segment: the shaft, then the five sides
        of the head's base, then its five edges to the tip. A `color`
        attribute in linear light.

    Raises:
        Error: If `direction` has no length, or `length`, `head_length` or
            `head_width` is not positive.
    """
    if direction.length() == 0:
        raise Error("An arrow helper needs a direction with some length")
    var reach = length.to(METER)
    if reach <= 0:
        raise Error("An arrow helper needs a positive length")
    var head = reach * HEAD_LENGTH_RATIO
    if Bool(head_length):
        head = head_length.value().to(METER)
    var width = head * HEAD_WIDTH_RATIO
    if Bool(head_width):
        width = head_width.value().to(METER)
    if head <= 0 or width <= 0:
        raise Error("An arrow helper needs a head of positive size")
    var unit = direction
    unit.normalize()
    var turn = arrow_turn(unit)
    var paint = FloatColor(srgb=color)
    var segments = Segments()
    var shaft = max(SHORTEST_SHAFT, reach - head)
    segments.add(origin, origin + turn.rotate(Vector3(0, shaft, 0)), paint)
    # The cone's base, at `length - head_length` up the arrow, with a
    # radius of half the head's width: three.js's cylinder of radius one
    # half, scaled by the width.
    var base = List[Vector3]()
    for side in range(HEAD_SIDES):  # pragma: no branch
        var theta = Float32(side) / Float32(HEAD_SIDES) * 2 * pi
        var corner = Vector3(
            width / 2 * sin(theta), reach - head, width / 2 * cos(theta)
        )
        base.append(origin + turn.rotate(corner))
    var tip = origin + turn.rotate(Vector3(0, reach, 0))
    for side in range(HEAD_SIDES):  # pragma: no branch
        segments.add(base[side], base[(side + 1) % HEAD_SIDES], paint)
    for side in range(HEAD_SIDES):  # pragma: no branch
        segments.add(base[side], tip, paint)
    return segments.geometry()
