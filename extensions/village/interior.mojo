# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a character can walk in a house: its walls, its floor, its
steps, its furniture and its doors, read from its building model.

`house_interior` reads the model of a house that stands on its lot, with
its ground floor at a height. It is a view of the canonical model, as the
render view is: it reads the model and never writes it.

- **Walls.** Each wall of the model is a `WallSpan` along the middle of
  its face. It reaches half its thickness past each end, so the corners
  close, as the render view draws it. A door cuts a gap from the floor
  to its head. The wall over the door is a span of its own, from the
  door's head to the wall's top.
- **The floor.** The ground floor is a `Floor` over the plan and its
  plinth, at the floor's height. Its ceiling is the underside of the
  slab over it.
- **Steps.** Where the ground outside an outside door lies more than
  `STEP_RISE` below the floor, stone steps lead up to the door. Each step
  is a `Floor` of its own.
- **Furniture.** Each piece is a `WallSpan` along its longer side, as
  thick as its shorter side and as high as the piece, on its storey's
  floor. So a piece upstairs passes over a character on the floor below.
- **The stair.** Where `house_stair` finds a stair, each tread is a
  `Floor`, and so is the upper floor round the stairwell. A railing
  guards the well's open side, from the ground floor up, so it closes the
  stair's side too. A railing crosses the well's foot upstairs, and a
  wall closes the space under the stair's top.
- **Doorways.** Each door of the ground storey is a `Doorway`: the jamb
  it hangs on, its width and the way it swings.

The model is z up and the scene is y up. A model point (x, y, z) stands
at the lot's point (x, -y), turned by the lot's turn, at the floor's
height plus z.
"""

from extensions.building.ids import ElementId
from extensions.building.kinds import DOOR, ROOF, SLAB, WALL
from extensions.building.model import Building
from extensions.vegetation.ground import Ground, Lot
from extensions.village.house import STAIR_GOING, Stair, house_stair
from extensions.village.terrain import OPEN_SKY, Floor, WallSpan
from generators.utils import Vec3d
from math.vector3 import Vector3
from std.math import atan2, ceil, copysign, cos, sin

comptime PLINTH_OVERHANG = Float32(0.15)
"""How far the plinth reaches past the middle of the outside walls, in
meters."""
comptime STEP_RISE = Float32(0.12)
"""The highest rise from the ground to a door's sill, in meters, that
needs no step."""
comptime STEP_HEIGHT = Float32(0.18)
"""The highest rise of one step, in meters."""
comptime STEP_DEPTH = Float32(0.32)
"""How deep each step is, from the door outward, in meters."""
comptime STEP_WIDER = Float32(0.6)
"""How much wider a step is than its door, in meters."""
comptime MOST_STEPS = 6
"""The most steps before one door."""
comptime RAIL_HEIGHT = Float32(1.0)
"""How high a railing stands over the floor it guards, in meters."""
comptime RAIL_HALF = Float32(0.05)
"""Half the thickness of a railing, in meters."""


@fieldwise_init
struct Doorway(ImplicitlyCopyable):
    """A door of a house's ground storey, in the scene."""

    # The foot of the jamb the leaf hangs on, on the wall's middle line,
    # in meters.
    var hinge_x: Float32
    var hinge_z: Float32
    # The way from that jamb to the other, of length one.
    var along_x: Float32
    var along_z: Float32
    # The way the leaf swings open, of length one: into the house for an
    # outside door.
    var swing_x: Float32
    var swing_z: Float32
    # The door's width and height, in meters.
    var width: Float32
    var height: Float32
    # The height of the floor at the door, in meters.
    var bottom: Float32
    # Whether the door leads outside.
    var outside: Bool

    def middle(self) -> Vector3:
        """Return the middle of the doorway, on the floor.

        Returns:
            The point halfway between the jambs, at the floor's height.
        """
        var half = self.width / 2
        return Vector3(
            self.hinge_x + self.along_x * half,
            self.bottom,
            self.hinge_z + self.along_z * half,
        )


