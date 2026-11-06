# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The things that stand about the village: a well, barrels, crates, hay
bales, fences, benches, woodpiles, carts, signposts, washing lines,
troughs, scarecrows, crops, lamp posts and hedges.

Each `Prop` is a kind, a place on the ground, a turn about +y and a
length. `stand_props` draws every prop with the houses' materials, in one
mesh for each material, and returns what stops a character: a solid `Lot`
for each prop but a fence, and a `WallSpan` for each fence.

| Kind | What it is | Its length |
|---|---|---|
| `WELL` | A round stone wall, two posts, a beam, a little roof and a bucket | Its radius |
| `BARREL` | Oak staves with two iron hoops | Its radius |
| `CRATE` | A box of boards with slats on its edges | Its side |
| `HAY_BALE` | A bale of hay | Its length; it is half as wide and tall |
| `FENCE` | Posts every 2 meters, and two rails | Its length, along its own x |
| `BENCH` | A plank on two trestles | Its length |
| `WOODPILE` | Split logs stacked under a board lid, their ends out | Its length, along its own x; it is `WOODPILE_DEPTH` deep and `WOODPILE_HEIGHT` tall |
| `CART` | A handcart: a bed of boards on two spoked wheels, with two shafts | Its bed's length, along its own x |
| `SIGNPOST` | A post with two pointing arms | Its height |
| `WASHING_LINE` | Two posts, a line between them, and cloths hung on it | Its length, along its own x |
| `TROUGH` | A trough of boards on legs, full of water | Its length, along its own x |
| `SCARECROW` | A post and a cross arm in a coat, with a straw head and a hat | Its height |
| `CROPS` | A garden bed of three rows of cabbages | Its length, along its own x |
| `LAMP_POST` | An iron post with a lantern, lit from dusk to dawn | Its height |
| `HEDGE` | A clipped hedge of leaves, 1.4 meters tall and 0.9 meters deep | Its length, along its own x |

A prop stands on the ground at its middle, and its foot reaches a little
below the ground, so a slope shows no gap. A fence and a hedge stop a
character as a wall span. Crops stop nobody. Each other prop is a solid
lot.

A lamp post's glass hangs from two nodes: `StandingProps.lit`, shown from
dusk to dawn, and `StandingProps.daylit`, shown by day.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.ordinal import ordinal_valid
from core.scene import Scene
from extensions.vegetation.checks import require_between
from extensions.vegetation.ground import Ground, Lot
from extensions.village.house_view import OAK, STONE
from extensions.village.sheet import Sheet
from extensions.village.dressing import FLAME, lantern_glass, prism
from extensions.village.surfaces import (
    ASHLAR_TILE,
    CLOTH_TILE,
    HouseLooks,
    PLASTER_TILE,
    TILE_TILE,
    WOOD_TILE,
)
from extensions.village.terrain import WallSpan
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, pi, sin
from units.si import RADIAN, Angle

comptime FENCE_HEIGHT = Float32(1.0)
"""How tall a fence is, in meters."""
comptime FENCE_BAY = Float32(2.0)
"""The longest gap between two posts of a fence, in meters."""
comptime SUNK = Float32(0.1)
"""How far a prop's foot reaches below the ground at its middle, in
meters."""
comptime HAY = Vector3(1.0, 0.82, 0.42)
"""The tint of hay over the plaster texture."""
comptime IRON = Vector3(0.06, 0.06, 0.065)
"""The tint of iron hoops over the wood texture."""
comptime WOODPILE_DEPTH = Float32(0.6)
"""How deep a woodpile is, along its own z, in meters."""
comptime WOODPILE_HEIGHT = Float32(1.15)
"""How tall a woodpile is, to the top of its lid, in meters."""
comptime LOG = Float32(0.065)
"""The radius of a log's end in a woodpile, in meters."""
comptime HEDGE_HEIGHT = Float32(1.4)
"""How tall a hedge is, in meters."""
comptime HEDGE_DEPTH = Float32(0.9)
"""How deep a hedge is, along its own z, in meters."""
comptime LEAVES = Vector3(0.16, 0.30, 0.08)
"""The tint of a hedge's leaves over the plaster texture."""
comptime CABBAGE = Vector3(0.30, 0.52, 0.22)
"""The tint of a cabbage over the plaster texture."""
comptime SOIL = Vector3(0.20, 0.13, 0.08)
"""The tint of a garden bed's tilled soil over the plaster texture."""
comptime STRAW = Vector3(0.85, 0.70, 0.36)
"""The tint of a scarecrow's straw over the plaster texture."""
comptime WATER = Vector3(0.05, 0.08, 0.09)
"""The color of the still water in a trough."""
comptime COLD_GLASS = Vector3(0.16, 0.15, 0.12)
"""The color of a lamp post's glass by day, drawn unlit."""


