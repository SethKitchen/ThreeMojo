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
- Collisions: a point that falls inside the body is pushed out of it,
  along the gradient of a distance field baked round it.

The wind blows in one direction, in gusts: each strand's strength
flutters, out of phase with its neighbors'. Friction takes part of each
point's motion away every step.

This ports the hair simulation of Frostbitten Hair WebGPU by Marcin
Matuszczyk, MIT license, copyright 2024, and keeps its defaults, which
are tuned to its fixed step of a thirtieth of a second. Its grids of
density and velocity, which push strands apart and carry them along
together, are left out. See THIRD-PARTY-NOTICES.md.

This is not a three.js port. See Extensions.

    var physics = HairSimulation(groom)
    var body = HairBody(dims)
    physics.step(body, HairWind(Vector3(1, 0, 0), 0.5))
"""

from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.hair.groom import (
    HairGroom,
    _unit_vector,
    follower_across,
)
from math.vector3 import Vector3
from std.math import floor, isfinite, max, min


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
    # How far outside the collider a point is kept, and how far apart
    # its field is read for its gradient, in meters.
    var offset: Float32
    var probe: Float32

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
        self.probe = Float32(0.001)


def _motion_normal(before: Vector3, after: Vector3, normal: Vector3) -> Vector3:
    """Rotate a rest normal with the shortest rotation of its tangent."""
    var cosine = min(Float32(1), max(Float32(-1), before.dot(after)))
    var axis = before
    axis.cross(after)
    var turned: Vector3
    if cosine > Float32(-0.9999):
        var first = axis
        first.cross(normal)
        var second = axis
        second.cross(first)
        turned = normal + first + second / (1 + cosine)
    else:
        # A half turn has no unique axis. Keep the projected rest normal
        # when possible, otherwise use a deterministic orthogonal axis.
        axis = normal - before * normal.dot(before)
        if axis.length() < Float32(1e-6):
            var basis = Vector3(1, 0, 0)
            if abs(before.x) > Float32(0.9):
                basis = Vector3(0, 1, 0)
            axis = before
            axis.cross(basis)
        axis.normalize()
        turned = axis * (2 * axis.dot(normal)) - normal
    if turned.length() == 0:
        return Vector3(0, 0, 1)
    turned.normalize()
    return turned


struct HairSimulation(Movable):
    """Every point of a groom as a particle: where it was groomed, where
    it is, and where it was a step ago."""

    var starts: List[Int]
    var initial: List[Vector3]
    var now: List[Vector3]
    var previous: List[Vector3]
    var lengths: List[Float32]
    var initial_normals: List[Vector3]
    var initial_depths: List[Float32]
    var initial_tangents: List[Vector3]
    var physics: HairPhysics
    var frame: Int
    # True steps the guides only and lays each follower along its guide.
    var guides_only: Bool
    var guides: List[Int]
    var follow_across: List[Float32]
    var follow_up: List[Float32]

    def __init__(
        out self,
        groom: HairGroom,
        physics: HairPhysics = HairPhysics(),
        guides_only: Bool = False,
    ) raises:
        """Start the particles at rest where the groom lays them.

        Args:
            groom: The strands.
            physics: How they move; Frostbitten's defaults by default.
            guides_only: True steps only the guide strands. Each follower
                then keeps its groomed offsets in its moved guide's frame,
                as TressFX lays follow strands. This costs about as much as
                the guides alone.

        Raises:
            Error: If `guides_only` is set and the groom's guide records do
                not match its strands.
        """
        if guides_only and (
            len(groom.guides) != len(groom)
            or len(groom.follow_across) != len(groom.points)
            or len(groom.follow_up) != len(groom.points)
        ):
            raise Error("The groom's guide records do not match its strands")
        self.guides_only = guides_only
        self.guides = groom.guides.copy()
        self.follow_across = groom.follow_across.copy()
        self.follow_up = groom.follow_up.copy()
        self.starts = groom.starts.copy()
        self.initial = groom.points.copy()
        self.now = groom.points.copy()
        self.previous = groom.points.copy()
        self.lengths = List[Float32](length=len(groom.points), fill=0)
        self.initial_normals = groom.normals.copy()
        self.initial_depths = groom.depths.copy()
        self.initial_tangents = List[Vector3](capacity=len(groom.points))
        for index in range(len(groom.points)):
            self.initial_tangents.append(groom.tangent(index))
        for index in range(len(groom.points) - 1):  # pragma: no branch
            self.lengths[index] = (
                groom.points[index + 1] - groom.points[index]
            ).length()
        self.physics = physics
        self.frame = 0

    def step[F: DistanceField](mut self, collider: F, wind: HairWind):
        """Move every strand one step, and settle it.

        Parameters:
            F: The collider's type.

        Args:
            collider: What the hair falls against, baked: a `HairBody`
                or a `HairCollider`.
            wind: The wind.
        """
        var p = self.physics
        var dt2 = p.step * p.step
        for strand in range(len(self.starts) - 1):  # pragma: no branch
            if self.guides_only and self.guides[strand] >= 0:
                continue
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
            # Reuse the particle arrays. No per-strand work list or
            # allocation is needed for these sequential constraints.
            self.previous[first] = self.now[first]
            for index in range(first + 1, end):  # pragma: no branch
                var motion = (self.now[index] - self.previous[index]) * (
                    1 - p.friction
                )
                var before = self.now[index]
                self.now[index] = before + motion + force * dt2
                self.previous[index] = before
            for _ in range(p.iterations):  # pragma: no branch
                self._settle(first, end, collider)
        if self.guides_only:
            self._lay_followers()
        self.frame += 1

    def _lay_followers(mut self):
        # Each follower point sits at its guide point, offset across the
        # hair and up off it in the guide's moved frame.
        for strand in range(len(self.starts) - 1):
            var guide = self.guides[strand]
            if guide < 0:
                continue
            var first = self.starts[strand]
            var lead = self.starts[guide]
            var last = self.starts[guide + 1] - 1 - lead
            for k in range(
                self.starts[strand + 1] - first
            ):  # pragma: no branch
                var before = self.now[lead + max(k - 1, 0)]
                var after = self.now[lead + min(k + 1, last)]
                var normal = _motion_normal(
                    self.initial_tangents[lead + k],
                    _unit_vector(after - before, Vector3(0, -1, 0)),
                    self.initial_normals[lead + k],
                )
                var across = follower_across(before, after, normal)
                var point = (
                    self.now[lead + k]
                    + across * self.follow_across[first + k]
                    + normal * self.follow_up[first + k]
                )
                self.now[first + k] = point
                self.previous[first + k] = point

    def _settle[F: DistanceField](mut self, first: Int, end: Int, collider: F):
        """Settle one strand once against every constraint."""
        var p = self.physics
        var count = end - first
        var iterations = Float32(p.iterations)
        # Length: the root is fixed, so its segment moves only the other
        # end.
        for k in range(count - 1):  # pragma: no branch
            var d = self.now[first + k + 1] - self.now[first + k]
            var length = max(d.length(), Float32(1e-9))
            var wrong = 1 - self.lengths[first + k] / length
            var w0 = Float32(0) if k == 0 else Float32(1)
            var delta = d * (wrong * p.length / (w0 + 1))
            self.now[first + k] = self.now[first + k] + delta * w0
            self.now[first + k + 1] = self.now[first + k + 1] - delta
        # Global shape, fading from the root to the tip.
        for k in range(1, count):  # pragma: no branch
            var x = Float32(k) / Float32(count - 1)
            var keep = 1 - min(
                Float32(1), max(Float32(0), (x - p.extent) / p.fade)
            )
            self.now[first + k] = self.now[first + k] + (
                self.initial[first + k] - self.now[first + k]
            ) * (p.shape / iterations * keep)
        # Local shape: each run of three keeps its bend.
        var bend = p.bend / iterations
        for k in range(count - 2):  # pragma: no branch
            var a = self.initial[first + k]
            var b = self.initial[first + k + 1]
            var c = self.initial[first + k + 2]
            var rest = (b - (a + b + c) / 3).length()
            var middle = (
                self.now[first + k]
                + self.now[first + k + 1]
                + self.now[first + k + 2]
            ) / 3
            var h = self.now[first + k + 1] - middle
            var height = h.length()
            if height < Float32(1e-9):
                continue
            var delta = h * (1 - rest / height)
            var w0 = Float32(0) if k == 0 else Float32(1)
            var total = w0 + 2 + 1
            self.now[first + k] = self.now[first + k] + delta * (
                bend * w0 / total * 2
            )
            self.now[first + k + 1] = self.now[first + k + 1] + delta * (
                bend / total * -4
            )
            self.now[first + k + 2] = self.now[first + k + 2] + delta * (
                bend / total * 2
            )
        # Collisions: a point inside the body goes out along the field's
        # gradient; the points by the root lie against it and are left.
        var push = p.collision / iterations
        var probe = p.probe
        for k in range(3, count):  # pragma: no branch
            var q = self.now[first + k]
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
            self.now[first + k] = q - g * (d * push / length)

    def write(self, mut groom: HairGroom) raises:
        """Write positions and refresh the motion-dependent shading fields.

        Normals rotate with each tangent from the rest frame. The old
        scalp depth is a rest-surface proxy: outward displacement reduces
        it, and inward displacement increases it. It is not a dynamic
        density estimate. HairStrands.shade rebuilds its separate moving
        density volume for direct-light self-shadow.

        Args:
            groom: The groom, with the simulation's topology and fields.

        Raises:
            Error: If topology or field counts differ, or a position is
                not finite. The groom is unchanged after such a failure.
        """
        if len(groom.points) != len(self.now) or len(groom.starts) != len(
            self.starts
        ):
            raise Error("The groom is not the one the hair moves")
        if len(groom.normals) != len(self.now) or len(groom.depths) != len(
            self.now
        ):
            raise Error("The groom's shading fields do not match the hair")
        if (
            len(self.initial_normals) != len(self.now)
            or len(self.initial_depths) != len(self.now)
            or len(self.initial_tangents) != len(self.now)
        ):
            raise Error("The hair's rest shading fields do not match")
        if groom.starts != self.starts:
            raise Error("The groom is not the one the hair moves")
        for index in range(len(self.now)):
            var p = self.now[index]
            if not isfinite(p.x) or not isfinite(p.y) or not isfinite(p.z):
                raise Error("Hair motion must have finite positions")
        for index in range(len(self.now)):
            groom.points[index] = self.now[index]
        for index in range(len(self.now)):
            var normal = self.initial_normals[index]
            groom.normals[index] = _motion_normal(
                self.initial_tangents[index], groom.tangent(index), normal
            )
            var lift = (self.now[index] - self.initial[index]).dot(normal)
            groom.depths[index] = max(
                Float32(0), self.initial_depths[index] - lift
            )
