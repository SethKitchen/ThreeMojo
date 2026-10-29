# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The small things that make a house a home: rugs, quilts, pottery,
candles, lanterns, books and bundles of herbs, and the warm light of a
fire on what stands near it.

The village's view of a house, `extensions.village.house_view`, calls
these to dress its rooms. Each draws into a `Sheet`, so each is drawn
with a material of `HouseLooks`:

| Function | Draws |
|---|---|
| `prism` | A post, a jar, a mug or a candle: a prism of a few sides with a lid, narrower or wider at its top |
| `rug` | A woven rug of sixteen by ten cells: a border, a cream line, a field and a medallion |
| `patchwork` | A quilt's top of four by five patches, of three dyes |
| `table_setting` | Plates, mugs, a bowl and a candle on a table |
| `jars` | Three jars and pots of glazed earthenware on a shelf |
| `books` | A stack of books bound in leather, and a candle |
| `lantern` | A lantern of iron and glowing glass on a chain from the ceiling |
| `herbs` | A pole under the ceiling, with bundles of drying herbs |

A candle, a lantern and a fire each give a `Glow`. A flame is drawn on
the unlit sheet, so it glows in a dark room. The game renderer has no
lamps, so `warm` bakes each glow's light into the vertex colors of the
surfaces that face it: see `warmth`.
"""

from extensions.vegetation.noise import hash01
from extensions.village.sheet import Sheet
from math.vector3 import Vector3
from std.math import cos, pi, sin

comptime FIRELIGHT = Vector3(1.0, 0.62, 0.3)
"""The tint of a fire's light on the surfaces that it warms."""
comptime FLAME = Vector3(1.0, 0.78, 0.4)
"""The color of a flame, drawn unlit."""
comptime FILL = Vector3(1.45, 1.28, 1.05)
"""How much the light that bounces round a lit room raises the colors
of its surfaces: warm, as the light off wood floors and limewash is."""
comptime WAX = Vector3(0.92, 0.86, 0.7)
"""The color of a tallow candle."""
comptime WROUGHT = Vector3(0.08, 0.075, 0.07)
"""The color of wrought iron over the wood texture."""
comptime RUG_CELLS = 16
"""A rug's cells along its length."""
comptime RUG_ROWS = 10
"""A rug's cells across it."""
comptime RUG_LIFT = Float32(0.015)
"""How far a rug's top stands over the floor, in meters."""
comptime PATCHES_ALONG = 4
"""A quilt's patches along the bed's width."""
comptime PATCHES_DOWN = 5
"""A quilt's patches along the bed's length."""
comptime CANDLE = Glow(Vector3(0, 0, 0), 0.6, 2.5, 0, 0)
"""The light of one candle at its flame: see `Glow`."""
comptime LANTERN = Glow(Vector3(0, 0, 0), 0.9, 4.0, 0, 0)
"""The light of a lantern at its flame: see `Glow`."""
comptime HEARTH = Glow(Vector3(0, 0, 0), 1.6, 5.0, 0, 0)
"""The light of a fire on a hearth at its embers: see `Glow`."""


@fieldwise_init
struct Glow(ImplicitlyCopyable):
    """A flame that warms what is near it: a candle, a lantern or a fire."""

    # Where the flame is, in the house's frame.
    var at: Vector3
    # The share of light it adds to a surface that faces it from close by.
    var strength: Float32
    # How far its light reaches, in meters. Nothing further is warmed.
    var reach: Float32
    # The floor and the ceiling of its storey: it warms nothing outside
    # these heights, so a fire downstairs does not warm the room above.
    var low: Float32
    var high: Float32

    def placed(self, at: Vector3, low: Float32, high: Float32) -> Glow:
        """Return this glow at a place, in a storey.

        Args:
            at: Where the flame is.
            low: The height of the storey's floor.
            high: The height of its ceiling.

        Returns:
            The same strength and reach, at the place.
        """
        return Glow(at, self.strength, self.reach, low, high)


def dye(index: Int) -> Vector3:
    """Return one of the dyes of the wool.

    Args:
        index: Any number: the dyes repeat.

    Returns:
        Madder, woad, weld, nettle or walnut.
    """
    var dyes: List[Vector3] = [
        Vector3(0.55, 0.12, 0.08),
        Vector3(0.14, 0.22, 0.42),
        Vector3(0.62, 0.5, 0.16),
        Vector3(0.24, 0.36, 0.18),
        Vector3(0.36, 0.22, 0.12),
    ]
    return dyes[index % len(dyes)]


