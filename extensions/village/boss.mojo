# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A raid boss: a giant that a party must fight together.

A `Boss` is the encounter's rules, apart from the scene: its health, its
poise, its threat table, its phases and its attacks. The party is a list
of members: the player first, then the allies. `Boss.think` decides what
the boss does each frame from a `BossSight`, and gives back a `BossIntent`.
`Boss.receive` takes a member's blow.

**Attacks.** Each attack shows its `Zone` on the ground through its
wind-up, and strikes everything in it when the wind-up ends:

| Attack | Zone | Wind-up | Damage | A guard stops it |
|---|---|---|---|---|
| `CLEAVE` | A cone of `CLEAVE_ARC` and `CLEAVE_REACH` before the boss | 1.1 s | 180 | Yes |
| `SLAM` | A circle of `SLAM_RADIUS` on its target | 1.5 s | 260 | No |
| `STOMP` | A circle of `STOMP_RADIUS` all around the boss | 1.8 s | 150 | No |
| `CHARGE` | A line `CHARGE_LENGTH` long and `CHARGE_WIDTH` wide at a member | 1.4 s | 220 | No |
| `ROCKFALL` | A member is marked; after `ROCK_SECONDS`, a boulder falls on them | 4 s | 640, shared | No |
| `SUMMON` | None: it calls its den's wolves | 1.2 s | | |

**The rockfall** is shared: its damage is split evenly between each member
within `ROCK_RADIUS` of where it falls. One member alone takes all of it,
and falls; three or more each take a third or less. So the party must
gather on the marked member.

**Poise.** Each blow's stamina damage takes the boss's poise. The poise comes
back at `POISE_RATE` a second, `POISE_DELAY` after the last blow, so one
fighter cannot break it alone. When it breaks, the boss staggers for
`BOSS_STAGGER`, makes no attack, and each blow on it is critical.

**The linked strike.** Once in each stagger, a member within `LINK_RANGE`
can call a linked strike. Each standing member within `LINK_REACH` of the
boss strikes with them. `link_damage` gives its damage, which grows faster
than the count of members who join. So a party that strikes together does
more than its members could alone.

**Threat.** Each member's damage adds to its threat, times `TANK_THREAT`
for a tank, and each heal adds `HEAL_THREAT` of the health healed. The
boss turns to the member with the most threat, once that member has
`THREAT_SWITCH` times the threat of its target. A taunt gives the
taunter more threat than any other member has, and holds the boss on it
for `TAUNT_SECONDS`.

**Phases.** `phase_of` gives the phase from the boss's health: `OPENING`,
then `FURY` from `FURY_SHARE` and `LAST_STAND` from `LAST_SHARE`. Each phase
has its own rotation of attacks, and quicker wind-ups. The boss summons
its wolves as each later phase begins. After `ENRAGE_SECONDS` of the fight
it enrages: its attacks do `ENRAGE_POWER` times their damage, and wind up
twice as fast.

