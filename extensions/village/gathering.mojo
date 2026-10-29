# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Things a player can gather about the village: herbs, mushrooms,
berries, ore, chests and lost trinkets.

Each `Spot` is a kind and a place on the ground. `Gathering` draws every
spot, and lets a player use the nearest one within reach:

| Kind | What it is | A use gives | It comes back |
|---|---|---|---|
| `HERBS` | A tuft of leaves with pale flowers | 1 herb | After the respawn time |
| `MUSHROOMS` | A cluster of red-capped mushrooms | 2 mushrooms | After the respawn time |
| `BERRIES` | A low bush hung with berries. The bush stays. | 3 berries | After the respawn time |
| `ORE` | A boulder with copper veins. It takes `STRIKES` uses. The boulder stays. | 1 ore | After the respawn time |
| `CHEST` | An iron-bound chest. Its lid swings open. | `CHEST_COINS` coins | Never |
| `TRINKET` | A gold trinket with a gem, which bobs and turns in the air | 1 trinket | Never |
| `FISH` | An oak stake on a pond's shore, with a creel. Its float lies on the water `CAST` out. | 1 fish, when hooked | It is never used up |

At a fishing spot, a press casts the float onto the water. After two to
six seconds a fish bites: the float dips and jerks for `BITE` seconds.
A press while it bites hooks the fish. A press before it reels the line
in, and a bite missed lets the fish get away. Walking out of reach reels
the line in.

A spot is ready, or it waits. A ready spot within `GatherParameters.reach`
of the player's feet, and less than `HEADROOM` above or below them, can
be used. Over each ready spot a shimmer of gold motes turns, so a player
sees it from afar. The nearest spot that can be used is the focus: a
gold marker turns and bobs over it. A new press of the use button uses
the focus: what it gives goes into the `Satchel`, and the part that is
gathered hides, with its shimmer.

A boulder, a chest and a berry bush are solid: `obstacles` gives each as
round. Herbs, mushrooms and trinkets are not.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.ordinal import ordinal_valid
from core.scene import Scene
from extensions.vegetation.checks import require_between
from extensions.vegetation.ground import Ground, Lot, lot_openness
from extensions.vegetation.noise import hash01
from extensions.vegetation.rock import boulder
from extensions.village.character import Obstacle
from extensions.village.dressing import WROUGHT, prism
from extensions.village.sheet import Sheet
from extensions.village.surfaces import (
    ASHLAR_TILE,
    HouseLooks,
    PLASTER_TILE,
    WOOD_TILE,
)
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from materials.material import MaterialId, standard_material
from render.framebuffer import Color
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, pi, sin
from units.si import METER, RADIAN, SECOND, Angle, Duration, Length

comptime STRIKES = 3
"""How many uses a boulder takes before it gives its ore."""
comptime CHEST_COINS = 12
"""How many coins a chest holds."""
comptime HEADROOM = Float32(1.5)
"""How far above or below the player's feet a spot can be used, in
meters."""
comptime LID_SPEED = Float32(2.0)
"""How fast a chest's lid swings open, in radians a second."""
comptime LID_OPEN = Float32(1.9)
"""How far a chest's lid swings open, in radians."""
comptime BOULDER = Float32(0.55)
"""The radius of a boulder of ore, in meters."""
comptime CAST = Float32(3.2)
"""How far out along a fishing spot's turn its float lies, in meters."""
comptime BITE = Float32(1.2)
"""How long a fish bites before it gets away, in seconds."""
comptime IDLE = 0
"""A fishing spot's line is in."""
comptime WAITING = 1
"""A fishing spot's float is out, and no fish bites yet."""
comptime BITING = 2
"""A fish bites at a fishing spot's float."""
comptime TRINKET_LIFT = Float32(0.9)
"""How high a trinket hangs over the ground, in meters."""
comptime GOLD = Vector3(1.0, 0.72, 0.2)
"""The color of gold, drawn unlit, so it glints."""
comptime LEAF = Vector3(0.22, 0.42, 0.12)
"""The tint of leaves over the plaster texture."""


