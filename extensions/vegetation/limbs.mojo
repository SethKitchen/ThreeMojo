# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Branches that grow toward the light, by space colonization.

A crown is a shape in the air. `CrownShape` says where it is: its bottom
and its top above the ground, its radius where it is widest, and how much
noise carves it into lobes with gaps of sky between them. `grow_limbs`
scatters points in the shape, the places that leaves will reach for, and
grows the tree toward them:

1. The trunk climbs from the ground to `fork` of the way up the crown,
   and on until a point is within `reach` of its top. It leans by `lean`
   and wanders by `bend` as it climbs. A crown's middle is bare, so a
   trunk that stopped at the first point in reach would bend away to
   the crown's lower edge.
2. Each point pulls the node nearest to it, if that node is within
   `reach`.
3. Each node that is pulled grows one new node a `step` away, toward the
   mean of its pulls. `up_pull` bends the growth up, and `droop` bends it
   down the further out from the trunk it is. `gnarl` turns it a little
   at random.
4. A point within `kill` of a node is reached, and pulls no more.
5. The growth stops when no node grows.

Points close together pull one branch. Points apart split it in two. So
the trunk forks where it enters the crown, its limbs fork as they spread,
and the twigs end where the points were. A gap in the points is a gap in
the crown. The method is the space colonization of Runions, Lane and
Prusinkiewicz (2007).

**The thickness** follows the pipe model: a node's radius to the power
`pipe` is the sum of its children's, and each twig tip is `tip_radius`
thick. The trunk flares at its foot by `flare`.

**The wood** is a tube along each chain of nodes. A chain follows the
thickest child at each fork, and each other child starts a chain of its
own. `limb_mesh` leaves out a tube thinner than its `thinnest`: the leaves
hide it.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.noise import hash01, value_noise3
from math.vector3 import Vector3
from std.math import cos, pi, pow, sin, sqrt
from units.si import DEGREE, METER, RADIAN, Angle, Length

# The most rounds of growth. A crown 20 meters across, at a step of 30
# centimeters, needs about 70.
comptime MAX_ROUNDS = 400
# A node does not grow a second child within this cosine of the way an
# earlier child grew: the two would be one branch drawn twice.
comptime TWIN = Float32(0.96)
# How many tries a point has to land in the shape, a point.
comptime TRIES = 40
# The height over which the trunk flares at its foot, in meters.
comptime FOOT = Float32(1.2)
# How deep in the crown's egg a lobe's middle can be, how near another
# lobe's middle, as a fraction of the lobe size, and how far past the egg
# a lobe can bulge.
comptime LOBE_IN = Float32(0.45)
comptime LOBE_OUT = Float32(0.85)
comptime LOBE_APART = Float32(0.9)
comptime LOBE_REACH = Float32(1.35)


@fieldwise_init
struct Lobe(ImplicitlyCopyable):
    """One lobe of a crown: a ball of foliage that one limb fills."""

    var center: Vector3
    # Its radius, in meters.
    var radius: Float32


