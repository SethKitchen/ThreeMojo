# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's foes in the village: bandits who keep a camp, wolves who
keep a den, and straw dummies to practice on.

**Bandits.** A `Bandit` is a person with a sword, as the player is: a
`Body` that plays the sword clips, and a `Fighter` with the moves of
`extensions.village.combat`. Each bandit has its own strength, so the
camp's captain hits harder and lasts longer. A `Brain` decides what it does, frame by
frame, as a state machine of `FoeState`:

| State | What the bandit does | It moves on when |
|---|---|---|
| `POSTED` | Stands at its post | The player comes within `NOTICE`: `ALERTED` |
| `ALERTED` | Faces the player for `ALERT` seconds | The time is over: `CLOSING` |
| `CLOSING` | Runs or walks at the player | It is within `CIRCLE`: `CIRCLING` |
| `CIRCLING` | Steps round the player at `CIRCLE`, facing them | Its wait is over and it holds the attack token: `ATTACKING`. An attack of the player's starts near it: `GUARDING`, one time in `GUARD_CHANCE` |
| `ATTACKING` | Comes within `STRIKE` and makes the attacks of its plan | The plan is done: `RETREATING`, and it gives the token back |
| `RETREATING` | Backs away for `RETREAT` seconds | The time is over: `CIRCLING` |
| `GUARDING` | Guards for `GUARD_TIME` seconds | The time is over: `CIRCLING` |
| `RETURNING` | Walks back to its post | It is there: `POSTED` |

A bandit returns to its post when the player falls, or leads it further
than `LOSE` from its post. Only the bandit that holds the attack token
attacks, so the others wait their turn round the player, as foes do in
most action games. A plan is two or three light attacks, a heavy attack,
or a light and a heavy attack. The dice that choose come from the
bandit's seed, so a fight plays the same way each time.

**Wolves.** A wolf is an animal of the village's kind, meshed as a
flipbook, with a `Fighter` whose one attack is the `BITE`: a crouch, and
a leap that bites. Its brain is a bandit's with a beast's temper: see
`Brain.wolf`. It notices the player from `WOLF_NOTICE`, waits its turn
further off, at `WOLF_CIRCLE`, and leaps from `WOLF_STRIKE`. Where a
bandit guards an attack, a wolf leaps back from it. A pack of `Den`'s
wolves keeps east of the pond.

**Dummies.** A dummy is a post with a crossbar, a body of straw and a
sack for a head. It has a fighter too, so blows on it break its ki and
are critical, but it never falls: each blow's health comes back at once.
It rocks on its post as it is hit.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.ordinal import ordinal_valid
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.noise import hash01
from extensions.village.clothes import (
    GRAY_WOOL,
    MADDER,
    NETTLE,
    WALNUT,
    village_outfit,
)
from extensions.village.combat import (
    BITE,
    FREE,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    CombatMove,
    FighterParameters,
)
from extensions.village.dressing import prism
from extensions.village.sheet import Sheet
from extensions.village.surfaces import HouseLooks
from materials.material import MaterialId
from math.utils import clamp
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, pi, sin, sqrt
from units.si import (
    DEGREE,
    INCH,
    PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
)

comptime FOE_STATES = 8
"""How many states a bandit's brain has."""
comptime NOTICE = Float32(14)
"""How near the player a posted bandit notices them, in meters."""
comptime LOSE = Float32(28)
"""How far from its post a bandit follows the player, in meters."""
comptime ALERT = Float32(0.7)
"""How long a bandit stares at the player before it comes, in seconds."""
comptime CIRCLE = Float32(3.6)
"""How far from the player a bandit waits its turn, in meters."""
comptime STRIKE = Float32(1.9)
"""How near the player a bandit comes to attack, in meters."""
comptime RUN_GAP = Float32(6)
"""A bandit further than this from the player runs to them, in meters."""
comptime RETREAT = Float32(0.8)
"""How long a bandit backs away after its attacks, in seconds."""
comptime GUARD_TIME = Float32(0.9)
"""How long a bandit guards, in seconds."""
comptime GUARD_CHANCE = Float32(0.35)
"""The share of the player's attacks that a waiting bandit guards."""
comptime GUARD_REACH = Float32(3.5)
"""How near the player a bandit must be to guard their attack, in
meters."""
comptime WOLF_NOTICE = Float32(18)
"""How near the player a wolf notices them, in meters."""
comptime WOLF_CIRCLE = Float32(4.5)
"""How far from the player a wolf waits its turn, in meters."""
comptime WOLF_STRIKE = Float32(3.2)
"""How near the player a wolf leaps to bite, in meters."""
comptime WOLF_RUN = Float32(7)
"""How fast a wolf runs, in meters a second."""
comptime HOME_NEAR = Float32(0.8)
"""How near its post a returning bandit stops, in meters."""
comptime FLIP_RATE = Float32(0.3)
"""How often a circling bandit turns the other way round, a second."""
comptime DUMMY_RADIUS = Float32(0.35)
"""How wide a dummy is, in meters from its post."""
comptime ROCK_STIFFNESS = Float32(60)
"""How hard a dummy's post pulls it upright, in radians a second squared
for each radian of tilt."""
comptime ROCK_DAMPING = Float32(5)
"""How fast a dummy's rocking dies away, a second."""
comptime ROCK_KICK = Float32(0.6)
"""How fast a blow of one meter a second sets a dummy rocking, in radians
a second."""


