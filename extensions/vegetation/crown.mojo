# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A broadleaf tree: the generator's branches, and a crown of leaf cards.

`TreeGenerator` grows the trunk and the branches as tubes. `leafy_tree`
puts leaves on every ring that is thinner than `twig_radius`, the twigs at
the ends of the branches. Each leaf is a card of two triangles, a diamond
a little longer than wide, turned a random way.

**Why the leaves face out.** A crown of thousands of cards lit by their
own normals is a noise of light and dark. Each leaf's normal is mostly the
direction from the crown's center out to the leaf, and a little its own.
The crown is then lit as one soft volume, bright on the sun side and dark
on the far side, as a real crown looks from a distance.

**The occlusion.** A leaf deep in the crown, or low in it, gets less sky.
Its color is darkened by how near the center and how low it is. This
stands in for the light the crown blocks, which the renderer does not
trace.

**The level of detail.** A far tree does not need every leaf. `detail`
keeps a fraction of the leaves and makes each one larger by the inverse
square root of the fraction, so the crown keeps its cover. A far tree is
still geometry and not an impostor.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.noise import hash01
from generators.tree import TreeGenerator, TreeParameters
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from units.si import METER, Length

# The linear color of a sunlit leaf, and of a leaf that is more yellow.
comptime LEAF = Vector3(0.060, 0.160, 0.022)
comptime LEAF_LIGHT = Vector3(0.140, 0.240, 0.035)
# The linear color of bark.
comptime BARK = Vector3(0.090, 0.075, 0.060)
# How much of a leaf's normal is its own, and not the crown's.
comptime OWN_NORMAL = Float32(0.3)
# How dark the deepest leaf of a crown is.
comptime DEEPEST = Float32(0.35)


struct CrownParameters(Copyable, Movable):
    """The branches of a tree and the leaves on its twigs."""

    # The branches.
    var tree: TreeParameters
    # Rings thinner than this carry leaves.
    var twig_radius: Length
    # How many leaves each twig ring carries, at full detail.
    var leaves_per_ring: Int
    # How far a leaf sits from its twig.
    var spread: Length
    # The length and width of one leaf card.
    var leaf_length: Length
    var leaf_width: Length
    # Which leaves to grow.
    var seed: Int

    def __init__(out self):
        """Create the parameters of a broadleaf tree about 14 meters tall."""
        self.tree = TreeParameters()
        self.twig_radius = Length(0.07, METER)
        self.leaves_per_ring = 22
        self.spread = Length(1.1, METER)
        self.leaf_length = Length(0.4, METER)
        self.leaf_width = Length(0.26, METER)
        self.seed = 1

    def check(self) raises:
        """Refuse parameters that cannot grow a crown.

        Raises:
            Error: If the tree is refused, the twig radius is not from 1
                millimeter to 1 meter, a ring has not from 1 to 256
                leaves, the spread is not from 0 to 10 meters, or a leaf
                is not from 1 centimeter to 2 meters long and wide.
        """
        self.tree.check()
        require_between(
            self.twig_radius.to(METER),
            0.001,
            1,
            "A twig must be from 1 millimeter to 1 meter thick",
        )
        require_count_between(
            self.leaves_per_ring,
            1,
            256,
            "A twig ring must carry from 1 to 256 leaves",
        )
        require_between(
            self.spread.to(METER),
            0,
            10,
            "Leaves must spread from 0 to 10 meters",
        )
        require_between(
            self.leaf_length.to(METER),
            0.01,
            2,
            "A leaf must be from 1 centimeter to 2 meters long",
        )
        require_between(
            self.leaf_width.to(METER),
            0.01,
            2,
            "A leaf must be from 1 centimeter to 2 meters wide",
        )


def bush_parameters() -> CrownParameters:
    """Return the parameters of a bush about 3 meters tall.

    A bush is a tree with a short trunk that forks at once, three levels
    of branches, and small leaves close to its twigs. Bushes fill the
    gaps under a treeline, so it reads as a wall of leaves.

    Returns:
        The parameters.
    """
    var bush = CrownParameters()
    bush.tree.levels = 3
    bush.tree.children = [5, 7]
    bush.tree.trunk_length = Length(1.8, METER)
    bush.tree.trunk_radius = Length(0.09, METER)
    bush.tree.section_length = Length(0.35, METER)
    bush.tree.min_length = Length(0.3, METER)
    bush.tree.min_radius = Length(0.01, METER)
    bush.tree.trunk_clear = 0.05
    bush.tree.child_start = 0.05
    bush.tree.radial_segments = 4
    bush.twig_radius = Length(0.035, METER)
    bush.leaves_per_ring = 9
    bush.spread = Length(0.55, METER)
    bush.leaf_length = Length(0.24, METER)
    bush.leaf_width = Length(0.16, METER)
    return bush^


