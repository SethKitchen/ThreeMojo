# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded floor plans: a corridor, a core and rooms in a convex footprint.

`plan_floor` lays out one storey as a double-loaded corridor. The corridor
is a strip along the footprint's longest edge, through the footprint's
middle. A band of rooms lies on each side of it. Cuts across each band at
seeded widths make the rooms. Every room spans its band from the corridor
to the outside wall, so every room has a wall on the corridor and every
room on the outside has a window wall.

The core is a run of rooms at the middle of one band: stairs and lifts,
toilets and plant. Its rooms have corridor walls too.

Each room is the footprint clipped by half-planes, so it is convex when
the footprint is. Clipping a convex polygon by a half-plane is the
Sutherland-Hodgman step. See Sutherland and Hodgman, "Reentrant polygon
clipping" (1974).

The layout follows the double-loaded corridor of office and residential
plans in Neufert, "Architects' Data" (5th edition, 2019), and the program
splits of Merrell, Schkufza and Koltun, "Computer-generated residential
building layouts" (2010), at a much simpler level.
"""

from std.math import isfinite, sqrt
from extensions.building.kinds import (
    BATHROOM,
    BEDROOM,
    CORE,
    CORRIDOR,
    KITCHEN,
    LIVING,
    LOBBY,
    MECHANICAL,
    MEETING,
    OFFICE,
    RETAIL,
    STORAGE,
    SpaceUse,
)
from extensions.building.model import SpacePlan
from extensions.topology.arrangement import Point2, polygon_area
from math.utils import SeededRandom
from units.si import Length64, METER


@fieldwise_init
struct FloorProgram(Equatable, ImplicitlyCopyable, Writable):
    """What a storey holds."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three programs.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


# Offices and meeting rooms around a core.
comptime OFFICE_FLOOR = FloorProgram(0)
# Living rooms, bedrooms, kitchens and bathrooms around a core.
comptime RESIDENTIAL_FLOOR = FloorProgram(1)
# A wide lobby instead of a corridor, with shops.
comptime LOBBY_FLOOR = FloorProgram(2)


@fieldwise_init
struct PlanOptions(ImplicitlyCopyable):
    """The sizes `plan_floor` works to."""

    var corridor_width: Length64
    var min_room: Length64
    var max_room: Length64
    # The width of the core run, along the corridor.
    var core_length: Length64

    def check(self) raises:
        """Refuse sizes no plan can use.

        Raises:
            Error: If a size is not positive and finite, or the largest room
                is narrower than the smallest.
        """
        var sizes = [
            self.corridor_width.to(METER),
            self.min_room.to(METER),
            self.max_room.to(METER),
            self.core_length.to(METER),
        ]
        for i in range(4):  # pragma: no branch
            if not (sizes[i] > 0 and isfinite(sizes[i])):
                raise Error("Plan sizes must be positive and finite")
        if sizes[2] < sizes[1]:
            raise Error(
                "The largest room must not be narrower than the smallest"
            )


def default_plan_options() -> PlanOptions:
    """Return a 1.8 m corridor, rooms 3 to 6 m wide and a 12 m core.

    Returns:
        The options.
    """
    return PlanOptions(
        Length64(1.8, METER),
        Length64(3, METER),
        Length64(6, METER),
        Length64(12, METER),
    )


def clip_half(polygon: List[Point2], n: Point2, d: Float64) -> List[Point2]:
    """Return the part of a convex polygon where n · p <= d.

    Args:
        polygon: The corners in order.
        n: The half-plane's outward normal. It need not be a unit vector.
        d: The half-plane's offset along `n`.

    Returns:
        The clipped corners in the same order. Empty when nothing is left.
    """
    var out = List[Point2]()
    var count = len(polygon)
    for i in range(count):
        var p = polygon[i]
        var q = polygon[(i + 1) % count]
        var dp = n.dot(p) - d
        var dq = n.dot(q) - d
        if dp <= 0:
            out.append(p)
        if (dp < 0 and dq > 0) or (dp > 0 and dq < 0):
            var t = dp / (dp - dq)
            out.append(Point2(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y)))
    return out^