@fieldwise_init
struct FoeState(Equatable, ImplicitlyCopyable, Writable):
    """What a bandit's brain is doing, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the states.

        Returns:
            True from `POSTED` to `RETURNING`.
        """
        return ordinal_valid(self.value, FOE_STATES - 1)


comptime POSTED = FoeState(0)
comptime ALERTED = FoeState(1)
comptime CLOSING = FoeState(2)
comptime CIRCLING = FoeState(3)
comptime ATTACKING = FoeState(4)
comptime RETREATING = FoeState(5)
comptime GUARDING = FoeState(6)
comptime RETURNING = FoeState(7)


def state_name(state: FoeState) raises -> String:
    """Return a brain state's name, for a log or a test.

    Args:
        state: The state.

    Returns:
        Such as "posted" or "circling".

    Raises:
        Error: If the state is not one.
    """
    if not state.is_valid():
        raise Error("A foe's state must be one of the eight")
    var names: List[String] = [
        "posted",
        "alerted",
        "closing",
        "circling",
        "attacking",
        "retreating",
        "guarding",
        "returning",
    ]
    return names[state.value]


@fieldwise_init
struct Intent(ImplicitlyCopyable):
    """What a bandit means to do this frame."""

    # The way to walk on the ground, its length the stick's lean, and
    # whether to run.
    var way: Vector3
    var run: Bool
    # Whether to turn to face the player.
    var face: Bool
    # The attack to ask for, or `FREE` for none.
    var attack: CombatMove
    # Whether to guard.
    var guard: Bool
    # Whether it takes the attack token, or gives it back.
    var claim: Bool
    var release: Bool


def still() -> Intent:
    """Return the intent of a bandit that does nothing.

    Returns:
        No walk, no attack, no guard, and the token left as it is.
    """
    return Intent(Vector3(0, 0, 0), False, False, FREE, False, False, False)


@fieldwise_init
struct Sight(ImplicitlyCopyable):
    """What a bandit knows of the fight this frame."""

    # Where the bandit, its post and the player stand.
    var at: Vector3
    var home: Vector3
    var player: Vector3
    # Whether the player is down, and whether an attack of theirs started
    # this frame.
    var player_down: Bool
    var threat: Bool
    # Whether the bandit makes no move, and whether it can ask for its next
    # attack: free, or past the active part of an attack with none
    # waiting.
    var free: Bool
    var ready: Bool
    # Whether it holds the attack token, and whether nobody does and it
    # can be taken.
    var holds: Bool
    var unclaimed: Bool


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


def plan_for(roll: Float32) -> List[CombatMove]:
    """Return the attacks a bandit makes for a roll of its dice.

    Args:
        roll: A number from zero to one.

    Returns:
        Two light attacks below 0.4, three below 0.65, a heavy attack below
        0.9, and a light and a heavy attack above.
    """
    if roll < 0.4:
        return [LIGHT_ONE, LIGHT_TWO]
    if roll < 0.65:
        return [LIGHT_ONE, LIGHT_TWO, LIGHT_THREE]
    if roll < 0.9:
        return [HEAVY]
    return [LIGHT_ONE, HEAVY]


