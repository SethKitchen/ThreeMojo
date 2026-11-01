# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A raid party: the allies who fight a boss beside the player, each in a
role.

A `PartyMind` decides what one member does, frame by frame, from a
`MemberSight`. In a game of many players, a player stands in each
member's place, and the mind stays out of it. Each `PartyRole` has its own
spot and its own way to fight:

| Role | Its style | Where it stands | What it does |
|---|---|---|---|
| `TANK` | The mace | `TANK_SPOT` before the boss | Taunts the boss when it fights another; guards a blow that a guard stops; strikes when the boss is open |
| `HEALER` | Magic | `HEALER_SPOT` behind the leader, away from the boss | Mends when a member falls below `MEND_BELOW`; else casts bolts at the boss; revives a fallen member |
| `STRIKER` | The axe | `STRIKER_SPOT` behind the boss | Strikes in chains of light attacks and a heavy attack |
| `ARCHER` | Archery | `ARCHER_SPOT` off the boss's flank | Shoots quick shots, and an aimed shot every third |

Every member steps out of a zone that winds up, and dodges out of it as
it is about to strike. A tank stays in a zone that its guard stops, and
guards. When a rockfall marks a member, every other member gathers on it,
so they share its damage: see `extensions.village.boss`. Out of the fight,
each member follows the leader, `FOLLOW_GAP` behind.
"""

from core.ordinal import ordinal_valid
from extensions.village.boss import CIRCLE, Zone, inside
from extensions.village.combat import (
    AIMED_SHOT,
    FREE,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MEND,
    QUICK_SHOT,
    SPELL_BOLT,
    CombatMove,
)
from extensions.village.styles import (
    ARCHERY,
    AXE,
    MACE,
    MAGIC,
    FightingStyle,
)
from math.vector3 import Vector3
from std.math import cos, sin, sqrt

comptime ROLES = 4
"""How many roles there are."""
comptime TANK_SPOT = Float32(2.8)
"""How far before the boss a tank stands, in meters."""
comptime STRIKER_SPOT = Float32(2.6)
"""How far behind the boss a striker stands, in meters."""
comptime ARCHER_SPOT = Float32(11)
"""How far from the boss an archer stands, in meters."""
comptime ARCHER_TURN = Float32(2.1)
"""How far around from the boss's front an archer stands, in radians."""
comptime HEALER_SPOT = Float32(5)
"""How far behind the leader, away from the boss, a healer stands, in
meters."""
comptime SPOT_NEAR = Float32(0.7)
"""How near its spot a member stops, in meters."""
comptime FOLLOW_GAP = Float32(3.5)
"""How far from the leader a member keeps out of a fight, in meters."""
comptime MEND_BELOW = Float32(0.6)
"""The share of a member's health below which a healer mends."""
comptime MEND_EVERY = Float32(7)
"""How long a healer waits between two mends, in seconds."""
comptime TAUNT_EVERY = Float32(8)
"""How long a tank waits between two taunts, in seconds."""
comptime DODGE_AT = Float32(0.8)
"""How far a zone has wound up when a member in it dodges, from 0 to 1."""
comptime ZONE_MARGIN = Float32(0.6)
"""How far past a zone's edge a member keeps, in meters."""
comptime STRIKE_EVERY = Float32(0.45)
"""How long a melee member waits between two presses of its chain, in
seconds."""
comptime SHOOT_EVERY = Float32(1.1)
"""How long an archer or a healer waits between two shots, in seconds."""


@fieldwise_init
struct PartyRole(Equatable, ImplicitlyCopyable, Writable):
    """What a member does in a party, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the roles.

        Returns:
            True from `TANK` to `ARCHER`.
        """
        return ordinal_valid(self.value, ROLES - 1)


comptime TANK = PartyRole(0)
"""Holds the boss's eye, and takes its blows on a guard."""
comptime HEALER = PartyRole(1)
"""Keeps the party alive."""
comptime STRIKER = PartyRole(2)
"""Strikes the boss from behind."""
comptime ARCHER = PartyRole(3)
"""Shoots the boss from afar."""


