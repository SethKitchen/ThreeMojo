# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Missiles: the arrows, the spell bolts and the blast orbs that a fighter
sends.

A `Missile` flies by its velocity. Gravity pulls an arrow down, and a
spell turns toward its target as it flies: see `fly`. A missile strikes a
target when its last step passed within its reach of the target's chest:
see `touches`. A step is a line, so a fast arrow does not pass through a
target between two frames.

| Kind | Speed | Gravity | Turn | Reach | What it does where it strikes |
|---|---|---|---|---|---|
| `ARROW` | `ARROW_SPEED` | `ARROW_GRAVITY` | None | `ARROW_REACH` | Its blow; an aimed shot's passes on through `AIMED_PIERCE` more |
| `SPARK` | `SPARK_SPEED` | None | `SPARK_TURN` | `SPARK_REACH` | Its blow |
| `ORB` | `ORB_SPEED` | None | `ORB_TURN` | `ORB_REACH` | Its blow to each target within `ORB_SPLASH` |

A volley sends `VOLLEY_ARROWS` arrows in a fan of `VOLLEY_SPREAD`: see
`fan`. A rain of arrows sends `RAIN_ARROWS` arrows high, which fall on a
ring of `RAIN_RADIUS` around its target: see `rain_spots`. `lob` finds the
velocity that carries an arrow to a point.
"""

from core.ordinal import ordinal_valid
from extensions.village.combat import Blow
from math.vector3 import Vector3
from std.math import atan2, cos, pi, sin, sqrt

comptime ARROW_SPEED = Float32(42)
"""How fast an arrow flies, in meters a second."""
comptime ARROW_GRAVITY = Float32(4)
"""How fast an arrow falls faster, in meters a second each second."""
comptime ARROW_REACH = Float32(0.45)
"""How near a target's chest an arrow strikes, in meters."""
comptime ARROW_LIFE = Float32(1.4)
"""How long an arrow flies before it falls, in seconds."""
comptime SPARK_SPEED = Float32(24)
"""How fast a spell bolt flies, in meters a second."""
comptime SPARK_TURN = Float32(5)
"""How fast a spell bolt turns toward its target, in radians a second."""
comptime SPARK_REACH = Float32(0.55)
"""How near a target's chest a spell bolt strikes, in meters."""
comptime SPARK_LIFE = Float32(1.2)
"""How long a spell bolt flies before it fades, in seconds."""
comptime ORB_SPEED = Float32(13)
"""How fast a blast's orb flies, in meters a second."""
comptime ORB_TURN = Float32(2)
"""How fast a blast's orb turns toward its target, in radians a second."""
comptime ORB_REACH = Float32(0.7)
"""How near a target's chest a blast's orb strikes, in meters."""
comptime ORB_SPLASH = Float32(2.5)
"""How far from where it strikes a blast's orb bursts, in meters."""
comptime ORB_LIFE = Float32(2)
"""How long a blast's orb flies before it fades, in seconds."""
comptime AIMED_PIERCE = 2
"""How many more targets an aimed shot's arrow passes through after its
first."""
comptime VOLLEY_ARROWS = 5
"""How many arrows a volley sends."""
comptime VOLLEY_SPREAD = Float32(50)
"""The angle of a volley's fan, in degrees."""
comptime RAIN_ARROWS = 6
"""How many arrows a rain of arrows sends."""
comptime RAIN_RADIUS = Float32(1.6)
"""How far from its target a rain of arrows' ring is, in meters."""
comptime RAIN_HEIGHT = Float32(9)
"""How high over its target the first arrow of a rain starts, in
meters."""
comptime RAIN_SPEED = Float32(26)
"""How fast a rain's arrows fall, in meters a second."""
comptime MISSILE_KINDS = 3
"""How many kinds of missile there are."""


@fieldwise_init
struct MissileKind(Equatable, ImplicitlyCopyable, Writable):
    """What a missile is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the kinds.

        Returns:
            True for `ARROW`, `SPARK` and `ORB`.
        """
        return ordinal_valid(self.value, MISSILE_KINDS - 1)


comptime ARROW = MissileKind(0)
"""An arrow: it flies straight and falls a little."""
comptime SPARK = MissileKind(1)
"""A spell bolt: a quick spark that follows its target."""
comptime ORB = MissileKind(2)
"""A blast's orb: slow, and it bursts where it strikes."""