struct Brain(Copyable, Movable):
    """A bandit's mind: its state, its timer, the way it circles, and its
    plan of attacks."""

    var state: FoeState
    # Seconds left in the state, for the states that wait.
    var timer: Float32
    # Which way round the player it steps: 1 or -1.
    var side: Float32
    var plan: List[CombatMove]
    # The next attack of the plan.
    var step: Int
    # How many times it rolled its dice, and its seed.
    var rolls: Int
    var seed: Int
    # Its temper: how near it notices the player, waits its turn and
    # strikes, in meters; the share of the player's attacks it answers;
    # and whether it is a beast, which bites and leaps back rather than
    # cutting and guarding.
    var notice: Float32
    var circle: Float32
    var strike: Float32
    var wary: Float32
    var beast: Bool

    def __init__(out self, seed: Int):
        """Post a bandit, with its dice's seed: it notices the player from
        `NOTICE`, waits at `CIRCLE`, strikes from `STRIKE` and guards one
        attack in `GUARD_CHANCE`.

        Args:
            seed: The seed of its dice.
        """
        self.state = POSTED
        self.timer = 0
        self.side = 1
        self.plan = List[CombatMove]()
        self.step = 0
        self.rolls = 0
        self.seed = seed
        self.notice = NOTICE
        self.circle = CIRCLE
        self.strike = STRIKE
        self.wary = GUARD_CHANCE
        self.beast = False

    @staticmethod
    def wolf(seed: Int) -> Brain:
        """Return a wolf's brain: it notices the player from `WOLF_NOTICE`,
        waits at `WOLF_CIRCLE`, bites from `WOLF_STRIKE`, and leaps back
        from one attack in `GUARD_CHANCE`.

        Args:
            seed: The seed of its dice.

        Returns:
            The brain, at its post.
        """
        var brain = Brain(seed)
        brain.notice = WOLF_NOTICE
        brain.circle = WOLF_CIRCLE
        brain.strike = WOLF_STRIKE
        brain.beast = True
        return brain^

    def roll(mut self, salt: Int) -> Float32:
        """Roll the dice.

        Args:
            salt: Which roll this is for, so two kinds of roll differ.

        Returns:
            A number from zero to one, the same for the same seed, salt
            and count of rolls.
        """
        self.rolls += 1
        return hash01(self.seed, self.rolls, salt)

    def hurt(mut self) -> Bool:
        """Learn that a blow landed: an attack in hand is given up.

        Returns:
            Whether the bandit gives the attack token back.
        """
        if self.state == ATTACKING:
            self.state = RETREATING
            self.timer = RETREAT
            return True
        return False

    def think(mut self, sight: Sight, delta: Duration) -> Intent:
        """Decide what to do this frame: see the module's table.

        Args:
            sight: What the bandit knows.
            delta: The frame's time.

        Returns:
            What it means to do.
        """
        var seconds = delta.to(SECOND)
        self.timer -= seconds
        var out = still()
        var gap = _flat_gap(sight.at, sight.player)
        var toward = _toward(sight.at, sight.player)
        var away_home = _flat_gap(sight.at, sight.home)
        if sight.player_down and not (
            self.state == POSTED or self.state == RETURNING
        ):
            self.state = RETURNING
            out.release = True
        if self.state == POSTED:
            if not sight.player_down and gap < self.notice:
                self.state = ALERTED
                self.timer = ALERT
                out.face = True
            elif away_home > HOME_NEAR:
                out.way = _toward(sight.at, sight.home) * 0.5
            return out
        if self.state == RETURNING:
            if not sight.player_down and gap < self.notice / 2:
                self.state = ALERTED
                self.timer = ALERT
            elif away_home > HOME_NEAR:
                out.way = _toward(sight.at, sight.home) * 0.6
            else:
                self.state = POSTED
            return out
        if _flat_gap(sight.home, sight.player) > LOSE:
            self.state = RETURNING
            out.release = True
            return out
        out.face = True
        if self.state == ALERTED:
            if self.timer <= 0:
                self.state = CLOSING
        elif self.state == CLOSING:
            if gap > self.circle:
                out.way = toward
                out.run = gap > RUN_GAP
            else:
                self.state = CIRCLING
                self.timer = 0.8 + 1.2 * self.roll(1)
        elif self.state == CIRCLING:
            self._circle(sight, gap, toward, seconds, out)
        elif self.state == ATTACKING:
            if not sight.holds:
                self.state = CIRCLING
                self.timer = 0.5
            elif self.step >= len(self.plan):
                if sight.free:
                    self.state = RETREATING
                    self.timer = RETREAT
                    out.release = True
            elif gap > self.strike:
                out.way = toward
                out.run = gap > 4
            elif sight.ready:
                out.attack = self.plan[self.step]
                self.step += 1
        elif self.state == RETREATING:
            out.way = toward * -0.7
            if self.timer <= 0:
                self.state = CIRCLING
                self.timer = 1 + 1.5 * self.roll(2)
        else:
            out.guard = self.timer > 0
            if self.timer <= 0:
                self.state = CIRCLING
                self.timer = 0.6
        return out

    def _circle(
        mut self,
        sight: Sight,
        gap: Float32,
        toward: Vector3,
        seconds: Float32,
        mut out: Intent,
    ):
        """Wait a turn round the player: step round them at its circle,
        guard an attack or leap back from it, or take the token and
        attack."""
        if gap > self.circle + 2:
            self.state = CLOSING
            return
        if sight.threat and gap < GUARD_REACH and self.roll(3) < self.wary:
            if self.beast:
                self.state = RETREATING
                self.timer = RETREAT
                out.way = toward * -1
                return
            self.state = GUARDING
            self.timer = GUARD_TIME
            out.guard = True
            return
        if self.timer <= 0 and (sight.holds or sight.unclaimed):
            out.claim = True
            self.state = ATTACKING
            if self.beast:
                self.plan = [BITE]
            else:
                self.plan = plan_for(self.roll(4))
            self.step = 0
            return
        if self.roll(5) < FLIP_RATE * seconds:
            self.side = -self.side
        var round = Vector3(-toward.z, 0, toward.x) * (0.5 * self.side)
        var closer = clamp((gap - self.circle) / 2, -0.5, 0.5)
        out.way = round + toward * closer


