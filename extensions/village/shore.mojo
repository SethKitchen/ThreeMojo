# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pond's shore: reeds, cattails, stones and lily pads.

`stand_shore` dresses the edge of a ground's pond:

| Part | Where it grows or lies | What it is |
|---|---|---|
| Reeds | In clumps where the water is shallow, and on the wet mud just above it | Thin blades, 0.8 to 1.6 meters tall, green at the foot and tan at the tip |
| Cattails | In some of the clumps | Stems with a brown head |
| Stones | On the damp band of the shore | Gray, flattened rocks |
| Lily pads | On the open water, away from the shore | Flat round leaves with a notch, some with a white flower |

A blade is a thin quad with a face to each side, so it shows from both.
Nothing of the shore stops a character. Nothing stands on a lot or its
apron.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.vegetation.ground import Ground, Lot, lot_openness
from extensions.vegetation.noise import hash01
from extensions.village.sheet import Sheet
from extensions.village.surfaces import HouseLooks, PLASTER_TILE
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, sin, sqrt
from units.si import METER, Length

comptime REED_GREEN = Vector3(0.22, 0.38, 0.10)
"""The linear color of a reed at its foot."""
comptime REED_TAN = Vector3(0.58, 0.50, 0.27)
"""The linear color of a reed's dry tip."""
comptime CATTAIL = Vector3(0.30, 0.17, 0.08)
"""The linear color of a cattail's head."""
comptime STONE_GRAY = Vector3(0.42, 0.40, 0.37)
"""The linear color of a shore stone."""
comptime PAD_GREEN = Vector3(0.10, 0.24, 0.06)
"""The linear color of a lily pad."""
comptime BLOOM = Vector3(0.95, 0.92, 0.88)
"""The linear color of a water lily's flower."""
comptime SHALLOWEST = Float32(-0.12)
"""The highest ground, above the water, that a reed grows on, in meters
below the water: so up to 12 centimeters above it."""
comptime DEEPEST = Float32(0.15)
"""The deepest water that a reed grows in, in meters."""
comptime PAD_FLOAT = Float32(0.035)
"""How far above the still water a lily pad lies, in meters, so the
waves do not cover it."""
comptime TRIES = 40
"""How many places each part tries for each of its pieces."""
comptime BEDS = 4
"""How many beds round the pond the clumps of reeds gather in."""
comptime BED_SPREAD = Float32(0.35)
"""How far round the pond, in radians, a bed's clumps spread from its
middle."""


struct ShoreParameters(Copyable, Movable):
    """How much of each part dresses the pond's shore."""

    var reeds: Int
    """How many clumps of reeds grow, from 0 to 500."""
    var stones: Int
    """How many stones lie on the shore, from 0 to 500."""
    var pads: Int
    """How many lily pads float on the water, from 0 to 500."""
    var seed: Int
    """The seed that places every piece."""

    def __init__(out self):
        """Make the village's shore: 16 clumps of reeds, 30 stones and 14
        lily pads."""
        self.reeds = 16
        self.stones = 30
        self.pads = 14
        self.seed = 5

    def check(self) raises:
        """Refuse counts that cannot be drawn.

        Raises:
            Error: If a count is not from 0 to 500.
        """
        for count in [self.reeds, self.stones, self.pads]:
            if count < 0 or count > 500:
                raise Error("A shore's parts must number from 0 to 500")


struct StandingShore(Movable):
    """What the shore drew."""

    var root: NodeId
    """The node that the shore's mesh hangs from."""
    var meshes: Int
    """How many meshes the shore drew: zero or one."""
    var triangles: Int
    """How many triangles the shore drew."""
    var reeds: Int
    """How many clumps of reeds grew."""
    var stones: Int
    """How many stones lie on the shore."""
    var pads: Int
    """How many lily pads float on the water."""

    def __init__(out self, root: NodeId):
        """Hold nothing yet, under a node.

        Args:
            root: The node the shore hangs from.
        """
        self.root = root
        self.meshes = 0
        self.triangles = 0
        self.reeds = 0
        self.stones = 0
        self.pads = 0


def _depth(ground: Ground, x: Float32, z: Float32) -> Float32:
    """Return how far below the pond's water the ground lies at a point."""
    return ground.water_level() - ground.height_at(x, z)


