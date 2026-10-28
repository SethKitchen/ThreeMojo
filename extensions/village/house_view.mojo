# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's render view of a house: its walls, its windows and
doors, its roof, its plinth and steps, and its furniture, as a game and
a still picture draw them.

`draw_house` reads a house's canonical building model, as the general
render view `extensions.building.views.render` does, and never writes
it. It draws more of what an eye sees from close by:

1. **Walls.** Each face of each wall is cut into cells at the edges of
   its openings, and no cell is wider or taller than `CELL`. The outside
   face wears the facade's texture. Its vertex colors darken it at its
   foot, where rain splashes, and under the eaves. The inside face wears
   lime plaster, darker in the corners of the room, where less light
   reaches. Each opening has reveals through the wall.
2. **Dressings.** A brick house has stone quoins at its corners, stone
   sills and stone lintels. A stone house has oak lintels. A framed house
   has oak posts, rails and braces over its plaster. A boarded house has
   battens over the joints of its boards. A window has a painted frame, a
   mullion and a transom, panes of glass and a pair of open shutters. A
   door has an oak frame, a stone threshold, and a leaf of boards on
   ledges that turns on its own hinge node.
3. **Floors and ceilings.** Each room has a floor of planks and a
   plastered ceiling. The ground storey's ceiling has oak joists.
4. **The roof.** A gable roof covers the flat roof of the model: two
   slopes of tiles or slates with a thickness, boards under the eaves, a
   fascia, barge boards and a ridge. A gable closes each end. A brick or
   stone house has a chimney.
5. **The plinth and the steps.** A stone plinth reaches from just below
   the floor to below the lowest ground. Each step of the interior's
   floors is a block of stone.
6. **Furniture.** Each furnishing of the model is drawn as its kind:
   a table on legs, a chair with a back, a bed with its blanket, and so
   on.

The house hangs from one node at its lot's middle, at the floor's height,
turned by the lot's turn. Each sheet of `extensions.village.sheet` is one
mesh of one material of `HouseLooks`. Each door leaf is a mesh of its own
under a hinge node, so `extensions.village.doors` can swing it.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.building.ids import ElementId
from extensions.building.kinds import (
    BED,
    CHAIR,
    COFFEE_TABLE,
    COUNTER,
    DESK,
    DOOR,
    FurnitureKind,
    SHELF,
    SINK,
    SOFA,
    TABLE,
    TOILET,
    WALL,
)
from extensions.building.model import Building, WallFrame
from extensions.vegetation.ground import Ground, Lot
from extensions.vegetation.noise import hash01
from extensions.village.house import (
    BOARDED,
    BRICK_FACADE,
    Facade,
    HouseParameters,
    STONE_FACADE,
    TIMBER_FRAMED,
    footing,
)
from extensions.village.interior import (
    HouseInterior,
    PLINTH_OVERHANG,
    house_interior,
)
from extensions.village.sheet import Sheet
from extensions.village.surfaces import (
    ASHLAR_TILE,
    BOARDS_TILE,
    BRICK_TILE,
    FIELDSTONE_TILE,
    HouseLooks,
    PLANK_TILE,
    PLASTER_TILE,
    SLATE_TILE,
    TILE_TILE,
    WOOD_TILE,
    tiled_noise,
)
from generators.utils import Vec3d
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import atan2, cos, sin, sqrt, tan
from units.si import METER, RADIAN, Angle

comptime CELL = Float64(1.0)
"""The widest and the tallest cell of a wall's face, in meters."""
comptime EAVES = Float32(0.35)
"""How far the roof reaches past the long walls, in meters."""
comptime VERGE = Float32(0.25)
"""How far the roof reaches past the gables, in meters."""
comptime ROOF_DEPTH = Float32(0.16)
"""How thick the roof is, from its boards to its tiles, in meters."""
comptime PLINTH_DEPTH = Float32(0.4)
"""How far the plinth reaches below the lowest ground, in meters."""
comptime FRAME_INSET = Float64(0.07)
"""How far a window's or a door's frame stands in from the outside face,
in meters."""
comptime WHITE = Vector3(1, 1, 1)
comptime WOOD_MEAN = Vector3(0.42, 0.22, 0.095)
"""The mean linear color of the wood texture: a paint divided by it
shows as itself."""
comptime OAK = Vector3(0.48, 0.48, 0.48)
"""The tint of dark oak over the wood texture."""
comptime GLASS = Vector3(0.07, 0.09, 0.11)
"""The linear color of a window pane seen from outside."""
comptime DAYLIGHT = Vector3(0.78, 0.84, 0.9)
"""The color of a window pane seen from inside, lit by the day beyond."""
comptime INDOORS = Vector3(1.08, 0.88, 0.68)
"""The warm tint of the inside walls, as light that bounced off the floor
and the wood gives them."""
comptime IRON = Vector3(0.06, 0.06, 0.065)
"""The tint of a door's iron straps over the wood texture."""
comptime STONE = Vector3(0.95, 0.93, 0.9)
"""The tint of the dressed stone."""


def painted(paint: Vector3) -> Vector3:
    """Return the vertex color that shows a paint over the wood texture.

    Args:
        paint: The paint's linear color.

    Returns:
        The paint divided by `WOOD_MEAN`, so the texture's mean shows as
        the paint and its grain still shows through.
    """
    return Vector3(
        paint.x / WOOD_MEAN.x, paint.y / WOOD_MEAN.y, paint.z / WOOD_MEAN.z
    )


def _smooth(t: Float32) -> Float32:
    """Return the smooth step of a share, clamped from 0 to 1."""
    var s = min(Float32(1), max(Float32(0), t))
    return s * s * (3 - 2 * s)


def outside_shade(
    u: Float32, height: Float32, top: Float32, seed: Int
) -> Float32:
    """Return how light an outside wall is at a point.

    Args:
        u: How far along the wall, in meters.
        height: How far above the ground floor, in meters.
        top: The height of the eaves above the ground floor, in meters.
        seed: Which patches are darker.

    Returns:
        A share from about 0.6 to 1.1: darker at the foot, where rain
        splashes and damp rises, and under the eaves, in large patches.
    """
    var damp = Float32(0.72) + 0.28 * _smooth(height / 0.7)
    var eave = 1 - 0.18 * _smooth((height - (top - 0.6)) / 0.6)
    var patch = Float32(0.9) + 0.2 * tiled_noise(
        u / 1.7 + 50, height / 1.3 + 50, 1024, seed
    )
    return damp * eave * patch


def inside_shade(
    u: Float32, v: Float32, length: Float32, height: Float32
) -> Float32:
    """Return how light an inside wall is at a point.

    Args:
        u: How far along the wall, in meters.
        v: How far up it, in meters.
        length: The wall's length, in meters.
        height: The wall's height, in meters.

    Returns:
        A share from about 0.5 to 1: darker in the corners of the room,
        at the floor and at the ceiling, where less light reaches.
    """
    var corner = min(u, length - u)
    var side = Float32(0.72) + 0.28 * _smooth(corner / 0.5)
    var floor = Float32(0.75) + 0.25 * _smooth(v / 0.35)
    var ceiling = Float32(0.8) + 0.2 * _smooth((height - v) / 0.35)
    return side * floor * ceiling


@fieldwise_init
struct Hinge(ImplicitlyCopyable):
    """A door leaf's hinge node, and how it turns."""

    var node: NodeId
    # The node's turn about +y when the door is shut, in radians.
    var shut: Float32
    # Which way the leaf opens: +1 or -1 times the opening angle.
    var sense: Float32