struct Missile(Copyable, Movable):
    """A missile in flight: where it is, how it flies, and what it does."""

    var kind: MissileKind
    # Where it is, and where it was before the last step.
    var at: Vector3
    var last: Vector3
    # How fast it flies, in meters a second.
    var velocity: Vector3
    # Where it was sent from: a guard faces this way.
    var origin: Vector3
    # The target it turns toward, or -1 for none.
    var target: Int
    # Who sent it: -1 for the player, else an ally's index.
    var owner: Int
    # What it does to each target it strikes.
    var blow: Blow
    # How many more targets it passes through after the next it strikes.
    var pierce: Int
    # The targets it struck, and how long it has flown, in seconds.
    var struck: List[Int]
    var age: Float32

    def __init__(
        out self,
        kind: MissileKind,
        at: Vector3,
        velocity: Vector3,
        target: Int,
        owner: Int,
        blow: Blow,
        pierce: Int = 0,
    ) raises:
        """Send a missile.

        Args:
            kind: What it is.
            at: Where it starts.
            velocity: How fast it flies, in meters a second.
            target: The target it turns toward, or -1 for none.
            owner: Who sent it: -1 for the player, else an ally's index.
            blow: What it does to each target it strikes.
            pierce: How many more targets it passes through after its
                first.

        Raises:
            Error: If the kind is not one, or the pierce is negative.
        """
        if not kind.is_valid():
            raise Error("A missile must be an arrow, a spark or an orb")
        if pierce < 0:
            raise Error("A missile's pierce must not be negative")
        self.kind = kind
        self.at = at
        self.last = at
        self.velocity = velocity
        self.origin = at
        self.target = target
        self.owner = owner
        self.blow = blow
        self.pierce = pierce
        self.struck = List[Int]()
        self.age = 0

    def reach(self) -> Float32:
        """Return how near a target's chest the missile strikes.

        Returns:
            `ARROW_REACH`, `SPARK_REACH` or `ORB_REACH`, in meters.
        """
        if self.kind == SPARK:
            return SPARK_REACH
        if self.kind == ORB:
            return ORB_REACH
        return ARROW_REACH

    def life(self) -> Float32:
        """Return how long the missile flies.

        Returns:
            `ARROW_LIFE`, `SPARK_LIFE` or `ORB_LIFE`, in seconds.
        """
        if self.kind == SPARK:
            return SPARK_LIFE
        if self.kind == ORB:
            return ORB_LIFE
        return ARROW_LIFE

    def splash(self) -> Float32:
        """Return how far from where it strikes the missile bursts.

        Returns:
            `ORB_SPLASH` for an orb, and zero for the others, in meters.
        """
        return ORB_SPLASH if self.kind == ORB else Float32(0)

    def spent(self) -> Bool:
        """Return whether the missile has flown its life.

        Returns:
            True after its life.
        """
        return self.age > self.life()

    def has_struck(self, target: Int) -> Bool:
        """Return whether the missile already struck a target.

        Args:
            target: The target.

        Returns:
            True if it is among the targets struck.
        """
        for index in self.struck:
            if index == target:
                return True
        return False


def turn_toward_point(
    velocity: Vector3, at: Vector3, aim: Vector3, most: Float32
) -> Vector3:
    """Return a velocity turned toward a point, at the same speed.

    Args:
        velocity: The velocity.
        at: Where the missile is.
        aim: The point it turns toward.
        most: How far it turns at most, in radians.

    Returns:
        The velocity turned by `most` toward the point, or onto it when it
        is nearer than that. The same velocity when it is still or at the
        point.
    """
    var speed = velocity.length()
    var off = aim - at
    var gap = off.length()
    if speed < 1.0e-6 or gap < 1.0e-6:
        return velocity
    var now = velocity / speed
    var want = off / gap
    var cosine = max(Float32(-1), min(Float32(1), now.dot(want)))
    var angle = atan2(sqrt(max(Float32(0), 1 - cosine * cosine)), cosine)
    if angle <= most:
        return want * speed
    # Mix the two ways so the turn is `most` along the arc between them.
    var t = most / angle
    var mixed = now * (1 - t) + want * t
    var size = mixed.length()
    if size < 1.0e-6:
        return velocity
    return mixed * (speed / size)


def fly(mut missile: Missile, h: Float32, aim: Optional[Vector3]):
    """Fly a missile on by one step.

    Args:
        missile: The missile.
        h: The step's time, in seconds.
        aim: Its target's chest, if it has one that stands.

    A spark or an orb turns toward the aim by its turn a second. An arrow
    falls by `ARROW_GRAVITY`.
    """
    missile.last = missile.at
    if aim:
        var turn = Float32(0)
        if missile.kind == SPARK:
            turn = SPARK_TURN
        elif missile.kind == ORB:
            turn = ORB_TURN
        if turn > 0:
            missile.velocity = turn_toward_point(
                missile.velocity, missile.at, aim.value(), turn * h
            )
    if missile.kind == ARROW:
        missile.velocity.y -= ARROW_GRAVITY * h
    missile.at = missile.at + missile.velocity * h
    missile.age += h