**Scaling.** A boss's health is `boss_health` for the size of its party,
so a party of five meets a boss of three times the health of one fighter's.
"""

from core.ordinal import ordinal_valid
from extensions.vegetation.noise import hash01
from extensions.village.combat import (
    CRITICAL,
    DEFEATED,
    HIT,
    IGNORED,
    STAMINA_BREAK,
    Blow,
    Struck,
)
from math.vector3 import Vector3
from std.math import atan2, pi, sqrt
from units.si import METER_PER_SECOND, Velocity

comptime BOSS_ATTACKS = 6
"""How many attacks a boss has."""
comptime ZONE_SHAPES = 3
"""How many shapes a zone can have."""
comptime BOSS_PHASES = 3
"""How many phases a boss fight has."""
comptime BOSS_HEALTH = Float32(4500)
"""A boss's health for a party of one."""
comptime PARTY_HEALTH = Float32(0.5)
"""The share of `BOSS_HEALTH` more each member past the first adds."""
comptime BOSS_POISE = Float32(700)
"""How much poise a boss has."""
comptime POISE_RATE = Float32(70)
"""How fast a boss's poise comes back, a second."""
comptime POISE_DELAY = Float32(1.5)
"""How long after the last blow a boss's poise comes back, in seconds."""
comptime POISE_SHARE = Float32(1)
"""How much of a blow's stamina damage the boss's poise loses."""
comptime BOSS_STAGGER = Float32(6)
"""How long a boss whose poise broke staggers, in seconds."""
comptime STAGGER_BONUS = Float32(1.5)
"""How many times its damage a blow on a staggered boss does."""
comptime LINK_RANGE = Float32(4.5)
"""How near a staggered boss a member must stand to call a linked strike,
in meters."""
comptime LINK_REACH = Float32(14)
"""How near the boss a member must stand to join a linked strike, in
meters."""
comptime LINK_DAMAGE = Float32(240)
"""Each member's share of a linked strike's damage, for one member."""
comptime LINK_GROWTH = Float32(0.25)
"""The share of `LINK_DAMAGE` that each member's share grows for each
member past the first."""
comptime TANK_THREAT = Float32(3)
"""How many times its damage a tank's blow adds to its threat."""
comptime HEAL_THREAT = Float32(0.5)
"""The share of the health healed that a heal adds to the healer's
threat."""
comptime THREAT_SWITCH = Float32(1.1)
"""How many times its target's threat a member needs to draw the boss."""
comptime TAUNT_SECONDS = Float32(4)
"""How long a taunt holds the boss on the taunter, in seconds."""
comptime FURY_SHARE = Float32(0.7)
"""The share of its health below which a boss is in its fury."""
comptime LAST_SHARE = Float32(0.35)
"""The share of its health below which a boss makes its last stand."""
comptime ENRAGE_SECONDS = Float32(300)
"""How long a fight lasts before the boss enrages, in seconds."""
comptime ENRAGE_POWER = Float32(3)
"""How many times their damage an enraged boss's attacks do."""
comptime CLEAVE_ARC = Float32(130)
"""The angle of a cleave's cone, in degrees."""
comptime CLEAVE_REACH = Float32(6.5)
"""How far a cleave reaches, in meters."""
comptime SLAM_RADIUS = Float32(3.5)
"""The radius of a slam's circle, in meters."""
comptime STOMP_RADIUS = Float32(7.5)
"""The radius of a stomp's circle around the boss, in meters."""
comptime CHARGE_LENGTH = Float32(18)
"""How long a charge's line is, in meters."""
comptime CHARGE_WIDTH = Float32(3)
"""How wide a charge's line is, in meters."""
comptime CHARGE_SPEED = Float32(16)
"""How fast a charging boss runs along its line, in meters a second."""
comptime ROCK_SECONDS = Float32(4)
"""How long after a member is marked the rockfall's boulder falls, in
seconds."""
comptime ROCK_RADIUS = Float32(3.5)
"""How near the boulder's fall a member shares its damage, in meters."""
comptime ROCK_DAMAGE = Float32(640)
"""The rockfall's damage, which its members share."""
comptime MELEE_RANGE = Float32(3.2)
"""How near its target a boss walks before it attacks, in meters."""
comptime AGGRO_RANGE = Float32(16)
"""How near a member must come to start the fight, in meters."""
comptime LEASH_RANGE = Float32(45)
"""How far from its home a boss follows the party, in meters."""
comptime BOSS_WALK = Float32(2.6)
"""How fast a boss walks to its target, in meters a second."""


@fieldwise_init
struct BossAttack(Equatable, ImplicitlyCopyable, Writable):
    """One of a boss's attacks, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the attacks.

        Returns:
            True from `CLEAVE` to `SUMMON`.
        """
        return ordinal_valid(self.value, BOSS_ATTACKS - 1)


comptime CLEAVE = BossAttack(0)
"""A wide swing of the boss's mace before it."""
comptime SLAM = BossAttack(1)
"""The mace brought down on its target."""
comptime STOMP = BossAttack(2)
"""A stamp that shakes the ground all around the boss."""
comptime CHARGE = BossAttack(3)
"""A run along a line at a member."""
comptime ROCKFALL = BossAttack(4)
"""A boulder called down on a marked member, whose damage the members near
share."""
comptime SUMMON = BossAttack(5)
"""A roar that calls the den's wolves."""


@fieldwise_init
struct ZoneShape(Equatable, ImplicitlyCopyable, Writable):
    """The shape of a zone on the ground, as a type rather than a bare
    int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the shapes.

        Returns:
            True for `CONE`, `CIRCLE` and `LINE`.
        """
        return ordinal_valid(self.value, ZONE_SHAPES - 1)