struct LeafyTree(Movable):
    """A tree's wood and its leaves, as two geometries."""

    # The trunk and the branches, with `position`, `normal` and `color`.
    var wood: BufferGeometry
    # The leaf cards, with `position`, `normal` and `color`.
    var leaves: BufferGeometry
    # The middle of the crown, and how far its furthest leaf is from it.
    var crown_center: Vector3
    var crown_radius: Float32
    # How many leaves the crown has.
    var leaf_count: Int

    def __init__(
        out self,
        var wood: BufferGeometry,
        var leaves: BufferGeometry,
        crown_center: Vector3,
        crown_radius: Float32,
        leaf_count: Int,
    ):
        """Hold a grown tree.

        Args:
            wood: The trunk and the branches.
            leaves: The leaf cards.
            crown_center: The middle of the crown, in meters.
            crown_radius: How far the furthest leaf is from it.
            leaf_count: How many leaves the crown has.
        """
        self.wood = wood^
        self.leaves = leaves^
        self.crown_center = crown_center
        self.crown_radius = crown_radius
        self.leaf_count = leaf_count


def _bark_colors(count: Int) -> List[Float32]:
    """Return one bark color a vertex."""
    var colors = List[Float32]()
    colors.reserve(3 * count)
    for _ in range(count):  # pragma: no branch
        colors.append(BARK.x)
        colors.append(BARK.y)
        colors.append(BARK.z)
    return colors^


@fieldwise_init
struct CrownLevel(ImplicitlyCopyable):
    """One level of detail of a crown: how far it reaches, and the
    fraction of the leaves it keeps."""

    # The furthest a tree can be for this level.
    var reach: Length
    # The fraction of the leaves this level keeps, from 0.01 to 1.
    var detail: Float32

    def check(self) raises:
        """Refuse a level that cannot be used.

        Raises:
            Error: If the reach is not from 0 to 100 kilometers, or the
                detail is not from 0.01 to 1.
        """
        require_between(
            self.reach.to(METER),
            0,
            1.0e5,
            "A crown level must reach from 0 to 100 kilometers",
        )
        require_between(
            self.detail, 0.01, 1, "A crown's detail must be from 0.01 to 1"
        )


def default_crown_levels() -> List[CrownLevel]:
    """Return the three levels of a treeline seen across a meadow.

    A leaf of the far level is about three times as long as a near one,
    which is still a few pixels wide at that distance.

    Returns:
        Every leaf to 28 meters, 30 percent of them to 60 meters, and 11
        percent past that.
    """
    return [
        CrownLevel(Length(28.0, METER), 1.0),
        CrownLevel(Length(60.0, METER), 0.3),
        CrownLevel(Length(1.0e5, METER), 0.11),
    ]


def crown_level_for(levels: List[CrownLevel], distance: Float32) raises -> Int:
    """Return the first level whose reach holds a distance.

    Args:
        levels: The levels, nearest first.
        distance: How far the tree is, in meters.

    Returns:
        The level's index, or the last level past every reach.

    Raises:
        Error: If there is no level.
    """
    if len(levels) == 0:
        raise Error("A crown with no level has nothing to wear")
    for index in range(len(levels)):  # pragma: no branch
        if distance <= levels[index].reach.to(METER):
            return index
    return len(levels) - 1


