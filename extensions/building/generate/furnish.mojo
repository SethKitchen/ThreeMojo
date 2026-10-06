# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded furniture for the rooms of a building model.

`furnish` places furniture by rules, room by room. Each use has a list of
pieces. A wall piece stands with its back to a wall and keeps a clearance
in front of it. A center piece stands in the open with a clearance all
round. A chair goes in front of a desk, or around a table.

A candidate place is refused when the piece leaves the room, overlaps a
piece or a clearance already placed, stands in the swing of a door, or is
a tall piece in front of a window. Among the places left, the piece takes
the best one by a score: a desk prefers a window, a bed prefers a wall far
from the door, and a small seeded term breaks ties. A piece with no place
left is skipped.

The rules follow the interior layout guidelines of Merrell, Schkufza, Li,
Agrawala and Koltun, "Interactive furniture layout using interior design
guidelines" (2011): clearance, circulation, and pairwise relations.
"""

from std.math import atan2, cos, pi, sin, sqrt
from extensions.building.ids import SpaceId
from extensions.building.kinds import (
    BATHROOM,
    BED,
    BEDROOM,
    CABINET,
    CHAIR,
    COFFEE_TABLE,
    COUNTER,
    DESK,
    DOOR,
    FurnitureKind,
    KITCHEN,
    LIVING,
    LOBBY,
    MECHANICAL,
    MEETING,
    NIGHTSTAND,
    OFFICE,
    RETAIL,
    SHELF,
    SINK,
    SOFA,
    STORAGE,
    SpaceUse,
    TABLE,
    TOILET,
    WARDROBE,
)
from extensions.building.model import Building, Furnishing, quads_apart
from extensions.topology.arrangement import Point2, contains
from math.utils import SeededRandom
from units.si import Angle64, Length64, METER, RADIAN, SQUARE_METER

# How a piece is placed.
comptime _WALL = 0
comptime _CENTER = 1


@fieldwise_init
struct _Piece(ImplicitlyCopyable):
    """A piece to place: its kind, size, placement and clearances."""

    var kind: FurnitureKind
    var width: Float64
    var depth: Float64
    var height: Float64
    var mode: Int
    # Clear space in front of a wall piece, or all round a center piece.
    var clearance: Float64
    # Chairs that go with it: in front of a desk, or around a table.
    var chairs: Int


def _pieces(use: SpaceUse, area: Float64) -> List[_Piece]:
    """Return the pieces a room of a use and an area gets."""
    var out = List[_Piece]()
    if use == OFFICE:
        var desks = max(1, Int(area / 10))
        for _ in range(desks):  # pragma: no branch
            out.append(_Piece(DESK, 1.4, 0.7, 0.75, _WALL, 1.0, 1))
        out.append(_Piece(SHELF, 1.0, 0.4, 1.8, _WALL, 0.8, 0))
    elif use == MEETING:
        out.append(_Piece(TABLE, 2.4, 1.2, 0.75, _CENTER, 0.9, 6))
        out.append(_Piece(CABINET, 1.2, 0.5, 0.9, _WALL, 0.8, 0))
    elif use == LIVING:
        out.append(_Piece(SOFA, 2.0, 0.9, 0.8, _WALL, 1.2, 0))
        out.append(_Piece(COFFEE_TABLE, 1.0, 0.6, 0.4, _CENTER, 0.4, 0))
        out.append(_Piece(SHELF, 1.2, 0.4, 1.8, _WALL, 0.8, 0))
    elif use == BEDROOM:
        out.append(_Piece(BED, 1.6, 2.0, 0.5, _WALL, 0.8, 0))
        out.append(_Piece(NIGHTSTAND, 0.45, 0.4, 0.55, _WALL, 0.3, 0))
        out.append(_Piece(WARDROBE, 1.2, 0.6, 2.0, _WALL, 0.9, 0))
    elif use == KITCHEN:
        out.append(_Piece(COUNTER, 2.4, 0.6, 0.9, _WALL, 1.0, 0))
        out.append(_Piece(TABLE, 1.2, 0.8, 0.75, _CENTER, 0.8, 4))
    elif use == BATHROOM:
        out.append(_Piece(TOILET, 0.4, 0.7, 0.8, _WALL, 0.6, 0))
        out.append(_Piece(SINK, 0.6, 0.45, 0.85, _WALL, 0.6, 0))
        out.append(_Piece(TOILET, 0.4, 0.7, 0.8, _WALL, 0.6, 0))
    elif use == STORAGE or use == MECHANICAL:
        out.append(_Piece(SHELF, 1.2, 0.5, 2.0, _WALL, 0.9, 0))
        out.append(_Piece(CABINET, 1.0, 0.6, 1.2, _WALL, 0.9, 0))
    elif use == RETAIL:
        out.append(_Piece(COUNTER, 1.8, 0.7, 1.0, _CENTER, 1.0, 0))
        out.append(_Piece(SHELF, 1.5, 0.5, 2.0, _WALL, 1.0, 0))
        out.append(_Piece(SHELF, 1.5, 0.5, 2.0, _WALL, 1.0, 0))
    elif use == LOBBY:
        out.append(_Piece(SOFA, 2.0, 0.9, 0.8, _WALL, 1.2, 0))
        out.append(_Piece(COFFEE_TABLE, 1.0, 0.6, 0.4, _CENTER, 0.5, 0))
    return out^


def _box(
    center: Point2, angle: Float64, width: Float64, depth: Float64
) -> List[Point2]:
    """Return the corners of a box turned by an angle."""
    var c = cos(angle)
    var s = sin(angle)
    var hw = width / 2
    var hd = depth / 2
    var local: List[Point2] = [
        Point2(-hw, -hd),
        Point2(hw, -hd),
        Point2(hw, hd),
        Point2(-hw, hd),
    ]
    var out = List[Point2](capacity=4)
    for i in range(4):  # pragma: no branch
        out.append(
            Point2(
                center.x + c * local[i].x - s * local[i].y,
                center.y + s * local[i].x + c * local[i].y,
            )
        )
    return out^


def _inside(outline: List[Point2], box: List[Point2]) -> Bool:
    """Return True if every corner of a box is inside a convex outline.

    The placer keeps pieces a few centimeters off the walls, so no corner
    falls on the outline itself.
    """
    for i in range(4):  # pragma: no branch
        if not contains(outline, box[i]):
            return False
    return True


def _clear(box: List[Point2], obstacles: List[List[Point2]]) -> Bool:
    """Return True if a box overlaps no obstacle."""
    for i in range(len(obstacles)):
        if not quads_apart(box, obstacles[i]):
            return False
    return True


struct _Room(Movable):
    """What the placer knows about one room."""

    var outline: List[Point2]
    var obstacles: List[List[Point2]]
    var windows: List[List[Point2]]
    var doors: List[Point2]

    def __init__(out self, var outline: List[Point2]):
        self.outline = outline^
        self.obstacles = List[List[Point2]]()
        self.windows = List[List[Point2]]()
        self.doors = List[Point2]()


def _room(building: Building, space: SpaceId) raises -> _Room:
    """Collect a room's outline, door swings and window strips."""
    var outline = building.spaces[space.value].outline.copy()
    if _signed_area(outline) < 0:
        outline.reverse()
    var room = _Room(outline^)
    # A space always has the walls and slabs of its cell.
    var elements = building.elements_of_space(space)
    for i in range(len(elements)):  # pragma: no branch
        var openings = building.openings_of(elements[i])
        if len(openings) == 0:
            continue
        var frame = building.wall_frame(elements[i])
        for k in range(len(openings)):  # pragma: no branch
            ref o = building.openings[openings[k].value]
            var w = o.width.to(METER)
            var middle = frame.point(o.offset.to(METER) + w / 2, 0, 0)
            var center = Point2(middle.x, middle.y)
            var angle = atan2(frame.along.y, frame.along.x)
            if o.kind == DOOR:
                # The swing, on both sides of the wall.
                room.obstacles.append(_box(center, angle, w + 0.2, 2 * w + 0.2))
                room.doors.append(center)
            else:
                room.windows.append(_box(center, angle, w, 1.2))
    return room^