comptime CONE = ZoneShape(0)
"""A cone from a point, along a way."""
comptime CIRCLE = ZoneShape(1)
"""A circle around a point."""
comptime LINE = ZoneShape(2)
"""A band from a point, along a way."""


@fieldwise_init
struct BossPhase(Equatable, ImplicitlyCopyable, Writable):
    """How far a boss fight has gone, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the phases.

        Returns:
            True for `OPENING`, `FURY` and `LAST_STAND`.
        """
        return ordinal_valid(self.value, BOSS_PHASES - 1)


comptime OPENING = BossPhase(0)
"""The boss above `FURY_SHARE` of its health."""
comptime FURY = BossPhase(1)
"""The boss from `FURY_SHARE` of its health: quicker, and it summons."""
comptime LAST_STAND = BossPhase(2)
"""The boss from `LAST_SHARE` of its health: quicker still."""


@fieldwise_init
struct Zone(ImplicitlyCopyable):
    """An area on the ground that an attack strikes."""

    var shape: ZoneShape
    # The cone's tip, the circle's middle, or the line's start.
    var at: Vector3
    # The way the cone or the line goes, of length one, on the ground.
    var way: Vector3
    # The cone's or the circle's radius, or the line's length, in meters.
    var size: Float32
    # The cone's angle, in degrees, or the line's width, in meters.
    var span: Float32


def inside(zone: Zone, point: Vector3, margin: Float32 = 0) -> Bool:
    """Return whether a point on the ground lies in a zone.

    Args:
        zone: The zone.
        point: The point. Its y is not used.
        margin: How far past the zone's edge a point still counts, in
            meters: a fighter's radius.

    Returns:
        Whether the point lies within the zone, grown by the margin.
    """
    var dx = point.x - zone.at.x
    var dz = point.z - zone.at.z
    var gap = sqrt(dx * dx + dz * dz)
    if zone.shape == CIRCLE:
        return gap <= zone.size + margin
    if zone.shape == LINE:
        var along = dx * zone.way.x + dz * zone.way.z
        var across = abs(dx * zone.way.z - dz * zone.way.x)
        if along < -margin or along > zone.size + margin:
            return False
        return across <= zone.span / 2 + margin
    if gap > zone.size + margin:
        return False
    if gap < 1.0e-4:
        return True
    var cosine = (dx * zone.way.x + dz * zone.way.z) / gap
    var off = atan2(sqrt(max(Float32(0), 1 - cosine * cosine)), cosine)
    # The margin widens the cone by the angle it fills at the point.
    var widen = atan2(margin, gap)
    return off <= zone.span / 2 * Float32(pi) / 180 + widen


@fieldwise_init
struct AttackData(ImplicitlyCopyable):
    """How an attack goes: its wind-up, its strike and its recovery, and
    what it does."""

    # How long it winds up, and how long the boss takes to recover after
    # it strikes, in seconds, before the phase quickens it.
    var windup: Float32
    var recovery: Float32
    # The damage to each member it strikes, and whether a guard stops it.
    var damage: Float32
    var unblockable: Bool
    # How fast it throws a member it strikes, in meters a second.
    var knockback: Float32


def attack_data(attack: BossAttack) raises -> AttackData:
    """Return how an attack goes: see the module's table.

    Args:
        attack: The attack.

    Returns:
        Its wind-up, recovery, damage, whether a guard stops it, and its
        push.

    Raises:
        Error: If the attack is not one.
    """
    if attack == CLEAVE:
        return AttackData(1.1, 0.9, 180, False, 6)
    if attack == SLAM:
        return AttackData(1.5, 1.1, 260, True, 7)
    if attack == STOMP:
        return AttackData(1.8, 1.0, 150, True, 9)
    if attack == CHARGE:
        return AttackData(1.4, 1.2, 220, True, 10)
    if attack == ROCKFALL:
        return AttackData(ROCK_SECONDS, 0.6, ROCK_DAMAGE, True, 3)
    if attack == SUMMON:
        return AttackData(1.2, 0.8, 0, True, 0)
    raise Error("A boss's attack must be one of the six")


def attack_name(attack: BossAttack) raises -> String:
    """Return an attack's name, in capitals for the display.

    Args:
        attack: The attack.

    Returns:
        "CLEAVE", "SLAM", "STOMP", "CHARGE", "ROCKFALL" or "SUMMON".

    Raises:
        Error: If the attack is not one.
    """
    if not attack.is_valid():
        raise Error("A boss's attack must be one of the six")
    var names: List[String] = [
        "CLEAVE",
        "SLAM",
        "STOMP",
        "CHARGE",
        "ROCKFALL",
        "SUMMON",
    ]
    return names[attack.value]


