# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Broadleaf trees and bushes: limbs, sprays of leaves, and their light.

`grow_crown` grows a tree's limbs into the shape of its crown, by space
colonization: see `extensions.vegetation.limbs`. Then it hangs the leaves
on the twigs. Each node within `leaf_reach` of a twig's tip carries
`leaves_per_node` leaves on the stretch of twig below it. Each leaf splays
out from its twig, toward the twig's tip and a little down, and turns its
face up and out of the crown. The leaves of one twig make a spray, and the
sprays of one limb make a lobe, so a crown is lobes with sky between
them. Neighboring twigs share a tint, and a slow noise makes patches of
the crown lighter or darker, so the lobes differ in color.

**The light.** `LeafShade` counts the leaves in a grid and gives each leaf
the sun and the sky that reach it through the others: see
`extensions.vegetation.foliage`. A leaf that sees neither is never seen
either, and is left out. The sun's direction is baked into the leaves, so
a tree must not be turned about +y once it is grown. Grow more seeds for
more variety.

**The bark** is pale with dark patches, as a birch's or a eucalyptus's is,
and darker near the ground.

**The levels of detail.** A crown is grown once, and `dress` makes the
meshes of one level from it. A level keeps a fraction of the leaves and
makes each larger by the inverse square root of the fraction, so the crown
keeps its cover. A level can draw its leaves as two-triangle cards, on
lean wood. A far tree is still geometry and not an impostor: it is lit,
and it casts a shadow, as a near tree does.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.foliage import LeafMesh, LeafShade, sky_rays
from extensions.vegetation.limbs import (
    CrownShape,
    LimbParameters,
    Skeleton,
    grow_limbs,
    limb_mesh,
)
from extensions.vegetation.noise import hash01, value_noise, value_noise3
from math.vector3 import Vector3
from std.math import atan2, cos, pi, sin, sqrt
from units.si import DEGREE, METER, PER_METER, Angle, InverseLength, Length

# A leaf whose sun and sky are both below this is left out.
comptime UNSEEN = Float32(0.004)
# The share of the sun that a leaf in the shade still gets, through the
# leaves between it and the sun: a leaf lets a tenth of its light through.
comptime PASSED_ON = Float32(0.1)
# A leaf's area as a share of its length times its width.
comptime LEAF_FILL = Float32(0.65)
# The side of a shade cell, as a fraction of the crown's radius, and the
# smallest and largest it can be, in meters.
comptime SHADE_CELL = Float32(0.11)
comptime SMALLEST_CELL = Float32(0.08)
comptime LARGEST_CELL = Float32(0.45)
# How many neighboring twig nodes share one tint, and how large a patch
# of one shade of a crown is, in meters.
comptime SPRAY = 3
comptime LOBE_TINT = Float32(2.2)