@fieldwise_init
struct Bandit(Copyable, Movable):
    """A bandit: who they are, what they wear, where they keep, and how
    strong they are."""

    var spec: HumanoidSpec
    var outfit: Outfit
    # Their post, in meters, and the way they face there.
    var x: Float32
    var z: Float32
    var heading: Angle
    # The seed of their dice.
    var seed: Int
    var fighter: FighterParameters


def bandit_fighter() -> FighterParameters:
    """Return how strong a bandit is.

    Returns:
        300 health, 70 ki that comes back at 26 a second after 0.8
        seconds, no arte gauge, blows of 0.55 times a move's own, a guard
        that blocks and never parries, and no Over Limit.
    """
    var p = FighterParameters()
    p.health = 300
    p.ki = 70
    p.ki_rate = Frequency(26.0, PER_SECOND)
    p.ki_delay = Duration(0.8, SECOND)
    p.arte_points = 0
    p.arte_rate = Frequency(0.0, PER_SECOND)
    p.might = 0.55
    p.parry = Duration(0.0, SECOND)
    p.limit_gain = 0
    return p


def captain_fighter() -> FighterParameters:
    """Return how strong the bandits' captain is.

    Returns:
        A bandit's strength, with 650 health, 120 ki that comes back at
        30 a second, and blows of 0.8 times a move's own.
    """
    var p = bandit_fighter()
    p.health = 650
    p.ki = 120
    p.ki_rate = Frequency(30.0, PER_SECOND)
    p.might = 0.8
    return p


def wolf_fighter() -> FighterParameters:
    """Return how strong a wolf is.

    Returns:
        160 health, 60 ki that comes back at 30 a second after 0.6
        seconds, no arte gauge, bites of 0.6 times the bite's own, no
        guard, and no Over Limit.
    """
    var p = FighterParameters()
    p.health = 160
    p.ki = 60
    p.ki_rate = Frequency(30.0, PER_SECOND)
    p.ki_delay = Duration(0.6, SECOND)
    p.arte_points = 0
    p.arte_rate = Frequency(0.0, PER_SECOND)
    p.might = 0.6
    p.guard_arc = Angle(0.0, DEGREE)
    p.parry = Duration(0.0, SECOND)
    p.limit_gain = 0
    return p


@fieldwise_init
struct Den(Copyable, Movable):
    """Where a pack of wolves keeps, how many they are, and how strong."""

    # The den's middle, in meters.
    var x: Float32
    var z: Float32
    # How many wolves, and the seed of their build and their dice.
    var count: Int
    var seed: Int
    var fighter: FighterParameters


