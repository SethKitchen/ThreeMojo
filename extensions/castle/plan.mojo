# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The plan of a moated castle: towers, wings, a gate, a quay wall, a moat
and a bridge.

Points are in a flat plan frame in meters, x east and y north of an origin
that the plan names. Levels are elevations above a datum, in meters. Every
length is a `Length64` and every angle an `Angle64`, and every part carries a
`Provenance` that says how its dimensions were found.

The parts are the solids an engineer counts:

- A `Tower` is a round tower with a wall to a height and a roof over it.
- A `Wing` is a band of constant width along an axis, with a gable roof
  whose ridge follows the axis. Its outline is the axis offset to both
  sides, with mitered corners.
- A `Gate` is a rectangular block with a flat top.
- A `QuayWall` is a wall that holds the island's earth at the edge of the
  moat, from the bed to a top level.
- A `Moat` is the water: an outline, a level and a depth.
- A `Bridge` is a run of semicircular brick arches on piers.

A `CastlePlan` holds them with the outline that a survey gave for the
building. `footprint_overlap` says how well the solids reproduce that
outline, as the area they share over the area they cover together.
"""

from std.math import cos, isfinite, sin, sqrt
from extensions.castle.kinds import CONE, FLAT, Provenance, RoofKind
from units.si import Angle64, Area64, Length64

# The shortest segment of an axis that is not a point, in meters.
comptime _TINY = 1e-9
# The least value of 1 + cos(turn) for a mitered corner. Below it the miter
# is longer than about ten half-widths.
comptime _SHARPEST = 0.1


@fieldwise_init
struct Point(ImplicitlyCopyable):
    """A point of the plan: meters east and north of its origin."""

    var x: Length64
    var y: Length64


def point(east: Float64, north: Float64) -> Point:
    """Return a point from meters east and north of the plan's origin.

    Args:
        east: The distance east, in meters.
        north: The distance north, in meters.

    Returns:
        The point.
    """
    return Point(Length64(east), Length64(north))


def points(meters: List[Float64]) raises -> List[Point]:
    """Return points from a flat list of east and north pairs, in meters.

    Args:
        meters: East, north, east, north and so on.

    Returns:
        The points.

    Raises:
        Error: If the list has an odd length, or a value is not finite.
    """
    if len(meters) % 2 != 0:
        raise Error("A list of points needs an east and a north each")
    var out = List[Point](capacity=len(meters) // 2)
    for at in range(len(meters) // 2):
        var east = meters[2 * at]
        var north = meters[2 * at + 1]
        if not (isfinite(east) and isfinite(north)):
            raise Error("A point must be finite")
        out.append(point(east, north))
    return out^


def polygon_area(outline: List[Point]) raises -> Area64:
    """Return the area of a polygon.

    Args:
        outline: The corners, in either winding.

    Returns:
        The area, whichever way the corners run.

    Raises:
        Error: If the outline has fewer than three points.
    """
    if len(outline) < 3:
        raise Error("A polygon needs at least three points")
    var twice = Float64(0)
    var count = len(outline)
    for at in range(count):
        var p = outline[at]
        var q = outline[(at + 1) % count]
        twice += p.x.value * q.y.value - q.x.value * p.y.value
    return Area64(abs(twice) / 2)


def polygon_contains(outline: List[Point], at: Point) -> Bool:
    """Return whether a point lies inside a polygon, by the even-odd rule.

    Args:
        outline: The corners, in either winding.
        at: The point.

    Returns:
        True if the point is inside. A polygon of fewer than three points
        holds nothing.
    """
    var count = len(outline)
    if count < 3:
        return False
    var inside = False
    var last = count - 1
    for first in range(count):
        var a = outline[first]
        var b = outline[last]
        if (a.y.value > at.y.value) != (b.y.value > at.y.value):
            var across = (b.x.value - a.x.value) * (at.y.value - a.y.value) / (
                b.y.value - a.y.value
            ) + a.x.value
            if at.x.value < across:
                inside = not inside
        last = first
    return inside


def check_polygon(outline: List[Point]) raises:
    """Refuse an outline that is not a polygon with an area.

    Args:
        outline: The corners.

    Raises:
        Error: If there are fewer than three points, a coordinate is not
            finite, or the area is zero.
    """
    if len(outline) < 3:
        raise Error("A polygon needs at least three points")
    for corner in outline:
        if not (isfinite(corner.x.value) and isfinite(corner.y.value)):
            raise Error("A point must be finite")
    if polygon_area(outline).value == 0:
        raise Error("A polygon must have an area")


def convex_hull(outline: List[Point]) raises -> List[Point]:
    """Return the convex hull of a set of points.

    Args:
        outline: The points, in any order. Three at least, not all on a line.

    Returns:
        The corners of the hull, counterclockwise, starting from the
        lowest point to the west.

    Raises:
        Error: If there are fewer than three points, or they all lie on one
            line.
    """
    var count = len(outline)
    if count < 3:
        raise Error("A hull needs at least three points")
    # An index list sorted by x and then by y, by insertion.
    var order = List[Int]()
    for at in range(count):
        var place = len(order)
        while place > 0:
            var before = outline[order[place - 1]]
            var here = outline[at]
            var later = before.x.value > here.x.value or (
                before.x.value == here.x.value and before.y.value > here.y.value
            )
            if not later:
                break
            place -= 1
        order.insert(place, at)
    var chain = List[Int]()
    # The lower hull, then the upper hull.
    for pass_ in range(2):
        var start = len(chain)
        for step in range(count):
            var at = order[step] if pass_ == 0 else order[count - 1 - step]
            while len(chain) >= start + 2 and (
                _turn(
                    outline[chain[len(chain) - 2]],
                    outline[chain[len(chain) - 1]],
                    outline[at],
                )
                <= 0
            ):
                _ = chain.pop()
            chain.append(at)
        # The last point of a pass is the first of the next.
        _ = chain.pop()
    if len(chain) < 3:
        raise Error("A hull needs points that do not lie on one line")
    var hull = List[Point]()
    for at in chain:
        hull.append(outline[at])
    return hull^


def _turn(a: Point, b: Point, c: Point) -> Float64:
    """Return twice the signed area of a, b, c: positive for a left turn."""
    return (b.x.value - a.x.value) * (c.y.value - a.y.value) - (
        b.y.value - a.y.value
    ) * (c.x.value - a.x.value)


def distance_to_outline(outline: List[Point], at: Point) raises -> Length64:
    """Return how far a point is from the edges of a polygon.

    Args:
        outline: The corners; the edge from the last back to the first is
            included.
        at: The point.

    Returns:
        The distance to the nearest edge, inside or outside the polygon.

    Raises:
        Error: If the outline has fewer than three points.
    """
    var count = len(outline)
    if count < 3:
        raise Error("A polygon needs at least three points")
    var nearest = Float64(1.0e30)
    for first in range(count):
        var a = outline[first]
        var b = outline[(first + 1) % count]
        var dx = b.x.value - a.x.value
        var dy = b.y.value - a.y.value
        var length2 = dx * dx + dy * dy
        var along = Float64(0)
        if length2 > 0:
            along = (
                (at.x.value - a.x.value) * dx + (at.y.value - a.y.value) * dy
            ) / length2
            along = max(Float64(0), min(Float64(1), along))
        var ex = a.x.value + along * dx - at.x.value
        var ey = a.y.value + along * dy - at.y.value
        nearest = min(nearest, ex * ex + ey * ey)
    return Length64(sqrt(nearest))


def offset_outline(axis: List[Point], width: Length64) raises -> List[Point]:
    """Return the outline of a band of constant width along an axis.

    The corners are mitered: at a bend, the two edges meet where the offset
    lines cross. The outline runs along the left side of the axis and back
    along the right side.

    Args:
        axis: The points of the axis, two at least.
        width: The width of the band.

    Returns:
        The outline, with twice as many corners as the axis has points.

    Raises:
        Error: If the axis has fewer than two points, a coordinate is not
            finite, the width is not positive and finite, a segment has no
            length, or a bend is too sharp to miter.
    """
    var count = len(axis)
    if count < 2:
        raise Error("An axis needs at least two points")
    if not (isfinite(width.value) and width.value > 0):
        raise Error("A band's width must be positive and finite")
    var half = width.value / 2
    # The unit normal of each segment, to the left of its direction.
    var nx = List[Float64]()
    var ny = List[Float64]()
    for at in range(count - 1):
        var p = axis[at]
        var q = axis[at + 1]
        if not (
            isfinite(p.x.value)
            and isfinite(p.y.value)
            and isfinite(q.x.value)
            and isfinite(q.y.value)
        ):
            raise Error("A point must be finite")
        var dx = q.x.value - p.x.value
        var dy = q.y.value - p.y.value
        var length = sqrt(dx * dx + dy * dy)
        if length < _TINY:
            raise Error("A segment of an axis must have a length")
        nx.append(-dy / length)
        ny.append(dx / length)
    var left = List[Point]()
    var right = List[Point]()
    for at in range(count):
        var ox: Float64
        var oy: Float64
        if at == 0:
            ox = nx[0] * half
            oy = ny[0] * half
        elif at == count - 1:
            ox = nx[count - 2] * half
            oy = ny[count - 2] * half
        else:
            var turn = 1.0 + nx[at - 1] * nx[at] + ny[at - 1] * ny[at]
            if turn < _SHARPEST:
                raise Error("A bend of an axis is too sharp to miter")
            ox = (nx[at - 1] + nx[at]) / turn * half
            oy = (ny[at - 1] + ny[at]) / turn * half
        var base = axis[at]
        left.append(point(base.x.value + ox, base.y.value + oy))
        right.append(point(base.x.value - ox, base.y.value - oy))
    var outline = left^
    for at in range(count):
        outline.append(right[count - 1 - at])
    return outline^


@fieldwise_init
struct Tower(Copyable, Movable):
    """A round tower: a wall to a height, and a roof over it."""

    # What the plan calls it.
    var name: String
    # The center of the tower.
    var center: Point
    # The outer radius of the wall.
    var radius: Length64
    # The elevation of the ground at its foot.
    var base: Length64
    # The height of the wall above the base.
    var wall_height: Length64
    # A cone, or a flat top behind a parapet.
    var roof: RoofKind
    # The height of the cone, or of the parapet over the wall.
    var roof_height: Length64
    # How these dimensions were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a tower that cannot stand.

        Raises:
            Error: If the center or a size is not finite, the radius or the
                wall is not positive, the roof is not a cone or a flat top,
                a cone has no height, the parapet height is negative, or the
                provenance is not valid.
        """
        if not (
            isfinite(self.center.x.value) and isfinite(self.center.y.value)
        ):
            raise Error("A tower's center must be finite")
        if not (isfinite(self.radius.value) and self.radius.value > 0):
            raise Error("A tower's radius must be positive and finite")
        if not isfinite(self.base.value):
            raise Error("A tower's base must be finite")
        if not (
            isfinite(self.wall_height.value) and self.wall_height.value > 0
        ):
            raise Error("A tower's wall must be positive and finite")
        if not (self.roof == CONE or self.roof == FLAT):
            raise Error("A tower's roof must be a cone or a flat top")
        if not (
            isfinite(self.roof_height.value) and self.roof_height.value >= 0
        ):
            raise Error("A tower's roof height must be zero or more")
        if self.roof == CONE and self.roof_height.value == 0:
            raise Error("A cone roof must have a height")
        if not self.provenance.is_valid():
            raise Error("A tower's provenance must be one of the four")

    def top(self) -> Length64:
        """Return the elevation of the highest point of the tower.

        Returns:
            The base, the wall and the roof added.
        """
        return self.base + self.wall_height + self.roof_height

    def contains(self, at: Point) -> Bool:
        """Return whether a point lies within the tower's wall.

        Args:
            at: The point.

        Returns:
            True if it is no farther than the radius from the center.
        """
        var dx = at.x.value - self.center.x.value
        var dy = at.y.value - self.center.y.value
        return dx * dx + dy * dy <= self.radius.value * self.radius.value


