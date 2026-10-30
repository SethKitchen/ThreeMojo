# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Swordplay in the village: the player and a companion against bandits,
wolves and straw dummies.

`Battle.tick` runs the fight for one frame, in place of the player's own
step and pose:

1. **Presses.** A new press of a button asks the player's `Fighter` for a
   move: a light attack, the heavy attack, an arte, or a dodge. A demon
   fang's cut sends a wave that runs along the ground at `FANG_SPEED`
   for `FANG_RANGE`, and strikes each target it passes over once. Over
   Limit, the mystic arte's buttons spend it on the mystic arte. A dodge
   needs the sword drawn, since its button also runs. The guard button
   guards while it is held, and a new press of it makes a ki pulse. A
   stance button changes the stance. The lock button locks the camera on
   the foe or the dummy nearest the middle of the view, or lets go. While
   it locks, a flick of the look stick moves the lock to the next target
   that way. The heal button eats one of the satchel's herbs, and heals
   `HEAL_SHARE` of the player's health.
2. **The player moves.** A free player walks, runs and jumps as before,
   at `GUARD_PACE` of the stick while guarding, and faces what they lock
   on. An attack carries the player along their heading, and turns them
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
   follow their foe. The boost button calls for her boost attack when its
   gauge is full. One foe
   at a time holds the attack token. A bandit plays its sword's clips; a
   wolf shows the pose of its walk, and lies on its side when it falls.
   A perfect dodge slows the foes to `SLOW_SHARE` of the time for
   `SLOW_SECONDS`, and a mystic arte for `MYSTIC_SLOW`.
4. **The blows.** In steps of at most `COMBAT_STEP`, each fighter's clock
   runs, and each swing gives its blow to the fighters that it reaches. A
   blow that lands pushes its fighter away, and the rising edge throws it
   up; a blow on a fighter in the air keeps it up. A guarded blow pushes
   it back `BLOCK_PUSH` as far.
5. **What shows.** Each blow writes its damage over the fighter it lands
   on, and the outcome's word: see `outcome_word`. A blow that lands
   bursts in sparks. A foe that begins to rage shows `RAGE`. Each
   swing's trail is measured for the display: see
   `extensions.village.slashes`. Over Limit, the player's trails are
   gold, and the note says when it begins. A plunge's landing rings the
   ground with light. The sword is drawn while a bandit within `ENGAGE`
   fights, or the player fights, and is sheathed `CALM_SECONDS` after.
6. **The weight of a blow.** A strong blow stops the whole fight for
   `HIT_STOP`, as action games freeze a frame on a heavy hit, and shakes
   the camera by `SHAKE`: see `strong_blow`. A finisher or a burst
   counter stops it for `FINISH_STOP`, and shakes it twice as far. The shake dies away at
   `SHAKE_FADE`.
