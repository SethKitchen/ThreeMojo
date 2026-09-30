# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hair that moves: a groom's strands under gravity and the wind.

Each point of every strand is a particle. A step moves them by Verlet
integration, then settles them against constraints, as position-based
dynamics does (Bender et al. 2015, "Position-Based Simulation Methods in
Computer Graphics"):

- Length: each segment keeps the length it was groomed at.
- Global shape: each point is pulled back to where it was groomed,
  fully near the root and less toward the tip, so the style holds.
- Local shape: each run of three points keeps its bend (Kelager et al.
  2010, "A Triangle Bending Constraint Model for Position-Based
  Dynamics"); the last points keep their groomed direction.
- Collisions: a point that falls inside the head is pushed out of it,
  along the gradient of a distance field baked round the head.

The wind blows in one direction, in gusts: each strand's strength
flutters, out of phase with its neighbors'. Friction takes part of each
point's motion away every step.

This ports the hair simulation of Frostbitten Hair WebGPU by Marcin
Matuszczyk, MIT license, copyright 2024, and keeps its defaults, which
are tuned to its fixed step of a thirtieth of a second. Its grids of
density and velocity, which push strands apart and carry them along
together, are left out. See THIRD-PARTY-NOTICES.md.

This is not a three.js port. See Extensions.

    var collider = HairCollider(HeadSkinField(dims))
    var physics = HairSimulation(groom)
    physics.step(collider, HairWind(Vector3(1, 0, 0), 0.5))
"""

from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import floor, max, min, sqrt

# The collider's grid: cells along each side of its box.
comptime COLLIDER_CELLS = 48
# How far past the collider's box a sample reads as empty, in meters.
comptime FAR_AWAY = Float32(1.0)


struct HairCollider(Copyable, Movable):
    """A distance field baked into a grid, which a step reads for each
    point: a solid's own field is far too slow to read that often."""

    var low: Vector3
    var cell: Vector3
    var cells: Int
    var values: List[Float32]

    def __init__[
        F: DistanceField
    ](out self, field: F, low: Vector3, high: Vector3):
        """Bake `field` over the box from `low` to `high`.

        Args:
            field: The solid, a head's skin.
            low: The box's least corner.
            high: The box's greatest corner.
        """
        self.cells = COLLIDER_CELLS
        self.low = low
        var n = Float32(self.cells - 1)
        self.cell = Vector3(
            (high.x - low.x) / n, (high.y - low.y) / n, (high.z - low.z) / n
        )
        self.values = List[Float32](
            capacity=self.cells * self.cells * self.cells
        )
        for k in range(self.cells):  # pragma: no branch
            for j in range(self.cells):  # pragma: no branch
                for i in range(self.cells):  # pragma: no branch
                    self.values.append(
                        field.distance(
                            low
                            + Vector3(
                                Float32(i) * self.cell.x,
                                Float32(j) * self.cell.y,
                                Float32(k) * self.cell.z,
                            )
                        )
                    )

    def distance(self, point: Vector3) -> Float32:
        """Return the baked distance at `point`, trilinear between the
        grid's samples, or far away off the grid.

        Args:
            point: Where to read, in the frame the field was baked in.

        Returns:
            The distance, negative inside the solid.
        """
        var u = (point.x - self.low.x) / self.cell.x
        var v = (point.y - self.low.y) / self.cell.y
        var w = (point.z - self.low.z) / self.cell.z
        var top = Float32(self.cells - 1)
        if u < 0 or v < 0 or w < 0 or u >= top or v >= top or w >= top:
            return FAR_AWAY
        var i = Int(u)
        var j = Int(v)
        var k = Int(w)
        var fu = u - Float32(i)
        var fv = v - Float32(j)
        var fw = w - Float32(k)
        var n = self.cells
        var at = (k * n + j) * n + i
        var c00 = self.values[at] + (self.values[at + 1] - self.values[at]) * fu
        var c10 = (
            self.values[at + n]
            + (self.values[at + n + 1] - self.values[at + n]) * fu
        )
        var c01 = (
            self.values[at + n * n]
            + (self.values[at + n * n + 1] - self.values[at + n * n]) * fu
        )
        var c11 = (
            self.values[at + n * n + n]
            + (self.values[at + n * n + n + 1] - self.values[at + n * n + n])
            * fu
        )
        var c0 = c00 + (c10 - c00) * fv
        var c1 = c01 + (c11 - c01) * fv
        return c0 + (c1 - c0) * fw


@fieldwise_init
struct HairWind(ImplicitlyCopyable):
    """The wind: which way it blows, how hard, and how it gusts."""

    # The unit direction it blows toward.
    var direction: Vector3
    # Its strength, in Frostbitten's units: zero through about one.
    var strength: Float32
    # How often each strand's strength flutters, and by how much.
    var frequency: Float32
    var jitter: Float32
    # How far out of phase each strand is with the one before it.
    var phase: Float32

    def __init__(out self, direction: Vector3, strength: Float32):
        """Take Frostbitten's gusts for a wind of `strength`.

        Args:
            direction: The unit direction it blows toward.
            strength: How hard it blows, zero through about one.
        """
        self.direction = direction
        self.strength = strength
        self.frequency = Float32(1.8)
        self.jitter = Float32(0.7)
        self.phase = Float32(0.45)


struct HairPhysics(ImplicitlyCopyable):
    """How the strands move: Frostbitten's defaults."""

    var step: Float32
    var gravity: Float32
    var friction: Float32
    var iterations: Int
    var length: Float32
    var shape: Float32
    var extent: Float32
    var fade: Float32
    var bend: Float32
    var collision: Float32
    # How far outside the collider a point is kept, in meters.
    var offset: Float32

    def __init__(out self):
        """Take Frostbitten's defaults."""
        self.step = Float32(1.0) / 30
        self.gravity = Float32(0.03)
        self.friction = Float32(0.3)
        self.iterations = 7
        self.length = Float32(1.0)
        self.shape = Float32(0.2)
        self.extent = Float32(0.1)
        self.fade = Float32(0.75)
        self.bend = Float32(0.3)
        self.collision = Float32(1.0)
        self.offset = Float32(0.0015)


struct HairSimulation(Movable):
    """Every point of a groom as a particle: where it was groomed, where
    it is, and where it was a step ago."""

    var starts: List[Int]
    var initial: List[Vector3]
    var now: List[Vector3]
    var previous: List[Vector3]
    var lengths: List[Float32]
    var physics: HairPhysics
    var frame: Int

    def __init__(
        out self, groom: HairGroom, physics: HairPhysics = HairPhysics()
    ):
        """Start the particles at rest where the groom lays them.

        Args:
            groom: The strands.
            physics: How they move; Frostbitten's defaults by default.
        """
        self.starts = groom.starts.copy()
        self.initial = groom.points.copy()
        self.now = groom.points.copy()
        self.previous = groom.points.copy()
        self.lengths = List[Float32](length=len(groom.points), fill=0)
        for index in range(len(groom.points) - 1):  # pragma: no branch
            self.lengths[index] = (
                groom.points[index + 1] - groom.points[index]
            ).length()
        self.physics = physics
        self.frame = 0

    def step(mut self, collider: HairCollider, wind: HairWind):
        """Move every strand one step, and settle it.

        Args:
            collider: The head, baked.
            wind: The wind.
        """
        ref p = self.physics
        var dt2 = p.step * p.step
        for strand in range(len(self.starts) - 1):  # pragma: no branch
            var first = self.starts[strand]
            var end = self.starts[strand + 1]
            # Verlet: each point but the root carries on as it moved,
            # less friction, under gravity and the wind.
            var timer = Float32(self.frame) * Float32(
                0.73
            ) + wind.phase * Float32(strand)
            var flutter = timer * wind.frequency
            flutter = flutter - floor(flutter)
            var gust = 1 + wind.jitter * (flutter - Float32(0.5))
            var force = Vector3(0, -p.gravity, 0) + wind.direction * abs(
                wind.strength * gust
            )
            var moved = List[Vector3](capacity=end - first)
            moved.append(self.now[first])
            for index in range(first + 1, end):  # pragma: no branch
                var motion = (self.now[index] - self.previous[index]) * (
                    1 - p.friction
                )
                moved.append(self.now[index] + motion + force * dt2)
            for _ in range(p.iterations):  # pragma: no branch
                self._settle(moved, first, collider)
            for k in range(end - first):  # pragma: no branch
                self.previous[first + k] = self.now[first + k]
                self.now[first + k] = moved[k]
        self.frame += 1

    def _settle(
        self, mut points: List[Vector3], first: Int, collider: HairCollider
    ):
        """Settle one strand once against every constraint."""
        ref p = self.physics
        var count = len(points)
        var iterations = Float32(p.iterations)
        # Length: the root is fixed, so its segment moves only the other
        # end.
        for k in range(count - 1):  # pragma: no branch
            var d = points[k + 1] - points[k]
            var length = max(d.length(), Float32(1e-9))
            var wrong = 1 - self.lengths[first + k] / length
            var w0 = Float32(0) if k == 0 else Float32(1)
            var delta = d * (wrong * p.length / (w0 + 1))
            points[k] = points[k] + delta * w0
            points[k + 1] = points[k + 1] - delta
        # Global shape, fading from the root to the tip.
        for k in range(1, count):  # pragma: no branch
            var x = Float32(k) / Float32(count - 1)
            var keep = 1 - min(
                Float32(1), max(Float32(0), (x - p.extent) / p.fade)
            )
            points[k] = points[k] + (self.initial[first + k] - points[k]) * (
                p.shape / iterations * keep
            )
        # Local shape: each run of three keeps its bend.
        var bend = p.bend / iterations
        for k in range(count - 2):  # pragma: no branch
            var a = self.initial[first + k]
            var b = self.initial[first + k + 1]
            var c = self.initial[first + k + 2]
            var rest = (b - (a + b + c) / 3).length()
            var middle = (points[k] + points[k + 1] + points[k + 2]) / 3
            var h = points[k + 1] - middle
            var height = h.length()
            if height < Float32(1e-9):
                continue
            var delta = h * (1 - rest / height)
            var w0 = Float32(0) if k == 0 else Float32(1)
            var total = w0 + 2 + 1
            points[k] = points[k] + delta * (bend * w0 / total * 2)
            points[k + 1] = points[k + 1] + delta * (bend / total * -4)
            points[k + 2] = points[k + 2] + delta * (bend / total * 2)
        # Collisions: a point inside the head goes out along the field's
        # gradient; the points by the root lie against it and are left.
        var push = p.collision / iterations
        var probe = collider.cell.x * Float32(0.1)
        for k in range(3, count):  # pragma: no branch
            var q = points[k]
            var d = collider.distance(q) - p.offset
            if d >= 0:
                continue
            var g = Vector3(
                collider.distance(q + Vector3(probe, 0, 0)) - p.offset - d,
                collider.distance(q + Vector3(0, probe, 0)) - p.offset - d,
                collider.distance(q + Vector3(0, 0, probe)) - p.offset - d,
            )
            var length = g.length()
            if length < Float32(1e-12):
                continue
            points[k] = q - g * (d * push / length)

    def write(self, mut groom: HairGroom) raises:
        """Put the particles' places into the groom it was made from.

        Args:
            groom: The groom, with as many points as the particles.

        Raises:
            Error: If the groom holds another count of points.
        """
        if len(groom.points) != len(self.now):
            raise Error("The groom is not the one the hair moves")
        for index in range(len(self.now)):  # pragma: no branch
            groom.points[index] = self.now[index]
