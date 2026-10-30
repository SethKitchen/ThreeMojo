# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Swordplay in the village: the player against bandits and straw dummies,
as in Tales of Arise and Nioh.

`Battle.tick` runs the fight for one frame, in place of the player's own
step and pose:

1. **Presses.** A new press of a button asks the player's `Fighter` for a
   move: a light attack, the heavy attack, an arte, or a dodge. A dodge
   needs the sword drawn, since its button also runs. The guard button
   guards while it is held, and a new press of it makes a ki pulse. A
   stance button changes the stance. The lock button locks the camera on
   the foe or the dummy nearest the middle of the view, or lets go.
2. **The player moves.** A free player walks, runs and jumps as before,
   at `GUARD_PACE` of the stick while guarding, and faces what they lock
   on. An attack carries the player along their heading, and turns them
   toward what they aim at through its start-up: the locked target, else
   the nearest within `AIM_RANGE` before them, else the stick. A dodge
   goes the way of the stick, or back. The push of a blow carries the
   player too, and fades at `SHOVE_FADE`.
3. **The foes think and move.** See `extensions.village.foes`. One bandit
   at a time holds the attack token. A perfect dodge slows the foes to
   `SLOW_SHARE` of the time for `SLOW_SECONDS`.
4. **The blows.** In steps of at most `COMBAT_STEP`, each fighter's clock
   runs, and each swing gives its blow to the fighters that it reaches. A
   blow that lands pushes its fighter away, and the rising edge throws it
   up; a blow on a fighter in the air keeps it up. A guarded blow pushes
   it back `BLOCK_PUSH` as far.
5. **What shows.** Each blow writes its damage over the fighter it lands
   on, and the outcome's word: see `outcome_word`. A blow that lands
   bursts in sparks. The sword is drawn while a bandit within `ENGAGE`
   fights, or the player fights, and is sheathed `CALM_SECONDS` after.
6. **The fallen.** A fallen bandit gives `LOOT` coins. It lies for the
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
from core.object3d import NodeId
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
    DEFEATED,
    DODGE,
    FREE,
    GUARD_BREAK,
    BLOCKED,
    HEAVY,
    HIGH_STANCE,
    LOW_STANCE,
    MID_STANCE,
    PARRIED,
    PERFECT_DODGE,
    RISING_EDGE,
    TEMPEST,
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
from extensions.village.foes import (
    POSTED,
    RETURNING,
    Bandit,
    Brain,
    DUMMY_RADIUS,
    Dummy,
    Post,
    Sight,
    bandit_fighter,
    default_bandits,
    default_posts,
    dummy_fighter,
)
from extensions.village.hud import GOLD_TEXT, WHITE_TEXT, Rgb
from extensions.village.residents import Body
from extensions.village.slashes import (
    FOE_TRAIL,
    PLAYER_TRAIL,
    Sparks,
    Trail,
    slash_material,
)
from extensions.village.surfaces import HouseLooks
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
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
)

comptime COMBAT_STEP = Float32(1.0 / 60.0)
"""The longest step of the fighters' clocks, in seconds."""
comptime GUARD_PACE = Float32(0.4)
"""The share of the stick a guarding fighter walks at."""
comptime SLOW_SECONDS = Float32(0.7)
"""How long a perfect dodge slows the foes, in seconds."""
comptime SLOW_SHARE = Float32(0.3)
"""The share of the time the foes move at while they are slowed."""
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
        dodge=now.dodge and not before.dodge,
        guard=now.guard and not before.guard,
        lock=now.lock and not before.lock,
        high=now.high and not before.high,
        middle=now.middle and not before.middle,
        low=now.low and not before.low,
    )