@fieldwise_init
struct PropKind(Equatable, ImplicitlyCopyable, Writable):
    """What a prop is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the fifteen kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return ordinal_valid(self.value, 14)


comptime WELL = PropKind(0)
comptime BARREL = PropKind(1)
comptime CRATE = PropKind(2)
comptime HAY_BALE = PropKind(3)
comptime FENCE = PropKind(4)
comptime BENCH = PropKind(5)
comptime WOODPILE = PropKind(6)
comptime CART = PropKind(7)
comptime SIGNPOST = PropKind(8)
comptime WASHING_LINE = PropKind(9)
comptime TROUGH = PropKind(10)
comptime SCARECROW = PropKind(11)
comptime CROPS = PropKind(12)
comptime LAMP_POST = PropKind(13)
comptime HEDGE = PropKind(14)


@fieldwise_init
struct Prop(ImplicitlyCopyable):
    """A thing that stands in the village, and where."""

    var kind: PropKind
    # Its middle on the ground, in meters.
    var x: Float32
    var z: Float32
    # How far it is turned about +y.
    var turn: Angle
    # Its length, in meters: see the module's table.
    var length: Float32

    def check(self) raises:
        """Refuse a prop that cannot be drawn.

        Raises:
            Error: If the kind is not one, the prop stands further than 10
                kilometers away, or its length is not from 0.2 to 50
                meters.
        """
        if not self.kind.is_valid():
            raise Error("A prop's kind must be one of the fifteen")
        require_between(
            self.x, -1.0e4, 1.0e4, "A prop must stand within 10 kilometers"
        )
        require_between(
            self.z, -1.0e4, 1.0e4, "A prop must stand within 10 kilometers"
        )
        require_between(
            self.length, 0.2, 50, "A prop must be from 0.2 to 50 meters long"
        )


struct StandingProps(Movable):
    """What the village's props drew, and what of them stops a
    character."""

    var root: NodeId
    var meshes: Int
    var triangles: Int
    # Each prop's footprint but a fence's, a hedge's and crops', and each
    # fence and hedge.
    var lots: List[Lot]
    var walls: List[WallSpan]
    var lit: NodeId
    """The node of the lamp posts' glowing glass, hidden by day."""
    var daylit: NodeId
    """The node of the lamp posts' cold glass, shown by day."""

    def __init__(out self, root: NodeId, lit: NodeId, daylit: NodeId):
        """Hold no prop yet, under a node.

        Args:
            root: The node the props hang from.
            lit: The node of the lamps' glowing glass.
            daylit: The node of the lamps' cold glass.
        """
        self.root = root
        self.meshes = 0
        self.triangles = 0
        self.lots = List[Lot]()
        self.walls = List[WallSpan]()
        self.lit = lit
        self.daylit = daylit


struct _PropSheets(Movable):
    """The sheets of the props, one per material."""

    var wood: Sheet
    var ashlar: Sheet
    var plaster: Sheet
    var tiles: Sheet
    var cloth: Sheet
    # The lamps' glass: glowing, and cold.
    var glow: Sheet
    var cold: Sheet
    # The water in the troughs, drawn unlit.
    var water: Sheet

    def __init__(out self):
        self.wood = Sheet(WOOD_TILE)
        self.ashlar = Sheet(ASHLAR_TILE)
        self.plaster = Sheet(PLASTER_TILE)
        self.tiles = Sheet(TILE_TILE)
        self.cloth = Sheet(CLOTH_TILE)
        self.glow = Sheet(1)
        self.cold = Sheet(1)
        self.water = Sheet(1)


