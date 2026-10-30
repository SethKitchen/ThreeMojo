# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's companion in a fight, as the party of Tales of Arise is: a
swordswoman who keeps back, casts bolts of light at the player's foe,
heals the player, and makes a boost attack when the player calls for it.

A `Companion` is her mind. `Companion.think` decides what she does, frame
by frame, from an `AllySight`:

1. **Out of a fight**, she follows the player. She walks to them when
   they are more than `FOLLOW` away, and runs when they are more than
   twice as far.
2. **In a fight**, she faces the player's foe and keeps `KEEP` meters from
   it, but never more than `LEASH` from the player. Every `CAST_EVERY`
   seconds, she casts a bolt at a foe within `CAST_RANGE`.
3. **She heals.** When the player's health falls below `MEND_BELOW` of
   its most, she heals `MEND_SHARE` of it. Then she waits `MEND_EVERY`
   seconds before she heals again.
4. **The boost gauge** fills by `BOOST_RATE` a second while the fight
   lasts, and by `BOOST_PER_HIT` for each bolt that lands. When it is
   full, the player can call for a boost attack: a bolt that no guard
   stops, and that breaks a burst attack. See `boost_blow`.

The foes do not attack her: she keeps out of their way. The game moves
her bolts: see `extensions.village.battle`.
"""

from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.village.clothes import CREAM_WOOL, WALNUT, WOAD, village_outfit
from extensions.village.combat import Blow, FighterParameters
from extensions.village.foes import Bandit
from math.vector3 import Vector3
from std.math import sqrt
from units.si import (
    DEGREE,
    INCH,
    METER_PER_SECOND,
    PER_SECOND,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
    Velocity,
)

comptime FOLLOW = Float32(3)
"""How far from the player the companion keeps out of a fight, in meters."""
comptime KEEP = Float32(6)
"""How far from the player's foe she keeps in a fight, in meters."""
comptime LEASH = Float32(10)
"""How far from the player she strays in a fight, at most, in meters."""
comptime CAST_RANGE = Float32(14)
"""How far she casts a bolt, in meters."""
comptime CAST_EVERY = Float32(2.6)
"""How long she waits between two casts, in seconds."""
comptime MEND_BELOW = Float32(0.4)
"""The share of the player's health below which she heals them."""
comptime MEND_SHARE = Float32(0.15)
"""The share of the player's health that her heal gives back."""
comptime MEND_EVERY = Float32(15)
"""How long she waits between two heals, in seconds."""
comptime BOOST_FULL = Float32(100)
"""How much the boost gauge holds."""
comptime BOOST_RATE = Float32(4)
"""How fast the boost gauge fills while the fight lasts, a second."""
comptime BOOST_PER_HIT = Float32(10)
"""How much each bolt that lands fills the boost gauge."""
comptime ALLY_X = Float32(1.5)
"""How far to the side of the player's start she starts, in meters."""
comptime ALLY_Z = Float32(1.5)
"""How far behind the player's start she starts, in meters."""