struct CrownShape(ImplicitlyCopyable):
    """Where a crown is: an egg of two half ellipsoids round its trunk,
    and the lobes of foliage that bulge from it."""

    # The heights of the crown's bottom and top above the ground.
    var bottom: Length
    var top: Length
    # The crown's radius where it is widest.
    var radius: Length
    # Where the crown is widest, as a fraction of its height up from its
    # bottom.
    var widest: Float32
    # How many lobes the crown is made of. Zero fills the whole egg.
    var lobes: Int
    # The mean radius of a lobe.
    var lobe_size: Length
    # How ragged the outline and the lobes are, from zero to one.
    var ragged: Float32
    # The share of the crown's depth, out from its middle, that holds no
    # point: the inside of a large crown is bare wood.
    var hollow: Float32

    def __init__(
        out self,
        bottom: Length = Length(5.0, METER),
        top: Length = Length(14.0, METER),
        radius: Length = Length(5.0, METER),
        widest: Float32 = 0.55,
        lobes: Int = 9,
        lobe_size: Length = Length(2.0, METER),
        ragged: Float32 = 0.4,
        hollow: Float32 = 0.2,
    ):
        """Create a crown shape.

        Args:
            bottom: The height of the crown's bottom above the ground.
            top: The height of its top.
            radius: Its radius where it is widest.
            widest: Where it is widest, as a fraction of its height.
            lobes: How many lobes it is made of. Zero fills the egg.
            lobe_size: The mean radius of a lobe.
            ragged: How ragged the outline and the lobes are, from zero
                to one.
            hollow: The share of its depth, out from its middle, that
                holds no point.
        """
        self.bottom = bottom
        self.top = top
        self.radius = radius
        self.widest = widest
        self.lobes = lobes
        self.lobe_size = lobe_size
        self.ragged = ragged
        self.hollow = hollow

    def check(self) raises:
        """Refuse a shape that cannot hold a crown.

        Raises:
            Error: If the bottom is not from 0 to 100 meters up, the top
                is not from 10 centimeters above the bottom to 200
                meters, the radius is not from 5 centimeters to 50
                meters, the widest point is not from 0.05 to 0.95 of the
                height, there are not from 0 to 64 lobes, a lobe is not
                from 10 centimeters to 50 meters, the raggedness is not
                from 0 to 1, or the hollow is not from 0 to 0.9.
        """
        require_between(
            self.bottom.to(METER),
            0,
            100,
            "A crown's bottom must be from 0 to 100 meters up",
        )
        require_between(
            self.top.to(METER),
            self.bottom.to(METER) + 0.1,
            200,
            (
                "A crown's top must be from 10 centimeters above its bottom to"
                " 200 meters"
            ),
        )
        require_between(
            self.radius.to(METER),
            0.05,
            50,
            "A crown's radius must be from 5 centimeters to 50 meters",
        )
        require_between(
            self.widest,
            0.05,
            0.95,
            "A crown must be widest from 0.05 to 0.95 of its height",
        )
        require_count_between(
            self.lobes, 0, 64, "A crown must have from 0 to 64 lobes"
        )
        require_between(
            self.lobe_size.to(METER),
            0.1,
            50,
            "A crown's lobe must be from 10 centimeters to 50 meters",
        )
        require_between(
            self.ragged, 0, 1, "A crown's raggedness must be from 0 to 1"
        )
        require_between(
            self.hollow, 0, 0.9, "A crown's hollow must be from 0 to 0.9"
        )

    def middle(self) -> Vector3:
        """Return the point on the trunk's line where the crown is widest.

        Returns:
            The point, in meters.
        """
        var low = self.bottom.to(METER)
        var high = self.top.to(METER)
        return Vector3(0, low + (high - low) * self.widest, 0)

    def depth(self, p: Vector3, seed: Int) -> Float32:
        """Return how deep a point is in the crown's egg.

        Zero is the crown's middle, one its skin, and more than one is
        outside. The skin bulges and dents by `ragged`, so the outline is
        not a smooth egg.

        Args:
            p: The point, in meters, with the trunk's foot at the origin.
            seed: Which bulges.

        Returns:
            The depth.
        """
        var mid = self.middle()
        var up = p.y - mid.y
        var half = (self.top.to(METER) - mid.y) if up > 0 else (
            mid.y - self.bottom.to(METER)
        )
        var distance = sqrt(p.x * p.x + p.z * p.z)
        var across = distance / self.radius.to(METER)
        var along = up / half
        # The noise is read round a circle, so the outline has no seam.
        var cosine = p.x / max(distance, Float32(1.0e-6))
        var sine = p.z / max(distance, Float32(1.0e-6))
        var coarse = value_noise3(
            cosine * 1.4 + 7, along * 1.2 + 3, sine * 1.4, seed
        )
        var fine = value_noise3(
            cosine * 3.5 + 1, along * 3 + 9, sine * 3.5, seed + 2
        )
        var bulge = 1 + self.ragged * 0.8 * (
            0.65 * (coarse - 0.5) + 0.35 * (fine - 0.5)
        )
        return sqrt(across * across + along * along) / bulge

    def lobe_balls(self, seed: Int) -> List[Lobe]:
        """Return the crown's lobes.

        Each lobe's middle lies from `LOBE_IN` to `LOBE_OUT` of the way out
        to the egg's skin, and no nearer another lobe's than `LOBE_APART`
        of a lobe's size, if it can be. Its radius is from 0.75 to 1.25 of
        `lobe_size`.

        Args:
            seed: Which lobes.

        Returns:
            The lobes. None for a crown of no lobe.
        """
        var balls = List[Lobe]()
        var size = self.lobe_size.to(METER)
        var radius = self.radius.to(METER)
        var low = self.bottom.to(METER)
        var high = self.top.to(METER)
        for tries in range(self.lobes * TRIES * 4):  # pragma: no branch
            if len(balls) >= self.lobes:
                break
            var p = Vector3(
                (hash01(tries, 0, seed) * 2 - 1) * radius,
                low + (high - low) * hash01(tries, 1, seed),
                (hash01(tries, 2, seed) * 2 - 1) * radius,
            )
            var deep = self.depth(p, seed)
            if deep < LOBE_IN or deep > LOBE_OUT:
                continue
            var crowded = False
            for k in range(len(balls)):
                if (balls[k].center - p).length() < LOBE_APART * size:
                    crowded = True
            if crowded and tries < self.lobes * TRIES:
                continue
            balls.append(Lobe(p, size * (0.75 + 0.5 * hash01(tries, 3, seed))))
        return balls^

    def holds(self, p: Vector3, balls: List[Lobe], seed: Int) -> Bool:
        """Return whether a point is one a leaf can reach for.

        With no lobe, the point must be inside the egg. With lobes, it
        must be inside a lobe, and a lobe can bulge past the egg to
        `LOBE_REACH` of its depth. Either way it must be outside the
        hollow, and not in one of the small gaps that `ragged` carves.

        Args:
            p: The point, in meters, with the trunk's foot at the origin.
            balls: The crown's lobes, from `lobe_balls`.
            seed: Which gaps.

        Returns:
            Whether the point holds.
        """
        var deep = self.depth(p, seed)
        if deep < self.hollow:
            return False
        if len(balls) == 0:
            if deep > 1:
                return False
        else:
            if deep > LOBE_REACH:
                return False
            var inside = False
            for k in range(len(balls)):  # pragma: no branch
                if (balls[k].center - p).length() < balls[k].radius:
                    inside = True
                    break
            if not inside:
                return False
        var size = self.lobe_size.to(METER) * 0.5
        var solid = value_noise3(p.x / size, p.y / size, p.z / size, seed + 1)
        return solid >= self.ragged * 0.5


