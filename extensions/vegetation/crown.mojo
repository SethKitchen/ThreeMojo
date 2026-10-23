# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Broadleaf trees and bushes: branches, clumps of leaves, and their light.

`TreeGenerator` grows the trunk and the branches as tubes. `leafy_tree`
finds the twigs, the tubes thinner than `twig_radius` at their tips, and
hangs a clump of leaves on each, one every `clump_spacing` along its thin
end. Each clump holds up to `leaves_per_clump` leaves that crowd its
shell. Each leaf faces out of its clump and up toward the sky, and hangs
a little from its stalk.

**The light.** The crown's clumps are spheres, so the sun and the sky that
reach each leaf through them are exact: see `extensions.vegetation.foliage`.
A leaf that sees neither is never seen either, and is left out. The sun's
direction is baked into the leaves, so a tree must not be turned about
+y once it is grown. Grow more seeds for more variety.

**The bark** is pale with dark patches, as a birch's or a eucalyptus's is,
and darker near the ground.

**The levels of detail.** A far tree does not need every leaf. A level
keeps a fraction of the leaves and makes each larger by the inverse
square root of the fraction, so the crown keeps its cover. A level can
draw its leaves as two-triangle cards, and grow lean wood. A far tree is
still geometry and not an impostor: it is lit, and it casts a shadow, as
a near tree does.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.foliage import (
    Clump,
    LeafMesh,
    sky_rays,
    sky_through,
    sun_through,
)
from extensions.vegetation.noise import hash01, value_noise
from generators.tree import TreeGenerator, TreeParameters
from math.vector3 import Vector3
from std.math import atan2, cos, pi, pow, sin, sqrt
from units.si import DEGREE, METER, PER_METER, Angle, InverseLength, Length

# A leaf whose sun and sky are both below this is left out.
comptime UNSEEN = Float32(0.004)
# How far a clump's center sits above its twig, as a fraction of its
# radius: leaves grow up toward the light.
comptime CLUMP_LIFT = Float32(0.25)