struct HouseInterior(Copyable, Movable):
    """Where a character can walk in a house, and what stops it there."""

    var walls: List[WallSpan]
    # The ground floor first, then the steps before the outside doors,
    # then the stair's treads and the upper floor round its well.
    var floors: List[Floor]
    # How many steps before the doors follow the ground floor.
    var steps: Int
    var furniture: List[WallSpan]
    var doorways: List[Doorway]
    # The height of the ground floor, in meters.
    var floor_height: Float32

    def __init__(out self, floor_height: Float32):
        """Hold nothing yet, over a floor at a height.

        Args:
            floor_height: The height of the ground floor, in meters.
        """
        self.walls = List[WallSpan]()
        self.floors = List[Floor]()
        self.steps = 0
        self.furniture = List[WallSpan]()
        self.doorways = List[Doorway]()
        self.floor_height = floor_height

    def front_door(self) raises -> Doorway:
        """Return the first door that leads outside.

        Returns:
            The doorway.

        Raises:
            Error: If no door leads outside.
        """
        for way in self.doorways:
            if way.outside:
                return way
        raise Error("A house needs a door that leads outside")


struct _Placer(ImplicitlyCopyable):
    """Turns model points and directions into the scene's."""

    var lot: Lot
    var floor: Float32
    var c: Float32
    var s: Float32

    def __init__(out self, lot: Lot, floor: Float32):
        self.lot = lot
        self.floor = floor
        self.c = cos(lot.turn)
        self.s = sin(lot.turn)

    def point(self, p: Vec3d) -> Vector3:
        """Return a model point in the scene."""
        var x = Float32(p.x)
        var z = -Float32(p.y)
        return Vector3(
            self.lot.x + x * self.c + z * self.s,
            self.floor + Float32(p.z),
            self.lot.z - x * self.s + z * self.c,
        )

    def way(self, d: Vec3d) -> Vector3:
        """Return a model direction on the ground in the scene."""
        var x = Float32(d.x)
        var z = -Float32(d.y)
        return Vector3(x * self.c + z * self.s, 0, -x * self.s + z * self.c)


def _span(
    placer: _Placer,
    building: Building,
    wall: ElementId,
    u0: Float64,
    u1: Float64,
    v0: Float64,
    v1: Float64,
    half: Float32,
) raises -> WallSpan:
    """Return the piece of a wall from `u0` to `u1` along it and from
    `v0` to `v1` up it."""
    var frame = building.wall_frame(wall)
    var a = placer.point(frame.point(u0, v0, 0))
    var b = placer.point(frame.point(u1, v0, 0))
    return WallSpan(
        a.x,
        a.z,
        b.x,
        b.z,
        half,
        a.y,
        placer.floor + Float32(frame.origin.z + v1),
    )


def _walls(
    mut interior: HouseInterior, placer: _Placer, building: Building
) raises:
    """Add a span for each piece of each wall, cut at the doors."""
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        if element.kind != WALL:
            continue
        var id = ElementId(e)
        var frame = building.wall_frame(id)
        var t = (
            building.constructions[element.construction.value().value]
            .thickness()
            .value
        )
        var half = Float32(t / 2)
        var doors = List[Tuple[Float64, Float64, Float64]]()
        for opening in building.openings_of(id):
            ref o = building.openings[opening.value]
            if o.kind == DOOR:
                var start = o.offset.value
                var k = len(doors)
                while k > 0 and doors[k - 1][0] > start:
                    k -= 1
                doors.insert(k, (start, start + o.width.value, o.height.value))
        var u = -t / 2
        for k in range(len(doors)):
            if doors[k][0] - u > 1.0e-6:
                interior.walls.append(
                    _span(
                        placer,
                        building,
                        id,
                        u,
                        doors[k][0],
                        0,
                        frame.height,
                        half,
                    )
                )
            interior.walls.append(
                _span(
                    placer,
                    building,
                    id,
                    doors[k][0],
                    doors[k][1],
                    doors[k][2],
                    frame.height,
                    half,
                )
            )
            u = doors[k][1]
        # A door ends inside its wall, so the last piece is at least half
        # the wall's thickness long.
        var end = frame.length + t / 2
        interior.walls.append(
            _span(placer, building, id, u, end, 0, frame.height, half)
        )


def _turn_of(along: Vector3) -> Float32:
    """Return the lot turn whose own x runs along a direction."""
    return atan2(-along.z, along.x)


