# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wind over a field: gusts that travel, a sway, and a flutter of each
blade.

**How a meadow moves.** Wind over tall grass is seen as waves of light
that sweep across the field. A gust bends the blades it reaches, and a
bent blade shows more of its lit face. So the motion has three scales:

- A gust is a patch of stronger wind, meters wide. The patches travel
  downwind at `gust_speed`. Every blade under a patch bends together,
  which gives the sweep. `gust` is value noise read in a frame that moves
  with the wind, stretched across the wind so a gust front is a band. A
  slower noise bends each front, so it is a ragged curve and not a line,
  and smaller gusts cross the large ones at an angle. The whole pattern
  travels with the wind, as turbulence does.
- A sway is a wave that rolls downwind every `sway_length`, `sway_rate`
  times a second. Whole tufts ride it together: pushed forward, they snap
  flat, and they spring back. The sway is mostly in the gusts: calm air
  barely rocks the grass.
- A flutter is a slight tremble of each blade on its own, a few degrees.
  Each blade has its own phase, so neighbors do not move in step. It is
  small and slow: a large fast flutter reads as jitter, not as wind.

The gust is the largest of the three. Calm air leans a tip `calm` of
`lean`, and a full gust leans it all of `lean`, so a gust front that
passes bends the whole patch over and lets it rise again.

**A loop.** A wind with a `loop` repeats itself exactly after that
time, so an animation of it can play round and round with no jump. The
gust field is the field at `t` faded into the field at `t - loop`, with
the fade weighted so a gust keeps its contrast in the middle of the
loop. The flutter wobbles a whole number of times a loop.

