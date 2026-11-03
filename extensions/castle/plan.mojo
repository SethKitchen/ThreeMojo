# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A castle as data: towers, blocks, a moat and a bridge, in meters.

The plan frame has x to the east, y to the north and z up. Every height is
above the ground of the castle island. A `Tower` is a round or square shaft
with a cone or a battlemented parapet. A `Block` is a long wall-bounded
range with a gable roof, or a gatehouse with a parapet. A `Moat` is an
ellipse of water around an island. A `Bridge` is a row of segmental masonry
arches.

`wijnendale` is the plan of Wijnendale Castle. See the wiki page Castle for
what the plan documents and what it estimates.
"""

from extensions.castle.kinds import (
    CONE,
    GABLE,
    PARAPET,
    ROUND,
    RoofForm,
    SQUARE,
    TowerShape,
    require_roof_form,
    require_tower_shape,
)
from math.finite import require_finite, require_positive_finite
from std.math import cos, pi, sin, sqrt
from units.si import (
    Angle64,
    Area64,
    DEGREE64,
    METER,
    Length64,
    Volume64,
)


def _m(value: Float64) -> Length64:
    """Return meters as a length."""
    return Length64(value, METER)


@fieldwise_init
struct PlanPoint(ImplicitlyCopyable):
    """A point of the plan."""

    # East of the origin.
    var x: Length64
    # North of the origin.
    var y: Length64


def _scaled_point(point: PlanPoint, factor: Float64) -> PlanPoint:
    """Return a point with both its distances multiplied by a factor."""
    return PlanPoint(point.x.scaled(factor), point.y.scaled(factor))


@fieldwise_init
struct Tower(Copyable, Movable):
    """A tower: a shaft of masonry under a cone or a parapet."""

    var name: String
    var shape: TowerShape
    var center: PlanPoint
    # The outer radius of a round tower, or half the side of a square one.
    var radius: Length64
    # The thickness of the shaft wall at its base.
    var wall: Length64
    # The height of the shaft above the ground, to the eave or the parapet.
    var height: Length64
    # CONE or PARAPET.
    var roof: RoofForm
    # The rise of a cone above the eave. It is ignored for a parapet.
    var roof_rise: Length64

    def check(self) raises:
        """Refuse a tower that cannot stand.

        Nothing. The call returns when the tower is sound.

        Raises:
            Error: If the shape or roof is not named, a size is not
                positive and finite, the roof is a gable, or the wall is
                not thinner than the radius.
        """
        require_tower_shape(self.shape)
        require_roof_form(self.roof)
        require_finite(self.center.x.value, "A tower must have a position")
        require_finite(self.center.y.value, "A tower must have a position")
        require_positive_finite(
            self.radius.value, "A tower radius must be positive"
        )
        require_positive_finite(
            self.wall.value, "A tower wall must be positive"
        )
        require_positive_finite(
            self.height.value, "A tower height must be positive"
        )
        if self.roof == GABLE:
            raise Error("A tower has a cone or a parapet, not a gable")
        if self.roof == CONE:
            require_positive_finite(
                self.roof_rise.value, "A cone must have a rise"
            )
        if not self.wall < self.radius:
            raise Error("A tower wall must be thinner than its radius")

    def apex(self) -> Length64:
        """Return the height of the top of the tower above the ground.

        Returns:
            The shaft height, plus the cone rise for a cone.
        """
        if self.roof == CONE:
            return self.height + self.roof_rise
        return self.height

    def footprint(self) -> Area64:
        """Return the plan area of the tower, walls and core.

        Returns:
            Pi r squared for a round tower, and the square of the side for
            a square one.
        """
        if self.shape == ROUND:
            return (self.radius * self.radius).scaled(pi)
        return (self.radius * self.radius).scaled(4.0)

    def core_radius(self) -> Length64:
        """Return the radius of the hollow inside the shaft.

        Returns:
            The radius less the wall. For a square tower it is the
            half-side less the wall.
        """
        return self.radius - self.wall

    def shaft_volume(self) -> Volume64:
        """Return the volume of masonry in the shaft.

        Returns:
            The footprint less the core, times the height.
        """
        var core = self.core_radius()
        var hollow = (core * core).scaled(pi)
        if self.shape == SQUARE:
            hollow = (core * core).scaled(4.0)
        return (self.footprint() - hollow) * self.height


@fieldwise_init
struct Block(Copyable, Movable):
    """A long range or a gatehouse, a rectangle of wall under a roof."""

    var name: String
    var center: PlanPoint
    # The size along the heading.
    var length: Length64
    # The size across the heading.
    var width: Length64
    # The direction of the length, counterclockwise from east.
    var heading: Angle64
    # The thickness of the outer walls.
    var wall: Length64
    # The height of the walls above the ground, to the eave or the parapet.
    var height: Length64
    # GABLE or PARAPET.
    var roof: RoofForm
    # The rise of a gable above the eave. It is ignored for a parapet.
    var roof_rise: Length64

    def check(self) raises:
        """Refuse a block that cannot stand.

        Nothing. The call returns when the block is sound.

        Raises:
            Error: If the roof is not named, a size is not positive and
                finite, the roof is a cone, or the walls are not thinner
                than half the width.
        """
        require_roof_form(self.roof)
        require_finite(self.center.x.value, "A block must have a position")
        require_finite(self.center.y.value, "A block must have a position")
        require_finite(self.heading.value, "A block must have a heading")
        require_positive_finite(
            self.length.value, "A block length must be positive"
        )
        require_positive_finite(
            self.width.value, "A block width must be positive"
        )
        require_positive_finite(
            self.wall.value, "A block wall must be positive"
        )
        require_positive_finite(
            self.height.value, "A block height must be positive"
        )
        if self.roof == CONE:
            raise Error("A block has a gable or a parapet, not a cone")
        if self.roof == GABLE:
            require_positive_finite(
                self.roof_rise.value, "A gable must have a rise"
            )
        if not self.wall.scaled(2.0) < self.width:
            raise Error("A block wall must be thinner than half its width")

    def apex(self) -> Length64:
        """Return the height of the top of the block above the ground.

        Returns:
            The wall height, plus the gable rise for a gable.
        """
        if self.roof == GABLE:
            return self.height + self.roof_rise
        return self.height

    def corner(self, along: Float64, across: Float64) -> PlanPoint:
        """Return a point of the block's rectangle in the plan.

        Args:
            along: The place along the length, -1 at one end, +1 at the
                other.
            across: The place across the width, -1 at one side, +1 at the
                other.

        Returns:
            The point, turned by the heading about the center.
        """
        var u = self.length.scaled(0.5 * along)
        var v = self.width.scaled(0.5 * across)
        var c = cos(self.heading.value)
        var s = sin(self.heading.value)
        return PlanPoint(
            self.center.x + u.scaled(c) - v.scaled(s),
            self.center.y + u.scaled(s) + v.scaled(c),
        )

    def footprint(self) -> Area64:
        """Return the plan area of the block.

        Returns:
            The length times the width.
        """
        return self.length * self.width


@fieldwise_init
struct Moat(Copyable, Movable):
    """The water ring: an outer ellipse around an island."""

    var center: PlanPoint
    # The semi-axes of the outer edge of the water.
    var semi_x: Length64
    var semi_y: Length64
    var island_center: PlanPoint
    # The semi-axes of the island, where the water meets its wall.
    var island_semi_x: Length64
    var island_semi_y: Length64
    # The depth of the water at its normal level.
    var depth: Length64
    # How far the island ground stands above the water.
    var freeboard: Length64

    def check(self) raises:
        """Refuse a moat that is not a ring.

        Nothing. The call returns when the island lies inside the water.

        Raises:
            Error: If a size is not positive and finite, or the island
                does not lie inside the outer edge.
        """
        require_finite(self.center.x.value, "A moat must have a center")
        require_finite(self.center.y.value, "A moat must have a center")
        require_finite(
            self.island_center.x.value, "An island must have a center"
        )
        require_finite(
            self.island_center.y.value, "An island must have a center"
        )
        require_positive_finite(
            self.semi_x.value, "A moat semi-axis must be positive"
        )
        require_positive_finite(
            self.semi_y.value, "A moat semi-axis must be positive"
        )
        require_positive_finite(
            self.island_semi_x.value, "An island semi-axis must be positive"
        )
        require_positive_finite(
            self.island_semi_y.value, "An island semi-axis must be positive"
        )
        require_positive_finite(
            self.depth.value, "A moat depth must be positive"
        )
        require_positive_finite(
            self.freeboard.value, "A moat freeboard must be positive"
        )
        if not self.island_inside():
            raise Error("The island must lie inside the moat")

    def island_inside(self) -> Bool:
        """Return True if the island ellipse lies inside the outer ellipse.

        The test samples the island edge at 64 points.

        Returns:
            Whether every sample is inside the outer ellipse.
        """
        # The 64 samples are a literal, so the loop always runs.
        for k in range(64):  # pragma: no branch
            var t = 2.0 * pi * Float64(k) / 64.0
            var x = self.island_center.x.value + self.island_semi_x.value * cos(
                t
            )
            var y = self.island_center.y.value + self.island_semi_y.value * sin(
                t
            )
            var u = (x - self.center.x.value) / self.semi_x.value
            var v = (y - self.center.y.value) / self.semi_y.value
            if u * u + v * v >= 1.0:
                return False
        return True

    def water_area(self) -> Area64:
        """Return the area of the water surface.

        Returns:
            The outer ellipse less the island.
        """
        var outer = (self.semi_x * self.semi_y).scaled(pi)
        var inner = (self.island_semi_x * self.island_semi_y).scaled(pi)
        return outer - inner

    def volume(self) -> Volume64:
        """Return the volume of water at the normal level.

        Returns:
            The water area times the depth.
        """
        return self.water_area() * self.depth


@fieldwise_init
struct Bridge(Copyable, Movable):
    """A bridge of equal segmental masonry arches on piers."""

    # Where the deck meets the gatehouse.
    var start: PlanPoint
    # The direction of the deck, counterclockwise from east.
    var heading: Angle64
    # The number of arches.
    var spans: Int
    # The clear span of one arch, between the faces of its piers.
    var span: Length64
    # The thickness of one pier, and of each abutment.
    var pier: Length64
    # The rise of an arch from the springing line to the crown intrados.
    var rise: Length64
    # The thickness of the arch ring at the crown.
    var ring: Length64
    # The width of the deck between the parapets.
    var width: Length64
    # The depth of fill over the extrados at the crown, under the deck.
    var fill: Length64
    # The height of the springing line above the water.
    var springing: Length64
    # The height of the parapet above the deck.
    var parapet: Length64

    def check(self) raises:
        """Refuse a bridge that cannot stand.

        Nothing. The call returns when the bridge is sound.

        Raises:
            Error: If there is no arch, a size is not positive and finite,
                or an arch is no shallower than a semicircle.
        """
        require_finite(self.start.x.value, "A bridge must have a start")
        require_finite(self.start.y.value, "A bridge must have a start")
        require_finite(self.heading.value, "A bridge must have a heading")
        if self.spans < 1:
            raise Error("A bridge must have at least one span")
        require_positive_finite(
            self.span.value, "A bridge span must be positive"
        )
        require_positive_finite(
            self.pier.value, "A bridge pier must be positive"
        )
        require_positive_finite(
            self.rise.value, "A bridge rise must be positive"
        )
        require_positive_finite(
            self.ring.value, "A bridge ring must be positive"
        )
        require_positive_finite(
            self.width.value, "A bridge width must be positive"
        )
        require_positive_finite(
            self.fill.value, "A bridge fill must be positive"
        )
        require_positive_finite(
            self.springing.value, "A bridge springing must be positive"
        )
        require_positive_finite(
            self.parapet.value, "A bridge parapet must be positive"
        )
        if not self.rise.scaled(2.0) <= self.span:
            raise Error("An arch cannot rise more than half its span")

    def length(self) -> Length64:
        """Return the length of the bridge, abutment face to abutment face.

        Returns:
            The spans plus one more pier than there are spans.
        """
        return self.span.scaled(Float64(self.spans)) + self.pier.scaled(
            Float64(self.spans + 1)
        )

    def intrados_radius(self) -> Length64:
        """Return the radius of the underside of an arch.

        Returns:
            (s^2 / 4 + f^2) / (2 f) for the clear span s and the rise f.
        """
        var half = self.span.scaled(0.5)
        return (half * half + self.rise * self.rise) / self.rise.scaled(2.0)

    def deck_height(self) -> Length64:
        """Return the height of the deck above the water at the crown.

        Returns:
            The springing, plus the rise, the ring and the fill.
        """
        return self.springing + self.rise + self.ring + self.fill

    def point(self, along: Length64, across: Length64) -> PlanPoint:
        """Return a point of the deck in the plan.

        Args:
            along: The distance from the start along the heading.
            across: The distance to the left of the heading.

        Returns:
            The point.
        """
        var c = cos(self.heading.value)
        var s = sin(self.heading.value)
        return PlanPoint(
            self.start.x + along.scaled(c) - across.scaled(s),
            self.start.y + along.scaled(s) + across.scaled(c),
        )


struct CastlePlan(Movable):
    """The whole castle: where it stands and what it is made of."""

    var name: String
    # The latitude of the castle, north positive.
    var latitude: Angle64
    # The longitude of the castle, east positive.
    var longitude: Angle64
    var towers: List[Tower]
    var blocks: List[Block]
    var moat: Moat
    var bridge: Bridge

    def __init__(
        out self,
        var name: String,
        latitude: Angle64,
        longitude: Angle64,
        var towers: List[Tower],
        var blocks: List[Block],
        var moat: Moat,
        var bridge: Bridge,
    ):
        """Hold a plan. Call `check` before use.

        Args:
            name: The castle's name.
            latitude: The latitude, north positive.
            longitude: The longitude, east positive.
            towers: The towers.
            blocks: The blocks.
            moat: The moat.
            bridge: The bridge.
        """
        self.name = name^
        self.latitude = latitude
        self.longitude = longitude
        self.towers = towers^
        self.blocks = blocks^
        self.moat = moat^
        self.bridge = bridge^

    def check(self) raises:
        """Refuse a plan that has a part that cannot stand.

        Nothing. The call returns when every part is sound.

        Raises:
            Error: If the site is outside the globe, there is no tower, a
                part is not sound, or a tower stands outside the island.
        """
        if not (abs(self.latitude.value) <= pi / 2.0):
            raise Error("A latitude must be from -90 to 90 degrees")
        if not (abs(self.longitude.value) <= pi):
            raise Error("A longitude must be from -180 to 180 degrees")
        if len(self.towers) == 0:
            raise Error("A castle must have a tower")
        # A castle has a tower, so this loop always runs.
        for i in range(len(self.towers)):  # pragma: no branch
            self.towers[i].check()
            if not self.on_island(self.towers[i].center):
                raise Error("A tower must stand on the island")
        for i in range(len(self.blocks)):
            self.blocks[i].check()
        self.moat.check()
        self.bridge.check()

    def scaled(self, factor: Float64) raises -> CastlePlan:
        """Return the plan with every length multiplied by a factor.

        The angles, the counts, the shapes and the roof forms stay. A
        survey that differs from an estimate by a known ratio gives the
        sensitivity of an analysis to the error of the estimate.

        Args:
            factor: The factor, above zero.

        Returns:
            The scaled plan. It is not checked.

        Raises:
            Error: If the factor is not positive and finite.
        """
        require_positive_finite(factor, "A scale factor must be positive")
        var towers = List[Tower]()
        for i in range(len(self.towers)):
            ref t = self.towers[i]
            towers.append(
                Tower(
                    t.name,
                    t.shape,
                    _scaled_point(t.center, factor),
                    t.radius.scaled(factor),
                    t.wall.scaled(factor),
                    t.height.scaled(factor),
                    t.roof,
                    t.roof_rise.scaled(factor),
                )
            )
        var blocks = List[Block]()
        for i in range(len(self.blocks)):
            ref b = self.blocks[i]
            blocks.append(
                Block(
                    b.name,
                    _scaled_point(b.center, factor),
                    b.length.scaled(factor),
                    b.width.scaled(factor),
                    b.heading,
                    b.wall.scaled(factor),
                    b.height.scaled(factor),
                    b.roof,
                    b.roof_rise.scaled(factor),
                )
            )
        var moat = Moat(
            _scaled_point(self.moat.center, factor),
            self.moat.semi_x.scaled(factor),
            self.moat.semi_y.scaled(factor),
            _scaled_point(self.moat.island_center, factor),
            self.moat.island_semi_x.scaled(factor),
            self.moat.island_semi_y.scaled(factor),
            self.moat.depth.scaled(factor),
            self.moat.freeboard.scaled(factor),
        )
        var bridge = Bridge(
            _scaled_point(self.bridge.start, factor),
            self.bridge.heading,
            self.bridge.spans,
            self.bridge.span.scaled(factor),
            self.bridge.pier.scaled(factor),
            self.bridge.rise.scaled(factor),
            self.bridge.ring.scaled(factor),
            self.bridge.width.scaled(factor),
            self.bridge.fill.scaled(factor),
            self.bridge.springing.scaled(factor),
            self.bridge.parapet.scaled(factor),
        )
        return CastlePlan(
            self.name,
            self.latitude,
            self.longitude,
            towers^,
            blocks^,
            moat^,
            bridge^,
        )

    def on_island(self, point: PlanPoint) -> Bool:
        """Return True if a point lies on the island.

        Args:
            point: The point.

        Returns:
            Whether the point is inside the island ellipse.
        """
        var u = (point.x - self.moat.island_center.x) / self.moat.island_semi_x
        var v = (point.y - self.moat.island_center.y) / self.moat.island_semi_y
        return u.value * u.value + v.value * v.value < 1.0

    def tallest(self) -> Length64:
        """Return the height of the highest part of the castle.

        Returns:
            The greatest apex of a tower or a block.
        """
        var top = _m(0.0)
        for i in range(len(self.towers)):
            var apex = self.towers[i].apex()
            if apex > top:
                top = apex
        for i in range(len(self.blocks)):
            var apex = self.blocks[i].apex()
            if apex > top:
                top = apex
        return top

    def masonry_footprint(self) -> Area64:
        """Return the plan area that towers and blocks cover.

        Overlaps count twice, so this is an upper bound of the area.

        Returns:
            The sum of the tower and block footprints.
        """
        var total = Area64(0.0)
        for i in range(len(self.towers)):
            total = total + self.towers[i].footprint()
        for i in range(len(self.blocks)):
            total = total + self.blocks[i].footprint()
        return total


def _round_tower(
    name: String,
    x: Float64,
    y: Float64,
    radius: Float64,
    height: Float64,
    roof: RoofForm,
    rise: Float64,
) -> Tower:
    """Return a round tower with a wall of one meter."""
    return Tower(
        name,
        ROUND,
        PlanPoint(_m(x), _m(y)),
        _m(radius),
        _m(1.0),
        _m(height),
        roof,
        _m(rise),
    )


def wijnendale() -> CastlePlan:
    """Return the plan of Wijnendale Castle.

    The site and the history are documented: the castle stands near
    Torhout in West Flanders at 51 deg 4' 44" N, 3 deg 3' 34" E. Felix
    Laureys designed the brick gatehouse and the keep in 1877 and 1878.
    The sources do not agree on the plan of the gatehouse, so the plan
    takes it as square. Sources describe the castle as round, with a
    circular moat around a round inner courtyard, so the moat is a circle:
    the oval in the aerial photograph is foreshortening. Every dimension
    here is an estimate from that photograph, good to about 15 percent.
    Replace the numbers with a survey to analyze the real walls.

    Returns:
        The plan, with the keep, five round towers and the four corner
        turrets of the gatehouse, a rear range, a front range and the
        gatehouse, a moat and a three-arch bridge.
    """
    var towers = List[Tower]()
    # The keep, at the west end of the rear range.
    towers.append(
        Tower(
            "keep",
            ROUND,
            PlanPoint(_m(-14.0), _m(10.0)),
            _m(3.6),
            _m(1.2),
            _m(28.0),
            PARAPET,
            _m(0.0),
        )
    )
    towers.append(
        _round_tower("south-west tower", -20.0, -13.0, 3.3, 15.0, PARAPET, 0.0)
    )
    towers.append(
        _round_tower("south tower", -11.0, -17.0, 3.0, 15.0, CONE, 9.0)
    )
    towers.append(
        _round_tower("south-east tower", 10.0, -15.5, 2.8, 15.0, CONE, 8.5)
    )
    towers.append(
        _round_tower("courtyard turret", -10.0, 4.0, 1.7, 13.0, CONE, 6.5)
    )
    towers.append(
        _round_tower("courtyard stair", -21.0, -2.0, 1.6, 12.0, CONE, 6.0)
    )
    towers.append(
        _round_tower("gate turret north-west", 14.0, 6.0, 1.7, 21.0, CONE, 5.5)
    )
    towers.append(
        _round_tower("gate turret north-east", 30.0, 6.0, 1.7, 21.0, CONE, 5.5)
    )
    towers.append(
        _round_tower(
            "gate turret south-west", 14.0, -10.0, 1.7, 21.0, CONE, 5.5
        )
    )
    towers.append(
        _round_tower(
            "gate turret south-east", 30.0, -10.0, 1.7, 21.0, CONE, 5.5
        )
    )
    var blocks = List[Block]()
    blocks.append(
        Block(
            "rear range",
            PlanPoint(_m(2.0), _m(9.0)),
            _m(30.0),
            _m(9.0),
            Angle64(0.0, DEGREE64),
            _m(1.1),
            _m(11.0),
            GABLE,
            _m(7.0),
        )
    )
    blocks.append(
        Block(
            "front range",
            PlanPoint(_m(-3.0), _m(-13.0)),
            _m(34.0),
            _m(9.0),
            Angle64(0.0, DEGREE64),
            _m(1.1),
            _m(11.0),
            GABLE,
            _m(6.5),
        )
    )
    blocks.append(
        Block(
            "gatehouse",
            PlanPoint(_m(22.0), _m(-2.0)),
            _m(16.0),
            _m(16.0),
            Angle64(0.0, DEGREE64),
            _m(1.6),
            _m(19.0),
            PARAPET,
            _m(0.0),
        )
    )
    var moat = Moat(
        PlanPoint(_m(4.0), _m(-3.0)),
        _m(46.0),
        _m(46.0),
        PlanPoint(_m(4.0), _m(-3.0)),
        _m(33.0),
        _m(33.0),
        _m(1.6),
        _m(2.4),
    )
    var bridge = Bridge(
        PlanPoint(_m(30.0), _m(-2.0)),
        Angle64(-8.0, DEGREE64),
        3,
        _m(5.0),
        _m(1.4),
        _m(1.4),
        _m(0.4),
        _m(4.2),
        _m(0.5),
        _m(0.1),
        _m(0.9),
    )
    return CastlePlan(
        "Wijnendale Castle",
        Angle64(51.0 + 4.0 / 60.0 + 44.0 / 3600.0, DEGREE64),
        Angle64(3.0 + 3.0 / 60.0 + 34.0 / 3600.0, DEGREE64),
        towers^,
        blocks^,
        moat^,
        bridge^,
    )