def _doorways(
    mut interior: HouseInterior, placer: _Placer, building: Building
) raises:
    """Add each door of the ground storey."""
    for index in range(len(building.openings)):
        ref o = building.openings[index]
        if o.kind != DOOR:
            continue
        ref host = building.elements[o.host.value]
        if host.storey.value != 0:
            continue
        var frame = building.wall_frame(o.host)
        var hinge = placer.point(frame.point(o.offset.value, 0, 0))
        var along = placer.way(frame.along)
        var normal = placer.way(frame.normal)
        var outside = building.is_exterior(o.host)
        # An outside door swings into the house: toward the lot's middle,
        # which a box of storeys holds. An inside door swings along the
        # normal.
        var swing = normal
        if outside:
            var toward = (placer.lot.x - hinge.x) * normal.x + (
                placer.lot.z - hinge.z
            ) * normal.z
            swing = normal * copysign(Float32(1), toward)
        interior.doorways.append(
            Doorway(
                hinge.x,
                hinge.z,
                along.x,
                along.z,
                swing.x,
                swing.z,
                Float32(o.width.value),
                Float32(o.height.value),
                hinge.y,
                outside,
            )
        )


def _steps(mut interior: HouseInterior, ground: Ground, turn: Float32) raises:
    """Add steps before each outside door that stands above the ground."""
    for index in range(len(interior.doorways)):
        var door = interior.doorways[index]
        if not door.outside:
            continue
        var middle = door.middle()
        var out_x = -door.swing_x
        var out_z = -door.swing_z
        var reach = PLINTH_OVERHANG + STEP_DEPTH
        var foot = ground.height_at(
            middle.x + out_x * reach, middle.z + out_z * reach
        )
        var rise = door.bottom - foot
        if rise <= STEP_RISE:
            continue
        var count = min(MOST_STEPS, Int(ceil(rise / STEP_HEIGHT)) - 1)
        count = max(1, count)
        var along = Vector3(door.along_x, 0, door.along_z)
        for k in range(count):  # pragma: no branch
            var out = PLINTH_OVERHANG + (Float32(k) + 0.5) * STEP_DEPTH
            var area = Lot(
                middle.x + out_x * out,
                middle.z + out_z * out,
                (door.width + STEP_WIDER) / 2,
                STEP_DEPTH / 2,
                _turn_of(along),
            )
            var height = door.bottom - rise * Float32(k + 1) / Float32(
                count + 1
            )
            interior.floors.append(Floor(area, height, OPEN_SKY))
            interior.steps += 1


def _plan_floor(
    placer: _Placer,
    x0: Float64,
    x1: Float64,
    y0: Float64,
    y1: Float64,
    height: Float32,
    ceiling: Float32,
) -> Floor:
    """Return a floor over a rectangle of the plan, from `x0` to `x1` and
    from `y0` to `y1`."""
    var middle = placer.point(Vec3d((x0 + x1) / 2, (y0 + y1) / 2, 0))
    return Floor(
        Lot(
            middle.x,
            middle.z,
            Float32(x1 - x0) / 2,
            Float32(y1 - y0) / 2,
            placer.lot.turn,
        ),
        height,
        ceiling,
    )


def _plan_span(
    placer: _Placer,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    half: Float32,
    bottom: Float32,
    top: Float32,
) -> WallSpan:
    """Return a span from one point of the plan to another, from a height
    to a height."""
    var a = placer.point(Vec3d(x0, y0, 0))
    var b = placer.point(Vec3d(x1, y1, 0))
    return WallSpan(a.x, a.z, b.x, b.z, half, bottom, top)