struct CrownParameters(Copyable, Movable):
    """The limbs of a tree, its leaves, and its colors."""

    # The crown's shape and how the branches grow into it.
    var limbs: LimbParameters
    # The thinnest branch drawn, at full detail.
    var wood_radius: Length
    # The most vertices round a branch's ring.
    var sides: Int
    # How far back from a twig's tip the leaves grow.
    var leaf_reach: Length
    # How many leaves each node near a tip carries.
    var leaves_per_node: Int
    # The length and width of one leaf.
    var leaf_length: Length
    var leaf_width: Length
    # How much of its area a leaf shades along a ray. A half is leaves
    # that face every way; more is leaves that crowd in clumps.
    var shade: Float32
    # The linear colors of a leaf: one tint and another, mixed per spray.
    var leaf: Vector3
    var leaf_light: Vector3
    # The linear colors of the bark and of its dark patches, and how many
    # patches a meter climb the trunk. Many short patches are a birch's
    # marks.
    var bark: Vector3
    var bark_dark: Vector3
    var bark_marks: InverseLength
    # Which leaves to grow.
    var seed: Int

    def __init__(out self):
        """Create an open tree about 14 meters tall, as a lone tree in a
        meadow is.

        Its pale trunk is bare for 5 meters and forks into thin limbs. The
        crown is 10 meters across, of lobes of small leaves with sky
        between them, and its lowest sprays droop.
        """
        var limbs = LimbParameters()
        limbs.shape = CrownShape(
            Length(5.2, METER),
            Length(14.5, METER),
            Length(6.0, METER),
            0.5,
            9,
            Length(2.5, METER),
            0.45,
            0.15,
        )
        limbs.points = 7000
        limbs.droop = 0.3
        limbs.fork = 0.15
        self.limbs = limbs^
        self.wood_radius = Length(0.006, METER)
        self.sides = 10
        self.leaf_reach = Length(0.9, METER)
        self.leaves_per_node = 20
        self.leaf_length = Length(0.15, METER)
        self.leaf_width = Length(0.08, METER)
        self.shade = 0.5
        self.leaf = Vector3(0.050, 0.100, 0.026)
        self.leaf_light = Vector3(0.125, 0.180, 0.044)
        self.bark = Vector3(0.330, 0.310, 0.270)
        self.bark_dark = Vector3(0.060, 0.052, 0.044)
        self.bark_marks = InverseLength(1.7, PER_METER)
        self.seed = 1

    def check(self) raises:
        """Refuse parameters that cannot grow a crown.

        Raises:
            Error: If the limbs are refused, the thinnest wood is not from
                half a millimeter to 1 meter, a ring has not from 3 to 32
                sides, the leaves reach back from a tip further than 20
                meters, a node has not from 1 to 200 leaves, a leaf is not
                from 5 millimeters to 2 meters long and wide, the shade is
                not from 0 to 50, the bark has not from 0.1 to 50 marks a
                meter, or a color channel is not from 0 to 1.
        """
        self.limbs.check()
        require_between(
            self.wood_radius.to(METER),
            0.0005,
            1,
            "The thinnest wood must be from half a millimeter to 1 meter",
        )
        require_count_between(
            self.sides, 3, 32, "A branch must have from 3 to 32 sides"
        )
        require_between(
            self.leaf_reach.to(METER),
            0,
            20,
            "Leaves must grow from 0 to 20 meters back from a tip",
        )
        require_count_between(
            self.leaves_per_node,
            1,
            200,
            "A node must hold from 1 to 200 leaves",
        )
        require_between(
            self.leaf_length.to(METER),
            0.005,
            2,
            "A leaf must be from 5 millimeters to 2 meters long",
        )
        require_between(
            self.leaf_width.to(METER),
            0.005,
            2,
            "A leaf must be from 5 millimeters to 2 meters wide",
        )
        require_between(
            self.shade, 0, 50, "A crown's shade must be from 0 to 50"
        )
        require_between(
            self.bark_marks.to(PER_METER),
            0.1,
            50,
            "Bark must have from 0.1 to 50 marks a meter",
        )
        var colors: List[Vector3] = [
            self.leaf,
            self.leaf_light,
            self.bark,
            self.bark_dark,
        ]
        for index in range(len(colors)):  # pragma: no branch
            require_between(colors[index].x, 0, 1, "A color must be 0 to 1")
            require_between(colors[index].y, 0, 1, "A color must be 0 to 1")
            require_between(colors[index].z, 0, 1, "A color must be 0 to 1")


def windswept_tree() -> CrownParameters:
    """Return a slender, sparse tree about 12 meters tall.

    Its dark trunk leans and wanders. Its narrow crown starts low, and is
    a few wisps of leaves with wide gaps of sky between them.

    Returns:
        The parameters.
    """
    var crown = CrownParameters()
    crown.limbs.shape = CrownShape(
        Length(3.4, METER),
        Length(12.5, METER),
        Length(2.6, METER),
        0.58,
        7,
        Length(1.25, METER),
        0.6,
        0.1,
    )
    crown.limbs.points = 3500
    crown.limbs.fork = 0.4
    crown.limbs.lean = Angle(7.0, DEGREE)
    crown.limbs.bend = 0.6
    crown.limbs.gnarl = 0.35
    crown.leaf_reach = Length(0.75, METER)
    crown.leaves_per_node = 14
    crown.bark = Vector3(0.140, 0.125, 0.105)
    crown.bark_dark = Vector3(0.040, 0.035, 0.030)
    return crown^


