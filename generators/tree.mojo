# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A procedural tree skeleton, from three.js
`examples/jsm/generators/TreeGenerator.js`.

The trunk, the branches and the twigs are tubes. Each tube is swept along
a gently bent path in rings, and each ring is a circle of vertices. A
branch forks into children along its upper part. Each child is thinner by
the pipe model, tilted off its parent, rolled by the golden angle and
pulled back toward the light. The tubes are baked into one indexed
geometry with positions and normals. There are no leaves: three.js adds
foliage as a separate layer.

The sweep carries a frame with it by parallel transport: each step turns
the frame by the turn that bends the tangent, so a tube never twists.

The branching is fixed by the seed. The same seed and parameters give the
same geometry as three.js, number for number up to `Float32` rounding.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from generators.utils import (
    Vec3d,
    check_finite,
    generator_random,
    meters,
    radians,
)
from math.utils import SeededRandom
from std.math import atan2, cos, floor, pi, pow, sin
from units.si import (
    Angle,
    DEGREE,
    InverseLength,
    Length,
    METER,
    PER_METER,
)

# The golden angle, about 137.5 degrees. Rolling each sibling by it spreads
# the branches round the stem so they never line up.
comptime GOLDEN_ANGLE = 2.399963229728653


@fieldwise_init
struct TreeRing(ImplicitlyCopyable):
    """One ring of a tube: its center, its frame and its radius."""

    var position: Vec3d
    var tangent: Vec3d
    var normal: Vec3d
    var radius: Float64


struct TreeTube(Copyable, Movable):
    """One branch as a tube: its rings, and how many vertices go round
    each."""

    var rings: List[TreeRing]
    var radial: Int

    def __init__(out self, var rings: List[TreeRing], radial: Int):
        """Create a tube.

        Args:
            rings: The rings, from base to tip.
            radial: The vertices round each ring.
        """
        self.rings = rings^
        self.radial = radial


struct TreeParameters(Copyable, Movable):
    """The parameters of a tree, three.js's `TreeGenerator.defaults`.

    The lists hold one entry a level, from the trunk out. A level past the
    end of a list takes the list's last entry.
    """

    # The seed of the branching.
    var seed: Int
    # The depth of the recursion: trunk, branch, twig, sub-twig.
    var levels: Int
    # The children a branch has, per level.
    var children: List[Int]
    # How far a child tilts off its parent's axis, per level.
    var branch_angle: List[Angle]
    # The random spread on the tilt.
    var angle_variance: Angle
    # A child's length over its parent's.
    var length_ratio: Float64
    # The random spread on a child's length, as a fraction.
    var length_variance: Float64
    # How much shorter the children are toward the tip of their parent.
    var branch_length_falloff: Float64
    # The trunk's length, which sets the tree's height.
    var trunk_length: Length
    # The trunk's radius at its base.
    var trunk_radius: Length
    # A branch thins to one minus this of its base radius at its tip.
    var taper: Float64
    # Under one keeps the bole full and then tapers; one is a cone.
    var taper_curve: Float64
    # How much the trunk swells at its very base.
    var root_flare: Float64
    # The fraction of the trunk the swell covers.
    var flare_frac: Float64
    # The pipe model's exponent: a child's base radius is its parent's
    # times one over the child count to the power one over this.
    var radius_exponent: Float64
    # The thinnest a branch starts.
    var min_radius: Length
    # A branch shorter than this has no children.
    var min_length: Length
    # How far a branch sags per meter of its step; the trunk does not.
    var droop: InverseLength
    # How far a child is pulled toward straight up: zero to one.
    var up_pull: Float64
    # The random wobble on each step of a tube, per level.
    var gnarl: List[Float64]
    # The vertices round the trunk's rings. One fewer each level, to three.
    var radial_segments: Int
    # The length of one step of a tube.
    var section_length: Length
    # The fraction up a branch before its children start.
    var child_start: Float64
    # The fraction of the trunk kept bare before the crown.
    var trunk_clear: Float64

    def __init__(out self):
        """Create three.js's default tree."""
        self.seed = 1
        self.levels = 4
        self.children = [3, 12, 8]
        self.branch_angle = [
            Angle(38, DEGREE),
            Angle(50, DEGREE),
            Angle(58, DEGREE),
        ]
        self.angle_variance = Angle(14, DEGREE)
        self.length_ratio = 0.62
        self.length_variance = 0
        self.branch_length_falloff = 0
        self.trunk_length = Length(9, METER)
        self.trunk_radius = Length(0.42, METER)
        self.taper = 0.55
        self.taper_curve = 0.7
        self.root_flare = 0.6
        self.flare_frac = 0.18
        self.radius_exponent = 2.3
        self.min_radius = Length(0.05, METER)
        self.min_length = Length(0.6, METER)
        self.droop = InverseLength(0.05, PER_METER)
        self.up_pull = 0.3
        self.gnarl = [0.05, 0.16, 0.26, 0.32]
        self.radial_segments = 6
        self.section_length = Length(1.3, METER)
        self.child_start = 0.12
        self.trunk_clear = 0.25

    def check(self) raises:
        """Refuse parameters three.js would grow nothing sensible from.

        Raises:
            Error: If there is no level, a list is empty, a child count is
                negative, the step length or the pipe exponent is not
                positive, or a number is not finite.
        """
        if self.levels < 1:
            raise Error("A tree needs one level at least")
        if len(self.children) == 0:
            raise Error("A tree needs a child count for one level at least")
        if len(self.branch_angle) == 0:
            raise Error("A tree needs a branch angle for one level at least")
        if len(self.gnarl) == 0:
            raise Error("A tree needs a gnarl for one level at least")
        for level in range(len(self.children)):  # pragma: no branch
            if self.children[level] < 0:
                raise Error("A child count must be zero or more")
        if meters(self.section_length) <= 0:
            raise Error("A tree's section length must be positive")
        if self.radius_exponent <= 0:
            raise Error("A tree's radius exponent must be positive")
        check_finite(meters(self.trunk_length), "A trunk length")
        check_finite(meters(self.trunk_radius), "A trunk radius")
        check_finite(self.taper + self.taper_curve, "A taper")
        check_finite(self.root_flare + self.flare_frac, "A root flare")
        check_finite(self.length_ratio, "A length ratio")


