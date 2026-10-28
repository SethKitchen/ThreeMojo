# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's render view of a house: its walls, its windows and
doors, its roof, its plinth and steps, and its furniture, as a game and
a still picture draw them.

`stand_house` reads a house's canonical building model, as the general
render view `extensions.building.views.render` does, and never writes
it. It draws more of what an eye sees from close by:

1. **Walls.** Each face of each wall is cut into cells at the edges of
   its openings, and no cell is wider or taller than `CELL`. The outside
   face wears the facade's texture. Its vertex colors darken it at its
   foot, where rain splashes, and under the eaves. The inside face wears
   lime plaster, or bare boards in a barn, darker in the corners of the
   room, where less light reaches. Each opening has reveals through the
   wall.
2. **Dressings.** A brick house has stone quoins at its corners, stone
   sills and stone lintels. A stone house has oak lintels. A framed house
   has oak posts, rails and braces over its plaster. A boarded house's
   texture has battens over the joints of its boards. A window has a
   painted frame, a mullion and a transom, panes of glass and a pair of
   open shutters. A door has an oak frame, a stone threshold, and a leaf
   of boards on ledges that turns on its own hinge node. A door
   `DOUBLE_DOOR` wide or wider has two leaves, one at each jamb.
3. **Floors and ceilings.** Each room has a floor of planks and a
   plastered ceiling, or a ceiling of planks in a barn. The ground
   storey's ceiling has oak joists.
4. **The stair.** Where `house_stair` finds a stair, it has oak treads
   and risers, a stringer on its open side, and a handrail on
   balusters. Its well is cut out of the hall's ceiling and the floor
   above, with oak trimmers round it. A balustrade guards the well
   upstairs.
5. **The roof.** A gable roof covers the flat roof of the model: two
   slopes of tiles or slates with a thickness, boards under the eaves, a
   fascia, barge boards and a ridge. A gable closes each end, cut into
   cells as a wall is. A chimney stands over a chimney breast. A barn
   has a loft door in its east gable, and a hoist beam over it.
6. **The plinth and the steps.** A stone plinth reaches from just below
   the floor to below the lowest ground. Each step of the interior's
   floors is a block of stone.