def _blade(
    mut sheet: Sheet,
    foot: Vector3,
    lean: Vector3,
    height: Float32,
    width: Float32,
    across: Vector3,
):
    """Add a reed's blade: a thin quad that tapers to its tip, with a face
    to each side."""
    var half = across * (width * 0.5)
    var tip = foot + Vector3(0, height, 0) + lean * height
    var a = foot - half
    var b = foot + half
    var c = tip + half * 0.15
    var d = tip - half * 0.15
    var n = Vector3(-across.z, 0, across.x)
    var back = Vector3(0, 0, 0) - n
    var ia = sheet.vertex(a, n, REED_GREEN, 0, 0)
    var ib = sheet.vertex(b, n, REED_GREEN, width, 0)
    var ic = sheet.vertex(c, n, REED_TAN, width, height)
    var id = sheet.vertex(d, n, REED_TAN, 0, height)
    sheet.triangle(ia, ib, ic)
    sheet.triangle(ia, ic, id)
    var ja = sheet.vertex(a, back, REED_GREEN, 0, 0)
    var jb = sheet.vertex(b, back, REED_GREEN, width, 0)
    var jc = sheet.vertex(c, back, REED_TAN, width, height)
    var jd = sheet.vertex(d, back, REED_TAN, 0, height)
    sheet.triangle(ja, jc, jb)
    sheet.triangle(ja, jd, jc)


def _clump(
    mut sheet: Sheet,
    ground: Ground,
    x: Float32,
    z: Float32,
    seed: Int,
    key: Int,
):
    """Add a clump of reeds round a point, with cattails in some."""
    var blades = 5 + Int(hash01(key, 1, seed) * 7)
    var cattails = hash01(key, 2, seed) < 0.3
    for b in range(blades):  # pragma: no branch
        var a = hash01(key, 10 + b, seed) * 6.2831855
        var r = 0.25 * sqrt(hash01(key, 40 + b, seed))
        var bx = x + r * cos(a)
        var bz = z + r * sin(a)
        var foot = Vector3(bx, ground.height_at(bx, bz) - 0.05, bz)
        var height = 0.5 + 0.6 * hash01(key, 70 + b, seed)
        var lean_turn = hash01(key, 100 + b, seed) * 6.2831855
        var lean = Vector3(cos(lean_turn), 0, sin(lean_turn)) * (
            0.05 + 0.3 * hash01(key, 130 + b, seed)
        )
        var face = hash01(key, 160 + b, seed) * 6.2831855
        var across = Vector3(cos(face), 0, sin(face))
        _blade(sheet, foot, lean, height, 0.02, across)
        if cattails and b % 4 == 0:
            # A cattail's head stands near the top of its stem.
            var top = (
                foot + Vector3(0, height * 0.82, 0) + lean * (height * 0.82)
            )
            sheet.box(
                top,
                Vector3(0.014, 0, 0),
                Vector3(0, 0.05, 0),
                Vector3(0, 0, 0.014),
                CATTAIL,
            )


def _stone(
    mut sheet: Sheet,
    ground: Ground,
    x: Float32,
    z: Float32,
    key: Int,
    seed: Int,
):
    """Add a rounded stone: a crown over a ring of eight points, and a
    skirt from the ring down into the mud."""
    var size = 0.05 + 0.11 * hash01(key, 1, seed)
    var turn = hash01(key, 2, seed) * 6.2831855
    var shade = STONE_GRAY * (0.7 + 0.45 * hash01(key, 3, seed))
    var foot = Vector3(x, ground.height_at(x, z) - size * 0.2, z)
    var crown = sheet.vertex(
        foot + Vector3(0, size * 0.6, 0), Vector3(0, 1, 0), shade, 0, 0
    )
    var rim = List[Vector3]()
    var ring = List[Int]()
    for k in range(8):  # pragma: no branch
        var a = turn + Float32(k) * 0.7853982
        var reach = size * (0.75 + 0.5 * hash01(key, 10 + k, seed))
        var p = foot + Vector3(reach * cos(a), size * 0.3, reach * sin(a))
        var n = Vector3(cos(a), 0.8, sin(a))
        rim.append(p)
        ring.append(sheet.vertex(p, n / n.length(), shade, 0, 0))
    for k in range(8):  # pragma: no branch
        var next = (k + 1) % 8
        sheet.triangle(crown, ring[next], ring[k])
        # The skirt runs from the ring down below the mud, outward.
        var p = rim[k]
        var q = rim[next]
        var drop = Vector3(0, size * 0.5, 0)
        sheet.quad(q - drop, p - drop, p, q, shade * 0.8)