@fieldwise_init
struct GatherKind(Equatable, ImplicitlyCopyable, Writable):
    """What a spot is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return ordinal_valid(self.value, 6)


comptime HERBS = GatherKind(0)
comptime MUSHROOMS = GatherKind(1)
comptime BERRIES = GatherKind(2)
comptime ORE = GatherKind(3)
comptime CHEST = GatherKind(4)
comptime TRINKET = GatherKind(5)
comptime FISH = GatherKind(6)
comptime KINDS = 7
"""How many kinds of spot there are."""


def kind_name(kind: GatherKind) raises -> String:
    """Return what a satchel calls the things a kind of spot gives.

    Args:
        kind: The kind.

    Returns:
        "herbs", "mushrooms", "berries", "ore", "coins", "trinkets" or
        "fish".

    Raises:
        Error: If the kind is not one.
    """
    if not kind.is_valid():
        raise Error("A gathering kind must be one of the seven")
    var names: List[String] = [
        "herbs",
        "mushrooms",
        "berries",
        "ore",
        "coins",
        "trinkets",
        "fish",
    ]
    return names[kind.value]


def respawns(kind: GatherKind) -> Bool:
    """Return whether a kind of spot comes back after it is used.

    Args:
        kind: The kind.

    Returns:
        False for a chest and a trinket, which are used once; True for
        the rest.
    """
    return kind != CHEST and kind != TRINKET


def solid_radius(kind: GatherKind) -> Float32:
    """Return how far round its middle a kind of spot stops a character.

    Args:
        kind: The kind.

    Returns:
        A boulder's 0.6 meters, a chest's 0.45 and a berry bush's 0.4, or
        zero for a spot a character walks through.
    """
    if kind == ORE:
        return 0.6
    if kind == CHEST:
        return 0.45
    if kind == BERRIES:
        return 0.4
    return 0


@fieldwise_init
struct Spot(ImplicitlyCopyable):
    """A place where something can be gathered."""

    var kind: GatherKind
    # Its middle on the ground, in meters.
    var x: Float32
    var z: Float32
    # How far it is turned about +y.
    var turn: Angle

    def check(self) raises:
        """Refuse a spot that cannot be drawn.

        Raises:
            Error: If the kind is not one, or the spot stands further than
                10 kilometers away.
        """
        if not self.kind.is_valid():
            raise Error("A gathering kind must be one of the seven")
        require_between(
            self.x, -1.0e4, 1.0e4, "A spot must stand within 10 kilometers"
        )
        require_between(
            self.z, -1.0e4, 1.0e4, "A spot must stand within 10 kilometers"
        )


def default_spots() -> List[Spot]:
    """Return the spots of the default village.

    Returns:
        Four tufts of herbs, three clusters of mushrooms, three berry
        bushes, two boulders, a chest behind the barn and three lost
        trinkets, scattered over the meadow clear of the houses, the
        trail and the pond, and a fishing spot on the pond's west shore.
    """
    return [
        Spot(HERBS, -5, 18, Angle(0.3, RADIAN)),
        Spot(HERBS, 6, 4, Angle(1.1, RADIAN)),
        Spot(HERBS, -15, -12, Angle(2.0, RADIAN)),
        Spot(HERBS, 15, -38, Angle(0.7, RADIAN)),
        Spot(MUSHROOMS, -8, 30, Angle(0.0, RADIAN)),
        Spot(MUSHROOMS, 25, -10, Angle(1.4, RADIAN)),
        Spot(MUSHROOMS, -31, -20, Angle(2.6, RADIAN)),
        Spot(BERRIES, -16, 24, Angle(0.5, RADIAN)),
        Spot(BERRIES, 12, -9, Angle(1.9, RADIAN)),
        Spot(BERRIES, -21, 1, Angle(3.0, RADIAN)),
        Spot(ORE, 29, 8, Angle(0.4, RADIAN)),
        Spot(ORE, -30, -52, Angle(1.2, RADIAN)),
        Spot(CHEST, -9, -67, Angle(-0.2, RADIAN)),
        Spot(TRINKET, 2, 14, Angle(0.0, RADIAN)),
        Spot(TRINKET, -12, -28, Angle(0.0, RADIAN)),
        Spot(TRINKET, 18, -47, Angle(0.0, RADIAN)),
        Spot(FISH, 1.5, 19.5, Angle(0.0, RADIAN)),
    ]


struct GatherParameters(Copyable, Movable):
    """Where things can be gathered, and how."""

    var spots: List[Spot]
    # How near the player's feet must come to a spot's middle to use it.
    var reach: Length
    # How long a spot that comes back waits after it is used.
    var respawn: Duration

    def __init__(out self):
        """Hold the default village's spots, a reach of 1.8 meters and a
        respawn time of 60 seconds."""
        self.spots = default_spots()
        self.reach = Length(1.8, METER)
        self.respawn = Duration(60.0, SECOND)


struct Satchel(Copyable, Movable):
    """What a player has gathered: a count for each kind of spot."""

    var counts: List[Int]
    # How many things the last use that gave something gave.
    var last: Int

    def __init__(out self):
        """Hold nothing."""
        self.counts = List[Int](length=KINDS, fill=0)
        self.last = 0

    def count(self, kind: GatherKind) raises -> Int:
        """Return how many things of a kind the satchel holds.

        Args:
            kind: The kind of spot they came from.

        Returns:
            The count.

        Raises:
            Error: If the kind is not one.
        """
        if not kind.is_valid():
            raise Error("A gathering kind must be one of the seven")
        return self.counts[kind.value]

    def total(self) -> Int:
        """Return how many things the satchel holds, of every kind.

        Returns:
            The sum of the counts.
        """
        var sum = 0
        for c in self.counts:  # pragma: no branch
            sum += c
        return sum


@fieldwise_init
struct Gatherable(Copyable, Movable):
    """A spot in a scene: the node of the part that is gathered, and its
    state."""

    var spot: Spot
    # The node of the part that hides when gathered: the herbs, the
    # mushrooms, the berries, the veins, the chest's coins or the
    # trinket. A chest's lid, or a fishing spot's float, hangs from
    # `hinge`.
    var node: NodeId
    var hinge: NodeId
    # The shimmer of gold motes that turns over the spot while it is ready.
    var glint: NodeId
    # The ground's height at the spot's middle, and the top of what stands
    # there, over the ground, in meters.
    var foot: Float32
    var top: Float32
    # Whether it can be used, and how long it still waits if not, in
    # seconds.
    var ready: Bool
    var wait: Float32
    # A boulder's strikes so far, and how far a chest's lid stands open,
    # in radians.
    var strikes: Int
    var lid: Float32
    # A fishing spot's phase, `IDLE`, `WAITING` or `BITING`, how long until
    # it changes, in seconds, and how many casts it has made. Its float
    # hangs from `hinge`.
    var phase: Int
    var timer: Float32
    var casts: Int


struct _Parts(Movable):
    """The sheets of one part of a spot, one per material."""

    var plaster: Sheet
    var wood: Sheet
    var ashlar: Sheet
    var glass: Sheet
    var glow: Sheet

    def __init__(out self):
        self.plaster = Sheet(PLASTER_TILE)
        self.wood = Sheet(WOOD_TILE)
        self.ashlar = Sheet(ASHLAR_TILE)
        self.glass = Sheet(1)
        self.glow = Sheet(1)


def _leaf(
    mut sheet: Sheet,
    foot: Vector3,
    toward: Vector3,
    height: Float32,
    width: Float32,
    color: Vector3,
):
    """Add a leaf of two faces that leans out from its foot toward a
    direction on the ground, its tip `height` up."""
    var tip = foot + toward * (height * 0.45) + Vector3(0, height, 0)
    var across = Vector3(-toward.z, 0, toward.x) * (width / 2)
    var middle = foot + (tip - foot) * 0.45 + toward * (height * 0.08)
    sheet.painted_quad(
        foot,
        middle + across,
        tip,
        middle - across,
        color,
        color,
        color,
        color,
        0,
        0,
        1,
        1,
    )
    sheet.painted_quad(
        foot,
        middle - across,
        tip,
        middle + across,
        color,
        color,
        color,
        color,
        0,
        0,
        1,
        1,
    )


def _herbs(mut parts: _Parts, seed: Int) -> Float32:
    """Add a tuft of herbs round the origin; return its height."""
    for k in range(12):
        var a = 2 * pi * (Float32(k) + hash01(k, seed, 1)) / 12
        var toward = Vector3(cos(a), 0, sin(a))
        var tall = 0.4 + 0.2 * hash01(k, seed, 2)
        _leaf(
            parts.plaster,
            toward * 0.04,
            toward,
            tall,
            0.1,
            LEAF * (0.85 + 0.3 * hash01(seed, k, 3)),
        )
        if k % 2 == 0:
            # A pale violet flower at the tip of every second stem, drawn
            # unlit, so it shows over the grass.
            prism(
                parts.glow,
                toward * (0.04 + tall * 0.45) + Vector3(0, tall - 0.02, 0),
                0.035,
                0.045,
                0.035,
                5,
                Vector3(0.78, 0.62, 1.0),
            )
    return 0.62


def _mushrooms(mut parts: _Parts, seed: Int) -> Float32:
    """Add a cluster of mushrooms round the origin; return its height."""
    for k in range(5):
        var a = 2 * pi * Float32(k) / 5 + hash01(k, seed, 4)
        var away = 0.06 + 0.1 * Float32(k % 3)
        var at = Vector3(cos(a) * away, 0, sin(a) * away)
        var tall = 0.1 + 0.1 * hash01(k, seed, 5)
        var cap = 0.07 + 0.05 * hash01(seed, k, 6)
        prism(
            parts.plaster, at, 0.022, 0.018, tall, 6, Vector3(0.9, 0.86, 0.76)
        )
        prism(
            parts.plaster,
            at + Vector3(0, tall - 0.015, 0),
            cap,
            cap * 0.25,
            cap * 0.8,
            8,
            Vector3(0.7, 0.07, 0.03),
        )
        # Pale flecks on the cap.
        for f in range(3):
            var b = 2 * pi * Float32(f) / 3 + a
            prism(
                parts.plaster,
                at
                + Vector3(
                    cos(b) * cap * 0.45, tall + cap * 0.3, sin(b) * cap * 0.45
                ),
                0.012,
                0.006,
                0.012,
                4,
                Vector3(0.95, 0.92, 0.85),
            )
    return 0.3


def _bush(mut body: _Parts, mut fruit: _Parts, seed: Int) -> Float32:
    """Add a berry bush round the origin, its berries apart; return its
    height."""
    # Three tiers of leafy sprays, each tier narrower and higher.
    for tier in range(3):
        var count = 10 - 2 * tier
        var rise = 0.16 * Float32(tier)
        for k in range(count):  # pragma: no branch
            var a = 2 * pi * (Float32(k) + 0.5 * Float32(tier)) / Float32(count)
            var toward = Vector3(cos(a), 0, sin(a))
            _leaf(
                body.plaster,
                toward * (0.06 * Float32(2 - tier)) + Vector3(0, rise, 0),
                toward,
                0.38 - 0.06 * Float32(tier),
                0.3,
                LEAF * (0.55 + 0.12 * Float32(tier) + 0.1 * hash01(k, seed, 7)),
            )
    for k in range(16):
        var a = 2 * pi * hash01(k, seed, 7)
        var up = 0.15 + 0.4 * hash01(seed, k, 8)
        var spread = 0.36 - 0.3 * (up / 0.6)
        fruit.glass.box(
            Vector3(cos(a) * spread, up, sin(a) * spread),
            Vector3(0.022, 0, 0),
            Vector3(0, 0.022, 0),
            Vector3(0, 0, 0.022),
            Vector3(0.42, 0.03, 0.14),
        )
    return 0.65


def _veins(mut veins: _Parts, rock: BufferGeometry, seed: Int) raises:
    """Set six copper nuggets, and a glint by every second one, on a
    boulder's faces that look out and up."""
    ref points = rock.attribute_view(String(POSITION))
    ref normals = rock.attribute_view(String(NORMAL))
    # The corners of the faces that look out, neither down nor up.
    var sides = List[Int]()
    for v in range(points.count()):  # pragma: no branch
        var n = normals.vector3(v)
        if n.y < 0 or n.y > 0.8:
            continue
        sides.append(v)
    for k in range(6):
        var v = sides[
            Int(hash01(k, seed, 9) * Float32(len(sides))) % len(sides)
        ]
        var n = normals.vector3(v)
        var p = points.vector3(v)
        var along = Vector3(-n.z, 0.3, n.x)
        veins.glass.box(
            p + n * 0.02,
            along * 0.07,
            Vector3(0, 0.035, 0),
            n * 0.03,
            Vector3(0.78, 0.4, 0.16),
        )
        if k % 2 == 0:
            veins.glow.box(
                p + n * 0.05 + Vector3(0, 0.03, 0),
                Vector3(0.015, 0, 0),
                Vector3(0, 0.015, 0),
                Vector3(0, 0, 0.015),
                GOLD,
            )