def birch_tree() -> CrownParameters:
    """Return a birch about 16 meters tall.

    Its white trunk is marked with short dark bands, and bare for 6
    meters. Its narrow crown is lobes of small, light leaves on limbs that
    droop.

    Returns:
        The parameters.
    """
    var crown = CrownParameters()
    crown.limbs.shape = CrownShape(
        Length(6.0, METER),
        Length(16.0, METER),
        Length(3.2, METER),
        0.45,
        8,
        Length(1.4, METER),
        0.55,
        0.15,
    )
    crown.limbs.points = 4500
    crown.limbs.up_pull = 0.12
    crown.limbs.droop = 0.45
    crown.limbs.fork = 0.35
    crown.limbs.lean = Angle(3.0, DEGREE)
    crown.limbs.bend = 0.25
    crown.limbs.tip_radius = Length(0.004, METER)
    crown.leaf_reach = Length(0.9, METER)
    crown.leaves_per_node = 22
    crown.leaf_length = Length(0.075, METER)
    crown.leaf_width = Length(0.05, METER)
    crown.shade = 0.55
    crown.leaf = Vector3(0.055, 0.110, 0.030)
    crown.leaf_light = Vector3(0.140, 0.200, 0.050)
    crown.bark = Vector3(0.620, 0.600, 0.560)
    crown.bark_dark = Vector3(0.035, 0.033, 0.030)
    crown.bark_marks = InverseLength(6.0, PER_METER)
    return crown^


def young_tree() -> CrownParameters:
    """Return a young tree about 9 meters tall.

    Its crown is a tall oval from 2 meters up, 4 meters across, and denser
    than an old tree's.

    Returns:
        The parameters.
    """
    var crown = CrownParameters()
    crown.limbs.shape = CrownShape(
        Length(1.9, METER),
        Length(9.4, METER),
        Length(2.0, METER),
        0.4,
        8,
        Length(1.05, METER),
        0.35,
        0.15,
    )
    crown.limbs.points = 4000
    crown.limbs.step = Length(0.22, METER)
    crown.limbs.reach = Length(1.4, METER)
    crown.limbs.kill = Length(0.35, METER)
    crown.limbs.up_pull = 0.25
    crown.limbs.droop = 0.1
    crown.limbs.fork = 0.55
    crown.leaf_reach = Length(0.8, METER)
    crown.leaves_per_node = 24
    crown.leaf_length = Length(0.15, METER)
    crown.leaf_width = Length(0.085, METER)
    crown.shade = 0.6
    crown.leaf = Vector3(0.036, 0.084, 0.026)
    crown.leaf_light = Vector3(0.090, 0.150, 0.040)
    crown.bark = Vector3(0.200, 0.185, 0.160)
    return crown^


def round_tree() -> CrownParameters:
    """Return a broad, dense tree about 11 meters tall.

    Its crown reaches nearly to the ground and is one dark mass of lobes,
    9 meters across.

    Returns:
        The parameters.
    """
    var crown = CrownParameters()
    crown.limbs.shape = CrownShape(
        Length(1.6, METER),
        Length(11.0, METER),
        Length(4.4, METER),
        0.42,
        14,
        Length(2.0, METER),
        0.3,
        0.3,
    )
    crown.limbs.points = 8000
    crown.limbs.up_pull = 0.1
    crown.limbs.fork = 0.25
    crown.leaves_per_node = 24
    crown.leaf_length = Length(0.17, METER)
    crown.leaf_width = Length(0.095, METER)
    crown.shade = 0.7
    crown.leaf = Vector3(0.036, 0.082, 0.026)
    crown.leaf_light = Vector3(0.085, 0.145, 0.040)
    crown.bark = Vector3(0.120, 0.105, 0.090)
    return crown^


def bush_parameters() -> CrownParameters:
    """Return a bush about 2 meters tall, with broad leaves.

    Its stems fork from the ground. Its leaves are 12 centimeters long,
    large enough to read one by one from a few meters away.

    Returns:
        The parameters.
    """
    var bush = CrownParameters()
    bush.limbs.shape = CrownShape(
        Length(0.02, METER),
        Length(1.9, METER),
        Length(1.35, METER),
        0.3,
        7,
        Length(0.65, METER),
        0.3,
        0,
    )
    bush.limbs.points = 1500
    bush.limbs.step = Length(0.08, METER)
    bush.limbs.reach = Length(0.5, METER)
    bush.limbs.kill = Length(0.14, METER)
    bush.limbs.up_pull = 0.25
    bush.limbs.droop = 0.2
    bush.limbs.fork = 0
    bush.limbs.lean = Angle(0.0, DEGREE)
    bush.limbs.bend = 0.1
    bush.limbs.gnarl = 0.35
    bush.limbs.tip_radius = Length(0.0025, METER)
    bush.limbs.pipe = 2.0
    bush.limbs.flare = 0
    bush.wood_radius = Length(0.004, METER)
    bush.sides = 5
    bush.leaf_reach = Length(0.35, METER)
    bush.leaves_per_node = 3
    bush.leaf_length = Length(0.12, METER)
    bush.leaf_width = Length(0.08, METER)
    bush.shade = 0.8
    bush.leaf = Vector3(0.060, 0.135, 0.030)
    bush.leaf_light = Vector3(0.130, 0.210, 0.050)
    bush.bark = Vector3(0.100, 0.085, 0.060)
    return bush^


