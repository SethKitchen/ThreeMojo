# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's raid: the Stone Warden, a giant who keeps a ring of
standing stones, and the raiders who wait there for a leader.

`RaidParameters` says where the arena is, who the warden is, and who the
raiders are. `Warden` is the giant in the scene: its character, its
`Boss`, and a puppet `Fighter` whose move picks the clip its body plays.
`Member` is a raider in the scene: its character, its fighter and its
`PartyMind`. See `extensions.village.boss` and `extensions.village.party`;
`extensions.village.battle` runs the fight.

The raiders wait at the stones until the player comes within
`JOIN_RANGE`. Then they join the player's party, and follow and fight
beside them. They go back to the stones when the player is further than
`PART_RANGE` from them.

| Who | Role | Health | Stamina | Might |
|---|---|---|---|---|
| A shieldwoman in nettle green | `TANK` | 900 | 150 | 0.7 |
| A priest in cream | `HEALER` | 420 | 90 | 0.6 |
| An axeman in weld yellow | `STRIKER` | 520 | 110 | 0.85 |
| A huntress in walnut brown | `ARCHER` | 450 | 100 | 0.8 |

The warden is 2.5 meters tall, drawn `WARDEN_SIZE` times larger, in gray
wool, with a mace. Its body plays the mace's clips at its attacks' pace:
see `puppet_move`.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.village.boss import (
    CHARGE,
    CLEAVE,
    ROCKFALL,
    SLAM,
    STOMP,
    SUMMON,
    Boss,
    BossAttack,
    attack_data,
)
from extensions.village.character import Character
from extensions.village.clothes import (
    CREAM_WOOL,
    GRAY_WOOL,
    NETTLE,
    WALNUT,
    WELD,
    WOAD,
    village_outfit,
)
from extensions.village.combat import (
    CAST,
    FALL,
    FREE,
    GROUND_WAVE,
    HEAVY,
    MEND,
    PIERCE,
    PLUNGE,
    STAGGER,
    WHIRLWIND,
    CombatMove,
    Fighter,
    FighterParameters,
    move_data,
)
from extensions.village.party import (
    ARCHER,
    HEALER,
    STRIKER,
    TANK,
    PartyMind,
    PartyRole,
)
from extensions.village.sheet import Sheet
from extensions.village.surfaces import HouseLooks
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, pi, sin
from units.si import (
    DEGREE,
    INCH,
    METER,
    PER_SECOND,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
)

comptime WARDEN_SIZE = Float32(1.45)
"""How many times larger than its body the warden is drawn."""
comptime WARDEN_RADIUS = Float32(0.95)
"""The circle the warden takes up on the ground, in meters."""
comptime JOIN_RANGE = Float32(30)
"""How near the stones the player must come for the raiders to join, in
meters."""
comptime PART_RANGE = Float32(60)
"""How far from the stones the player goes before the raiders go back, in
meters."""
comptime STONES = 9
"""How many standing stones ring the arena."""
comptime RING_RADIUS = Float32(17)
"""How far from the arena's middle the stones stand, in meters."""
comptime REVIVE_SECONDS = Float32(2.5)
"""How long a member must stand by a fallen member to revive it, in
seconds."""
comptime REVIVE_SHARE = Float32(0.4)
"""The share of its health a revived member stands up with."""
comptime RISE_SECONDS = Float32(10)
"""How long a fallen member lies after the fight ends before it stands
up by itself, in seconds."""


@fieldwise_init
struct Raider(Copyable, Movable):
    """A raider: who they are, what they wear, and their role."""

    var spec: HumanoidSpec
    var outfit: Outfit
    var role: PartyRole
    # Their place at the stones, from the arena's middle, in meters.
    var x: Float32
    var z: Float32