def _chest(mut body: _Parts, mut lid: _Parts, mut coins: _Parts) -> Float32:
    """Add a chest on the origin: its body, its lid from its hinge at the
    back of its top, and the coins in it; return its height."""
    var wood = Vector3(0.62, 0.52, 0.45)
    var hw = Float32(0.4)
    var hd = Float32(0.26)
    var high = Float32(0.38)
    body.wood.box(
        Vector3(0, high / 2, 0),
        Vector3(hw, 0, 0),
        Vector3(0, high / 2, 0),
        Vector3(0, 0, hd),
        wood,
    )
    for sx in [Float32(-0.6), Float32(0.6)]:
        body.wood.box(
            Vector3(hw * sx, high / 2, 0),
            Vector3(0.025, 0, 0),
            Vector3(0, high / 2 + 0.005, 0),
            Vector3(0, 0, hd + 0.01),
            WROUGHT,
        )
    # The lock plate on the front.
    body.wood.box(
        Vector3(0, high - 0.06, hd + 0.01),
        Vector3(0.05, 0, 0),
        Vector3(0, 0.06, 0),
        Vector3(0, 0, 0.01),
        WROUGHT * 4,
    )
    # The lid, from the hinge: it reaches toward +z over the body.
    lid.wood.box(
        Vector3(0, 0.05, hd),
        Vector3(hw + 0.01, 0, 0),
        Vector3(0, 0.05, 0),
        Vector3(0, 0, hd + 0.01),
        wood * 1.05,
    )
    for sx in [Float32(-0.6), Float32(0.6)]:
        lid.wood.box(
            Vector3(hw * sx, 0.05, hd),
            Vector3(0.025, 0, 0),
            Vector3(0, 0.055, 0),
            Vector3(0, 0, hd + 0.02),
            WROUGHT,
        )
    # A heap of coins under the lid.
    coins.glow.box(
        Vector3(0, high - 0.03, 0),
        Vector3(hw - 0.04, 0, 0),
        Vector3(0, 0.03, 0),
        Vector3(0, 0, hd - 0.04),
        GOLD * 0.8,
    )
    return high + 0.1