struct LimbParameters(Copyable, Movable):
    """The crown a tree grows into, and how its branches grow."""

    var shape: CrownShape
    # How many points the leaves reach for.
    var points: Int
    # How far apart two nodes of a branch are.
    var step: Length
    # How far a point pulls a node from.
    var reach: Length
    # How near a node must come to a point to reach it.
    var kill: Length
    # How much the growth bends up, or down if below zero.
    var up_pull: Float32
    # How much the growth bends down, at the crown's skin.
    var droop: Float32
    # How far up the crown, as a share of its height, the trunk climbs
    # before it branches.
    var fork: Float32
    # How far the trunk leans from upright.
    var lean: Angle
    # How much the trunk wanders as it climbs, from zero to one.
    var bend: Float32
    # How much each step of growth turns at random, from zero to one.
    var gnarl: Float32
    # How thick a twig's tip is.
    var tip_radius: Length
    # The pipe model's power.
    var pipe: Float32
    # How much the trunk flares at its foot.
    var flare: Float32
    # Which points, lean and gnarl.
    var seed: Int

    def __init__(out self):
        """Create the limbs of a tree about 14 meters tall, with a crown
        10 meters across from 5 meters up."""
        self.shape = CrownShape()
        self.points = 5000
        self.step = Length(0.25, METER)
        self.reach = Length(1.6, METER)
        self.kill = Length(0.4, METER)
        self.up_pull = 0.15
        self.droop = 0.2
        self.fork = 0.2
        self.lean = Angle(4.0, DEGREE)
        self.bend = 0.15
        self.gnarl = 0.25
        self.tip_radius = Length(0.006, METER)
        self.pipe = 2.3
        self.flare = 0.6
        self.seed = 1

    def check(self) raises:
        """Refuse limbs that cannot grow.

        Raises:
            Error: If the shape is refused, there are not from 1 to 20,000
                points, the step is not from 2 centimeters to 2 meters,
                the kill distance is not from the step to the reach, the
                reach is not from twice the step to 20 meters, the pull up
                is not from -1 to 1, the droop is not from 0 to 2, the
                fork is not from 0 to 0.9 of the crown's height, the
                lean is not from 0 to 45 degrees, the bend or the gnarl is
                not from 0 to 1, a tip is not from half a millimeter to 10
                centimeters thick, the pipe's power is not from 1.5 to
                3.5, or the flare is not from 0 to 3.
        """
        self.shape.check()
        require_count_between(
            self.points, 1, 20000, "A crown must have from 1 to 20,000 points"
        )
        var step = self.step.to(METER)
        require_between(
            step, 0.02, 2, "A step must be from 2 centimeters to 2 meters"
        )
        require_between(
            self.reach.to(METER),
            2 * step,
            20,
            "A reach must be from twice the step to 20 meters",
        )
        require_between(
            self.kill.to(METER),
            step,
            self.reach.to(METER),
            "A kill distance must be from the step to the reach",
        )
        require_between(self.up_pull, -1, 1, "A pull up must be from -1 to 1")
        require_between(self.droop, 0, 2, "A droop must be from 0 to 2")
        require_between(
            self.fork, 0, 0.9, "A trunk must fork from 0 to 0.9 up its crown"
        )
        require_between(
            self.lean.to(DEGREE),
            0,
            45,
            "A trunk must lean from 0 to 45 degrees",
        )
        require_between(self.bend, 0, 1, "A bend must be from 0 to 1")
        require_between(self.gnarl, 0, 1, "A gnarl must be from 0 to 1")
        require_between(
            self.tip_radius.to(METER),
            0.0005,
            0.1,
            (
                "A twig's tip must be from half a millimeter to 10 centimeters"
                " thick"
            ),
        )
        require_between(
            self.pipe, 1.5, 3.5, "A pipe's power must be from 1.5 to 3.5"
        )
        require_between(self.flare, 0, 3, "A flare must be from 0 to 3")