struct _Sheets(Movable):
    """The sheets of one house, one per material."""

    var facade: Sheet
    var plaster: Sheet
    var wood: Sheet
    var ashlar: Sheet
    var roof: Sheet
    var planks: Sheet
    var glass: Sheet
    var daylight: Sheet

    def __init__(out self, facade: Facade):
        var tile = BRICK_TILE
        if facade == STONE_FACADE:
            tile = FIELDSTONE_TILE
        elif facade == TIMBER_FRAMED:
            tile = PLASTER_TILE
        elif facade == BOARDED:
            tile = BOARDS_TILE
        self.facade = Sheet(tile)
        self.plaster = Sheet(PLASTER_TILE)
        self.wood = Sheet(WOOD_TILE)
        self.ashlar = Sheet(ASHLAR_TILE)
        self.roof = Sheet(SLATE_TILE if facade == STONE_FACADE else TILE_TILE)
        self.planks = Sheet(PLANK_TILE)
        self.glass = Sheet(1)
        self.daylight = Sheet(1)


def _local(p: Vec3d) -> Vector3:
    """Return a model point in the house's own frame: y up."""
    return Vector3(Float32(p.x), Float32(p.z), -Float32(p.y))


struct _Face(ImplicitlyCopyable):
    """A wall's frame in the house's own frame."""

    var origin: Vector3
    var along: Vector3
    var normal: Vector3
    var length: Float32
    var height: Float32
    # The model height of the wall's foot, in meters.
    var base: Float32

    def __init__(out self, frame: WallFrame):
        self.origin = _local(frame.origin)
        self.along = _local(frame.along)
        self.normal = _local(frame.normal)
        self.length = Float32(frame.length)
        self.height = Float32(frame.height)
        self.base = Float32(frame.origin.z)

    def at(self, u: Float32, v: Float32, w: Float32) -> Vector3:
        """Return the point `u` along, `v` up and `w` out."""
        return (
            self.origin
            + self.along * u
            + Vector3(0, 1, 0) * v
            + self.normal * w
        )


def _breaks(
    start: Float64, end: Float64, marks: List[Float64]
) -> List[Float64]:
    """Return the sorted cuts from `start` to `end`, at each mark held
    between them, and more so no gap is wider than `CELL`."""
    var cuts = List[Float64]()
    cuts.append(start)
    # Each face passes the marks of its edges, so there are always some.
    for mark in marks:  # pragma: no branch
        var m = min(max(mark, start), end)
        # The first cut is `start`, so the search stops at it.
        var k = len(cuts)
        while cuts[k - 1] > m:
            k -= 1
        if abs(cuts[k - 1] - m) > 1.0e-4:
            cuts.insert(k, m)
    cuts.append(end)
    var out = List[Float64]()
    for k in range(len(cuts) - 1):  # pragma: no branch
        var a = cuts[k]
        var b = cuts[k + 1]
        var parts = max(1, Int((b - a) / CELL + 0.999))
        for p in range(parts):  # pragma: no branch
            out.append(a + (b - a) * Float64(p) / Float64(parts))
    out.append(end)
    return out^


@fieldwise_init
struct _Opening(ImplicitlyCopyable):
    """An opening in a wall's own frame."""

    var u0: Float32
    var u1: Float32
    var v0: Float32
    var v1: Float32
    var door: Bool


def _openings(building: Building, wall: ElementId) raises -> List[_Opening]:
    """Return a wall's openings in its own frame."""
    var out = List[_Opening]()
    for id in building.openings_of(wall):
        ref o = building.openings[id.value]
        var u0 = Float32(o.offset.value)
        var v0 = Float32(o.sill.value)
        out.append(
            _Opening(
                u0,
                u0 + Float32(o.width.value),
                v0,
                v0 + Float32(o.height.value),
                o.kind == DOOR,
            )
        )
    return out^


def _inside(openings: List[_Opening], u: Float32, v: Float32) -> Bool:
    """Return whether a point of a wall's face lies in an opening."""
    for o in openings:
        if u > o.u0 and u < o.u1 and v > o.v0 and v < o.v1:
            return True
    return False


def _wall_faces(
    mut sheets: _Sheets,
    face: _Face,
    openings: List[_Opening],
    half: Float32,
    out_sign: Float32,
    exterior: Bool,
    eaves: Float32,
    seed: Int,
):
    """Add a wall's two faces, cut into cells round its openings.

    `out_sign` is +1 when the outside is along the normal, and -1 when it
    is against it."""
    var marks_u = List[Float64]()
    var marks_v = List[Float64]()
    for o in openings:
        marks_u.append(Float64(o.u0))
        marks_u.append(Float64(o.u1))
        marks_v.append(Float64(o.v0))
        marks_v.append(Float64(o.v1))
    marks_u.append(0.45)
    marks_u.append(Float64(face.length) - 0.45)
    for mark in [0.3, 0.7]:  # pragma: no branch
        marks_v.append(mark)
        marks_v.append(Float64(face.height) - mark)
    var us = _breaks(-Float64(half), Float64(face.length + half), marks_u)
    var vs = _breaks(0, Float64(face.height), marks_v)
    # Each list of cuts holds its start and its end.
    for j in range(len(vs) - 1):  # pragma: no branch
        var v0 = Float32(vs[j])
        var v1 = Float32(vs[j + 1])
        for i in range(len(us) - 1):  # pragma: no branch
            var u0 = Float32(us[i])
            var u1 = Float32(us[i + 1])
            if _inside(openings, (u0 + u1) / 2, (v0 + v1) / 2):
                continue
            for side in range(2):
                # The front face looks along the normal, the back against.
                var sign = Float32(1) if side == 0 else Float32(-1)
                var w = sign * half
                var outdoors = exterior and sign == out_sign
                var a = face.at(u0, v0, w)
                var b = face.at(u1, v0, w)
                var c = face.at(u1, v1, w)
                var d = face.at(u0, v1, w)
                var h0 = face.base + v0
                var h1 = face.base + v1
                if outdoors:
                    var c0 = WHITE * outside_shade(u0, h0, eaves, seed)
                    var c1 = WHITE * outside_shade(u1, h0, eaves, seed)
                    var c2 = WHITE * outside_shade(u1, h1, eaves, seed)
                    var c3 = WHITE * outside_shade(u0, h1, eaves, seed)
                    if sign > 0:
                        sheets.facade.painted_quad(
                            a, b, c, d, c0, c1, c2, c3, u0, h0, u1, h1
                        )
                    else:
                        sheets.facade.painted_quad(
                            b, a, d, c, c1, c0, c3, c2, -u1, h0, -u0, h1
                        )
                    continue
                var length = face.length
                var height = face.height
                var k0 = INDOORS * inside_shade(u0, v0, length, height)
                var k1 = INDOORS * inside_shade(u1, v0, length, height)
                var k2 = INDOORS * inside_shade(u1, v1, length, height)
                var k3 = INDOORS * inside_shade(u0, v1, length, height)
                if sign > 0:
                    sheets.plaster.painted_quad(
                        a, b, c, d, k0, k1, k2, k3, u0, v0, u1, v1
                    )
                else:
                    sheets.plaster.painted_quad(
                        b, a, d, c, k1, k0, k3, k2, -u1, v0, -u0, v1
                    )