struct _Frame(ImplicitlyCopyable):
    """A prop's own frame: its middle on the ground, and its own x and z
    on the ground, of length one."""

    var foot: Vector3
    var x: Vector3
    var z: Vector3

    def __init__(out self, prop: Prop, ground: Ground):
        var turn = prop.turn.to(RADIAN)
        self.foot = Vector3(prop.x, ground.height_at(prop.x, prop.z), prop.z)
        self.x = Vector3(cos(turn), 0, -sin(turn))
        self.z = Vector3(sin(turn), 0, cos(turn))

    def at(self, a: Float32, b: Float32, c: Float32) -> Vector3:
        """Return the point `a` along x, `b` up and `c` along z."""
        return self.foot + self.x * a + Vector3(0, b, 0) + self.z * c

    def block(
        self,
        mut sheet: Sheet,
        center: Vector3,
        half_x: Float32,
        half_y: Float32,
        half_z: Float32,
        color: Vector3,
    ):
        """Add a box of the prop, in its own frame."""
        sheet.box(
            self.at(center.x, center.y, center.z),
            self.x * half_x,
            Vector3(0, half_y, 0),
            self.z * half_z,
            color,
        )


def _ring(
    mut sheet: Sheet,
    frame: _Frame,
    radius: Float32,
    low: Float32,
    high: Float32,
    sides: Int,
    color: Vector3,
):
    """Add a ring of upright quads around the frame's middle, facing out,
    from `low` to `high`, with a lid on top facing up."""
    var top = sheet.vertex(frame.at(0, high, 0), Vector3(0, 1, 0), color, 0, 0)
    for k in range(sides):  # pragma: no branch
        var a = 2 * pi * Float32(k) / Float32(sides)
        var b = 2 * pi * Float32(k + 1) / Float32(sides)
        var p = frame.at(radius * cos(a), low, radius * sin(a))
        var q = frame.at(radius * cos(b), low, radius * sin(b))
        var shade = color * (0.92 + 0.08 * Float32(k % 2))
        # Seen from outside, the quad runs from `q` to `p`.
        sheet.quad(
            q,
            p,
            p + Vector3(0, high - low, 0),
            q + Vector3(0, high - low, 0),
            shade,
        )
        var ip = sheet.vertex(
            p + Vector3(0, high - low, 0), Vector3(0, 1, 0), color, 0, 0
        )
        var iq = sheet.vertex(
            q + Vector3(0, high - low, 0), Vector3(0, 1, 0), color, 0, 0
        )
        sheet.triangle(top, iq, ip)


def _well(mut sheets: _PropSheets, frame: _Frame, radius: Float32):
    """Add a well: a stone wall around its shaft, two posts, a beam, a
    roof and a bucket."""
    var stones = 14
    for k in range(stones):  # pragma: no branch
        var a = 2 * pi * (Float32(k) + 0.5) / Float32(stones)
        var c = Vector3(radius * cos(a), (0.8 - SUNK) / 2, radius * sin(a))
        # Each stone faces out from the middle.
        var out = Vector3(cos(a), 0, sin(a))
        var along = Vector3(-sin(a), 0, cos(a))
        var span = 2 * pi * radius / Float32(stones) / 2 + 0.02
        sheets.ashlar.box(
            frame.at(c.x, c.y - SUNK, c.z),
            frame.x * (along.x * span) + frame.z * (along.z * span),
            Vector3(0, (0.8 + SUNK) / 2, 0),
            frame.x * (out.x * 0.14) + frame.z * (out.z * 0.14),
            STONE * (0.85 + 0.1 * Float32(k % 3) / 2),
        )
    # The dark water down the shaft.
    _ring(sheets.ashlar, frame, radius - 0.12, -SUNK, 0.3, 12, STONE * 0.08)
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        frame.block(
            sheets.wood,
            Vector3(side * (radius + 0.05), 1.0, 0),
            0.06,
            1.0,
            0.06,
            OAK,
        )
    frame.block(
        sheets.wood, Vector3(0, 1.75, 0), radius + 0.15, 0.05, 0.05, OAK
    )
    # A little roof of two boards over the beam.
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        var lean = side * 0.32
        var p0 = frame.at(-radius - 0.25, 1.95, 0)
        var p1 = frame.at(radius + 0.25, 1.95, 0)
        var p2 = frame.at(radius + 0.25, 1.62, lean * 1.6)
        var p3 = frame.at(-radius - 0.25, 1.62, lean * 1.6)
        if side > 0:
            sheets.tiles.quad(p3, p2, p1, p0, Vector3(1, 1, 1))
        else:
            sheets.tiles.quad(p0, p1, p2, p3, Vector3(1, 1, 1))
    # The bucket on the wall.
    frame.block(
        sheets.wood,
        Vector3(radius * 0.7, 0.9, 0),
        0.12,
        0.12,
        0.12,
        OAK * 1.2,
    )