struct RaidParameters(Copyable, Movable):
    """Where the arena is, who its warden is, and who waits there."""

    # The arena's middle, in meters, and the way the warden faces.
    var x: Float32
    var z: Float32
    var heading: Angle
    # The warden's body and clothes, and the seed of its dice.
    var spec: HumanoidSpec
    var outfit: Outfit
    var seed: Int
    var raiders: List[Raider]

    def __init__(out self) raises:
        """Hold the default village's raid: the Stone Warden in a ring of
        stones 30 meters behind the start, and its four raiders: see the
        module's table.

        Raises:
            Error: Never: the outfits check.
        """
        self.x = 24
        self.z = 62
        self.heading = Angle(180.0, DEGREE)
        self.spec = HumanoidSpec(
            Length(98.0, INCH), MALE, TONED, random_genome(91)
        )
        self.outfit = village_outfit(GRAY_WOOL, WALNUT, GRAY_WOOL, True)
        self.seed = 91
        self.raiders = [
            Raider(
                HumanoidSpec(
                    Length(68.0, INCH), FEMALE, TONED, random_genome(92)
                ),
                village_outfit(NETTLE, WELD, WALNUT, False),
                TANK,
                -6,
                -20,
            ),
            Raider(
                HumanoidSpec(
                    Length(69.0, INCH), MALE, TONED, random_genome(93)
                ),
                village_outfit(CREAM_WOOL, WOAD, CREAM_WOOL, True),
                HEALER,
                -3,
                -21,
            ),
            Raider(
                HumanoidSpec(
                    Length(72.0, INCH), MALE, TONED, random_genome(94)
                ),
                village_outfit(WELD, WALNUT, GRAY_WOOL, False),
                STRIKER,
                0,
                -21,
            ),
            Raider(
                HumanoidSpec(
                    Length(66.0, INCH), FEMALE, TONED, random_genome(95)
                ),
                village_outfit(WALNUT, NETTLE, WALNUT, True),
                ARCHER,
                3,
                -20,
            ),
        ]

    def check(self) raises:
        """Refuse a raid that cannot be held.

        Raises:
            Error: If there are more than 8 raiders, or a raider's role is
                not one.
        """
        if len(self.raiders) > 8:
            raise Error("A raid holds at most 8 raiders")
        for raider in self.raiders:
            if not raider.role.is_valid():
                raise Error("A raider's role must be one of the four")


def member_fighter(role: PartyRole) raises -> FighterParameters:
    """Return how strong a raider of a role is: see the module's table.

    Args:
        role: The role.

    Returns:
        The raider's strength. A tank's guard parries for half the player's
        window; the others' guards do not parry. No raider surges.

    Raises:
        Error: If the role is not one.
    """
    if not role.is_valid():
        raise Error("A party role must be one of the four")
    var p = FighterParameters()
    p.limit_gain = 0
    p.parry = Duration(0.0, SECOND)
    if role == TANK:
        p.health = 900
        p.stamina = 150
        p.stamina_rate = Frequency(40.0, PER_SECOND)
        p.might = 0.7
        p.parry = Duration(0.08, SECOND)
    elif role == HEALER:
        p.health = 420
        p.stamina = 90
        p.might = 0.6
    elif role == STRIKER:
        p.health = 520
        p.stamina = 110
        p.might = 0.85
    else:
        p.health = 450
        p.stamina = 100
        p.might = 0.8
    return p


def puppet_move(boss: Boss) raises -> Tuple[CombatMove, Float32, Float32]:
    """Return the move whose clip the warden's body plays, how far into it
    it is, and its pace.

    Args:
        boss: The warden's rules.

    Returns:
        `FALL` once it falls; `STAGGER` while it staggers, paced to last
        the stagger; for an attack, its clip: `HEAVY` for a cleave, `PLUNGE`
        for a slam, `GROUND_WAVE` for a stomp, `PIERCE` for a charge,
        `CAST` for a rockfall and `MEND` for a summon, paced so the clip
        strikes as the attack does;
        else `FREE`. The clock is in the clip's own seconds times the pace.

    Raises:
        Error: Never: each move is one.
    """
    if boss.defeated():
        return (FALL, Float32(0), Float32(1))
    if boss.staggered > 0:
        var length = move_data(STAGGER).recovery.to(SECOND)
        var pace = Float32(6) / length
        return (STAGGER, pace * length - boss.staggered, pace)
    if not boss.busy():
        return (FREE, Float32(0), Float32(1))
    var move = CAST
    if boss.attack == CLEAVE:
        move = HEAVY
    elif boss.attack == SLAM:
        move = PLUNGE
    elif boss.attack == STOMP:
        move = GROUND_WAVE
    elif boss.attack == CHARGE:
        move = PIERCE
    elif boss.attack == SUMMON:
        move = MEND
    var data = move_data(move)
    var strike = data.startup.to(SECOND) + data.active.to(SECOND) * 0.5
    var pace = max(Float32(0.2), boss.windup() / strike)
    return (move, boss.clock, pace)