def den_places(den: Den) -> List[Vector3]:
    """Return where each wolf of a den lies.

    Args:
        den: The den.

    Returns:
        One point a wolf, on the ground's plane: the first at the den's
        middle, the rest on a ring 1.8 meters round it.
    """
    var out = List[Vector3]()
    for k in range(den.count):
        if k == 0:
            out.append(Vector3(den.x, 0, den.z))
            continue
        var a = Float32(2 * pi) * Float32(k) / Float32(max(1, den.count - 1))
        out.append(Vector3(den.x + 1.8 * cos(a), 0, den.z + 1.8 * sin(a)))
    return out^


def default_dens() -> List[Den]:
    """Return the wolves of the default village.

    Returns:
        A pack of three wolves 30 meters east of the pond.
    """
    return [Den(38, 20, 3, 71, wolf_fighter())]


def dummy_fighter() -> FighterParameters:
    """Return how strong a straw dummy is.

    Returns:
        A great deal of health, 120 ki that comes back at 40 a second
        after a second, a guard that covers nothing and never parries, and
        no Over Limit.
    """
    var p = FighterParameters()
    p.health = 1.0e5
    p.ki = 120
    p.ki_rate = Frequency(40.0, PER_SECOND)
    p.ki_delay = Duration(1.0, SECOND)
    p.arte_points = 0
    p.arte_rate = Frequency(0.0, PER_SECOND)
    p.guard_arc = Angle(0.0, DEGREE)
    p.parry = Duration(0.0, SECOND)
    p.limit_gain = 0
    return p


def default_bandits() raises -> List[Bandit]:
    """Return the bandits of the default village.

    Returns:
        Three hooded bandits round a camp past the meadow's north-west
        edge, 25 meters from where the player starts: one in walnut
        brown, one in gray and one in nettle green. Behind them stands
        their captain, taller, in madder red: see `captain_fighter`.

    Raises:
        Error: Never: the outfits check.
    """
    return [
        Bandit(
            HumanoidSpec(Length(69.0, INCH), MALE, TONED, random_genome(61)),
            village_outfit(WALNUT, GRAY_WOOL, WALNUT, True),
            -20,
            41,
            Angle(-60.0, DEGREE),
            61,
            bandit_fighter(),
        ),
        Bandit(
            HumanoidSpec(Length(71.0, INCH), MALE, TONED, random_genome(62)),
            village_outfit(GRAY_WOOL, WALNUT, WALNUT, True),
            -16.5,
            44,
            Angle(-120.0, DEGREE),
            62,
            bandit_fighter(),
        ),
        Bandit(
            HumanoidSpec(Length(67.0, INCH), MALE, TONED, random_genome(63)),
            village_outfit(NETTLE, WALNUT, GRAY_WOOL, True),
            -23,
            45,
            Angle(10.0, DEGREE),
            63,
            bandit_fighter(),
        ),
        Bandit(
            HumanoidSpec(Length(75.0, INCH), MALE, TONED, random_genome(64)),
            village_outfit(MADDER, WALNUT, WALNUT, True),
            -21,
            49,
            Angle(-90.0, DEGREE),
            64,
            captain_fighter(),
        ),
    ]


@fieldwise_init
struct Post(ImplicitlyCopyable):
    """Where a straw dummy stands, and the way it faces."""

    var x: Float32
    var z: Float32
    var heading: Angle


def default_posts() -> List[Post]:
    """Return the straw dummies of the default village.

    Returns:
        Two dummies east of where the player starts, facing them.
    """
    return [
        Post(5, 31, Angle(-100.0, DEGREE)),
        Post(7.5, 34, Angle(-120.0, DEGREE)),
    ]


def dummy_sheets(mut wood: Sheet, mut straw: Sheet, mut sack: Sheet):
    """Add a straw dummy about its foot: a post, a crossbar for arms, a
    body of bound straw, and a sack for a head.

    Args:
        wood: The sheet for the post and the crossbar.
        straw: The sheet for the straw.
        sack: The sheet for the head.
    """
    var oak = Vector3(0.8, 0.7, 0.6)
    prism(wood, Vector3(0, -0.2, 0), 0.05, 0.045, 1.95, 6, oak)
    wood.box(
        Vector3(0, 1.32, 0),
        Vector3(0.55, 0, 0),
        Vector3(0, 0.035, 0),
        Vector3(0, 0, 0.035),
        oak,
    )
    var hay = Vector3(1.0, 0.82, 0.38)
    prism(straw, Vector3(0, 0.75, 0), 0.2, 0.24, 0.62, 8, hay)
    # Two cords bind the straw.
    for at in [Float32(0.9), Float32(1.2)]:  # pragma: no branch
        prism(straw, Vector3(0, at, 0), 0.225, 0.225, 0.03, 8, hay * 0.45)
    # The arms: straw round the crossbar's ends.
    for side in [Float32(-1), Float32(1)]:  # pragma: no branch
        straw.box(
            Vector3(side * 0.42, 1.3, 0),
            Vector3(0.12, 0, 0),
            Vector3(0, 0.06, 0),
            Vector3(0, 0, 0.06),
            hay * 0.9,
        )
    prism(
        sack,
        Vector3(0, 1.42, 0),
        0.13,
        0.11,
        0.26,
        8,
        Vector3(0.85, 0.78, 0.62),
    )


