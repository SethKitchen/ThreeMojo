# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Swordplay in the village: the player and a companion against bandits,
wolves and straw dummies.

`Battle.tick` runs the fight for one frame, in place of the player's own
step and pose:

1. **Presses.** A new press of a button asks the player's `Fighter` for a
   move in its fighting style: a light attack, the heavy attack, a special,
   or a dodge. See `style_move`. An attack pressed on the beat does
   `BEAT_BONUS` times its damage: see `extensions.village.combos`. Each
   press of the light or the heavy attack, the dodge, the jump or the guard
   adds a key to the combo string; when the string ends in a combo the
   player knows, its finisher starts at the combo's power, free of its
   special points. A jump cuts an attack's recovery short. The swap button
   takes up the next style the player carries, and the book button shows
   the combo book. A ground
   wave's cut sends a wave that runs along the ground at `WAVE_SPEED`
   for `WAVE_RANGE`, and strikes each target it passes over once. In a
   surge, the ultimate's buttons spend it on the ultimate. A dodge
   needs the sword drawn, since its button also runs. The guard button
   guards while it is held, and a new press of it makes a stamina recovery. A
   stance button changes the stance. The lock button locks the camera on
   the foe or the dummy nearest the middle of the view, or lets go. While
   it locks, a flick of the look stick moves the lock to the next target
   that way. The heal button eats one of the satchel's herbs, and heals
   `HEAL_SHARE` of the player's health.
2. **The player moves.** A free player walks, runs, sprints and jumps as
   before, at `GUARD_PACE` of the stick while guarding. A player locked on
   a target faces it, and strafes around it. A sprint spends
   `SPRINT_COST` stamina a second; a player with none left runs until
   they have `SPRINT_REST` again. A hard landing shakes the camera. An
   attack carries the player along their heading, and turns them
   toward what they aim at through its start-up: the locked target, else
   the nearest within `AIM_RANGE` before them, else the stick. In the
   air, the heavy attack's button makes the plunge, which dives at
   `PLUNGE_SPEED`. A dodge
   goes the way of the stick, or back. The push of a blow carries the
   player too, and fades at `SHOVE_FADE`.
3. **The foes think and move**, and so does the companion: see
   `extensions.village.foes` and `extensions.village.companion`. The
   thrower keeps back and throws knives, which fly at `KNIFE_SPEED`
   along the way they were thrown. The companion casts at the locked
   foe, else at the nearest foe that fights
   within `ALLY_SEEK` of the player. Her bolts fly at `BOLT_SPEED`, and
   follow their foe. The assist button calls for her assist attack when its
   gauge is full. Each foe goes for the nearest of the player and the
   raiders who stand with them: see `quarries`. One foe at a time holds
   the attack token, which is for the player alone. A bandit plays its sword's clips; a
   wolf shows the pose of its walk, and lies on its side when it falls.
   A perfect dodge slows the foes to `SLOW_SHARE` of the time for
   `SLOW_SECONDS`, and an ultimate for `ULTIMATE_SLOW`. In magic or
   archery, an ultimate also drops a star of light or a rain of arrows on
   each target within `STORM_RANGE`.
4. **The blows.** In steps of at most `COMBAT_STEP`, each fighter's clock
   runs, and each swing gives its blow to the fighters that it reaches.
   The player's spells and arrows fly as `Missile`s from the hand, at the
   locked target, else the nearest within `SHOT_RANGE` and `SHOT_ARC`
   before them; each strikes the targets it passes: see
   `extensions.village.missiles`. A mend heals the player and each ally
   within `MEND_RADIUS` by `MEND_HEAL` of their health. A
   blow that lands pushes its fighter away, and the rising edge throws it
   up; a blow on a fighter in the air keeps it up. A guarded blow pushes
   it back `BLOCK_PUSH` as far.
5. **What shows.** Each blow writes its damage over the fighter it lands
   on, and the outcome's word: see `outcome_word`. A blow that lands
   bursts in sparks. A foe that begins to rage shows `RAGE`. Each
   swing's trail is measured for the display: see
   `extensions.village.slashes`. In a surge, the player's trails are
   gold, and the note says when it begins. A plunge's landing rings the
   ground with light. The sword is drawn while a bandit within `ENGAGE`
   fights, or the player fights, and is sheathed `CALM_SECONDS` after.
6. **The weight of a blow.** A strong blow stops the whole fight for
   `HIT_STOP`, as action games freeze a frame on a heavy hit, and shakes
   the camera by `SHAKE`: see `strong_blow`. A finisher or a pierce
   break stops it for `FINISH_STOP`, and shakes it twice as far. The shake dies away at
   `SHAKE_FADE`.
7. **The raid.** The Stone Warden keeps a ring of stones, and its raiders
   join the player's party as the player comes near: see
   `extensions.village.raid`. The warden thinks by its `Boss`, walks to its
   target, lays each attack's zone on the ground, and strikes every member
   in the zone as the wind-up ends; its rockfall's damage is shared by the
   members near it; its summon calls the den's wolves. Each raider thinks
   by its `PartyMind`, and fights by its style. The taunt button holds the
   warden on the player, once every `TAUNT_EVERY`. A member who stands by a
   fallen raider for `REVIVE_SECONDS`, holding the use button, revives it.
   Near a staggered warden, the heavy button calls a linked strike: each
   standing raider near it strikes with the player, once in each stagger.
8. **The fallen.** A fallen bandit gives `LOOT` coins, and one time in
   two an herb. It lies for the
   `linger`, then is gone, and comes back to its post after the
   `respawn`. A fallen player comes to at the start after the `revive`.
"""

from controls.third_person_controls import (
    ThirdPersonControls,
    ground_direction,
    turn_toward,
    wrap_angle,
    yaw_of,
)
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.vegetation.ground import Lot, lot_openness
from extensions.village.arms import Arms
from extensions.village.blade import BRIGHT_STEEL, DULL_IRON, SwordLooks
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
)
from extensions.village.combat import (
    STAMINA_BREAK,
    AIMED_SHOT,
    ARROW_RAIN,
    HEAVY_BUTTON,
    LEAP_SHOT,
    LIGHT_BUTTON,
    MEND,
    QUICK_SHOT,
    RISING_BUTTON,
    SPELL_BLAST,
    SPELL_BOLT,
    ULTIMATE_BUTTON,
    VOLLEY,
    WAVE_BUTTON,
    WHIRLWIND_BUTTON,
    FightButton,
    is_shot,
    is_special,
    style_move,
    PIERCE_BREAK,
    CAST,
    DEFEATED,
    GROUND_WAVE,
    REACH_HEIGHT,
    FINISHED,
    HIT,
    DODGE,
    FREE,
    GUARD_BREAK,
    BLOCKED,
    HEAVY,
    HIGH_STANCE,
    LOW_STANCE,
    MID_STANCE,
    ULTIMATE,
    PARRIED,
    PLUNGE,
    PERFECT_DODGE,
    RISING_EDGE,
    WHIRLWIND,
    THROW,
    Blow,
    CombatMove,
    CombatStance,
    CRITICAL,
    Fighter,
    FighterParameters,
    Struck,
    faces,
    is_attack,
    landed_blow,
    move_data,
    move_name,
    outcome_word,
    reaches,
)
from extensions.animals.options import CROWD
from extensions.animals.registry import WOLF
from extensions.village.combos import (
    BEAT_BONUS,
    DODGE_KEY,
    GUARD_KEY,
    HEAVY_KEY,
    JUMP_KEY,
    LAND_MASTERY,
    LIGHT_KEY,
    MAKE_MASTERY,
    MASTERED_SPECIAL,
    MAX_RANK,
    PRACTICED_RANK,
    BLEED,
    CHAIN,
    DRAIN,
    LAUNCH,
    MARK,
    NO_EFFECT,
    SHOCKWAVE,
    SUNDER,
    ComboBook,
    ComboEffect,
    ComboKey,
    ComboTracker,
    effect_name,
    on_beat,
)
from extensions.village.missiles import (
    AIMED_PIERCE,
    ARROW,
    ARROW_SPEED,
    ORB,
    ORB_SPEED,
    RAIN_ARROWS,
    RAIN_SPEED,
    SPARK,
    SPARK_SPEED,
    VOLLEY_ARROWS,
    VOLLEY_SPREAD,
    Missile,
    fan,
    fly,
    lob,
    rain_spots,
    touches,
)
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    STYLES,
    SWORD,
    FightingStyle,
    is_melee,
    style_name,
)
from extensions.village.boss import (
    BOSS_POISE,
    CHARGE_SPEED,
    LINK_RANGE,
    LINK_REACH,
    BossSight,
    inside,
    rock_blow,
)
from extensions.village.party import (
    HEALER,
    MEND_BELOW,
    TANK,
    TAUNT_EVERY,
    MemberSight,
    PartyMind,
    role_style,
)
from extensions.village.raid import (
    JOIN_RANGE,
    PART_RANGE,
    REVIVE_SECONDS,
    REVIVE_SHARE,
    RISE_SECONDS,
    STONES,
    WARDEN_RADIUS,
    WARDEN_SIZE,
    Member,
    RaidParameters,
    Warden,
    add_stones,
    member_fighter,
    puppet_move,
    stone_places,
)
from extensions.village.boss import Boss, BOSS_WALK
from extensions.village.companion import (
    ASSIST_PER_HIT,
    AllySight,
    Companion,
    MEND_SHARE,
    assist_blow,
    default_allies,
)
from extensions.village.foes import (
    POSTED,
    RETURNING,
    WOLF_RUN,
    Bandit,
    Brain,
    DUMMY_RADIUS,
    Den,
    Dummy,
    Post,
    Sight,
    default_bandits,
    default_dens,
    default_posts,
    den_places,
    dummy_fighter,
)
from extensions.village.hud import GOLD_TEXT, WHITE_TEXT, Rgb
from extensions.village.residents import (
    Body,
    Flipbook,
    animal_look,
    animal_paints,
    facing_turn,
)
from extensions.village.skills import (
    BLOW_EXPERIENCE,
    DEFEAT_EXPERIENCE,
    PRACTICE_EXPERIENCE,
)
from extensions.village.slashes import (
    FOE_TRAIL,
    OVER_TRAIL,
    PLAYER_TRAIL,
    Sparks,
    Trail,
    slash_material,
)
from extensions.village.surfaces import HouseLooks
from extensions.village.terrain import Terrain
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import ceil, cos, exp, sin, sqrt
from units.si import (
    DEGREE,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)

comptime COMBAT_STEP = Float32(1.0 / 60.0)
"""The longest step of the fighters' clocks, in seconds."""
comptime GUARD_PACE = Float32(0.4)
"""The share of the stick a guarding fighter walks at."""
comptime SLOW_SECONDS = Float32(0.7)
"""How long a perfect dodge slows the foes, in seconds."""
comptime SLOW_SHARE = Float32(0.3)
"""The share of the time the foes move at while they are slowed."""
comptime ULTIMATE_SLOW = Float32(2.1)
"""How long an ultimate slows the foes, in seconds: all through it."""
comptime LAUNCH_SPEED = Float32(7)
"""How fast a launching finisher throws its foe up, in meters a second."""
comptime SUNDER_POISE = Float32(300)
"""How much poise a sundering finisher takes from a boss."""
comptime BLEED_SECONDS = Float32(4)
"""How long a finisher's wound bleeds, in seconds."""
comptime BLEED_SHARE = Float32(0.6)
"""The share of its finisher's damage that a wound bleeds, all told."""
comptime BLEED_TICK = Float32(0.5)
"""How often a wound's bleeding shows as a number, in seconds."""
comptime DRAIN_SHARE = Float32(0.35)
"""The share of its damage that a draining finisher heals the player by."""
comptime SHOCK_RADIUS = Float32(3.5)
"""How near its foe a shockwave strikes the other targets, in meters."""
comptime SHOCK_SHARE = Float32(0.5)
"""The share of its finisher's blow that a shockwave strikes with."""
comptime CHAIN_RANGE = Float32(8)
"""How far a chaining finisher's sparks leap, in meters."""
comptime CHAIN_TARGETS = 3
"""How many other targets a chaining finisher's sparks leap to at most."""
comptime CHAIN_SHARE = Float32(0.6)
"""The share of its finisher's blow that each chained spark strikes with."""
comptime CHAIN_SPEED = Float32(40)
"""How fast a chained spark flies, in meters a second."""
comptime MARK_SECONDS = Float32(6)
"""How long a marking finisher's mark lasts, in seconds."""
comptime MARK_BONUS = Float32(1.25)
"""How many times its damage each blow on a marked target does."""
comptime FLASH_SECONDS = Float32(0.6)
"""How long an effect's flash of light shows, in seconds."""
comptime EFFECT_TEXT = Rgb(200, 160, 255)
"""The color of an effect's word over its foe."""
comptime BLEED_TEXT = Rgb(220, 40, 50)
"""The color of a wound's bleeding numbers."""
comptime STORM_RANGE = Float32(18)
"""How near the player a target must stand for a ranged style's ultimate
to fall on it, in meters."""
comptime STORM_HEIGHT = Float32(9)
"""How high over each target a magic ultimate's star of light starts, in
meters."""
comptime LOCK_RANGE = Float32(16)
"""How near a target must be to lock on to, in meters."""
comptime LOCK_BREAK = Float32(22)
"""How far a locked target can go before the lock lets go, in meters."""
comptime LOCK_TURN = Float32(5)
"""How fast the camera turns toward a locked target, in radians a
second."""
comptime AIM_RANGE = Float32(4)
"""How near a target must be for an attack to turn to it, in meters."""
comptime AIM_ARC = Float32(150)
"""The arc before the player in which an attack finds a target, in
degrees."""
comptime TRACK_TURN = Float32(12)
"""How fast an attack's start-up turns its fighter, in radians a second."""
comptime FACE_TURN = Float32(10)
"""How fast a free fighter turns to face its foe, in radians a second."""
comptime SHOVE_FADE = Float32(7)
"""How fast a blow's push dies away: each second it keeps
`exp(-SHOVE_FADE)` of itself."""
comptime STILL_SHOVE = Float32(0.05)
"""A push slower than this, in meters a second, is over."""
comptime BLOCK_PUSH = Float32(0.4)
"""The share of a blow's push that a guarded blow gives."""
comptime JUGGLE = Float32(3)
"""How fast a blow throws up a fighter in the air, at least, in meters a
second."""
comptime HEAD = Float32(2.0)
"""How high over a fighter's feet its numbers show, in meters."""
comptime CHEST = Float32(1.3)
"""How high over a fighter's feet a blow's sparks burst, in meters."""
comptime POPUP_SECONDS = Float32(0.9)
"""How long a number or a word shows over a fighter, in seconds."""
comptime POPUP_RISE = Float32(0.9)
"""How fast a number or a word rises, in meters a second."""
comptime ENGAGE = Float32(10)
"""How near a fighting bandit keeps the player's sword drawn, in
meters."""
comptime CALM_SECONDS = Float32(6)
"""How long after the last fight the sword is sheathed, in seconds."""
comptime TOKEN_REST = Float32(0.6)
"""How long after a bandit gives back the attack token another can take
it, in seconds."""
comptime LOOT = 8
"""How many coins a fallen bandit gives."""
comptime HERB_CHANCE = Float32(0.5)
"""The share of fallen bandits that drop an herb as well."""
comptime WAVE_SPEED = Float32(14)
"""How fast a ground wave's wave runs, in meters a second."""
comptime WAVE_RANGE = Float32(12)
"""How far a ground wave's wave runs, in meters."""
comptime WAVE_WIDTH = Float32(1.6)
"""How wide a ground wave's wave strikes, in meters."""
comptime WAVE_START = Float32(0.6)
"""How far before the player a ground wave's wave starts, in meters."""
comptime HIT_STOP = Float32(0.06)
"""How long a strong blow stops the fight, in seconds."""
comptime FINISH_STOP = Float32(0.2)
"""How long a finisher stops the fight, in seconds."""
comptime SHAKE = Float32(0.06)
"""How far a strong blow shakes the camera, in meters."""
comptime SHAKE_FADE = Float32(10)
"""How fast the camera's shake dies away: each second it keeps
`exp(-SHAKE_FADE)` of itself."""
comptime STRONG_PUSH = Float32(4)
"""A blow that lands and pushes at least this fast, in meters a second,
is strong."""
comptime FLICK = Float32(0.7)
"""How far the look stick must lean, newly, to move the lock."""
comptime HEAL_SHARE = Float32(0.3)
"""The share of the player's health that an herb heals."""
comptime HEAL_TEXT = Rgb(120, 230, 120)
"""The color of what an herb or the companion heals."""
comptime PLUNGE_SPEED = Float32(14)
"""How fast a plunge dives, in meters a second."""
comptime KNIFE_SPEED = Float32(18)
"""How fast a thrown knife flies, in meters a second."""
comptime KNIFE_REACH = Float32(0.5)
"""How near the player's chest a knife strikes, in meters."""
comptime KNIFE_LIFE = Float32(1.2)
"""How long a knife flies before it falls, in seconds."""
comptime BOLT_SPEED = Float32(16)
"""How fast a companion's bolt flies, in meters a second."""
comptime BOLT_REACH = Float32(0.5)
"""How near its foe's chest a bolt strikes, in meters."""
comptime BOLT_LIFE = Float32(1.5)
"""How long a bolt flies before it fades, in seconds."""
comptime BOLT_START = Float32(0.6)
"""How far before the companion a bolt starts, in meters."""
comptime ALLY_SEEK = Float32(15)
"""How far from the player a foe that fights draws the companion's
casts, in meters."""
comptime SHOT_RANGE = Float32(26)
"""How near a target must be for a spell or an arrow to aim at it, in
meters."""
comptime SHOT_ARC = Float32(70)
"""The arc before the player in which a spell or an arrow finds a target,
in degrees."""
comptime SHOT_HEIGHT = Float32(1.45)
"""How high over the player's feet a spell or an arrow leaves the hand, in
meters."""
comptime SHOT_AHEAD = Float32(0.5)
"""How far before the player a spell or an arrow leaves the hand, in
meters."""
comptime RAIN_REACH = Float32(10)
"""How far before the player a rain of arrows falls with no target, in
meters."""
comptime MEND_RADIUS = Float32(8)
"""How near the player a mend heals an ally, in meters."""
comptime MEND_HEAL = Float32(0.18)
"""The share of each one's health that a mend heals."""
comptime SPRINT_COST = Float32(11)
"""The stamina a sprint spends, a second."""
comptime SPRINT_REST = Float32(25)
"""The stamina a player who ran out needs before they sprint again."""
comptime LANDING_SHAKE = Float32(0.008)
"""How far a hard landing shakes the camera, in meters, for each meter a
second it lands faster than a hard landing must."""
comptime FAR_POSE = 3
"""How many frames apart a fighter past the fight's reach is posed."""
comptime RAID_LOOT = 60
"""How many coins the fallen warden gives."""
comptime RAID_HERBS = 3
"""How many herbs the fallen warden gives."""
comptime RAID_EXPERIENCE = 400
"""The fighting experience of the warden felled."""
comptime TAUNT_RANGE = Float32(25)
"""How near the warden the player must be to taunt it, in meters."""
comptime ROLL_TAP = Float32(0.3)
"""How long a press of the dodge can last, out of a fight, to roll, in
seconds. A longer hold of the east button runs."""
comptime REVIVE_REACH = Float32(1.6)
"""How near a fallen raider a member must stand to revive it, in
meters."""
comptime HURT_TEXT = Rgb(255, 90, 70)
"""The color of the player's own damage."""
comptime CALM_TEXT = Rgb(150, 200, 255)
"""The color of a guard's, a dodge's and a recovery's words."""