7. **The fallen.** A fallen bandit gives `LOOT` coins, and one time in
   two a herb. It lies for the
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
    BURST_COUNTER,
    CAST,
    DEFEATED,
    DEMON_FANG,
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
    MYSTIC_ARTE,
    PARRIED,
    PLUNGE,
    PERFECT_DODGE,
    RISING_EDGE,
    TEMPEST,
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
from extensions.village.companion import (
    BOOST_PER_HIT,
    AllySight,
    Companion,
    MEND_SHARE,
    boost_blow,
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
from std.math import ceil, exp, sqrt
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
comptime MYSTIC_SLOW = Float32(2.1)
"""How long a mystic arte slows the foes, in seconds: all through it."""
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
"""The share of fallen bandits that drop a herb as well."""
comptime FANG_SPEED = Float32(14)
"""How fast a demon fang's wave runs, in meters a second."""
comptime FANG_RANGE = Float32(12)
"""How far a demon fang's wave runs, in meters."""
comptime FANG_WIDTH = Float32(1.6)
"""How wide a demon fang's wave strikes, in meters."""
comptime FANG_START = Float32(0.6)
"""How far before the player a demon fang's wave starts, in meters."""
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
"""The share of the player's health that a herb heals."""
comptime HEAL_TEXT = Rgb(120, 230, 120)
"""The color of what a herb or the companion heals."""
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
comptime HURT_TEXT = Rgb(255, 90, 70)
"""The color of the player's own damage."""
comptime CALM_TEXT = Rgb(150, 200, 255)
"""The color of a guard's, a dodge's and a pulse's words."""


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
        tempest=now.tempest and not before.tempest,
        fang=now.fang and not before.fang,
        boost=now.boost and not before.boost,
        mystic=now.mystic and not before.mystic,
        dodge=now.dodge and not before.dodge,
        guard=now.guard and not before.guard,
        lock=now.lock and not before.lock,
        high=now.high and not before.high,
        middle=now.middle and not before.middle,
        low=now.low and not before.low,
        heal=now.heal and not before.heal,
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
        True for a guard broken, a critical blow, a ki broken and a fighter
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
    """A demon fang's wave of force, which runs along the ground."""

    # Where its middle is, the way it runs, of length one, and how far it
    # has run, in meters.
    var at: Vector3
    var way: Vector3
    var gone: Float32
    # What it does to each target it strikes, and the targets it struck.
    var blow: Blow
    var struck: List[Int]


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

    def __init__(out self) raises:
        """Hold the default village's fight: the player's strength, the
        companion, the bandits' camp and its captain, the wolves' den, and
        the dummies,
        a revive of 4 seconds, foes that lie for 10 seconds and come back
        after a minute, and wolves of six poses at their quality's cell.

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

    def check(self) raises:
        """Refuse a fight that cannot be held.

        Raises:
            Error: If the player's, the companion's, a bandit's, a den's or
                the dummies' parameters do not check; a den holds not from
                1 to 8 wolves; there are more than 16 bandits, 16 dummies,
                4 dens or 1 companion; a time is negative or not below 10,000 seconds; a
                wolf's walk has not from 1 to 32 poses; or its coarseness
                is not from 1 to 8.
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
    """A bandit's looks: its body, its sword and its trail."""

    var body: Body
    var arms: Arms
    var trail: Trail


@fieldwise_init
struct Ally(Movable):
    """The companion in the scene: her character, fighter and mind, and
    what she casts at."""

    var character: Character
    var fighter: Fighter
    var mind: Companion
    # Her looks' index in the battle's `people`.
    var look: Int
    # The target her cast aims at, or -1; and whether the cast is a boost
    # attack.
    var aim: Int
    var boosting: Bool


@fieldwise_init
struct Bolt(Copyable, Movable):
    """A companion's bolt of light, which flies at its target."""

    # Where it is, and where it was cast from.
    var at: Vector3
    var origin: Vector3
    # The target it flies at, and the blow it carries.
    var target: Int
    var blow: Blow
    # Whether it is a boost attack's, and how long it has flown, in
    # seconds.
    var boosted: Bool
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
    # The demon fang's waves that run.
    var waves: List[Wave]
    # The companion, if any, and her bolts that fly; and whether the boost
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
    # How long ago the player last made a ki pulse that got ki back, in
    # seconds, or -1 if they never did.
    var pulsed: Float32
    # How long the player has lain fallen, in seconds, or -1.
    var down: Float32
    # Whether the player was Over Limit at the end of the last frame.
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
    # The swordplay experience won and not yet taken: see
    # `extensions.village.skills`.
    var trained: Int

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
        water, is left out.

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
        var swords = SwordLooks(assets)
        var glow = slash_material(assets)
        self.arms = Arms(scene, assets, body, swords, BRIGHT_STEEL)
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
            self.people.append(Person(person^, arms^, trail^))
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
            self.people.append(Person(person^, arms^, trail^))
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
            var places = den_places(den)
            for k in range(len(places)):  # pragma: no branch
                var at = places[k]
                if lot_openness(lots, at.x, at.z) < 1:
                    continue
                if ground.wet(at.x, at.z):
                    continue
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
        self.sparks = Sparks(scene, assets, glow)
        self.popups = List[Popup]()
        self.waves = List[Wave]()
        self.bolts = List[Bolt]()
        self.called = False
        self.knives = List[Knife]()
        self.lock = -1
        self.token = -1
        self.token_rest = 0
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
        self.trained = 0

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
        return out^

    def targets(self) -> Int:
        """Return how many targets there are: the bandits, then the
        dummies.

        Returns:
            The count.
        """
        return len(self.foes) + len(self.dummies)

    def target_at(self, index: Int) -> Vector3:
        """Return where a target's feet are.

        Args:
            index: A bandit's index, or a dummy's after the bandits.

        Returns:
            The feet.
        """
        if index < len(self.foes):
            return self.foes[index].character.position
        return self.dummies[index - len(self.foes)].dummy.where()

    def standing(self, index: Int) -> Bool:
        """Return whether a target stands, so it can be struck or locked.

        Args:
            index: A bandit's index, or a dummy's after the bandits.

        Returns:
            False for a fallen bandit, and True for a dummy.
        """
        if index < len(self.foes):
            return self.foes[index].down < 0
        return True

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
        self, at: Vector3, heading: Angle, stick: Vector3
    ) -> Optional[Angle]:
        """Return the way an attack turns its player toward.

        Args:
            at: Where the player stands.
            heading: The way they face.
            stick: The way the stick leans on the ground; of no length
                when it rests.

        Returns:
            The way to the locked target; else to the nearest standing
            target within `AIM_RANGE` and `AIM_ARC` of the stick, or of
            the heading when the stick rests; else the stick's way; else
            None.
        """
        if self.lock >= 0:
            return yaw_of(self.target_at(self.lock) - at)
        var leaning = stick.length() > 0.1
        var look = yaw_of(stick) if leaning else heading
        var best = -1
        var nearest = AIM_RANGE
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
        if presses.lock:
            if self.lock >= 0:
                self.lock = -1
            else:
                self.lock = self.pick_lock(player.position, yaw)
        if self.lock >= 0 and flick != 0:
            self.lock = self.switch_lock(player.position, flick)
        if presses.guard:
            var back = self.fighter.pulse()
            if back > 0:
                self._popup(player.position, "KI PULSE", CALM_TEXT)
                self.pulsed = 0
        self.fighter.hold_guard(input.guard)
        self.called = presses.boost
        var fought = input.guard or presses.lock
        if presses.mystic and self.fighter.over > 0:
            if self.fighter.request(MYSTIC_ARTE):
                self.notes.append("MYSTIC ARTE!")
                self.slow = MYSTIC_SLOW
            fought = True
        elif presses.rising or presses.tempest or presses.fang:
            var arte = DEMON_FANG
            if presses.rising:
                arte = RISING_EDGE
            elif presses.tempest:
                arte = TEMPEST
            if self.fighter.request(arte):
                self.notes.append(move_name(arte) + "!")
            fought = True
        elif presses.light:
            _ = self.fighter.press_light()
            fought = True
        elif presses.heavy:
            var heavy = HEAVY if player.grounded else PLUNGE
            _ = self.fighter.request(heavy)
            fought = True
        if presses.dodge and self.drawn:
            _ = self.fighter.request(DODGE)
        if fought:
            self.drawn = True
            self.calm = 0

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
            player.step(walk, yaw, delta, terrain, blocking)
            if self.lock >= 0:
                var toward = yaw_of(self.target_at(self.lock) - player.position)
                player.heading = turn_toward(
                    player.heading, toward, Angle(FACE_TURN * seconds, RADIAN)
                )
            return
        var way = _ahead(player.heading)
        if move == DODGE:
            way = self.dodge_way
        elif is_attack(move):
            var start = move_data(move).startup.to(SECOND) * self.fighter.pace
            var aim = self.aim(player.position, player.heading, stick)
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
            var sight = Sight(
                foe.character.position,
                foe.home,
                feet,
                self.fighter.defeated(),
                self.threat,
                fighter.free(),
                ready,
                self.token == index,
                self.token < 0 and self.token_rest <= 0,
                fighter.raging(),
            )
            var intent = foe.brain.think(sight, delta)
            var toward = yaw_of(feet - foe.character.position)
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
            if intent.claim:
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
        blow; longer and harder for a finisher or a burst counter."""
        if struck.outcome == FINISHED or struck.outcome == BURST_COUNTER:
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
        var radius = Length(0.3, METER)
        for index in range(self.targets()):
            if not self.standing(index):
                continue
            var there = self.target_at(index)
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
        from a demon fang's wave at `source`. The player learns what it
        did, and trains."""
        var struck = self._strike(scene, index, hit, source)
        if index >= len(self.foes):
            self.trained += PRACTICE_EXPERIENCE
        elif landed_blow(struck.outcome):
            self.trained += BLOW_EXPERIENCE
        self.fighter.landed(struck)

    def _strike(
        mut self, mut scene: Scene, index: Int, hit: Blow, source: Vector3
    ) raises -> Struck:
        """Give a blow from `source` to a target, show it, and weigh it; a
        felled foe gives its loot. Return what the blow did."""
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
                self.trained += DEFEAT_EXPERIENCE
            if (fell or struck.outcome == FINISHED) and not foe.beast:
                self.loot += LOOT
                var note = String("+", LOOT, " COINS")
                if foe.brain.roll(6) < HERB_CHANCE:
                    self.found += 1
                    note += " +1 HERB"
                self.notes.append(note)
        else:
            ref practice = self.dummies[index - len(self.foes)]
            struck = practice.fighter.receive(hit, False)
            practice.dummy.knock(way, hit.knockback.to(METER_PER_SECOND))
            practice.fighter.health = practice.fighter.parameters.health
        if raged:
            self._popup(there + Vector3(0, 0.7, 0), "RAGE", HURT_TEXT)
        self._show(scene, struck, there, False)
        self._weigh(struck, hit)
        return struck

    def _send_waves(
        mut self, mut scene: Scene, player: Character, h: Float32
    ) raises:
        """Send a demon fang's wave as its cut swings, and run each wave
        on by `h` seconds: it strikes each standing target it passes over
        once, and fades out at `FANG_RANGE`."""
        if self.fighter.move == DEMON_FANG and self.fighter.launched():
            var ahead = _ahead(player.heading)
            self.waves.append(
                Wave(
                    player.position + ahead * FANG_START,
                    ahead,
                    0,
                    self.fighter.blow(),
                    List[Int](),
                )
            )
        var kept = List[Wave]()
        for w in range(len(self.waves)):
            var wave = self.waves[w].copy()
            wave.at = wave.at + wave.way * (FANG_SPEED * h)
            wave.gone += FANG_SPEED * h
            for index in range(self.targets()):
                if not self.standing(index):
                    continue
                var there = self.target_at(index)
                if _flat(wave.at, there) > FANG_WIDTH / 2:
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
            if wave.gone < FANG_RANGE:
                kept.append(wave^)
        self.waves = kept^

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
            if ally.boosting:
                blow = boost_blow(ally.fighter.parameters.might)
            self.bolts.append(
                Bolt(
                    at + ahead * BOLT_START + Vector3(0, CHEST, 0),
                    at,
                    ally.aim,
                    blow,
                    ally.boosting,
                    0,
                )
            )
            ally.boosting = False
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
                    self.allies[k].mind.charge(BOOST_PER_HIT)
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
        make the boost attack the player calls for."""
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
        var boosted = False
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
                boosted = True
                ally.boosting = True
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
        if boosted:
            self.notes.append("BOOST ATTACK!")
        if mend > 0:
            var gain = min(p.health - self.fighter.health, mend)
            self.fighter.health += gain
            var amount = String(Int(gain + 0.5))
            self._popup(player.position, "+" + amount, HEAL_TEXT)
            self.notes.append("YOUR COMPANION HEALS " + amount)

    def _foe_strikes(
        mut self, mut scene: Scene, index: Int, mut player: Character
    ) raises:
        """Give a bandit's swing to the player, if it reaches them."""
        var swing = self.foes[index].fighter.swing()
        if not swing:
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
        mut self, mut scene: Scene, mut player: Character, delta: Duration
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
            self._player_strikes(scene, player)
            self._send_waves(scene, player, h)
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
        for index in range(len(self.dummies)):
            self.dummies[index].dummy.rock(scene, delta)
        var fade = exp(-SHOVE_FADE * seconds)
        self.shove = self.shove * fade
        self.slow = max(Float32(0), self.slow - seconds)
        if self.pulsed >= 0:
            self.pulsed += seconds
        self.token_rest -= seconds
        ref p = self.parameters
        var engaged = not self.fighter.free() or self.fighter.guarding
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
        self.last = input
        self._command(input, presses, flick, view.yaw, player)
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
        self._exchange(scene, player, still)
        var over = self.fighter.over > 0
        if over and not self.limited:
            self.notes.append("OVER LIMIT!")
        self.limited = over
        self.trail.color = OVER_TRAIL if over else PLAYER_TRAIL
        self._settle(scene, player, terrain, still)
        self.arms.pose(scene, body, player, self.fighter, self.drawn, still)
        self.trail.show(scene, self.fighter)
        for index in range(len(self.foes)):
            if self.foes[index].beast:
                self._pose_beast(scene, index)
                continue
            ref foe = self.foes[index]
            ref person = self.people[foe.look]
            person.arms.pose(
                scene, person.body, foe.character, foe.fighter, True, slowed
            )
            person.trail.show(scene, foe.fighter)
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