def _signed_area(points: List[Point2]) -> Float64:
    var total = Float64(0)
    var n = len(points)
    for i in range(n):  # pragma: no branch
        total += (
            points[i].x * points[(i + 1) % n].y
            - points[(i + 1) % n].x * points[i].y
        )
    return total / 2


@fieldwise_init
struct _Place(ImplicitlyCopyable):
    var center: Point2
    var angle: Float64
    var score: Float64


def _wall_places(
    room: _Room, piece: _Piece, mut random: SeededRandom
) -> List[_Place]:
    """Return candidate places with the piece's back to a wall."""
    var out = List[_Place]()
    var n = len(room.outline)
    for e in range(n):  # pragma: no branch
        var a = room.outline[e]
        var b = room.outline[(e + 1) % n]
        var d = b - a
        var length = sqrt(d.dot(d))
        var t = Point2(d.x / length, d.y / length)
        # Inward, for a counterclockwise outline.
        var inward = Point2(-t.y, t.x)
        var angle = atan2(inward.y, inward.x) - pi / 2
        var s = piece.width / 2 + 0.05
        while s <= length - piece.width / 2 - 0.05:
            var offset = piece.depth / 2 + 0.02
            var center = Point2(
                a.x + t.x * s + inward.x * offset,
                a.y + t.y * s + inward.y * offset,
            )
            out.append(_Place(center, angle, random.next() * 0.1))
            s += 0.25
    return out^