def leafy_tree(
    parameters: CrownParameters, detail: Float32, lean_wood: Bool = False
) raises -> LeafyTree:
    """Grow a tree and put leaves on its twigs.

    Args:
        parameters: The branches and the leaves.
        detail: The fraction of the leaves to keep, from 0.01 to 1. Each
            kept leaf grows by the inverse square root of it.
        lean_wood: Whether to build the wood of a far tree: one level of
            branches fewer, three vertices round each ring. The leaves
            still sit where the full tree's twigs are, and they hide the
            difference.

    Returns:
        The wood and the leaves.

    Raises:
        Error: If `parameters.check` refuses a value, `detail` is out of
            range, or the tree has no twig thin enough to carry a leaf.
    """
    parameters.check()
    require_between(detail, 0.01, 1, "A crown's detail must be from 0.01 to 1")
    var generator = TreeGenerator(parameters.tree.copy())
    var wood_tree = parameters.tree.copy()
    if lean_wood:
        wood_tree.levels = max(1, wood_tree.levels - 1)
        wood_tree.radial_segments = 3
    var wood = TreeGenerator(wood_tree^).build()
    wood.set_attribute(
        COLOR, BufferAttribute(_bark_colors(wood.vertex_count()), 3)
    )
    var tubes = generator.tubes()
    var twig = Float64(parameters.twig_radius.to(METER))
    var anchors = List[Vector3]()
    for t in range(len(tubes)):  # pragma: no branch
        ref rings = tubes[t].rings
        for r in range(len(rings)):  # pragma: no branch
            if rings[r].radius < twig:
                var p = rings[r].position
                anchors.append(
                    Vector3(Float32(p.x), Float32(p.y), Float32(p.z))
                )
    if len(anchors) == 0:
        raise Error(
            "A tree with no twig thinner than its twig radius has no leaves"
        )
    var center = Vector3(0, 0, 0)
    for a in range(len(anchors)):  # pragma: no branch
        center = center + anchors[a]
    center = center / Float32(len(anchors))
    var seed = parameters.seed * 104729
    var grow = 1 / sqrt(detail)
    var length = parameters.leaf_length.to(METER) * grow
    var width = parameters.leaf_width.to(METER) * grow
    var spread = parameters.spread.to(METER)
    var turn = Float32(2) * Float32(pi)
    # Pass one: place the leaves, and find how far the crown reaches.
    var places = List[Vector3]()
    var keys = List[Int]()
    var radius = Float32(0)
    for a in range(len(anchors)):  # pragma: no branch
        for k in range(parameters.leaves_per_ring):  # pragma: no branch
            var key = a * 256 + k
            if hash01(key, 0, seed) >= detail:
                continue
            var yaw = turn * hash01(key, 1, seed)
            var lift = hash01(key, 2, seed) * 2 - 1
            var out = spread * sqrt(hash01(key, 3, seed))
            var flat = sqrt(1 - lift * lift)
            var place = anchors[a] + Vector3(
                cos(yaw) * flat * out, lift * out, sin(yaw) * flat * out
            )
            places.append(place)
            keys.append(key)
            radius = max(radius, (place - center).length())
    if len(places) == 0:
        raise Error("A crown at this detail keeps no leaf")
    var positions = List[Float32]()
    var normals = List[Float32]()
    var colors = List[Float32]()
    var index = List[Int]()
    positions.reserve(12 * len(places))
    normals.reserve(12 * len(places))
    colors.reserve(12 * len(places))
    index.reserve(6 * len(places))
    var bottom = center.y - radius
    for i in range(len(places)):  # pragma: no branch
        var place = places[i]
        var key = keys[i]
        # The card's long axis and its short axis, turned a random way.
        var yaw = turn * hash01(key, 4, seed)
        var pitch = (hash01(key, 5, seed) - 0.5) * 2.2
        var along = Vector3(
            cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)
        )
        var across = Vector3(-sin(yaw), 0, cos(yaw))
        var own = Vector3(
            across.y * along.z - across.z * along.y,
            across.z * along.x - across.x * along.z,
            across.x * along.y - across.y * along.x,
        )
        var outward = place - center
        var reach = outward.length()
        var crown = outward / max(reach, Float32(1.0e-6))
        var normal = crown * (1 - OWN_NORMAL) + own * OWN_NORMAL
        normal = normal / max(normal.length(), Float32(1.0e-6))
        var depth = min(Float32(1), reach / max(radius, Float32(1.0e-6)))
        var height = min(
            Float32(1), (place.y - bottom) / max(2 * radius, Float32(1.0e-6))
        )
        var light = DEEPEST + (1 - DEEPEST) * (0.55 * depth + 0.45 * height)
        var tint = LEAF + (LEAF_LIGHT - LEAF) * hash01(key, 6, seed)
        var color = tint * light
        var half_length = along * (length * 0.5)
        var half_width = across * (width * 0.5)
        var corners: List[Vector3] = [
            place - half_length,
            place - half_width,
            place + half_length,
            place + half_width,
        ]
        var first = len(positions) // 3
        for c in range(4):  # pragma: no branch
            positions.append(corners[c].x)
            positions.append(corners[c].y)
            positions.append(corners[c].z)
            normals.append(normal.x)
            normals.append(normal.y)
            normals.append(normal.z)
            colors.append(color.x)
            colors.append(color.y)
            colors.append(color.z)
        index.append(first)
        index.append(first + 1)
        index.append(first + 2)
        index.append(first)
        index.append(first + 2)
        index.append(first + 3)
    var count = len(places)
    var leaves = BufferGeometry()
    leaves.set_attribute(POSITION, BufferAttribute(positions^, 3))
    leaves.set_attribute(NORMAL, BufferAttribute(normals^, 3))
    leaves.set_attribute(COLOR, BufferAttribute(colors^, 3))
    leaves.set_index(index^)
    return LeafyTree(wood^, leaves^, center, radius, count)