def _bar(
    mut sheet: Sheet,
    a: Vector3,
    b: Vector3,
    normal: Vector3,
    width: Float32,
    depth: Float32,
    color: Vector3,
):
    """Add a beam of square ends from `a` to `b`, `width` across in the
    plane at right angles to `normal`, and `depth` along `normal`, its
    back on the points. The points must differ."""
    var x = (b - a) * 0.5
    var ux = x / x.length()
    var z = normal * (depth / 2)
    # y lies in the plane, so that x, y and z turn the right way.
    var uy = Vector3(
        normal.y * ux.z - normal.z * ux.y,
        normal.z * ux.x - normal.x * ux.z,
        normal.x * ux.y - normal.y * ux.x,
    )
    sheet.box((a + b) * 0.5 + z, x, uy * (width / 2), z, color)


def _reveals(
    mut sheets: _Sheets,
    face: _Face,
    o: _Opening,
    half: Float32,
    out_sign: Float32,
    exterior: Bool,
):
    """Add the four faces that line an opening through the wall: plaster
    inside the frame, and the facade's material outside it."""
    var inset = Float32(FRAME_INSET)
    var split = out_sign * (half - inset) if exterior else -half
    var w0 = -half
    var w1 = half
    for part in range(2):  # pragma: no branch
        var a = w0 if part == 0 else split
        var b = split if part == 0 else w1
        if b - a <= 1.0e-5:
            continue
        # The outer part of an outside wall wears the facade: the part on
        # the outside's side of the frame.
        var outer = exterior and (a + b) * out_sign > 0
        # The left jamb faces +along, the right one -along, the head down
        # and the sill up.
        var jamb_l = [
            face.at(o.u0, o.v0, b),
            face.at(o.u0, o.v0, a),
            face.at(o.u0, o.v1, a),
            face.at(o.u0, o.v1, b),
        ]
        var jamb_r = [
            face.at(o.u1, o.v0, a),
            face.at(o.u1, o.v0, b),
            face.at(o.u1, o.v1, b),
            face.at(o.u1, o.v1, a),
        ]
        var head = [
            face.at(o.u0, o.v1, b),
            face.at(o.u0, o.v1, a),
            face.at(o.u1, o.v1, a),
            face.at(o.u1, o.v1, b),
        ]
        var sill = [
            face.at(o.u0, o.v0, a),
            face.at(o.u0, o.v0, b),
            face.at(o.u1, o.v0, b),
            face.at(o.u1, o.v0, a),
        ]
        var shade = WHITE * 0.85
        for q in [jamb_l^, jamb_r^, head^, sill^]:  # pragma: no branch
            if outer:
                sheets.facade.quad(q[0], q[1], q[2], q[3], shade)
            else:
                sheets.plaster.quad(q[0], q[1], q[2], q[3], shade)


def _window(
    mut sheets: _Sheets,
    face: _Face,
    o: _Opening,
    half: Float32,
    out_sign: Float32,
    parameters: HouseParameters,
):
    """Add a window's frame, its bars, its panes, its sill, its lintel and
    its shutters. A window is in an outside wall."""
    var n = face.normal * out_sign
    var plane = out_sign * (half - Float32(FRAME_INSET))
    var paint = painted(parameters.trim)
    var bar = Float32(0.06)
    var deep = Float32(0.07)
    var back = plane - out_sign * deep / 2
    # The frame round the opening.
    _bar(
        sheets.wood,
        face.at(o.u0, o.v0 + bar / 2, back),
        face.at(o.u1, o.v0 + bar / 2, back),
        n,
        bar,
        deep,
        paint,
    )
    _bar(
        sheets.wood,
        face.at(o.u0, o.v1 - bar / 2, back),
        face.at(o.u1, o.v1 - bar / 2, back),
        n,
        bar,
        deep,
        paint,
    )
    _bar(
        sheets.wood,
        face.at(o.u0 + bar / 2, o.v0 + bar, back),
        face.at(o.u0 + bar / 2, o.v1 - bar, back),
        n,
        bar,
        deep,
        paint,
    )
    _bar(
        sheets.wood,
        face.at(o.u1 - bar / 2, o.v0 + bar, back),
        face.at(o.u1 - bar / 2, o.v1 - bar, back),
        n,
        bar,
        deep,
        paint,
    )
    # A mullion and a transom.
    var mid = (o.u0 + o.u1) / 2
    var transom = o.v0 + (o.v1 - o.v0) * 0.66
    var thin = Float32(0.04)
    _bar(
        sheets.wood,
        face.at(mid, o.v0 + bar, back),
        face.at(mid, o.v1 - bar, back),
        n,
        thin,
        deep * 0.8,
        paint,
    )
    _bar(
        sheets.wood,
        face.at(o.u0 + bar, transom, back),
        face.at(o.u1 - bar, transom, back),
        n,
        thin,
        deep * 0.8,
        paint,
    )
    # The panes, facing out and in: along `side` and up, a quad faces
    # along `n`.
    var side = face.along * out_sign
    var low = face.at((o.u0 + o.u1) / 2, o.v0 + bar, plane)
    var high = face.at((o.u0 + o.u1) / 2, o.v1 - bar, plane)
    var across = side * ((o.u1 - o.u0) / 2 - bar)
    sheets.glass.quad(
        low - across, low + across, high + across, high - across, GLASS
    )
    sheets.daylight.quad(
        low + across, low - across, high - across, high + across, DAYLIGHT
    )
    var outer = out_sign * half
    # A sill of stone, or of oak on a boarded house.
    var sill_from = face.at(o.u0 - 0.06, o.v0 - 0.025, plane)
    var sill_to = face.at(o.u1 + 0.06, o.v0 - 0.025, plane)
    var reach = Float32(FRAME_INSET) + 0.05
    if parameters.facade == BOARDED:
        _bar(sheets.wood, sill_from, sill_to, n, 0.05, reach, WHITE * 0.7)
    else:
        _bar(sheets.ashlar, sill_from, sill_to, n, 0.05, reach, STONE)
    # A lintel over the window.
    var lintel_from = face.at(o.u0 - 0.15, o.v1 + 0.11, outer - out_sign * 0.1)
    var lintel_to = face.at(o.u1 + 0.15, o.v1 + 0.11, outer - out_sign * 0.1)
    if parameters.facade == BRICK_FACADE:
        _bar(sheets.ashlar, lintel_from, lintel_to, n, 0.22, 0.115, STONE)
    elif parameters.facade == STONE_FACADE:
        _bar(sheets.wood, lintel_from, lintel_to, n, 0.2, 0.115, OAK)
    if parameters.facade == BOARDED:
        return
    # Most windows of the ground storey have a box of flowers.
    var pick = hash01(Int(o.u0 * 10), Int(face.base * 10), parameters.seed)
    if face.base < 0.5 and pick < 0.65:
        _flower_box(sheets, face, o, n, outer, out_sign, paint, pick)
    # A pair of shutters, open against the wall.
    var leaf = (o.u1 - o.u0) / 2
    for hand in range(2):  # pragma: no branch
        var u_a = o.u0 - leaf - 0.02 if hand == 0 else o.u1 + 0.02
        var u_b = u_a + leaf
        _bar(
            sheets.wood,
            face.at(u_a, (o.v0 + o.v1) / 2, outer),
            face.at(u_b, (o.v0 + o.v1) / 2, outer),
            n,
            o.v1 - o.v0,
            0.03,
            paint,
        )
        # Two ledges across each shutter.
        for k in range(2):  # pragma: no branch
            var v = o.v0 + 0.2 + Float32(k) * (o.v1 - o.v0 - 0.4)
            _bar(
                sheets.wood,
                face.at(u_a + 0.03, v, outer + out_sign * 0.03),
                face.at(u_b - 0.03, v, outer + out_sign * 0.03),
                n,
                0.08,
                0.015,
                paint * 0.8,
            )