def _center_places(
    room: _Room, piece: _Piece, mut random: SeededRandom
) -> List[_Place]:
    """Return candidate places in the open, on a grid, along the room's
    longest edge."""
    var out = List[_Place]()
    var n = len(room.outline)
    var best = 0
    var best_length = Float64(0)
    var low = Point2(Float64.MAX, Float64.MAX)
    var high = Point2(-Float64.MAX, -Float64.MAX)
    var centroid = Point2(0, 0)
    for e in range(n):  # pragma: no branch
        var p = room.outline[e]
        var d = room.outline[(e + 1) % n] - p
        if d.dot(d) > best_length:
            best_length = d.dot(d)
            best = e
        low = Point2(min(low.x, p.x), min(low.y, p.y))
        high = Point2(max(high.x, p.x), max(high.y, p.y))
        centroid = Point2(
            centroid.x + p.x / Float64(n), centroid.y + p.y / Float64(n)
        )
    var d = room.outline[(best + 1) % n] - room.outline[best]
    var angle = atan2(d.y, d.x)
    var y = low.y + 0.15
    while y < high.y:
        var x = low.x + 0.15
        while x < high.x:
            var gap = Point2(x - centroid.x, y - centroid.y)
            out.append(
                _Place(
                    Point2(x, y),
                    angle,
                    -sqrt(gap.dot(gap)) + random.next() * 0.1,
                )
            )
            x += 0.3
        y += 0.3
    return out^


def _distance_to_windows(room: _Room, p: Point2) -> Float64:
    var best = Float64(100)
    for i in range(len(room.windows)):
        ref w = room.windows[i]
        var middle = Point2((w[0].x + w[2].x) / 2, (w[0].y + w[2].y) / 2)
        var gap = p - middle
        best = min(best, sqrt(gap.dot(gap)))
    return best


def _distance_to_doors(room: _Room, p: Point2) -> Float64:
    var best = Float64(100)
    for i in range(len(room.doors)):
        var gap = p - room.doors[i]
        best = min(best, sqrt(gap.dot(gap)))
    return best


def _place(
    mut building: Building,
    mut room: _Room,
    space: SpaceId,
    piece: _Piece,
    mut random: SeededRandom,
) raises -> Bool:
    """Place one piece and its chairs at its best free place. Return
    whether it was placed."""
    var places = _wall_places(
        room, piece, random
    ) if piece.mode == _WALL else _center_places(room, piece, random)
    var found = -1
    var best = -Float64.MAX
    for i in range(len(places)):
        var p = places[i]
        var body = _box(p.center, p.angle, piece.width, piece.depth)
        if not _inside(room.outline, body) or not _clear(body, room.obstacles):
            continue
        var zone = _zone(p, piece)
        if not _clear(zone, room.obstacles):
            continue
        if piece.height > 1.0 and not _clear(body, room.windows):
            continue
        var score = p.score
        if piece.kind == DESK:
            score -= _distance_to_windows(room, p.center)
        elif piece.kind == BED:
            score += _distance_to_doors(room, p.center)
        if score > best:
            best = score
            found = i
    if found < 0:
        return False
    var p = places[found]
    _ = building.add_furnishing(
        piece.kind,
        space,
        p.center,
        Angle64(p.angle, RADIAN),
        Length64(piece.width, METER),
        Length64(piece.depth, METER),
        Length64(piece.height, METER),
    )
    room.obstacles.append(_box(p.center, p.angle, piece.width, piece.depth))
    room.obstacles.append(_zone(p, piece))
    _chairs(building, room, space, p, piece)
    return True