@fieldwise_init
struct Wing(Copyable, Movable):
    """A band of constant width with a gable roof along its axis."""

    # What the plan calls it.
    var name: String
    # The axis, two points at least.
    var axis: List[Point]
    # The width between the outer faces of the walls.
    var width: Length64
    # The elevation of the ground at its foot.
    var base: Length64
    # The height of the eaves above the base.
    var eave_height: Length64
    # The height of the ridge above the base.
    var ridge_height: Length64
    # How these dimensions were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a wing that cannot stand.

        Raises:
            Error: If the axis or the width is refused by `offset_outline`,
                the base is not finite, the eaves are not positive, the
                ridge is not above the eaves, or the provenance is not
                valid.
        """
        _ = offset_outline(self.axis, self.width)
        if not isfinite(self.base.value):
            raise Error("A wing's base must be finite")
        if not (
            isfinite(self.eave_height.value) and self.eave_height.value > 0
        ):
            raise Error("A wing's eaves must be positive and finite")
        if not (
            isfinite(self.ridge_height.value)
            and self.ridge_height.value > self.eave_height.value
        ):
            raise Error("A wing's ridge must be above its eaves")
        if not self.provenance.is_valid():
            raise Error("A wing's provenance must be one of the four")

    def outline(self) raises -> List[Point]:
        """Return the outline of the wing.

        Returns:
            The corners of the walls, as `offset_outline` gives them.

        Raises:
            Error: If the axis or the width is refused.
        """
        return offset_outline(self.axis, self.width)

    def roof_rise(self) -> Length64:
        """Return how far the ridge stands above the eaves.

        Returns:
            The ridge height less the eave height.
        """
        return self.ridge_height - self.eave_height


@fieldwise_init
struct Gate(Copyable, Movable):
    """A rectangular block with a flat top behind a parapet."""

    # What the plan calls it.
    var name: String
    # The center of the block.
    var center: Point
    # The length, along the heading.
    var length: Length64
    # The width, across the heading.
    var width: Length64
    # The direction of the length, counterclockwise from east.
    var heading: Angle64
    # The elevation of the ground at its foot.
    var base: Length64
    # The height of the walls above the base.
    var height: Length64
    # The height of the parapet over the walls.
    var parapet: Length64
    # How these dimensions were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a gate that cannot stand.

        Raises:
            Error: If the center, a size or the heading is not finite, the
                length, the width or the height is not positive, the
                parapet is negative, or the provenance is not valid.
        """
        if not (
            isfinite(self.center.x.value) and isfinite(self.center.y.value)
        ):
            raise Error("A gate's center must be finite")
        if not (isfinite(self.length.value) and self.length.value > 0):
            raise Error("A gate's length must be positive and finite")
        if not (isfinite(self.width.value) and self.width.value > 0):
            raise Error("A gate's width must be positive and finite")
        if not isfinite(self.heading.value):
            raise Error("A gate's heading must be finite")
        if not isfinite(self.base.value):
            raise Error("A gate's base must be finite")
        if not (isfinite(self.height.value) and self.height.value > 0):
            raise Error("A gate's height must be positive and finite")
        if not (isfinite(self.parapet.value) and self.parapet.value >= 0):
            raise Error("A gate's parapet must be zero or more")
        if not self.provenance.is_valid():
            raise Error("A gate's provenance must be one of the four")

    def outline(self) -> List[Point]:
        """Return the corners of the block, counterclockwise.

        Returns:
            The four corners.
        """
        var ux = cos(self.heading.value)
        var uy = sin(self.heading.value)
        var vx = -uy
        var vy = ux
        var half_length = self.length.value / 2
        var half_width = self.width.value / 2
        var cx = self.center.x.value
        var cy = self.center.y.value
        var corners = List[Point]()
        corners.append(
            point(
                cx - ux * half_length - vx * half_width,
                cy - uy * half_length - vy * half_width,
            )
        )
        corners.append(
            point(
                cx + ux * half_length - vx * half_width,
                cy + uy * half_length - vy * half_width,
            )
        )
        corners.append(
            point(
                cx + ux * half_length + vx * half_width,
                cy + uy * half_length + vy * half_width,
            )
        )
        corners.append(
            point(
                cx - ux * half_length + vx * half_width,
                cy - uy * half_length + vy * half_width,
            )
        )
        return corners^