def _perpendicular(v: Vec3d) -> Vec3d:
    """Return a unit vector across `v`: its cross product with the axis
    it leans on least, three.js's `perpendicular`."""
    var axis = Vec3d(1, 0, 0) if abs(v.x) < 0.9 else Vec3d(0, 1, 0)
    return v.cross(axis).normalized()


def _transport(t0: Vec3d, t1: Vec3d, n: Vec3d) -> Vec3d:
    """Return `n` turned by the turn that takes tangent `t0` to `t1`,
    three.js's `transport`. Parallel tangents leave it as it is."""
    var axis = t0.cross(t1)
    var s = axis.length()
    if s < 1e-6:
        return n
    return n.rotated(axis * (1.0 / s), atan2(s, t0.dot(t1)))


def _ring_at(rings: List[TreeRing], t: Float64) -> TreeRing:
    """Return the frame a fraction of the way along a tube, three.js's
    `ringAt`."""
    var f = max(0.0, min(0.999, t)) * Float64(len(rings) - 1)
    var i = Int(floor(f))
    var frac = f - Float64(i)
    ref a = rings[i]
    ref b = rings[i + 1]
    return TreeRing(
        a.position.lerp(b.position, frac),
        a.tangent.lerp(b.tangent, frac).normalized(),
        a.normal.lerp(b.normal, frac).normalized(),
        a.radius + (b.radius - a.radius) * frac,
    )


def _js_round(value: Float64) -> Int:
    """Return JavaScript's `Math.round`: halves go up."""
    return Int(floor(value + 0.5))


def _signed(mut random: SeededRandom) -> Float64:
    """Return a number from minus one up to one, `random() * 2 - 1`."""
    return random.next() * 2 - 1


def _radius_at(
    p: TreeParameters, base_radius: Float64, level: Int, t: Float64
) -> Float64:
    """Return a tube's radius a fraction of the way along it: the taper,
    and the root flare on the trunk."""
    var radius = base_radius * (
        (1 - p.taper) + p.taper * pow(1 - t, p.taper_curve)
    )
    if level == 0 and p.root_flare > 0:
        var flare = max(0.0, (p.flare_frac - t) / p.flare_frac)
        radius *= 1 + p.root_flare * flare * flare * flare
    return radius


def _grow(
    mut tubes: List[TreeTube],
    base: Vec3d,
    direction: Vec3d,
    length: Float64,
    base_radius: Float64,
    level: Int,
    p: TreeParameters,
    mut random: SeededRandom,
):
    """Grow one branch as a tube, then its children, three.js's
    `growBranch`."""
    var sections = max(3, min(24, _js_round(length / meters(p.section_length))))
    var radial = max(3, p.radial_segments - level)
    var step = length / Float64(sections)
    var gnarl = p.gnarl[min(level, len(p.gnarl) - 1)]
    var start = p.trunk_clear if level == 0 else p.child_start
    var sag = Float64(p.droop.to(PER_METER)) * step if level > 0 else 0.0
    var tangent = direction.normalized()
    var normal = _perpendicular(tangent)
    var position = base
    var rings = List[TreeRing]()
    for s in range(sections + 1):  # pragma: no branch
        var t = Float64(s) / Float64(sections)
        rings.append(
            TreeRing(
                position, tangent, normal, _radius_at(p, base_radius, level, t)
            )
        )
        if s < sections:
            var dx = _signed(random) * gnarl
            var dy = _signed(random) * gnarl
            var dz = _signed(random) * gnarl
            var next = Vec3d(
                tangent.x + dx, tangent.y + dy - sag, tangent.z + dz
            ).normalized()
            normal = _transport(tangent, next, normal)
            position = position + next * step
            tangent = next
    tubes.append(TreeTube(rings.copy(), radial))
    if level >= p.levels - 1 or length < meters(p.min_length):
        return
    var n = p.children[min(level, len(p.children) - 1)]
    var angle = radians(p.branch_angle[min(level, len(p.branch_angle) - 1)])
    var pipe_drop = pow(1.0 / Float64(n), 1.0 / p.radius_exponent)
    var up = Vec3d(0, 1, 0)
    for i in range(n):
        var t = start + (
            Float64(i) + 0.5 + (random.next() - 0.5) * 0.6
        ) / Float64(n) * (1 - start)
        var ring = _ring_at(rings, t)
        var tilt = angle + _signed(random) * radians(p.angle_variance)
        var roll = Float64(i) * GOLDEN_ANGLE + _signed(random) * 0.4
        var child = ring.tangent.rotated(ring.normal, tilt).rotated(
            ring.tangent, roll
        )
        if p.up_pull > 0:
            child = child.lerp(up, p.up_pull).normalized()
        var child_base = max(
            meters(p.min_radius), min(base_radius * pipe_drop, ring.radius)
        )
        var child_length = (
            length * p.length_ratio * (1 - p.branch_length_falloff * t)
        )
        if p.length_variance > 0:
            child_length *= 1 + _signed(random) * p.length_variance
        _grow(
            tubes,
            ring.position,
            child,
            child_length,
            child_base,
            level + 1,
            p,
            random,
        )