struct Skeleton(Movable):
    """A tree's branches, as nodes each joined to its parent.

    A parent comes before each of its children, so node 0 is the root at
    the trunk's foot.
    """

    var position: List[Vector3]
    # Each node's parent, or -1 for the root.
    var parent: List[Int]
    # Each node's first child and its next sibling, or -1 for none.
    var first_child: List[Int]
    var next_sibling: List[Int]
    # Each node's thickest child, or -1 for a tip.
    var main_child: List[Int]
    var radius: List[Float32]
    # How far each node is from the nearest twig tip above it, along the
    # branches.
    var tip_distance: List[Float32]
    # How many points the leaves reached for, and how many they reached.
    var points: Int
    var reached: Int
    # How many nodes the trunk climbed before the branches grew: nodes 0
    # to `trunk - 1`.
    var trunk: Int

    def __init__(out self):
        """Create a skeleton with no node."""
        self.position = List[Vector3]()
        self.parent = List[Int]()
        self.first_child = List[Int]()
        self.next_sibling = List[Int]()
        self.main_child = List[Int]()
        self.radius = List[Float32]()
        self.tip_distance = List[Float32]()
        self.points = 0
        self.reached = 0
        self.trunk = 0

    def count(self) -> Int:
        """Return how many nodes the skeleton has.

        Returns:
            The count.
        """
        return len(self.position)

    def tips(self) -> Int:
        """Return how many twig tips the skeleton has.

        Returns:
            The count of nodes with no child.
        """
        var tips = 0
        for n in range(self.count()):  # pragma: no branch
            if self.first_child[n] < 0:
                tips += 1
        return tips

    def _add(mut self, p: Vector3, parent: Int) -> Int:
        """Append a node as the first child of its parent."""
        var index = self.count()
        self.position.append(p)
        self.parent.append(parent)
        self.first_child.append(-1)
        self.next_sibling.append(-1)
        if parent >= 0:
            self.next_sibling[index] = self.first_child[parent]
            self.first_child[parent] = index
        return index

    def _grows_toward(self, n: Int, way: Vector3) -> Bool:
        """Return whether a child of `n` already grows close to `way`."""
        var c = self.first_child[n]
        while c >= 0:
            var grown = self.position[c] - self.position[n]
            if grown.dot(way) > TWIN * grown.length():
                return True
            c = self.next_sibling[c]
        return False


