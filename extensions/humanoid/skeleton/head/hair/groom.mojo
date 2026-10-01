# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A groom: the scalp's hair as strands, grown from guides.

Real hair is strands. A groom here is built the way grooming tools build
one:

- Guide strands grow from roots on the scalp's hair. Each lies along the
  hair, a little above it, combed away from the crown's whorl and pulled
  down as the hair grows longer. A guide at the front falls onto the
  forehead as a fringe and ends at a ragged line above the brows. Any
  other guide ends at its own length, or where the hair it lies on turns
  under at the hairline.
- Follow strands fill in round each guide, as AMD's TressFX makes them:
  each keeps an offset from its guide, carried along the guide in the
  guide's own frame, and the offset widens toward the tips.
- Clumping pulls followers back toward their guide toward the tips, as
  Blender's Clump Hair Curves does, so the hair gathers into locks.
- Frizz moves each strand a little, most at its tip, as Blender's Frizz
  Hair Curves does.

The follow strands port `TressFXAsset::GenerateFollowHairs` from AMD
TressFX 4.1, MIT license, copyright 2020 Advanced Micro Devices. See
THIRD-PARTY-NOTICES.md.

This is not a three.js port. See Extensions.

    var groom = groom_hair(dims, GroomSpec(dims))
    var strands = groom_lines(groom)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from extensions.humanoid.genome import HAIR_CURL, HAIR_LENGTH
from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.field import DistanceField, smin
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.head.hair.dimensions import (
    SCALP_HAIR,
    HairShape,
)
from extensions.humanoid.skeleton.head.hair.styles import (
    BUN,
    GROWN,
    LAYERED,
    LONG,
    MOHAWK,
    PONYTAIL,
    HairStyle,
    HairStyleFile,
    hair_style_path,
)
from extensions.humanoid.skeleton.head.hair.collider import (
    FAR_AWAY,
    HairCollider,
)
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.surface_nets import surface_gradient
from extensions.humanoid.skeleton.torso.body import BodySkinField
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from std.math import acos, cos, max, min, pi, pow, sin, sqrt

# The most guides one groom has.
comptime MAX_GUIDES = 20000
# The most followers one guide has.
comptime MAX_FOLLOWERS = 64
# How many roots are tried for each guide before it is given up.
comptime ROOT_TRIES = 8
# How many points a guide takes over one turn of its curl.
comptime CURL_POINTS = Float32(8)
# The designed styles, in template centimeters: the middle of the
# cranium's height; where a ponytail and a bun are tied; how wide a
# ponytail fans and how big a bun is; and the height below which long
# hair leaves the scalp and hangs. How far a part pushes the hair to
# each side, against how far it falls, and the most steps a guide takes
# over the scalp.
comptime CRANIUM_CENTER_Y = Float32(75.1)
comptime TAIL_TIE_Y = Float32(75.5)
comptime TAIL_TIE_Z = Float32(-11.5)
comptime BUN_TIE_Y = Float32(83.0)
comptime BUN_TIE_Z = Float32(-6.5)
comptime TAIL_SPREAD = Float32(2.0)
comptime BUN_RADIUS = Float32(3.2)
comptime LONG_HANGS_Y = Float32(70.0)
comptime PART_SPREAD = Float32(0.9)
comptime MAX_STEPS = 60
# How far a tied strand's path over the scalp is arched up at its middle,
# in the cranium's radius.
comptime ARC_RISE = Float32(0.3)
# How far down the back the body hair falls against is baked, in
# template centimeters above the hip joint centers.
comptime BODY_FROM_Y = Float32(22.0)
# Where the body's grid gives way to the head's: in full below the neck,
# not at all above the chin, in template centimeters.
comptime BODY_NECK_Y = Float32(56.0)
comptime BODY_CHIN_Y = Float32(60.0)
# How long long hair and a ponytail's strands are, from root to tip, in
# template centimeters.
comptime LONG_SHORTEST = Float32(34.0)
comptime LONG_LONGEST = Float32(50.0)
comptime TAIL_SHORTEST = Float32(20.0)
comptime TAIL_LONGEST = Float32(32.0)
# How many Newton steps lift a laid strand's point out of the skin.
comptime LIFT_STEPS = 6


def _unit(key: Int, salt: Int) -> Float32:
    """Return a value in 0 through 1 hashed from a key and a salt."""
    var h = UInt32(key) * 374761393 + UInt32(salt) * 668265263
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return Float32(h & 0xFFFFFF) / Float32(0x1000000)