def _flower_box(
    mut sheets: _Sheets,
    face: _Face,
    o: _Opening,
    n: Vector3,
    outer: Float32,
    out_sign: Float32,
    paint: Vector3,
    pick: Float32,
):
    """Add a painted box of flowers under a window, on the wall's outside
    face."""
    var low = o.v0 - 0.3
    var high = o.v0 - 0.1
    var middle = (low + high) / 2
    _bar(
        sheets.wood,
        face.at(o.u0 - 0.05, middle, outer),
        face.at(o.u1 + 0.05, middle, outer),
        n,
        high - low,
        0.2,
        paint,
    )
    # A row of leafy clumps, each with a flower head.
    var heads: List[Vector3] = [
        Vector3(0.75, 0.04, 0.03),
        Vector3(0.85, 0.62, 0.05),
        Vector3(0.8, 0.3, 0.45),
        Vector3(0.85, 0.85, 0.8),
    ]
    # Along `side`, up and along `n`, a box turns the right way.
    var side = face.along * out_sign
    var count = max(2, Int((o.u1 - o.u0) / 0.16))
    for k in range(count):  # pragma: no branch
        var u = o.u0 + (o.u1 - o.u0) * (Float32(k) + 0.5) / Float32(count)
        var w = outer + out_sign * 0.1
        var stem = face.at(u, high + 0.05, w)
        sheets.plaster.box(
            stem,
            side * 0.06,
            Vector3(0, 0.06, 0),
            n * 0.07,
            Vector3(0.07, 0.2, 0.04),
        )
        var head = heads[(k + Int(pick * 7)) % 4]
        sheets.plaster.box(
            stem + Vector3(0, 0.1, 0),
            side * 0.035,
            Vector3(0, 0.035, 0),
            n * 0.035,
            head,
        )


def _door_frame(
    mut sheets: _Sheets,
    face: _Face,
    o: _Opening,
    half: Float32,
    out_sign: Float32,
    exterior: Bool,
):
    """Add a door's oak frame, and a stone threshold to an outside door."""
    var n = face.normal * out_sign
    var w = Float32(0.08)
    var deep = half * 2 + 0.02
    var back = -out_sign * (half + 0.01)
    _bar(
        sheets.wood,
        face.at(o.u0 - w / 2, o.v0, back),
        face.at(o.u0 - w / 2, o.v1 + w, back),
        n,
        w,
        deep,
        OAK,
    )
    _bar(
        sheets.wood,
        face.at(o.u1 + w / 2, o.v0, back),
        face.at(o.u1 + w / 2, o.v1 + w, back),
        n,
        w,
        deep,
        OAK,
    )
    _bar(
        sheets.wood,
        face.at(o.u0 - w, o.v1 + w / 2, back),
        face.at(o.u1 + w, o.v1 + w / 2, back),
        n,
        w,
        deep,
        OAK,
    )
    if exterior:
        _bar(
            sheets.ashlar,
            face.at(o.u0 - 0.05, -0.03, back - out_sign * 0.1),
            face.at(o.u1 + 0.05, -0.03, back - out_sign * 0.1),
            n,
            0.06,
            deep + 0.1,
            STONE,
        )


def door_leaf(width: Float32, height: Float32, paint: Vector3) raises -> Sheet:
    """Return a door leaf of boards on ledges, hung at its left edge.

    The leaf runs from x 0 at its hinge to x `width`, from y 0 to
    `height`, and from z -0.02 to 0.02 meters. Its iron straps are on its
    +z face, and its ledges on its -z face.

    Args:
        width: Its width, in meters.
        height: Its height, in meters.
        paint: The vertex color of its boards over the wood texture.

    Returns:
        The leaf's sheet.

    Raises:
        Error: Never; the sizes are the caller's.
    """
    var sheet = Sheet(WOOD_TILE)
    var boards = 4
    var board = width / Float32(boards)
    for k in range(boards):  # pragma: no branch
        var shade = paint * (0.9 + 0.1 * Float32(k % 2))
        sheet.box(
            Vector3(board * (Float32(k) + 0.5), height / 2, 0),
            Vector3(0, height / 2, 0),
            Vector3(-board / 2 + 0.003, 0, 0),
            Vector3(0, 0, 0.02),
            shade,
        )
    for k in range(3):  # pragma: no branch
        var y = 0.2 + Float32(k) * (height - 0.4) / 2
        sheet.box(
            Vector3(width / 2, y, -0.035),
            Vector3(width / 2 - 0.05, 0, 0),
            Vector3(0, 0.07, 0),
            Vector3(0, 0, 0.015),
            paint * 0.85,
        )
        sheet.box(
            Vector3(width * 0.32, y, 0.026),
            Vector3(width * 0.3, 0, 0),
            Vector3(0, 0.025, 0),
            Vector3(0, 0, 0.006),
            IRON,
        )
    # A ring to pull it by.
    sheet.box(
        Vector3(width - 0.12, height * 0.48, 0.04),
        Vector3(0.025, 0, 0),
        Vector3(0, 0.05, 0),
        Vector3(0, 0, 0.02),
        IRON,
    )
    return sheet^


def _quoins(
    mut sheets: _Sheets, half_x: Float32, half_z: Float32, top: Float32
):
    """Add stone quoins up each outside corner of the house, long and
    short in turn on each face. A quoin is two thin blocks, one on each
    face, so it stays in the wall and does not show in the room."""
    var course = Float32(0.25)
    var face = Float32(0.06)
    var proud = Float32(0.015)
    var count = Int(top / course)
    for corner in range(4):  # pragma: no branch
        var sx = Float32(1) if corner % 2 == 0 else Float32(-1)
        var sz = Float32(1) if corner < 2 else Float32(-1)
        # A wall is 2.4 meters tall at least: nine courses or more.
        for k in range(count):  # pragma: no branch
            var long = Float32(0.42) if k % 2 == 0 else Float32(0.24)
            var short = Float32(0.24) if k % 2 == 0 else Float32(0.42)
            var y = Float32(k) * course + course / 2
            var shade = STONE * (0.92 + 0.04 * Float32(k % 3))
            var height = Vector3(0, course / 2 - 0.006, 0)
            # On the face along x, at the outside of the face across z.
            var x0 = sx * (half_x + proud)
            var x1 = sx * (half_x - long)
            var z0 = sz * (half_z + proud)
            var z1 = sz * (half_z - face)
            sheets.ashlar.box(
                Vector3((x0 + x1) / 2, y, (z0 + z1) / 2),
                Vector3(abs(x0 - x1) / 2, 0, 0),
                height,
                Vector3(0, 0, abs(z0 - z1) / 2),
                shade,
            )
            # On the face along z.
            var x2 = sx * (half_x - face)
            var z2 = sz * (half_z - short)
            sheets.ashlar.box(
                Vector3((x0 + x2) / 2, y, (z0 + z2) / 2),
                Vector3(abs(x0 - x2) / 2, 0, 0),
                height,
                Vector3(0, 0, abs(z0 - z2) / 2),
                shade,
            )