def role_name(role: PartyRole) raises -> String:
    """Return a role's name, in capitals for the display.

    Args:
        role: The role.

    Returns:
        "TANK", "HEALER", "STRIKER" or "ARCHER".

    Raises:
        Error: If the role is not one.
    """
    if not role.is_valid():
        raise Error("A party role must be one of the four")
    var names: List[String] = ["TANK", "HEALER", "STRIKER", "ARCHER"]
    return names[role.value]


def role_style(role: PartyRole) raises -> FightingStyle:
    """Return the style a role fights in.

    Args:
        role: The role.

    Returns:
        The mace for a tank, magic for a healer, the axe for a striker and
        archery for an archer.

    Raises:
        Error: If the role is not one.
    """
    if not role.is_valid():
        raise Error("A party role must be one of the four")
    var styles: List[FightingStyle] = [MACE, MAGIC, AXE, ARCHERY]
    return styles[role.value]


def _flat(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def _toward(a: Vector3, b: Vector3) -> Vector3:
    """Return the way from one point to another on the ground, of length
    one, or of no length when they meet."""
    var gap = _flat(a, b)
    if gap < 1.0e-4:
        return Vector3(0, 0, 0)
    return Vector3((b.x - a.x) / gap, 0, (b.z - a.z) / gap)


def escape(zone: Zone, at: Vector3) -> Vector3:
    """Return the shortest way out of a zone.

    Args:
        zone: The zone.
        at: Where the member stands.

    Returns:
        The way on the ground, of length one: away from a circle's middle,
        and across a cone's or a line's way, to the side the member stands
        on. A member right at a circle's middle steps along plus x.
    """
    if zone.shape == CIRCLE:
        var out = _toward(zone.at, at)
        if out.length() < 0.5:
            return Vector3(1, 0, 0)
        return out
    var dx = at.x - zone.at.x
    var dz = at.z - zone.at.z
    var side = dx * zone.way.z - dz * zone.way.x
    var sign = Float32(1) if side >= 0 else Float32(-1)
    return Vector3(zone.way.z * sign, 0, -zone.way.x * sign)


@fieldwise_init
struct MemberSight(Copyable, Movable):
    """What a party member knows of the fight this frame."""

    # Where it stands, and where the leader stands.
    var at: Vector3
    var leader: Vector3
    # Where the foe it fights stands, and the way that foe faces, if it
    # fights one.
    var target: Optional[Vector3]
    var facing: Vector3
    # The zone of an attack that winds up, how far it has wound up from 0
    # to 1, and whether a guard stops it.
    var danger: Optional[Zone]
    var warning: Float32
    var blockable: Bool
    # Where a rockfall will fall, if one is marked, and whether it marks
    # this member.
    var stack: Optional[Vector3]
    # The share of its most health the member has, and the most hurt
    # member's share and place, if any is below `MEND_BELOW`.
    var health: Float32
    var hurt: Optional[Vector3]
    # A fallen member to revive, if any.
    var fallen: Optional[Vector3]
    # Whether the member makes no move; whether the boss fights it; and
    # whether the fight is on.
    var free: Bool
    var targeted: Bool
    var fighting: Bool


@fieldwise_init
struct MemberIntent(ImplicitlyCopyable):
    """What a party member means to do this frame."""

    # The way it walks, of length one or less, and whether it runs.
    var way: Vector3
    var run: Bool
    # The point it turns to face, if any.
    var face: Optional[Vector3]
    # The move it asks for, or `FREE`; whether it guards; whether it
    # taunts; the way it dodges, of no length for none; and whether it
    # revives the fallen member near it.
    var attack: CombatMove
    var guard: Bool
    var taunt: Bool
    var dodge: Vector3
    var revive: Bool


def still_intent() -> MemberIntent:
    """Return the intent of a member who does nothing.

    Returns:
        No way, no face, no move, no guard, no taunt, no dodge and no
        revive.
    """
    return MemberIntent(
        Vector3(0, 0, 0),
        False,
        None,
        FREE,
        False,
        False,
        Vector3(0, 0, 0),
        False,
    )


struct PartyMind(Copyable, Movable):
    """One party member's mind: its role, its waits and its chain."""

    var role: PartyRole
    # How long until it presses again, taunts again and mends again, in
    # seconds.
    var wait: Float32
    var taunt_wait: Float32
    var mend_wait: Float32
    # How far it is through its chain of presses.
    var chain: Int

    def __init__(out self, role: PartyRole) raises:
        """Make a member's mind.

        Args:
            role: Its role.

        Raises:
            Error: If the role is not one.
        """
        if not role.is_valid():
            raise Error("A party role must be one of the four")
        self.role = role
        self.wait = 0.5
        self.taunt_wait = 0
        self.mend_wait = 0
        self.chain = 0

    def spot(self, sight: MemberSight) -> Vector3:
        """Return where the member stands in a fight.

        Args:
            sight: What it knows. It must fight a foe.

        Returns:
            Its role's spot around the foe, or behind the leader for a
            healer.
        """
        var foe = sight.target.value()
        if self.role == TANK:
            return foe + sight.facing * TANK_SPOT
        if self.role == STRIKER:
            return foe - sight.facing * STRIKER_SPOT
        if self.role == ARCHER:
            var c = cos(ARCHER_TURN)
            var s = sin(ARCHER_TURN)
            var f = sight.facing
            var way = Vector3(f.x * c - f.z * s, 0, f.x * s + f.z * c)
            return foe + way * ARCHER_SPOT
        var back = _toward(foe, sight.leader)
        if back.length() < 0.5:
            back = sight.facing
        return sight.leader + back * HEALER_SPOT

    def _press(mut self) -> CombatMove:
        """Return the next press of the member's chain."""
        var turn = self.chain
        self.chain += 1
        if self.role == TANK:
            var chain: List[CombatMove] = [LIGHT_ONE, LIGHT_TWO, HEAVY]
            return chain[turn % 3]
        if self.role == STRIKER:
            var chain: List[CombatMove] = [
                LIGHT_ONE,
                LIGHT_TWO,
                LIGHT_THREE,
                HEAVY,
            ]
            return chain[turn % 4]
        if self.role == ARCHER:
            return AIMED_SHOT if turn % 3 == 2 else QUICK_SHOT
        return SPELL_BOLT

    def think(mut self, sight: MemberSight, seconds: Float32) -> MemberIntent:
        """Decide what to do this frame: see the module's table.

        Args:
            sight: What it knows.
            seconds: The frame's time.

        Returns:
            What it means to do.
        """
        self.wait = max(Float32(0), self.wait - seconds)
        self.taunt_wait = max(Float32(0), self.taunt_wait - seconds)
        self.mend_wait = max(Float32(0), self.mend_wait - seconds)
        var out = still_intent()
        if not sight.fighting or not sight.target:
            var gap = _flat(sight.at, sight.leader)
            if gap > FOLLOW_GAP:
                out.way = _toward(sight.at, sight.leader)
                out.run = gap > 2 * FOLLOW_GAP
            if sight.fallen and self.role == HEALER:
                out.way = _toward(sight.at, sight.fallen.value())
                out.revive = _flat(sight.at, sight.fallen.value()) < 1.5
            return out
        var foe = sight.target.value()
        out.face = foe
        # Out of a zone first; a tank stays in one its guard stops.
        if sight.danger:
            var zone = sight.danger.value()
            var held = self.role == TANK and sight.blockable
            if inside(zone, sight.at, ZONE_MARGIN) and not held:
                var away = escape(zone, sight.at)
                out.way = away
                out.run = True
                if sight.warning >= DODGE_AT and sight.free:
                    out.dodge = away
                return out
            if held and inside(zone, sight.at, ZONE_MARGIN):
                out.guard = True
                return out
        if sight.stack:
            var there = sight.stack.value()
            if _flat(sight.at, there) > 1.2:
                out.way = _toward(sight.at, there)
                out.run = True
                return out
        if self.role == TANK and not sight.targeted and self.taunt_wait <= 0:
            out.taunt = True
            self.taunt_wait = TAUNT_EVERY
        if self.role == HEALER and sight.free and self.mend_wait <= 0:
            if sight.hurt:
                out.attack = MEND
                self.mend_wait = MEND_EVERY
                return out
        var spot = self.spot(sight)
        var off = _flat(sight.at, spot)
        if off > SPOT_NEAR:
            out.way = _toward(sight.at, spot)
            out.run = off > 3
            if self.role == TANK or self.role == STRIKER:
                return out
        if self.wait <= 0:
            out.attack = self._press()
            var ranged = self.role == ARCHER or self.role == HEALER
            self.wait = SHOOT_EVERY if ranged else STRIKE_EVERY
        return out