def _signed(key: Int, salt: Int) -> Float32:
    """Return a value in -1 through 1 hashed from a key and a salt."""
    return 2 * _unit(key, salt) - 1


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of `a` and `b`."""
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _unit_vector(v: Vector3, fallback: Vector3) -> Vector3:
    """Return `v` made unit, or `fallback` where it has no length."""
    var n = v.length()
    if n < Float32(1e-9):
        return fallback
    return v / n


struct GroomField(Copyable, DistanceField, Movable):
    """The surface a groom's strands lie on: the scalp's hair, joined to
    the skin a little above it, so a fringe can fall off the hair onto
    the forehead."""

    var hair: HairShape
    var gap: Float32
    var blend: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: HeadMuscleDimensions, style: HairStyle = GROWN
    ) raises:
        """Shape the surface for one head.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.
            style: How the hair is cut, which shapes the hair under the
                strands; `GROWN` by default.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or `style`
                is not named.
        """
        self.hair = HairShape(dimensions, SCALP_HAIR, RIGHT, style)
        self.gap = dimensions.head.cm(0.15)
        self.blend = dimensions.head.cm(0.3)
        self.low = self.hair.skin.low
        self.high = self.hair.skin.high

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the hair or the skin."""
        return smin(
            self.hair.distance(point),
            self.hair.skin.distance(point) - self.gap,
            self.blend,
        )

    def on_hair(self, point: Vector3) -> Bool:
        """Return True where the hair, not the skin, is the surface."""
        return (
            self.hair.distance(point)
            < self.hair.skin.distance(point) - self.gap
        )