def unit_or_up(v: Vector3) -> Vector3:
    """Return a vector scaled to unit length.

    Args:
        v: The vector.

    Returns:
        `v` at unit length, or +y when `v` is shorter than 1e-6.
    """
    var length = v.length()
    if length < 1.0e-6:
        return Vector3(0, 1, 0)
    return v / length


def _scatter(parameters: LimbParameters) -> List[Vector3]:
    """Return the points the leaves reach for: up to `points` of them,
    tried at random in the shape's bounds, which its lobes can bulge past.
    """
    ref shape = parameters.shape
    var radius = shape.radius.to(METER)
    var low = shape.bottom.to(METER)
    var high = shape.top.to(METER)
    var seed = parameters.seed * 7349 + 11
    var balls = shape.lobe_balls(parameters.seed + 3)
    var points = List[Vector3]()
    var tries = 0
    while len(points) < parameters.points and tries < (
        parameters.points * TRIES
    ):
        var p = Vector3(
            (hash01(tries, 0, seed) * 2 - 1) * radius * LOBE_REACH,
            low + (high - low) * hash01(tries, 1, seed),
            (hash01(tries, 2, seed) * 2 - 1) * radius * LOBE_REACH,
        )
        tries += 1
        if shape.holds(p, balls, parameters.seed):
            points.append(p)
    return points^


def _nearest(points: List[Vector3], p: Vector3) -> Float32:
    """Return the distance from `p` to the nearest point, or a large
    number if there is none."""
    var best = Float32(1.0e30)
    for index in range(len(points)):
        best = min(best, (points[index] - p).length())
    return best


def _climb(
    mut skeleton: Skeleton, parameters: LimbParameters, points: List[Vector3]
):
    """Grow the trunk from the ground to its fork, and on until a point is
    within reach of its top, or it passes the crown's top."""
    var step = parameters.step.to(METER)
    var reach = parameters.reach.to(METER)
    var top = parameters.shape.top.to(METER)
    var bottom = parameters.shape.bottom.to(METER)
    var fork = bottom + (top - bottom) * parameters.fork
    var seed = parameters.seed * 3511 + 5
    var tilt = parameters.lean.to(RADIAN)
    var heading = Float32(2) * Float32(pi) * hash01(0, 0, seed)
    var phase = Float32(2) * Float32(pi) * hash01(0, 1, seed)
    var here = Vector3(0, 0, 0)
    var node = skeleton._add(here, -1)
    while (here.y < fork or _nearest(points, here) >= reach) and here.y < top:
        var wander = parameters.bend * 0.25 * sin(here.y * 0.45 + phase)
        var way = unit_or_up(
            Vector3(
                sin(tilt) * cos(heading) + wander,
                cos(tilt),
                sin(tilt) * sin(heading) + wander * 0.6,
            )
        )
        here = here + way * step
        node = skeleton._add(here, node)
    skeleton.trunk = skeleton.count()