@fieldwise_init
struct CrownLevel(ImplicitlyCopyable):
    """One level of detail of a crown: how far it reaches, the fraction
    of the leaves it keeps, and whether they are cards."""

    # The furthest a tree can be for this level.
    var reach: Length
    # The fraction of the leaves this level keeps, from 0.01 to 1.
    var detail: Float32
    # Whether the leaves are two-triangle cards on lean wood.
    var cards: Bool

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
    """Return the four levels of trees seen across a meadow.

    Returns:
        Every leaf to 40 meters, 40 percent of them to 110 meters, 16
        percent as cards to 300 meters, and 5 percent as cards past that,
        for the woodland beyond the canyon.
    """
    return [
        CrownLevel(Length(40.0, METER), 1.0, False),
        CrownLevel(Length(110.0, METER), 0.4, False),
        CrownLevel(Length(300.0, METER), 0.16, True),
        CrownLevel(Length(1.0e5, METER), 0.05, True),
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


@fieldwise_init
struct Leaf(ImplicitlyCopyable):
    """One leaf of a grown crown, before a level draws it."""

    # Where it meets its twig, in meters.
    var base: Vector3
    # Its midrib, across it, and its face: unit directions.
    var along: Vector3
    var across: Vector3
    var normal: Vector3
    # Its size, as a multiple of the crown's leaf.
    var scale: Float32
    # Its linear color.
    var color: Vector3
    # The share of the sun that reaches it, and of the sky it sees.
    var sun: Float32
    var sky: Float32
    # A level keeps it if the level's detail is above this.
    var keep: Float32


struct GrownCrown(Movable):
    """A crown grown once: its branches and its lit leaves, from which
    `dress` makes the meshes of each level."""

    var skeleton: Skeleton
    var leaves: List[Leaf]

    def __init__(out self, var skeleton: Skeleton, var leaves: List[Leaf]):
        """Hold a grown crown.

        Args:
            skeleton: The branches.
            leaves: The leaves, lit.
        """
        self.skeleton = skeleton^
        self.leaves = leaves^


struct LeafyTree(Movable):
    """A tree's wood and its leaves at one level, as two geometries."""

    # The trunk and the branches, with `position`, `normal` and `color`.
    var wood: BufferGeometry
    # The leaves, with `position`, `normal`, `color`, `SUNLIT` and
    # `SKYLIT`.
    var leaves: BufferGeometry
    # How many leaves the crown has.
    var leaf_count: Int

    def __init__(
        out self,
        var wood: BufferGeometry,
        var leaves: BufferGeometry,
        leaf_count: Int,
    ):
        """Hold a dressed tree.

        Args:
            wood: The trunk and the branches.
            leaves: The leaves.
            leaf_count: How many leaves the crown has.
        """
        self.wood = wood^
        self.leaves = leaves^
        self.leaf_count = leaf_count


def _bark_colors(
    wood: BufferGeometry, parameters: CrownParameters
) raises -> List[Float32]:
    """Return one bark color a vertex: pale, with dark patches round the
    trunk and darker near the ground."""
    ref positions = wood.attribute_view(String(POSITION))
    var colors = List[Float32]()
    colors.reserve(3 * positions.count())
    var seed = parameters.seed * 31 + 7
    for v in range(positions.count()):  # pragma: no branch
        var p = positions.vector3(v)
        var round = atan2(p.z, p.x) / Float32(pi) * 3
        var patch = value_noise(
            round, p.y * parameters.bark_marks.to(PER_METER), seed
        )
        var dark = min(Float32(1), max(Float32(0), (patch - 0.55) * 4))
        var foot = min(Float32(1), p.y / 1.5)
        var shade = 0.55 + 0.45 * foot
        var c = (
            parameters.bark + (parameters.bark_dark - parameters.bark) * dark
        )
        colors.append(c.x * shade)
        colors.append(c.y * shade)
        colors.append(c.z * shade)
    return colors^


def _unit(v: Vector3) -> Vector3:
    """Return `v` scaled to unit length, or +y for a vector near zero."""
    var length = v.length()
    if length < 1.0e-6:
        return Vector3(0, 1, 0)
    return v / length


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product `a x b`."""
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def hang_leaves(skeleton: Skeleton, parameters: CrownParameters) -> List[Leaf]:
    """Return the leaves on the twigs of a skeleton, not yet lit.

    Args:
        skeleton: The branches, with each node's distance from its tip.
        parameters: The crown's leaves and colors.

    Returns:
        The leaves, with no sun and no sky.
    """
    ref shape = parameters.limbs.shape
    var mid = shape.middle()
    var radius = shape.radius.to(METER)
    var half = (shape.top.to(METER) - shape.bottom.to(METER)) * 0.5
    var reach = parameters.leaf_reach.to(METER)
    var length = parameters.leaf_length.to(METER)
    var seed = parameters.seed * 7919 + 3
    var turn = Float32(2) * Float32(pi)
    var up = Vector3(0, 1, 0)
    var leaves = List[Leaf]()
    for n in range(1, skeleton.count()):
        if skeleton.tip_distance[n] > reach:
            continue
        var a = skeleton.position[skeleton.parent[n]]
        var b = skeleton.position[n]
        var twig = b - a
        var way = _unit(twig)
        var side = _unit(
            _cross(way, up) if abs(way.y) < 0.95 else Vector3(1, 0, 0)
        )
        var other = _cross(way, side)
        var outward = _unit(
            Vector3(
                (b.x - mid.x) / radius,
                (b.y - mid.y) / half,
                (b.z - mid.z) / radius,
            )
        )
        # A lobe is lighter or darker than its neighbors, and each spray
        # differs within it.
        var lobe = value_noise3(
            b.x / LOBE_TINT, b.y / LOBE_TINT, b.z / LOBE_TINT, seed + 9
        )
        var tint = (
            parameters.leaf
            + (parameters.leaf_light - parameters.leaf)
            * hash01(n // SPRAY, 0, seed)
        ) * (0.8 + 0.4 * lobe)
        for k in range(parameters.leaves_per_node):  # pragma: no branch
            var key = k * 8
            var spin = turn * hash01(n, key + 1, seed)
            var spoke = side * cos(spin) + other * sin(spin)
            # A leaf splays out from its twig, leans toward the twig's
            # tip, and hangs a little from its stalk.
            var along = _unit(spoke + way * 0.7 + Vector3(0, -0.35, 0))
            var jitter = Vector3(
                hash01(n, key + 2, seed) - 0.5,
                hash01(n, key + 3, seed) - 0.5,
                hash01(n, key + 4, seed) - 0.5,
            )
            var face = up * 0.75 + outward * 0.55 + jitter * 0.9
            var normal = _unit(face - along * face.dot(along))
            var across = _unit(_cross(along, normal))
            var scale = 0.7 + 0.6 * hash01(n, key + 5, seed)
            var base = a + twig * hash01(n, key, seed) + spoke * (length * 0.12)
            leaves.append(
                Leaf(
                    base,
                    along,
                    across,
                    normal,
                    scale,
                    tint * (0.8 + 0.4 * hash01(n, key + 6, seed)),
                    0,
                    0,
                    hash01(n, key + 7, seed + 1),
                )
            )
    return leaves^


def grow_crown(parameters: CrownParameters, sun: Vector3) raises -> GrownCrown:
    """Grow a tree's limbs, hang its leaves, and bake the light on each
    leaf.

    Args:
        parameters: The limbs, the leaves and the colors.
        sun: The unit direction toward the sun, in the tree's own frame.

    Returns:
        The branches and the leaves that anyone sees.

    Raises:
        Error: If `parameters.check` refuses a value, the sun's direction
            is not of unit length, or the tree has no twig.
    """
    parameters.check()
    require_between(
        sun.length(), 0.999, 1.001, "The sun's direction must be of unit length"
    )
    var skeleton = grow_limbs(parameters.limbs)
    var hung = hang_leaves(skeleton, parameters)
    if len(hung) == 0:
        raise Error("A tree with no twig has no leaves")
    var length = parameters.leaf_length.to(METER)
    var area = length * parameters.leaf_width.to(METER) * LEAF_FILL
    var low = hung[0].base
    var high = hung[0].base
    for index in range(len(hung)):  # pragma: no branch
        low.min(hung[index].base)
        high.max(hung[index].base)
    var cell = min(
        LARGEST_CELL,
        max(
            SMALLEST_CELL,
            parameters.limbs.shape.radius.to(METER) * SHADE_CELL,
        ),
    )
    var margin = Vector3(cell, cell, cell)
    var shade = LeafShade(low - margin, high + margin, Length(cell, METER))
    for index in range(len(hung)):  # pragma: no branch
        ref leaf = hung[index]
        shade.add(
            leaf.base + leaf.along * (length * 0.5 * leaf.scale),
            area * leaf.scale * leaf.scale,
        )
    shade.finish(parameters.shade)
    var rays = sky_rays()
    var leaves = List[Leaf]()
    for index in range(len(hung)):  # pragma: no branch
        var leaf = hung[index]
        var middle = leaf.base + leaf.along * (length * 0.5 * leaf.scale)
        var direct = shade.through(middle, sun)
        leaf.sky = shade.sky(middle, rays)
        if direct < UNSEEN and leaf.sky < UNSEEN:
            continue
        leaf.sun = direct + (1 - direct) * PASSED_ON * leaf.sky
        leaves.append(leaf)
    return GrownCrown(skeleton^, leaves^)


def dress(
    crown: GrownCrown, parameters: CrownParameters, level: CrownLevel
) raises -> LeafyTree:
    """Make the wood and the leaves of a grown crown at one level.

    Args:
        crown: The grown crown.
        parameters: The crown's parameters, as it was grown with.
        level: The level of detail: the fraction of leaves to keep, and
            whether they are cards on lean wood.

    Returns:
        The wood and the leaves.

    Raises:
        Error: If `level.check` refuses a value, no branch is as thick as
            the thinnest wood, or the level keeps no leaf.
    """
    level.check()
    var thinnest = parameters.wood_radius.to(METER)
    var sides = parameters.sides
    if level.cards:
        thinnest *= 3
        sides = 3
    var wood = limb_mesh(crown.skeleton, Length(thinnest, METER), sides)
    wood.set_attribute(
        COLOR, BufferAttribute(_bark_colors(wood, parameters), 3)
    )
    var grow = 1 / sqrt(level.detail)
    var length = parameters.leaf_length.to(METER) * grow
    var width = parameters.leaf_width.to(METER) * grow
    var mesh = LeafMesh()
    for index in range(len(crown.leaves)):  # pragma: no branch
        ref leaf = crown.leaves[index]
        if leaf.keep >= level.detail:
            continue
        var size = Vector3(
            length * leaf.scale, width * leaf.scale, length * leaf.scale * 0.25
        )
        if level.cards:
            mesh.add_card(
                leaf.base,
                leaf.along,
                leaf.across,
                leaf.normal,
                size,
                leaf.color,
                leaf.sun,
                leaf.sky,
            )
        else:
            mesh.add_ovate(
                leaf.base,
                leaf.along,
                leaf.across,
                leaf.normal,
                size,
                leaf.color,
                leaf.sun,
                leaf.sky,
            )
    if mesh.leaf_count() == 0:
        raise Error("A crown at this detail keeps no leaf")
    var count = mesh.leaf_count()
    return LeafyTree(wood^, mesh^.geometry(), count)


def leafy_tree(
    parameters: CrownParameters, level: CrownLevel, sun: Vector3
) raises -> LeafyTree:
    """Grow a crown and dress it at one level.

    Args:
        parameters: The limbs, the leaves and the colors.
        level: The level of detail.
        sun: The unit direction toward the sun, in the tree's own frame.

    Returns:
        The wood and the leaves.

    Raises:
        Error: If `grow_crown` or `dress` refuses.
    """
    var crown = grow_crown(parameters, sun)
    return dress(crown, parameters, level)