def _barrel(mut sheets: _PropSheets, frame: _Frame, radius: Float32):
    """Add a barrel of oak staves with two iron hoops."""
    var tall = radius * 2.8
    _ring(sheets.wood, frame, radius, -SUNK, tall, 10, OAK * 1.3)
    for k in range(2):  # pragma: no branch
        var y = tall * (0.25 + 0.5 * Float32(k))
        _ring(sheets.wood, frame, radius + 0.012, y, y + 0.05, 10, IRON)


def _crate(mut sheets: _PropSheets, frame: _Frame, side: Float32):
    """Add a crate of boards with slats on its edges."""
    var h = side / 2
    frame.block(
        sheets.wood, Vector3(0, h - SUNK / 2, 0), h, h + SUNK / 2, h, OAK * 1.4
    )
    for k in range(4):  # pragma: no branch
        var sx = Float32(1) if k % 2 == 0 else Float32(-1)
        var sz = Float32(1) if k < 2 else Float32(-1)
        frame.block(
            sheets.wood,
            Vector3(sx * (h - 0.02), h, sz * (h - 0.02)),
            0.035,
            h + 0.01,
            0.035,
            OAK,
        )


def _hay(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a bale of hay, tied with two cords."""
    var half = length / 2
    var tall = length / 4
    frame.block(
        sheets.plaster,
        Vector3(0, tall - SUNK / 2, 0),
        half,
        tall + SUNK / 2,
        length / 4,
        HAY,
    )
    for k in range(2):  # pragma: no branch
        var x = half * (Float32(k) - 0.5)
        frame.block(
            sheets.wood,
            Vector3(x, tall, 0),
            0.015,
            tall + 0.012,
            length / 4 + 0.012,
            OAK * 0.6,
        )


def _fence(mut sheets: _PropSheets, frame: _Frame, length: Float32) -> WallSpan:
    """Add a fence of posts and two rails, and return the span that
    stops a character."""
    var bays = Int(length / FENCE_BAY + 0.999)
    for k in range(bays + 1):  # pragma: no branch
        var x = -length / 2 + length * Float32(k) / Float32(bays)
        frame.block(
            sheets.wood,
            Vector3(x, (FENCE_HEIGHT - SUNK) / 2, 0),
            0.05,
            (FENCE_HEIGHT + SUNK) / 2,
            0.05,
            OAK,
        )
    for y in [Float32(0.4), Float32(0.85)]:  # pragma: no branch
        frame.block(
            sheets.wood, Vector3(0, y, 0.06), length / 2, 0.04, 0.02, OAK * 1.2
        )
    var a = frame.at(-length / 2, 0, 0)
    var b = frame.at(length / 2, 0, 0)
    return WallSpan(a.x, a.z, b.x, b.z, 0.08, a.y - SUNK, a.y + FENCE_HEIGHT)


def _bench(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a bench: a plank on two trestles."""
    var half = length / 2
    frame.block(sheets.wood, Vector3(0, 0.45, 0), half, 0.03, 0.17, OAK * 1.3)
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        frame.block(
            sheets.wood,
            Vector3(side * (half - 0.15), (0.42 - SUNK) / 2, 0),
            0.04,
            (0.42 + SUNK) / 2,
            0.15,
            OAK,
        )


def _woodpile(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a woodpile: a stack of split logs, their light ends in rows on
    its front, its own +z, under a lid of boards."""
    var half = length / 2
    var deep = WOODPILE_DEPTH / 2
    var top = WOODPILE_HEIGHT - 0.06
    # The stack, dark with bark, and the lid over it.
    frame.block(
        sheets.wood,
        Vector3(0, (top - SUNK) / 2, 0),
        half,
        (top + SUNK) / 2,
        deep,
        OAK * 0.55,
    )
    frame.block(
        sheets.wood,
        Vector3(0, top + 0.03, 0.04),
        half + 0.08,
        0.03,
        deep + 0.1,
        OAK * 0.9,
    )
    # The logs' ends: an octagon each, in staggered rows.
    var n = frame.z
    var up = Vector3(0, 1, 0)
    var across = max(1, Int(length / (2.2 * LOG)))
    var rows = max(1, Int(top / (1.9 * LOG)))
    var step_x = length / Float32(across)
    var step_y = top / Float32(rows)
    for row in range(rows):  # pragma: no branch
        var shift = Float32(row % 2) * 0.5 - 0.25
        for k in range(across):  # pragma: no branch
            var middle = frame.at(
                -half + step_x * (Float32(k) + 0.5 + shift * 0.5),
                step_y * (Float32(row) + 0.5),
                deep + 0.004,
            )
            var tone = 1.5 + 0.25 * Float32((row * 7 + k * 3) % 4) / 3
            var core = sheets.wood.vertex(middle, n, OAK * tone, 0, 0)
            var rim = List[Int]()
            for corner in range(8):
                var angle = Float32(corner) * Float32(pi) / 4
                var p = (
                    middle
                    + frame.x * (LOG * cos(angle))
                    + up * (LOG * sin(angle))
                )
                rim.append(
                    sheets.wood.vertex(
                        p, n, OAK * (tone * 0.75), LOG * cos(angle), LOG
                    )
                )
            for corner in range(8):
                sheets.wood.triangle(core, rim[corner], rim[(corner + 1) % 8])


def _wheel(
    mut sheet: Sheet, frame: _Frame, x: Float32, z: Float32, radius: Float32
):
    """Add a cart's wheel at its own x and z: a rim of eight felloes, a hub
    and two spokes across it, in the plane of the prop's x and up."""
    var hub = frame.at(x, radius, z)
    var up = Vector3(0, 1, 0)
    var thick = frame.z * 0.03
    for k in range(8):  # pragma: no branch
        var a = Float32(k) * Float32(pi) / 4
        var b = Float32(k + 1) * Float32(pi) / 4
        var p = hub + frame.x * (radius * cos(a)) + up * (radius * sin(a))
        var q = hub + frame.x * (radius * cos(b)) + up * (radius * sin(b))
        var middle = (p + q) / 2
        var outward = (middle - hub) / (middle - hub).length()
        sheet.box(middle, (q - p) / 2, outward * 0.035, thick, OAK * 0.8)
    sheet.box(hub, frame.x * 0.06, up * 0.06, frame.z * 0.08, IRON)
    sheet.box(hub, frame.x * radius, up * 0.02, thick * 0.7, OAK)
    sheet.box(hub, frame.x * 0.02, up * radius, thick * 0.7, OAK)


def _cart(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a handcart: a bed of boards with low sides on two wheels, and
    two shafts that rest on the ground."""
    var half = length / 2
    var radius = Float32(0.42)
    var bed = radius + 0.12
    frame.block(sheets.wood, Vector3(0, bed, 0), half, 0.04, 0.45, OAK * 1.2)
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        frame.block(
            sheets.wood,
            Vector3(0, bed + 0.17, side * 0.43),
            half,
            0.13,
            0.02,
            OAK * 1.1,
        )
        _wheel(sheets.wood, frame, 0, side * 0.55, radius)
        # A shaft from the bed down to the ground before it.
        var from_p = frame.at(half, bed, side * 0.3)
        var to_p = frame.at(half + 1.2, 0.05, side * 0.3)
        var middle = (from_p + to_p) / 2
        sheets.wood.box(
            middle,
            (to_p - from_p) / 2,
            Vector3(0, 0.03, 0),
            frame.z * 0.03,
            OAK,
        )
    frame.block(sheets.wood, Vector3(0, radius, 0), 0.04, 0.04, 0.6, OAK * 0.7)


def _signpost(mut sheets: _PropSheets, frame: _Frame, height: Float32):
    """Add a signpost: a post with two arms that point two ways."""
    frame.block(
        sheets.wood,
        Vector3(0, (height - SUNK) / 2, 0),
        0.06,
        (height + SUNK) / 2,
        0.06,
        OAK,
    )
    frame.block(
        sheets.wood,
        Vector3(0.35, height - 0.25, 0),
        0.35,
        0.08,
        0.02,
        OAK * 1.5,
    )
    frame.block(
        sheets.wood,
        Vector3(0, height - 0.5, -0.32),
        0.02,
        0.08,
        0.32,
        OAK * 1.4,
    )
    frame.block(
        sheets.wood, Vector3(0, height + 0.02, 0), 0.08, 0.02, 0.08, OAK * 0.8
    )


def _washing_line(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a washing line: two posts, a line between them, and cloths
    of three colors hung on it."""
    var half = length / 2
    var high = Float32(1.8)
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        frame.block(
            sheets.wood,
            Vector3(side * half, (high - SUNK) / 2, 0),
            0.04,
            (high + SUNK) / 2,
            0.04,
            OAK,
        )
    frame.block(
        sheets.wood, Vector3(0, high - 0.05, 0), half, 0.006, 0.006, OAK * 0.4
    )
    var colors: List[Vector3] = [
        Vector3(0.85, 0.83, 0.76),
        Vector3(0.40, 0.12, 0.10),
        Vector3(0.20, 0.28, 0.45),
    ]
    var count = max(1, Int(length / 0.9))
    for k in range(count):  # pragma: no branch
        var x = -half + length * (Float32(k) + 0.5) / Float32(count)
        var drop = 0.45 + 0.2 * Float32(k % 2)
        frame.block(
            sheets.cloth,
            Vector3(x, high - 0.05 - drop / 2, 0),
            min(Float32(0.32), length / Float32(count) / 2 - 0.05),
            drop / 2,
            0.01,
            colors[k % 3],
        )


def _trough(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a trough of boards on legs, full of still water."""
    var half = length / 2
    var top = Float32(0.6)
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        frame.block(
            sheets.wood,
            Vector3(0, top - 0.15, side * 0.28),
            half,
            0.15,
            0.03,
            OAK * 1.1,
        )
        frame.block(
            sheets.wood,
            Vector3(side * half, top - 0.15, 0),
            0.03,
            0.15,
            0.31,
            OAK * 1.1,
        )
        for end in [Float32(-1), Float32(1)]:  # pragma: no branch
            frame.block(
                sheets.wood,
                Vector3(end * (half - 0.1), (top - 0.3 - SUNK) / 2, side * 0.2),
                0.04,
                (top - 0.3 + SUNK) / 2,
                0.04,
                OAK * 0.9,
            )
    frame.block(sheets.wood, Vector3(0, top - 0.3, 0), half, 0.02, 0.28, OAK)
    var a = frame.at(-half + 0.03, top - 0.06, -0.25)
    var b = frame.at(half - 0.03, top - 0.06, -0.25)
    var c = frame.at(half - 0.03, top - 0.06, 0.25)
    var d = frame.at(-half + 0.03, top - 0.06, 0.25)
    sheets.water.quad(d, c, b, a, WATER)


def _scarecrow(mut sheets: _PropSheets, frame: _Frame, height: Float32):
    """Add a scarecrow: a post and a cross arm in a coat, a head of
    straw, and a broad hat."""
    frame.block(
        sheets.wood,
        Vector3(0, (height - SUNK) / 2, 0),
        0.04,
        (height + SUNK) / 2,
        0.04,
        OAK,
    )
    var arms = height * 0.72
    frame.block(sheets.wood, Vector3(0, arms, 0), 0.7, 0.03, 0.03, OAK)
    # The coat over the post and the arms, and its sleeves.
    frame.block(
        sheets.cloth,
        Vector3(0, arms - 0.25, 0),
        0.22,
        0.32,
        0.12,
        Vector3(0.30, 0.22, 0.12),
    )
    frame.block(
        sheets.cloth,
        Vector3(0, arms, 0),
        0.6,
        0.07,
        0.07,
        Vector3(0.26, 0.19, 0.10),
    )
    frame.block(
        sheets.plaster,
        Vector3(0, arms + 0.2, 0),
        0.12,
        0.13,
        0.12,
        STRAW,
    )
    frame.block(
        sheets.plaster,
        Vector3(0, arms + 0.34, 0),
        0.26,
        0.015,
        0.26,
        STRAW * 0.7,
    )
    frame.block(
        sheets.plaster,
        Vector3(0, arms + 0.42, 0),
        0.11,
        0.08,
        0.11,
        STRAW * 0.7,
    )


def _crops(mut sheets: _PropSheets, frame: _Frame, length: Float32):
    """Add a garden bed: tilled soil with three rows of cabbages."""
    var half = length / 2
    frame.block(sheets.plaster, Vector3(0, 0.0, 0), half, 0.06, 0.95, SOIL)
    var count = max(1, Int(length / 0.55))
    for row in range(3):  # pragma: no branch
        var z = (Float32(row) - 1) * 0.6
        for k in range(count):  # pragma: no branch
            var x = -half + length * (Float32(k) + 0.5) / Float32(count)
            var size = 0.14 + 0.04 * Float32((k * 5 + row * 3) % 3) / 2
            prism(
                sheets.plaster,
                frame.at(x, 0.04, z),
                size,
                size * 0.6,
                size * 1.1,
                6,
                CABBAGE * (0.85 + 0.15 * Float32((k + row) % 2)),
            )


def _lamp_post(mut sheets: _PropSheets, frame: _Frame, height: Float32):
    """Add a lamp post: an iron post on a stone foot, an arm, and a
    lantern that glows from dusk to dawn."""
    frame.block(
        sheets.ashlar,
        Vector3(0, 0.15 - SUNK / 2, 0),
        0.16,
        0.15 + SUNK / 2,
        0.16,
        STONE,
    )
    frame.block(
        sheets.wood, Vector3(0, height / 2, 0), 0.035, height / 2, 0.035, IRON
    )
    frame.block(
        sheets.wood, Vector3(0.2, height - 0.05, 0), 0.22, 0.02, 0.02, IRON
    )
    var hook = frame.at(0.38, height - 0.05, 0)
    _ = lantern_glass(sheets.glow, hook, 0.3, FLAME * 0.8)
    _ = lantern_glass(sheets.cold, hook, 0.3, COLD_GLASS)
    sheets.wood.box(
        hook - Vector3(0, 0.07, 0),
        Vector3(0.1, 0, 0),
        Vector3(0, 0.02, 0),
        Vector3(0, 0, 0.1),
        IRON,
    )


def _hedge(mut sheets: _PropSheets, frame: _Frame, length: Float32) -> WallSpan:
    """Add a clipped hedge of leaves, and return the span that stops a
    character."""
    var half = length / 2
    var count = max(1, Int(length / 0.8))
    for k in range(count):  # pragma: no branch
        var x = -half + length * (Float32(k) + 0.5) / Float32(count)
        var bulge = 0.04 * Float32((k * 7) % 3)
        frame.block(
            sheets.plaster,
            Vector3(x, (HEDGE_HEIGHT - SUNK) / 2 + bulge / 2, 0),
            length / Float32(count) / 2 + 0.05,
            (HEDGE_HEIGHT + SUNK) / 2 + bulge / 2,
            HEDGE_DEPTH / 2 + bulge,
            LEAVES * (0.85 + 0.12 * Float32(k % 3)),
        )
    var a = frame.at(-half, 0, 0)
    var b = frame.at(half, 0, 0)
    return WallSpan(
        a.x, a.z, b.x, b.z, HEDGE_DEPTH / 2, a.y - SUNK, a.y + HEDGE_HEIGHT
    )


def _footprint(prop: Prop) -> Lot:
    """Return the ground a prop that is not a fence, a hedge or crops
    takes up."""
    var half_x = prop.length / 2
    var half_z = prop.length / 2
    if prop.kind == WELL or prop.kind == BARREL:
        half_x = prop.length + 0.15
        half_z = prop.length + 0.15
    elif prop.kind == HAY_BALE:
        half_z = prop.length / 4
    elif prop.kind == BENCH:
        half_z = 0.18
    elif prop.kind == WOODPILE:
        half_z = WOODPILE_DEPTH / 2
    elif prop.kind == CART:
        half_x = prop.length / 2 + 0.6
        half_z = 0.6
    elif prop.kind == WASHING_LINE:
        half_z = 0.1
    elif prop.kind == TROUGH:
        half_z = 0.32
    elif prop.kind == SIGNPOST or prop.kind == LAMP_POST:
        half_x = 0.2
        half_z = 0.2
    elif prop.kind == SCARECROW:
        half_x = 0.15
        half_z = 0.15
    return Lot(prop.x, prop.z, half_x, half_z, prop.turn.to(RADIAN))


def _add(
    mut scene: Scene,
    mut assets: Assets,
    sheet: Sheet,
    material: MaterialId,
    parent: NodeId,
    mut standing: StandingProps,
) raises:
    """Add a sheet as a mesh, if it has any triangle."""
    if sheet.triangles() == 0:
        return
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sheet.geometry()),
            material,
            parent,
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    standing.meshes += 1
    standing.triangles += sheet.triangles()


def stand_props(
    mut scene: Scene,
    mut assets: Assets,
    looks: HouseLooks,
    props: List[Prop],
    ground: Ground,
) raises -> StandingProps:
    """Draw props on the ground, and return what of them stops a
    character.

    Args:
        scene: The scene. Three nodes, and one mesh for each material the
            props wear, are added: the props' node, and under it the
            nodes of the lamps' glowing glass and of their cold glass.
        assets: The stores for the geometries.
        looks: The houses' materials, which the props wear too.
        props: The props.
        ground: The ground they stand on.

    Returns:
        The nodes, what they draw, a solid lot for each prop but a fence,
        a hedge or crops, and a wall span for each fence and each hedge.

    Raises:
        Error: If a prop does not check.
    """
    var root = scene.add(Object3D())
    var lamps = Object3D()
    lamps.parent = root
    lamps.visible = False
    var lit = scene.add(lamps^)
    var sun = Object3D()
    sun.parent = root
    var daylit = scene.add(sun^)
    var standing = StandingProps(root, lit, daylit)
    var sheets = _PropSheets()
    for prop in props:
        prop.check()
        var frame = _Frame(prop, ground)
        if prop.kind == FENCE:
            standing.walls.append(_fence(sheets, frame, prop.length))
            continue
        if prop.kind == HEDGE:
            standing.walls.append(_hedge(sheets, frame, prop.length))
            continue
        if prop.kind == CROPS:
            _crops(sheets, frame, prop.length)
            continue
        standing.lots.append(_footprint(prop))
        if prop.kind == WELL:
            _well(sheets, frame, prop.length)
        elif prop.kind == BARREL:
            _barrel(sheets, frame, prop.length)
        elif prop.kind == CRATE:
            _crate(sheets, frame, prop.length)
        elif prop.kind == HAY_BALE:
            _hay(sheets, frame, prop.length)
        elif prop.kind == BENCH:
            _bench(sheets, frame, prop.length)
        elif prop.kind == WOODPILE:
            _woodpile(sheets, frame, prop.length)
        elif prop.kind == CART:
            _cart(sheets, frame, prop.length)
        elif prop.kind == SIGNPOST:
            _signpost(sheets, frame, prop.length)
        elif prop.kind == WASHING_LINE:
            _washing_line(sheets, frame, prop.length)
        elif prop.kind == TROUGH:
            _trough(sheets, frame, prop.length)
        elif prop.kind == SCARECROW:
            _scarecrow(sheets, frame, prop.length)
        else:
            _lamp_post(sheets, frame, prop.length)
    _add(scene, assets, sheets.wood, looks.wood, root, standing)
    _add(scene, assets, sheets.ashlar, looks.ashlar, root, standing)
    _add(scene, assets, sheets.plaster, looks.plaster, root, standing)
    _add(scene, assets, sheets.tiles, looks.tiles, root, standing)
    _add(scene, assets, sheets.cloth, looks.cloth, root, standing)
    _add(scene, assets, sheets.water, looks.daylight, root, standing)
    _add(scene, assets, sheets.glow, looks.daylight, lit, standing)
    _add(scene, assets, sheets.cold, looks.daylight, daylit, standing)
    return standing^