def glaze(index: Int) -> Vector3:
    """Return one of the glazes of the pottery.

    Args:
        index: Any number: the glazes repeat.

    Returns:
        Earthenware, green, cream, blue or red.
    """
    var glazes: List[Vector3] = [
        Vector3(0.55, 0.3, 0.17),
        Vector3(0.3, 0.42, 0.25),
        Vector3(0.82, 0.76, 0.62),
        Vector3(0.25, 0.3, 0.42),
        Vector3(0.48, 0.2, 0.12),
    ]
    return glazes[index % len(glazes)]


def warmth(glows: List[Glow], p: Vector3, n: Vector3) -> Float32:
    """Return how much light the glows add to a surface at a point.

    Each glow adds its strength times the cosine between the surface's
    normal and the way to the flame, times the square of what is left of
    its reach. A surface that faces away from a flame takes none of it.

    Args:
        glows: The flames.
        p: The point.
        n: The surface's normal there, of length one.

    Returns:
        The share of light added, zero or more.
    """
    var total = Float32(0)
    for g in glows:
        if p.y < g.low or p.y > g.high:
            continue
        var d = g.at - p
        var distance = d.length()
        if distance >= g.reach:
            continue
        var facing = Float32(1)
        if distance > 1.0e-4:
            facing = max(Float32(0), n.dot(d) / distance)
        var left = 1 - distance / g.reach
        total += g.strength * facing * left * left
    return total