def phase_of(share: Float32) -> BossPhase:
    """Return a boss fight's phase from the boss's health.

    Args:
        share: The share of its most health the boss has.

    Returns:
        `OPENING` above `FURY_SHARE`, `FURY` above `LAST_SHARE`, and
        `LAST_STAND` at or below it.
    """
    if share > FURY_SHARE:
        return OPENING
    if share > LAST_SHARE:
        return FURY
    return LAST_STAND


def phase_pace(phase: BossPhase) -> Float32:
    """Return how many times their time a phase's wind-ups take.

    Args:
        phase: The phase.

    Returns:
        1 in the opening, 0.85 in the fury and 0.7 in the last stand.
    """
    if phase == FURY:
        return 0.85
    if phase == LAST_STAND:
        return 0.7
    return 1


def rotation(phase: BossPhase) -> List[BossAttack]:
    """Return the attacks a phase makes, in turn.

    Args:
        phase: The phase.

    Returns:
        Five attacks in the opening, six in the fury and seven in the last
        stand. Each phase has a rockfall.
    """
    if phase == FURY:
        return [SLAM, CLEAVE, ROCKFALL, CHARGE, STOMP, CLEAVE]
    if phase == LAST_STAND:
        return [STOMP, SLAM, ROCKFALL, CHARGE, CLEAVE, STOMP, SLAM]
    return [CLEAVE, SLAM, CLEAVE, ROCKFALL, STOMP]


def boss_health(members: Int) raises -> Float32:
    """Return a boss's health for the size of its party.

    Args:
        members: How many fight it, from 1 to 40.

    Returns:
        `BOSS_HEALTH`, and `PARTY_HEALTH` of it more for each member past
        the first.

    Raises:
        Error: If the party is empty or larger than 40.
    """
    if not (members >= 1 and members <= 40):
        raise Error("A boss's party must have from 1 to 40 members")
    return BOSS_HEALTH * (1 + PARTY_HEALTH * Float32(members - 1))


def link_damage(members: Int) raises -> Float32:
    """Return the damage of a linked strike.

    Args:
        members: How many members strike together, from 1 to 40.

    Returns:
        `LINK_DAMAGE` for each member, and `LINK_GROWTH` of each share more
        for each member past the first: 240 for one, 2,400 for five.

    Raises:
        Error: If no member strikes, or more than 40 do.
    """
    if not (members >= 1 and members <= 40):
        raise Error("A linked strike must have from 1 to 40 members")
    var count = Float32(members)
    return LINK_DAMAGE * count * (1 + LINK_GROWTH * (count - 1))


def share_rockfall(
    at: Vector3, members: List[Vector3], up: List[Bool]
) -> List[Float32]:
    """Return the damage of a rockfall to each member.

    Args:
        at: Where the boulder falls.
        members: Where each member stands.
        up: Whether each member stands, and is not fallen.

    Returns:
        `ROCK_DAMAGE` split evenly between each standing member within
        `ROCK_RADIUS` of the fall, and zero for the others.
    """
    var near = List[Bool]()
    var count = 0
    for k in range(len(members)):
        var dx = members[k].x - at.x
        var dz = members[k].z - at.z
        var close = up[k] and dx * dx + dz * dz <= ROCK_RADIUS * ROCK_RADIUS
        near.append(close)
        if close:
            count += 1
    var out = List[Float32]()
    for k in range(len(members)):
        if near[k]:
            out.append(ROCK_DAMAGE / Float32(count))
        else:
            out.append(0)
    return out^


@fieldwise_init
struct BossSight(Copyable, Movable):
    """What a boss knows of the fight this frame."""

    # Where the boss stands, the way it faces, and its home.
    var at: Vector3
    var heading: Vector3
    var home: Vector3
    # Where each member stands, and whether each stands.
    var members: List[Vector3]
    var up: List[Bool]


@fieldwise_init
struct BossIntent(Copyable, Movable):
    """What a boss means to do this frame."""

    # The way it walks, of length one or less, and the point it faces.
    var way: Vector3
    var face: Optional[Vector3]
    # Whether its attack strikes this frame, and the zone it strikes.
    var strikes: Bool
    var zone: Zone
    # The rockfall's damage to each member, as it falls; empty otherwise.
    var rock: List[Float32]
    # Whether it calls its wolves, and whether it runs along a charge.
    var summon: Bool
    var charging: Bool