def _trinket(mut parts: _Parts, seed: Int) -> Float32:
    """Add a trinket about the origin: a gold ring hung with a gem; return
    its height."""
    var gem = Vector3(0.2, 0.5, 1.0)
    if seed % 2 == 1:
        gem = Vector3(1.0, 0.15, 0.25)
    for k in range(10):
        var a = 2 * pi * Float32(k) / 10
        var b = 2 * pi * Float32(k + 1) / 10
        var p = Vector3(cos(a) * 0.14, sin(a) * 0.14, 0)
        var q = Vector3(cos(b) * 0.14, sin(b) * 0.14, 0)
        var middle = (p + q) / 2
        var along = (q - p) / 2
        parts.glow.box(
            middle,
            along,
            Vector3(-along.y, along.x, 0) * (0.02 / along.length()),
            Vector3(0, 0, 0.02),
            GOLD,
        )
    parts.glow.box(
        Vector3(0, -0.14, 0),
        Vector3(0.05, 0, 0),
        Vector3(0, 0.06, 0),
        Vector3(0, 0, 0.03),
        gem,
    )
    return 0.3


def _stake(mut parts: _Parts) -> Float32:
    """Add a fishing spot: an oak stake with a coil of rope, and a creel of
    woven willow beside it; return the stake's height."""
    prism(
        parts.wood,
        Vector3(0, -0.1, 0),
        0.06,
        0.05,
        1.0,
        6,
        Vector3(0.8, 0.7, 0.6),
    )
    prism(
        parts.wood,
        Vector3(0, 0.55, 0),
        0.1,
        0.1,
        0.08,
        8,
        Vector3(0.95, 0.85, 0.6),
    )
    prism(
        parts.wood,
        Vector3(0.1, 0, 0.35),
        0.16,
        0.19,
        0.28,
        8,
        Vector3(1.1, 0.9, 0.6),
    )
    return 0.9