struct CrownParameters(Copyable, Movable):
    """The branches of a tree, its clumps of leaves, and its colors."""

    # The branches.
    var tree: TreeParameters
    # A tube thinner than this at its tip is a twig and carries clumps.
    var twig_radius: Length
    # The mean radius of a clump.
    var clump_radius: Length
    # How far apart the clumps along one twig are.
    var clump_spacing: Length
    # How many leaves a clump holds, at full detail.
    var leaves_per_clump: Int
    # The length and width of one leaf.
    var leaf_length: Length
    var leaf_width: Length
    # How much a meter of clump dims the light that crosses it.
    var density: InverseLength
    # The linear colors of a leaf: one tint and another, mixed per clump.
    var leaf: Vector3
    var leaf_light: Vector3
    # The linear colors of the bark and of its dark patches.
    var bark: Vector3
    var bark_dark: Vector3
    # Which leaves to grow.
    var seed: Int

    def __init__(out self):
        """Create a slender tree about 14 meters tall.

        The trunk is pale and bare for half its height. Four limbs climb
        from it, fork twice, and carry clumps of small leaves with sky
        between them, as a lone tree in a meadow does.
        """
        var tree = TreeParameters()
        tree.levels = 4
        tree.children = [5, 4, 4]
        tree.branch_angle = [
            Angle(60.0, DEGREE),
            Angle(45.0, DEGREE),
            Angle(50.0, DEGREE),
        ]
        tree.angle_variance = Angle(14.0, DEGREE)
        tree.length_ratio = 0.62
        tree.branch_length_falloff = 0.45
        tree.trunk_length = Length(13.0, METER)
        tree.trunk_radius = Length(0.2, METER)
        tree.taper = 0.82
        tree.taper_curve = 0.9
        tree.root_flare = 0.35
        tree.radius_exponent = 2.0
        tree.min_radius = Length(0.012, METER)
        tree.min_length = Length(0.5, METER)
        tree.droop = InverseLength(0.03, PER_METER)
        tree.up_pull = 0.1
        tree.gnarl = [0.03, 0.1, 0.16, 0.22]
        tree.radial_segments = 9
        tree.section_length = Length(0.7, METER)
        tree.child_start = 0.3
        tree.trunk_clear = 0.45
        self.tree = tree^
        self.twig_radius = Length(0.03, METER)
        self.clump_radius = Length(0.8, METER)
        self.clump_spacing = Length(0.6, METER)
        self.leaves_per_clump = 640
        self.leaf_length = Length(0.15, METER)
        self.leaf_width = Length(0.09, METER)
        self.density = InverseLength(1.3, PER_METER)
        self.leaf = Vector3(0.050, 0.120, 0.020)
        self.leaf_light = Vector3(0.130, 0.215, 0.032)
        self.bark = Vector3(0.330, 0.310, 0.270)
        self.bark_dark = Vector3(0.060, 0.052, 0.044)
        self.seed = 1

    def check(self) raises:
        """Refuse parameters that cannot grow a crown.

        Raises:
            Error: If the tree is refused, the twig radius is not from 1
                millimeter to 1 meter, a clump's radius is not from 5
                centimeters to 10 meters, the spacing is not from 5
                centimeters to 10 meters, a clump has not from 1 to 10,000
                leaves, a leaf is not from 5 millimeters to 2 meters long
                and wide, the density is not from 0 to 100 per meter, or a
                color channel is not from 0 to 1.
        """
        self.tree.check()
        require_between(
            self.twig_radius.to(METER),
            0.001,
            1,
            "A twig must be from 1 millimeter to 1 meter thick",
        )
        require_between(
            self.clump_radius.to(METER),
            0.05,
            10,
            "A clump must be from 5 centimeters to 10 meters across",
        )
        require_between(
            self.clump_spacing.to(METER),
            0.05,
            10,
            "Clumps must be from 5 centimeters to 10 meters apart",
        )
        require_count_between(
            self.leaves_per_clump,
            1,
            10000,
            "A clump must hold from 1 to 10,000 leaves",
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
            self.density.to(PER_METER),
            0,
            100,
            "A crown's density must be from 0 to 100 per meter",
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


def broad_tree() -> CrownParameters:
    """Return a broad tree about 12 meters tall, for the far woods.

    It forks lower than the slender tree and carries more and larger
    clumps, so its crown is one dense mass of lobes.

    Returns:
        The parameters.
    """
    var crown = CrownParameters()
    crown.tree.children = [6, 4, 4]
    crown.tree.branch_angle = [
        Angle(46.0, DEGREE),
        Angle(44.0, DEGREE),
        Angle(52.0, DEGREE),
    ]
    crown.tree.trunk_length = Length(10.0, METER)
    crown.tree.trunk_radius = Length(0.3, METER)
    crown.tree.trunk_clear = 0.25
    crown.tree.length_ratio = 0.62
    crown.tree.up_pull = 0.08
    crown.clump_radius = Length(1.2, METER)
    crown.leaves_per_clump = 1100
    crown.leaf_length = Length(0.17, METER)
    crown.leaf_width = Length(0.1, METER)
    crown.density = InverseLength(1.5, PER_METER)
    crown.leaf = Vector3(0.035, 0.090, 0.016)
    crown.leaf_light = Vector3(0.080, 0.150, 0.024)
    crown.bark = Vector3(0.120, 0.105, 0.090)
    return crown^


def bush_parameters() -> CrownParameters:
    """Return a bush about 2 meters tall, with broad leaves.

    Its stems fork from the ground. Its leaves are ten centimeters long,
    large enough to read one by one from a few meters away.

    Returns:
        The parameters.
    """
    var bush = CrownParameters()
    bush.tree.levels = 3
    bush.tree.children = [8, 5]
    bush.tree.branch_angle = [Angle(55.0, DEGREE), Angle(45.0, DEGREE)]
    bush.tree.trunk_length = Length(1.3, METER)
    bush.tree.trunk_radius = Length(0.05, METER)
    bush.tree.trunk_clear = 0.04
    bush.tree.angle_variance = Angle(22.0, DEGREE)
    bush.tree.gnarl = [0.12, 0.2, 0.28]
    bush.tree.child_start = 0.15
    bush.tree.length_ratio = 0.62
    bush.tree.branch_length_falloff = 0.3
    bush.tree.section_length = Length(0.25, METER)
    bush.tree.min_radius = Length(0.006, METER)
    bush.tree.min_length = Length(0.2, METER)
    bush.tree.radial_segments = 5
    bush.tree.root_flare = 0
    bush.twig_radius = Length(0.015, METER)
    bush.clump_radius = Length(0.42, METER)
    bush.clump_spacing = Length(0.35, METER)
    bush.leaves_per_clump = 150
    bush.leaf_length = Length(0.12, METER)
    bush.leaf_width = Length(0.08, METER)
    bush.density = InverseLength(1.6, PER_METER)
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
    """Return the three levels of trees seen across a meadow.

    Returns:
        Every leaf to 40 meters, 40 percent of them to 110 meters, and 16
        percent as cards past that.
    """
    return [
        CrownLevel(Length(40.0, METER), 1.0, False),
        CrownLevel(Length(110.0, METER), 0.4, False),
        CrownLevel(Length(1.0e5, METER), 0.16, True),
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


struct LeafyTree(Movable):
    """A tree's wood and its leaves, as two geometries."""

    # The trunk and the branches, with `position`, `normal` and `color`.
    var wood: BufferGeometry
    # The leaves, with `position`, `normal`, `color`, `SUNLIT` and
    # `SKYLIT`.
    var leaves: BufferGeometry
    # The clumps the leaves hang in.
    var clumps: List[Clump]
    # How many leaves the crown has.
    var leaf_count: Int

    def __init__(
        out self,
        var wood: BufferGeometry,
        var leaves: BufferGeometry,
        var clumps: List[Clump],
        leaf_count: Int,
    ):
        """Hold a grown tree.

        Args:
            wood: The trunk and the branches.
            leaves: The leaves.
            clumps: The clumps the leaves hang in.
            leaf_count: How many leaves the crown has.
        """
        self.wood = wood^
        self.leaves = leaves^
        self.clumps = clumps^
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
        var patch = value_noise(round, p.y * 1.7, seed)
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


def crown_clumps(
    generator: TreeGenerator, parameters: CrownParameters
) raises -> List[Clump]:
    """Return the clumps a tree's twigs carry.

    Each twig carries a clump at its tip, and one more every
    `clump_spacing` back along it while it stays thinner than twice
    `twig_radius`.

    Args:
        generator: The tree's branches.
        parameters: The crown.

    Returns:
        The clumps.

    Raises:
        Error: If the tree has no twig, or its branches cannot be grown.
    """
    var tubes = generator.tubes()
    var twig = Float64(parameters.twig_radius.to(METER))
    var spacing = parameters.clump_spacing.to(METER)
    var radius = parameters.clump_radius.to(METER)
    var seed = parameters.seed * 104729
    var clumps = List[Clump]()
    for t in range(len(tubes)):  # pragma: no branch
        ref rings = tubes[t].rings
        if rings[len(rings) - 1].radius >= twig:
            continue
        var since = spacing
        var r = len(rings) - 1
        while r >= 0 and rings[r].radius < 2 * twig:
            var p = rings[r].position
            var here = Vector3(Float32(p.x), Float32(p.y), Float32(p.z))
            if since >= spacing:
                var size = radius * (0.7 + 0.6 * hash01(t, r, seed))
                clumps.append(
                    Clump(here + Vector3(0, size * CLUMP_LIFT, 0), size)
                )
                since = 0
            if r > 0:
                var q = rings[r - 1].position
                since += (
                    here - Vector3(Float32(q.x), Float32(q.y), Float32(q.z))
                ).length()
            r -= 1
    if len(clumps) == 0:
        raise Error(
            "A tree with no twig thinner than its twig radius has no leaves"
        )
    return clumps^


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


def leafy_tree(
    parameters: CrownParameters, level: CrownLevel, sun: Vector3
) raises -> LeafyTree:
    """Grow a tree, hang its clumps, and bake the light on each leaf.

    Args:
        parameters: The branches, the clumps and the colors.
        level: The level of detail: the fraction of leaves to keep, and
            whether they are cards on lean wood.
        sun: The unit direction toward the sun, in the tree's own frame.

    Returns:
        The wood, the leaves and the clumps.

    Raises:
        Error: If `parameters.check` or `level.check` refuses a value, the
            sun's direction is not of unit length, the tree has no twig,
            or the level keeps no leaf anyone sees.
    """
    parameters.check()
    level.check()
    require_between(
        sun.length(), 0.999, 1.001, "The sun's direction must be of unit length"
    )
    var generator = TreeGenerator(parameters.tree.copy())
    var clumps = crown_clumps(generator, parameters)
    var wood_tree = parameters.tree.copy()
    if level.cards:
        wood_tree.levels = max(1, wood_tree.levels - 1)
        wood_tree.radial_segments = 3
    var wood = TreeGenerator(wood_tree^).build()
    wood.set_attribute(
        COLOR, BufferAttribute(_bark_colors(wood, parameters), 3)
    )
    var rays = sky_rays()
    var density = parameters.density.to(PER_METER)
    var grow = 1 / sqrt(level.detail)
    var size = Vector3(
        parameters.leaf_length.to(METER) * grow,
        parameters.leaf_width.to(METER) * grow,
        parameters.leaf_length.to(METER) * grow * 0.25,
    )
    var seed = parameters.seed * 7919 + 3
    var turn = Float32(2) * Float32(pi)
    var mesh = LeafMesh()
    for c in range(len(clumps)):  # pragma: no branch
        ref clump = clumps[c]
        var tint = parameters.leaf + (
            parameters.leaf_light - parameters.leaf
        ) * hash01(c, 0, seed)
        for k in range(parameters.leaves_per_clump):  # pragma: no branch
            var key = k * 8
            if hash01(c, key, seed + 1) >= level.detail:
                continue
            # A direction out of the clump, a little toward the sky, and
            # a place near the shell along it.
            var z = hash01(c, key + 1, seed) * 2 - 1
            var round = turn * hash01(c, key + 2, seed)
            var flat = sqrt(1 - z * z)
            var outward = _unit(
                Vector3(flat * cos(round), z + 0.3, flat * sin(round))
            )
            # The shell is lumpy, and a few leaves stray past it, so a
            # clump has a ragged edge and not a sphere's.
            var deep = pow(hash01(c, key + 3, seed), Float32(0.35))
            var lump = 0.75 + 0.5 * value_noise(
                outward.x * 2.5 + Float32(c),
                outward.z * 2.5 + outward.y * 2.5,
                seed + 2,
            )
            var stray = 1 + 0.35 * pow(hash01(c, key + 7, seed), Float32(6))
            var place = clump.center + outward * (
                clump.radius * (0.4 + 0.6 * deep) * lump * stray
            )
            var sky = sky_through(place, rays, clumps, density)
            var lit = sun_through(place, sun, clumps, density)
            if sky < UNSEEN and lit < UNSEEN:
                continue
            # The face turns out of the clump and up; the midrib hangs.
            var spin = turn * hash01(c, key + 4, seed)
            var jitter = Vector3(
                cos(spin), hash01(c, key + 5, seed) - 0.5, sin(spin)
            )
            var normal = _unit(
                outward * 0.6 + Vector3(0, 0.55, 0) + jitter * 0.35
            )
            var side = _unit(_cross(normal, Vector3(cos(spin), 0, sin(spin))))
            var along = _unit(_cross(side, normal) + Vector3(0, -0.3, 0))
            var across = _unit(_cross(along, normal))
            var color = tint * (0.8 + 0.4 * hash01(c, key + 6, seed))
            var base = place - along * (size.x * 0.4)
            if level.cards:
                mesh.add_card(
                    base, along, across, normal, size, color, lit, sky
                )
            else:
                mesh.add_ovate(
                    base, along, across, normal, size, color, lit, sky
                )
    if mesh.leaf_count() == 0:
        raise Error("A crown at this detail keeps no leaf anyone sees")
    var count = mesh.leaf_count()
    return LeafyTree(wood^, mesh^.geometry(), clumps^, count)