def _timbers(
    mut sheets: _Sheets,
    face: _Face,
    openings: List[_Opening],
    half: Float32,
    out_sign: Float32,
):
    """Add oak posts, rails and braces over a framed wall's outside face."""
    var w = out_sign * half
    var n = face.normal * out_sign
    var beam = Float32(0.16)
    var deep = Float32(0.04)
    var posts = List[Float32]()
    posts.append(-half + beam / 2)
    for o in openings:  # pragma: no branch
        posts.append(o.u0 - beam / 2)
        posts.append(o.u1 + beam / 2)
    posts.append(face.length + half - beam / 2)
    # Sort the posts, and add more where two stand far apart.
    var sorted = List[Float32]()
    sorted.append(posts[0])
    for index in range(1, len(posts)):  # pragma: no branch
        var p = posts[index]
        var k = len(sorted)
        # Every post stands right of the first, at the wall's start.
        while sorted[k - 1] > p:
            k -= 1
        sorted.insert(k, p)
    var all = List[Float32]()
    for k in range(len(sorted)):  # pragma: no branch
        if k > 0:
            var gap = sorted[k] - sorted[k - 1]
            var more = Int(gap / 1.3)
            for m in range(more):
                all.append(
                    sorted[k - 1] + gap * Float32(m + 1) / Float32(more + 1)
                )
        all.append(sorted[k])
    var top = face.height
    for u in all:  # pragma: no branch
        if _inside(openings, u, top / 2):
            continue
        _bar(
            sheets.wood,
            face.at(u, beam, w),
            face.at(u, top - beam, w),
            n,
            beam,
            deep,
            OAK,
        )
    # The sole plate, the rail under the windows, the head rail and the
    # wall plate.
    for v in [beam / 2, top - beam / 2]:  # pragma: no branch
        _bar(
            sheets.wood,
            face.at(-half, v, w),
            face.at(face.length + half, v, w),
            n,
            beam,
            deep,
            OAK,
        )
    for k in range(len(all) - 1):  # pragma: no branch
        var a = all[k]
        var b = all[k + 1]
        var middle = (a + b) / 2
        var under = Float32(0.82)
        var over = Float32(2.2)
        if not _inside(openings, middle, under + 0.01):
            _bar(
                sheets.wood,
                face.at(a, under, w),
                face.at(b, under, w),
                n,
                beam * 0.8,
                deep,
                OAK,
            )
        # A storey is 2.4 meters tall at least, so the head rail fits.
        if not _inside(openings, middle, over - 0.01):
            _bar(
                sheets.wood,
                face.at(a, over, w),
                face.at(b, over, w),
                n,
                beam * 0.8,
                deep,
                OAK,
            )
    # A brace in the panel at each end: the posts round each opening
    # keep the end panels clear of it.
    var first = all[0]
    var second = all[1]
    var last = all[len(all) - 1]
    var before = all[len(all) - 2]
    _bar(
        sheets.wood,
        face.at(first, beam, w),
        face.at(second, top - beam, w),
        n,
        beam * 0.8,
        deep * 0.9,
        OAK,
    )
    _bar(
        sheets.wood,
        face.at(last, beam, w),
        face.at(before, top - beam, w),
        n,
        beam * 0.8,
        deep * 0.9,
        OAK,
    )


def _battens(
    mut sheets: _Sheets,
    face: _Face,
    openings: List[_Opening],
    half: Float32,
    out_sign: Float32,
):
    """Add a batten over each joint of a boarded wall's boards, cut at
    its openings."""
    var w = out_sign * half
    var n = face.normal * out_sign
    var step = BOARDS_TILE / 6
    var u = -half + step
    while u < face.length + half - 0.05:
        var spans = List[Tuple[Float32, Float32]]()
        var start = Float32(0)
        for o in openings:
            if u > o.u0 - 0.04 and u < o.u1 + 0.04:
                if o.v0 > start:
                    spans.append((start, o.v0))
                start = o.v1
        spans.append((start, face.height))
        # An opening fits in its wall, so each span has a length.
        for s in spans:  # pragma: no branch
            _bar(
                sheets.wood,
                face.at(u, s[0], w),
                face.at(u, s[1], w),
                n,
                0.05,
                0.025,
                WHITE * 0.75,
            )
        u += step


def _walls(
    mut sheets: _Sheets,
    building: Building,
    parameters: HouseParameters,
    eaves: Float32,
) raises:
    """Add every wall, its openings and its dressings."""
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        if element.kind != WALL:
            continue
        var id = ElementId(e)
        var face = _Face(building.wall_frame(id))
        var half = (
            Float32(
                building.constructions[element.construction.value().value]
                .thickness()
                .value
            )
            / 2
        )
        var exterior = building.is_exterior(id)
        ref topo = building.topology.complex.faces[element.faces[0].value]
        var out_sign = Float32(1) if not topo.positive else Float32(-1)
        var openings = _openings(building, id)
        _wall_faces(
            sheets,
            face,
            openings,
            half,
            out_sign,
            exterior,
            eaves,
            parameters.seed,
        )
        for o in openings:
            _reveals(sheets, face, o, half, out_sign, exterior)
            if o.door:
                _door_frame(sheets, face, o, half, out_sign, exterior)
            else:
                _window(sheets, face, o, half, out_sign, parameters)
        if not exterior:
            continue
        if parameters.facade == TIMBER_FRAMED:
            _timbers(sheets, face, openings, half, out_sign)
        elif parameters.facade == BOARDED:
            _battens(sheets, face, openings, half, out_sign)


def _rooms(mut sheets: _Sheets, building: Building) raises:
    """Add each room's floor of planks and its plastered ceiling, and the
    ground storey's joists."""
    var slab = Float32(0.2)
    for s in range(len(building.spaces)):
        ref space = building.spaces[s]
        ref storey = building.storeys[space.storey.value]
        var low = Float32(storey.elevation.value)
        var high = low + Float32(storey.height.value) - slab
        var x0 = Float32(1.0e9)
        var x1 = Float32(-1.0e9)
        var y0 = Float32(1.0e9)
        var y1 = Float32(-1.0e9)
        for p in space.outline:  # pragma: no branch
            x0 = min(x0, Float32(p.x))
            x1 = max(x1, Float32(p.x))
            y0 = min(y0, Float32(p.y))
            y1 = max(y1, Float32(p.y))
        # The scene's z is the model's -y.
        var z0 = -y1
        var z1 = -y0
        var floor = WHITE * 0.95
        sheets.planks.painted_quad(
            Vector3(x0, low, z1),
            Vector3(x1, low, z1),
            Vector3(x1, low, z0),
            Vector3(x0, low, z0),
            floor,
            floor,
            floor,
            floor,
            x0,
            -z1,
            x1,
            -z0,
        )
        var ceiling = INDOORS * 0.8
        sheets.plaster.painted_quad(
            Vector3(x0, high, z0),
            Vector3(x1, high, z0),
            Vector3(x1, high, z1),
            Vector3(x0, high, z1),
            ceiling,
            ceiling,
            ceiling,
            ceiling,
            x0,
            z0,
            x1,
            z1,
        )
        if space.storey.value != 0:
            continue
        # Oak joists under the ceiling, across the shorter span.
        var wide = (x1 - x0) >= (z1 - z0)
        var span = (x1 - x0) if wide else (z1 - z0)
        # A room is 2.4 meters across at least: four joists or more.
        var count = Int(span / 0.6)
        for k in range(1, count):  # pragma: no branch
            var t = Float32(k) / Float32(count)
            if wide:
                var x = x0 + (x1 - x0) * t
                sheets.wood.box(
                    Vector3(x, high - 0.08, (z0 + z1) / 2),
                    Vector3(0.05, 0, 0),
                    Vector3(0, 0.08, 0),
                    Vector3(0, 0, (z1 - z0) / 2),
                    OAK,
                )
            else:
                var z = z0 + (z1 - z0) * t
                sheets.wood.box(
                    Vector3((x0 + x1) / 2, high - 0.08, z),
                    Vector3((x1 - x0) / 2, 0, 0),
                    Vector3(0, 0.08, 0),
                    Vector3(0, 0, 0.05),
                    OAK,
                )


