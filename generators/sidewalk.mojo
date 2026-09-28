# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The raised sidewalk of a city block, from three.js
`examples/jsm/generators/city/SidewalkGenerator.js`.

Each block gets a concrete slab with rounded corners, rimmed by a granite
curb that stands a little proud of the walking surface and drops to the
road. The slab and the curb are extruded footprints stood up so that y is
up, and each is placed at every block. The rounded corners turn each
intersection instead of meeting it at a right angle.

The concrete and granite materials are not ported.
"""

from core.buffer_geometry import BufferGeometry
from generators.street_furniture import placed
from generators.utils import Instances, meters
from geometries.extrude import extrude
from math.matrix4 import Matrix4
from math.path import Path, Shape
from math.vector2 import Vector2
from std.math import pi
from units.si import Angle, Length, METER, RADIAN


def rounded_rect(
    width: Float64, depth: Float64, radius: Float64
) raises -> Shape:
    """Return a rectangle with rounded corners centered on the origin,
    three.js's `roundedRect`.

    Args:
        width: The size along x, in meters.
        depth: The size along y, in meters.
        radius: The corner radius, in meters. It is cut to half the
            shorter side.

    Returns:
        The outline, counter-clockwise, each corner a quadratic curve.

    Raises:
        Error: If the outline cannot be drawn: a side of no length.
    """
    var w = Float32(width / 2)
    var d = Float32(depth / 2)
    var r = Float32(min(radius, min(width / 2, depth / 2)))
    var path = Path(Vector2(-w + r, -d))
    _line(path, Vector2(w - r, -d))
    path.quadratic_to(Vector2(w, -d), Vector2(w, -d + r))
    _line(path, Vector2(w, d - r))
    path.quadratic_to(Vector2(w, d), Vector2(w - r, d))
    _line(path, Vector2(-w + r, d))
    path.quadratic_to(Vector2(-w, d), Vector2(-w, d - r))
    _line(path, Vector2(-w, -d + r))
    path.quadratic_to(Vector2(-w, -d), Vector2(-w + r, -d))
    return Shape(path^)


def _line(mut path: Path, end: Vector2) raises:
    """Draw a straight run, or nothing when it has no length. three.js
    draws the empty run, and `getPoints` then skips its repeated point, so
    the points are the same."""
    if end != path.current():
        path.line_to(end)


def extrude_up(shape: Shape, height: Float64) raises -> BufferGeometry:
    """Return an outline extruded up by a height, three.js's `extrudeUp`:
    extruded along +z with six segments a curve, then stood up.

    Args:
        shape: The footprint.
        height: How far up, in meters.

    Returns:
        The solid, without an index, its base at y equals zero.

    Raises:
        Error: If the footprint cannot be filled in.
    """
    var geometry = extrude(shape, Length(Float32(height), METER), 1, 6)
    geometry.rotate_x(Angle(Float32(-pi / 2), RADIAN))
    return geometry^


struct SidewalkInstances(Movable):
    """The two instanced parts of the sidewalk, three.js's `Sidewalk`
    group: the walking slab and the curb."""

    var slab: Instances
    var curb: Instances

    def __init__(out self, var slab: Instances, var curb: Instances):
        """Pair the slab and the curb.

        Args:
            slab: The walking slab.
            curb: The curb.
        """
        self.slab = slab^
        self.curb = curb^


@fieldwise_init
struct SidewalkGenerator(Copyable, Movable):
    """Generates the raised sidewalk for a city's blocks, three.js's
    `SidewalkGenerator`."""

    # The block footprint each slab covers.
    var width: Length
    var depth: Length
    # The height of the walking surface above the road.
    var height: Length
    # The corner radius.
    var radius: Length
    # The width of the curb's top.
    var curb_width: Length
    # How far the curb stands above the walking surface.
    var curb_lip: Length

    def __init__(out self):
        """Create three.js's default sidewalk."""
        self.width = Length(90, METER)
        self.depth = Length(60, METER)
        self.height = Length(0.5, METER)
        self.radius = Length(5, METER)
        self.curb_width = Length(0.13, METER)
        self.curb_lip = Length(0.01, METER)

    def slab_geometry(self) raises -> BufferGeometry:
        """Return the walking slab, three.js's `slabGeometry`: inset to sit
        inside the curb, overlapping it a little so the seam is buried.

        Returns:
            The slab, without an index.

        Raises:
            Error: If a size cannot be drawn.
        """
        var cw = meters(self.curb_width)
        var inner = max(0.5, meters(self.radius) - cw)
        return extrude_up(
            rounded_rect(
                meters(self.width) - 2 * cw + 0.06,
                meters(self.depth) - 2 * cw + 0.06,
                inner,
            ),
            meters(self.height),
        )

    def curb_geometry(self) raises -> BufferGeometry:
        """Return the curb, three.js's `curbGeometry`: the block outline
        with the slab's outline cut out, standing proud by the lip.

        Returns:
            The curb, without an index.

        Raises:
            Error: If a size cannot be drawn.
        """
        var cw = meters(self.curb_width)
        var inner = max(0.5, meters(self.radius) - cw)
        var shape = rounded_rect(
            meters(self.width), meters(self.depth), meters(self.radius)
        )
        var hole = rounded_rect(
            meters(self.width) - 2 * cw, meters(self.depth) - 2 * cw, inner
        )
        shape.add_hole(hole.outline.copy())
        return extrude_up(shape, meters(self.height) + meters(self.curb_lip))

    def build(self, placements: List[Matrix4]) raises -> SidewalkInstances:
        """Place a slab and a curb at every block, three.js's `build`.
        Neither casts a shadow; shadows fall on both.

        Args:
            placements: One matrix a block, at its center.

        Returns:
            The slab and the curb.

        Raises:
            Error: If a size cannot be drawn.
        """
        var slab = placed("", self.slab_geometry(), placements)
        var curb = placed("", self.curb_geometry(), placements)
        slab.cast_shadow = False
        curb.cast_shadow = False
        return SidewalkInstances(slab^, curb^)