def pressed(now: MoveInput, before: MoveInput) -> MoveInput:
    """Return the buttons pressed since the last frame.

    Args:
        now: This frame's input.
        before: The last frame's.

    Returns:
        This frame's sticks, and each button held now and not before.
    """
    return MoveInput(
        now.forward,
        now.right,
        now.look_right,
        now.look_up,
        now.run and not before.run,
        now.jump and not before.jump,
        now.use and not before.use,
        light=now.light and not before.light,
        heavy=now.heavy and not before.heavy,
        rising=now.rising and not before.rising,
        whirlwind=now.whirlwind and not before.whirlwind,
        ground_wave=now.ground_wave and not before.ground_wave,
        assist=now.assist and not before.assist,
        ultimate=now.ultimate and not before.ultimate,
        dodge=now.dodge and not before.dodge,
        guard=now.guard and not before.guard,
        lock=now.lock and not before.lock,
        high=now.high and not before.high,
        middle=now.middle and not before.middle,
        low=now.low and not before.low,
        heal=now.heal and not before.heal,
        swap=now.swap and not before.swap,
        taunt=now.taunt and not before.taunt,
        book=now.book and not before.book,
    )


def _flat(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def _way(a: Vector3, b: Vector3) -> Vector3:
    """Return the way from one point to another on the ground, of length
    one, or of no length when they meet."""
    var gap = max(_flat(a, b), Float32(1.0e-4))
    return Vector3((b.x - a.x) / gap, 0, (b.z - a.z) / gap)


def _ahead(heading: Angle) -> Vector3:
    """Return the way a heading faces on the ground."""
    return ground_direction(heading, 1, 0)


def push_of(struck: Struck, blow: Blow, way: Vector3) -> Vector3:
    """Return how fast a blow pushes the fighter it reaches.

    Args:
        struck: What the blow did.
        blow: The blow.
        way: The way from the attacker to the fighter, of length one.

    Returns:
        The blow's push along `way` for a blow that landed, `BLOCK_PUSH`
        of it for a guarded blow, and nothing otherwise.
    """
    var speed = blow.knockback.to(METER_PER_SECOND)
    if landed_blow(struck.outcome):
        return way * speed
    if struck.outcome == BLOCKED or struck.outcome == GUARD_BREAK:
        return way * (speed * BLOCK_PUSH)
    return Vector3(0, 0, 0)


def throw_up(mut character: Character, struck: Struck, blow: Blow):
    """Throw a fighter up, if a blow that lands throws or juggles it.

    Args:
        character: The fighter's character.
        struck: What the blow did.
        blow: The blow.
    """
    if not landed_blow(struck.outcome):
        return
    var launch = blow.launch.to(METER_PER_SECOND)
    if launch > 0:
        character.velocity.y = launch
        character.grounded = False
    elif not character.grounded:
        character.velocity.y = max(character.velocity.y, JUGGLE)


def strong_blow(struck: Struck, blow: Blow) -> Bool:
    """Return whether a blow is strong enough to stop the fight a moment.

    Args:
        struck: What the blow did.
        blow: The blow.

    Returns:
        True for a guard broken, a critical blow, a stamina broken and a fighter
        felled, and for a blow that lands, pushes at least `STRONG_PUSH`
        or throws its fighter up.
    """
    if struck.outcome == GUARD_BREAK:
        return True
    if not landed_blow(struck.outcome):
        return False
    if struck.outcome != HIT:
        return True
    var push = blow.knockback.to(METER_PER_SECOND)
    return push >= STRONG_PUSH or blow.launch.to(METER_PER_SECOND) > 0


@fieldwise_init
struct Wave(Copyable, Movable):
    """A ground wave's wave of force, which runs along the ground."""

    # Where its middle is, the way it runs, of length one, and how far it
    # has run, in meters.
    var at: Vector3
    var way: Vector3
    var gone: Float32
    # What it does to each target it strikes, and the targets it struck.
    var blow: Blow
    var struck: List[Int]


@fieldwise_init
struct Wound(Copyable, Movable):
    """A finisher's wound, which bleeds its target's health away."""

    # The target; how long it still bleeds, in seconds; and how much
    # health it takes a second.
    var index: Int
    var left: Float32
    var rate: Float32
    # The health it has taken and not yet shown, and how long since it
    # last showed, in seconds.
    var owed: Float32
    var since: Float32


@fieldwise_init
struct Flash(Copyable, Movable):
    """A combo effect's flash of light, which the display draws."""

    var effect: ComboEffect
    # Where it starts and where it ends: the same place, but for a chain's
    # spark and a drain's light, which run to the next target and to the
    # player. Each is at chest height.
    var at: Vector3
    var to: Vector3
    var age: Float32


@fieldwise_init
struct Popup(Copyable, Movable):
    """A number or a word over a fighter: what a blow did."""

    var at: Vector3
    var text: String
    var color: Rgb
    # How long it has shown, in seconds.
    var age: Float32


struct BattleParameters(Copyable, Movable):
    """Who fights in the village, and how strong they are."""

    var player: FighterParameters
    var dummy: FighterParameters
    var bandits: List[Bandit]
    var dens: List[Den]
    var posts: List[Post]
    # The companion, if any: her `x` and `z` are her place from the
    # player's start.
    var allies: List[Bandit]
    # How long a fallen player lies before they come to; how long a fallen
    # foe lies before it is gone, and comes back to its post.
    var revive: Duration
    var linger: Duration
    var respawn: Duration
    # How many poses of its walk each wolf is meshed in, and how many
    # times its quality's cell its mesh's cell is.
    var phases: Int
    var coarseness: Float64
    # The fighting styles the player carries, the first taken up at the
    # start, and the style they specialize in.
    var styles: List[FightingStyle]
    var specialty: FightingStyle
    # The raid, if any.
    var raids: List[RaidParameters]
    # How far from the player a fighter is posed every frame and leaves a
    # trail, in meters; past it, it is posed every `FAR_POSE`th frame.
    var fight_reach: Float32

    def __init__(out self) raises:
        """Hold the default village's fight: the player's strength, the
        companion, the bandits' camp and its captain, the wolves' den, and
        the dummies,
        a revive of 4 seconds, foes that lie for 10 seconds and come back
        after a minute, and wolves of six poses at their quality's cell.
        The player carries every style, takes up the sword, and
        specializes in it. The Stone Warden keeps its ring of stones, and
        its four raiders wait there.

        Raises:
            Error: Never: the outfits check.
        """
        self.player = FighterParameters()
        self.dummy = dummy_fighter()
        self.bandits = default_bandits()
        self.dens = default_dens()
        self.posts = default_posts()
        self.allies = default_allies()
        self.revive = Duration(4.0, SECOND)
        self.linger = Duration(10.0, SECOND)
        self.respawn = Duration(60.0, SECOND)
        self.phases = 6
        self.coarseness = 1
        self.styles = [SWORD, AXE, MACE, HAND_TO_HAND, MAGIC, ARCHERY]
        self.specialty = SWORD
        self.raids = [RaidParameters()]
        self.fight_reach = 1.0e4

    def check(self) raises:
        """Refuse a fight that cannot be held.

        Raises:
            Error: If the player's, the companion's, a bandit's, a den's or
                the dummies' parameters do not check; a den holds not from
                1 to 8 wolves; there are more than 16 bandits, 16 dummies,
                4 dens or 1 companion; a time is negative or not below 10,000 seconds; a
                wolf's walk has not from 1 to 32 poses; its coarseness
                is not from 1 to 8; the player carries no style, more than
                six, one twice or one that is not a style; the specialty
                is not a style; there is more than one raid, or its
                parameters do not check; or the fight's reach is not from
                5 to 10,000 meters.
        """
        self.player.check()
        self.dummy.check()
        for bandit in self.bandits:
            bandit.fighter.check()
        for ally in self.allies:
            ally.fighter.check()
        if len(self.allies) > 1:
            raise Error("A fight holds at most one companion")
        for den in self.dens:
            den.fighter.check()
            if not (den.count >= 1 and den.count <= 8):
                raise Error("A den holds from 1 to 8 wolves")
        if len(self.bandits) > 16 or len(self.posts) > 16:
            raise Error("A fight holds at most 16 bandits and 16 dummies")
        if len(self.dens) > 4:
            raise Error("A fight holds at most 4 dens")
        if not (self.phases >= 1 and self.phases <= 32):
            raise Error("A wolf's walk must have from 1 to 32 poses")
        if not (self.coarseness >= 1 and self.coarseness <= 8):
            raise Error("A wolf's coarseness must be from 1 to 8")
        if not (len(self.styles) >= 1 and len(self.styles) <= STYLES):
            raise Error("A player carries from one to six fighting styles")
        var seen = List[Bool](length=STYLES, fill=False)
        for style in self.styles:  # pragma: no branch
            if not style.is_valid() or seen[style.value]:
                raise Error(
                    "A player's styles must be six styles at most, apart"
                )
            seen[style.value] = True
        if not self.specialty.is_valid():
            raise Error("A player's specialty must be one of the six styles")
        if len(self.raids) > 1:
            raise Error("A fight holds at most one raid")
        if not (self.fight_reach >= 5 and self.fight_reach <= 1.0e4):
            raise Error("A fight's reach must be from 5 to 10,000 meters")
        for raid in self.raids:
            raid.check()
        for time in [  # pragma: no branch
            self.revive,
            self.linger,
            self.respawn,
        ]:
            var seconds = time.to(SECOND)
            if not (seconds >= 0 and seconds < 1.0e4):
                raise Error(
                    "A fight's revive, linger and respawn must be from 0 to"
                    " 10,000 seconds"
                )


@fieldwise_init
struct Foe(Movable):
    """A bandit or a wolf in the scene: its character, fighter and brain,
    and where its looks are."""

    var character: Character
    var fighter: Fighter
    var brain: Brain
    # Its post, and the way it faces there.
    var home: Vector3
    var heading: Angle
    # How fast a blow pushes it, in meters a second.
    var shove: Vector3
    # How long it has lain fallen, in seconds, or -1 while it stands.
    var down: Float32
    # Whether it is a wolf; and its looks: its index in the battle's
    # `people` for a bandit, or in its `pelts` for a wolf.
    var beast: Bool
    var look: Int
    # The way its sidestep goes, of length one.
    var dodge_way: Vector3


@fieldwise_init
struct Person(Movable):
    """A fighter's looks: its body, its weapons and its trail."""

    var body: Body
    var arms: Arms
    var trail: Trail
    # The time its clips have not yet played, in seconds: a body past the
    # fight's reach plays them every `FAR_POSE`th frame.
    var unposed: Float32


def pose_person(
    mut scene: Scene,
    mut person: Person,
    character: Character,
    fighter: Fighter,
    drawn: Bool,
    delta: Duration,
    near: Bool,
    turn: Bool,
) raises:
    """Pose a fighter's body, and show its trail.

    A body near the player plays its clips each frame, and shows its trail.
    A body past the fight's reach plays them only on its turn, for all the
    time it waited, and shows no trail; between, it only stands where its
    character stands.

    Args:
        scene: The scene the body is in.
        person: The body, its weapons and its trail.
        character: The character the body shows.
        fighter: What the body does in a fight.
        drawn: Whether its weapon is drawn.
        delta: The frame's time.
        near: Whether the body is within the fight's reach of the player.
        turn: Whether it is the body's turn to pose, past the reach.

    Raises:
        Error: If a clip cannot be played.
    """
    person.unposed += delta.to(SECOND)
    if not near and not turn:
        person.arms.place(scene, person.body, character)
        person.trail.shown = -1
        return
    var waited = Duration(person.unposed, SECOND)
    person.unposed = 0
    person.arms.pose(scene, person.body, character, fighter, drawn, waited)
    if near:
        person.trail.show(scene, fighter)
    else:
        person.trail.shown = -1


@fieldwise_init
struct Ally(Movable):
    """The companion in the scene: her character, fighter and mind, and
    what she casts at."""

    var character: Character
    var fighter: Fighter
    var mind: Companion
    # Her looks' index in the battle's `people`.
    var look: Int
    # The target her cast aims at, or -1; and whether the cast is a assist
    # attack.
    var aim: Int
    var assisting: Bool


@fieldwise_init
struct Bolt(Copyable, Movable):
    """A companion's bolt of light, which flies at its target."""

    # Where it is, and where it was cast from.
    var at: Vector3
    var origin: Vector3
    # The target it flies at, and the blow it carries.
    var target: Int
    var blow: Blow
    # Whether it is a assist attack's, and how long it has flown, in
    # seconds.
    var assisted: Bool
    var age: Float32


@fieldwise_init
struct Knife(Copyable, Movable):
    """A thrower's knife, which flies straight along the way it was
    thrown."""

    # Where it is, the way it flies, of length one, and where it was
    # thrown from.
    var at: Vector3
    var way: Vector3
    var origin: Vector3
    # The foe that threw it, the blow it carries, and how long it has
    # flown, in seconds.
    var thrower: Int
    var blow: Blow
    var age: Float32


@fieldwise_init
struct Pelt(ImplicitlyCopyable):
    """A wolf's looks: its node, its mesh in `scene.meshes`, and its
    flipbook's index in the battle's `books`."""

    var node: NodeId
    var mesh: Int
    var book: Int


@fieldwise_init
struct Practice(Movable):
    """A straw dummy and its fighter."""

    var dummy: Dummy
    var fighter: Fighter


struct Battle(Movable):
    """The player's fighter, the bandits and the dummies, and what the
    fight shows."""

    var parameters: BattleParameters
    var fighter: Fighter
    var arms: Arms
    var trail: Trail
    var foes: List[Foe]
    var people: List[Person]
    var pelts: List[Pelt]
    var books: List[Flipbook]
    var dummies: List[Practice]
    var sparks: Sparks
    var popups: List[Popup]
    # The ground wave's waves that run.
    var waves: List[Wave]
    # The companion, if any, and her bolts that fly; and whether the assist
    # button was pressed this frame.
    var allies: List[Ally]
    var bolts: List[Bolt]
    var called: Bool
    # The throwers' knives that fly.
    var knives: List[Knife]
    # The target locked on: a foe's index, or a dummy's after the foes;
    # -1 for none.
    var lock: Int
    # The foe that holds the attack token, or -1; and how long until
    # another can take it, in seconds.
    var token: Int
    var token_rest: Float32
    # The member each foe goes for: -1 for the player, and `k` for the
    # raider `k`.
    var quarries: List[Int]
    # The wounds that bleed; how long each target is still marked, in
    # seconds; and the effects' flashes of light.
    var wounds: List[Wound]
    var marks: List[Float32]
    var flashes: List[Flash]
    # The last frame's input, for new presses.
    var last: MoveInput
    # The way the player's dodge goes, and how fast a blow pushes them.
    var dodge_way: Vector3
    var shove: Vector3
    # The player's move last frame, and how far into it they were.
    var seen: CombatMove
    var seen_clock: Float32
    # Whether an attack of the player's started this frame.
    var threat: Bool
    # Whether the sword is drawn, and how long since the last fight.
    var drawn: Bool
    var calm: Float32
    # How long the foes are still slowed, in seconds.
    var slow: Float32
    # How long ago the player last made a stamina recovery that got stamina back, in
    # seconds, or -1 if they never did.
    var pulsed: Float32
    # How long the player has lain fallen, in seconds, or -1.
    var down: Float32
    # Whether the player was in a surge at the end of the last frame.
    var limited: Bool
    # How long the fight still stands still, in seconds; and how far the
    # camera shakes, in meters.
    var freeze: Float32
    var shake: Float32
    # Where the player comes to.
    var start: Vector3
    # Coins won and not yet taken, and lines for the game's note.
    var loot: Int
    var notes: List[String]
    # How many herbs the satchel holds, as the game says before each
    # frame; how many the player ate, for the game to take; and how many
    # fallen bandits dropped, for the game to give.
    var herbs: Int
    var eaten: Int
    var found: Int
    # The experience won and not yet taken, for each fighting style: see
    # `extensions.village.skills`.
    var trained: List[Int]
    # The player's combos, and the string they make now; the combo whose
    # finisher the player makes, or -1, the finisher's move, and whether it
    # landed.
    var book: ComboBook
    var tracker: ComboTracker
    var finisher: Int
    var finishing: CombatMove
    var finisher_landed: Bool
    # The level of each style's skill, as the game says before each frame;
    # the place in the parameters' styles of the style the player fights
    # in; and whether the combo book shows.
    var levels: List[Int]
    var style_at: Int
    var reading: Bool
    # The player's spells and arrows that fly.
    var shots: List[Missile]
    # How long ago the player last pressed on the beat, and last mended,
    # in seconds, or -1.
    var beat: Float32
    var mended: Float32
    # The raid's warden, if it was built, and its raiders; and how long
    # until the player can taunt again, in seconds.
    var wardens: List[Warden]
    var members: List[Member]
    var taunt_wait: Float32
    # How long the dodge has been held, in seconds.
    var dodge_hold: Float32
    # Where the player's feet were at the end of the last frame, for the
    # display.
    var feet: Vector3
    # How many frames the fight has run.
    var frame: Int

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        parameters: BattleParameters,
        looks: HouseLooks,
        terrain: Terrain,
        lots: List[Lot],
        mut body: Body,
        start: Vector3,
        triangles: Int,
        detail: Int,
    ) raises:
        """Arm the player's body, and build the bandits, the wolves and the
        dummies.

        A bandit, a wolf or a dummy on a lot or its apron, or in the
        water, is left out. A den with no wolf left builds no look.

        Args:
            scene: The scene.
            assets: The stores.
            parameters: Who fights.
            looks: The village's materials, which the dummies wear.
            terrain: The ground the fighters stand on.
            lots: The ground kept clear of fighters.
            body: The player's body: it gets the sword clips and a sword.
            start: Where the player comes to after a fall.
            triangles: Each bandit's budget of triangles.
            detail: The cells along each bandit's skin.

        Raises:
            Error: If `parameters.check` refuses a value, or a fighter
                cannot be built.
        """
        parameters.check()
        self.parameters = parameters.copy()
        self.fighter = Fighter(parameters.player)
        _ = self.fighter.set_style(parameters.styles[0])
        var swords = SwordLooks(assets)
        var glow = slash_material(assets)
        self.arms = Arms(
            scene, assets, body, swords, BRIGHT_STEEL, parameters.styles
        )
        var scale = body.person.rig.stature / Float32(1.8288)
        self.trail = Trail(scene, body.carrier, scale, PLAYER_TRAIL)
        self.foes = List[Foe]()
        self.people = List[Person]()
        self.pelts = List[Pelt]()
        self.books = List[Flipbook]()
        ref ground = terrain.ground
        for bandit in parameters.bandits:
            if lot_openness(lots, bandit.x, bandit.z) < 1:
                continue
            if ground.wet(bandit.x, bandit.z):
                continue
            var person = Body(
                scene, assets, bandit.spec, bandit.outfit, triangles, detail
            )
            var arms = Arms(scene, assets, person, swords, DULL_IRON)
            var size = person.person.rig.stature / Float32(1.8288)
            var trail = Trail(scene, person.carrier, size, FOE_TRAIL)
            var character = Character(
                CharacterParameters(),
                bandit.x,
                bandit.z,
                bandit.heading,
                terrain,
            )
            var home = character.position
            self.people.append(Person(person^, arms^, trail^, 0))
            self.foes.append(
                Foe(
                    character^,
                    Fighter(bandit.fighter),
                    Brain.thrower(bandit.seed) if bandit.thrower else Brain(
                        bandit.seed
                    ),
                    home,
                    bandit.heading,
                    Vector3(0, 0, 0),
                    -1,
                    False,
                    len(self.people) - 1,
                    Vector3(0, 0, 1),
                )
            )
        self.allies = List[Ally]()
        for ally in parameters.allies:
            var person = Body(
                scene, assets, ally.spec, ally.outfit, triangles, detail
            )
            var arms = Arms(scene, assets, person, swords, BRIGHT_STEEL)
            var size = person.person.rig.stature / Float32(1.8288)
            var trail = Trail(scene, person.carrier, size, PLAYER_TRAIL)
            var character = Character(
                CharacterParameters(),
                start.x + ally.x,
                start.z + ally.z,
                ally.heading,
                terrain,
            )
            self.people.append(Person(person^, arms^, trail^, 0))
            self.allies.append(
                Ally(
                    character^,
                    Fighter(ally.fighter),
                    Companion(),
                    len(self.people) - 1,
                    -1,
                    False,
                )
            )
        var paints = animal_paints(assets)
        for den in parameters.dens:
            var places = den_places(den)
            var kept = List[Int]()
            for k in range(len(places)):  # pragma: no branch
                var at = places[k]
                if lot_openness(lots, at.x, at.z) < 1:
                    continue
                if ground.wet(at.x, at.z):
                    continue
                kept.append(k)
            # A den whose every wolf is left out costs no look.
            if len(kept) == 0:
                continue
            var look = animal_look(
                assets,
                WOLF,
                den.seed,
                parameters.phases,
                CROWD,
                parameters.coarseness,
            )
            var walker = look.walker
            walker.run_speed = Velocity(WOLF_RUN, METER_PER_SECOND)
            self.books.append(look.book.copy())
            for k in kept:  # pragma: no branch
                var at = places[k]
                var node = scene.add(Object3D())
                self.pelts.append(
                    Pelt(node, len(scene.meshes), len(self.books) - 1)
                )
                scene.add_mesh(
                    Mesh(
                        look.book.stand,
                        paints,
                        node,
                        cast_shadow=True,
                        receive_shadow=True,
                    )
                )
                var heading = Angle(Float32(k) * 2.1, RADIAN)
                var character = Character(walker, at.x, at.z, heading, terrain)
                var home = character.position
                self.foes.append(
                    Foe(
                        character^,
                        Fighter(den.fighter),
                        Brain.wolf(den.seed * 16 + k),
                        home,
                        heading,
                        Vector3(0, 0, 0),
                        -1,
                        True,
                        len(self.pelts) - 1,
                        Vector3(0, 0, 1),
                    )
                )
        self.dummies = List[Practice]()
        for post in parameters.posts:
            if lot_openness(lots, post.x, post.z) < 1:
                continue
            if ground.wet(post.x, post.z):
                continue
            var foot = ground.height_at(post.x, post.z)
            self.dummies.append(
                Practice(
                    Dummy(scene, assets, looks, post, foot),
                    Fighter(parameters.dummy),
                )
            )
        self.wardens = List[Warden]()
        self.members = List[Member]()
        self.taunt_wait = 0
        self.dodge_hold = 0
        self.feet = start
        self.frame = 0
        self.sparks = Sparks(scene, assets, glow)
        self.popups = List[Popup]()
        self.waves = List[Wave]()
        self.bolts = List[Bolt]()
        self.called = False
        self.knives = List[Knife]()
        self.lock = -1
        self.token = -1
        self.token_rest = 0
        self.quarries = List[Int](length=len(self.foes), fill=-1)
        self.wounds = List[Wound]()
        self.marks = List[Float32]()
        self.flashes = List[Flash]()
        self.last = MoveInput(0, 0, 0, 0, False, False)
        self.dodge_way = Vector3(0, 0, 1)
        self.shove = Vector3(0, 0, 0)
        self.seen = FREE
        self.seen_clock = 0
        self.threat = False
        self.drawn = False
        self.calm = CALM_SECONDS
        self.slow = 0
        self.pulsed = -1
        self.down = -1
        self.limited = False
        self.freeze = 0
        self.shake = 0
        self.start = start
        self.loot = 0
        self.notes = List[String]()
        self.herbs = 0
        self.eaten = 0
        self.found = 0
        self.trained = List[Int](length=STYLES, fill=0)
        self.book = ComboBook(parameters.specialty)
        for style in parameters.styles:  # pragma: no branch
            _ = self.book.teach(style, 1)
        self.tracker = ComboTracker()
        self.finisher = -1
        self.finishing = FREE
        self.finisher_landed = False
        self.levels = List[Int](length=STYLES, fill=1)
        self.style_at = 0
        self.reading = False
        self.shots = List[Missile]()
        self.beat = -1
        self.mended = -1
        for raid in parameters.raids:
            if lot_openness(lots, raid.x, raid.z) < 1:
                continue
            if ground.wet(raid.x, raid.z):
                continue
            self._raise_raid(
                scene, assets, raid, looks, terrain, swords, triangles, detail
            )
        self.marks = List[Float32](length=self.targets(), fill=0)

    def _raise_raid(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        raid: RaidParameters,
        looks: HouseLooks,
        terrain: Terrain,
        swords: SwordLooks,
        triangles: Int,
        detail: Int,
    ) raises:
        """Build the raid's stones, its warden and its raiders."""
        ref ground = terrain.ground
        var person = Body(
            scene, assets, raid.spec, raid.outfit, triangles, detail
        )
        scene.node(person.carrier).set_scale(
            WARDEN_SIZE, WARDEN_SIZE, WARDEN_SIZE
        )
        person.lift *= WARDEN_SIZE
        var arms = Arms(
            scene, assets, person, swords, DULL_IRON, [MACE], giant=True
        )
        var size = person.person.rig.stature / Float32(1.8288)
        var trail = Trail(scene, person.carrier, size, FOE_TRAIL)
        var giant = CharacterParameters()
        giant.radius = Length(WARDEN_RADIUS, METER)
        giant.walk_speed = Velocity(BOSS_WALK, METER_PER_SECOND)
        giant.run_speed = Velocity(BOSS_WALK, METER_PER_SECOND)
        var character = Character(giant, raid.x, raid.z, raid.heading, terrain)
        var home = character.position
        self.people.append(Person(person^, arms^, trail^, 0))
        var puppet = Fighter(FighterParameters())
        _ = puppet.set_style(MACE)
        self.wardens.append(
            Warden(
                character^,
                Boss(1 + len(raid.raiders), raid.seed),
                puppet^,
                home,
                raid.heading,
                len(self.people) - 1,
                -1,
            )
        )
        var heights = List[Float32]()
        for at in stone_places(home):  # pragma: no branch
            heights.append(ground.height_at(at.x, at.z))
        _ = add_stones(scene, assets, looks, home, heights)
        for raider in raid.raiders:
            var body = Body(
                scene, assets, raider.spec, raider.outfit, triangles, detail
            )
            var style = role_style(raider.role)
            var kit = Arms(scene, assets, body, swords, BRIGHT_STEEL, [style])
            var scale = body.person.rig.stature / Float32(1.8288)
            var streak = Trail(scene, body.carrier, scale, PLAYER_TRAIL)
            var walker = Character(
                CharacterParameters(),
                raid.x + raider.x,
                raid.z + raider.z,
                raid.heading,
                terrain,
            )
            var post = walker.position
            var fighter = Fighter(member_fighter(raider.role))
            _ = fighter.set_style(style)
            self.people.append(Person(body^, kit^, streak^, 0))
            self.members.append(
                Member(
                    walker^,
                    fighter^,
                    PartyMind(raider.role),
                    post,
                    len(self.people) - 1,
                    False,
                    -1,
                    0,
                    Vector3(0, 0, 0),
                    Vector3(0, 0, 1),
                )
            )

    def first_warden(self) -> Int:
        """Return the target index of the first warden.

        Returns:
            The index after the foes and the dummies.
        """
        return len(self.foes) + len(self.dummies)

    def node_of(self, index: Int) -> NodeId:
        """Return the node a foe's looks hang from.

        Args:
            index: The foe's index.

        Returns:
            A bandit's body's carrier, or a wolf's node.
        """
        ref foe = self.foes[index]
        if foe.beast:
            return self.pelts[foe.look].node
        return self.people[foe.look].body.carrier

    def movers(self) -> List[NodeId]:
        """Return the nodes that move: each foe's, each dummy's and the
        companion's.

        Returns:
            Each foe's node, then each dummy's pivot, then the companion's
            body's carrier.
        """
        var out = List[NodeId]()
        for index in range(len(self.foes)):
            out.append(self.node_of(index))
        for index in range(len(self.dummies)):
            out.append(self.dummies[index].dummy.pivot)
        for index in range(len(self.allies)):
            out.append(self.people[self.allies[index].look].body.carrier)
        for index in range(len(self.wardens)):
            out.append(self.people[self.wardens[index].look].body.carrier)
        for index in range(len(self.members)):
            out.append(self.people[self.members[index].look].body.carrier)
        return out^

    def targets(self) -> Int:
        """Return how many targets there are: the bandits, then the
        dummies, then the wardens.

        Returns:
            The count.
        """
        return len(self.foes) + len(self.dummies) + len(self.wardens)

    def target_at(self, index: Int) -> Vector3:
        """Return where a target's feet are.

        Args:
            index: A bandit's index, a dummy's after the bandits, or a
                warden's after the dummies.

        Returns:
            The feet.
        """
        if index < len(self.foes):
            return self.foes[index].character.position
        var post = index - len(self.foes)
        if post < len(self.dummies):
            return self.dummies[post].dummy.where()
        return self.wardens[post - len(self.dummies)].character.position

    def target_radius(self, index: Int) -> Float32:
        """Return how wide a target is, for a swing to reach it.

        Args:
            index: A target's index.

        Returns:
            `WARDEN_RADIUS` for a warden, and 0.3 meters for any other.
        """
        if index >= self.first_warden():
            return WARDEN_RADIUS
        return 0.3

    def standing(self, index: Int) -> Bool:
        """Return whether a target stands, so it can be struck or locked.

        Args:
            index: A bandit's index, a dummy's after the bandits, or a
                warden's after the dummies.

        Returns:
            False for a fallen bandit or warden, and True for a dummy.
        """
        if index < len(self.foes):
            return self.foes[index].down < 0
        if index < self.first_warden():
            return True
        return not self.wardens[index - self.first_warden()].boss.defeated()

    def obstacles(self) -> List[Obstacle]:
        """Return the circle each standing bandit, each dummy and the
        companion take up.

        Returns:
            One obstacle a bandit, of no size for a fallen one, then one a
            dummy, then the companion's.
        """
        var out = List[Obstacle]()
        for index in range(len(self.foes)):
            ref foe = self.foes[index]
            ref at = foe.character.position
            var r = foe.character.parameters.radius.to(METER)
            out.append(Obstacle(at.x, at.z, r if foe.down < 0 else 0))
        for index in range(len(self.dummies)):
            ref post = self.dummies[index].dummy.post
            out.append(Obstacle(post.x, post.z, DUMMY_RADIUS))
        for index in range(len(self.allies)):
            ref ally = self.allies[index].character
            ref at = ally.position
            out.append(Obstacle(at.x, at.z, ally.parameters.radius.to(METER)))
        for index in range(len(self.wardens)):
            ref warden = self.wardens[index]
            ref at = warden.character.position
            var r = WARDEN_RADIUS if not warden.boss.defeated() else Float32(0)
            out.append(Obstacle(at.x, at.z, r))
        for index in range(len(self.members)):
            ref member = self.members[index].character
            ref at = member.position
            out.append(Obstacle(at.x, at.z, member.parameters.radius.to(METER)))
        return out^

    def pick_lock(self, at: Vector3, yaw: Angle) -> Int:
        """Return the target to lock on to.

        Args:
            at: Where the player stands.
            yaw: The way the camera looks.

        Returns:
            The standing target within `LOCK_RANGE` that is nearest the
            middle of the view, counting a radian off it as six meters
            further; -1 if there is none.
        """
        var best = -1
        var score = Float32(1.0e9)
        for index in range(self.targets()):
            if not self.standing(index):
                continue
            var there = self.target_at(index)
            var gap = _flat(at, there)
            if gap > LOCK_RANGE:
                continue
            var off = wrap_angle(
                Angle(yaw_of(there - at).to(RADIAN) - yaw.to(RADIAN), RADIAN)
            )
            var mark = gap + 6 * abs(off.to(RADIAN))
            if mark < score:
                score = mark
                best = index
        return best

    def switch_lock(self, at: Vector3, side: Float32) -> Int:
        """Return the target that a flick moves the lock to.

        Args:
            at: Where the player stands.
            side: 1 for a flick to the right, -1 for one to the left.

        Returns:
            The standing target within `LOCK_RANGE` nearest in angle to
            the locked one on that side, as the player sees them; the
            locked one if there is none.
        """
        var base = yaw_of(self.target_at(self.lock) - at).to(RADIAN)
        var best = self.lock
        var nearest = Float32(10)
        # A lock names a target, so there is one at least.
        for index in range(self.targets()):  # pragma: no branch
            if index == self.lock or not self.standing(index):
                continue
            var there = self.target_at(index)
            if _flat(at, there) > LOCK_RANGE:
                continue
            var off = wrap_angle(
                Angle(yaw_of(there - at).to(RADIAN) - base, RADIAN)
            )
            # A yaw that grows turns to the left.
            var turn = -off.to(RADIAN) * side
            if turn > 0 and turn < nearest:
                nearest = turn
                best = index
        return best

    def aim(
        self,
        at: Vector3,
        heading: Angle,
        stick: Vector3,
        within: Float32 = AIM_RANGE,
    ) -> Optional[Angle]:
        """Return the way an attack turns its player toward.

        Args:
            at: Where the player stands.
            heading: The way they face.
            stick: The way the stick leans on the ground; of no length
                when it rests.
            within: How near a target must be: `AIM_RANGE` for a melee
                attack, `SHOT_RANGE` for a spell or a shot.

        Returns:
            The way to the locked target; else to the nearest standing
            target within `within` and `AIM_ARC` of the stick, or of the
            heading when the stick rests; else the stick's way; else None.
        """
        if self.lock >= 0:
            return yaw_of(self.target_at(self.lock) - at)
        var leaning = stick.length() > 0.1
        var look = yaw_of(stick) if leaning else heading
        var best = -1
        var nearest = within
        for index in range(self.targets()):
            if not self.standing(index):
                continue
            var there = self.target_at(index)
            var gap = _flat(at, there)
            if gap < nearest and faces(at, look, Angle(AIM_ARC, DEGREE), there):
                nearest = gap
                best = index
        if best >= 0:
            return yaw_of(self.target_at(best) - at)
        if leaning:
            return look
        return None

    def _command(
        mut self,
        input: MoveInput,
        presses: MoveInput,
        flick: Float32,
        yaw: Angle,
        player: Character,
    ) raises:
        """Turn the frame's presses into the player's moves."""
        if self.fighter.defeated():
            return
        if presses.heal and self.herbs > self.eaten:
            ref f = self.fighter
            var gain = min(
                f.parameters.health - f.health, HEAL_SHARE * f.parameters.health
            )
            if gain > 0:
                f.health += gain
                self.eaten += 1
                var amount = String(Int(gain + 0.5))
                self._popup(player.position, "+" + amount, HEAL_TEXT)
                self.notes.append("HERBS HEAL " + amount)
        var stances: List[CombatStance] = [HIGH_STANCE, MID_STANCE, LOW_STANCE]
        var asked: List[Bool] = [presses.high, presses.middle, presses.low]
        var names: List[String] = ["HIGH", "MIDDLE", "LOW"]
        for k in range(3):  # pragma: no branch
            if asked[k] and self.fighter.set_stance(stances[k]):
                self.notes.append(names[k] + " STANCE")
        if presses.swap:
            self._swap()
        if presses.taunt:
            self._taunt(player)
        if presses.book:
            self.reading = not self.reading
        if presses.lock:
            if self.lock >= 0:
                self.lock = -1
            else:
                self.lock = self.pick_lock(player.position, yaw)
        if self.lock >= 0 and flick != 0:
            self.lock = self.switch_lock(player.position, flick)
        if presses.guard:
            _ = self._key(GUARD_KEY, on_beat(self.fighter), player)
            var back = self.fighter.pulse()
            if back > 0:
                self._popup(player.position, "RECOVERED", CALM_TEXT)
                self.pulsed = 0
        self.fighter.hold_guard(input.guard)
        self.called = presses.assist
        var fought = input.guard or presses.lock
        var button = FightButton(-1)
        if presses.ultimate and self.fighter.over > 0:
            button = ULTIMATE_BUTTON
        elif presses.rising:
            button = RISING_BUTTON
        elif presses.whirlwind:
            button = WHIRLWIND_BUTTON
        elif presses.ground_wave:
            button = WAVE_BUTTON
        elif presses.light:
            button = LIGHT_BUTTON
        elif presses.heavy:
            button = HEAVY_BUTTON
        if button.is_valid():
            fought = True
            self._attack(button, player)
        if presses.dodge and self.drawn:
            _ = self._key(DODGE_KEY, on_beat(self.fighter), player)
            _ = self.fighter.request(DODGE)
        if presses.jump and player.grounded and not self.fighter.free():
            # A jump cuts an attack's recovery short.
            if self.fighter.cancel():
                _ = self._key(JUMP_KEY, True, player)
        elif presses.jump and player.grounded:
            _ = self._key(JUMP_KEY, False, player)
        if fought:
            self.drawn = True
            self.calm = 0

    def _taunt(mut self, player: Character) raises:
        """Taunt the nearest warden in the fight, once every
        `TAUNT_EVERY`."""
        if self.taunt_wait > 0:
            return
        for w in range(len(self.wardens)):
            ref warden = self.wardens[w]
            if warden.boss.defeated():
                continue
            var gap = _flat(warden.character.position, player.position)
            if gap > TAUNT_RANGE:
                continue
            warden.boss.taunt(0)
            self.taunt_wait = TAUNT_EVERY
            self._popup(player.position, "TAUNT", GOLD_TEXT)
            self.drawn = True
            self.calm = 0
            return

    def _swap(mut self) raises:
        """Take up the next style the player carries, while free."""
        var count = len(self.parameters.styles)
        var next = (self.style_at + 1) % count
        if self.fighter.set_style(self.parameters.styles[next]):
            self.style_at = next
            self.tracker.clear()
            self.notes.append(style_name(self.fighter.style))

    def _key(
        mut self, key: ComboKey, beat: Bool, player: Character
    ) raises -> Bool:
        """Add a key to the combo string; if the string ends in a combo the
        player knows, start its finisher. Return whether one started."""
        self.tracker.press(key, beat)
        if beat:
            self.beat = 0
        var found = self.book.match(self.tracker, self.fighter.style)
        if found < 0:
            return False
        var finisher = self.book.combos[found].finisher
        if finisher == HEAVY and not player.grounded:
            finisher = PLUNGE
        var power = self.book.power(found)
        if beat:
            power *= BEAT_BONUS
        if not self.fighter.request(finisher, power, True):
            return False
        self.tracker.clear()
        self.finisher = found
        self.finishing = finisher
        self.finisher_landed = False
        self.notes.append(self.book.combos[found].name + "!")
        self._master(found, MAKE_MASTERY)
        return True

    def _afflict(
        mut self, mut scene: Scene, index: Int, struck: Struck, hit: Blow
    ) raises:
        """Give the combo's effect to the target that its finisher first
        lands on: see `extensions.village.combos`. Its word shows over the
        target, and its flash of light."""
        var effect = self.book.combos[self.finisher].effect
        if effect == NO_EFFECT:
            return
        var there = self.target_at(index)
        var chest = there + Vector3(0, CHEST, 0)
        self._popup(
            there + Vector3(0, 0.7, 0), effect_name(effect), EFFECT_TEXT
        )
        self.flashes.append(Flash(effect, chest, chest, 0))
        if effect == LAUNCH:
            if index < len(self.foes):
                ref body = self.foes[index].character
                body.velocity.y = max(body.velocity.y, LAUNCH_SPEED)
                body.grounded = False
        elif effect == SUNDER:
            if index < len(self.foes):
                ref guard = self.foes[index].fighter
                guard.stamina = 0
                guard.hold_guard(False)
            elif index >= self.first_warden():
                ref boss = self.wardens[index - self.first_warden()].boss
                boss.poise = max(Float32(0), boss.poise - SUNDER_POISE)
        elif effect == BLEED:
            var rate = struck.damage * BLEED_SHARE / BLEED_SECONDS
            self.wounds.append(Wound(index, BLEED_SECONDS, rate, 0, 0))
        elif effect == DRAIN:
            ref f = self.fighter
            var gain = min(
                f.parameters.health - f.health, struck.damage * DRAIN_SHARE
            )
            f.health += gain
            var feet = self.feet
            self._popup(feet, "+" + String(Int(gain + 0.5)), HEAL_TEXT)
            self.flashes[len(self.flashes) - 1].to = feet + Vector3(0, CHEST, 0)
        elif effect == SHOCKWAVE:
            var blow = hit
            blow.damage *= SHOCK_SHARE
            blow.stamina_damage *= SHOCK_SHARE
            var tank = self.fighter.style == MACE
            # The target the finisher landed on is one.
            for other in range(self.targets()):  # pragma: no branch
                if other == index or not self.standing(other):
                    continue
                if _flat(self.target_at(other), there) > SHOCK_RADIUS:
                    continue
                _ = self._strike(scene, other, blow, there, 0, tank)
        elif effect == CHAIN:
            var blow = hit
            blow.damage *= CHAIN_SHARE
            blow.stamina_damage *= CHAIN_SHARE
            var sent = 0
            # The target the finisher landed on is one.
            for other in range(self.targets()):  # pragma: no branch
                if sent == CHAIN_TARGETS:
                    break
                if other == index or not self.standing(other):
                    continue
                var to = self.target_at(other) + Vector3(0, CHEST, 0)
                if _flat(to, chest) > CHAIN_RANGE:
                    continue
                var way = (to - chest) / max((to - chest).length(), 1.0e-3)
                var spark = Missile(
                    SPARK, chest, way * CHAIN_SPEED, other, -1, blow
                )
                spark.struck.append(index)
                self.shots.append(spark^)
                self.flashes.append(Flash(CHAIN, chest, to, 0))
                sent += 1
        else:
            self.marks[index] = MARK_SECONDS

    def _bleed(mut self, index: Int, amount: Float32):
        """Take a wound's bleeding from its target, and show it: a wound
        does not fell a target."""
        if index < len(self.foes):
            ref f = self.foes[index].fighter
            f.health = max(Float32(1), f.health - amount)
        elif index >= self.first_warden():
            ref boss = self.wardens[index - self.first_warden()].boss
            boss.health = max(Float32(1), boss.health - amount)
        if amount >= 0.5:
            var there = self.target_at(index)
            self._popup(there, String(Int(amount + 0.5)), BLEED_TEXT)

    def _effects_step(mut self, seconds: Float32):
        """Age the effects' flashes and marks, and bleed each wound."""
        var flashes = List[Flash]()
        for flash in self.flashes:
            if flash.age + seconds < FLASH_SECONDS:
                var aged = flash.copy()
                aged.age += seconds
                flashes.append(aged^)
        self.flashes = flashes^
        for k in range(len(self.marks)):
            self.marks[k] = max(Float32(0), self.marks[k] - seconds)
        var wounds = List[Wound]()
        for wound in self.wounds:
            if not self.standing(wound.index):
                continue
            var w = wound.copy()
            var step = min(seconds, w.left)
            w.left -= step
            w.owed += w.rate * step
            w.since += step
            if w.since >= BLEED_TICK or w.left <= 0:
                self._bleed(w.index, w.owed)
                w.owed = 0
                w.since = 0
            if w.left > 0:
                wounds.append(w^)
        self.wounds = wounds^

    def _master(mut self, index: Int, amount: Int) raises:
        """Give a combo mastery, and say so when its rank rises."""
        if self.book.practice(index, amount):
            var name = self.book.combos[index].name
            var rank = self.book.rank(index)
            if rank == MAX_RANK:
                self.notes.append(name + " MASTERED!")
            else:
                self.notes.append(String(name, " RANK ", rank, "!"))

    def _perks(mut self, index: Int) raises:
        """Give a landed finisher's perks, by its combo's rank: its stamina
        back from `PRACTICED_RANK`, and `MASTERED_SPECIAL` special points
        at `MAX_RANK`."""
        var rank = self.book.rank(index)
        ref f = self.fighter
        if rank >= PRACTICED_RANK:
            var back = f.stamina_price(self.finishing)
            f.stamina = min(f.parameters.stamina, f.stamina + back)
        if rank == MAX_RANK:
            f.special = min(
                f.parameters.special_points, f.special + MASTERED_SPECIAL
            )

    def _link(mut self, player: Character) raises -> Bool:
        """Call a linked strike on a staggered warden within `LINK_RANGE`:
        the player and each standing raider within `LINK_REACH` of it make
        their heavy attacks together. Return whether one struck."""
        for w in range(len(self.wardens)):
            if not self.wardens[w].boss.link_ready():
                continue
            var at = self.wardens[w].character.position
            if _flat(at, player.position) > LINK_RANGE:
                continue
            var heavy = style_move(
                self.fighter.style, HEAVY_BUTTON, player.grounded, FREE
            )
            if not self.fighter.request(heavy, 1, True):
                return False
            var members: List[Int] = [0]
            for k in range(len(self.members)):
                ref member = self.members[k]
                if not member.joined or member.down >= 0:
                    continue
                if _flat(member.character.position, at) > LINK_REACH:
                    continue
                members.append(k + 1)
                var move = style_move(
                    member.fighter.style, HEAVY_BUTTON, True, FREE
                )
                _ = member.fighter.request(move, 1, True)
            var struck = self.wardens[w].boss.link(members)
            self.tracker.clear()
            self.notes.append(String("LINKED STRIKE x", len(members), "!"))
            self._popup(at + Vector3(0, 1.2, 0), "LINKED", GOLD_TEXT)
            self._popup(at, String(Int(struck.damage + 0.5)), GOLD_TEXT)
            self.freeze = FINISH_STOP
            self.shake = 3 * SHAKE
            self.drawn = True
            self.calm = 0
            if struck.outcome == DEFEATED:
                self._warden_falls()
            return True
        return False

    def _warden_falls(mut self):
        """Give the fallen warden's loot, and say so."""
        self.loot += RAID_LOOT
        self.found += RAID_HERBS
        self.trained[self.fighter.style.value] += RAID_EXPERIENCE
        self.notes.append(
            String("THE STONE WARDEN FALLS! +", RAID_LOOT, " COINS")
        )

    def _attack(mut self, button: FightButton, player: Character) raises:
        """Make the move of an attack's button: a linked strike, a combo's
        finisher, or the button's own move in the player's style."""
        if button == HEAVY_BUTTON and self._link(player):
            return
        var beat = on_beat(self.fighter)
        if button == LIGHT_BUTTON or button == HEAVY_BUTTON:
            var key = LIGHT_KEY if button == LIGHT_BUTTON else HEAVY_KEY
            if self._key(key, beat, player):
                return
        else:
            self.tracker.clear()
        var move = style_move(
            self.fighter.style, button, player.grounded, self.fighter.move
        )
        var boost = BEAT_BONUS if beat else Float32(1)
        if move == ULTIMATE:
            if self.fighter.request(ULTIMATE):
                self.notes.append("ULTIMATE!")
                self.slow = ULTIMATE_SLOW
            return
        if self.fighter.request(move, boost) and is_special(move):
            self.notes.append(move_name(move) + "!")

    def _move_player(
        mut self,
        input: MoveInput,
        yaw: Angle,
        mut player: Character,
        terrain: Terrain,
        blocking: List[Obstacle],
        delta: Duration,
    ) raises:
        """Move the player: by the stick while free, by the move or the
        blow's push while not."""
        var seconds = delta.to(SECOND)
        var move = self.fighter.move
        var began = not self.fighter.free() and (
            move != self.seen or self.fighter.clock < self.seen_clock
        )
        self.seen = move
        self.seen_clock = self.fighter.clock
        if began and self.finisher >= 0 and move != self.finishing:
            # Another move began: the finisher is over.
            if self.fighter.queued != self.finishing:
                self.finisher = -1
        var stick = ground_direction(yaw, input.forward, input.right)
        if began and move == DODGE:
            if stick.length() > 0.1:
                self.dodge_way = stick / stick.length()
            else:
                self.dodge_way = _ahead(player.heading) * -1
        if began and is_attack(move):
            self.threat = True
        var pushed = self.shove.length() > STILL_SHOVE
        if self.fighter.free() and not pushed:
            var share = GUARD_PACE if self.fighter.guarding else Float32(1)
            var walk = MoveInput(
                input.forward * share,
                input.right * share,
                input.look_right,
                input.look_up,
                input.run and not self.fighter.guarding,
                input.jump and not self.fighter.guarding,
            )
            var face: Optional[Angle] = None
            if self.lock >= 0:
                face = yaw_of(self.target_at(self.lock) - player.position)
            player.step(walk, yaw, delta, terrain, blocking, face=face)
            if player.sprinting:
                self.fighter.drain(SPRINT_COST * seconds)
            if self.fighter.stamina <= 0:
                player.tired = True
            elif self.fighter.stamina >= SPRINT_REST:
                player.tired = False
            self._land_hard(player)
            return
        var way = _ahead(player.heading)
        if move == DODGE:
            way = self.dodge_way
        elif is_attack(move):
            var start = move_data(move).startup.to(SECOND) * self.fighter.pace
            var reach = AIM_RANGE if is_melee(
                self.fighter.style
            ) else SHOT_RANGE
            var aim = self.aim(player.position, player.heading, stick, reach)
            if self.fighter.clock < start and aim:
                player.heading = turn_toward(
                    player.heading,
                    aim.value(),
                    Angle(TRACK_TURN * seconds, RADIAN),
                )
            way = _ahead(player.heading)
            # An attack in the air hangs there while it strikes; a plunge
            # dives.
            if not player.grounded and self.fighter.swing():
                player.velocity.y = max(player.velocity.y, Float32(0))
            if move == PLUNGE and not player.grounded:
                player.velocity.y = -PLUNGE_SPEED
        var speed = self.fighter.drive().to(METER_PER_SECOND)
        player.drive(way * speed + self.shove, delta, terrain, blocking)
        self._land_hard(player)

    def _land_hard(mut self, mut player: Character):
        """Shake the camera for a hard landing, and forget it."""
        if player.landed <= 0:
            return
        var over = player.landed - player.parameters.hard_landing.to(
            METER_PER_SECOND
        )
        self.shake = max(self.shake, LANDING_SHAKE * max(Float32(1), over))
        player.landed = 0

    def _move_foes(
        mut self,
        player: Character,
        terrain: Terrain,
        blocking: List[Obstacle],
        delta: Duration,
    ) raises:
        """Let each standing bandit think, and move it."""
        var seconds = delta.to(SECOND)
        var around = blocking.copy()
        ref feet = player.position
        around.append(
            Obstacle(feet.x, feet.z, player.parameters.radius.to(METER))
        )
        var first = len(around)
        around.extend(self.obstacles())
        for index in range(len(self.foes)):
            if self.foes[index].down >= 0:
                continue
            ref foe = self.foes[index]
            var fighter = foe.fighter.copy()
            var ready = fighter.free() or (
                is_attack(fighter.move)
                and fighter.clock >= fighter.active_end()
                and fighter.queued == FREE
            )
            # It goes for the nearest of the player and the raiders who
            # stand with them. The attack token is for the player alone.
            var quarry = -1
            var goal = feet
            var near = Float32(1.0e9)
            if not self.fighter.defeated():
                near = _flat(foe.character.position, feet)
            for k in range(len(self.members)):
                ref member = self.members[k]
                if not member.joined or member.down >= 0:
                    continue
                var there = member.character.position
                var gap = _flat(foe.character.position, there)
                if gap < near:
                    near = gap
                    quarry = k
                    goal = there
            self.quarries[index] = quarry
            var player_quarry = quarry < 0
            var sight = Sight(
                foe.character.position,
                foe.home,
                goal,
                player_quarry and self.fighter.defeated(),
                player_quarry and self.threat,
                fighter.free(),
                ready,
                self.token == index or not player_quarry,
                self.token < 0 and self.token_rest <= 0,
                fighter.raging(),
            )
            var intent = foe.brain.think(sight, delta)
            var toward = yaw_of(goal - foe.character.position)
            foe.fighter.hold_guard(intent.guard)
            if intent.dodge.length() > 0:
                _ = foe.fighter.request(DODGE)
                foe.dodge_way = intent.dodge
            if intent.attack != FREE:
                foe.character.heading = toward
                _ = foe.fighter.request(intent.attack)
            var share = GUARD_PACE if foe.fighter.guarding else Float32(1)
            if foe.fighter.free() and foe.shove.length() <= STILL_SHOVE:
                var walk = MoveInput(
                    -intent.way.z * share,
                    intent.way.x * share,
                    0,
                    0,
                    intent.run,
                    False,
                )
                foe.character.step(
                    walk,
                    Angle(0.0, RADIAN),
                    delta,
                    terrain,
                    around,
                    first + index,
                )
                if intent.face:
                    foe.character.heading = turn_toward(
                        foe.character.heading,
                        toward,
                        Angle(FACE_TURN * seconds, RADIAN),
                    )
            else:
                var speed = foe.fighter.drive().to(METER_PER_SECOND)
                var way = _ahead(foe.character.heading)
                if foe.fighter.move == DODGE:
                    way = foe.dodge_way
                foe.character.drive(
                    way * speed + foe.shove,
                    delta,
                    terrain,
                    around,
                    first + index,
                )
            ref at = foe.character.position
            around[first + index] = Obstacle(
                at.x, at.z, foe.character.parameters.radius.to(METER)
            )
            if intent.claim and player_quarry:
                self.token = index
            if intent.release and self.token == index:
                self.token = -1
                self.token_rest = TOKEN_REST

    def _popup(mut self, at: Vector3, text: String, color: Rgb):
        """Show a number or a word over a fighter's feet."""
        self.popups.append(Popup(at + Vector3(0, HEAD, 0), text, color, 0))

    def _show(
        mut self, mut scene: Scene, struck: Struck, at: Vector3, hurt: Bool
    ) raises:
        """Show what a blow did to the fighter whose feet are `at`: its
        damage, its word and its sparks. `hurt` is True for the player: a
        perfect dodge of theirs slows the foes."""
        var outcome = struck.outcome
        var word = outcome_word(outcome)
        if landed_blow(outcome):
            var color = WHITE_TEXT
            if hurt:
                color = HURT_TEXT
            elif outcome == CRITICAL:
                color = GOLD_TEXT
            self._popup(at, String(Int(struck.damage + 0.5)), color)
            self.sparks.burst(scene, at + Vector3(0, CHEST, 0))
        if word.byte_length() > 0:
            var tone = GOLD_TEXT if landed_blow(outcome) else CALM_TEXT
            self._popup(at + Vector3(0, 0.35, 0), word, tone)
        if outcome == PERFECT_DODGE and hurt:
            self.slow = SLOW_SECONDS

    def _weigh(mut self, struck: Struck, blow: Blow):
        """Stop the fight a moment, and shake the camera, for a strong
        blow; longer and harder for a finisher or a pierce break."""
        if struck.outcome == FINISHED or struck.outcome == PIERCE_BREAK:
            self.freeze = FINISH_STOP
            self.shake = 2 * SHAKE
        elif strong_blow(struck, blow):
            self.freeze = HIT_STOP
            self.shake = SHAKE

    def _player_strikes(mut self, mut scene: Scene, player: Character) raises:
        """Give the player's swing to each target that it reaches."""
        var swing = self.fighter.swing()
        if not swing:
            return
        var reach = swing.value().reach
        var arc = swing.value().arc
        ref feet = player.position
        for index in range(self.targets()):
            if not self.standing(index):
                continue
            var there = self.target_at(index)
            var radius = Length(self.target_radius(index), METER)
            if not reaches(feet, player.heading, reach, arc, there, radius):
                continue
            var blow = self.fighter.connect(index)
            if not blow:
                continue
            self._land(scene, index, blow.value(), feet)

    def _land(
        mut self, mut scene: Scene, index: Int, hit: Blow, source: Vector3
    ) raises:
        """Give one of the player's blows to a target: from a swing, or
        from a ground wave's wave at `source`. The player learns what it
        did, and trains."""
        var tank = self.fighter.style == MACE
        var struck = self._strike(scene, index, hit, source, 0, tank)
        var style = self.fighter.style.value
        if index >= len(self.foes):
            self.trained[style] += PRACTICE_EXPERIENCE
        elif landed_blow(struck.outcome):
            self.trained[style] += BLOW_EXPERIENCE
        var finished = self.finisher >= 0 and not self.finisher_landed
        if finished and landed_blow(struck.outcome):
            self.finisher_landed = True
            self._afflict(scene, index, struck, hit)
            self._perks(self.finisher)
            self._master(self.finisher, LAND_MASTERY)
        self.fighter.landed(struck)

    def _strike(
        mut self,
        mut scene: Scene,
        index: Int,
        given: Blow,
        source: Vector3,
        member: Int = 0,
        tank: Bool = False,
    ) raises -> Struck:
        """Give a blow from `source` to a target, show it, and weigh it; a
        felled foe gives its loot. `member` is who struck it, for a
        warden's threat: 0 for the player, and 1 and on for the raiders.
        A marked target takes `MARK_BONUS` times the blow's damage. Return
        what the blow did."""
        var hit = given
        if self.marks[index] > 0:
            hit.damage *= MARK_BONUS
        var there = self.target_at(index)
        var way = _way(source, there)
        var struck: Struck
        var raged = False
        if index < len(self.foes):
            ref foe = self.foes[index]
            var front = faces(
                there,
                foe.character.heading,
                foe.fighter.parameters.guard_arc,
                source,
            )
            var calm = not foe.fighter.raging()
            struck = foe.fighter.receive(hit, front)
            foe.shove = push_of(struck, hit, way)
            raged = calm and foe.fighter.raging()
            throw_up(foe.character, struck, hit)
            # An attacking foe holds the token: its brain claims it before
            # it attacks, and lets go of the attack without it.
            if landed_blow(struck.outcome) and foe.brain.hurt():
                self.token = -1
                self.token_rest = TOKEN_REST
            var fell = struck.outcome == DEFEATED
            if fell or struck.outcome == FINISHED:
                self.trained[self.fighter.style.value] += DEFEAT_EXPERIENCE
            if (fell or struck.outcome == FINISHED) and not foe.beast:
                self.loot += LOOT
                var note = String("+", LOOT, " COINS")
                if foe.brain.roll(6) < HERB_CHANCE:
                    self.found += 1
                    note += " +1 HERB"
                self.notes.append(note)
        elif index < self.first_warden():
            ref practice = self.dummies[index - len(self.foes)]
            struck = practice.fighter.receive(hit, False)
            practice.dummy.knock(way, hit.knockback.to(METER_PER_SECOND))
            practice.fighter.health = practice.fighter.parameters.health
        else:
            ref warden = self.wardens[index - self.first_warden()]
            struck = warden.boss.receive(hit, member, tank)
            if struck.outcome == STAMINA_BREAK:
                self.notes.append("THE WARDEN STAGGERS!")
            if struck.outcome == DEFEATED:
                self._warden_falls()
        if raged:
            self._popup(there + Vector3(0, 0.7, 0), "RAGE", HURT_TEXT)
        self._show(scene, struck, there, False)
        self._weigh(struck, hit)
        return struck

    def _send_waves(
        mut self, mut scene: Scene, player: Character, h: Float32
    ) raises:
        """Send a ground wave's wave as its cut swings, and run each wave
        on by `h` seconds: it strikes each standing target it passes over
        once, and fades out at `WAVE_RANGE`."""
        if self.fighter.move == GROUND_WAVE and self.fighter.launched():
            var ahead = _ahead(player.heading)
            self.waves.append(
                Wave(
                    player.position + ahead * WAVE_START,
                    ahead,
                    0,
                    self.fighter.blow(),
                    List[Int](),
                )
            )
        var kept = List[Wave]()
        for w in range(len(self.waves)):
            var wave = self.waves[w].copy()
            wave.at = wave.at + wave.way * (WAVE_SPEED * h)
            wave.gone += WAVE_SPEED * h
            for index in range(self.targets()):
                if not self.standing(index):
                    continue
                var there = self.target_at(index)
                if _flat(wave.at, there) > WAVE_WIDTH / 2:
                    continue
                if abs(there.y - wave.at.y) > REACH_HEIGHT:
                    continue
                var seen = False
                for k in wave.struck:
                    if k == index:
                        seen = True
                if seen:
                    continue
                wave.struck.append(index)
                self._land(scene, index, wave.blow, wave.at - wave.way)
            if wave.gone < WAVE_RANGE:
                kept.append(wave^)
        self.waves = kept^

    def shot_target(self, at: Vector3, heading: Angle) -> Int:
        """Return the target a spell or an arrow of the player's flies at.

        Args:
            at: Where the player stands.
            heading: The way they face.

        Returns:
            The locked target; else the nearest standing target within
            `SHOT_RANGE` and `SHOT_ARC` before them; else -1.
        """
        if self.lock >= 0:
            return self.lock
        var best = -1
        var nearest = SHOT_RANGE
        for index in range(self.targets()):
            if not self.standing(index):
                continue
            var there = self.target_at(index)
            var gap = _flat(at, there)
            if gap < nearest and faces(
                at, heading, Angle(SHOT_ARC, DEGREE), there
            ):
                nearest = gap
                best = index
        return best

    def _shoot(mut self, player: Character) raises:
        """Send the missiles of the player's spell or shot, as it looses."""
        var target = self.shot_target(player.position, player.heading)
        var move = self.fighter.move
        var blow = self.fighter.blow()
        self._launch(player.position, player.heading, move, blow, target, -1)

    def _launch(
        mut self,
        at: Vector3,
        heading: Angle,
        move: CombatMove,
        blow: Blow,
        target: Int,
        owner: Int,
    ) raises:
        """Send the missiles of a spell or a shot from a fighter's hand, at
        a target or straight ahead; `owner` is -1 for the player, else the
        raider's index."""
        var ahead = _ahead(heading)
        var hand = at + ahead * SHOT_AHEAD + Vector3(0, SHOT_HEIGHT, 0)
        var aim = hand + ahead * 20
        if target >= 0:
            aim = self.target_at(target) + Vector3(0, CHEST, 0)
        var way = aim - hand
        way = way / max(way.length(), Float32(1.0e-4))
        if move == SPELL_BOLT:
            self.shots.append(
                Missile(SPARK, hand, way * SPARK_SPEED, target, owner, blow)
            )
        elif move == SPELL_BLAST:
            self.shots.append(
                Missile(ORB, hand, way * ORB_SPEED, target, owner, blow)
            )
        elif move == VOLLEY:
            var flight = lob(hand, aim, ARROW_SPEED)
            var level = Vector3(flight.x, 0, flight.z) / ARROW_SPEED
            for side in fan(  # pragma: no branch
                level, VOLLEY_ARROWS, VOLLEY_SPREAD
            ):
                var v = side * ARROW_SPEED + Vector3(0, flight.y, 0)
                self.shots.append(Missile(ARROW, hand, v, -1, owner, blow))
        elif move == ARROW_RAIN:
            var center = at + ahead * RAIN_REACH
            if target >= 0:
                center = self.target_at(target)
            for spot in rain_spots(center, RAIN_ARROWS):  # pragma: no branch
                self.shots.append(
                    Missile(
                        ARROW, spot, Vector3(0, -RAIN_SPEED, 0), -1, owner, blow
                    )
                )
        else:
            var pierce = AIMED_PIERCE if move == AIMED_SHOT else 0
            self.shots.append(
                Missile(
                    ARROW,
                    hand,
                    lob(hand, aim, ARROW_SPEED),
                    target,
                    owner,
                    blow,
                    pierce,
                )
            )

    def _storm(mut self, player: Character) raises:
        """Send a ranged style's ultimate as it rises: on each standing
        target within `STORM_RANGE`, a star of light falls for magic, and a
        rain of arrows for archery."""
        var blow = self.fighter.blow()
        var magic = self.fighter.style == MAGIC
        for index in range(self.targets()):
            if not self.standing(index):
                continue
            var there = self.target_at(index)
            if _flat(there, player.position) > STORM_RANGE:
                continue
            if magic:
                var high = there + Vector3(0, STORM_HEIGHT, 0)
                var fall = Vector3(0, -2 * ORB_SPEED, 0)
                self.shots.append(Missile(ORB, high, fall, index, -1, blow))
            else:
                var fall = Vector3(0, -RAIN_SPEED, 0)
                for spot in rain_spots(there, RAIN_ARROWS):  # pragma: no branch
                    self.shots.append(Missile(ARROW, spot, fall, -1, -1, blow))
        self.notes.append("STARFALL!" if magic else "ARROW STORM!")

    def _mend(mut self, player: Character) raises:
        """Heal the player, the companion and each raider near them, as a
        mend's light rises. Each warden learns of the heal."""
        var share = MEND_HEAL * self.fighter.boost
        ref f = self.fighter
        var gain = min(
            f.parameters.health - f.health, share * f.parameters.health
        )
        f.health += gain
        self.mended = 0
        var amount = String(Int(gain + 0.5))
        self._popup(player.position, "+" + amount, HEAL_TEXT)
        self.notes.append("MEND +" + amount)
        for k in range(len(self.allies)):
            ref ally = self.allies[k]
            if _flat(ally.character.position, player.position) > MEND_RADIUS:
                continue
            ref a = ally.fighter
            var more = min(
                a.parameters.health - a.health, share * a.parameters.health
            )
            a.health += more
            var place = ally.character.position
            self._popup(place, "+" + String(Int(more + 0.5)), HEAL_TEXT)
        var healed = gain
        for k in range(len(self.members)):
            ref member = self.members[k]
            if not member.joined or member.down >= 0:
                continue
            var place = member.character.position
            if _flat(place, player.position) > MEND_RADIUS:
                continue
            ref m = member.fighter
            var more = min(
                m.parameters.health - m.health, share * m.parameters.health
            )
            m.health += more
            healed += more
            self._popup(place, "+" + String(Int(more + 0.5)), HEAL_TEXT)
        for w in range(len(self.wardens)):
            self.wardens[w].boss.healed(0, healed)

    def _send_shots(
        mut self,
        mut scene: Scene,
        player: Character,
        terrain: Terrain,
        h: Float32,
    ) raises:
        """Send the player's spell or shot as it looses, and fly each of the
        player's missiles on by `h` seconds: it strikes each target it
        passes, an orb bursts on every target near, and a missile ends at
        the ground, at the end of its life, or when it can pass through no
        more."""
        if self.fighter.launched():
            if is_shot(self.fighter.move):
                self._shoot(player)
            elif self.fighter.move == MEND:
                self._mend(player)
            elif self.fighter.move == ULTIMATE and not is_melee(
                self.fighter.style
            ):
                self._storm(player)
        var kept = List[Missile]()
        for k in range(len(self.shots)):
            var shot = self.shots[k].copy()
            var aim: Optional[Vector3] = None
            if shot.target >= 0 and self.standing(shot.target):
                aim = self.target_at(shot.target) + Vector3(0, CHEST, 0)
            fly(shot, h, aim)
            if shot.spent():
                continue
            var floor = terrain.ground.height_at(shot.at.x, shot.at.z)
            var done = shot.at.y < floor
            for index in range(self.targets()):
                if done:
                    break
                if not self.standing(index) or shot.has_struck(index):
                    continue
                var chest = self.target_at(index) + Vector3(0, CHEST, 0)
                if not touches(shot, chest):
                    continue
                if shot.splash() > 0:
                    for other in range(self.targets()):  # pragma: no branch
                        if not self.standing(other):
                            continue
                        var there = self.target_at(other)
                        var chest_at = there + Vector3(0, CHEST, 0)
                        if (chest_at - shot.at).length() <= shot.splash():
                            self._hit_by(scene, shot, other)
                    self.sparks.burst(scene, shot.at)
                    done = True
                    continue
                self._hit_by(scene, shot, index)
                shot.struck.append(index)
                if shot.pierce > 0:
                    shot.pierce -= 1
                else:
                    done = True
            if not done:
                kept.append(shot^)
        self.shots = kept^

    def _hit_by(mut self, mut scene: Scene, shot: Missile, index: Int) raises:
        """Give a missile's blow to a target: the player's as a blow of
        theirs, a raider's as the raider's."""
        if shot.owner < 0:
            self._land(scene, index, shot.blow, shot.origin)
            return
        var role = self.members[shot.owner].mind.role
        var struck = self._strike(
            scene, index, shot.blow, shot.origin, shot.owner + 1, role == TANK
        )
        self.members[shot.owner].fighter.landed(struck)

    def _send_bolts(mut self, mut scene: Scene, h: Float32) raises:
        """Send the companion's bolt as her cast points, and fly each bolt
        on by `h` seconds toward its target's chest: it strikes there, or
        fades when its target falls or after `BOLT_LIFE`."""
        for k in range(len(self.allies)):
            ref ally = self.allies[k]
            if not (ally.fighter.move == CAST and ally.fighter.launched()):
                continue
            var at = ally.character.position
            var ahead = _ahead(ally.character.heading)
            var blow = ally.fighter.blow()
            if ally.assisting:
                blow = assist_blow(ally.fighter.parameters.might)
            self.bolts.append(
                Bolt(
                    at + ahead * BOLT_START + Vector3(0, CHEST, 0),
                    at,
                    ally.aim,
                    blow,
                    ally.assisting,
                    0,
                )
            )
            ally.assisting = False
        var kept = List[Bolt]()
        for b in range(len(self.bolts)):
            var bolt = self.bolts[b].copy()
            bolt.age += h
            if bolt.age > BOLT_LIFE or not self.standing(bolt.target):
                continue
            var off = self.target_at(bolt.target) + Vector3(0, CHEST, 0)
            off = off - bolt.at
            var gap = off.length()
            var step = BOLT_SPEED * h
            if gap > max(step, BOLT_REACH):
                bolt.at = bolt.at + off * (step / gap)
                kept.append(bolt^)
                continue
            var struck = self._strike(
                scene, bolt.target, bolt.blow, bolt.origin
            )
            if landed_blow(struck.outcome):
                for k in range(len(self.allies)):
                    self.allies[k].mind.charge(ASSIST_PER_HIT)
        self.bolts = kept^

    def ally_target(self, at: Vector3) -> Int:
        """Return the target the companion casts at.

        Args:
            at: Where the player stands.

        Returns:
            The locked target while it stands; else the nearest standing
            foe within `ALLY_SEEK` of the player that fights, neither at
            its post nor going back to it; else -1.
        """
        if self.lock >= 0 and self.standing(self.lock):
            return self.lock
        for w in range(len(self.wardens)):
            ref boss = self.wardens[w].boss
            if boss.engaged and not boss.defeated():
                return self.first_warden() + w
        var best = -1
        var nearest = ALLY_SEEK
        for index in range(len(self.foes)):
            ref foe = self.foes[index]
            var state = foe.brain.state
            if foe.down >= 0 or state == POSTED or state == RETURNING:
                continue
            var gap = _flat(foe.character.position, at)
            if gap < nearest:
                nearest = gap
                best = index
        return best

    def _move_ally(
        mut self,
        player: Character,
        terrain: Terrain,
        blocking: List[Obstacle],
        delta: Duration,
    ) raises:
        """Let the companion think: move her, and let her cast, heal and
        make the assist attack the player calls for."""
        var seconds = delta.to(SECOND)
        var around = blocking.copy()
        var first = len(around) + len(self.foes) + len(self.dummies)
        around.extend(self.obstacles())
        var aim = self.ally_target(player.position)
        var target: Optional[Vector3] = None
        if aim >= 0:
            target = self.target_at(aim)
        ref p = self.fighter.parameters
        var share = self.fighter.health / p.health
        var mend = Float32(0)
        var assisted = False
        for k in range(len(self.allies)):
            ref ally = self.allies[k]
            var sight = AllySight(
                ally.character.position,
                player.position,
                target,
                share,
                ally.fighter.free(),
                self.drawn,
            )
            var intent = ally.mind.think(sight, delta)
            if self.called and aim >= 0 and ally.mind.spend():
                assisted = True
                ally.assisting = True
                ally.aim = aim
                _ = ally.fighter.request(CAST)
            elif intent.cast:
                ally.aim = aim
                _ = ally.fighter.request(CAST)
            if intent.heal:
                mend = MEND_SHARE * p.health
            if not ally.fighter.free():
                if target:
                    ally.character.heading = yaw_of(
                        target.value() - ally.character.position
                    )
                continue
            var walk = MoveInput(
                -intent.way.z, intent.way.x, 0, 0, intent.run, False
            )
            ally.character.step(
                walk,
                Angle(0.0, RADIAN),
                delta,
                terrain,
                around,
                first + k,
            )
            if intent.face:
                ally.character.heading = turn_toward(
                    ally.character.heading,
                    yaw_of(intent.face.value() - ally.character.position),
                    Angle(FACE_TURN * seconds, RADIAN),
                )
        if assisted:
            self.notes.append("ASSIST ATTACK!")
        if mend > 0:
            var gain = min(p.health - self.fighter.health, mend)
            self.fighter.health += gain
            var amount = String(Int(gain + 0.5))
            self._popup(player.position, "+" + amount, HEAL_TEXT)
            self.notes.append("YOUR COMPANION HEALS " + amount)

    def _foe_strikes(
        mut self, mut scene: Scene, index: Int, mut player: Character
    ) raises:
        """Give a foe's swing to the member it goes for, if it reaches
        them."""
        var swing = self.foes[index].fighter.swing()
        if not swing:
            return
        var quarry = self.quarries[index]
        if quarry >= 0:
            self._strike_raider(scene, index, quarry)
            return
        ref feet = player.position
        var at = self.foes[index].character.position
        if not reaches(
            at,
            self.foes[index].character.heading,
            swing.value().reach,
            swing.value().arc,
            feet,
            player.parameters.radius,
        ):
            return
        var blow = self.foes[index].fighter.connect(0)
        if not blow:
            return
        self._hurt(scene, index, blow.value(), at, player)

    def _strike_raider(mut self, mut scene: Scene, index: Int, k: Int) raises:
        """Give a foe's swing to the raider `k`, if it reaches them."""
        ref foe = self.foes[index]
        var swing = foe.fighter.swing().value()
        ref member = self.members[k]
        var at = foe.character.position
        var there = member.character.position
        var radius = member.character.parameters.radius
        if not reaches(
            at, foe.character.heading, swing.reach, swing.arc, there, radius
        ):
            return
        var blow = foe.fighter.connect(k + 1)
        if not blow:
            return
        var front = faces(
            there,
            member.character.heading,
            member.fighter.parameters.guard_arc,
            at,
        )
        var struck = member.fighter.receive(blow.value(), front)
        member.shove = push_of(struck, blow.value(), _way(at, there))
        self._show(scene, struck, there, False)

    def _hurt(
        mut self,
        mut scene: Scene,
        index: Int,
        hit: Blow,
        source: Vector3,
        mut player: Character,
    ) raises:
        """Give a foe's blow from `source` to the player: a swing's, or a
        knife's. The foe learns what it did."""
        ref feet = player.position
        var front = faces(
            feet, player.heading, self.fighter.parameters.guard_arc, source
        )
        var struck = self.fighter.receive(hit, front)
        self.foes[index].fighter.landed(struck)
        self.shove = push_of(struck, hit, _way(source, feet))
        throw_up(player, struck, hit)
        self._show(scene, struck, feet, True)
        self._weigh(struck, hit)

    def _send_knives(
        mut self, mut scene: Scene, mut player: Character, h: Float32
    ) raises:
        """Send a thrower's knife as its arm flings, at the player's chest;
        and fly each knife on by `h` seconds: it strikes the player when
        it passes within `KNIFE_REACH` of their chest, and falls after
        `KNIFE_LIFE`."""
        var chest = player.position + Vector3(0, CHEST, 0)
        for index in range(len(self.foes)):
            ref foe = self.foes[index]
            if not (foe.fighter.move == THROW and foe.fighter.launched()):
                continue
            var hand = foe.character.position + Vector3(0, CHEST, 0)
            var way = chest - hand
            way = way / max(way.length(), Float32(1.0e-4))
            self.knives.append(
                Knife(
                    hand + way * 0.5,
                    way,
                    foe.character.position,
                    index,
                    foe.fighter.blow(),
                    0,
                )
            )
        var kept = List[Knife]()
        for k in range(len(self.knives)):
            var knife = self.knives[k].copy()
            knife.age += h
            knife.at = knife.at + knife.way * (KNIFE_SPEED * h)
            if knife.age > KNIFE_LIFE:
                continue
            if (chest - knife.at).length() <= KNIFE_REACH:
                self._hurt(
                    scene, knife.thrower, knife.blow, knife.origin, player
                )
                continue
            kept.append(knife^)
        self.knives = kept^

    def _exchange(
        mut self,
        mut scene: Scene,
        mut player: Character,
        terrain: Terrain,
        delta: Duration,
    ) raises:
        """Run the fighters' clocks in steps, and give each swing's blows."""
        var seconds = delta.to(SECOND)
        var steps = max(1, Int(ceil(seconds / COMBAT_STEP)))
        var h = seconds / Float32(steps)
        var pace = SLOW_SHARE if self.slow > 0 else Float32(1)
        for _ in range(steps):  # pragma: no branch
            self.fighter.update(Duration(h, SECOND))
            for index in range(len(self.foes)):
                self.foes[index].fighter.update(Duration(h * pace, SECOND))
            for index in range(len(self.dummies)):
                self.dummies[index].fighter.update(Duration(h, SECOND))
            for index in range(len(self.allies)):
                self.allies[index].fighter.update(Duration(h, SECOND))
            for index in range(len(self.members)):
                self.members[index].fighter.update(Duration(h, SECOND))
                self._member_strikes(scene, index, player)
            self._player_strikes(scene, player)
            self._send_waves(scene, player, h)
            self._send_shots(scene, player, terrain, h)
            self._send_bolts(scene, h)
            self._send_knives(scene, player, h)
            for index in range(len(self.foes)):
                self._foe_strikes(scene, index, player)

    def _settle(
        mut self,
        mut scene: Scene,
        mut player: Character,
        terrain: Terrain,
        delta: Duration,
    ) raises:
        """Age what shows, fade the pushes, lay down the fallen and bring
        them back, and draw or sheathe the sword."""
        var seconds = delta.to(SECOND)
        var kept = List[Popup]()
        for popup in self.popups:
            if popup.age + seconds < POPUP_SECONDS:
                kept.append(
                    Popup(
                        popup.at + Vector3(0, POPUP_RISE * seconds, 0),
                        popup.text,
                        popup.color,
                        popup.age + seconds,
                    )
                )
        self.popups = kept^
        self.sparks.update(scene, delta)
        self._effects_step(seconds)
        for index in range(len(self.dummies)):
            self.dummies[index].dummy.rock(scene, delta)
        var fade = exp(-SHOVE_FADE * seconds)
        self.shove = self.shove * fade
        self.slow = max(Float32(0), self.slow - seconds)
        if self.pulsed >= 0:
            self.pulsed += seconds
        if self.beat >= 0:
            self.beat += seconds
        if self.mended >= 0:
            self.mended += seconds
        self.tracker.update(seconds)
        self.taunt_wait = max(Float32(0), self.taunt_wait - seconds)
        var fighting = False
        for w in range(len(self.wardens)):
            ref warden = self.wardens[w]
            if warden.boss.engaged and not warden.boss.defeated():
                fighting = True
                if _flat(warden.character.position, player.position) < ENGAGE:
                    self.drawn = True
                    self.calm = 0
            if not warden.boss.defeated():
                continue
            if warden.down < 0:
                warden.down = 0
            warden.down += seconds
            if warden.down > self.parameters.respawn.to(SECOND):
                warden.character.position = warden.home
                warden.character.heading = warden.heading
                warden.boss = Boss(len(warden.boss.threat), warden.boss.seed)
                warden.down = -1
        for k in range(len(self.members)):
            ref member = self.members[k]
            member.shove = member.shove * exp(-SHOVE_FADE * seconds)
            if member.fighter.defeated() and member.down < 0:
                member.down = 0
                member.revive = 0
            if member.down < 0:
                continue
            member.down += seconds
            if not fighting and member.down > RISE_SECONDS:
                member.fighter.revive()
                member.down = -1
        self.token_rest -= seconds
        ref p = self.parameters
        # A move or a guard draws the weapon; a roll does not.
        var moving = not self.fighter.free() and self.fighter.move != DODGE
        var engaged = moving or self.fighter.guarding
        for index in range(len(self.foes)):
            var node = self.node_of(index)
            ref foe = self.foes[index]
            foe.shove = foe.shove * fade
            if not foe.fighter.defeated():
                var state = foe.brain.state
                var near = _flat(foe.character.position, player.position)
                if near < ENGAGE and state != POSTED and state != RETURNING:
                    engaged = True
                continue
            if foe.down < 0:
                foe.down = 0
                if self.token == index:
                    self.token = -1
                if self.lock == index:
                    self.lock = -1
            foe.down += seconds
            if foe.down > p.linger.to(SECOND):
                scene.node(node).visible = False
            if foe.down > p.respawn.to(SECOND):
                foe.character.position = foe.home
                foe.character.heading = foe.heading
                foe.fighter.revive()
                foe.brain = Brain(foe.brain.seed)
                foe.down = -1
                scene.node(node).visible = True
        if (
            self.lock >= 0
            and _flat(player.position, self.target_at(self.lock)) > LOCK_BREAK
        ):
            self.lock = -1
        if self.fighter.defeated():
            if self.down < 0:
                self.down = 0
                self.lock = -1
                self.notes.append("YOU FALL")
            self.down += seconds
            if self.down > p.revive.to(SECOND):
                var x = self.start.x
                var z = self.start.z
                var ground = terrain.ground.height_at(x, z)
                player.position = Vector3(x, terrain.height_at(x, z, ground), z)
                player.velocity = Vector3(0, 0, 0)
                player.grounded = True
                self.fighter.revive()
                self.shove = Vector3(0, 0, 0)
                self.down = -1
                self.notes.append("YOU COME TO BY THE TRAIL")
        if engaged or self.lock >= 0:
            self.drawn = True
            self.calm = 0
        else:
            self.calm += seconds
            if self.calm > CALM_SECONDS:
                self.drawn = False

    def _move_wardens(
        mut self,
        mut scene: Scene,
        mut player: Character,
        terrain: Terrain,
        blocking: List[Obstacle],
        delta: Duration,
    ) raises:
        """Let each warden think, move it, and strike with its zones, its
        rockfalls and its summons."""
        var seconds = delta.to(SECOND)
        var places = List[Vector3]()
        var up = List[Bool]()
        places.append(player.position)
        up.append(not self.fighter.defeated())
        for k in range(len(self.members)):
            ref member = self.members[k]
            places.append(member.character.position)
            up.append(member.joined and member.down < 0)
        var around = blocking.copy()
        ref feet = player.position
        around.append(
            Obstacle(feet.x, feet.z, player.parameters.radius.to(METER))
        )
        for w in range(len(self.wardens)):
            if self.wardens[w].boss.defeated():
                continue
            ref warden = self.wardens[w]
            var sight = BossSight(
                warden.character.position,
                _ahead(warden.character.heading),
                warden.home,
                places.copy(),
                up.copy(),
            )
            var intent = warden.boss.think(sight, seconds)
            if intent.charging:
                var run = intent.zone.way * CHARGE_SPEED
                warden.character.drive(run, delta, terrain, around)
            elif warden.boss.busy() or warden.boss.staggered > 0:
                warden.character.drive(Vector3(0, 0, 0), delta, terrain, around)
            else:
                var walk = MoveInput(
                    -intent.way.z, intent.way.x, 0, 0, False, False
                )
                warden.character.step(
                    walk, Angle(0.0, RADIAN), delta, terrain, around
                )
            var busy = warden.boss.busy() and warden.boss.warning() > 0
            if intent.face and not intent.charging and not busy:
                warden.character.heading = turn_toward(
                    warden.character.heading,
                    yaw_of(intent.face.value() - warden.character.position),
                    Angle(FACE_TURN * 0.35 * seconds, RADIAN),
                )
            if intent.strikes:
                self._zone_strikes(scene, w, player)
            if len(intent.rock) > 0:
                self._rockfall(scene, intent.rock, player)
            if intent.summon:
                self._summon(w)

    def _zone_strikes(
        mut self, mut scene: Scene, w: Int, mut player: Character
    ) raises:
        """Give a warden's attack to each member in its zone."""
        ref warden = self.wardens[w]
        var blow = warden.boss.attack_blow()
        var zone = warden.boss.zone
        var source = warden.character.position
        self.shake = max(self.shake, 2 * SHAKE)
        ref feet = player.position
        var r = player.parameters.radius.to(METER)
        if not self.fighter.defeated() and inside(zone, feet, r):
            var front = faces(
                feet, player.heading, self.fighter.parameters.guard_arc, source
            )
            var struck = self.fighter.receive(blow, front)
            self.shove = push_of(struck, blow, _way(source, feet))
            throw_up(player, struck, blow)
            self._show(scene, struck, feet, True)
            self._weigh(struck, blow)
        for k in range(len(self.members)):
            ref member = self.members[k]
            if not member.joined or member.down >= 0:
                continue
            ref at = member.character.position
            var radius = member.character.parameters.radius.to(METER)
            if not inside(zone, at, radius):
                continue
            var front = faces(
                at,
                member.character.heading,
                member.fighter.parameters.guard_arc,
                source,
            )
            var struck = member.fighter.receive(blow, front)
            member.shove = push_of(struck, blow, _way(source, at))
            var place = at
            self._show(scene, struck, place, False)

    def _rockfall(
        mut self, mut scene: Scene, rock: List[Float32], mut player: Character
    ) raises:
        """Let a rockfall's boulder fall: each member near shares its
        damage."""
        self.shake = max(self.shake, 3 * SHAKE)
        self.notes.append("ROCKFALL!")
        if rock[0] > 0 and not self.fighter.defeated():
            var blow = rock_blow(rock[0])
            var struck = self.fighter.receive(blow, False)
            self._show(scene, struck, player.position, True)
            self.sparks.burst(scene, player.position + Vector3(0, CHEST, 0))
        for k in range(len(self.members)):
            if k + 1 >= len(rock) or rock[k + 1] <= 0:
                continue
            var blow = rock_blow(rock[k + 1])
            var struck = self.members[k].fighter.receive(blow, False)
            var place = self.members[k].character.position
            self._show(scene, struck, place, False)

    def _summon(mut self, w: Int) raises:
        """Call the den's wolves to a warden: each fallen wolf stands up
        beside it, and every wolf comes."""
        var at = self.wardens[w].character.position
        var k = 0
        for index in range(len(self.foes)):
            ref foe = self.foes[index]
            if not foe.beast:
                continue
            var turn = Float32(k) * 2.1
            var place = at + Vector3(cos(turn) * 4, 0, sin(turn) * 4)
            k += 1
            if foe.down >= 0:
                foe.fighter.revive()
                foe.down = -1
                foe.character.position = place
            foe.brain = Brain.wolf(foe.brain.seed)
            foe.character.position = place
        self.notes.append("THE WARDEN CALLS ITS WOLVES!")

    def _member_target(self) -> Int:
        """Return the target the raiders fight: a warden in its fight, or
        -1."""
        for w in range(len(self.wardens)):
            ref boss = self.wardens[w].boss
            if boss.engaged and not boss.defeated():
                return self.first_warden() + w
        return -1

    def _move_members(
        mut self,
        mut scene: Scene,
        player: Character,
        terrain: Terrain,
        blocking: List[Obstacle],
        delta: Duration,
    ) raises:
        """Let each raider join or leave, think, and move: by its stick
        while free, by its move or a blow's push while not."""
        var seconds = delta.to(SECOND)
        var around = blocking.copy()
        ref feet = player.position
        around.append(
            Obstacle(feet.x, feet.z, player.parameters.radius.to(METER))
        )
        var first = len(around)
        around.extend(self.obstacles())
        var skip_from = first + self.first_warden() + len(self.allies)
        skip_from += len(self.wardens)
        var target = self._member_target()
        var joined_now = False
        # The places that each raider sees: the hurt, the fallen, the mark.
        var hurt: Optional[Vector3] = None
        var lowest = MEND_BELOW
        ref f = self.fighter
        var share = f.health / f.parameters.health
        if not f.defeated() and share < lowest:
            lowest = share
            hurt = feet
        var fallen: Optional[Vector3] = None
        for k in range(len(self.members)):
            ref other = self.members[k]
            if not other.joined:
                continue
            if other.down >= 0:
                fallen = other.character.position
                continue
            var part = other.fighter.health / other.fighter.parameters.health
            if part < lowest:
                lowest = part
                hurt = other.character.position
        for k in range(len(self.members)):
            var near = _flat(feet, self.members[k].post)
            var gone = self.fighter.defeated()
            if not self.members[k].joined and near < JOIN_RANGE and not gone:
                self.members[k].joined = True
                joined_now = True
            elif self.members[k].joined and near > PART_RANGE:
                self.members[k].joined = False
            if self.members[k].down >= 0:
                continue
            ref mine = self.members[k]
            var sight = MemberSight(
                mine.character.position,
                feet,
                None,
                Vector3(0, 0, 1),
                None,
                0,
                False,
                None,
                mine.fighter.health / mine.fighter.parameters.health,
                hurt,
                fallen,
                mine.fighter.free(),
                False,
                False,
            )
            var joined = mine.joined
            if not joined:
                sight.leader = mine.post
            if target >= 0 and joined:
                ref warden = self.wardens[target - self.first_warden()]
                sight.target = warden.character.position
                sight.facing = _ahead(warden.character.heading)
                sight.fighting = True
                sight.targeted = warden.boss.target == k + 1
                if warden.boss.busy() and warden.boss.warning() > 0:
                    sight.danger = warden.boss.zone
                    sight.warning = warden.boss.warning()
                    sight.blockable = not warden.boss.attack_blow().unblockable
                var marked = warden.boss.marked
                if marked >= 0:
                    sight.stack = feet
                    if marked > 0:
                        sight.stack = self.members[
                            marked - 1
                        ].character.position
            var intent = self.members[k].mind.think(sight, seconds)
            var place = self.members[k].character.position
            # A raider taunts and attacks only in a warden's fight.
            var aim = place
            if target >= 0:
                aim = self.target_at(target)
                if intent.taunt:
                    var w = target - self.first_warden()
                    self.wardens[w].boss.taunt(k + 1)
                    self._popup(place, "TAUNT", GOLD_TEXT)
            if intent.revive:
                self._revive_near(place, seconds)
            ref member = self.members[k]
            member.fighter.hold_guard(intent.guard)
            if intent.dodge.length() > 0:
                if member.fighter.request(DODGE):
                    member.dodge_way = intent.dodge
            if intent.attack != FREE:
                member.character.heading = yaw_of(aim - place)
                _ = member.fighter.request(intent.attack)
            var pushed = member.shove.length() > STILL_SHOVE
            if member.fighter.free() and not pushed:
                var share_pace = (
                    GUARD_PACE if member.fighter.guarding else Float32(1)
                )
                var walk = MoveInput(
                    -intent.way.z * share_pace,
                    intent.way.x * share_pace,
                    0,
                    0,
                    intent.run,
                    False,
                )
                var face: Optional[Angle] = None
                if intent.face:
                    face = yaw_of(
                        intent.face.value() - member.character.position
                    )
                member.character.step(
                    walk,
                    Angle(0.0, RADIAN),
                    delta,
                    terrain,
                    around,
                    skip_from + k,
                    face=face,
                )
            else:
                var speed = member.fighter.drive().to(METER_PER_SECOND)
                var way = _ahead(member.character.heading)
                if member.fighter.move == DODGE:
                    way = member.dodge_way
                member.character.drive(
                    way * speed + member.shove,
                    delta,
                    terrain,
                    around,
                    skip_from + k,
                )
        if joined_now:
            self.notes.append("THE RAIDERS JOIN YOUR PARTY")

    def _revive_near(mut self, at: Vector3, seconds: Float32):
        """Revive the fallen raider within `REVIVE_REACH` of a point, once a
        member has stood by it for `REVIVE_SECONDS`."""
        for k in range(len(self.members)):
            ref member = self.members[k]
            if member.down < 0:
                continue
            if _flat(member.character.position, at) > REVIVE_REACH:
                continue
            member.revive += seconds
            if member.revive >= REVIVE_SECONDS:
                member.fighter.revive()
                member.fighter.health *= REVIVE_SHARE
                member.down = -1
                member.revive = 0
                self.notes.append("A RAIDER IS REVIVED")
            return

    def _member_strikes(
        mut self, mut scene: Scene, k: Int, player: Character
    ) raises:
        """Give a raider's swing to each foe and warden it reaches; send its
        spell or shot; and heal with its mend."""
        if self.members[k].down >= 0:
            return
        var role = self.members[k].mind.role
        var tank = role == TANK
        if self.members[k].fighter.launched():
            var move = self.members[k].fighter.move
            ref member = self.members[k]
            if is_shot(move):
                var target = self._member_target()
                var at = member.character.position
                var heading = member.character.heading
                var blow = member.fighter.blow()
                self._launch(at, heading, move, blow, target, k)
            elif move == MEND:
                self._party_mend(k, player)
        var swing = self.members[k].fighter.swing()
        if not swing:
            return
        var feet = self.members[k].character.position
        var heading = self.members[k].character.heading
        # A raid has its warden, so there is a target.
        for index in range(self.targets()):  # pragma: no branch
            if not self.standing(index):
                continue
            if index >= len(self.foes) and index < self.first_warden():
                continue
            var there = self.target_at(index)
            var radius = Length(self.target_radius(index), METER)
            var reach = swing.value().reach
            var arc = swing.value().arc
            if not reaches(feet, heading, reach, arc, there, radius):
                continue
            var blow = self.members[k].fighter.connect(index)
            if not blow:
                continue
            var struck = self._strike(
                scene, index, blow.value(), feet, k + 1, tank
            )
            self.members[k].fighter.landed(struck)

    def _party_mend(mut self, k: Int, player: Character) raises:
        """Heal the player and each raider near a healer's mend."""
        var at = self.members[k].character.position
        var healed = Float32(0)
        if (
            _flat(at, player.position) <= MEND_RADIUS
            and not self.fighter.defeated()
        ):
            ref f = self.fighter
            var gain = min(
                f.parameters.health - f.health, MEND_HEAL * f.parameters.health
            )
            f.health += gain
            healed += gain
            self._popup(
                player.position, "+" + String(Int(gain + 0.5)), HEAL_TEXT
            )
        for j in range(len(self.members)):  # pragma: no branch
            ref other = self.members[j]
            if other.down >= 0:
                continue
            if _flat(at, other.character.position) > MEND_RADIUS:
                continue
            ref o = other.fighter
            var gain = min(
                o.parameters.health - o.health, MEND_HEAL * o.parameters.health
            )
            o.health += gain
            healed += gain
        for w in range(len(self.wardens)):  # pragma: no branch
            self.wardens[w].boss.healed(k + 1, healed)

    def _pose_beast(self, mut scene: Scene, index: Int) raises:
        """Stand a wolf where its character stands, in the pose of its
        walk; on its side, once it falls."""
        ref foe = self.foes[index]
        ref pelt = self.pelts[foe.look]
        ref at = foe.character.position
        ref node = scene.node(pelt.node)
        var turn = Quaternion.from_axis_angle(
            Vector3(0, 1, 0), facing_turn(foe.character.heading)
        )
        if foe.fighter.defeated():
            var ahead = _ahead(foe.character.heading)
            var side = Quaternion.from_axis_angle(ahead, Angle(90.0, DEGREE))
            var r = foe.character.parameters.radius.to(METER)
            node.set_position(at.x, at.y + r, at.z)
            node.quaternion = side * turn
        else:
            node.set_position(at.x, at.y, at.z)
            node.quaternion = turn
        scene.meshes[pelt.mesh].geometry = self.books[pelt.book].frame(
            foe.character
        )

    def _teach(mut self) raises:
        """Learn each combo that a style's level teaches, and say so."""
        for style in self.parameters.styles:  # pragma: no branch
            var level = self.levels[style.value]
            for index in self.book.teach(style, level):
                self.notes.append("NEW COMBO: " + self.book.combos[index].name)

    def tick(
        mut self,
        mut scene: Scene,
        input: MoveInput,
        mut view: ThirdPersonControls,
        mut player: Character,
        mut body: Body,
        terrain: Terrain,
        blocking: List[Obstacle],
        delta: Duration,
    ) raises:
        """Run the fight for one frame: see the module's steps.

        Args:
            scene: The scene the fight is in.
            input: The player's input for the frame.
            view: The camera, which turns toward a locked target.
            player: The player's character, which the fight moves.
            body: The player's body, which `__init__` armed.
            terrain: The ground, the floors and the walls.
            blocking: The round things in the player's way, but the
                bandits and the dummies.
            delta: The frame's time. While a strong blow stops the fight,
                none of it moves the fight on.

        Raises:
            Error: If the time is negative, or a fighter or a body cannot
                move.
        """
        var real = delta.to(SECOND)
        if not (real >= 0 and real < 1.0e9):
            raise Error("A frame's time must not be negative or endless")
        self._teach()
        # A strong blow stops the fight; the camera shakes on.
        var seconds = real if self.freeze <= 0 else Float32(0)
        self.freeze = max(Float32(0), self.freeze - real)
        self.shake *= exp(-SHAKE_FADE * real)
        var still = Duration(seconds, SECOND)
        self.threat = False
        var presses = pressed(input, self.last)
        var flick = Float32(0)
        if abs(input.look_right) > FLICK and abs(self.last.look_right) <= FLICK:
            flick = Float32(1) if input.look_right > 0 else Float32(-1)
        var let_go = self.last.dodge and not input.dodge
        self.last = input
        self._command(input, presses, flick, view.yaw, player)
        # Out of a fight, a tap of the dodge rolls, to cross the ground.
        var tap = let_go and self.dodge_hold <= ROLL_TAP
        if tap and not self.drawn and player.grounded:
            _ = self.fighter.request(DODGE)
        self.dodge_hold = self.dodge_hold + real if input.dodge else 0
        if input.use and not self.fighter.defeated():
            self._revive_near(player.position, real)
        var around = blocking.copy()
        around.extend(self.obstacles())
        self._move_player(input, view.yaw, player, terrain, around, still)
        if self.lock >= 0:
            view.yaw = turn_toward(
                view.yaw,
                yaw_of(self.target_at(self.lock) - player.position),
                Angle(LOCK_TURN * seconds, RADIAN),
            )
        var pace = SLOW_SHARE if self.slow > 0 else Float32(1)
        var slowed = Duration(seconds * pace, SECOND)
        self._move_foes(player, terrain, blocking, slowed)
        self._move_ally(player, terrain, blocking, still)
        self._move_wardens(scene, player, terrain, blocking, slowed)
        self._move_members(scene, player, terrain, blocking, still)
        self._exchange(scene, player, terrain, still)
        var over = self.fighter.over > 0
        if over and not self.limited:
            self.notes.append("SURGE!")
        self.limited = over
        self.trail.color = OVER_TRAIL if over else PLAYER_TRAIL
        self._settle(scene, player, terrain, still)
        self.feet = player.position
        self.arms.pose(scene, body, player, self.fighter, self.drawn, still)
        self.trail.show(scene, self.fighter)
        # Fists and shots leave no blade's trail; a spinning kick does.
        var bare = self.fighter.style == HAND_TO_HAND
        var cut = is_melee(self.fighter.style) and not bare
        if not cut and self.fighter.move != WHIRLWIND:
            self.trail.shown = -1
        var reach = self.parameters.fight_reach
        ref feet = player.position
        self.frame += 1
        for index in range(len(self.foes)):
            if self.foes[index].beast:
                self._pose_beast(scene, index)
                continue
            ref foe = self.foes[index]
            var near = _flat(foe.character.position, feet) <= reach
            var turn = (self.frame + index) % FAR_POSE == 0
            pose_person(
                scene,
                self.people[foe.look],
                foe.character,
                foe.fighter,
                True,
                slowed,
                near,
                turn,
            )
        for index in range(len(self.allies)):
            ref ally = self.allies[index]
            ref person = self.people[ally.look]
            person.arms.pose(
                scene,
                person.body,
                ally.character,
                ally.fighter,
                self.drawn,
                still,
            )
        for index in range(len(self.wardens)):
            ref warden = self.wardens[index]
            var shown = puppet_move(warden.boss)
            warden.puppet.move = shown[0]
            warden.puppet.clock = shown[1]
            warden.puppet.pace = shown[2]
            var near = _flat(warden.character.position, feet) <= reach
            var turn = (self.frame + index) % FAR_POSE == 0
            pose_person(
                scene,
                self.people[warden.look],
                warden.character,
                warden.puppet,
                True,
                slowed,
                near,
                turn,
            )
        for index in range(len(self.members)):
            ref member = self.members[index]
            var near = _flat(member.character.position, feet) <= reach
            var turn = (self.frame + index + 1) % FAR_POSE == 0
            pose_person(
                scene,
                self.people[member.look],
                member.character,
                member.fighter,
                member.joined,
                still,
                near,
                turn,
            )