def _flat(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def _way(a: Vector3, b: Vector3) -> Vector3:
    """Return the way from one point to another on the ground, of length
    one, or +z when they meet."""
    var gap = _flat(a, b)
    if gap < 1.0e-4:
        return Vector3(0, 0, 1)
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
    var bandit: FighterParameters
    var dummy: FighterParameters
    var bandits: List[Bandit]
    var posts: List[Post]
    # How long a fallen player lies before they come to; how long a fallen
    # bandit lies before it is gone, and comes back to its post.
    var revive: Duration
    var linger: Duration
    var respawn: Duration

    def __init__(out self) raises:
        """Hold the default village's fight: the player's strength, the
        bandits' camp and the dummies, a revive of 4 seconds, and bandits
        that lie for 10 seconds and come back after a minute.

        Raises:
            Error: Never: the outfits check.
        """
        self.player = FighterParameters()
        self.bandit = bandit_fighter()
        self.dummy = dummy_fighter()
        self.bandits = default_bandits()
        self.posts = default_posts()
        self.revive = Duration(4.0, SECOND)
        self.linger = Duration(10.0, SECOND)
        self.respawn = Duration(60.0, SECOND)

    def check(self) raises:
        """Refuse a fight that cannot be held.

        Raises:
            Error: If a fighter's parameters do not check, there are more
                than 16 bandits or 16 dummies, or a time is negative or
                not below 10,000 seconds.
        """
        self.player.check()
        self.bandit.check()
        self.dummy.check()
        if len(self.bandits) > 16 or len(self.posts) > 16:
            raise Error("A fight holds at most 16 bandits and 16 dummies")
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
    """A bandit in the scene: its character, fighter, body and brain."""

    var character: Character
    var fighter: Fighter
    var body: Body
    var arms: Arms
    var trail: Trail
    var brain: Brain
    # Its post, and the way it faces there.
    var home: Vector3
    var heading: Angle
    # How fast a blow pushes it, in meters a second.
    var shove: Vector3
    # How long it has lain fallen, in seconds, or -1 while it stands.
    var down: Float32


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
    var dummies: List[Practice]
    var sparks: Sparks
    var popups: List[Popup]
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
    # How long the player has lain fallen, in seconds, or -1.
    var down: Float32
    # Where the player comes to.
    var start: Vector3
    # Coins won and not yet taken, and lines for the game's note.
    var loot: Int
    var notes: List[String]

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
        """Arm the player's body, and build the bandits and the dummies.

        A bandit or a dummy on a lot or its apron, or in the water, is
        left out.

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
        self.trail = Trail(
            scene, assets, glow, body.carrier, scale, PLAYER_TRAIL
        )
        self.foes = List[Foe]()
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
            var trail = Trail(
                scene, assets, glow, person.carrier, size, FOE_TRAIL
            )
            var character = Character(
                CharacterParameters(),
                bandit.x,
                bandit.z,
                bandit.heading,
                terrain,
            )
            var home = character.position
            self.foes.append(
                Foe(
                    character^,
                    Fighter(parameters.bandit),
                    person^,
                    arms^,
                    trail^,
                    Brain(bandit.seed),
                    home,
                    bandit.heading,
                    Vector3(0, 0, 0),
                    -1,
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
        self.down = -1
        self.start = start
        self.loot = 0
        self.notes = List[String]()

    def movers(self) -> List[NodeId]:
        """Return the nodes that move: each bandit's and each dummy's.

        Returns:
            Each bandit's carrier, then each dummy's pivot.
        """
        var out = List[NodeId]()
        for index in range(len(self.foes)):
            out.append(self.foes[index].body.carrier)
        for index in range(len(self.dummies)):
            out.append(self.dummies[index].dummy.pivot)
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
        """Return the circle each standing bandit and each dummy takes up.

        Returns:
            One obstacle a bandit, of no size for a fallen one, then one a
            dummy.
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
        yaw: Angle,
        player: Character,
    ) raises:
        """Turn the frame's presses into the player's moves."""
        if self.fighter.defeated():
            return
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
        if presses.guard:
            var back = self.fighter.pulse()
            if back > 0:
                self._popup(player.position, "KI PULSE", CALM_TEXT)
        self.fighter.hold_guard(input.guard)
        var fought = input.guard or presses.lock
        if presses.rising or presses.tempest:
            var arte = RISING_EDGE if presses.rising else TEMPEST
            if self.fighter.request(arte):
                self.notes.append(move_name(arte) + "!")
            fought = True
        elif presses.light:
            _ = self.fighter.press_light()
            fought = True
        elif presses.heavy:
            _ = self.fighter.request(HEAVY)
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
            # An attack in the air hangs there while it strikes.
            if not player.grounded and self.fighter.swing():
                player.velocity.y = max(player.velocity.y, Float32(0))
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
            )
            var intent = foe.brain.think(sight, delta)
            var toward = yaw_of(feet - foe.character.position)
            foe.fighter.hold_guard(intent.guard)
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
                foe.character.drive(
                    _ahead(foe.character.heading) * speed + foe.shove,
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
        damage, its word and its sparks. `hurt` is True for the player."""
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
        if outcome == PERFECT_DODGE:
            self.slow = SLOW_SECONDS

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
            var hit = blow.value()
            var way = _way(feet, there)
            var struck: Struck
            if index < len(self.foes):
                ref foe = self.foes[index]
                var front = faces(
                    there,
                    foe.character.heading,
                    foe.fighter.parameters.guard_arc,
                    feet,
                )
                struck = foe.fighter.receive(hit, front)
                foe.shove = push_of(struck, hit, way)
                throw_up(foe.character, struck, hit)
                if landed_blow(struck.outcome) and foe.brain.hurt():
                    if self.token == index:
                        self.token = -1
                        self.token_rest = TOKEN_REST
                if struck.outcome == DEFEATED:
                    self.loot += LOOT
                    self.notes.append(String("+", LOOT, " COINS"))
            else:
                ref practice = self.dummies[index - len(self.foes)]
                struck = practice.fighter.receive(hit, False)
                practice.dummy.knock(way, hit.knockback.to(METER_PER_SECOND))
                practice.fighter.health = practice.fighter.parameters.health
            self.fighter.landed(struck)
            self._show(scene, struck, there, False)

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
        var hit = blow.value()
        var front = faces(
            feet, player.heading, self.fighter.parameters.guard_arc, at
        )
        var struck = self.fighter.receive(hit, front)
        self.foes[index].fighter.landed(struck)
        self.shove = push_of(struck, hit, _way(at, feet))
        throw_up(player, struck, hit)
        self._show(scene, struck, feet, True)

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
            self._player_strikes(scene, player)
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
        self.token_rest -= seconds
        ref p = self.parameters
        var engaged = not self.fighter.free() or self.fighter.guarding
        for index in range(len(self.foes)):
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
                scene.node(foe.body.carrier).visible = False
            if foe.down > p.respawn.to(SECOND):
                foe.character.position = foe.home
                foe.character.heading = foe.heading
                foe.fighter.revive()
                foe.brain = Brain(foe.brain.seed)
                foe.down = -1
                scene.node(foe.body.carrier).visible = True
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
            delta: The frame's time.

        Raises:
            Error: If the time is negative, or a fighter or a body cannot
                move.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0 and seconds < 1.0e9):
            raise Error("A frame's time must not be negative or endless")
        self.threat = False
        var presses = pressed(input, self.last)
        self.last = input
        self._command(input, presses, view.yaw, player)
        var around = blocking.copy()
        around.extend(self.obstacles())
        self._move_player(input, view.yaw, player, terrain, around, delta)
        if self.lock >= 0:
            view.yaw = turn_toward(
                view.yaw,
                yaw_of(self.target_at(self.lock) - player.position),
                Angle(LOCK_TURN * seconds, RADIAN),
            )
        var pace = SLOW_SHARE if self.slow > 0 else Float32(1)
        var slowed = Duration(seconds * pace, SECOND)
        self._move_foes(player, terrain, blocking, slowed)
        self._exchange(scene, player, delta)
        self._settle(scene, player, terrain, delta)
        self.arms.pose(scene, body, player, self.fighter, self.drawn, delta)
        self.trail.show(scene, self.fighter)
        for index in range(len(self.foes)):
            ref foe = self.foes[index]
            foe.arms.pose(
                scene, foe.body, foe.character, foe.fighter, True, slowed
            )
            foe.trail.show(scene, foe.fighter)