def _float(mut parts: _Parts):
    """Add a fishing float about the origin: red over the water and white
    under it, with a quill on top."""
    prism(
        parts.glass,
        Vector3(0, -0.03, 0),
        0.03,
        0.045,
        0.03,
        8,
        Vector3(0.9, 0.9, 0.85),
    )
    prism(
        parts.glass,
        Vector3(0, 0, 0),
        0.045,
        0.02,
        0.05,
        8,
        Vector3(0.75, 0.06, 0.04),
    )
    prism(
        parts.wood,
        Vector3(0, 0.05, 0),
        0.006,
        0.004,
        0.08,
        4,
        Vector3(0.3, 0.3, 0.3),
    )


def _glint() -> Sheet:
    """Return the shimmer over a ready spot: four gold motes on a ring 35
    centimeters across, at three heights."""
    var sheet = Sheet(1)
    for k in range(4):
        var a = pi / 2 * Float32(k)
        var at = Vector3(cos(a) * 0.35, 0.12 * Float32(k % 3), -sin(a) * 0.35)
        sheet.box(
            at,
            Vector3(0.018, 0, 0),
            Vector3(0, 0.018, 0),
            Vector3(0, 0, 0.018),
            GOLD * (0.7 + 0.1 * Float32(k)),
        )
    return sheet^


def _marker() -> Sheet:
    """Return the gold marker that hangs over the focus: a diamond of
    eight faces, 24 centimeters tall."""
    var sheet = Sheet(1)
    var top = Vector3(0, 0.12, 0)
    var bottom = Vector3(0, -0.12, 0)
    for k in range(4):
        var a = pi / 2 * Float32(k)
        var b = pi / 2 * Float32(k + 1)
        var p = Vector3(cos(a) * 0.07, 0, -sin(a) * 0.07)
        var q = Vector3(cos(b) * 0.07, 0, -sin(b) * 0.07)
        var shade = GOLD * (0.8 + 0.2 * Float32(k % 2))
        var i0 = sheet.vertex(top, Vector3(0, 1, 0), shade, 0, 0)
        var i1 = sheet.vertex(p, Vector3(0, 1, 0), shade, 0, 0)
        var i2 = sheet.vertex(q, Vector3(0, 1, 0), shade, 0, 0)
        sheet.triangle(i0, i1, i2)
        var j0 = sheet.vertex(bottom, Vector3(0, -1, 0), shade * 0.7, 0, 0)
        var j1 = sheet.vertex(q, Vector3(0, -1, 0), shade * 0.7, 0, 0)
        var j2 = sheet.vertex(p, Vector3(0, -1, 0), shade * 0.7, 0, 0)
        sheet.triangle(j0, j1, j2)
    return sheet^