def _colonize(
    mut skeleton: Skeleton, parameters: LimbParameters, points: List[Vector3]
):
    """Grow the branches toward the points until no node grows."""
    var step = parameters.step.to(METER)
    var reach = parameters.reach.to(METER)
    var kill = parameters.kill.to(METER)
    var radius = parameters.shape.radius.to(METER)
    var seed = parameters.seed * 4271 + 9
    var count = len(points)
    var best = List[Float32](length=count, fill=Float32(1.0e30))
    var owner = List[Int](length=count, fill=-1)
    var alive = List[Bool](length=count, fill=True)
    var pull = List[Vector3]()
    var pulls = List[Int]()
    var checked = 0
    for growth in range(MAX_ROUNDS):  # pragma: no branch
        var nodes = skeleton.count()
        while len(pull) < nodes:
            pull.append(Vector3(0, 0, 0))
            pulls.append(0)
        var pulled = List[Int]()
        for a in range(count):
            if not alive[a]:
                continue
            ref p = points[a]
            # A round that grows no node is the last, so each round has
            # new nodes to check.
            for n in range(checked, nodes):  # pragma: no branch
                var d = (p - skeleton.position[n]).length()
                if d < best[a]:
                    best[a] = d
                    owner[a] = n
            if best[a] < kill:
                alive[a] = False
                skeleton.reached += 1
                continue
            if best[a] < reach:
                var n = owner[a]
                if pulls[n] == 0:
                    pulled.append(n)
                pull[n] = pull[n] + (p - skeleton.position[n]) / best[a]
                pulls[n] += 1
        checked = nodes
        var grew = False
        for k in range(len(pulled)):
            var n = pulled[k]
            var at = skeleton.position[n]
            var mean = unit_or_up(pull[n] / Float32(pulls[n]))
            pull[n] = Vector3(0, 0, 0)
            pulls[n] = 0
            var far = sqrt(at.x * at.x + at.z * at.z) / radius
            var key = growth * 8
            var jitter = Vector3(
                hash01(n, key, seed) - 0.5,
                hash01(n, key + 1, seed) - 0.5,
                hash01(n, key + 2, seed) - 0.5,
            )
            var way = unit_or_up(
                mean
                + Vector3(
                    0, parameters.up_pull - parameters.droop * far * far, 0
                )
                + jitter * parameters.gnarl
            )
            if skeleton._grows_toward(n, way):
                continue
            _ = skeleton._add(at + way * step, n)
            grew = True
        if not grew:
            break


def _thicken(mut skeleton: Skeleton, parameters: LimbParameters):
    """Give each node its pipe-model radius, its thickest child and its
    distance from the nearest tip, then flare the trunk's foot."""
    var count = skeleton.count()
    var power = parameters.pipe
    var tip = pow(parameters.tip_radius.to(METER), power)
    var area = List[Float32](length=count, fill=0)
    skeleton.radius = List[Float32](length=count, fill=0)
    skeleton.main_child = List[Int](length=count, fill=-1)
    skeleton.tip_distance = List[Float32](length=count, fill=Float32(1.0e30))
    var n = count - 1
    while n >= 0:
        if skeleton.first_child[n] < 0:
            area[n] = tip
            skeleton.tip_distance[n] = 0
        skeleton.radius[n] = pow(area[n], 1 / power)
        var up = skeleton.parent[n]
        if up >= 0:
            area[up] += area[n]
            var main = skeleton.main_child[up]
            if main < 0 or area[n] > area[main]:
                skeleton.main_child[up] = n
            var length = (skeleton.position[n] - skeleton.position[up]).length()
            skeleton.tip_distance[up] = min(
                skeleton.tip_distance[up], skeleton.tip_distance[n] + length
            )
        n -= 1
    for m in range(count):  # pragma: no branch
        var low = max(Float32(0), 1 - skeleton.position[m].y / FOOT)
        skeleton.radius[m] *= 1 + parameters.flare * low * low * low


def _smooth(mut skeleton: Skeleton):
    """Move each inner node a quarter of the way toward the middle of its
    parent and its thickest child, so a branch curves and does not kink.
    """
    var moved = skeleton.position.copy()
    for n in range(1, skeleton.count()):
        var child = skeleton.main_child[n]
        if child < 0:
            continue
        var middle = (
            skeleton.position[skeleton.parent[n]] + skeleton.position[child]
        ) * 0.5
        moved[n] = skeleton.position[n] * 0.5 + middle * 0.5
    skeleton.position = moved^


def grow_limbs(parameters: LimbParameters) raises -> Skeleton:
    """Grow a tree's branches into its crown.

    Args:
        parameters: The crown's shape and how the branches grow.

    Returns:
        The branches, with each node's radius, thickest child and distance
        from the nearest tip.

    Raises:
        Error: If `parameters.check` refuses a value.
    """
    parameters.check()
    var points = _scatter(parameters)
    var skeleton = Skeleton()
    skeleton.points = len(points)
    _climb(skeleton, parameters, points)
    _colonize(skeleton, parameters, points)
    _thicken(skeleton, parameters)
    _smooth(skeleton)
    _smooth(skeleton)
    return skeleton^