@fieldwise_init
struct QuayWall(Copyable, Movable):
    """The wall that holds the island's earth at the edge of the moat."""

    # What the plan calls it.
    var name: String
    # The axis along the face of the wall.
    var axis: List[Point]
    # The thickness of the wall.
    var thickness: Length64
    # The elevation of the foot, on the bed of the moat.
    var foot: Length64
    # The elevation of the top.
    var top: Length64
    # How these dimensions were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a wall that cannot stand.

        Raises:
            Error: If the axis or the thickness is refused by
                `offset_outline`, the foot or the top is not finite, the top
                is not above the foot, or the provenance is not valid.
        """
        _ = offset_outline(self.axis, self.thickness)
        if not (isfinite(self.foot.value) and isfinite(self.top.value)):
            raise Error("A wall's foot and top must be finite")
        if not self.top.value > self.foot.value:
            raise Error("A wall's top must be above its foot")
        if not self.provenance.is_valid():
            raise Error("A wall's provenance must be one of the four")

    def height(self) -> Length64:
        """Return the height of the wall.

        Returns:
            The top less the foot.
        """
        return self.top - self.foot


@fieldwise_init
struct Moat(Copyable, Movable):
    """The water around the island."""

    # What the plan calls it.
    var name: String
    # The outline of the water, a polygon.
    var outline: List[Point]
    # The elevation of the water's surface.
    var water_level: Length64
    # The depth of the water.
    var depth: Length64
    # How these dimensions were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a moat that cannot hold water.

        Raises:
            Error: If the outline is not a polygon, the level is not
                finite, the depth is not positive and finite, or the
                provenance is not valid.
        """
        check_polygon(self.outline)
        if not isfinite(self.water_level.value):
            raise Error("A moat's water level must be finite")
        if not (isfinite(self.depth.value) and self.depth.value > 0):
            raise Error("A moat's depth must be positive and finite")
        if not self.provenance.is_valid():
            raise Error("A moat's provenance must be one of the four")

    def area(self) raises -> Area64:
        """Return the area of the water's surface.

        Returns:
            The area of the outline.

        Raises:
            Error: If the outline has fewer than three points.
        """
        return polygon_area(self.outline)

    def bed(self) -> Length64:
        """Return the elevation of the bed.

        Returns:
            The water level less the depth.
        """
        return self.water_level - self.depth