struct Boss(Copyable, Movable):
    """A raid boss's health, poise, threat table and attack."""

    var health: Float32
    var most: Float32
    var poise: Float32
    # How long since a blow last took its poise, and how long it still
    # staggers, in seconds.
    var poise_rest: Float32
    var staggered: Float32
    # Whether a linked strike has struck in this stagger.
    var linked: Bool
    # Each member's threat, the member it fights, and how long a taunt
    # still holds it, in seconds.
    var threat: List[Float32]
    var target: Int
    var taunted: Float32
    # Whether the fight is on, and how long it has lasted, in seconds.
    var engaged: Bool
    var fight_time: Float32
    var phase: BossPhase
    # The attack it makes, or -1 for none; how far into it it is, in
    # seconds; its zone; and the place in its phase's rotation.
    var attack: BossAttack
    var clock: Float32
    var zone: Zone
    var turn: Int
    # The member a rockfall marks, or -1, and how long until it falls.
    var marked: Int
    var mark_clock: Float32
    # Whether it has summoned in its fury and in its last stand.
    var summoned: List[Bool]
    # The seed of its dice.
    var seed: Int
    var rolls: Int

    def __init__(out self, members: Int, seed: Int) raises:
        """Make a boss for a party, at full health, out of the fight.

        Args:
            members: How many members its party has, from 1 to 40.
            seed: The seed of its dice.

        Raises:
            Error: If the party is empty or larger than 40.
        """
        self.most = boss_health(members)
        self.health = self.most
        self.poise = BOSS_POISE
        self.poise_rest = 0
        self.staggered = 0
        self.linked = False
        self.threat = List[Float32](length=members, fill=0)
        self.target = 0
        self.taunted = 0
        self.engaged = False
        self.fight_time = 0
        self.phase = OPENING
        self.attack = BossAttack(-1)
        self.clock = 0
        self.zone = Zone(CIRCLE, Vector3(0, 0, 0), Vector3(0, 0, 1), 0, 0)
        self.turn = 0
        self.marked = -1
        self.mark_clock = 0
        self.summoned = [False, False]
        self.seed = seed
        self.rolls = 0

    def defeated(self) -> Bool:
        """Return whether the boss has fallen.

        Returns:
            True with no health left.
        """
        return self.health <= 0

    def enraged(self) -> Bool:
        """Return whether the boss has enraged.

        Returns:
            True once the fight has lasted `ENRAGE_SECONDS`.
        """
        return self.fight_time >= ENRAGE_SECONDS

    def pace(self) -> Float32:
        """Return how many times their time the boss's wind-ups take.

        Returns:
            The phase's pace, halved when it is enraged.
        """
        var pace = phase_pace(self.phase)
        if self.enraged():
            pace *= 0.5
        return pace

    def power(self) -> Float32:
        """Return how many times their damage the boss's attacks do.

        Returns:
            `ENRAGE_POWER` when it is enraged, and 1 before.
        """
        return ENRAGE_POWER if self.enraged() else Float32(1)

    def busy(self) -> Bool:
        """Return whether the boss makes an attack.

        Returns:
            True while an attack winds up, strikes or recovers.
        """
        return self.attack.is_valid()

    def windup(self) raises -> Float32:
        """Return how long the boss's attack winds up, at its pace.

        Returns:
            The attack's wind-up, in seconds, or zero with no attack.

        Raises:
            Error: Never: the attack is one.
        """
        if not self.busy():
            return 0
        return attack_data(self.attack).windup * self.pace()

    def warning(self) raises -> Float32:
        """Return how far the boss's attack has wound up, for its zone.

        Returns:
            From 0 as it begins to 1 as it strikes; zero with no attack,
            and after it strikes.

        Raises:
            Error: Never: the attack is one.
        """
        var wind = self.windup()
        if wind <= 0 or self.clock >= wind:
            return 0
        return self.clock / wind

    def roll(mut self) -> Float32:
        """Roll the boss's dice.

        Returns:
            A number from 0 to 1, the same for the same seed and roll.
        """
        self.rolls += 1
        return hash01(self.seed, self.rolls, 37)

    def add_threat(mut self, member: Int, amount: Float32) raises:
        """Add to a member's threat.

        Args:
            member: The member.
            amount: How much, zero or more.

        Raises:
            Error: If there is no such member, or the amount is negative.
        """
        if not (member >= 0 and member < len(self.threat)):
            raise Error("A boss's party has no such member")
        if amount < 0:
            raise Error("A threat must not be negative")
        self.threat[member] += amount
        self.engaged = True

    def taunt(mut self, member: Int) raises:
        """Taunt the boss: it turns to the taunter, and stays on it.

        Args:
            member: The member who taunts.

        Raises:
            Error: If there is no such member.
        """
        if not (member >= 0 and member < len(self.threat)):
            raise Error("A boss's party has no such member")
        var most = Float32(0)
        for value in self.threat:  # pragma: no branch
            most = max(most, value)
        self.threat[member] = most * THREAT_SWITCH + 50
        self.target = member
        self.taunted = TAUNT_SECONDS
        self.engaged = True

    def pick_target(mut self, up: List[Bool]):
        """Turn to the member with the most threat, once it has
        `THREAT_SWITCH` times the target's, or to any standing member when
        the target falls. A taunt holds the target.

        Args:
            up: Whether each member stands.
        """
        var lost = not up[self.target]
        if self.taunted > 0 and not lost:
            return
        var best = -1
        var most = Float32(-1)
        for k in range(len(self.threat)):  # pragma: no branch
            if up[k] and self.threat[k] > most:
                most = self.threat[k]
                best = k
        if best < 0:
            return
        if lost or most > self.threat[self.target] * THREAT_SWITCH:
            self.target = best

    def receive(mut self, blow: Blow, member: Int, tank: Bool) raises -> Struck:
        """Take a member's blow.

        Args:
            blow: The blow.
            member: The member who struck it.
            tank: Whether the member is a tank, whose blows draw more
                threat.

        Returns:
            What the blow did: `CRITICAL` on a staggered boss, which does
            `STAGGER_BONUS` times its damage; `STAMINA_BREAK` as its poise
            breaks; `DEFEATED` as it falls; `IGNORED` once it has fallen;
            and `HIT` for any other.

        Raises:
            Error: If there is no such member.
        """
        if not (member >= 0 and member < len(self.threat)):
            raise Error("A boss's party has no such member")
        if self.defeated():
            return Struck(IGNORED, 0, 0)
        var damage = blow.damage
        var critical = self.staggered > 0
        if critical:
            damage *= STAGGER_BONUS
        self.add_threat(member, damage * (TANK_THREAT if tank else 1))
        self.health -= damage
        if self.health <= 0:
            self.health = 0
            self.attack = BossAttack(-1)
            self.marked = -1
            return Struck(DEFEATED, damage, 0)
        if critical:
            return Struck(CRITICAL, damage, 0)
        var lost = blow.stamina_damage * POISE_SHARE
        self.poise -= lost
        self.poise_rest = 0
        if self.poise <= 0:
            self.poise = 0
            self.staggered = BOSS_STAGGER
            self.linked = False
            self.attack = BossAttack(-1)
            return Struck(STAMINA_BREAK, damage, lost)
        return Struck(HIT, damage, lost)

    def link_ready(self) -> Bool:
        """Return whether the party can make a linked strike on the boss.

        Returns:
            True while it staggers, until a linked strike strikes.
        """
        return self.staggered > 0 and not self.linked and not self.defeated()

    def link(mut self, members: List[Int]) raises -> Struck:
        """Take a linked strike: the members strike together, once in each
        stagger. Each member's share of the damage adds to its threat.

        Args:
            members: The members who strike, each once; the first calls it.

        Returns:
            `CRITICAL` with its `link_damage`; `DEFEATED` as the boss falls;
            and `IGNORED` while no linked strike can strike.

        Raises:
            Error: If no member strikes, or there is no such member, or a
                member strikes twice.
        """
        if len(members) == 0:
            raise Error("A linked strike must have a member")
        for k in range(len(members)):  # pragma: no branch
            var member = members[k]
            if not (member >= 0 and member < len(self.threat)):
                raise Error("A boss's party has no such member")
            for j in range(k):
                if members[j] == member:
                    raise Error("A member strikes a linked strike once")
        if not self.link_ready():
            return Struck(IGNORED, 0, 0)
        var damage = link_damage(len(members))
        self.linked = True
        for member in members:  # pragma: no branch
            self.add_threat(member, damage / Float32(len(members)))
        self.health -= damage
        if self.health <= 0:
            self.health = 0
            self.attack = BossAttack(-1)
            self.marked = -1
            return Struck(DEFEATED, damage, 0)
        return Struck(CRITICAL, damage, 0)

    def healed(mut self, member: Int, amount: Float32) raises:
        """Learn that a member healed: its heal adds to its threat.

        Args:
            member: The member who healed.
            amount: The health healed.

        Raises:
            Error: If there is no such member, or the amount is negative.
        """
        if self.engaged:
            self.add_threat(member, amount * HEAL_THREAT)

    def _begin(mut self, attack: BossAttack, sight: BossSight) raises:
        """Start an attack, and lay its zone."""
        self.attack = attack
        self.clock = 0
        var target = sight.members[self.target]
        var way = target - sight.at
        way.y = 0
        var gap = way.length()
        way = way / gap if gap > 1.0e-4 else sight.heading
        if attack == CLEAVE:
            self.zone = Zone(CONE, sight.at, way, CLEAVE_REACH, CLEAVE_ARC)
        elif attack == SLAM:
            self.zone = Zone(CIRCLE, target, way, SLAM_RADIUS, 0)
        elif attack == STOMP:
            self.zone = Zone(CIRCLE, sight.at, way, STOMP_RADIUS, 0)
        elif attack == CHARGE:
            self.zone = Zone(LINE, sight.at, way, CHARGE_LENGTH, CHARGE_WIDTH)
        elif attack == ROCKFALL:
            # The rockfall marks a member at random, other than the target
            # when it can.
            var pick = Int(self.roll() * Float32(len(sight.members)))
            pick = min(pick, len(sight.members) - 1)
            if not sight.up[pick] or (
                pick == self.target and len(sight.members) > 1
            ):
                pick = (pick + 1) % len(sight.members)
            if not sight.up[pick]:
                pick = self.target
            self.marked = pick
            self.mark_clock = attack_data(ROCKFALL).windup * self.pace()
            self.zone = Zone(CIRCLE, sight.members[pick], way, ROCK_RADIUS, 0)
        else:
            self.zone = Zone(CIRCLE, sight.at, way, 0, 0)

    def _next_attack(mut self) -> BossAttack:
        """Return the next attack of the phase's rotation."""
        var turns = rotation(self.phase)
        var attack = turns[self.turn % len(turns)]
        self.turn += 1
        return attack

    def think(
        mut self, sight: BossSight, seconds: Float32
    ) raises -> BossIntent:
        """Decide what the boss does this frame.

        Out of the fight, it stands at home until a member comes within
        `AGGRO_RANGE`, or strikes it. In the fight, it turns to its target
        and walks to it, and makes the attacks of its phase's rotation in
        turn. As a later phase begins, it summons first. A staggered boss
        makes no attack. A boss whose party has all fallen, or that is led
        further than `LEASH_RANGE` from home, goes home, and heals.

        Args:
            sight: What it knows.
            seconds: The frame's time.

        Returns:
            What it means to do.

        Raises:
            Error: If the time is negative, or the sight's lists are not one
                for each member.
        """
        if seconds < 0:
            raise Error("A frame's time must not be negative")
        var count = len(self.threat)
        if len(sight.members) != count or len(sight.up) != count:
            raise Error("A boss's sight must have one place for each member")
        var out = BossIntent(
            Vector3(0, 0, 0),
            None,
            False,
            self.zone,
            List[Float32](),
            False,
            False,
        )
        if self.defeated():
            return out^
        var anyone = False
        var near = False
        for k in range(count):  # pragma: no branch
            if not sight.up[k]:
                continue
            anyone = True
            var dx = sight.members[k].x - sight.at.x
            var dz = sight.members[k].z - sight.at.z
            if dx * dx + dz * dz <= AGGRO_RANGE * AGGRO_RANGE:
                near = True
        var hx = sight.at.x - sight.home.x
        var hz = sight.at.z - sight.home.z
        var far = hx * hx + hz * hz > LEASH_RANGE * LEASH_RANGE
        if not anyone or far:
            self._reset()
            var home = sight.home - sight.at
            home.y = 0
            if home.length() > 0.5:
                out.way = home / home.length()
            return out^
        if near:
            self.engaged = True
        if not self.engaged:
            return out^
        self.fight_time += seconds
        self.taunted = max(Float32(0), self.taunted - seconds)
        self.poise_rest += seconds
        if self.poise_rest >= POISE_DELAY:
            self.poise = min(BOSS_POISE, self.poise + POISE_RATE * seconds)
        if self.staggered > 0:
            self.staggered = max(Float32(0), self.staggered - seconds)
            if self.staggered == 0:
                self.poise = BOSS_POISE
            return out^
        self.pick_target(sight.up)
        self.phase = phase_of(self.health / self.most)
        ref goal = sight.members[self.target]
        out.face = goal
        # The marked member's boulder falls on them where they stand.
        if self.marked >= 0:
            self.mark_clock -= seconds
            self.zone.at = sight.members[self.marked]
            if self.attack == ROCKFALL:
                out.zone = self.zone
            if self.mark_clock <= 0:
                out.rock = share_rockfall(
                    sight.members[self.marked], sight.members, sight.up
                )
                for k in range(len(out.rock)):  # pragma: no branch
                    out.rock[k] *= self.power()
                self.marked = -1
        if not self.busy():
            var later = self.phase.value - 1
            if later >= 0 and not self.summoned[later]:
                self.summoned[later] = True
                self._begin(SUMMON, sight)
                return out^
            var dx = goal.x - sight.at.x
            var dz = goal.z - sight.at.z
            var gap = sqrt(dx * dx + dz * dz)
            var next = rotation(self.phase)[
                self.turn % len(rotation(self.phase))
            ]
            var ranged = next == CHARGE or next == ROCKFALL
            if gap > MELEE_RANGE and not ranged:
                out.way = Vector3(dx / gap, 0, dz / gap)
                return out^
            self._begin(self._next_attack(), sight)
            out.zone = self.zone
            return out^
        var data = attack_data(self.attack)
        var wind = data.windup * self.pace()
        var before = self.clock
        self.clock += seconds
        out.zone = self.zone
        if self.attack == CHARGE and self.clock >= wind:
            out.charging = self.clock < wind + CHARGE_LENGTH / CHARGE_SPEED
        if before < wind and self.clock >= wind:
            if self.attack == SUMMON:
                out.summon = True
            elif self.attack != ROCKFALL:
                out.strikes = True
        if self.attack == ROCKFALL and self.clock >= 0.6 * self.pace():
            # The boss calls the boulder down, and fights on while it falls.
            self.attack = BossAttack(-1)
            return out^
        var done = wind + data.recovery * self.pace()
        if self.attack == CHARGE:
            done += CHARGE_LENGTH / CHARGE_SPEED
        if self.clock >= done:
            self.attack = BossAttack(-1)
        return out^

    def _reset(mut self):
        """Leave the fight: full health and poise, no threat, no attack."""
        self.health = self.most
        self.poise = BOSS_POISE
        self.staggered = 0
        self.linked = False
        for k in range(len(self.threat)):  # pragma: no branch
            self.threat[k] = 0
        self.target = 0
        self.taunted = 0
        self.engaged = False
        self.fight_time = 0
        self.phase = OPENING
        self.attack = BossAttack(-1)
        self.turn = 0
        self.marked = -1
        self.summoned = [False, False]

    def attack_blow(self) raises -> Blow:
        """Return the blow of the boss's attack, for each member it
        strikes.

        Returns:
            The attack's damage times the boss's power, a third of it as
            stamina damage, the attack's push, and a blow that no guard
            stops for an attack that a guard does not stop.

        Raises:
            Error: If the boss makes no attack.
        """
        if not self.busy():
            raise Error("A boss that makes no attack strikes no blow")
        var data = attack_data(self.attack)
        var damage = data.damage * self.power()
        return Blow(
            damage,
            damage / 3,
            Velocity(data.knockback, METER_PER_SECOND),
            Velocity(0.0, METER_PER_SECOND),
            unblockable=data.unblockable,
        )


def rock_blow(damage: Float32) -> Blow:
    """Return a rockfall's blow, for a member who shares it.

    Args:
        damage: The member's share of the damage.

    Returns:
        The damage, a third of it as stamina damage, a push of 3 meters a
        second, and a blow that no guard stops.
    """
    return Blow(
        damage,
        damage / 3,
        Velocity(3.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
        unblockable=True,
    )