def _roof(
    mut sheets: _Sheets, parameters: HouseParameters, half_t: Float32
) raises:
    """Add the gable roof, its gables and its chimney."""
    var half_w = parameters.width.to(METER) / 2
    var half_d = parameters.depth.to(METER) / 2
    var base = parameters.storey_height.to(METER) * Float32(parameters.storeys)
    var slope = tan(parameters.pitch.to(RADIAN))
    var hx = half_w + half_t + VERGE
    var hz = half_d + half_t + EAVES
    # The underside passes over the long walls' outside faces at `base`.
    var lift = ROOF_DEPTH * sqrt(1 + slope * slope)
    var edge = half_d + half_t
    var ridge = base + slope * edge
    var eave = base - slope * EAVES
    var tint = parameters.roof
    var run = sqrt(hz * hz + (ridge - eave) * (ridge - eave))
    for side in range(2):  # pragma: no branch
        var sz = Float32(1) if side == 0 else Float32(-1)
        # The tiles: from the eave up to the ridge.
        var t0 = Vector3(-hx, eave + lift, sz * hz)
        var t1 = Vector3(hx, eave + lift, sz * hz)
        var t2 = Vector3(hx, ridge + lift, 0)
        var t3 = Vector3(-hx, ridge + lift, 0)
        var low = tint * 0.8
        var high = tint
        if sz > 0:
            sheets.roof.painted_quad(
                t0, t1, t2, t3, low, low, high, high, -hx, 0, hx, run
            )
        else:
            sheets.roof.painted_quad(
                t1, t0, t3, t2, low, low, high, high, -hx, 0, hx, run
            )
        # The boards under the eaves, facing down.
        var b0 = Vector3(-hx, eave, sz * hz)
        var b1 = Vector3(hx, eave, sz * hz)
        var b2 = Vector3(hx, ridge, 0)
        var b3 = Vector3(-hx, ridge, 0)
        if sz > 0:
            sheets.wood.quad(b1, b0, b3, b2, OAK * 0.8)
        else:
            sheets.wood.quad(b0, b1, b2, b3, OAK * 0.8)
        # The fascia along the eave.
        if sz > 0:
            sheets.wood.quad(
                b0, b1, t1 + Vector3(0, 0.02, 0), t0 + Vector3(0, 0.02, 0), OAK
            )
        else:
            sheets.wood.quad(
                b1, b0, t0 + Vector3(0, 0.02, 0), t1 + Vector3(0, 0.02, 0), OAK
            )
        # The barge boards up each verge.
        for end in range(2):  # pragma: no branch
            var sx = Float32(1) if end == 0 else Float32(-1)
            var p0 = Vector3(sx * hx, eave - 0.06, sz * hz)
            var p1 = Vector3(sx * hx, ridge - 0.06, 0)
            var p2 = Vector3(sx * hx, ridge + lift + 0.04, 0)
            var p3 = Vector3(sx * hx, eave + lift + 0.04, sz * hz)
            if sx * sz > 0:
                sheets.wood.quad(p0, p1, p2, p3, OAK)
            else:
                sheets.wood.quad(p1, p0, p3, p2, OAK)
    # The ridge: two strips of capping over the top.
    var top = ridge + lift
    for side in range(2):  # pragma: no branch
        var sz = Float32(1) if side == 0 else Float32(-1)
        var a = Vector3(-hx, top - 0.02, sz * 0.14)
        var b = Vector3(hx, top - 0.02, sz * 0.14)
        var c = Vector3(hx, top + 0.07, 0)
        var d = Vector3(-hx, top + 0.07, 0)
        var cap = tint * 0.7
        if sz > 0:
            sheets.roof.painted_quad(
                a, b, c, d, cap, cap, cap, cap, -hx, 0, hx, 0.2
            )
        else:
            sheets.roof.painted_quad(
                b, a, d, c, cap, cap, cap, cap, -hx, 0, hx, 0.2
            )
    # A gable at each end, over the end walls' outside faces.
    var gx = half_w + half_t
    for end in range(2):  # pragma: no branch
        var sx = Float32(1) if end == 0 else Float32(-1)
        var p0 = Vector3(sx * gx, base, _end_sign(end) * edge)
        var p1 = Vector3(sx * gx, base, -_end_sign(end) * edge)
        var p2 = Vector3(sx * gx, ridge, 0)
        var c0 = WHITE * outside_shade(0, base, ridge, parameters.seed)
        var c2 = WHITE * 0.75
        var n = Vector3(sx, 0, 0)
        var i0 = sheets.facade.vertex(p0, n, c0, p0.z * sx, p0.y)
        var i1 = sheets.facade.vertex(p1, n, c0, p1.z * sx, p1.y)
        var i2 = sheets.facade.vertex(p2, n, c2, p2.z * sx, p2.y)
        sheets.facade.triangle(i0, i1, i2)
        if parameters.facade == TIMBER_FRAMED:
            # A king post and two rafters' worth of oak on the gable.
            _bar(
                sheets.wood,
                Vector3(sx * gx, base, 0),
                Vector3(sx * gx, ridge - 0.1, 0),
                n,
                0.16,
                0.04,
                OAK,
            )
            _bar(
                sheets.wood,
                Vector3(sx * gx, base + 0.08, -edge),
                Vector3(sx * gx, base + 0.08, edge),
                n,
                0.16,
                0.04,
                OAK,
            )
    if parameters.facade != BRICK_FACADE and parameters.facade != STONE_FACADE:
        return
    # A chimney through the roof, over the hall's end.
    var cx = -half_w + 1.1
    var cz = Float32(0.45)
    var stack_top = ridge + 0.9
    var stack_foot = base - 0.1
    var stack = WHITE * 0.85
    sheets.facade.box(
        Vector3(cx, (stack_top + stack_foot) / 2, cz),
        Vector3(0.32, 0, 0),
        Vector3(0, (stack_top - stack_foot) / 2, 0),
        Vector3(0, 0, 0.26),
        stack,
    )
    sheets.ashlar.box(
        Vector3(cx, stack_top + 0.05, cz),
        Vector3(0.38, 0, 0),
        Vector3(0, 0.05, 0),
        Vector3(0, 0, 0.32),
        STONE,
    )
    sheets.ashlar.box(
        Vector3(cx, stack_top + 0.22, cz),
        Vector3(0.09, 0, 0),
        Vector3(0, 0.12, 0),
        Vector3(0, 0, 0.09),
        Vector3(0.75, 0.42, 0.3),
    )


def _end_sign(end: Int) -> Float32:
    """Return +1 for the first end of a gable, and -1 for the second: the
    sign that winds the gable's triangle to face out."""
    return Float32(1) if end == 0 else Float32(-1)


def _plinth(
    mut sheets: _Sheets, half_x: Float32, half_z: Float32, low: Float32
):
    """Add the stone plinth from `low` up to just below the floor."""
    var x = half_x + PLINTH_OVERHANG
    var z = half_z + PLINTH_OVERHANG
    var top = Float32(-0.005)
    var bottom = low - PLINTH_DEPTH
    var middle = (top + bottom) / 2
    var depth = (top - bottom) / 2
    sheets.ashlar.box(
        Vector3(0, middle, 0),
        Vector3(x, 0, 0),
        Vector3(0, depth, 0),
        Vector3(0, 0, z),
        STONE * 0.85,
    )