@fieldwise_init
struct Bridge(Copyable, Movable):
    """A run of semicircular brick arches on piers."""

    # What the plan calls it.
    var name: String
    # The center of the first pier, at the gate.
    var start: Point
    # The direction of the bridge, counterclockwise from east.
    var heading: Angle64
    # How many arches there are.
    var spans: Int
    # The distance between the centers of two piers.
    var pitch: Length64
    # The width between the faces of the spandrel walls.
    var width: Length64
    # The thickness of a pier along the bridge.
    var pier: Length64
    # The elevation of the deck.
    var deck: Length64
    # The thickness of the arch ring.
    var ring: Length64
    # How these dimensions were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a bridge that cannot span.

        Raises:
            Error: If the start or the heading is not finite, there are no
                spans, a size is not positive and finite, the pier fills the
                pitch, the deck is not finite, the ring is thicker than half
                the clear span, or the provenance is not valid.
        """
        if not (isfinite(self.start.x.value) and isfinite(self.start.y.value)):
            raise Error("A bridge's start must be finite")
        if not isfinite(self.heading.value):
            raise Error("A bridge's heading must be finite")
        if self.spans < 1:
            raise Error("A bridge needs at least one span")
        if not (isfinite(self.pitch.value) and self.pitch.value > 0):
            raise Error("A bridge's pitch must be positive and finite")
        if not (isfinite(self.width.value) and self.width.value > 0):
            raise Error("A bridge's width must be positive and finite")
        if not (isfinite(self.pier.value) and self.pier.value > 0):
            raise Error("A bridge's pier must be positive and finite")
        if not self.pier.value < self.pitch.value:
            raise Error("A bridge's pier must be thinner than its pitch")
        if not isfinite(self.deck.value):
            raise Error("A bridge's deck must be finite")
        if not (isfinite(self.ring.value) and self.ring.value > 0):
            raise Error("A bridge's ring must be positive and finite")
        if not self.ring.value < self.clear_span().value / 2:
            raise Error("A bridge's ring must be thinner than half its span")
        if not self.provenance.is_valid():
            raise Error("A bridge's provenance must be one of the four")

    def clear_span(self) -> Length64:
        """Return the clear span of an arch, between two piers.

        Returns:
            The pitch less the pier.
        """
        return self.pitch - self.pier

    def length(self) -> Length64:
        """Return the length of the bridge between the first and last pier.

        Returns:
            The spans times the pitch.
        """
        return self.pitch.scaled(Float64(self.spans))

    def rise(self) -> Length64:
        """Return the rise of an arch: a semicircle has half its span.

        Returns:
            Half the clear span.
        """
        return self.clear_span().scaled(0.5)


@fieldwise_init
struct CastlePlan(Copyable, Movable):
    """A castle: its parts, and the outline a survey gave for the building."""

    # The name of the castle.
    var name: String
    # The elevation of the island's ground, in the courtyard.
    var island_level: Length64
    # The elevation of the ground outside the moat.
    var ground_level: Length64
    # The outline of the building, from a survey.
    var surveyed_footprint: List[Point]
    # The round towers.
    var towers: List[Tower]
    # The wings.
    var wings: List[Wing]
    # The gate.
    var gate: Gate
    # The wall of the quay.
    var quay: QuayWall
    # The moat.
    var moat: Moat
    # The bridge.
    var bridge: Bridge

    def check(self) raises:
        """Refuse a plan that is not consistent.

        Raises:
            Error: If a part is refused, the levels are not finite, the
                island is not above the water, the surveyed footprint is
                not a polygon, there are no towers or wings, or the
                bridge's deck is below the water.
        """
        if not (
            isfinite(self.island_level.value)
            and isfinite(self.ground_level.value)
        ):
            raise Error("The levels of a plan must be finite")
        check_polygon(self.surveyed_footprint)
        if len(self.towers) == 0:
            raise Error("A castle needs a tower")
        if len(self.wings) == 0:
            raise Error("A castle needs a wing")
        for tower in self.towers:
            tower.check()
        for wing in self.wings:
            wing.check()
        self.gate.check()
        self.quay.check()
        self.moat.check()
        self.bridge.check()
        if not self.island_level.value > self.moat.water_level.value:
            raise Error("The island must stand above the water")
        if not self.bridge.deck.value > self.moat.water_level.value:
            raise Error("The bridge's deck must stand above the water")

    def footprint_area(self) raises -> Area64:
        """Return the area of the surveyed outline of the building.

        Returns:
            The area of the polygon.

        Raises:
            Error: If the outline has fewer than three points.
        """
        return polygon_area(self.surveyed_footprint)

    def footprint_overlap(self, step: Length64) raises -> Float64:
        """Return how well the solids reproduce the surveyed outline.

        The plan is sampled on a grid. A sample is built when it lies in a
        tower, a wing or the gate, and surveyed when it lies in the outline.

        Args:
            step: The spacing of the samples.

        Returns:
            The samples that are both, over the samples that are either:
            one for a perfect match.

        Raises:
            Error: If the step is not positive and finite, a wing is
                refused, or nothing is built or surveyed.
        """
        if not (isfinite(step.value) and step.value > 0):
            raise Error("A sampling step must be positive and finite")
        var wings = List[List[Point]]()
        for wing in self.wings:
            wings.append(wing.outline())
        var gate = self.gate.outline()
        var low_x = Float64(1.0e30)
        var low_y = Float64(1.0e30)
        var high_x = Float64(-1.0e30)
        var high_y = Float64(-1.0e30)
        for corner in self.surveyed_footprint:
            low_x = min(low_x, corner.x.value)
            low_y = min(low_y, corner.y.value)
            high_x = max(high_x, corner.x.value)
            high_y = max(high_y, corner.y.value)
        var both = 0
        var either = 0
        var across = Int((high_x - low_x) / step.value) + 1
        var up = Int((high_y - low_y) / step.value) + 1
        for row in range(up):
            for column in range(across):
                var at = point(
                    low_x + (Float64(column) + 0.5) * step.value,
                    low_y + (Float64(row) + 0.5) * step.value,
                )
                var built = polygon_contains(gate, at)
                for tower in self.towers:
                    built = built or tower.contains(at)
                for wing in wings:
                    built = built or polygon_contains(wing, at)
                var surveyed = polygon_contains(self.surveyed_footprint, at)
                if built and surveyed:
                    both += 1
                if built or surveyed:
                    either += 1
        if either == 0:
            raise Error("Nothing is built or surveyed")
        return Float64(both) / Float64(either)