def is_convex(polygon: List[Point2]) -> Bool:
    """Return True if a polygon turns the same way at every corner.

    Straight corners are allowed.

    Args:
        polygon: The corners in order.

    Returns:
        Whether it is convex.
    """
    var n = len(polygon)
    var turns_left = False
    var turns_right = False
    for i in range(n):
        var a = polygon[i]
        var b = polygon[(i + 1) % n]
        var c = polygon[(i + 2) % n]
        var cross = (b - a).cross(c - b)
        if cross > 1e-12:
            turns_left = True
        elif cross < -1e-12:
            turns_right = True
    return not (turns_left and turns_right)


@fieldwise_init
struct _Frame(ImplicitlyCopyable):
    """The plan frame of a footprint: along its longest edge, and across."""

    var u: Point2
    var v: Point2

    def to_local(self, p: Point2) -> Point2:
        return Point2(p.dot(self.u), p.dot(self.v))


def _frame(footprint: List[Point2]) -> _Frame:
    """Return unit axes along and across the footprint's longest edge."""
    var n = len(footprint)
    var best = Point2(1, 0)
    var best_length = Float64(0)
    for i in range(n):  # pragma: no branch
        var d = footprint[(i + 1) % n] - footprint[i]
        var length = sqrt(d.dot(d))
        if length > best_length:
            best_length = length
            best = Point2(d.x / length, d.y / length)
    return _Frame(best, Point2(-best.y, best.x))


def _cuts(
    low: Float64,
    high: Float64,
    mut random: SeededRandom,
    min_room: Float64,
    max_room: Float64,
) -> List[Float64]:
    """Return seeded cut positions that split low to high into rooms.

    Every room is at least `min_room` wide. The last room takes what is
    left, so it can be up to `min_room` wider than `max_room`.
    """
    var out = List[Float64]()
    var at = low
    while high - at >= 2 * min_room:
        var width = min_room + random.next() * (max_room - min_room)
        width = min(width, high - at - min_room)
        at += width
        out.append(at)
    return out^


def _piece(
    band: List[Point2], frame: _Frame, start: Float64, end: Float64
) -> List[Point2]:
    """Return the part of a band between two positions along the frame."""
    var neg_u = Point2(-frame.u.x, -frame.u.y)
    return clip_half(clip_half(band, frame.u, end), neg_u, -start)