def warm(
    mut sheet: Sheet,
    glows: List[Glow],
    half_x: Float32,
    half_z: Float32,
    fill: Vector3,
):
    """Bake the light inside a house into the colors of a sheet's vertices:
    the fill of the light that bounces round its rooms, and each glow's
    light.

    Only a vertex within the house's walls is lit so, so a flame does not
    light the outside of the wall that it stands by.

    Args:
        sheet: The sheet, in the house's frame.
        glows: The flames.
        half_x: Half the house's width, to the middle of its walls.
        half_z: Half its depth.
        fill: What each color is multiplied by before the glows add to it:
            `FILL` in a dwelling, one for no change.
    """
    for v in range(len(sheet.positions) // 3):
        var p = Vector3(
            sheet.positions[3 * v],
            sheet.positions[3 * v + 1],
            sheet.positions[3 * v + 2],
        )
        if abs(p.x) > half_x or abs(p.z) > half_z:
            continue
        var n = Vector3(
            sheet.normals[3 * v],
            sheet.normals[3 * v + 1],
            sheet.normals[3 * v + 2],
        )
        var w = warmth(glows, p, n)
        sheet.colors[3 * v] *= fill.x * (1 + FIRELIGHT.x * w)
        sheet.colors[3 * v + 1] *= fill.y * (1 + FIRELIGHT.y * w)
        sheet.colors[3 * v + 2] *= fill.z * (1 + FIRELIGHT.z * w)


def prism(
    mut sheet: Sheet,
    foot: Vector3,
    radius: Float32,
    top: Float32,
    height: Float32,
    sides: Int,
    color: Vector3,
):
    """Add an upright prism with a lid: a post, a jar, a mug or a candle.

    Args:
        sheet: The sheet.
        foot: The middle of its foot.
        radius: Its radius at the foot, in meters.
        top: Its radius at the top, in meters.
        height: Its height, in meters.
        sides: How many sides, three or more.
        color: Its color.
    """
    var count = max(3, sides)
    var lid = foot + Vector3(0, height, 0)
    var middle = sheet.vertex(lid, Vector3(0, 1, 0), color, 0, 0)
    var rim = List[Int]()
    for k in range(count):  # pragma: no branch
        var a0 = 2 * pi * Float32(k) / Float32(count)
        var a1 = 2 * pi * Float32(k + 1) / Float32(count)
        var d0 = Vector3(cos(a0), 0, -sin(a0))
        var d1 = Vector3(cos(a1), 0, -sin(a1))
        var u0 = radius * a0
        var u1 = radius * a1
        sheet.painted_quad(
            foot + d0 * radius,
            foot + d1 * radius,
            lid + d1 * top,
            lid + d0 * top,
            color,
            color,
            color,
            color,
            u0,
            0,
            u1,
            height,
        )
        rim.append(
            sheet.vertex(
                lid + d0 * top, Vector3(0, 1, 0), color, d0.x * top, d0.z * top
            )
        )
    for k in range(count):  # pragma: no branch
        sheet.triangle(middle, rim[k], rim[(k + 1) % count])


def rug(
    mut sheet: Sheet,
    x0: Float32,
    x1: Float32,
    z0: Float32,
    z1: Float32,
    floor: Float32,
    seed: Int,
):
    """Add a woven rug on a floor, its edges along x and z.

    The rug is `RUG_CELLS` cells along x and `RUG_ROWS` across, each cell
    of one color: a border of one dye inside a cream line, a field of
    another, and a diamond medallion of a third with a cream heart, and a
    cream fringe at each end.

    Args:
        sheet: The cloth's sheet.
        x0: Its least x.
        x1: Its greatest x.
        z0: Its least z.
        z1: Its greatest z.
        floor: The height of the floor under it.
        seed: Which dyes.
    """
    var field = dye(seed) * 0.9
    var border = dye(seed + 1) * 0.8
    var motif = dye(seed + 2)
    var cream = Vector3(0.82, 0.76, 0.62)
    var y = floor + RUG_LIFT
    var du = (x1 - x0) / Float32(RUG_CELLS)
    var dv = (z1 - z0) / Float32(RUG_ROWS)
    for j in range(RUG_ROWS):  # pragma: no branch
        for i in range(RUG_CELLS):  # pragma: no branch
            # The cell's middle, from -1 to 1 each way.
            var cx = Float32(2 * i + 1 - RUG_CELLS) / Float32(RUG_CELLS)
            var cz = Float32(2 * j + 1 - RUG_ROWS) / Float32(RUG_ROWS)
            var ring = min(min(i, RUG_CELLS - 1 - i), min(j, RUG_ROWS - 1 - j))
            var medallion = abs(cx) + abs(cz) * 1.6
            var color = field
            if ring == 0:
                color = border
            elif ring == 1:
                color = cream
            elif medallion < 0.3:
                color = cream
            elif medallion < 0.75:
                color = motif
            var a = x0 + du * Float32(i)
            var b = z0 + dv * Float32(j)
            sheet.painted_quad(
                Vector3(a, y, b + dv),
                Vector3(a + du, y, b + dv),
                Vector3(a + du, y, b),
                Vector3(a, y, b),
                color,
                color,
                color,
                color,
                a,
                -(b + dv),
                a + du,
                -b,
            )
    # The fringe: a strip of threads past each short end.
    for end in range(2):
        var x = x0 - 0.04 if end == 0 else x1
        sheet.quad(
            Vector3(x, y - 0.005, z1),
            Vector3(x + 0.04, y - 0.005, z1),
            Vector3(x + 0.04, y - 0.005, z0),
            Vector3(x, y - 0.005, z0),
            cream,
        )


def patchwork(
    mut sheet: Sheet,
    middle: Vector3,
    side: Vector3,
    front: Vector3,
    half_width: Float32,
    half_length: Float32,
    seed: Int,
):
    """Add a quilt's top of patches, facing up.

    Args:
        sheet: The cloth's sheet.
        middle: The middle of the quilt's top.
        side: Along the bed's width, of length one.
        front: Along the bed's length, of length one, so that `side`
            cross `front` points up, as a piece of furniture's do.
        half_width: Half the quilt's width.
        half_length: Half its length.
        seed: Which dyes.
    """
    var du = 2 * half_width / Float32(PATCHES_ALONG)
    var dv = 2 * half_length / Float32(PATCHES_DOWN)
    var corner = middle - side * half_width - front * half_length
    for j in range(PATCHES_DOWN):  # pragma: no branch
        for i in range(PATCHES_ALONG):  # pragma: no branch
            var pick = Int(hash01(i, j, seed) * 3)
            var color = dye(seed + pick) * (0.85 + 0.1 * Float32((i + j) % 2))
            var p = (
                corner + side * (du * Float32(i)) + front * (dv * Float32(j))
            )
            sheet.quad(
                p,
                p + side * du,
                p + side * du + front * dv,
                p + front * dv,
                color,
            )


def _candle(
    mut wax: Sheet, mut flame: Sheet, foot: Vector3, tall: Float32
) -> Vector3:
    """Add a candle in an iron dish and its flame; return the flame's
    place."""
    prism(wax, foot, 0.05, 0.045, 0.015, 8, WROUGHT * 3)
    prism(wax, foot + Vector3(0, 0.015, 0), 0.016, 0.015, tall, 6, WAX)
    var tip = foot + Vector3(0, 0.015 + tall, 0)
    # The flame: a small diamond of two crossed quads.
    var at = tip + Vector3(0, 0.03, 0)
    for k in range(2):
        var d = Vector3(0.012, 0, 0) if k == 0 else Vector3(0, 0, 0.012)
        flame.painted_quad(
            tip - d,
            tip + d,
            at + Vector3(0, 0.03, 0) + d * 0.2,
            at + Vector3(0, 0.03, 0) - d * 0.2,
            FLAME,
            FLAME,
            FLAME * 0.6,
            FLAME * 0.6,
            0,
            0,
            1,
            1,
        )
        flame.painted_quad(
            tip + d,
            tip - d,
            at + Vector3(0, 0.03, 0) - d * 0.2,
            at + Vector3(0, 0.03, 0) + d * 0.2,
            FLAME,
            FLAME,
            FLAME * 0.6,
            FLAME * 0.6,
            0,
            0,
            1,
            1,
        )
    return at


def table_setting(
    mut pottery: Sheet,
    mut flame: Sheet,
    top: Vector3,
    side: Vector3,
    front: Vector3,
    half_width: Float32,
    half_depth: Float32,
    seed: Int,
) -> Vector3:
    """Lay a table: a plate and a mug at each place along both long sides,
    a bowl, and a candle in the middle.

    Args:
        pottery: The sheet of the pottery and the candle.
        flame: The unlit sheet of the flame.
        top: The middle of the table's top.
        side: Along the table's width, of length one.
        front: Along its depth, of length one.
        half_width: Half its width.
        half_depth: Half its depth.
        seed: Which glazes.

    Returns:
        Where the candle's flame is.
    """
    var places = max(1, Int(half_width / 0.35))
    for k in range(places):  # pragma: no branch
        var t = (Float32(k) + 0.5) / Float32(places) * 2 - 1
        var along = side * (t * half_width * 0.8)
        for sz in [Float32(1), Float32(-1)]:
            var at = top + along + front * (sz * half_depth * 0.55)
            prism(pottery, at, 0.09, 0.11, 0.018, 10, glaze(seed + k))
            prism(
                pottery,
                at + side * 0.14 - front * (sz * 0.04),
                0.035,
                0.04,
                0.09,
                8,
                glaze(seed + k + 2),
            )
    # A bowl of a different glaze, by the candle.
    prism(pottery, top + side * 0.18, 0.06, 0.12, 0.07, 10, glaze(seed + 1))
    return _candle(pottery, flame, top - side * 0.08, 0.14)


def jars(
    mut pottery: Sheet,
    board: Vector3,
    side: Vector3,
    half_width: Float32,
    depth: Float32,
    seed: Int,
):
    """Stand three jars and pots of different glazes and heights on a
    shelf's board.

    Args:
        pottery: The pottery's sheet.
        board: The middle of the board's top.
        side: Along the shelf, of length one.
        half_width: Half the shelf's width.
        depth: How deep the shelf is.
        seed: Which glazes and heights.
    """
    var radius = min(Float32(0.09), depth * 0.35)
    for k in range(3):
        var t = Float32(k - 1) * 0.6
        var tall = 0.1 + 0.12 * hash01(k, seed, 7)
        var neck = radius * (0.5 + 0.5 * hash01(seed, k, 8))
        prism(
            pottery,
            board + side * (t * half_width),
            radius * 0.85,
            neck,
            tall,
            8,
            glaze(seed + k),
        )


def books(
    mut bound: Sheet,
    mut flame: Sheet,
    top: Vector3,
    side: Vector3,
    front: Vector3,
    seed: Int,
) -> Vector3:
    """Stack four books on a desk, and stand a candle beside them.

    Args:
        bound: The sheet the books and the candle are drawn on.
        flame: The unlit sheet of the flame.
        top: The middle of the desk's top.
        side: Along the desk's width, of length one.
        front: Along its depth, of length one.
        seed: Which bindings.

    Returns:
        Where the candle's flame is.
    """
    var y = Float32(0)
    for k in range(4):
        var thick = 0.03 + 0.02 * hash01(k, seed, 3)
        var turn = 0.15 * (hash01(seed, k, 4) - 0.5)
        var across = side * cos(turn) + front * sin(turn)
        var deep = front * cos(turn) - side * sin(turn)
        bound.box(
            top + side * 0.15 + Vector3(0, y + thick / 2, 0),
            across * 0.12,
            Vector3(0, thick / 2, 0),
            deep * (-0.09),
            dye(seed + k) * 0.7,
        )
        y += thick
    return _candle(bound, flame, top - side * 0.2, 0.12)


def lantern(
    mut iron: Sheet,
    mut flame: Sheet,
    ceiling: Vector3,
    drop: Float32,
) -> Vector3:
    """Hang a lantern from the ceiling on a chain.

    Args:
        iron: The sheet of its iron.
        flame: The unlit sheet of its glowing glass.
        ceiling: Where the chain meets the ceiling.
        drop: How far below the ceiling the lantern's foot hangs.

    Returns:
        Where its flame is.
    """
    var foot = ceiling - Vector3(0, drop, 0)
    var height = Float32(0.26)
    var half = Float32(0.08)
    # The chain, down to the lantern's cap.
    iron.box(
        ceiling - Vector3(0, (drop - height) / 2, 0),
        Vector3(0.008, 0, 0),
        Vector3(0, (drop - height) / 2, 0),
        Vector3(0, 0, 0.008),
        WROUGHT,
    )
    # A base, a pyramid cap and four corner posts.
    prism(iron, foot, half * 1.5, half * 1.3, 0.03, 4, WROUGHT)
    prism(
        iron,
        foot + Vector3(0, height - 0.06, 0),
        half * 1.5,
        0.01,
        0.07,
        4,
        WROUGHT,
    )
    for k in range(4):
        var a = pi / 2 * Float32(k)
        var d = Vector3(cos(a), 0, -sin(a)) * (half * 1.4)
        iron.box(
            foot + d + Vector3(0, height / 2, 0),
            Vector3(0.01, 0, 0),
            Vector3(0, height / 2 - 0.02, 0),
            Vector3(0, 0, 0.01),
            WROUGHT,
        )
    # The glowing glass, brightest low where the flame burns.
    var core = foot + Vector3(0, 0.03, 0)
    var glass_height = height - 0.1
    prism(flame, core, half, half, glass_height, 4, FLAME * 0.8)
    return core + Vector3(0, glass_height * 0.4, 0)


def herbs(
    mut wood: Sheet,
    start: Vector3,
    end: Vector3,
    seed: Int,
):
    """Hang bundles of herbs to dry from a pole under the ceiling.

    Args:
        wood: The sheet of the pole and the herbs.
        start: One end of the pole.
        end: The other end, at the same height.
        seed: Which herbs, and how long each bundle hangs.
    """
    var span = end - start
    var length = span.length()
    var along = span / max(length, Float32(1.0e-4))
    var middle = (start + end) / 2
    wood.box(
        middle,
        along * (length / 2),
        Vector3(0, 0.02, 0),
        Vector3(-along.z, 0, along.x) * 0.02,
        Vector3(0.48, 0.48, 0.48) * 0.8,
    )
    var count = max(1, Int(length / 0.22))
    # Green, sage, lavender and straw.
    var tints: List[Vector3] = [
        Vector3(0.24, 0.34, 0.14),
        Vector3(0.36, 0.38, 0.2),
        Vector3(0.42, 0.32, 0.46),
        Vector3(0.45, 0.36, 0.18),
    ]
    for k in range(count):  # pragma: no branch
        var t = (Float32(k) + 0.5) / Float32(count)
        var at = start + span * t
        var hang = 0.18 + 0.14 * hash01(k, seed, 5)
        # The string, then the bundle: wide at its foot, where the leaves
        # hang, and tied narrow at its top.
        wood.box(
            at - Vector3(0, 0.05, 0),
            Vector3(0.004, 0, 0),
            Vector3(0, 0.05, 0),
            Vector3(0, 0, 0.004),
            Vector3(0.6, 0.55, 0.4),
        )
        prism(
            wood,
            at - Vector3(0, 0.1 + hang, 0),
            0.07,
            0.012,
            hang,
            6,
            tints[(k + seed) % len(tints)],
        )
