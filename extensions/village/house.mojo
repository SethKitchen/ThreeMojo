# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A house of the village: its building model, and the house standing on
its lot.

`house_model` writes the canonical building model with
`extensions.building.model.assemble`. The ground storey of a house 6
meters wide or more has two rooms: a hall with a hearth, a counter and a
table, and a chamber with a bed. A narrower house has the hall only.
Each storey above has one living room. The outside walls are `cladding`
over mineral wool and gypsum board. The hall has a front door in the
middle of its front wall, the wall at the plan's -y. The chamber has a
door into the hall. Each outside wall has a row of windows, and
`furnish` gives each room its furniture.

`extensions.village.house_view.stand_house` stands the model on its lot.
It does not use the general render view: it draws the village's own view
of the same model, with its facade, its roof and its doors on hinges.
`extensions.village.interior` reads from the model where a character can
walk.

`Facade` says how the outside walls look:

| Facade | Walls | Dressings |
|---|---|---|
| `BRICK_FACADE` | Red brick | Stone quoins, lintels and sills |
| `STONE_FACADE` | Fieldstone | Timber lintels, stone sills |
| `TIMBER_FRAMED` | Lime plaster | Oak posts, rails and braces |
| `BOARDED` | Vertical boards | Battens over the joints |
"""

from core.ordinal import ordinal_valid
from extensions.building.construction import (
    Construction,
    Layer,
    double_glazing,
)
from extensions.building.generate.furnish import furnish
from extensions.building.generate.openings import (
    WindowOptions,
    add_doors,
    add_windows,
)
from extensions.building.ids import ConstructionId, ElementId, MaterialId
from extensions.building.kinds import BEDROOM, DOOR, KITCHEN, LIVING, WALL
from extensions.building.material import (
    BuildingMaterial,
    Look,
    concrete,
    gypsum_board,
    mineral_wool,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Furnishing,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
)
from extensions.topology.arrangement import Point2
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.ground import Ground, Lot
from math.vector3 import Vector3
from std.math import ceil, cos, sin
from units.si import (
    DEGREE,
    DEGREE64,
    GIGAPASCAL,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    MEGAPASCAL,
    METER,
    PER_KELVIN,
    RADIAN,
    WATT_PER_METER_KELVIN,
    Angle,
    Angle64,
    Density64,
    Length,
    Length64,
    Pressure64,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    ThermalExpansion64,
)

# The tint that shows a roof's covering as its texture is.
comptime NATURAL = Vector3(1, 1, 1)
# The linear color of painted wood: doors, shutters and frames.
comptime PAINT = Vector3(0.030, 0.090, 0.060)
# The front door's width and height, and an inside door's, in meters.
comptime FRONT_DOOR = Vector3(1.0, 2.1, 0)
comptime INSIDE_DOOR = Vector3(0.9, 2.0, 0)
# The share of the width the hall takes, when the house has a chamber.
comptime HALL_SHARE = Float64(0.6)
# The narrowest house, in meters, whose ground storey has a chamber.
comptime CHAMBERED = Float32(6)
"""How wide a house must be for a chamber beside its hall, in meters."""
comptime STAIR_WIDTH = Float64(1.0)
"""How wide a stair is, in meters."""
comptime STAIR_GOING = Float64(0.25)
"""How deep each tread of a stair is, in meters."""
comptime STAIR_RISE = Float64(0.19)
"""The most that one riser of a stair rises, in meters."""
comptime STAIR_LANDING = Float64(0.9)
"""How much floor a stair keeps clear before its foot, in meters."""


@fieldwise_init
struct Facade(Equatable, ImplicitlyCopyable, Writable):
    """How a house's outside walls look, as a type rather than a bare
    int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four facades there are.

        Returns:
            Whether the value names a facade.
        """
        return ordinal_valid(self.value, 3)


# Red brick walls, with stone quoins at the corners and stone lintels and
# sills at the windows.
comptime BRICK_FACADE = Facade(0)
# Fieldstone walls, with timber lintels and stone sills.
comptime STONE_FACADE = Facade(1)
# Lime plaster between oak posts, rails and braces.
comptime TIMBER_FRAMED = Facade(2)
# Vertical boards with battens over the joints, as a barn has.
comptime BOARDED = Facade(3)


def fieldstone() -> BuildingMaterial:
    """Return rubble masonry of fieldstone in lime mortar.

    Returns:
        2,200 kg/m³, 5 GPa, a compressive strength of 5 MPa and a
        conductivity of 1.7 W/(m K).
    """
    return BuildingMaterial(
        "fieldstone",
        Density64(2200, KILOGRAM_PER_CUBIC_METER),
        Pressure64(5, GIGAPASCAL),
        0.2,
        Pressure64(5, MEGAPASCAL),
        ThermalConductivity64(1.7, WATT_PER_METER_KELVIN),
        SpecificHeatCapacity64(840, JOULE_PER_KILOGRAM_KELVIN),
        ThermalExpansion64(8e-6, PER_KELVIN),
        Look(0.55, 0.53, 0.49, 0.9, 0, 0),
    )


def lime_plaster() -> BuildingMaterial:
    """Return lime plaster on a lath, as between the timbers of a framed
    wall.

    Returns:
        1,600 kg/m³, 2 GPa, a compressive strength of 2 MPa and a
        conductivity of 0.7 W/(m K).
    """
    return BuildingMaterial(
        "lime plaster",
        Density64(1600, KILOGRAM_PER_CUBIC_METER),
        Pressure64(2, GIGAPASCAL),
        0.2,
        Pressure64(2, MEGAPASCAL),
        ThermalConductivity64(0.7, WATT_PER_METER_KELVIN),
        SpecificHeatCapacity64(840, JOULE_PER_KILOGRAM_KELVIN),
        ThermalExpansion64(9e-6, PER_KELVIN),
        Look(0.86, 0.83, 0.76, 0.95, 0, 0),
    )


struct HouseParameters(Copyable, Movable):
    """What a house is made of, how large it is and how it looks."""

    var name: String
    # The width and the depth of the plan, and the height of a storey.
    var width: Length
    var depth: Length
    var storey_height: Length
    var storeys: Int
    # The outer layer of the outside walls, and how they look.
    var cladding: BuildingMaterial
    var facade: Facade
    # How steep the gable roof is. Zero is the model's flat roof.
    var pitch: Angle
    # The tint over the roof covering's texture, and the linear color of
    # the painted wood.
    var roof: Vector3
    var trim: Vector3
    # Which furniture, and which weathering of the walls.
    var seed: Int

    def __init__(
        out self,
        var name: String,
        width: Length,
        depth: Length,
        storeys: Int,
        var cladding: BuildingMaterial,
        facade: Facade = BRICK_FACADE,
        storey_height: Length = Length(2.8, METER),
        pitch: Angle = Angle(40.0, DEGREE),
        roof: Vector3 = NATURAL,
        trim: Vector3 = PAINT,
        seed: Int = 1,
    ):
        """Create a house's parameters.

        Args:
            name: A name for people and for exchange files.
            width: The plan's width, along its x.
            depth: The plan's depth, along its y.
            storeys: How many storeys.
            cladding: The outer layer of the outside walls.
            facade: How the outside walls look.
            storey_height: The height of a storey.
            pitch: How steep the gable roof is. Zero keeps the flat roof.
            roof: The tint over the roof covering's texture. White shows
                the texture as it is.
            trim: The linear color of the doors, shutters and frames.
            seed: Which furniture, and which weathering of the walls.
        """
        self.name = name^
        self.width = width
        self.depth = depth
        self.storey_height = storey_height
        self.storeys = storeys
        self.cladding = cladding^
        self.facade = facade
        self.pitch = pitch
        self.roof = roof
        self.trim = trim
        self.seed = seed

    def check(self) raises:
        """Refuse a house that cannot be built.

        Raises:
            Error: If the width or the depth is not from 3 to 60 meters,
                there are not from 1 to 6 storeys, a storey is not from
                2.4 to 6 meters tall, the facade is not one, the pitch is
                not from 0 to 60 degrees, or a color channel is not from
                0 to 1.
        """
        require_between(
            self.width.to(METER),
            3,
            60,
            "A house must be from 3 to 60 meters wide",
        )
        require_between(
            self.depth.to(METER),
            3,
            60,
            "A house must be from 3 to 60 meters deep",
        )
        require_count_between(
            self.storeys, 1, 6, "A house must have from 1 to 6 storeys"
        )
        require_between(
            self.storey_height.to(METER),
            2.4,
            6,
            "A storey must be from 2.4 to 6 meters tall",
        )
        if not self.facade.is_valid():
            raise Error("A facade must be one of the four")
        require_between(
            self.pitch.to(DEGREE),
            0,
            60,
            "A roof must pitch from 0 to 60 degrees",
        )
        for color in [self.roof, self.trim]:  # pragma: no branch
            require_between(color.x, 0, 1, "A color must be 0 to 1")
            require_between(color.y, 0, 1, "A color must be 0 to 1")
            require_between(color.z, 0, 1, "A color must be 0 to 1")

    def chambered(self) -> Bool:
        """Return whether the ground storey has a chamber beside the hall.

        Returns:
            Whether the house is `CHAMBERED` meters wide or more.
        """
        return self.width.to(METER) >= CHAMBERED


def _m(meters: Float64) -> Length64:
    """Return a length of `meters`."""
    return Length64(meters, METER)


def front_wall(building: Building) raises -> ElementId:
    """Return the hall's front wall: the longest outside wall of the
    ground storey along the plan's -y side.

    Args:
        building: A house's model.

    Returns:
        The wall.

    Raises:
        Error: If the ground storey has no outside wall along its -y side.
    """
    var lowest = Float64(1.0e30)
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        if element.kind == WALL and element.storey.value == 0:
            var frame = building.wall_frame(ElementId(e))
            lowest = min(lowest, frame.origin.y)
    var best = -1
    var best_length = Float64(0)
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        if element.kind != WALL or element.storey.value != 0:
            continue
        var frame = building.wall_frame(ElementId(e))
        var flat = abs(frame.along.y) < 1.0e-6
        if (
            flat
            and abs(frame.origin.y - lowest) < 1.0e-6
            and frame.length > best_length
        ):
            best = e
            best_length = frame.length
    if best < 0:
        raise Error("A house needs a front wall")
    return ElementId(best)


@fieldwise_init
struct Stair(ImplicitlyCopyable):
    """A straight stair along a hall's back wall, from the ground floor up
    to the floor of the storey above, in the model's plan.

    It climbs along the plan's +x. Tread `k`, from zero, runs from
    `x0 + k * STAIR_GOING` to one going further, and its top stands
    `(k + 1) * rise` over the ground floor. The last riser reaches the
    upper floor at `x1`."""

    # Where its foot and its top are along the plan's x, in meters.
    var x0: Float64
    var x1: Float64
    # Its open side, and the back wall's inside face, along the plan's y,
    # in meters.
    var y0: Float64
    var y1: Float64
    # How many risers it has, and how high each one is, in meters.
    var risers: Int
    var rise: Float64

    def height(self) -> Float64:
        """Return how high the stair climbs.

        Returns:
            The height of the upper floor over the ground floor, in meters.
        """
        return Float64(self.risers) * self.rise


def house_stair(building: Building) -> Optional[Stair]:
    """Return a house's stair: along the back wall of its hall, from the
    ground floor up to the storey above.

    The hall is the first space of the ground storey, as `house_model`
    writes it. The stair keeps `STAIR_LANDING` of floor clear before its
    foot, at the hall's -x end. It has as few risers as keep each one at
    most `STAIR_RISE`.

    Args:
        building: A house's model.

    Returns:
        The stair, or None for a model of one storey or of no room, for
        an upper storey no more than one riser over the ground floor, and
        for a hall too short for the stair.
    """
    if len(building.storeys) < 2:
        return None
    if len(building.spaces) == 0:
        return None
    var west = Float64(1.0e30)
    var east = Float64(-1.0e30)
    var back = Float64(-1.0e30)
    for p in building.spaces[0].outline:  # pragma: no branch
        west = min(west, p.x)
        east = max(east, p.x)
        back = max(back, p.y)
    var half = building.constructions[0].thickness().value / 2
    var climb = (
        building.storeys[1].elevation.value
        - building.storeys[0].elevation.value
    )
    # A stair has two risers or more: a lower storey needs no stair.
    if climb <= STAIR_RISE:
        return None
    var risers = Int(ceil(climb / STAIR_RISE))
    var foot = west + half + STAIR_LANDING
    var top = foot + Float64(risers - 1) * STAIR_GOING
    if top > east - half:
        return None
    var wall = back - half
    return Stair(
        foot, top, wall - STAIR_WIDTH, wall, risers, climb / Float64(risers)
    )


def clear_stair(mut building: Building, stair: Stair) raises:
    """Take away the furniture of the ground storey and of the storey above
    that stands on a stair, before its foot, or over its well.

    Args:
        building: A house's model. It is changed.
        stair: Its stair.

    Raises:
        Error: If a piece's room is not in the model.
    """
    var west = stair.x0 - STAIR_LANDING
    var middle_x = (west + stair.x1) / 2
    var middle_y = (stair.y0 + stair.y1) / 2
    var half_x = (stair.x1 - west) / 2
    var half_y = (stair.y1 - stair.y0) / 2
    var kept = List[Furnishing]()
    for index in range(len(building.furnishings)):
        ref piece = building.furnishings[index]
        building.check_space(piece.space)
        var storey = building.spaces[piece.space.value].storey.value
        # The piece's reach along the plan's axes, as it is turned.
        var c = abs(cos(piece.rotation.value))
        var s = abs(sin(piece.rotation.value))
        var w = piece.width.value / 2
        var d = piece.depth.value / 2
        var reach_x = half_x + c * w + s * d
        var reach_y = half_y + s * w + c * d
        var apart_x = abs(piece.center.x - middle_x) >= reach_x
        var apart_y = abs(piece.center.y - middle_y) >= reach_y
        if storey > 1 or apart_x or apart_y:
            kept.append(piece.copy())
    building.furnishings = kept^


def house_model(parameters: HouseParameters) raises -> Building:
    """Return a house's model, with its doors, windows and furniture.

    Args:
        parameters: The house.

    Returns:
        The model, centered on its plan's middle.

    Raises:
        Error: If `parameters.check` refuses a value, or the model cannot
            be assembled.
    """
    parameters.check()
    var half_x = Float64(parameters.width.to(METER)) / 2
    var half_y = Float64(parameters.depth.to(METER)) / 2
    var outline: List[Point2] = [
        Point2(-half_x, -half_y),
        Point2(half_x, -half_y),
        Point2(half_x, half_y),
        Point2(-half_x, half_y),
    ]
    var plans = List[StoreyPlan]()
    var height = _m(Float64(parameters.storey_height.to(METER)))
    var ground_rooms = List[SpacePlan]()
    if parameters.chambered():
        var split = -half_x + 2 * half_x * HALL_SHARE
        ground_rooms.append(
            SpacePlan(
                "hall",
                KITCHEN,
                [
                    Point2(-half_x, -half_y),
                    Point2(split, -half_y),
                    Point2(split, half_y),
                    Point2(-half_x, half_y),
                ],
            )
        )
        ground_rooms.append(
            SpacePlan(
                "chamber",
                BEDROOM,
                [
                    Point2(split, -half_y),
                    Point2(half_x, -half_y),
                    Point2(half_x, half_y),
                    Point2(split, half_y),
                ],
            )
        )
    else:
        ground_rooms.append(SpacePlan("hall", KITCHEN, outline.copy()))
    plans.append(StoreyPlan("ground storey", height, ground_rooms^))
    for storey in range(1, parameters.storeys):
        var rooms: List[SpacePlan] = [
            SpacePlan("room " + String(storey), LIVING, outline.copy())
        ]
        plans.append(StoreyPlan("storey " + String(storey), height, rooms^))
    var materials: List[BuildingMaterial] = [
        parameters.cladding.copy(),
        mineral_wool(),
        gypsum_board(),
        concrete(),
    ]
    var constructions: List[Construction] = [
        Construction(
            "outside wall",
            [
                Layer(MaterialId(0), _m(0.12)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        ),
        Construction("inside wall", [Layer(MaterialId(2), _m(0.1))]),
        Construction("slab", [Layer(MaterialId(3), _m(0.2))]),
    ]
    var building = assemble(
        parameters.name,
        Site(Angle64(55, DEGREE64), Angle64(9, DEGREE64), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        _m(1e-6),
    )
    var front = front_wall(building)
    var length = building.wall_frame(front).length
    var door_width = Float64(FRONT_DOOR.x)
    _ = building.add_opening(
        DOOR,
        front,
        _m((length - door_width) / 2),
        _m(0),
        _m(door_width),
        _m(Float64(FRONT_DOOR.y)),
        None,
    )
    _ = add_doors(
        building, _m(Float64(INSIDE_DOOR.x)), _m(Float64(INSIDE_DOOR.y))
    )
    _ = add_windows(
        building,
        WindowOptions(_m(2.6), _m(1.5), _m(0.9), _m(1.25), double_glazing()),
    )
    _ = furnish(building, parameters.seed)
    var stair = house_stair(building)
    if stair:
        clear_stair(building, stair.value())
    return building^


def house_lot(
    parameters: HouseParameters, x: Float32, z: Float32, turn: Angle
) -> Lot:
    """Return the lot a house stands on.

    Args:
        parameters: The house.
        x: Its middle's x, in meters.
        z: Its middle's z, in meters.
        turn: How far it is turned about +y.

    Returns:
        The lot, as wide and as deep as the house.
    """
    return Lot(
        x,
        z,
        parameters.width.to(METER) / 2,
        parameters.depth.to(METER) / 2,
        turn.to(RADIAN),
    )


def footing(lot: Lot, ground: Ground) -> Tuple[Float32, Float32]:
    """Return the lowest and the highest ground under a lot's corners.

    Args:
        lot: The lot.
        ground: The ground.

    Returns:
        The lowest height, then the highest, in meters.
    """
    var c = cos(lot.turn)
    var s = sin(lot.turn)
    var high = Float32(-1.0e30)
    var low = Float32(1.0e30)
    for k in range(4):  # pragma: no branch
        var u = lot.half_width * (Float32(1) if k % 2 == 0 else Float32(-1))
        var v = lot.half_depth * (Float32(1) if k < 2 else Float32(-1))
        var y = ground.height_at(lot.x + u * c + v * s, lot.z - u * s + v * c)
        high = max(high, y)
        low = min(low, y)
    return (low, high)