struct HairBody(Copyable, DistanceField, Movable):
    """What hair falls against: the head's skin, and the body's below the
    neck, from the crown down to the middle of the back, baked.

    The body's own field joins the neck, the shoulders and the arms as
    the body's mesh draws them, so hair that falls past the neck lies on
    the skin that shows. Both fields are far too slow to read for every
    point, so each is baked into a grid; the head's is baked finer, over
    its own box, since hair lies on it closest. Above the chin only the
    head counts: the body's coarser grid would ripple the hair laid on
    the scalp.
    """

    var head: HairCollider
    var body: HairCollider
    # Below `neck` the body counts in full; above `chin`, not at all.
    var neck: Float32
    var chin: Float32

    def __init__(out self, dimensions: HeadMuscleDimensions) raises:
        """Fit and bake the head's and the body's skin for one person.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.

        Raises:
            Error: If the person the dimensions were made for is refused.
        """
        var h = dimensions.head.copy()
        var skin = HeadSkinField(dimensions)
        var margin = Vector3(h.cm(5.0), h.cm(2.0), h.cm(5.0))
        self.head = HairCollider(skin, skin.low - margin, skin.high + margin)
        self.body = _body_grid(dimensions)
        self.neck = h.at(0, BODY_NECK_Y, 0).y
        self.chin = h.at(0, BODY_CHIN_Y, 0).y

    def joined(self, head: Float32, point: Vector3) -> Float32:
        """Return the distance to the body, given the head's at `point`.

        The body's baked distance is pushed away above the neck, all the
        way by the chin, so the head's alone counts there.

        Args:
            head: How far `point` lies outside the head's skin.
            point: Where, in the pelvis frame, in meters.

        Returns:
            The nearer of the head and the body, in meters.
        """
        return min(
            head,
            _pushed(self.body.distance(point), point.y, self.neck, self.chin),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the body, in meters."""
        return self.joined(self.head.distance(point), point)


def _body_grid(dimensions: HeadMuscleDimensions) raises -> HairCollider:
    """Return the body's skin baked from the middle of the back up."""
    var h = dimensions.head.copy()
    var field = BodySkinField(
        HumanoidSpec(h.stature, h.sex, dimensions.athleticism, h.torso.genome)
    )
    return HairCollider(
        field,
        Vector3(field.low.x, h.at(0, BODY_FROM_Y, 0).y, field.low.z),
        Vector3(field.high.x, field.high.y + h.cm(2.0), field.high.z),
    )


def _pushed(body: Float32, y: Float32, neck: Float32, chin: Float32) -> Float32:
    """Return the body's distance pushed away above `neck`, all the way
    by `chin`."""
    var t = min(Float32(1), max(Float32(0), (y - neck) / (chin - neck)))
    return body + t * FAR_AWAY


@fieldwise_init
struct _Lift(Copyable, DistanceField, Movable):
    """The body's grid with the head's own skin, not its grid: what a
    designed strand is lifted out of, once, as it is groomed."""

    var skin: HeadSkinField
    var body: HairCollider
    var neck: Float32
    var chin: Float32

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the body, in meters."""
        return min(
            self.skin.distance(point),
            _pushed(self.body.distance(point), point.y, self.neck, self.chin),
        )


struct GroomSpec(ImplicitlyCopyable):
    """How a groom is grown: how many strands, how long, and how they
    gather."""

    var guides: Int
    var followers: Int
    # How far a guide's step is, and how far above the hair it lies.
    var step: Float32
    var lift: Float32
    # How far a strand's tip stands off the hair under it.
    var rise: Float32
    var shortest: Float32
    var longest: Float32
    # TressFX's follow strands: how far a root lies from its guide's, and
    # how much wider the offset is at the tip than at the root.
    var radius: Float32
    var tip_spread: Float32
    # How strongly a follower is pulled back to its guide at the tip.
    var clump: Float32
    # How far a tip wanders, and how far the comb sways a guide.
    var frizz: Float32
    var sway: Float32
    var wavelength: Float32
    # The fringe: how far below the hairline it may fall, and the height
    # of the line it is cut at, above the brows.
    var fringe: Float32
    var fringe_line: Float32
    var fringe_ragged: Float32
    # How many roots are tried for each guide before it is given up.
    var root_tries: Int
    # The curl, from `HAIR_CURL`: how far a strand swings off its line,
    # and how long one turn of it is. No swing is straight hair.
    var curl: Float32
    var curl_length: Float32

    def __init__(
        out self,
        dimensions: HeadMuscleDimensions,
        guides: Int = 1500,
        followers: Int = 6,
    ) raises:
        """Size a groom for a head and its `HAIR_LENGTH`.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.
            guides: How many guide strands, one through 20000.
            followers: How many follow strands round each guide, zero
                through 64.

        Raises:
            Error: If a count is out of range or the genome is not valid.
        """
        if guides < 1 or guides > MAX_GUIDES:
            raise Error("A groom's guides number one through 20000")
        if followers < 0 or followers > MAX_FOLLOWERS:
            raise Error("A guide's followers number zero through 64")
        var h = dimensions.head.copy()
        var length = h.torso.genome.get(HAIR_LENGTH)
        var grow = max(Float32(0), length)
        var crop = 1 + Float32(0.6) * min(Float32(0), length)
        self.guides = guides
        self.followers = followers
        self.step = h.cm(0.9)
        self.lift = h.cm(0.25)
        self.rise = h.cm(0.2) + h.cm(0.5) * grow
        self.shortest = h.cm(3.0) * crop
        self.longest = (h.cm(7.0) + h.cm(16.0) * grow) * crop
        self.radius = h.cm(0.3)
        self.tip_spread = Float32(1.5)
        self.clump = Float32(0.7)
        self.frizz = h.cm(0.12)
        self.sway = Float32(0.25)
        self.wavelength = h.cm(2.5)
        # A crop has no fringe: the hair is too short to fall.
        self.fringe = (
            h.cm(1.0) * (1 + min(Float32(0), length)) + h.cm(4.0) * grow
        )
        self.fringe_line = h.at(0, 75.4 + 2.0 * (1 - grow), 0).y
        self.fringe_ragged = h.cm(0.9)
        self.root_tries = ROOT_TRIES
        # A wave swings wide over a long turn; a coil tightly over a
        # short one, and stands the hair up off the head.
        var coil = max(Float32(0), h.torso.genome.get(HAIR_CURL))
        self.curl = h.cm(0.9) * pow(coil, Float32(0.8)) * (1 - coil / 2)
        self.curl_length = h.cm(5.0) * (1 - Float32(0.75) * coil)
        self.rise += h.cm(1.5) * coil * coil


struct HairGroom(Movable, Sized):
    """Strands, each a run of points from its root to its tip."""

    var points: List[Vector3]
    # The hair's outward unit normal under each point.
    var normals: List[Vector3]
    # How far each point lies under the groom's outer surface, in
    # meters: light is lost on its way down to it.
    var depths: List[Float32]
    # The index of each strand's first point, and one past the last.
    var starts: List[Int]
    # Each strand's brightness, near one.
    var shades: List[Float32]

    def __init__(out self):
        """Start an empty groom."""
        self.points = List[Vector3]()
        self.normals = List[Vector3]()
        self.depths = List[Float32]()
        self.starts = [0]
        self.shades = List[Float32]()

    def __len__(self) -> Int:
        """Return how many strands the groom holds."""
        return len(self.starts) - 1

    def add(
        mut self,
        points: List[Vector3],
        normals: List[Vector3],
        depths: List[Float32],
        shade: Float32,
    ):
        """Append one strand.

        Args:
            points: Its points, root first.
            normals: The hair's normal under each point.
            depths: How deep under the groom's outer surface each lies.
            shade: Its brightness.
        """
        for index in range(len(points)):  # pragma: no branch
            self.points.append(points[index])
            self.normals.append(normals[index])
            self.depths.append(depths[index])
        self.starts.append(len(self.points))
        self.shades.append(shade)

    def tangent(self, index: Int) -> Vector3:
        """Return the unit direction along its strand at point `index`.

        Args:
            index: A point of the groom.

        Returns:
            The direction from the point before to the point after.
        """
        var strand = _strand_of(self.starts, index)
        var first = self.starts[strand]
        var last = self.starts[strand + 1] - 1
        var d = (
            self.points[min(index + 1, last)]
            - self.points[max(index - 1, first)]
        )
        return _unit_vector(d, Vector3(0, -1, 0))


def _strand_of(starts: List[Int], index: Int) -> Int:
    """Return which strand holds point `index`, by bisection."""
    var lo = 0
    var hi = len(starts) - 2
    while lo < hi:
        var mid = (lo + hi + 1) // 2
        if starts[mid] <= index:
            lo = mid
        else:
            hi = mid - 1
    return lo


def _onto(
    field: GroomField, start: Vector3, level: Float32, probe: Float32
) -> Vector3:
    """Return `start` walked onto the level `level` of `field`."""
    var p = start
    for _ in range(3):  # pragma: no branch
        var g = surface_gradient(field, p, probe)
        var g2 = max(g.dot(g), Float32(1e-12))
        p = p - g * ((field.distance(p) - level) / g2)
    return p


def _normal(field: GroomField, point: Vector3, probe: Float32) -> Vector3:
    """Return the field's outward unit normal at `point`."""
    return _unit_vector(surface_gradient(field, point, probe), Vector3(0, 1, 0))


def _root(
    field: GroomField,
    center: Vector3,
    key: Int,
    level: Float32,
    probe: Float32,
    tries: Int,
) -> Tuple[Bool, Vector3]:
    """Return a root on the hair for one guide, and whether one was found.

    Each try takes a direction from the cranium's center, walks in from
    outside to the level, and keeps the point only where the hair covers
    the skin there.
    """
    for attempt in range(tries):
        var salt = attempt * 7 + 11
        var turn = Float32(2 * pi) * _unit(key, salt)
        var up = Float32(-0.35) + Float32(1.35) * _unit(key, salt + 1)
        var flat = sqrt(max(Float32(0), 1 - up * up))
        var ray = Vector3(flat * cos(turn), up, flat * sin(turn))
        var p = center + ray * Float32(0.25)
        for _ in range(120):  # pragma: no branch
            var d = field.distance(p) - level
            if d < probe:
                break
            p = p - ray * max(d, probe * 2)
        p = _onto(field, p, level, probe)
        if field.on_hair(p):
            return (True, p)
    return (False, center)


struct _Comb(ImplicitlyCopyable):
    """How the hair is combed: away from the whorl, and down."""

    var whorl: Vector3
    var gravity: Float32
    var sway: Float32
    var wavelength: Float32

    def __init__(
        out self,
        whorl: Vector3,
        gravity: Float32,
        sway: Float32,
        wavelength: Float32,
    ):
        """Keep the comb's parameters."""
        self.whorl = whorl
        self.gravity = gravity
        self.sway = sway
        self.wavelength = wavelength

    def direction(
        self,
        point: Vector3,
        normal: Vector3,
        travelled: Float32,
        phase: Float32,
    ) -> Vector3:
        """Return the unit direction a strand grows in at `point`, or zero
        where the comb stands straight off the hair."""
        var away = _unit_vector(point - self.whorl, Vector3(0, -1, 0))
        var d = away + Vector3(0, -self.gravity, 0)
        var t = d - normal * normal.dot(d)
        var n = t.length()
        if n < Float32(1e-5):
            return Vector3(0, 0, 0)
        t = t / n
        var across = _cross(normal, t)
        var sway = self.sway * sin(phase + travelled / self.wavelength)
        return _unit_vector(t + across * sway, t)


def _stride_ok(moved: Float32, step: Float32) -> Bool:
    """Return True if a step moved about as far as it was meant to.

    A step that went nowhere found no way along the hair; one that went
    twice as far jumped across a gap to some other surface.
    """
    return moved >= step * Float32(0.2) and moved <= step * 2


def _fringe_continues(
    fringe: Bool, off_hair: Float32, limit: Float32, y: Float32, cut: Float32
) -> Bool:
    """Return True if a strand that has left the hair may go on over the
    skin: only a fringe's, not yet past its reach, and above its cut."""
    return fringe and off_hair <= limit and y >= cut


def _grow_guide(
    field: GroomField,
    spec: GroomSpec,
    comb: _Comb,
    root: Vector3,
    level: Float32,
    key: Int,
    front: Float32,
    probe: Float32,
    mut points: List[Vector3],
    mut normals: List[Vector3],
    mut levels: List[Float32],
):
    """Grow one guide from `root` along the comb, on the field's level."""
    var target = spec.shortest + (spec.longest - spec.shortest) * _unit(key, 2)
    var phase = Float32(2 * pi) * _unit(key, 3)
    # A root at the front of the scalp may fall past the hair's edge
    # onto the forehead, down to the fringe's ragged line.
    var fringe = root.z > front
    var cut = spec.fringe_line + spec.fringe_ragged * _signed(key, 5)
    var p = root
    var n = _normal(field, p, probe)
    points.append(p)
    normals.append(n)
    levels.append(level)
    var travelled = Float32(0)
    var off_hair = Float32(0)
    while travelled < target:
        # Where the comb stands straight off the hair, it gives no
        # direction, the step goes nowhere, and the stride stops it.
        var t = comb.direction(p, n, travelled, phase)
        var along = min(Float32(1), travelled / target)
        var lift = level + spec.rise * along * sqrt(along)
        var q = _onto(field, p + t * spec.step, lift, probe)
        var moved = (q - p).length()
        if not _stride_ok(moved, spec.step):
            break
        if not field.on_hair(q):
            off_hair += moved
            if not _fringe_continues(fringe, off_hair, spec.fringe, q.y, cut):
                break
        p = q
        n = _normal(field, p, probe)
        travelled += moved
        points.append(p)
        normals.append(n)
        levels.append(lift)


def groom_hair(
    dimensions: HeadMuscleDimensions,
    spec: GroomSpec,
    seed: Int = 1,
    style: HairStyle = GROWN,
) raises -> HairGroom:
    """Grow the scalp's hair as strands, or lay an artist's style.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        spec: How many strands, how long, and how they gather. An
            artist's style keeps its own lengths and lay.
        seed: Picks the roots, the lengths and the sway.
        style: `GROWN` by default; see `HairStyle`.

    Returns:
        Every guide, each followed by its followers.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `style` is
            not named or its file cannot be read, or if no guide finds a
            root.
    """
    if not style.is_valid():
        raise Error("A hair style must be a named style")
    if style == LAYERED or style == MOHAWK:
        return _laid(dimensions, spec, seed, style)
    if style != GROWN:
        return _designed(dimensions, spec, seed, style)
    var field = GroomField(dimensions)
    var h = dimensions.head.copy()
    var length = h.torso.genome.get(HAIR_LENGTH)
    var comb = _Comb(
        h.at(0, 83.0, -5.0),
        Float32(0.25) + Float32(1.5) * max(Float32(0), length),
        spec.sway,
        spec.wavelength,
    )
    var center = h.at(0, 76.0, -1.0)
    var front = h.at(0, 0, 5.0).z
    var probe = h.cm(0.08)
    var top = spec.lift + spec.rise
    var groom = HairGroom()
    for guide in range(spec.guides):  # pragma: no branch
        var key = seed * 100003 + guide
        var level = spec.lift * (Float32(0.1) + Float32(0.9) * _unit(key, 1))
        var found = _root(field, center, key, level, probe, spec.root_tries)
        if not found[0]:
            continue
        var points = List[Vector3]()
        var normals = List[Vector3]()
        var levels = List[Float32]()
        _grow_guide(
            field,
            spec,
            comb,
            found[1],
            level,
            key,
            front,
            probe,
            points,
            normals,
            levels,
        )
        if len(points) < 3:
            continue
        var depths = List[Float32]()
        for index in range(len(levels)):  # pragma: no branch
            depths.append(max(Float32(0), top - levels[index]))
        _curl(points, normals, depths, spec, key)
        groom.add(points, normals, depths, _shade(key, 0))
        for follower in range(spec.followers):  # pragma: no branch
            _follow(groom, spec, points, normals, depths, key, follower + 1)
    if len(groom) == 0:
        raise Error("No guide found a root on the scalp's hair")
    return groom^


def _laid(
    dimensions: HeadMuscleDimensions,
    spec: GroomSpec,
    seed: Int,
    style: HairStyle,
) raises -> HairGroom:
    """Lay an artist's style on the head: its strands, spread evenly
    over as many guides as `spec` asks for."""
    var file = HairStyleFile(hair_style_path(style))
    var field = GroomField(dimensions)
    var h = dimensions.head.copy()
    var guides = min(spec.guides, file.count)
    var groom = HairGroom()
    for guide in range(guides):  # pragma: no branch
        var strand = file.strand(h, guide * file.count // guides)
        _finish(
            groom,
            strand,
            field,
            field.hair.skin,
            spec,
            h.cm(0.08),
            seed * 100003 + guide,
            True,
        )
    return groom^


def _finish[
    F: DistanceField
](
    mut groom: HairGroom,
    strand: List[Vector3],
    field: GroomField,
    body: F,
    spec: GroomSpec,
    probe: Float32,
    key: Int,
    snap: Bool,
    taut: Float32 = 0,
):
    """Curl a laid or designed strand, keep it off the skin, and add it
    and its followers to the groom.

    A laid strand was not grown on this head's skin: with `snap` its root
    is walked onto the skin, and the strand goes with it. Any point that
    would pass under `body` is lifted back out, a little at a time. Its
    first `taut` meters are pulled straight, and do not curl.
    """
    ref skin = field.hair.skin
    var top = spec.lift + spec.rise
    var root = strand[0]
    if snap:
        for _ in range(4):  # pragma: no branch
            var g = surface_gradient(skin, root, probe)
            root = root - g * (skin.distance(root) / max(g.dot(g), 1e-12))
    var shift = root - strand[0]
    var points = List[Vector3]()
    var normals = List[Vector3]()
    var depths = List[Float32]()
    for k in range(len(strand)):  # pragma: no branch
        var p = strand[k] + shift
        points.append(p)
        normals.append(
            _unit_vector(surface_gradient(skin, p, probe), Vector3(0, 1, 0))
        )
        depths.append(0)
    _curl(points, normals, depths, spec, key, taut)
    for k in range(len(points)):  # pragma: no branch
        var p = points[k]
        var d = body.distance(p)
        if k > 0:
            for _ in range(LIFT_STEPS):  # pragma: no branch
                if d >= spec.lift:
                    break
                var g = surface_gradient(body, p, probe)
                var move = g * ((spec.lift - d) / max(g.dot(g), 1e-12))
                if move.length() > spec.step:
                    move = move * (spec.step / move.length())
                p = p + move
                d = body.distance(p)
            normals[k] = _unit_vector(
                surface_gradient(body, p, probe), Vector3(0, 1, 0)
            )
        points[k] = p
        depths[k] = max(Float32(0), top - d)
    groom.add(points, normals, depths, _shade(key, 0))
    for follower in range(spec.followers):  # pragma: no branch
        _follow(groom, spec, points, normals, depths, key, follower + 1)


def _designed(
    dimensions: HeadMuscleDimensions,
    spec: GroomSpec,
    seed: Int,
    style: HairStyle,
) raises -> HairGroom:
    """Design a long, a ponytail or a bun style on the head.

    Each guide grows from a root on the scalp's hair. It is combed over
    the skin, away from a part down the middle of the crown for `LONG`,
    or toward the tie at the back of the head for `PONYTAIL` and `BUN`.
    Long hair then hangs past the scalp to its length; a ponytail's tail
    springs back from the tie and falls; a bun's coils round a ball on
    the tie.
    """
    var field = GroomField(dimensions, style)
    var h = dimensions.head.copy()
    var body = _Lift(
        field.hair.skin.copy(),
        _body_grid(dimensions),
        h.at(0, BODY_NECK_Y, 0).y,
        h.at(0, BODY_CHIN_Y, 0).y,
    )
    var probe = h.cm(0.08)
    var center = h.at(0, 76.0, -1.0)
    var cranium = h.at(0, CRANIUM_CENTER_Y, -1.0)
    var tie = h.at(0, TAIL_TIE_Y, TAIL_TIE_Z)
    if style == BUN:
        tie = h.at(0, BUN_TIE_Y, BUN_TIE_Z)
    # The tie lies on the hair, out from the cranium's middle.
    tie = _onto(field, tie, spec.lift, probe)
    var away = _unit_vector(tie - cranium, Vector3(0, 0, -1))
    var groom = HairGroom()
    for guide in range(spec.guides):  # pragma: no branch
        var key = seed * 100003 + guide
        var found = _root(field, center, key, spec.lift, probe, spec.root_tries)
        if not found[0]:
            continue
        var strand = List[Vector3]()
        var p = found[1]
        strand.append(p)
        var travelled = Float32(0)
        var target = h.cm(LONG_SHORTEST) + h.cm(
            LONG_LONGEST - LONG_SHORTEST
        ) * _unit(key, 2)
        if style == PONYTAIL:
            target = h.cm(TAIL_SHORTEST) + h.cm(
                TAIL_LONGEST - TAIL_SHORTEST
            ) * _unit(key, 2)
        if style == LONG:
            # Over the scalp, away from the part and down.
            for _ in range(MAX_STEPS):  # pragma: no branch
                if p.y < h.at(0, LONG_HANGS_Y, 0).y:
                    break
                var n = _normal(field, p, probe)
                var side = Float32(1) if p.x >= 0 else Float32(-1)
                var want = Vector3(side * PART_SPREAD, -1, -Float32(0.15))
                var t = want - n * n.dot(want)
                var q = _onto(
                    field, p + _unit_vector(t, t) * spec.step, spec.lift, probe
                )
                travelled += (q - p).length()
                p = q
                strand.append(p)
        else:
            travelled = _arc(field, strand, cranium, tie, spec, probe)
        if style == LONG:
            _hang(strand, target - travelled, spec.step, key)
        elif style == PONYTAIL:
            _tail(strand, tie, away, target, spec.step, h.cm(TAIL_SPREAD), key)
        else:
            _coil(strand, tie, away, h.cm(BUN_RADIUS), spec.step, key)
        # Hair gathered to a tie is pulled straight over the scalp.
        var taut = travelled if style.is_tied() else Float32(0)
        _finish(groom, strand, field, body, spec, probe, key, False, taut)
    if len(groom) == 0:
        raise Error("No guide found a root on the scalp's hair")
    return groom^


def _arc(
    field: GroomField,
    mut strand: List[Vector3],
    middle: Vector3,
    tie: Vector3,
    spec: GroomSpec,
    probe: Float32,
) -> Float32:
    """Comb a strand from its root to the tie over the scalp, and return
    how far it went.

    The strand follows the arc from its root to the tie round the
    cranium's middle, so it goes up over the crown from the brow and back
    over the ear from the temple, as a comb pulls it; each point is laid
    on the hair. The arc is arched up a little in its middle, so the hair
    from the temple clears the ear.
    """
    var p = strand[len(strand) - 1]
    var a = p - middle
    var b = tie - middle
    var ra = a.length()
    var rb = b.length()
    var ua = a / ra
    var ub = b / rb
    var angle = acos(min(Float32(1), max(Float32(-1), ua.dot(ub))))
    var sine = max(sin(angle), Float32(1e-6))
    var count = max(1, Int(angle * (ra + rb) / 2 / spec.step))
    var travelled = Float32(0)
    for i in range(1, count + 1):  # pragma: no branch
        var t = Float32(i) / Float32(count)
        var d = _unit_vector(
            ua * (sin((1 - t) * angle) / sine)
            + ub * (sin(t * angle) / sine)
            + Vector3(0, ARC_RISE * sin(Float32(pi) * t), 0),
            ub,
        )
        var q = _onto(
            field, middle + d * (ra + (rb - ra) * t), spec.lift, probe
        )
        travelled += (q - p).length()
        p = q
        strand.append(q)
    return travelled


def _hang(mut strand: List[Vector3], length: Float32, step: Float32, key: Int):
    """Let a strand fall `length` further, bending down from the way it
    was going, and swaying a little out of line with its neighbors."""
    var last = len(strand) - 1
    # The way the strand was going over the scalp, or down from a root
    # that did not move.
    var going = _unit_vector(
        strand[last] - strand[max(0, last - 1)], Vector3(0, -1, 0)
    )
    var drift = Vector3(_signed(key, 41), 0, _signed(key, 43)) * Float32(0.08)
    var left = length
    var p = strand[last]
    while left > 0:
        going = _unit_vector(
            going * Float32(0.6) + Vector3(0, -1, 0) + drift, going
        )
        p = p + going * step
        strand.append(p)
        left -= step


def _tail(
    mut strand: List[Vector3],
    tie: Vector3,
    away: Vector3,
    length: Float32,
    step: Float32,
    spread: Float32,
    key: Int,
):
    """Gather a strand into the tie and let it fall as part of the
    ponytail: out from the head at first, then down, fanning a little
    wider toward its tip."""
    var angle = Float32(2 * pi) * _unit(key, 51)
    var across = _unit_vector(_cross(away, Vector3(0, 1, 0)), Vector3(1, 0, 0))
    var up = _cross(across, away)
    var fan = _unit(key, 53)
    var along = Float32(0)
    var core = tie
    var going = away
    while along < length:
        going = _unit_vector(
            going * Float32(0.85) + Vector3(0, -0.35, 0), going
        )
        core = core + going * step
        along += step
        var r = spread * sqrt(fan) * (Float32(0.3) + along / length)
        strand.append(core + (across * cos(angle) + up * sin(angle)) * r)


def _coil(
    mut strand: List[Vector3],
    tie: Vector3,
    away: Vector3,
    radius: Float32,
    step: Float32,
    key: Int,
):
    """Wind a strand round the ball of a bun that sits on the tie."""
    var middle = tie + away * radius
    var across = _unit_vector(_cross(away, Vector3(0, 1, 0)), Vector3(1, 0, 0))
    var up = _cross(across, away)
    var lean = Float32(-0.9) + Float32(1.8) * _unit(key, 61)
    var start = Float32(2 * pi) * _unit(key, 63)
    var turns = Float32(1.2) + _unit(key, 65)
    var count = Int(turns * Float32(2 * pi) * radius / step) + 1
    for k in range(count):  # pragma: no branch
        var a = start + Float32(2 * pi) * turns * Float32(k) / Float32(count)
        var c = sqrt(max(Float32(0), 1 - lean * lean))
        # Round the ball: a circle tipped by `lean` out of the plane square
        # to the head.
        var ring = (across * cos(a) + up * sin(a)) * c + away * lean
        strand.append(middle + ring * radius)


def _curl(
    mut points: List[Vector3],
    mut normals: List[Vector3],
    mut depths: List[Float32],
    spec: GroomSpec,
    key: Int,
    taut: Float32 = 0,
):
    """Wind a guide into its curl, if its hair curls.

    The guide is first resampled finely enough to hold its turns, eight
    points a turn. Each point then swings about the guide's line, across
    the hair and out off it, never in under it, by the curl's swing. The
    swing grows in over the first half turn past the first `taut` meters,
    so the root, and hair pulled to a tie, stay where they lie.
    """
    if spec.curl <= 0:
        return
    var spacing = spec.curl_length / CURL_POINTS
    var along = List[Float32](capacity=len(points))
    along.append(0)
    for k in range(1, len(points)):  # pragma: no branch
        along.append(along[k - 1] + (points[k] - points[k - 1]).length())
    var total = along[len(along) - 1]
    var count = max(len(points), Int(total / spacing) + 1)
    var phase = Float32(2 * pi) * _unit(key, 31)
    var fine = List[Vector3](capacity=count)
    var ups = List[Vector3](capacity=count)
    var deep = List[Float32](capacity=count)
    var j = 0
    for i in range(count):  # pragma: no branch
        var s = total * Float32(i) / Float32(count - 1)
        while j < len(points) - 2 and along[j + 1] < s:
            j += 1
        var span = max(along[j + 1] - along[j], Float32(1e-9))
        var t = min(Float32(1), max(Float32(0), (s - along[j]) / span))
        var p = points[j] + (points[j + 1] - points[j]) * t
        var tangent = _unit_vector(points[j + 1] - points[j], Vector3(0, -1, 0))
        var n = normals[j]
        var outward = _unit_vector(n - tangent * n.dot(tangent), n)
        var across = _cross(outward, tangent)
        var angle = phase + Float32(2 * pi) * s / spec.curl_length
        var swing = spec.curl * min(
            Float32(1), max(Float32(0), 2 * (s - taut) / spec.curl_length)
        )
        fine.append(
            p
            + across * (swing * cos(angle))
            + outward * (swing * Float32(0.5) * (1 + sin(angle)))
        )
        ups.append(n)
        deep.append(depths[j] + (depths[j + 1] - depths[j]) * t)
    points = fine^
    normals = ups^
    depths = deep^


def _shade(key: Int, follower: Int) -> Float32:
    """Return a strand's brightness, a little either side of one."""
    return Float32(0.85) + Float32(0.3) * _unit(key * 67 + follower, 9)


def _follow(
    mut groom: HairGroom,
    spec: GroomSpec,
    points: List[Vector3],
    normals: List[Vector3],
    depths: List[Float32],
    key: Int,
    follower: Int,
):
    """Append one follower of the guide through `points`.

    TressFX offsets a follower's every point from its guide's by one
    vector in the plane square to the guide's first segment, times one
    plus the tip spread times how far along it is. Here the offset is
    kept in each point's own frame, across the hair and up off it, so a
    follower of a guide that bends over the head bends with it. Toward
    the tip the clump pulls it back to its guide, and frizz moves it.
    """
    var salt = follower * 13
    var a = spec.radius * _signed(key, salt + 1)
    var c = spec.radius * Float32(0.5) * _unit(key, salt + 2)
    var last = len(points) - 1
    var mine = List[Vector3]()
    var ups = List[Vector3]()
    var deep = List[Float32]()
    for k in range(len(points)):  # pragma: no branch
        var s = Float32(k) / Float32(last)
        var ahead = points[min(k + 1, last)] - points[max(k - 1, 0)]
        var n = normals[k]
        var across = _unit_vector(_cross(n, ahead), Vector3(1, 0, 0))
        var spread = (1 + spec.tip_spread * s) * (1 - spec.clump * s * s)
        var frizz = spec.frizz * s * s
        var p = (
            points[k]
            + across * (a * spread + frizz * _signed(key, salt + 3 + k))
            + n
            * (c * spread + frizz * Float32(0.5) * _signed(key, salt + 40 + k))
        )
        mine.append(p)
        ups.append(n)
        deep.append(max(Float32(0), depths[k] - c * spread))
    groom.add(mine, ups, deep, _shade(key, follower))


def groom_lines(groom: HairGroom) raises -> BufferGeometry:
    """Return a groom's strands as segments for a `LineSegments2`.

    Args:
        groom: The strands.

    Returns:
        A geometry whose `position` holds each segment's two ends in
        turn, the layout `line_segments_geometry` makes.

    Raises:
        Error: If the groom has no strands.
    """
    if len(groom) == 0:
        raise Error("A groom with no strands has no lines")
    var positions = List[Float32]()
    for strand in range(len(groom)):  # pragma: no branch
        for index in range(
            groom.starts[strand], groom.starts[strand + 1] - 1
        ):  # pragma: no branch
            for end in range(2):  # pragma: no branch
                var p = groom.points[index + end]
                positions.append(p.x)
                positions.append(p.y)
                positions.append(p.z)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    return geometry^
