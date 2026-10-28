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
- **Furniture.** Each piece of the ground storey is a solid `Lot`.
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
from extensions.village.terrain import OPEN_SKY, Floor, WallSpan
from generators.utils import Vec3d
from math.vector3 import Vector3
from std.math import atan2, ceil, cos, sin

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
    # The ground floor first, then the steps before the outside doors.
    var floors: List[Floor]
    var furniture: List[Lot]
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
        self.furniture = List[Lot]()
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
        var end = frame.length + t / 2
        if end - u > 1.0e-6:
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
        ref face = building.topology.complex.faces[host.faces[0].value]
        var outside = building.is_exterior(o.host)
        # An outside door swings into the house: toward the side of its
        # wall that has a room. An inside door swings along the normal.
        var swing = normal
        if outside and not face.positive:
            swing = Vector3(-normal.x, 0, -normal.z)
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
        Its walls, its floor and steps, its furniture and its doors.

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
    for index in range(len(building.furnishings)):
        ref piece = building.furnishings[index]
        if building.spaces[piece.space.value].storey.value != 0:
            continue
        var at = placer.point(Vec3d(piece.center.x, piece.center.y, 0))
        interior.furniture.append(
            Lot(
                at.x,
                at.z,
                Float32(piece.width.value) / 2,
                Float32(piece.depth.value) / 2,
                lot.turn + Float32(piece.rotation.value),
            )
        )
    return interior^