def _chains(skeleton: Skeleton, thinnest: Float32) -> List[List[Int]]:
    """Return the chains of nodes that make tubes. Each starts at the fork
    it leaves, follows the thickest child, and stops before a node thinner
    than `thinnest`."""
    var chains = List[List[Int]]()
    var starts: List[Int] = [0]
    while len(starts) > 0:
        var n = starts.pop()
        var chain = List[Int]()
        if skeleton.parent[n] >= 0:
            chain.append(skeleton.parent[n])
        while True:
            chain.append(n)
            var main = skeleton.main_child[n]
            var c = skeleton.first_child[n]
            while c >= 0:
                if c != main and skeleton.radius[c] >= thinnest:
                    starts.append(c)
                c = skeleton.next_sibling[c]
            if main < 0 or skeleton.radius[main] < thinnest:
                break
            n = main
        if len(chain) >= 2:
            chains.append(chain^)
    return chains^


def limb_mesh(
    skeleton: Skeleton, thinnest: Length, sides: Int
) raises -> BufferGeometry:
    """Return the wood of a skeleton: a tube along each chain of nodes.

    A tube has from 3 to `sides` vertices round each ring, more on a
    thicker branch. Its first ring sits at the fork it leaves, as thick as
    the branch and not as the fork.

    Args:
        skeleton: The branches.
        thinnest: The thinnest branch drawn.
        sides: The most vertices round a ring, from 3 to 32.

    Returns:
        The geometry, with `position`, `normal` and an index.

    Raises:
        Error: If `sides` is not from 3 to 32, or no branch is as thick as
            `thinnest`.
    """
    require_count_between(sides, 3, 32, "A branch must have from 3 to 32 sides")
    var chains = _chains(skeleton, thinnest.to(METER))
    if len(chains) == 0:
        raise Error("A tree thinner than its thinnest wood has no wood")
    var positions = List[Float32]()
    var normals = List[Float32]()
    var index = List[Int]()
    var turn = Float32(2) * Float32(pi)
    for k in range(len(chains)):  # pragma: no branch
        ref chain = chains[k]
        var last = len(chain) - 1
        var thick = skeleton.radius[chain[1]]
        var radial = max(3, min(sides, 3 + Int(thick * 100)))
        var first = len(positions) // 3
        var tangent = unit_or_up(
            skeleton.position[chain[1]] - skeleton.position[chain[0]]
        )
        var side = unit_or_up(
            Vector3(tangent.z, 0, -tangent.x) if abs(tangent.y)
            < 0.9 else Vector3(1, 0, 0)
        )
        for r in range(len(chain)):  # pragma: no branch
            ref here = skeleton.position[chain[r]]
            var ahead = skeleton.position[chain[min(r + 1, last)]]
            var behind = skeleton.position[chain[max(r - 1, 0)]]
            tangent = unit_or_up(ahead - behind)
            # Carry the side round to stay square to the tube, so the
            # rings do not twist.
            side = unit_or_up(side - tangent * side.dot(tangent))
            var other = Vector3(
                tangent.y * side.z - tangent.z * side.y,
                tangent.z * side.x - tangent.x * side.z,
                tangent.x * side.y - tangent.y * side.x,
            )
            var thickness = skeleton.radius[chain[max(r, 1)]]
            for j in range(radial):  # pragma: no branch
                var a = turn * Float32(j) / Float32(radial)
                var radial = side * cos(a) + other * sin(a)
                var p = here + radial * thickness
                positions.append(p.x)
                positions.append(p.y)
                positions.append(p.z)
                normals.append(radial.x)
                normals.append(radial.y)
                normals.append(radial.z)
        for r in range(last):  # pragma: no branch
            var a = first + r * radial
            var b = a + radial
            for j in range(radial):  # pragma: no branch
                var next = (j + 1) % radial
                index.append(a + j)
                index.append(b + next)
                index.append(b + j)
                index.append(a + j)
                index.append(a + next)
                index.append(b + next)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(NORMAL, BufferAttribute(normals^, 3))
    geometry.set_index(index^)
    return geometry^