def _flat_gap(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def _toward(a: Vector3, b: Vector3) -> Vector3:
    """Return the way from one point to another on the ground, of length
    one, or +z when they meet."""
    var gap = _flat_gap(a, b)
    if gap < 1.0e-4:
        return Vector3(0, 0, 1)
    return Vector3((b.x - a.x) / gap, 0, (b.z - a.z) / gap)


@fieldwise_init
struct AllySight(ImplicitlyCopyable):
    """What the companion knows of the fight this frame."""

    # Where she and the player stand.
    var at: Vector3
    var player: Vector3
    # Where the foe she casts at stands, if there is one.
    var target: Optional[Vector3]
    # The share of its most that the player's health is.
    var health: Float32
    # Whether she makes no move, and whether the fight is on.
    var free: Bool
    var fighting: Bool


@fieldwise_init
struct AllyIntent(ImplicitlyCopyable):
    """What the companion means to do this frame."""

    # The way she walks, of length one or less; and whether she runs.
    var way: Vector3
    var run: Bool
    # The point she turns to face, if any.
    var face: Optional[Vector3]
    # Whether she casts a bolt, and whether she heals the player.
    var cast: Bool
    var heal: Bool


struct Companion(Copyable, Movable):
    """The companion's mind: her waits, and her boost gauge."""

    # How long until she can cast again, and heal again, in seconds.
    var cast_wait: Float32
    var mend_wait: Float32
    # How full the boost gauge is.
    var boost: Float32

    def __init__(out self):
        """Make a companion who can heal at once, casts after a second, and
        has an empty boost gauge."""
        self.cast_wait = 1
        self.mend_wait = 0
        self.boost = 0

    def charge(mut self, amount: Float32):
        """Fill the boost gauge, up to `BOOST_FULL`.

        Args:
            amount: How much.
        """
        self.boost = min(BOOST_FULL, self.boost + amount)

    def ready(self) -> Bool:
        """Return whether the boost gauge is full.

        Returns:
            True at `BOOST_FULL`.
        """
        return self.boost >= BOOST_FULL

    def spend(mut self) -> Bool:
        """Spend a full boost gauge on a boost attack.

        Returns:
            Whether the gauge was full. A full gauge empties, and the next
            plain cast waits `CAST_EVERY`.
        """
        if not self.ready():
            return False
        self.boost = 0
        self.cast_wait = CAST_EVERY
        return True

    def think(mut self, sight: AllySight, delta: Duration) -> AllyIntent:
        """Decide what to do this frame: see the module's steps.

        Args:
            sight: What she knows.
            delta: The frame's time.

        Returns:
            What she means to do.
        """
        var seconds = delta.to(SECOND)
        self.cast_wait = max(Float32(0), self.cast_wait - seconds)
        self.mend_wait = max(Float32(0), self.mend_wait - seconds)
        var out = AllyIntent(Vector3(0, 0, 0), False, None, False, False)
        var near = _flat_gap(sight.at, sight.player)
        var home = _toward(sight.at, sight.player)
        if sight.fighting:
            self.charge(BOOST_RATE * seconds)
        if sight.fighting and sight.target:
            var target = sight.target.value()
            var gap = _flat_gap(sight.at, target)
            var toward = _toward(sight.at, target)
            out.face = target
            if near > LEASH:
                out.way = home
                out.run = True
            elif gap < KEEP - 1:
                out.way = toward * -0.8
            elif gap > KEEP + 2:
                out.way = toward
                out.run = gap > KEEP + 6
            if sight.free and self.cast_wait <= 0 and gap <= CAST_RANGE:
                out.cast = True
                self.cast_wait = CAST_EVERY
        elif near > FOLLOW:
            out.way = home
            out.run = near > 2 * FOLLOW + 1
        var low = sight.health > 0 and sight.health < MEND_BELOW
        if sight.free and low and self.mend_wait <= 0:
            out.heal = True
            self.mend_wait = MEND_EVERY
        return out


def ally_fighter() -> FighterParameters:
    """Return how strong the companion is.

    Returns:
        400 health, 100 ki, no arte gauge, bolts of the cast's own
        strength, and no Over Limit. The foes do not attack her.
    """
    var p = FighterParameters()
    p.health = 400
    p.arte_points = 0
    p.arte_rate = Frequency(0.0, PER_SECOND)
    p.limit_gain = 0
    return p


def boost_blow(might: Float32) -> Blow:
    """Return what a boost attack's bolt does.

    Args:
        might: How many times its damage and ki damage the bolt does.

    Returns:
        70 damage and 50 ki damage, times the might; a push of 5 meters a
        second; and a blow that no guard stops, and that breaks a burst
        attack.
    """
    return Blow(
        70 * might,
        50 * might,
        Velocity(5.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
        False,
        True,
        True,
    )


def default_allies() raises -> List[Bandit]:
    """Return the companion of the default village.

    Returns:
        One swordswoman in woad blue and cream, who starts beside the
        player: `x` and `z` are her place from the player's start, to the
        side and behind. Her seed and her heading are not used.

    Raises:
        Error: Never: the outfit checks.
    """
    return [
        Bandit(
            HumanoidSpec(Length(66.0, INCH), FEMALE, TONED, random_genome(70)),
            village_outfit(WOAD, CREAM_WOOL, WALNUT, False),
            ALLY_X,
            ALLY_Z,
            Angle(0.0, DEGREE),
            70,
            ally_fighter(),
        )
    ]
