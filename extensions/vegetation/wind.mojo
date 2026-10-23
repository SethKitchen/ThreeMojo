# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wind over a field: gusts that travel, and a flutter of each blade.

**How a meadow moves.** Wind over tall grass is seen as waves of light
that sweep across the field. A gust bends the blades it reaches, and a
bent blade shows more of its lit face. So the motion has two scales:

- A gust is a patch of stronger wind, meters wide. The patches travel
  downwind at `gust_speed`. Every blade under a patch bends together,
  which gives the sweep. `gust` is value noise read in a frame that moves
  with the wind, stretched across the wind so a gust front is a band.
- A flutter is the fast wobble of each blade on its own, a few degrees.
  Each blade has its own phase, so neighbors do not move in step.

**Why a bend is an angle.** `tip_bend` returns how far the tip turns from
upright, as an angle along the ground, and not a distance. The blade is
built segment by segment, and each segment turns by its share of that
angle. The segments keep their length, so a bent blade is as long as a
straight one and the field does not stretch in a gust.
"""

from extensions.vegetation.checks import require_between
from extensions.vegetation.noise import layered_noise
from math.vector2 import Vector2
from std.math import cos, pi, sin
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
comptime GUST_STRETCH = Float32(1.6)
# How far the side wobble of a flutter is, as a fraction of the flutter.
comptime SIDE_FLUTTER = Float32(0.6)


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
    # Which gust field to read.
    var seed: Int

    def __init__(
        out self,
        heading: Angle = Angle(25.0, DEGREE),
        lean: Angle = Angle(45.0, DEGREE),
        calm: Float32 = 0.15,
        gust_length: Length = Length(6.0, METER),
        gust_speed: Velocity = Velocity(4.5, METER_PER_SECOND),
        flutter: Angle = Angle(8.0, DEGREE),
        flutter_rate: Frequency = Frequency(1.6, PER_SECOND),
        seed: Int = 7,
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
        `time`.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.
            time: The time since the wind began.

        Returns:
            The gust strength. One is a full gust.
        """
        var down = self.downwind()
        var length = self.gust_length.to(METER)
        var travel = self.gust_speed.to(METER_PER_SECOND) * time.to(SECOND)
        var along = (x * down.x + z * down.y - travel) / length
        var across = (z * down.x - x * down.y) / (length * GUST_STRETCH)
        var raw = layered_noise(along, across, self.seed)
        var t = (raw - 0.25) / 0.55
        t = min(Float32(1), max(Float32(0), t))
        return t * t * (3 - 2 * t)

    def tip_bend(
        self, gust: Float32, phase: Float32, time: Duration
    ) -> Vector2:
        """Return how far a blade's tip turns from upright, and which way.

        The length of the result is the angle in radians. Its direction
        on the ground is the way the tip leans. A gust leans it downwind.
        The flutter adds a wobble along the wind and a smaller one across.

        Args:
            gust: The gust at the blade's root, from `gust`.
            phase: The blade's own phase, from zero to one.
            time: The time since the wind began.

        Returns:
            The tip's bend: x and z, in radians.
        """
        var down = self.downwind()
        var strength = self.calm + (1 - self.calm) * gust
        var turn = Float32(2) * Float32(pi)
        var beat = turn * (self.flutter_rate.to(PER_SECOND) * time.to(SECOND))
        var wobble = self.flutter.to(RADIAN)
        var along = self.lean.to(RADIAN) * strength + wobble * sin(
            beat + turn * phase
        )
        var side = wobble * SIDE_FLUTTER * cos(beat * 1.7 + turn * phase * 1.3)
        return Vector2(
            down.x * along - down.y * side, down.y * along + down.x * side
        )


def still_air() raises -> Wind:
    """Return a wind that bends nothing.

    Returns:
        A wind with no lean and no flutter.

    Raises:
        Error: Never; the values are in range.
    """
    return Wind(lean=Angle(0.0, DEGREE), calm=1.0, flutter=Angle(0.0, DEGREE))