def _steps(
    mut sheets: _Sheets, interior: HouseInterior, lot: Lot, ground: Ground
):
    """Add a block of stone under each step of the interior's floors."""
    var c = cos(lot.turn)
    var s = sin(lot.turn)
    var floor = interior.floor_height
    for k in range(1, len(interior.floors)):
        ref step = interior.floors[k]
        ref area = step.area
        var dx = area.x - lot.x
        var dz = area.z - lot.z
        var x = dx * c - dz * s
        var z = dx * s + dz * c
        var turn = area.turn - lot.turn
        var ax = Vector3(cos(turn), 0, -sin(turn))
        var az = Vector3(sin(turn), 0, cos(turn))
        var top = step.height - floor
        var foot = ground.height_at(area.x, area.z) - floor - 0.3
        sheets.ashlar.box(
            Vector3(x, (top + foot) / 2, z),
            ax * area.half_width,
            Vector3(0, (top - foot) / 2, 0),
            az * area.half_depth,
            STONE * 0.9,
        )


def _block(
    mut sheet: Sheet,
    center: Vector3,
    side: Vector3,
    front: Vector3,
    half_width: Float32,
    half_height: Float32,
    half_depth: Float32,
    color: Vector3,
):
    """Add a box of a piece of furniture, `side` along its width and
    `front` along its depth, both of length one."""
    # Side, up and back turn the right way round.
    sheet.box(
        center,
        side * half_width,
        Vector3(0, half_height, 0),
        front * (-half_depth),
        color,
    )


def _legs(
    mut sheet: Sheet,
    center: Vector3,
    side: Vector3,
    front: Vector3,
    half_width: Float32,
    half_depth: Float32,
    inset: Float32,
    tall: Float32,
    thick: Float32,
    color: Vector3,
):
    """Add four legs, `inset` in from the corners, `tall` high."""
    for k in range(4):  # pragma: no branch
        var sx = Float32(1) if k % 2 == 0 else Float32(-1)
        var sz = Float32(1) if k < 2 else Float32(-1)
        _block(
            sheet,
            center
            + side * (sx * (half_width - inset))
            + front * (sz * (half_depth - inset))
            + Vector3(0, tall / 2, 0),
            side,
            front,
            thick,
            tall / 2,
            thick,
            color,
        )


def _piece(
    mut sheets: _Sheets,
    kind: FurnitureKind,
    center: Vector3,
    side: Vector3,
    front: Vector3,
    width: Float32,
    depth: Float32,
    height: Float32,
    seed: Int,
):
    """Add one piece of furniture: `side` runs along its width and
    `front` toward the side it is used from, both of length one."""
    var hw = width / 2
    var hd = depth / 2
    var wood = OAK * (1.1 + 0.2 * Float32(seed % 3))
    var cloth = Vector3(0.9, 0.85, 0.75)
    var up = Vector3(0, 1, 0)
    if kind == TABLE or kind == COFFEE_TABLE or kind == DESK:
        var top = Float32(0.05)
        _legs(
            sheets.wood,
            center,
            side,
            front,
            hw,
            hd,
            0.08,
            height - top,
            0.035,
            wood,
        )
        _block(
            sheets.wood,
            center + up * (height - top / 2),
            side,
            front,
            hw,
            top / 2,
            hd,
            wood,
        )
        return
    if kind == CHAIR:
        var seat = Float32(0.45)
        _legs(sheets.wood, center, side, front, hw, hd, 0.06, seat, 0.02, wood)
        _block(
            sheets.wood,
            center + up * (seat + 0.02),
            side,
            front,
            hw * 0.85,
            0.02,
            hd * 0.85,
            wood,
        )
        # The back, behind the seat.
        _block(
            sheets.wood,
            center - front * (hd * 0.8) + up * ((seat + height) / 2),
            side,
            front,
            hw * 0.85,
            (height - seat) / 2,
            0.02,
            wood,
        )
        return
    if kind == BED:
        _legs(sheets.wood, center, side, front, hw, hd, 0.06, 0.25, 0.04, wood)
        _block(sheets.wood, center + up * 0.28, side, front, hw, 0.05, hd, wood)
        _block(
            sheets.plaster,
            center + up * 0.4,
            side,
            front,
            hw - 0.04,
            0.08,
            hd - 0.04,
            cloth,
        )
        # The blanket over the foot of the bed, a pillow at its head, and
        # the headboard.
        _block(
            sheets.wood,
            center + front * (hd * 0.25) + up * 0.49,
            side,
            front,
            hw - 0.02,
            0.02,
            hd * 0.72,
            painted(Vector3(0.25, 0.04, 0.03)) * 0.9,
        )
        _block(
            sheets.plaster,
            center - front * (hd - 0.25) + up * 0.52,
            side,
            front,
            hw - 0.2,
            0.05,
            0.15,
            cloth,
        )
        _block(
            sheets.wood,
            center - front * (hd - 0.03) + up * 0.5,
            side,
            front,
            hw,
            0.5,
            0.03,
            wood,
        )
        return
    if kind == SOFA:
        # A settle: a bench with a high back, arms and a cushion.
        _block(sheets.wood, center + up * 0.22, side, front, hw, 0.22, hd, wood)
        _block(
            sheets.wood,
            center - front * (hd - 0.05) + up * (height / 2 + 0.2),
            side,
            front,
            hw,
            height / 2 + 0.2,
            0.05,
            wood,
        )
        for sx in [Float32(1), Float32(-1)]:  # pragma: no branch
            _block(
                sheets.wood,
                center + side * (sx * (hw - 0.04)) + up * 0.32,
                side,
                front,
                0.04,
                0.32,
                hd,
                wood,
            )
        _block(
            sheets.plaster,
            center + front * 0.05 + up * 0.47,
            side,
            front,
            hw - 0.1,
            0.03,
            hd - 0.15,
            painted(Vector3(0.08, 0.12, 0.2)),
        )
        return
    if kind == SHELF:
        _block(
            sheets.wood,
            center - front * (hd - 0.02) + up * (height / 2),
            side,
            front,
            hw,
            height / 2,
            0.02,
            wood * 0.9,
        )
        for sx in [Float32(1), Float32(-1)]:  # pragma: no branch
            _block(
                sheets.wood,
                center + side * (sx * (hw - 0.02)) + up * (height / 2),
                side,
                front,
                0.02,
                height / 2,
                hd,
                wood,
            )
        for k in range(5):  # pragma: no branch
            var y = 0.05 + Float32(k) * (height - 0.1) / 4
            _block(
                sheets.wood, center + up * y, side, front, hw, 0.015, hd, wood
            )
            if k < 4:
                # Jars and pots on the shelf.
                _block(
                    sheets.ashlar,
                    center + side * (hw * 0.4) + up * (y + 0.1),
                    side,
                    front,
                    hw * 0.35,
                    0.08,
                    hd * 0.6,
                    Vector3(0.7, 0.55, 0.45),
                )
        return
    # A cabinet, a wardrobe, a nightstand, a counter, a sink or a toilet:
    # a carcass with a top and two doors.
    _block(
        sheets.wood,
        center + up * (height / 2 - 0.02),
        side,
        front,
        hw,
        height / 2 - 0.02,
        hd,
        wood * 0.9,
    )
    var lid = center + up * (height - 0.02)
    if kind == COUNTER or kind == SINK or kind == TOILET:
        _block(
            sheets.ashlar, lid, side, front, hw + 0.02, 0.02, hd + 0.02, STONE
        )
    else:
        _block(sheets.wood, lid, side, front, hw + 0.02, 0.02, hd + 0.02, wood)
    for sx in [Float32(1), Float32(-1)]:  # pragma: no branch
        _block(
            sheets.wood,
            center
            + side * (sx * hw / 2)
            + front * (hd + 0.01)
            + up * (height / 2),
            side,
            front,
            hw / 2 - 0.03,
            height / 2 - 0.08,
            0.01,
            wood * 1.1,
        )