def segment_gap(a: Vector3, b: Vector3, point: Vector3) -> Float32:
    """Return how near a line from `a` to `b` passes a point.

    Args:
        a: The line's start.
        b: The line's end.
        point: The point.

    Returns:
        The distance from the point to the nearest point of the line, in
        meters.
    """
    var line = b - a
    var long = line.dot(line)
    if long < 1.0e-12:
        return (point - a).length()
    var t = max(Float32(0), min(Float32(1), (point - a).dot(line) / long))
    return (point - (a + line * t)).length()


def touches(missile: Missile, chest: Vector3) -> Bool:
    """Return whether a missile's last step passed a target's chest.

    Args:
        missile: The missile.
        chest: The target's chest.

    Returns:
        True when the step passed within the missile's reach of it.
    """
    return segment_gap(missile.last, missile.at, chest) <= missile.reach()


def fan(way: Vector3, count: Int, spread: Float32) raises -> List[Vector3]:
    """Return the ways of a fan of missiles around a way on the ground.

    Args:
        way: The fan's middle way. Its y is kept.
        count: How many ways, from 1 to 64.
        spread: The angle of the fan, in degrees, from 0 to 360.

    Returns:
        `count` ways turned evenly across the spread about the y axis, the
        middle one along `way`. One way is `way` itself.

    Raises:
        Error: If the count or the spread is out of range.
    """
    if not (count >= 1 and count <= 64):
        raise Error("A fan must have from 1 to 64 ways")
    if not (spread >= 0 and spread <= 360):
        raise Error("A fan's spread must be from 0 to 360 degrees")
    var out = List[Vector3]()
    if count == 1:
        out.append(way)
        return out^
    var step = spread / Float32(count - 1) * Float32(pi) / 180
    var first = -spread / 2 * Float32(pi) / 180
    for k in range(count):  # pragma: no branch
        var turn = first + step * Float32(k)
        var c = cos(turn)
        var s = sin(turn)
        out.append(
            Vector3(way.x * c + way.z * s, way.y, -way.x * s + way.z * c)
        )
    return out^


def rain_spots(center: Vector3, count: Int) raises -> List[Vector3]:
    """Return where the arrows of a rain start, high over a ring.

    Args:
        center: The rain's target, on the ground.
        count: How many arrows, from 1 to 64.

    Returns:
        The first over the center, the rest around a ring of `RAIN_RADIUS`,
        each `RAIN_HEIGHT` up and a meter higher than the one before it,
        so they fall one after another.

    Raises:
        Error: If the count is out of range.
    """
    if not (count >= 1 and count <= 64):
        raise Error("A rain must have from 1 to 64 arrows")
    var out = List[Vector3]()
    out.append(center + Vector3(0, RAIN_HEIGHT, 0))
    for k in range(1, count):
        var turn = Float32(2 * pi) * Float32(k - 1) / Float32(max(1, count - 1))
        out.append(
            center
            + Vector3(
                RAIN_RADIUS * cos(turn),
                RAIN_HEIGHT + Float32(k),
                RAIN_RADIUS * sin(turn),
            )
        )
    return out^


def lob(start: Vector3, end: Vector3, speed: Float32) raises -> Vector3:
    """Return the velocity that carries an arrow from one point to another.

    Args:
        start: Where the arrow starts.
        end: Where it must pass.
        speed: How fast it flies over the ground, in meters a second, above
            zero.

    Returns:
        A velocity of `speed` over the ground toward `end`, and an upward
        part that `ARROW_GRAVITY` brings down onto `end`'s height when it
        gets there. Straight up for a point over the start.

    Raises:
        Error: If the speed is not above zero.
    """
    if not (speed > 0):
        raise Error("An arrow's speed must be above zero")
    var dx = end.x - start.x
    var dz = end.z - start.z
    var gap = sqrt(dx * dx + dz * dz)
    if gap < 1.0e-4:
        return Vector3(0, speed, 0)
    var t = gap / speed
    var rise = (end.y - start.y + ARROW_GRAVITY * t * t / 2) / t
    return Vector3(dx / gap * speed, rise, dz / gap * speed)