7. **Furniture.** Each furnishing of the model is drawn as its kind:
   a table on legs, a chair with a back, a bed with its blanket, and so
   on. In a barn, a shelf is a stack of straw bales, and any other piece
   is a manger with a rack over it.

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
    CABINET,
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
    BARN,
    BOARDED,
    BRICK_FACADE,
    Breast,
    Facade,
    HouseParameters,
    STAIR_GOING,
    STONE_FACADE,
    Stair,
    TIMBER_FRAMED,
    footing,
    house_breast,
    house_stair,
)
from extensions.village.interior import (
    HouseInterior,
    PLINTH_OVERHANG,
    RAIL_HEIGHT,
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
from std.math import atan2, ceil, cos, sin, sqrt, tan
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
comptime SOOT = Vector3(0.1, 0.085, 0.075)
"""The tint of the blackened stone at the back of a fire."""
comptime EMBERS = Vector3(1.0, 0.38, 0.08)
"""The color of glowing embers, drawn unlit."""
comptime FIREBOX_HEIGHT = Float32(0.85)
"""How high a fireplace's opening is, in meters."""
comptime FIREBOX_HALF = Float32(0.45)
"""Half the width of a fireplace's opening, in meters."""
comptime DOUBLE_DOOR = Float32(2)
"""The narrowest door that hangs two leaves, one at each jamb, in
meters."""
comptime BRACED_LEAF = Float32(1.2)
"""The narrowest door leaf that has diagonal braces between its ledges,
in meters."""
comptime STRAW = Vector3(1.0, 0.82, 0.42)
"""The tint of straw over the plaster texture, as the hay props have."""
comptime BALE = Vector3(0.9, 0.4, 0.45)
"""A bale of straw's length, height and width, in meters."""
comptime LOFT_DOOR = Vector3(1.4, 1.5, 0)
"""A barn's loft door's width and its most height, in meters."""


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
    # Which of the interior's doorways the leaf hangs in.
    var door: Int


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


def _inside_face(
    mut sheet: Sheet,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    d: Vector3,
    k0: Vector3,
    k1: Vector3,
    k2: Vector3,
    k3: Vector3,
    u0: Float32,
    u1: Float32,
    v0: Float32,
    v1: Float32,
    sign: Float32,
):
    """Add one inside cell of a wall, from `a` to `d` along the wall and up,
    facing along the normal when `sign` is +1 and against it when -1."""
    if sign > 0:
        sheet.painted_quad(a, b, c, d, k0, k1, k2, k3, u0, v0, u1, v1)
    else:
        sheet.painted_quad(b, a, d, c, k1, k0, k3, k2, -u1, v0, -u0, v1)


def _wall_faces(
    mut sheets: _Sheets,
    face: _Face,
    openings: List[_Opening],
    half: Float32,
    out_sign: Float32,
    exterior: Bool,
    eaves: Float32,
    seed: Int,
    boards: Bool,
):
    """Add a wall's two faces, cut into cells round its openings.

    `out_sign` is +1 when the outside is along the normal, and -1 when it
    is against it. The inside faces are plaster, or bare boards when
    `boards` is True."""
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
                if boards:
                    _inside_face(
                        sheets.facade,
                        a,
                        b,
                        c,
                        d,
                        k0,
                        k1,
                        k2,
                        k3,
                        u0,
                        u1,
                        v0,
                        v1,
                        sign,
                    )
                else:
                    _inside_face(
                        sheets.plaster,
                        a,
                        b,
                        c,
                        d,
                        k0,
                        k1,
                        k2,
                        k3,
                        u0,
                        u1,
                        v0,
                        v1,
                        sign,
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

    A leaf has at least four boards, each at most 25 centimeters wide. A
    leaf `BRACED_LEAF` wide or wider has diagonal braces between its
    ledges.

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
    var boards = max(4, Int(width / 0.25))
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
    # A wide leaf has a brace between each two ledges, rising from the
    # hinge's side, so it does not sag.
    if width >= BRACED_LEAF:
        for k in range(2):  # pragma: no branch
            var y0 = 0.2 + Float32(k) * (height - 0.4) / 2 + 0.07
            var y1 = 0.2 + Float32(k + 1) * (height - 0.4) / 2 - 0.07
            var run = Vector3(width - 0.2, y1 - y0, 0)
            var long = run.length()
            sheet.box(
                Vector3(width / 2, (y0 + y1) / 2, -0.035),
                run * 0.5,
                Vector3(-run.y, run.x, 0) * (0.06 / long),
                Vector3(0, 0, 0.015),
                paint * 0.8,
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
            parameters.use == BARN,
        )
        for o in openings:
            _reveals(sheets, face, o, half, out_sign, exterior)
            if o.door:
                _door_frame(sheets, face, o, half, out_sign, exterior)
            else:
                _window(sheets, face, o, half, out_sign, parameters)
        if not exterior:
            continue
        # A boarded wall's battens are in its texture.
        if parameters.facade == TIMBER_FRAMED:
            _timbers(sheets, face, openings, half, out_sign)


@fieldwise_init
struct _Rect(ImplicitlyCopyable):
    """A rectangle in the house's frame: from `x0` to `x1` along x, and
    from `z0` to `z1` along z, the model's -y."""

    var x0: Float32
    var x1: Float32
    var z0: Float32
    var z1: Float32


def _well(stair: Stair) -> _Rect:
    """Return a stair's well in the house's frame: where it rises through
    the floor above."""
    return _Rect(
        Float32(stair.x0),
        Float32(stair.x1),
        -Float32(stair.y1),
        -Float32(stair.y0),
    )


def _around(room: _Rect, hole: _Rect) -> List[_Rect]:
    """Return four rectangles that cover a room but for a hole inside it:
    before the hole, behind it, and either side of it."""
    return [
        _Rect(room.x0, room.x1, room.z0, hole.z0),
        _Rect(room.x0, room.x1, hole.z1, room.z1),
        _Rect(room.x0, hole.x0, hole.z0, hole.z1),
        _Rect(hole.x1, room.x1, hole.z0, hole.z1),
    ]


def _ceiling(mut sheet: Sheet, r: _Rect, high: Float32, color: Vector3):
    """Add a ceiling over a rectangle at a height, facing down."""
    sheet.painted_quad(
        Vector3(r.x0, high, r.z0),
        Vector3(r.x1, high, r.z0),
        Vector3(r.x1, high, r.z1),
        Vector3(r.x0, high, r.z1),
        color,
        color,
        color,
        color,
        r.x0,
        r.z0,
        r.x1,
        r.z1,
    )


def _rooms(
    mut sheets: _Sheets,
    building: Building,
    stair: Optional[Stair],
    barn: Bool,
) raises:
    """Add each room's floor of planks and its plastered ceiling, and the
    ground storey's joists. A barn's ceilings are planks. A stair's well
    is cut out of the ceiling of the room it rises from and the floor of
    the room above."""
    var slab = Float32(0.2)
    var hole = _Rect(0, 0, 0, 0)
    if stair:
        hole = _well(stair.value())
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
        var room = _Rect(x0, x1, -y1, -y0)
        var floors: List[_Rect] = [room]
        if Bool(stair) and space.storey.value == 1:
            floors = _around(room, hole)
        # The stair rises from the hall, the first room of the ground
        # storey.
        var ceilings: List[_Rect] = [room]
        var under = Bool(stair) and s == 0
        if under:
            ceilings = _around(room, hole)
        var floor = WHITE * 0.95
        for r in floors:  # pragma: no branch
            sheets.planks.painted_quad(
                Vector3(r.x0, low, r.z1),
                Vector3(r.x1, low, r.z1),
                Vector3(r.x1, low, r.z0),
                Vector3(r.x0, low, r.z0),
                floor,
                floor,
                floor,
                floor,
                r.x0,
                -r.z1,
                r.x1,
                -r.z0,
            )
        var ceiling = INDOORS * 0.8
        for r in ceilings:  # pragma: no branch
            if barn:
                _ceiling(sheets.planks, r, high, ceiling * 0.8)
            else:
                _ceiling(sheets.plaster, r, high, ceiling)
        if space.storey.value != 0:
            continue
        var z0 = room.z0
        var z1 = room.z1
        # Oak joists under the ceiling, across the shorter span. Under a
        # stair's well they run along it, and a joist over the well is left
        # out: trimmers frame it.
        var wide = not under and (x1 - x0) >= (z1 - z0)
        var span = (x1 - x0) if wide else (z1 - z0)
        # A room is 2.4 meters across at least: four joists or more.
        var count = Int(span / 0.6)
        for k in range(1, count):  # pragma: no branch
            var t = Float32(k) / Float32(count)
            var joist: _Rect
            if wide:
                var x = x0 + (x1 - x0) * t
                joist = _Rect(x - 0.05, x + 0.05, z0, z1)
            else:
                var z = z0 + (z1 - z0) * t
                joist = _Rect(x0, x1, z - 0.05, z + 0.05)
            if under and joist.z0 < hole.z1:
                continue
            sheets.wood.box(
                Vector3(
                    (joist.x0 + joist.x1) / 2,
                    high - 0.08,
                    (joist.z0 + joist.z1) / 2,
                ),
                Vector3((joist.x1 - joist.x0) / 2, 0, 0),
                Vector3(0, 0.08, 0),
                Vector3(0, 0, (joist.z1 - joist.z0) / 2),
                OAK,
            )
        if under:
            _trimmers(sheets, hole, high, low + Float32(storey.height.value))


def _trimmers(mut sheets: _Sheets, hole: _Rect, low: Float32, high: Float32):
    """Add oak trimmers round the open sides of a stair's well, from the
    ceiling below it at `low` to the floor above it at `high`."""
    var middle = (low + high) / 2
    var half = (high - low) / 2
    var center_x = (hole.x0 + hole.x1) / 2
    var center_z = (hole.z0 + hole.z1) / 2
    # Along the open side, and across the foot and the top.
    sheets.wood.box(
        Vector3(center_x, middle, hole.z1 + 0.05),
        Vector3((hole.x1 - hole.x0) / 2 + 0.1, 0, 0),
        Vector3(0, half, 0),
        Vector3(0, 0, 0.05),
        OAK,
    )
    for x in [hole.x0 - 0.05, hole.x1 + 0.05]:  # pragma: no branch
        sheets.wood.box(
            Vector3(x, middle, center_z),
            Vector3(0.05, 0, 0),
            Vector3(0, half, 0),
            Vector3(0, 0, (hole.z1 - hole.z0) / 2),
            OAK,
        )


def _stair_view(mut sheets: _Sheets, stair: Stair):
    """Add a stair: its treads and risers, a stringer on its open side, a
    handrail on balusters, and a balustrade round its well upstairs."""
    var hole = _well(stair)
    var rise = Float32(stair.rise)
    var going = Float32(STAIR_GOING)
    var top = Float32(stair.height())
    var middle_z = (hole.z0 + hole.z1) / 2
    var half_z = (hole.z1 - hole.z0) / 2
    var treads = stair.risers - 1
    # `house_stair` gives a stair two risers or more: a tread or more.
    for k in range(treads):  # pragma: no branch
        var x = hole.x0 + Float32(k) * going
        var height = Float32(k + 1) * rise
        # The tread, with a nosing over the riser below it.
        sheets.planks.box(
            Vector3(x + going / 2 - 0.015, height - 0.02, middle_z),
            Vector3(going / 2 + 0.015, 0, 0),
            Vector3(0, 0.02, 0),
            Vector3(0, 0, half_z),
            WHITE * 0.8,
        )
        sheets.wood.box(
            Vector3(x + 0.01, height - rise / 2, middle_z),
            Vector3(0.01, 0, 0),
            Vector3(0, rise / 2, 0),
            Vector3(0, 0, half_z),
            OAK * 0.85,
        )
    # The last riser, up to the floor above.
    sheets.wood.box(
        Vector3(hole.x1 + 0.01, top - rise / 2, middle_z),
        Vector3(0.01, 0, 0),
        Vector3(0, rise / 2, 0),
        Vector3(0, 0, half_z),
        OAK * 0.85,
    )
    # The stringer along the open side, under the treads' line, and the
    # handrail over it, both on the slope from the foot to the top.
    var run = hole.x1 - hole.x0
    var length = sqrt(run * run + top * top)
    var up = Vector3(-top / length, run / length, 0)
    var slope = Vector3(run / 2, top / 2, 0)
    var side = hole.z1 - 0.04
    sheets.wood.box(
        Vector3(hole.x0 + run / 2, top / 2 - 0.05, side),
        slope,
        up * 0.14,
        Vector3(0, 0, 0.03),
        OAK * 0.9,
    )
    var rail = RAIL_HEIGHT - 0.1
    sheets.wood.box(
        Vector3(hole.x0 + run / 2, top / 2 + rail, side),
        slope,
        up * 0.035,
        Vector3(0, 0, 0.035),
        OAK,
    )
    # A baluster on every second tread, from the tread to the handrail.
    for k in range(0, treads, 2):  # pragma: no branch
        var x = hole.x0 + (Float32(k) + 0.5) * going
        var foot = Float32(k + 1) * rise
        var head = (x - hole.x0) / run * top + rail
        sheets.wood.box(
            Vector3(x, (foot + head) / 2, side),
            Vector3(0.02, 0, 0),
            Vector3(0, (head - foot) / 2, 0),
            Vector3(0, 0, 0.02),
            OAK,
        )
    # A newel post at the foot.
    sheets.wood.box(
        Vector3(hole.x0 - 0.05, (rail + 0.1) / 2, side),
        Vector3(0.05, 0, 0),
        Vector3(0, (rail + 0.1) / 2, 0),
        Vector3(0, 0, 0.05),
        OAK * 0.8,
    )
    # Upstairs, a balustrade along the well's open side and across its
    # foot: a rail on posts, standing on the floor's edge.
    var guard = top + RAIL_HEIGHT
    var edge = hole.z1 + 0.04
    sheets.wood.box(
        Vector3(hole.x0 + run / 2, guard - 0.03, edge),
        Vector3(run / 2 + 0.04, 0, 0),
        Vector3(0, 0.03, 0),
        Vector3(0, 0, 0.04),
        OAK,
    )
    sheets.wood.box(
        Vector3(hole.x0 - 0.04, guard - 0.03, middle_z),
        Vector3(0.04, 0, 0),
        Vector3(0, 0.03, 0),
        Vector3(0, 0, half_z),
        OAK,
    )
    var posts = Int(run / 0.5)
    for k in range(posts + 1):  # pragma: no branch
        var x = hole.x0 + run * Float32(k) / Float32(posts)
        sheets.wood.box(
            Vector3(x, top + RAIL_HEIGHT / 2, edge),
            Vector3(0.025, 0, 0),
            Vector3(0, RAIL_HEIGHT / 2, 0),
            Vector3(0, 0, 0.025),
            OAK,
        )
    for k in range(1, 3):  # pragma: no branch
        var z = hole.z1 - Float32(k) * (hole.z1 - hole.z0) / 3
        sheets.wood.box(
            Vector3(hole.x0 - 0.04, top + RAIL_HEIGHT / 2, z),
            Vector3(0.025, 0, 0),
            Vector3(0, RAIL_HEIGHT / 2, 0),
            Vector3(0, 0, 0.025),
            OAK,
        )


def _cube(
    mut sheet: Sheet,
    x0: Float32,
    x1: Float32,
    y0: Float32,
    y1: Float32,
    z0: Float32,
    z1: Float32,
    color: Vector3,
):
    """Add a box from `x0` to `x1`, `y0` to `y1` and `z0` to `z1` in the
    house's frame."""
    sheet.box(
        Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        Vector3((x1 - x0) / 2, 0, 0),
        Vector3(0, (y1 - y0) / 2, 0),
        Vector3(0, 0, (z1 - z0) / 2),
        color,
    )


def _breast_view(mut sheets: _Sheets, building: Building, breast: Breast):
    """Add a chimney breast up through every storey, and on the ground
    storey its fireplace: a stone surround, an oak mantel, a sooty back, a
    stone hearth, logs and glowing embers."""
    var back = Float32(breast.x0)
    var face = Float32(breast.x1)
    # The scene's z is the model's -y.
    var z0 = -Float32(breast.y1)
    var z1 = -Float32(breast.y0)
    var mid = (z0 + z1) / 2
    var plaster = INDOORS * 0.9
    for s in range(len(building.storeys)):  # pragma: no branch
        ref storey = building.storeys[s]
        var low = Float32(storey.elevation.value)
        var high = low + Float32(storey.height.value)
        if s != 0:
            _cube(sheets.plaster, back, face, low, high, z0, z1, plaster)
            continue
        var opening = low + FIREBOX_HEIGHT
        var lintel = opening + 0.2
        # The jambs either side of the opening, the lintel over it, and the
        # plastered breast over the mantel.
        _cube(
            sheets.ashlar,
            back,
            face,
            low,
            opening,
            z0,
            mid - FIREBOX_HALF,
            STONE,
        )
        _cube(
            sheets.ashlar,
            back,
            face,
            low,
            opening,
            mid + FIREBOX_HALF,
            z1,
            STONE,
        )
        _cube(sheets.ashlar, back, face + 0.02, opening, lintel, z0, z1, STONE)
        _cube(sheets.plaster, back, face, lintel, high, z0, z1, plaster)
        _cube(
            sheets.wood,
            face - 0.04,
            face + 0.14,
            lintel,
            lintel + 0.06,
            z0 - 0.06,
            z1 + 0.06,
            OAK,
        )
        # The sooty back of the fire, and the stone hearth before it.
        _cube(
            sheets.ashlar,
            back,
            back + 0.1,
            low,
            opening,
            mid - FIREBOX_HALF,
            mid + FIREBOX_HALF,
            SOOT,
        )
        _cube(
            sheets.ashlar,
            back + 0.1,
            face + 0.45,
            low,
            low + 0.03,
            mid - FIREBOX_HALF - 0.3,
            mid + FIREBOX_HALF + 0.3,
            STONE * 0.8,
        )
        # Glowing embers under two logs, and the fire's glow on the back.
        _cube(
            sheets.daylight,
            back + 0.16,
            back + 0.44,
            low + 0.03,
            low + 0.07,
            mid - 0.25,
            mid + 0.25,
            EMBERS,
        )
        for k in range(2):  # pragma: no branch
            var x = back + 0.22 + Float32(k) * 0.16
            _cube(
                sheets.wood,
                x - 0.05,
                x + 0.05,
                low + 0.06,
                low + 0.15,
                mid - 0.28,
                mid + 0.28,
                OAK * 0.5,
            )
        # The glow is brightest over the embers and fades up the back.
        var bright = EMBERS * 0.7
        var dim = EMBERS * 0.05
        sheets.daylight.painted_quad(
            Vector3(back + 0.101, low + 0.05, mid + 0.38),
            Vector3(back + 0.101, low + 0.05, mid - 0.38),
            Vector3(back + 0.101, opening - 0.02, mid - 0.38),
            Vector3(back + 0.101, opening - 0.02, mid + 0.38),
            bright,
            bright,
            dim,
            dim,
            0,
            0,
            1,
            1,
        )


def _gable(
    mut sheet: Sheet,
    x: Float32,
    sense: Float32,
    n: Vector3,
    base: Float32,
    ridge: Float32,
    edge: Float32,
    low: Vector3,
    high: Vector3,
):
    """Add a gable's triangle at `x`, from `base` up to `ridge`, `edge` to
    each side at its foot, cut into rows and cells no more than `CELL`
    across, so each cell reads its texture at the level it needs. Its
    color runs from `low` at its foot to `high` at its peak, and its foot
    runs from `sense * edge` to `-sense * edge`."""
    var rows = max(1, Int(ceil((ridge - base) / Float32(CELL))))
    var cols = max(1, Int(ceil(2 * edge / Float32(CELL))))
    for k in range(rows):  # pragma: no branch
        var f0 = Float32(k) / Float32(rows)
        var f1 = Float32(k + 1) / Float32(rows)
        var y0 = base + (ridge - base) * f0
        var y1 = base + (ridge - base) * f1
        var w0 = edge * (1 - f0)
        var w1 = edge * (1 - f1)
        var k0 = low + (high - low) * f0
        var k1 = low + (high - low) * f1
        for i in range(cols):  # pragma: no branch
            var g0 = 1 - 2 * Float32(i) / Float32(cols)
            var g1 = 1 - 2 * Float32(i + 1) / Float32(cols)
            var a = Vector3(x, y0, sense * w0 * g0)
            var b = Vector3(x, y0, sense * w0 * g1)
            var c = Vector3(x, y1, sense * w1 * g1)
            var d = Vector3(x, y1, sense * w1 * g0)
            var ia = sheet.vertex(a, n, k0, a.z * n.x, a.y)
            var ib = sheet.vertex(b, n, k0, b.z * n.x, b.y)
            var ic = sheet.vertex(c, n, k1, c.z * n.x, c.y)
            var id = sheet.vertex(d, n, k1, d.z * n.x, d.y)
            sheet.triangle(ia, ib, ic)
            sheet.triangle(ia, ic, id)


def _roof(
    mut sheets: _Sheets,
    parameters: HouseParameters,
    half_t: Float32,
    breast: Optional[Breast],
) raises:
    """Add the gable roof, its gables, and the chimney over a breast."""
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
        var c0 = WHITE * outside_shade(0, base, ridge, parameters.seed)
        var c2 = WHITE * 0.75
        var n = Vector3(sx, 0, 0)
        _gable(
            sheets.facade, sx * gx, _end_sign(end), n, base, ridge, edge, c0, c2
        )
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
    if not breast:
        return
    # A chimney through the roof, over the breast.
    ref over = breast.value()
    var cx = Float32((over.x0 + over.x1) / 2)
    var cz = -Float32((over.y0 + over.y1) / 2)
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
    """Add a block of stone under each step before the doors."""
    var c = cos(lot.turn)
    var s = sin(lot.turn)
    var floor = interior.floor_height
    for k in range(1, 1 + interior.steps):
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


def _hay(
    mut sheets: _Sheets,
    center: Vector3,
    side: Vector3,
    front: Vector3,
    width: Float32,
    depth: Float32,
    height: Float32,
    seed: Int,
):
    """Add a stack of straw bales that fills a piece's box, its top course
    one bale shorter, each bale a little lighter or darker and tied with
    two cords."""
    var up = Vector3(0, 1, 0)
    var across = max(1, Int(width / BALE.x + 0.5))
    var deep = max(1, Int(depth / BALE.z + 0.5))
    var courses = max(1, Int(height / BALE.y + 0.5))
    var long = width / Float32(across)
    var wide = depth / Float32(deep)
    var tall = height / Float32(courses)
    for k in range(courses):  # pragma: no branch
        var count = across if k < courses - 1 else max(1, across - 1)
        var start = -Float32(count) * long / 2
        for i in range(count):  # pragma: no branch
            for j in range(deep):  # pragma: no branch
                var tint = STRAW * (
                    0.85 + 0.3 * hash01(i + 11 * k, j + 7 * seed, 23)
                )
                var middle = (
                    center
                    + side * (start + long * (Float32(i) + 0.5))
                    + front * (wide * (Float32(j) + 0.5) - depth / 2)
                    + up * (tall * (Float32(k) + 0.5))
                )
                _block(
                    sheets.plaster,
                    middle,
                    side,
                    front,
                    long / 2 - 0.015,
                    tall / 2 - 0.008,
                    wide / 2 - 0.015,
                    tint,
                )
                for sx in [Float32(-1), Float32(1)]:  # pragma: no branch
                    _block(
                        sheets.wood,
                        middle + side * (sx * long / 4),
                        side,
                        front,
                        0.012,
                        tall / 2 - 0.002,
                        wide / 2 - 0.009,
                        OAK * 0.6,
                    )


def _manger(
    mut sheets: _Sheets,
    center: Vector3,
    side: Vector3,
    front: Vector3,
    width: Float32,
    depth: Float32,
    height: Float32,
):
    """Add a manger against its wall: a trough of boards on four posts,
    with hay in it, and a rack of slats on the wall over it."""
    var up = Vector3(0, 1, 0)
    var hw = width / 2
    var hd = depth / 2
    var wood = OAK * 0.8
    var floor = height * 0.55
    _legs(sheets.wood, center, side, front, hw, hd, 0.05, floor, 0.05, wood)
    # The trough's bottom, its front and back, and its ends.
    _block(
        sheets.wood,
        center + up * floor,
        side,
        front,
        hw,
        0.025,
        hd,
        wood,
    )
    for sz in [Float32(1), Float32(-1)]:  # pragma: no branch
        _block(
            sheets.wood,
            center + front * (sz * (hd - 0.025)) + up * ((floor + height) / 2),
            side,
            front,
            hw,
            (height - floor) / 2,
            0.025,
            wood * 1.1,
        )
        _block(
            sheets.wood,
            center + side * (sz * (hw - 0.025)) + up * ((floor + height) / 2),
            side,
            front,
            0.025,
            (height - floor) / 2,
            hd - 0.05,
            wood,
        )
    # Hay heaped in the trough.
    _block(
        sheets.plaster,
        center + up * (height - 0.08),
        side,
        front,
        hw - 0.06,
        0.05,
        hd - 0.06,
        STRAW,
    )
    # The rack: two rails along the wall, and slats between them.
    var low = height + 0.25
    var high = height + 1.0
    var back = center - front * (hd - 0.04)
    for y in [low, high]:  # pragma: no branch
        _block(sheets.wood, back + up * y, side, front, hw, 0.035, 0.035, wood)
    var slats = Int(width / 0.15)
    for k in range(slats + 1):  # pragma: no branch
        _block(
            sheets.wood,
            back
            + side * (-hw + 0.05 + (width - 0.1) * Float32(k) / Float32(slats))
            + up * ((low + high) / 2),
            side,
            front,
            0.015,
            (high - low) / 2,
            0.015,
            wood * 1.1,
        )


def _loft(mut sheets: _Sheets, parameters: HouseParameters, half_t: Float32):
    """Add a barn's loft door high in its east gable, shut, and a hoist
    beam out from under the ridge over it, with its pulley and rope. A
    gable too low for a door of 60 centimeters has none."""
    var half_w = parameters.width.to(METER) / 2
    var half_d = parameters.depth.to(METER) / 2
    var base = parameters.storey_height.to(METER) * Float32(parameters.storeys)
    var slope = tan(parameters.pitch.to(RADIAN))
    var ridge = base + slope * (half_d + half_t)
    var gx = half_w + half_t
    var n = Vector3(1, 0, 0)
    # The door's top stays under the roof at its sides.
    var sill = base + 0.25
    var tall = min(LOFT_DOOR.y, ridge - slope * (LOFT_DOOR.x / 2 + 0.15) - sill)
    if tall < 0.6:
        return
    var paint = painted(parameters.trim)
    var hw = LOFT_DOOR.x / 2
    # Two leaves of boards, a frame round them, and the beam over them.
    for sz in [Float32(1), Float32(-1)]:  # pragma: no branch
        sheets.wood.box(
            Vector3(gx + 0.03, sill + tall / 2, sz * hw / 2),
            Vector3(0.02, 0, 0),
            Vector3(0, tall / 2, 0),
            Vector3(0, 0, hw / 2 - 0.01),
            paint * (0.9 + 0.1 * sz),
        )
        _bar(
            sheets.wood,
            Vector3(gx, sill, sz * (hw + 0.05)),
            Vector3(gx, sill + tall + 0.05, sz * (hw + 0.05)),
            n,
            0.1,
            0.12,
            OAK,
        )
        # A strap across each leaf.
        for y in [sill + 0.25, sill + tall - 0.25]:  # pragma: no branch
            sheets.wood.box(
                Vector3(gx + 0.055, y, sz * hw / 2),
                Vector3(0.006, 0, 0),
                Vector3(0, 0.025, 0),
                Vector3(0, 0, hw / 2 - 0.08),
                IRON,
            )
    _bar(
        sheets.wood,
        Vector3(gx, sill - 0.05, -hw - 0.1),
        Vector3(gx, sill - 0.05, hw + 0.1),
        n,
        0.1,
        0.14,
        OAK,
    )
    _bar(
        sheets.wood,
        Vector3(gx, sill + tall + 0.05, -hw - 0.1),
        Vector3(gx, sill + tall + 0.05, hw + 0.1),
        n,
        0.1,
        0.14,
        OAK,
    )
    # The hoist beam, its pulley, and the rope down from it.
    var beam = ridge - 0.45
    sheets.wood.box(
        Vector3(gx + 0.4, beam, 0),
        Vector3(0.75, 0, 0),
        Vector3(0, 0.09, 0),
        Vector3(0, 0, 0.08),
        OAK * 0.9,
    )
    sheets.wood.box(
        Vector3(gx + 0.95, beam - 0.17, 0),
        Vector3(0.06, 0, 0),
        Vector3(0, 0.08, 0),
        Vector3(0, 0, 0.04),
        IRON,
    )
    sheets.wood.box(
        Vector3(gx + 0.95, beam - 0.25 - 0.6, 0),
        Vector3(0.012, 0, 0),
        Vector3(0, 0.6, 0),
        Vector3(0, 0, 0.012),
        STRAW * 0.6,
    )


def _furniture(mut sheets: _Sheets, building: Building, barn: Bool):
    """Add each furnishing of the model. In a barn, a shelf is a stack of
    hay, and any other piece is a manger."""
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
        var width = Float32(piece.width.value)
        var depth = Float32(piece.depth.value)
        var height = Float32(piece.height.value)
        if not barn:
            _piece(
                sheets,
                piece.kind,
                center,
                side,
                front,
                width,
                depth,
                height,
                index,
            )
        elif piece.kind == SHELF:
            _hay(sheets, center, side, front, width, depth, height, index)
        else:
            _manger(sheets, center, side, front, width, depth, height)


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
    var stair = house_stair(building)
    var barn = parameters.use == BARN
    _rooms(sheets, building, stair, barn)
    if stair:
        _stair_view(sheets, stair.value())
    var breast = house_breast(building)
    if breast:
        _breast_view(sheets, building, breast.value())
    var half_t = Float32(building.constructions[0].thickness().value) / 2
    if parameters.pitch.to(RADIAN) > 0:
        _roof(sheets, parameters, half_t, breast)
    _plinth(sheets, half_x, half_z, feet[0] - floor)
    _steps(sheets, interior, lot, ground)
    if parameters.facade == BRICK_FACADE or parameters.facade == STONE_FACADE:
        _quoins(sheets, half_x + half_t, half_z + half_t, top)
    _furniture(sheets, building, barn)
    if barn and parameters.pitch.to(RADIAN) > 0:
        _loft(sheets, parameters, half_t)
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
    # A leaf on a hinge for each door of the ground storey, two for a
    # wide one, in the order of the interior's doorways.
    var hinges = List[Hinge]()
    var paint = painted(parameters.trim)
    var doorway = 0
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
        # An outside door swings into the house, and an outside double
        # door out of it, so its leaves keep its way clear. An inside door
        # swings along the wall's normal.
        var leaves = 2 if width >= DOUBLE_DOOR else 1
        var into = -out_sign if leaves == 1 else out_sign
        var swing = face.normal * (into if exterior else Float32(1))
        var u0 = Float32(o.offset.value)
        for leaf_index in range(leaves):  # pragma: no branch
            # The first leaf hangs at the door's start and runs along the
            # wall; a second hangs at its end and runs back.
            var at = face.at(
                u0 + width * Float32(leaf_index), Float32(o.sill.value), plane
            )
            var along = face.along * (1 - 2 * Float32(leaf_index))
            var shut = atan2(-along.z, along.x)
            # The leaf's -z, turned shut, is (-sin shut, 0, -cos shut),
            # along the wall's normal one way or the other, so `toward`
            # is 1 or -1.
            var toward = -sin(shut) * swing.x - cos(shut) * swing.z
            var sense = toward / abs(toward)
            var node = Object3D()
            node.set_position(at.x, at.y, at.z)
            node.rotate_y(Angle(shut, RADIAN))
            node.parent = root
            var hinge = scene.add(node^)
            var leaf = door_leaf(
                width / Float32(leaves) - 0.02,
                height - 0.01,
                paint if exterior else OAK,
            )
            triangles += _add(scene, assets, leaf, looks.wood, hinge, True)
            if host.storey.value == 0:
                hinges.append(Hinge(hinge, shut, sense, doorway))
        if host.storey.value == 0:
            doorway += 1
    var meshes = len(scene.meshes) - before
    return StandingHouse(root, meshes, triangles, interior^, hinges^)