struct Dummy(Movable):
    """A straw dummy in a scene: its fighter, its nodes, and how it rocks."""

    var post: Post
    # The ground's height at its post.
    var foot: Float32
    # The node at its foot, and the node it rocks on.
    var root: NodeId
    var pivot: NodeId
    # How far it leans, about x and about z, in radians, and how fast.
    var tilt: Vector3
    var spin: Vector3

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        looks: HouseLooks,
        post: Post,
        foot: Float32,
    ) raises:
        """Stand a straw dummy at its post.

        Args:
            scene: The scene.
            assets: The stores for its geometries.
            looks: The village's materials: the post is wood, the straw
                plaster and the sack cloth.
            post: Where it stands.
            foot: The ground's height there.

        Raises:
            Error: If a mesh cannot be added.
        """
        self.post = post
        self.foot = foot
        self.tilt = Vector3(0, 0, 0)
        self.spin = Vector3(0, 0, 0)
        var place = Object3D()
        place.set_position(post.x, foot, post.z)
        place.rotate_y(Angle(post.heading.to(RADIAN) + pi, RADIAN))
        self.root = scene.add(place^)
        self.pivot = scene.attach(Object3D(), self.root)
        var wood = Sheet(1)
        var straw = Sheet(1)
        var sack = Sheet(1)
        dummy_sheets(wood, straw, sack)
        var parts: List[MaterialId] = [looks.wood, looks.plaster, looks.cloth]
        var sheets = List[Sheet]()
        sheets.append(wood^)
        sheets.append(straw^)
        sheets.append(sack^)
        for k in range(3):  # pragma: no branch
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(sheets[k].geometry()),
                    parts[k],
                    self.pivot,
                    cast_shadow=True,
                    receive_shadow=True,
                )
            )

    def where(self) -> Vector3:
        """Return where the dummy's foot is.

        Returns:
            The post, at the ground's height.
        """
        return Vector3(self.post.x, self.foot, self.post.z)

    def knock(mut self, way: Vector3, speed: Float32):
        """Set the dummy rocking away from a blow.

        Args:
            way: The way the blow pushes, on the ground, of length one.
            speed: How hard, in meters a second.
        """
        # A push along +z tips the top toward +z: a turn about +x.
        self.spin = self.spin + Vector3(way.z, 0, -way.x) * (ROCK_KICK * speed)

    def rock(mut self, mut scene: Scene, delta: Duration) raises:
        """Move the dummy's rocking on by one frame, and lean its node.

        Args:
            scene: The scene the dummy is in.
            delta: The frame's time.

        Raises:
            Error: Never: the node is the scene's.
        """
        var seconds = delta.to(SECOND)
        var pull = self.tilt * (-ROCK_STIFFNESS) - self.spin * ROCK_DAMPING
        self.spin = self.spin + pull * seconds
        self.tilt = self.tilt + self.spin * seconds
        var lean = clamp(self.tilt.length(), 0, 0.6)
        ref node = scene.node(self.pivot)
        if lean < 1.0e-5:
            node.set_rotation_from_axis_angle(
                Vector3(1, 0, 0), Angle(0.0, RADIAN)
            )
            return
        # The tilt is in the world's frame; the post is turned about +y.
        var turn = -(self.post.heading.to(RADIAN) + pi)
        var c = cos(turn)
        var s = sin(turn)
        var axis = Vector3(
            self.tilt.x * c + self.tilt.z * s,
            0,
            -self.tilt.x * s + self.tilt.z * c,
        )
        node.set_rotation_from_axis_angle(
            axis / self.tilt.length(), Angle(lean, RADIAN)
        )