def _add(
    mut scene: Scene,
    mut assets: Assets,
    sheet: Sheet,
    material: MaterialId,
    parent: NodeId,
    casts: Bool,
) raises -> Int:
    """Add a sheet as a mesh under a node, if it has a triangle; return
    its triangles."""
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


def _add_parts(
    mut scene: Scene,
    mut assets: Assets,
    parts: _Parts,
    looks: HouseLooks,
    parent: NodeId,
    casts: Bool,
) raises -> Int:
    """Add each sheet of a part as a mesh of its material under a node;
    return their triangles."""
    var triangles = 0
    triangles += _add(
        scene, assets, parts.plaster, looks.plaster, parent, casts
    )
    triangles += _add(scene, assets, parts.wood, looks.wood, parent, casts)
    triangles += _add(scene, assets, parts.ashlar, looks.ashlar, parent, casts)
    triangles += _add(scene, assets, parts.glass, looks.glass, parent, casts)
    triangles += _add(scene, assets, parts.glow, looks.daylight, parent, False)
    return triangles


def _node(
    mut scene: Scene, parent: NodeId, x: Float32, y: Float32, z: Float32
) raises -> NodeId:
    """Add a node under a parent at a place, and return it."""
    var node = Object3D()
    node.set_position(x, y, z)
    node.parent = parent
    return scene.add(node^)


def _fish(
    mut scene: Scene,
    mut g: Gatherable,
    near: Bool,
    seconds: Float32,
    clock: Float32,
    water: Float32,
) raises:
    """Move a fishing spot's line on by one frame: a fish bites when the
    wait is over, and gets away when the bite is; a player out of reach
    reels the line in. The float bobs on the water at `water`, and dips
    and jerks while a fish bites."""
    g.timer -= seconds
    if not near or (g.phase == BITING and g.timer <= 0):
        g.phase = IDLE
    elif g.phase == WAITING and g.timer <= 0:
        g.phase = BITING
        g.timer = BITE
    ref bobber = scene.node(g.hinge)
    bobber.visible = g.phase != IDLE
    var bob = 0.012 * sin(clock * 3)
    if g.phase == BITING:
        bob = -0.05 + 0.03 * sin(clock * 31)
    bobber.position.y = water - g.foot + bob


