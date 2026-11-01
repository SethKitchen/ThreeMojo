# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The things that stand about the village: a well, barrels, crates, hay
bales, fences, benches and woodpiles.

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

A prop stands on the ground at its middle, and its foot reaches a little
below the ground, so a slope shows no gap.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.ordinal import ordinal_valid
from core.scene import Scene
from extensions.vegetation.checks import require_between
from extensions.vegetation.ground import Ground, Lot
from extensions.village.house_view import OAK, STONE
from extensions.village.sheet import Sheet
from extensions.village.surfaces import (
    ASHLAR_TILE,
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


@fieldwise_init
struct PropKind(Equatable, ImplicitlyCopyable, Writable):
    """What a prop is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return ordinal_valid(self.value, 6)


comptime WELL = PropKind(0)
comptime BARREL = PropKind(1)
comptime CRATE = PropKind(2)
comptime HAY_BALE = PropKind(3)
comptime FENCE = PropKind(4)
comptime BENCH = PropKind(5)
comptime WOODPILE = PropKind(6)


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
            raise Error("A prop's kind must be one of the seven")
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
    # Each prop's footprint but a fence's, and each fence.
    var lots: List[Lot]
    var walls: List[WallSpan]

    def __init__(out self, root: NodeId):
        """Hold no prop yet, under a node.

        Args:
            root: The node the props hang from.
        """
        self.root = root
        self.meshes = 0
        self.triangles = 0
        self.lots = List[Lot]()
        self.walls = List[WallSpan]()


struct _PropSheets(Movable):
    """The sheets of the props, one per material."""

    var wood: Sheet
    var ashlar: Sheet
    var plaster: Sheet
    var tiles: Sheet

    def __init__(out self):
        self.wood = Sheet(WOOD_TILE)
        self.ashlar = Sheet(ASHLAR_TILE)
        self.plaster = Sheet(PLASTER_TILE)
        self.tiles = Sheet(TILE_TILE)


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


def _footprint(prop: Prop) -> Lot:
    """Return the ground a prop that is not a fence takes up."""
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
        scene: The scene. One node, and one mesh for each material the
            props wear, are added.
        assets: The stores for the geometries.
        looks: The houses' materials, which the props wear too.
        props: The props.
        ground: The ground they stand on.

    Returns:
        The node, what it draws, and a solid lot for each prop but a
        fence, and a wall span for each fence.

    Raises:
        Error: If a prop does not check.
    """
    var root = scene.add(Object3D())
    var standing = StandingProps(root)
    var sheets = _PropSheets()
    for prop in props:
        prop.check()
        var frame = _Frame(prop, ground)
        if prop.kind == FENCE:
            standing.walls.append(_fence(sheets, frame, prop.length))
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
        else:
            _woodpile(sheets, frame, prop.length)
    _add(scene, assets, sheets.wood, looks.wood, root, standing)
    _add(scene, assets, sheets.ashlar, looks.ashlar, root, standing)
    _add(scene, assets, sheets.plaster, looks.plaster, root, standing)
    _add(scene, assets, sheets.tiles, looks.tiles, root, standing)
    return standing^