def _zone(p: _Place, piece: _Piece) -> List[Point2]:
    """Return the clearance a placed piece keeps.

    A wall piece keeps a strip in front of it; a center piece keeps a
    margin all round. The strip starts just past the piece, so it does not
    overlap the piece itself.
    """
    if piece.mode == _CENTER:
        return _box(
            p.center,
            p.angle,
            piece.width + 2 * piece.clearance,
            piece.depth + 2 * piece.clearance,
        )
    var front = Point2(-sin(p.angle), cos(p.angle))
    var shift = piece.depth / 2 + piece.clearance / 2 + 0.001
    var center = Point2(
        p.center.x + front.x * shift, p.center.y + front.y * shift
    )
    return _box(center, p.angle, piece.width, piece.clearance)


def _chairs(
    mut building: Building,
    mut room: _Room,
    space: SpaceId,
    p: _Place,
    piece: _Piece,
) raises:
    """Add the chairs of a desk or a table, where they fit."""
    if piece.chairs == 0:
        return
    var front = Point2(-sin(p.angle), cos(p.angle))
    var side = Point2(cos(p.angle), sin(p.angle))
    var spots = List[Point2]()
    var angles = List[Float64]()
    if piece.mode == _WALL:
        var reach = piece.depth / 2 + 0.3
        spots.append(
            Point2(p.center.x + front.x * reach, p.center.y + front.y * reach)
        )
        angles.append(p.angle + pi)
    else:
        var per_side = (piece.chairs + 1) // 2
        for k in range(per_side):  # pragma: no branch
            var along = (Float64(k) + 0.5) / Float64(per_side) - 0.5
            along *= piece.width
            for sign in range(2):  # pragma: no branch
                var facing = 1.0 if sign == 0 else -1.0
                var reach = facing * (piece.depth / 2 + 0.3)
                spots.append(
                    Point2(
                        p.center.x + side.x * along + front.x * reach,
                        p.center.y + side.y * along + front.y * reach,
                    )
                )
                angles.append(p.angle + (pi if sign == 0 else 0.0))
    # Each chair stands inside its piece's clearance, which the placer
    # checked against every piece already in the room. It can still leave
    # a room shallower than that clearance.
    for k in range(len(spots)):  # pragma: no branch
        var body = _box(spots[k], angles[k], 0.5, 0.5)
        if not _inside(room.outline, body):
            continue
        _ = building.add_furnishing(
            CHAIR,
            space,
            spots[k],
            Angle64(angles[k], RADIAN),
            Length64(0.5, METER),
            Length64(0.5, METER),
            Length64(0.9, METER),
        )


def furnish(mut building: Building, seed: Int) raises -> Int:
    """Furnish every room of a building model by rules.

    Call it after the doors and windows are in, so the furniture keeps
    clear of them.

    Args:
        building: The model.
        seed: The seed. The same seed gives the same furniture.

    Returns:
        The number of furnishings added, chairs included.

    Raises:
        Error: Never, for a model that validates.
    """
    var before = len(building.furnishings)
    var random = SeededRandom(seed if seed != 0 else 1)
    for s in range(len(building.spaces)):
        var space = SpaceId(s)
        var area = building.floor_area(space).to(SQUARE_METER)
        var pieces = _pieces(building.spaces[s].use, area)
        if len(pieces) == 0:
            continue
        var room = _room(building, space)
        for k in range(len(pieces)):  # pragma: no branch
            _ = _place(building, room, space, pieces[k], random)
    return len(building.furnishings) - before