def _pad(mut sheet: Sheet, at: Vector3, key: Int, seed: Int):
    """Add a lily pad: a flat disc with a notch, and now and then a
    flower."""
    var radius = 0.12 + 0.12 * hash01(key, 1, seed)
    var notch = hash01(key, 2, seed) * 6.2831855
    var up = Vector3(0, 1, 0)
    var shade = PAD_GREEN * (0.8 + 0.4 * hash01(key, 3, seed))
    var middle = sheet.vertex(at, up, shade, 0, 0)
    var sides = 12
    var ring = List[Int]()
    for k in range(sides + 1):  # pragma: no branch
        # The notch is a wedge of the disc that is missing.
        var a = notch + 0.5 + Float32(k) / Float32(sides) * 5.7831855
        var p = at + Vector3(radius * cos(a), 0, radius * sin(a))
        ring.append(sheet.vertex(p, up, shade, 0, 0))
    for k in range(sides):  # pragma: no branch
        sheet.triangle(middle, ring[k + 1], ring[k])
    if hash01(key, 4, seed) < 0.3:
        sheet.box(
            at + Vector3(0, 0.03, 0),
            Vector3(0.04, 0, 0),
            Vector3(0, 0.03, 0),
            Vector3(0, 0, 0.04),
            BLOOM,
        )


def stand_shore(
    mut scene: Scene,
    mut assets: Assets,
    looks: HouseLooks,
    parameters: ShoreParameters,
    ground: Ground,
    lots: List[Lot],
) raises -> StandingShore:
    """Dress a ground's pond with reeds, cattails, stones and lily pads.

    Args:
        scene: The scene. A node, and a mesh if any piece is drawn, are
            added.
        assets: The stores for the geometry.
        looks: The houses' materials. The shore wears their plaster,
            tinted.
        parameters: How much of each part to draw.
        ground: The ground with the pond.
        lots: The ground kept clear: nothing stands on a lot or its apron.

    Returns:
        The node, what it draws, and how many of each part it placed. A
        ground with no pond gets nothing.

    Raises:
        Error: If `parameters.check` refuses a count.
    """
    parameters.check()
    var root = scene.add(Object3D())
    var standing = StandingShore(root)
    ref pond = ground.pond
    var radius = pond.radius.to(METER)
    if radius <= 0:
        return standing^
    var cx = pond.x.to(METER)
    var cz = pond.z.to(METER)
    var seed = parameters.seed
    var sheet = Sheet(PLASTER_TILE)
    var level = ground.water_level()
    var key = 0
    # Each part tries places round the pond until it has its count.
    for part in range(3):  # pragma: no branch
        var want = parameters.reeds
        if part == 1:
            want = parameters.stones
        elif part == 2:
            want = parameters.pads
        var placed = 0
        var tries = 0
        while placed < want and tries < want * TRIES:
            tries += 1
            key += 1
            var a = hash01(key, part, seed) * 6.2831855
            if part == 0:
                # Reeds gather in a few beds round the pond.
                var bed = Int(hash01(key, 20, seed) * Float32(BEDS))
                a = hash01(bed, 21, seed) * 6.2831855 + BED_SPREAD * (
                    2 * hash01(key, 22, seed) - 1
                )
            var r = radius * (0.25 + 0.85 * hash01(key, part + 7, seed))
            var x = cx + r * cos(a)
            var z = cz + r * sin(a)
            if lot_openness(lots, x, z) < 1:
                continue
            var depth = _depth(ground, x, z)
            if part == 0:
                if depth < SHALLOWEST or depth > DEEPEST:
                    continue
                _clump(sheet, ground, x, z, seed, key)
            elif part == 1:
                # Stones lie on the damp band, and just under the water.
                if depth < -0.12 or depth > 0.06:
                    continue
                _stone(sheet, ground, x, z, key, seed)
            else:
                if depth < 0.6:
                    continue
                _pad(sheet, Vector3(x, level + PAD_FLOAT, z), key, seed)
            placed += 1
        if part == 0:
            standing.reeds = placed
        elif part == 1:
            standing.stones = placed
        else:
            standing.pads = placed
    if sheet.triangles() > 0:
        scene.add_mesh(
            Mesh(
                assets.geometries.add(sheet.geometry()),
                looks.plaster,
                root,
                cast_shadow=True,
                receive_shadow=True,
            )
        )
        standing.meshes = 1
        standing.triangles = sheet.triangles()
    return standing^