**Why a bend is an angle.** `tip_bend` returns how far the tip turns from
upright, as an angle along the ground, and not a distance. The blade is
built segment by segment, and each segment turns by its share of that
angle. The segments keep their length, so a bent blade is as long as a
straight one and the field does not stretch in a gust.
"""

from extensions.vegetation.checks import require_between
from extensions.vegetation.noise import layered_noise, value_noise
from math.vector2 import Vector2
from std.math import cos, floor, pi, sin, sqrt
from units.si import (
    DEGREE,
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
    Velocity,
)

# How much longer a gust patch is across the wind than along it.
comptime GUST_STRETCH = Float32(1.8)
# How far a slow noise bends the gust fronts, in gust lengths: a front is
# a ragged curve, with Vs where it lags, and not a straight line.
comptime WARP = Float32(1.2)
# The smaller gusts: their size as a share of a gust's, the share of the
# gust field they make, and the cosine and sine of the angle at which they
# cross the large ones, 35 degrees.
comptime SMALL_GUST = Float32(0.55)
# How far a tree leans in a full gust, and how far it rocks, as shares of
# the wind's lean, and how many times a second it rocks.
comptime TREE_LEAN = Float32(0.025)
comptime TREE_ROCK = Float32(0.008)
comptime TREE_RATE = Float32(0.5)
# A crown's limbs and leaves in a wind of `CROWN_LEAN`: how far an outer
# twig swings with its limb and how many times a second, and how far a
# leaf flutters and how many times a second. A wind of another lean moves
# them in proportion.
comptime CROWN_LEAN = Float32(50)
comptime CROWN_REACH = Float32(0.3)
comptime CROWN_RATE = Float32(0.8)
comptime CROWN_FLUTTER = Float32(0.035)
comptime CROWN_FLUTTER_RATE = Float32(2.4)


@fieldwise_init
struct CrownMotion(ImplicitlyCopyable):
    """How the wind moves the limbs and the leaves of the crowns: what a
    vertex program needs to sway them."""

    # The unit direction the wind blows toward, as x and z.
    var downwind: Vector2
    # How far an outer twig swings with its limb, and how many times a
    # second.
    var reach: Length
    var rate: Frequency
    # How far a leaf flutters up and down, and how many times a second.
    var flutter: Length
    var flutter_rate: Frequency


comptime CROSS_SHARE = Float32(0.35)
comptime CROSS_COS = Float32(0.81915204)
comptime CROSS_SIN = Float32(0.57357644)
# The gust noise below the first of these is calm air, and above the
# second a full gust. The noise rarely leaves the middle of its range, so
# the edges are close together, and a gust front is sharp.
comptime GUST_LOW = Float32(0.39)
comptime GUST_HIGH = Float32(0.61)
# How much of a cycle the phases of the blades spread the sway: a little,
# so the sway stays one wave across a patch.
comptime SWAY_SPREAD = Float32(0.08)
# How far the side wobble of a flutter is, as a fraction of the flutter.
comptime SIDE_FLUTTER = Float32(0.6)
# How much of its double a sway's wave adds, so it snaps forward.
comptime SNAP = Float32(0.33)


struct Wind(ImplicitlyCopyable):
    """A steady wind with gusts that travel downwind, and a flutter."""

    # Which way the wind blows toward, turned from +x toward +z.
    var heading: Angle
    # How far a full gust bends a blade's tip from upright.
    var lean: Angle
    # The fraction of `lean` that the wind keeps between gusts, from zero
    # to one. One is a steady wind with no gusts.
    var calm: Float32
    # How long one gust patch is along the wind.
    var gust_length: Length
    # How fast the gust patches travel downwind.
    var gust_speed: Velocity
    # How far each blade wobbles on its own.
    var flutter: Angle
    # How many wobbles a second.
    var flutter_rate: Frequency
    # How far the sway swings a tip, how many swings a second, and how far
    # apart the crests of the sway are along the wind.
    var sway: Angle
    var sway_rate: Frequency
    var sway_length: Length
    # Which gust field to read.
    var seed: Int
    # How long the wind takes to repeat itself, or zero for a wind that
    # never repeats.
    var loop: Duration

    def __init__(
        out self,
        heading: Angle = Angle(-10.0, DEGREE),
        lean: Angle = Angle(50.0, DEGREE),
        calm: Float32 = 0.1,
        gust_length: Length = Length(8.0, METER),
        gust_speed: Velocity = Velocity(3.5, METER_PER_SECOND),
        flutter: Angle = Angle(1.0, DEGREE),
        flutter_rate: Frequency = Frequency(1.0, PER_SECOND),
        seed: Int = 7,
        loop: Duration = Duration(0.0, SECOND),
        sway: Angle = Angle(10.0, DEGREE),
        sway_rate: Frequency = Frequency(1.0, PER_SECOND),
        sway_length: Length = Length(6.0, METER),
    ) raises:
        """Create a wind and check it.

        Args:
            heading: Which way the wind blows toward, turned from +x toward
                +z. Any finite angle.
            lean: How far a full gust bends a tip, from 0 to 80 degrees.
            calm: The fraction of `lean` between gusts, from 0 to 1.
            gust_length: How long a gust patch is along the wind, from
                1 centimeter to 100 kilometers.
            gust_speed: How fast the gusts travel, from 0 to 100 meters a
                second.
            flutter: How far each blade wobbles, from 0 to 30 degrees.
            flutter_rate: How many wobbles a second, from 0 to 20.
            seed: Which gust field to read.
            loop: How long the wind takes to repeat itself, from 0 to
                100,000 seconds. Zero never repeats.
            sway: How far the sway swings a tip, from 0 to 45 degrees.
            sway_rate: How many swings a second, from 0 to 20.
            sway_length: How far apart its crests are, from 1 centimeter
                to 100 kilometers.

        Raises:
            Error: If `check` refuses a value.
        """
        self.heading = heading
        self.lean = lean
        self.calm = calm
        self.gust_length = gust_length
        self.gust_speed = gust_speed
        self.flutter = flutter
        self.flutter_rate = flutter_rate
        self.seed = seed
        self.loop = loop
        self.sway = sway
        self.sway_rate = sway_rate
        self.sway_length = sway_length
        self.check()

    def check(self) raises:
        """Refuse a value outside the range `__init__` names.

        Raises:
            Error: If a value is out of its range, or NaN.
        """
        require_between(
            self.heading.to(RADIAN),
            -1.0e6,
            1.0e6,
            "A wind heading must be finite",
        )
        require_between(
            self.lean.to(DEGREE),
            0,
            80,
            "A wind must lean a blade from 0 to 80 degrees",
        )
        require_between(
            self.calm, 0, 1, "The calm of a wind must be from 0 to 1"
        )
        require_between(
            self.gust_length.to(METER),
            0.01,
            1.0e5,
            "A gust must be from 1 centimeter to 100 kilometers long",
        )
        require_between(
            self.gust_speed.to(METER_PER_SECOND),
            0,
            100,
            "Gusts must travel from 0 to 100 meters a second",
        )
        require_between(
            self.flutter.to(DEGREE),
            0,
            30,
            "A flutter must be from 0 to 30 degrees",
        )
        require_between(
            self.flutter_rate.to(PER_SECOND),
            0,
            20,
            "A flutter must be from 0 to 20 wobbles a second",
        )
        require_between(
            self.loop.to(SECOND),
            0,
            1.0e5,
            "A wind's loop must be from 0 to 100,000 seconds",
        )
        require_between(
            self.sway.to(DEGREE), 0, 45, "A sway must be from 0 to 45 degrees"
        )
        require_between(
            self.sway_rate.to(PER_SECOND),
            0,
            20,
            "A sway must be from 0 to 20 swings a second",
        )
        require_between(
            self.sway_length.to(METER),
            0.01,
            1.0e5,
            "A sway's crests must be from 1 centimeter to 100 kilometers apart",
        )

    def _clock(self, time: Duration) -> Float32:
        """Return the time in seconds, wrapped into the loop if there is
        one."""
        var seconds = time.to(SECOND)
        var period = self.loop.to(SECOND)
        if period <= 0:
            return seconds
        return seconds - floor(seconds / period) * period

    def _field(self, x: Float32, z: Float32, seconds: Float32) -> Float32:
        """Return the raw gust noise at a point and a time in seconds."""
        var down = self.downwind()
        var length = self.gust_length.to(METER)
        var travel = self.gust_speed.to(METER_PER_SECOND) * seconds
        var forward = x * down.x + z * down.y - travel
        var sideways = z * down.x - x * down.y
        var along = forward / length
        var across = sideways / (length * GUST_STRETCH)
        var bent = value_noise(
            across * 1.3 + 4.1, along * 0.35 + 2.7, self.seed + 5
        )
        var main = layered_noise(along + WARP * (bent - 0.5), across, self.seed)
        # Smaller gusts cross the large ones at an angle, so the fronts
        # meet in Vs and break into patches.
        var small = length * SMALL_GUST
        var u = forward * CROSS_COS + sideways * CROSS_SIN
        var v = sideways * CROSS_COS - forward * CROSS_SIN
        var cross = layered_noise(u / small, v / (small * 1.4), self.seed + 11)
        return main * (1 - CROSS_SHARE) + cross * CROSS_SHARE

    def _rate(self, rate: Float32) -> Float32:
        """Return a rate a second: a whole number a loop when the wind
        loops, and at least one."""
        var period = self.loop.to(SECOND)
        if period <= 0:
            return rate
        return max(Float32(1), floor(rate * period + 0.5)) / period

    def downwind(self) -> Vector2:
        """Return the unit direction the wind blows toward, on the ground.

        Returns:
            The direction as x and z.
        """
        var h = self.heading.to(RADIAN)
        return Vector2(cos(h), sin(h))

    def gust(self, x: Float32, z: Float32, time: Duration) -> Float32:
        """Return how strong the gust is at a point, from zero to one.

        The pattern moves downwind at `gust_speed`: the gust at a point at
        time zero is the gust a distance `gust_speed * time` downwind at
        `time`. A looping wind fades that pattern into the one a loop
        earlier, so the gust at `loop` is the gust at zero.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.
            time: The time since the wind began.

        Returns:
            The gust strength. One is a full gust.
        """
        var seconds = self._clock(time)
        var raw = self._field(x, z, seconds)
        var period = self.loop.to(SECOND)
        if period > 0:
            var w = seconds / period
            var earlier = self._field(x, z, seconds - period)
            var weight = sqrt((1 - w) * (1 - w) + w * w)
            raw = 0.5 + ((1 - w) * (raw - 0.5) + w * (earlier - 0.5)) / weight
        var t = (raw - GUST_LOW) / (GUST_HIGH - GUST_LOW)
        t = min(Float32(1), max(Float32(0), t))
        return t * t * (3 - 2 * t)

    def tip_bend(
        self,
        x: Float32,
        z: Float32,
        gust: Float32,
        phase: Float32,
        time: Duration,
    ) -> Vector2:
        """Return how far a blade's tip turns from upright, and which way.

        The length of the result is the angle in radians. Its direction
        on the ground is the way the tip leans. A gust leans it downwind,
        the sway swings it along the wind, and the flutter adds a wobble
        along the wind and a smaller one across.

        The sway is a wave that rolls downwind. Its shape is a sine and a
        third of its double, so a tip snaps forward and springs back.

        Args:
            x: The blade root's x, in meters.
            z: The blade root's z, in meters.
            gust: The gust at the blade's root, from `gust`.
            phase: The blade's own phase, from zero to one. Blades of a
                tuft have phases close together, so the tuft sways as one.
            time: The time since the wind began.

        Returns:
            The tip's bend: x and z, in radians.
        """
        var down = self.downwind()
        var strength = self.calm + (1 - self.calm) * gust
        var turn = Float32(2) * Float32(pi)
        var seconds = self._clock(time)
        var crest = (x * down.x + z * down.y) / self.sway_length.to(METER)
        var swing = (
            turn * (self._rate(self.sway_rate.to(PER_SECOND)) * seconds - crest)
            + turn * SWAY_SPREAD * phase
        )
        var wave = sin(swing) + SNAP * sin(2 * swing + 0.5)
        var beat = turn * (
            self._rate(self.flutter_rate.to(PER_SECOND)) * seconds
        )
        var wobble = self.flutter.to(RADIAN)
        var flick = turn * phase * 7
        var along = (
            self.lean.to(RADIAN) * strength
            + self.sway.to(RADIAN) * (0.1 + 0.9 * gust) * wave
            + wobble * sin(beat + flick)
        )
        var side = wobble * SIDE_FLUTTER * cos(beat * 2 + flick * 1.3)
        return Vector2(
            down.x * along - down.y * side, down.y * along + down.x * side
        )

    def crown_motion(self) -> CrownMotion:
        """Return how this wind moves the limbs and the leaves of a crown.

        The swing and the flutter are `CROWN_REACH` and `CROWN_FLUTTER` in
        a wind of `CROWN_LEAN`, and in proportion to the lean in another.
        A looping wind swings them a whole number of times a loop. Still
        air moves nothing.

        Returns:
            The motion.
        """
        var share = self.lean.to(DEGREE) / CROWN_LEAN
        return CrownMotion(
            self.downwind(),
            Length(CROWN_REACH * share, METER),
            Frequency(self._rate(CROWN_RATE), PER_SECOND),
            Length(CROWN_FLUTTER * share, METER),
            Frequency(self._rate(CROWN_FLUTTER_RATE), PER_SECOND),
        )

    def tree_sway(
        self, x: Float32, z: Float32, phase: Float32, time: Duration
    ) -> Vector2:
        """Return how far a tree leans from its foot, and which way.

        A tree is stiff and heavy, so it leans little and slowly. A full
        gust leans it `TREE_LEAN` of the wind's `lean` downwind, and calm
        air `calm` of that. It also rocks by `TREE_ROCK` of the lean,
        `TREE_RATE` times a second. A looping wind rocks it a whole number
        of times a loop.

        Args:
            x: The tree's foot's x, in meters.
            z: The tree's foot's z, in meters.
            phase: The tree's own phase, from zero to one.
            time: The time since the wind began.

        Returns:
            The lean: x and z, in radians.
        """
        var down = self.downwind()
        var gust = self.gust(x, z, time)
        var swing = (
            Float32(2)
            * Float32(pi)
            * (self._rate(TREE_RATE) * self._clock(time) + phase)
        )
        var along = self.lean.to(RADIAN) * (
            TREE_LEAN * (self.calm + (1 - self.calm) * gust)
            + TREE_ROCK * sin(swing)
        )
        return Vector2(down.x * along, down.y * along)


def still_air() raises -> Wind:
    """Return a wind that bends nothing.

    Returns:
        A wind with no lean and no flutter.

    Raises:
        Error: Never; the values are in range.
    """
    return Wind(
        lean=Angle(0.0, DEGREE),
        calm=1.0,
        flutter=Angle(0.0, DEGREE),
        sway=Angle(0.0, DEGREE),
    )