def plan_floor(
    footprint: List[Point2],
    program: FloorProgram,
    seed: Int,
    options: PlanOptions,
) raises -> List[SpacePlan]:
    """Return the spaces of one storey in a convex footprint.

    Args:
        footprint: The storey's outline, convex, either winding, in meters.
        program: What the storey holds.
        seed: The seed. The same seed gives the same plan.
        options: The corridor width, the room widths and the core length.

    Returns:
        The corridor or lobby first, then the rooms of each band.

    Raises:
        Error: If the program or options are not valid, the footprint is
            not convex or has no area, or it is too narrow for a corridor
            and two rooms deep, or too short for the core.
    """
    if not program.is_valid():
        raise Error("A floor program must be office, residential or lobby")
    options.check()
    if len(footprint) < 3 or abs(polygon_area(footprint)) <= 1e-9:
        raise Error("A footprint needs three corners and an area")
    if not is_convex(footprint):
        raise Error("A footprint must be convex")
    var frame = _frame(footprint)
    var u_low = Float64.MAX
    var u_high = -Float64.MAX
    var v_low = Float64.MAX
    var v_high = -Float64.MAX
    for i in range(len(footprint)):  # pragma: no branch
        var p = frame.to_local(footprint[i])
        u_low = min(u_low, p.x)
        u_high = max(u_high, p.x)
        v_low = min(v_low, p.y)
        v_high = max(v_high, p.y)
    var corridor = options.corridor_width.to(METER)
    if program == LOBBY_FLOOR:
        corridor *= 2.5
    var min_room = options.min_room.to(METER)
    var max_room = options.max_room.to(METER)
    var core_length = options.core_length.to(METER)
    if v_high - v_low < corridor + 2 * min_room:
        raise Error("The footprint is too narrow for a corridor and two rooms")
    if u_high - u_low < core_length + 2 * min_room:
        raise Error("The footprint is too short for the core")
    var middle = (v_low + v_high) / 2
    var lower_line = middle - corridor / 2
    var upper_line = middle + corridor / 2
    var neg_v = Point2(-frame.v.x, -frame.v.y)
    var out = List[SpacePlan]()
    # The corridor strip.
    var strip = clip_half(
        clip_half(footprint, frame.v, upper_line), neg_v, -lower_line
    )
    var hall_use = LOBBY if program == LOBBY_FLOOR else CORRIDOR
    out.append(SpacePlan(hall_use.name(), hall_use, strip^))
    var random = SeededRandom(seed if seed != 0 else 1)
    # The upper band holds the core at its middle.
    var upper = clip_half(footprint, neg_v, -upper_line)
    var core_start = (u_low + u_high) / 2 - core_length / 2
    var core_end = core_start + core_length
    var core_uses: List[SpaceUse]
    var core_shares: List[Float64]
    if program == RESIDENTIAL_FLOOR:
        core_uses = [CORE, STORAGE]
        core_shares = [0.6, 0.4]
    elif program == LOBBY_FLOOR:
        core_uses = [CORE, BATHROOM]
        core_shares = [0.6, 0.4]
    else:
        core_uses = [CORE, BATHROOM, MECHANICAL]
        core_shares = [0.5, 0.25, 0.25]
    var bands = [upper^, clip_half(footprint, frame.v, lower_line)]
    for b in range(2):  # pragma: no branch
        ref band = bands[b]
        var positions = List[Float64]()
        var uses = List[SpaceUse]()
        positions.append(-Float64.MAX)
        if b == 0:
            for c in _cuts(u_low, core_start, random, min_room, max_room):
                positions.append(c)
                uses.append(_room_use(program, len(uses), random))
            positions.append(core_start)
            uses.append(_room_use(program, len(uses), random))
            var at = core_start
            for k in range(len(core_uses)):  # pragma: no branch
                at += core_shares[k] * core_length
                positions.append(at)
                uses.append(core_uses[k])
            # The last core position is the core's end.
            positions[len(positions) - 1] = core_end
            for c in _cuts(core_end, u_high, random, min_room, max_room):
                positions.append(c)
                uses.append(_room_use(program, len(uses), random))
        else:
            # The band is longer than the core and two rooms, so it has a
            # cut.
            for c in _cuts(  # pragma: no branch
                u_low, u_high, random, min_room, max_room
            ):
                positions.append(c)
                uses.append(_room_use(program, len(uses), random))
        positions.append(Float64.MAX)
        uses.append(_room_use(program, len(uses), random))
        for k in range(len(uses)):  # pragma: no branch
            var shape = _piece(band, frame, positions[k], positions[k + 1])
            out.append(
                SpacePlan(
                    String(uses[k].name(), " ", len(out)), uses[k], shape^
                )
            )
    return out^


def _room_use(
    program: FloorProgram, index: Int, mut random: SeededRandom
) -> SpaceUse:
    """Return the use of a band room."""
    var draw = random.next()
    if program == LOBBY_FLOOR:
        return RETAIL
    if program == RESIDENTIAL_FLOOR:
        var cycle = [LIVING, BEDROOM, KITCHEN, BEDROOM]
        return cycle[index % 4]
    return MEETING if draw < 0.2 else OFFICE