struct Gathering(Movable):
    """Every spot of the village, what the player has gathered, and the
    marker over the spot the player can use."""

    var spots: List[Gatherable]
    var satchel: Satchel
    var reach: Float32
    var respawn: Float32
    # The marker's node, and the spot it hangs over: the focus, or -1.
    var marker: NodeId
    var focus: Int
    # Whether the use button was held last frame, so only a new press
    # uses a spot.
    var held: Bool
    # The game's clock, in seconds, for the trinkets' and the marker's
    # motion.
    var clock: Float32
    var root: NodeId
    var meshes: Int
    var triangles: Int
    # The height of the pond's water, where a fishing float lies.
    var water: Float32
    # How the player's skills change their gathering: how many strikes a
    # boulder takes, how many more things a pick of herbs, mushrooms or
    # berries gives, and the share of a fish's usual wait that it waits.
    # See `extensions.village.skills`.
    var ore_strikes: Int
    var forage_bonus: Int
    var fish_haste: Float32

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        looks: HouseLooks,
        parameters: GatherParameters,
        ground: Ground,
        lots: List[Lot],
    ) raises:
        """Draw every spot that stands clear of the lots and the water.

        A spot on a lot or its apron, or in the water, is left out, as a
        tree there is. The spots that stay keep their order.

        Args:
            scene: The scene. A node for the spots, and for each spot a
                node for what is gathered, are added, with their meshes.
            assets: The stores for the geometries.
            looks: The houses' materials, which the spots wear too.
            parameters: The spots, the reach and the respawn time.
            ground: The ground the spots stand on.
            lots: The ground kept clear of spots.

        Raises:
            Error: If a spot does not check, or the reach or the respawn
                time is negative.
        """
        var reach = parameters.reach.to(METER)
        var respawn = parameters.respawn.to(SECOND)
        if not (reach >= 0) or not (respawn >= 0):
            raise Error("A gathering's reach and respawn must not be negative")
        self.reach = reach
        self.respawn = respawn
        self.satchel = Satchel()
        self.spots = List[Gatherable]()
        self.focus = -1
        self.held = False
        self.clock = 0
        self.meshes = 0
        self.triangles = 0
        self.root = scene.add(Object3D())
        var before = len(scene.meshes)
        var water = ground.water_level()
        self.water = water
        self.ore_strikes = STRIKES
        self.forage_bonus = 0
        self.fish_haste = 1
        # A boulder's stone shows its vertex colors: gray, mossy on top.
        var rough = standard_material(Color(255, 255, 255), roughness=0.9)
        rough.vertex_colors = True
        var stone = assets.materials.add(rough)
        for index in range(len(parameters.spots)):
            ref spot = parameters.spots[index]
            spot.check()
            if lot_openness(lots, spot.x, spot.z) < 1:
                continue
            if ground.wet(spot.x, spot.z):
                continue
            var foot = ground.height_at(spot.x, spot.z)
            var place = Object3D()
            place.set_position(spot.x, foot, spot.z)
            place.rotate_y(spot.turn)
            place.parent = self.root
            var at = scene.add(place^)
            var part = _Parts()
            var lid = _Parts()
            var hinge = at
            var top: Float32
            var lift = Float32(0)
            if spot.kind == HERBS:
                top = _herbs(part, index)
            elif spot.kind == MUSHROOMS:
                top = _mushrooms(part, index)
            elif spot.kind == BERRIES:
                # The bush stays: it is drawn with the bodies, in the
                # spot's turn, round its middle.
                var bush = _Parts()
                top = _bush(bush, part, index)
                self.triangles += _add_parts(
                    scene, assets, bush, looks, at, True
                )
            elif spot.kind == ORE:
                var rock = boulder(Length(BOULDER, METER), 2, index)
                _veins(part, rock, index)
                self.triangles += rock.triangle_count()
                scene.add_mesh(
                    Mesh(
                        assets.geometries.add(rock^),
                        stone,
                        at,
                        cast_shadow=True,
                        receive_shadow=True,
                    )
                )
                top = BOULDER * 1.1
            elif spot.kind == CHEST:
                var box = _Parts()
                top = _chest(box, lid, part)
                self.triangles += _add_parts(
                    scene, assets, box, looks, at, True
                )
                hinge = _node(scene, at, 0, 0.38, -0.26)
                self.triangles += _add_parts(
                    scene, assets, lid, looks, hinge, True
                )
            elif spot.kind == FISH:
                var stake = _Parts()
                top = _stake(stake)
                self.triangles += _add_parts(
                    scene, assets, stake, looks, at, True
                )
                # The float lies on the water, out along the spot's turn.
                var bobber = _Parts()
                _float(bobber)
                hinge = _node(scene, at, CAST, water - foot, 0)
                scene.node(hinge).visible = False
                self.triangles += _add_parts(
                    scene, assets, bobber, looks, hinge, False
                )
            else:
                top = _trinket(part, index)
                lift = TRINKET_LIFT
            var node = _node(scene, at, 0, lift, 0)
            self.triangles += _add_parts(
                scene, assets, part, looks, node, False
            )
            var glint = _node(scene, at, 0, top + lift + 0.1, 0)
            self.triangles += _add(
                scene, assets, _glint(), looks.daylight, glint, False
            )
            self.spots.append(
                Gatherable(
                    spot,
                    node,
                    hinge,
                    glint,
                    foot,
                    top + lift,
                    True,
                    0,
                    0,
                    0,
                    IDLE,
                    0,
                    0,
                )
            )
        var marker = Object3D()
        marker.visible = False
        marker.parent = self.root
        self.marker = scene.add(marker^)
        self.triangles += _add(
            scene, assets, _marker(), looks.daylight, self.marker, False
        )
        self.meshes = len(scene.meshes) - before

    def obstacles(self) -> List[Obstacle]:
        """Return each solid spot as round: a boulder, a chest and a berry
        bush.

        Returns:
            One obstacle for each solid spot.
        """
        var out = List[Obstacle]()
        for g in self.spots:
            var radius = solid_radius(g.spot.kind)
            if radius > 0:
                out.append(Obstacle(g.spot.x, g.spot.z, radius))
        return out^

    def nearest(self, feet: Vector3) -> Int:
        """Return the ready spot nearest a player's feet, within reach.

        Args:
            feet: Where the player's feet are.

        Returns:
            The spot's place in `spots`, or -1 if no ready spot is within
            the reach, and within `HEADROOM` above or below the feet.
        """
        var best = -1
        var nearest = self.reach * self.reach
        for index in range(len(self.spots)):
            ref g = self.spots[index]
            if not g.ready or abs(g.foot - feet.y) > HEADROOM:
                continue
            var dx = g.spot.x - feet.x
            var dz = g.spot.z - feet.z
            var d = dx * dx + dz * dz
            if d <= nearest:
                nearest = d
                best = index
        return best

    def update(
        mut self,
        mut scene: Scene,
        feet: Vector3,
        use: Bool,
        delta: Duration,
    ) raises -> Optional[GatherKind]:
        """Run one frame: bring back spots whose wait is over, use the
        focus on a new press, and move the trinkets, the lids and the
        marker.

        Args:
            scene: The scene the spots are in.
            feet: Where the player's feet are.
            use: Whether the use button is held.
            delta: The frame's time.

        Returns:
            The kind of spot gathered this frame, if one gave something:
            a boulder gives nothing until its last strike.

        Raises:
            Error: If the time is negative.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        self.clock += seconds
        for ref g in self.spots:
            if g.ready or not respawns(g.spot.kind):
                continue
            g.wait -= seconds
            if g.wait <= 0:
                g.ready = True
                g.wait = 0
                scene.node(g.node).visible = True
                scene.node(g.glint).visible = True
        var pressed = use and not self.held
        self.held = use
        self.focus = self.nearest(feet)
        var gathered = Optional[GatherKind](None)
        if pressed and self.focus >= 0:
            ref g = self.spots[self.focus]
            var kind = g.spot.kind
            var gives = 1
            if kind == FISH:
                # Cast, reel in early, or hook the fish that bites.
                gives = 1 if g.phase == BITING else 0
                if g.phase == IDLE:
                    g.casts += 1
                    g.phase = WAITING
                    g.timer = (2 + 4 * hash01(g.casts, 0, 79)) * self.fish_haste
                else:
                    g.phase = IDLE
                scene.node(g.hinge).visible = g.phase != IDLE
            elif kind == MUSHROOMS:
                gives = 2 + self.forage_bonus
            elif kind == BERRIES:
                gives = 3 + self.forage_bonus
            elif kind == CHEST:
                gives = CHEST_COINS
            elif kind == ORE:
                g.strikes += 1
                if g.strikes < self.ore_strikes:
                    gives = 0
            elif kind == HERBS:
                gives = 1 + self.forage_bonus
            if gives > 0 and kind == FISH:
                self.satchel.counts[kind.value] += gives
                self.satchel.last = gives
                gathered = kind
            elif gives > 0:
                self.satchel.counts[kind.value] += gives
                self.satchel.last = gives
                g.ready = False
                g.strikes = 0
                g.wait = self.respawn
                # A chest's coins hide as its lid opens.
                scene.node(g.node).visible = False
                scene.node(g.glint).visible = False
                gathered = kind
                self.focus = self.nearest(feet)
        var spin = self.clock * 1.5
        for index in range(len(self.spots)):
            ref g = self.spots[index]
            if g.spot.kind == FISH and g.phase != IDLE:
                _fish(
                    scene,
                    g,
                    index == self.focus,
                    seconds,
                    self.clock,
                    self.water,
                )
        for ref g in self.spots:
            if g.ready:
                ref glint = scene.node(g.glint)
                glint.set_rotation_from_axis_angle(
                    Vector3(0, 1, 0), Angle(spin * 0.8, RADIAN)
                )
                glint.position.y = g.top + 0.1 + 0.05 * sin(self.clock * 1.7)
            if g.spot.kind == TRINKET:
                ref node = scene.node(g.node)
                node.position.y = TRINKET_LIFT + 0.08 * sin(self.clock * 2.2)
                node.set_rotation_from_axis_angle(
                    Vector3(0, 1, 0), Angle(spin, RADIAN)
                )
            elif g.spot.kind == CHEST and not g.ready and g.lid < LID_OPEN:
                g.lid = min(LID_OPEN, g.lid + LID_SPEED * seconds)
                scene.node(g.hinge).set_rotation_from_axis_angle(
                    Vector3(1, 0, 0), Angle(-g.lid, RADIAN)
                )
        ref marker = scene.node(self.marker)
        marker.visible = self.focus >= 0
        if self.focus >= 0:
            ref g = self.spots[self.focus]
            marker.position = Vector3(
                g.spot.x,
                g.foot + g.top + 0.45 + 0.05 * sin(self.clock * 3),
                g.spot.z,
            )
            marker.set_rotation_from_axis_angle(
                Vector3(0, 1, 0), Angle(spin * 1.6, RADIAN)
            )
        return gathered