def _furniture(mut sheets: _Sheets, building: Building):
    """Add each furnishing of the model."""
    for index in range(len(building.furnishings)):
        ref piece = building.furnishings[index]
        ref storey = building.storeys[
            building.spaces[piece.space.value].storey.value
        ]
        var r = Float32(piece.rotation.value)
        # The piece's own x and y in the model, in the house's frame.
        var side = Vector3(cos(r), 0, -sin(r))
        var front = Vector3(-sin(r), 0, -cos(r))
        var center = Vector3(
            Float32(piece.center.x),
            Float32(storey.elevation.value),
            -Float32(piece.center.y),
        )
        _piece(
            sheets,
            piece.kind,
            center,
            side,
            front,
            Float32(piece.width.value),
            Float32(piece.depth.value),
            Float32(piece.height.value),
            index,
        )


struct StandingHouse(Movable):
    """A house in a scene: its node, what it draws, where a character can
    walk in it, and its doors' hinges."""

    var root: NodeId
    var meshes: Int
    var triangles: Int
    var interior: HouseInterior
    # The hinge of each door leaf of the ground storey, in the order of
    # `interior.doorways`.
    var hinges: List[Hinge]

    def __init__(
        out self,
        root: NodeId,
        meshes: Int,
        triangles: Int,
        var interior: HouseInterior,
        var hinges: List[Hinge],
    ):
        """Hold a house in a scene.

        Args:
            root: The house's node.
            meshes: How many meshes it added.
            triangles: How many triangles they hold.
            interior: Where a character can walk in it.
            hinges: The hinge of each door leaf of the ground storey.
        """
        self.root = root
        self.meshes = meshes
        self.triangles = triangles
        self.interior = interior^
        self.hinges = hinges^


def _add(
    mut scene: Scene,
    mut assets: Assets,
    sheet: Sheet,
    material: MaterialId,
    parent: NodeId,
    casts: Bool,
) raises -> Int:
    """Add a sheet as a mesh under a node, and return its triangles."""
    if sheet.triangles() == 0:
        return 0
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sheet.geometry()),
            material,
            parent,
            cast_shadow=casts,
            receive_shadow=True,
        )
    )
    return sheet.triangles()


def facade_look(looks: HouseLooks, facade: Facade) -> MaterialId:
    """Return the material of a facade's outside walls.

    Args:
        looks: The village's materials.
        facade: The facade.

    Returns:
        Brick, fieldstone, lime plaster or boards.
    """
    if facade == STONE_FACADE:
        return looks.fieldstone
    if facade == TIMBER_FRAMED:
        return looks.plaster
    if facade == BOARDED:
        return looks.boards
    return looks.brick


def stand_house(
    mut scene: Scene,
    mut assets: Assets,
    looks: HouseLooks,
    parameters: HouseParameters,
    building: Building,
    lot: Lot,
    ground: Ground,
) raises -> StandingHouse:
    """Add a house to a scene, standing on the ground on its lot.

    The model's +x runs along the lot's width and its +y along the lot's
    -z, both turned by the lot's turn. The ground floor stands at the
    highest of the ground under the lot's corners, on a stone plinth that
    reaches down below the lowest. Steps lead up to each outside door.

    Args:
        scene: The scene.
        assets: The stores for the geometries.
        looks: The village's materials.
        parameters: The house.
        building: The house's model.
        lot: Where it stands: its middle, its half sizes and its turn.
        ground: The ground it stands on.

    Returns:
        The house's node, what it draws, its interior and its doors.

    Raises:
        Error: If the house cannot be drawn.
    """
    var feet = footing(lot, ground)
    var floor = feet[1]
    var interior = house_interior(building, lot, floor, ground)
    var stand = Object3D()
    stand.name = building.name
    stand.set_position(lot.x, floor, lot.z)
    stand.rotate_y(Angle(lot.turn, RADIAN))
    var root = scene.add(stand^)
    var sheets = _Sheets(parameters.facade)
    var half_x = parameters.width.to(METER) / 2
    var half_z = parameters.depth.to(METER) / 2
    var top = parameters.storey_height.to(METER) * Float32(parameters.storeys)
    _walls(sheets, building, parameters, top)
    _rooms(sheets, building)
    var half_t = Float32(building.constructions[0].thickness().value) / 2
    if parameters.pitch.to(RADIAN) > 0:
        _roof(sheets, parameters, half_t)
    _plinth(sheets, half_x, half_z, feet[0] - floor)
    _steps(sheets, interior, lot, ground)
    if parameters.facade == BRICK_FACADE or parameters.facade == STONE_FACADE:
        _quoins(sheets, half_x + half_t, half_z + half_t, top)
    _furniture(sheets, building)
    var roof = (
        looks.slates if parameters.facade == STONE_FACADE else looks.tiles
    )
    var before = len(scene.meshes)
    var triangles = 0
    triangles += _add(
        scene,
        assets,
        sheets.facade,
        facade_look(looks, parameters.facade),
        root,
        True,
    )
    triangles += _add(scene, assets, sheets.plaster, looks.plaster, root, True)
    triangles += _add(scene, assets, sheets.wood, looks.wood, root, True)
    triangles += _add(scene, assets, sheets.ashlar, looks.ashlar, root, True)
    triangles += _add(scene, assets, sheets.roof, roof, root, True)
    triangles += _add(scene, assets, sheets.planks, looks.planks, root, False)
    triangles += _add(scene, assets, sheets.glass, looks.glass, root, False)
    triangles += _add(
        scene, assets, sheets.daylight, looks.daylight, root, False
    )
    # A leaf on a hinge for each door of the ground storey, in the order
    # of the interior's doorways.
    var hinges = List[Hinge]()
    var paint = painted(parameters.trim)
    for index in range(len(building.openings)):  # pragma: no branch
        ref o = building.openings[index]
        if o.kind != DOOR:
            continue
        ref host = building.elements[o.host.value]
        var face = _Face(building.wall_frame(o.host))
        var width = Float32(o.width.value)
        var height = Float32(o.height.value)
        var exterior = building.is_exterior(o.host)
        ref topo = building.topology.complex.faces[host.faces[0].value]
        var out_sign = Float32(1) if not topo.positive else Float32(-1)
        var plane = Float32(0)
        if exterior:
            plane = out_sign * (half_t - Float32(FRAME_INSET) - 0.03)
        var at = face.at(Float32(o.offset.value), Float32(o.sill.value), plane)
        var shut = atan2(-face.along.z, face.along.x)
        # The leaf's -z, turned shut, is (-sin shut, 0, -cos shut). An
        # outside door swings into the house; an inside one along the
        # wall's normal.
        var swing = face.normal * (-out_sign if exterior else Float32(1))
        # The leaf's -z is along the wall's normal, one way or the other,
        # so `toward` is 1 or -1.
        var toward = -sin(shut) * swing.x - cos(shut) * swing.z
        var sense = toward / abs(toward)
        var node = Object3D()
        node.set_position(at.x, at.y, at.z)
        node.rotate_y(Angle(shut, RADIAN))
        node.parent = root
        var hinge = scene.add(node^)
        var leaf = door_leaf(
            width - 0.02, height - 0.01, paint if exterior else OAK
        )
        triangles += _add(scene, assets, leaf, looks.wood, hinge, True)
        if host.storey.value == 0:
            hinges.append(Hinge(hinge, shut, sense))
    var meshes = len(scene.meshes) - before
    return StandingHouse(root, meshes, triangles, interior^, hinges^)