def _bake(tubes: List[TreeTube]) raises -> BufferGeometry:
    """Write each ring's vertices once and join neighboring rings with
    triangles, three.js's `createGeometry`."""
    var positions = List[Float32]()
    var normals = List[Float32]()
    var index = List[Int]()
    var offset = 0
    for tube in range(len(tubes)):  # pragma: no branch
        ref rings = tubes[tube].rings
        var radial = tubes[tube].radial
        for r in range(len(rings)):  # pragma: no branch
            _write_ring(positions, normals, rings[r], radial)
        for r in range(len(rings) - 1):  # pragma: no branch
            _join(index, offset + r * radial, radial)
        offset += len(rings) * radial
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_index(index^)
    return geometry^


def _write_ring(
    mut positions: List[Float32],
    mut normals: List[Float32],
    ring: TreeRing,
    radial: Int,
):
    """Write one ring's vertices: a circle round its center in the plane of
    its normal and binormal."""
    var binormal = ring.tangent.cross(ring.normal)
    for j in range(radial):  # pragma: no branch
        var angle = Float64(j) / Float64(radial) * 2 * pi
        var c = cos(angle)
        var s = sin(angle)
        var nx = c * ring.normal.x + s * binormal.x
        var ny = c * ring.normal.y + s * binormal.y
        var nz = c * ring.normal.z + s * binormal.z
        positions.append(Float32(ring.position.x + nx * ring.radius))
        positions.append(Float32(ring.position.y + ny * ring.radius))
        positions.append(Float32(ring.position.z + nz * ring.radius))
        normals.append(Float32(nx))
        normals.append(Float32(ny))
        normals.append(Float32(nz))


def _join(mut index: List[Int], a: Int, radial: Int):
    """Append the two triangles of every cell between the ring that starts
    at vertex `a` and the next."""
    var b = a + radial
    for j in range(radial):  # pragma: no branch
        var next = (j + 1) % radial
        index.append(a + j)
        index.append(b + next)
        index.append(b + j)
        index.append(a + j)
        index.append(a + next)
        index.append(b + next)


struct TreeGenerator(Movable):
    """Grows a tree skeleton from its parameters, three.js's
    `TreeGenerator`.

    three.js sets each parameter with a fluent `set<Param>` method. Here
    the parameters are a field: set `generator.parameters.seed` and build
    again. Every build starts from the seed, so it gives a fresh geometry
    the caller owns.
    """

    var parameters: TreeParameters

    def __init__(out self):
        """Create a generator with three.js's default tree."""
        self.parameters = TreeParameters()

    def __init__(out self, var parameters: TreeParameters):
        """Create a generator with given parameters.

        Args:
            parameters: The tree.
        """
        self.parameters = parameters^

    def tubes(self) raises -> List[TreeTube]:
        """Return the skeleton: every branch as a tube of rings, the trunk
        first and each branch before its children.

        Returns:
            The tubes.

        Raises:
            Error: If the parameters are refused; see
                `TreeParameters.check`.
        """
        self.parameters.check()
        var random = generator_random(self.parameters.seed)
        var tubes = List[TreeTube]()
        _grow(
            tubes,
            Vec3d(0, 0, 0),
            Vec3d(0, 1, 0),
            meters(self.parameters.trunk_length),
            meters(self.parameters.trunk_radius),
            0,
            self.parameters,
            random,
        )
        return tubes^

    def build(self) raises -> BufferGeometry:
        """Grow the tree and bake it into one geometry, three.js's
        `build`.

        three.js returns a mesh named `Tree` with a bark material. The
        material is not ported, so this returns the geometry: `position`
        and `normal` attributes and an index.

        Returns:
            The geometry.

        Raises:
            Error: If the parameters are refused; see
                `TreeParameters.check`.
        """
        return _bake(self.tubes())