def _stair(
    mut interior: HouseInterior,
    placer: _Placer,
    stair: Stair,
    ceiling: Float32,
):
    """Add a stair's treads, the upper floor round its well, and the
    railings. `ceiling` is the upper storey's."""
    var floor = placer.floor
    var top = floor + Float32(stair.height())
    # `house_stair` gives a stair two risers or more: a tread or more.
    for k in range(stair.risers - 1):  # pragma: no branch
        var x0 = stair.x0 + Float64(k) * STAIR_GOING
        interior.floors.append(
            _plan_floor(
                placer,
                x0,
                x0 + STAIR_GOING,
                stair.y0,
                stair.y1,
                floor + Float32(Float64(k + 1) * stair.rise),
                ceiling,
            )
        )
    # The upper floor before the well, beside its foot, and past its top.
    var half_x = Float64(placer.lot.half_width)
    var half_y = Float64(placer.lot.half_depth)
    interior.floors.append(
        _plan_floor(placer, -half_x, half_x, -half_y, stair.y0, top, ceiling)
    )
    interior.floors.append(
        _plan_floor(placer, -half_x, stair.x0, stair.y0, half_y, top, ceiling)
    )
    interior.floors.append(
        _plan_floor(placer, stair.x1, half_x, stair.y0, half_y, top, ceiling)
    )
    interior.walls.append(
        _plan_span(
            placer,
            stair.x0,
            stair.y0,
            stair.x1,
            stair.y0,
            RAIL_HALF,
            floor,
            top + RAIL_HEIGHT,
        )
    )
    interior.walls.append(
        _plan_span(
            placer,
            stair.x0,
            stair.y0,
            stair.x0,
            stair.y1,
            RAIL_HALF,
            top,
            top + RAIL_HEIGHT,
        )
    )
    interior.walls.append(
        _plan_span(
            placer,
            stair.x1,
            stair.y0,
            stair.x1,
            stair.y1,
            RAIL_HALF,
            floor,
            floor + Float32(stair.height() / 2),
        )
    )


def _furniture(
    mut interior: HouseInterior, placer: _Placer, building: Building
) raises:
    """Add a span for each piece of furniture, on its storey's floor."""
    for index in range(len(building.furnishings)):
        ref piece = building.furnishings[index]
        building.check_space(piece.space)
        ref storey = building.storeys[
            building.spaces[piece.space.value].storey.value
        ]
        # Along the piece's longer side, as thick as its shorter one.
        var w = piece.width.value
        var d = piece.depth.value
        var across = Float64(Int(w >= d))
        var turn = piece.rotation.value
        var way_x = cos(turn) * across - sin(turn) * (1 - across)
        var way_y = sin(turn) * across + cos(turn) * (1 - across)
        var reach = (max(w, d) - min(w, d)) / 2
        var bottom = placer.floor + Float32(storey.elevation.value)
        interior.furniture.append(
            _plan_span(
                placer,
                piece.center.x - way_x * reach,
                piece.center.y - way_y * reach,
                piece.center.x + way_x * reach,
                piece.center.y + way_y * reach,
                Float32(min(w, d) / 2),
                bottom,
                bottom + Float32(piece.height.value),
            )
        )


def house_interior(
    building: Building, lot: Lot, floor: Float32, ground: Ground
) raises -> HouseInterior:
    """Return where a character can walk in a house on its lot.

    Args:
        building: The house's model.
        lot: Where it stands: its middle, its half sizes and its turn.
        floor: The height of its ground floor, in meters.
        ground: The ground round it, which the steps lead down to.

    Returns:
        Its walls, its floor and steps, its stair, its furniture and
        its doors.

    Raises:
        Error: If the model's ids do not agree.
    """
    var placer = _Placer(lot, floor)
    var interior = HouseInterior(floor)
    _walls(interior, placer, building)
    # The ground floor's ceiling is the underside of the thickest slab
    # over it.
    var slab = Float64(0)
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        if element.kind == SLAB or element.kind == ROOF:
            slab = max(
                slab,
                building.constructions[element.construction.value().value]
                .thickness()
                .value,
            )
    var ceiling = floor + Float32(building.storeys[0].height.value - slab)
    interior.floors.append(
        Floor(
            Lot(
                lot.x,
                lot.z,
                lot.half_width + PLINTH_OVERHANG,
                lot.half_depth + PLINTH_OVERHANG,
                lot.turn,
            ),
            floor,
            ceiling,
        )
    )
    _doorways(interior, placer, building)
    _steps(interior, ground, lot.turn)
    var stair = house_stair(building)
    if stair:
        ref upper = building.storeys[1]
        var over = floor + Float32(
            upper.elevation.value + upper.height.value - slab
        )
        _stair(interior, placer, stair.value(), over)
    _furniture(interior, placer, building)
    return interior^