def add_stones(
    mut scene: Scene,
    mut assets: Assets,
    looks: HouseLooks,
    center: Vector3,
    ground: List[Float32],
) raises -> NodeId:
    """Ring an arena with standing stones.

    Args:
        scene: The scene.
        assets: The stores for the stones' geometry.
        looks: The village's materials: the stones are fieldstone.
        center: The arena's middle.
        ground: The ground's height at each stone, `STONES` of them.

    Returns:
        The node the stones hang from.

    Raises:
        Error: If there is not one height for each stone, or the mesh
            cannot be added.
    """
    if len(ground) != STONES:
        raise Error("An arena needs the ground's height at each stone")
    var sheet = Sheet(1)
    for k in range(STONES):  # pragma: no branch
        var turn = Float32(2 * pi) * Float32(k) / Float32(STONES)
        var outward = Vector3(cos(turn), 0, sin(turn))
        var side = Vector3(-outward.z, 0, outward.x)
        var tall = Float32(2.2) + Float32(0.6) * sin(Float32(k) * 2.3)
        var at = center + outward * RING_RADIUS
        at.y = ground[k] + tall / 2 - 0.2
        # Each stone leans a little, outward from the ring.
        var lean = outward * (0.08 * tall)
        var up = Vector3(0, tall / 2, 0) + lean
        var tint = Float32(0.85) + Float32(0.1) * sin(Float32(k) * 1.7)
        sheet.box(
            at - center,
            side * 0.45,
            outward * 0.32,
            up,
            Vector3(tint, tint, tint),
        )
    var holder = Object3D()
    holder.set_position(center.x, center.y, center.z)
    var node = scene.add(holder^)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sheet.geometry()),
            looks.fieldstone,
            node,
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    return node


def stone_places(center: Vector3) -> List[Vector3]:
    """Return where each standing stone stands.

    Args:
        center: The arena's middle.

    Returns:
        `STONES` points on a ring of `RING_RADIUS`, their y the center's.
    """
    var out = List[Vector3]()
    for k in range(STONES):  # pragma: no branch
        var turn = Float32(2 * pi) * Float32(k) / Float32(STONES)
        out.append(center + Vector3(cos(turn), 0, sin(turn)) * RING_RADIUS)
    return out^


@fieldwise_init
struct Warden(Movable):
    """The warden in the scene: its character, its rules, the puppet whose
    move picks its clip, and where its looks are."""

    var character: Character
    var boss: Boss
    var puppet: Fighter
    # Its home, and the way it faces there.
    var home: Vector3
    var heading: Angle
    # Its looks' index in the battle's `people`.
    var look: Int
    # How long it has lain fallen, in seconds, or -1 while it stands.
    var down: Float32


@fieldwise_init
struct Member(Movable):
    """A raider in the scene: its character, its fighter and its mind."""

    var character: Character
    var fighter: Fighter
    var mind: PartyMind
    # Its place at the stones, and its looks' index in the battle's
    # `people`.
    var post: Vector3
    var look: Int
    # Whether it has joined the player's party; how long it has lain
    # fallen, in seconds, or -1; and how far a revive of it has gone, in
    # seconds.
    var joined: Bool
    var down: Float32
    var revive: Float32
    # How fast a blow pushes it, in meters a second; and the way its dodge
    # goes.
    var shove: Vector3
    var dodge_way: Vector3
