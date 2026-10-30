# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Swordplay: a fighter's health, ki and arte gauge, its moves, and what a
blow does to the fighter that it reaches.

A `Fighter` does not know where it stands. The game finds the fighters
that a swing reaches with `reaches`, and gives each one the blow that
`Fighter.connect` returns. `Fighter.receive` says what the blow did, and
`Fighter.landed` tells the attacker. The rules come from two games:

- **Ki, as in Nioh.** Each light attack, heavy attack and dodge spends
  ki. Ki comes back after `FighterParameters.ki_delay` without spending.
  A fighter that spends its last ki is winded: it staggers when its move
  ends. A guard takes a blow on ki, not on health. A **ki pulse**, a press
  of the guard button just after a swing, gets back the ki that the swing
  spent: all of it in the first `PULSE_PERFECT` seconds after the swing,
  and `PULSE_LATE` of it until `PULSE_WINDOW`. A blow that lands also takes
  ki. A fighter with no ki left staggers, and a blow on a staggered fighter
  is critical: it does `CRITICAL_BONUS` times its damage.
- **Stances, as in Nioh.** The high stance hits harder and more slowly,
  and costs more ki. The low stance is quick and costs less ki, and hits
  less hard. The middle stance is between them, and guards best. A stance
  changes the light and the heavy attacks, and the dodge's ki and length.
- **Artes, as in Tales of Arise.** An arte is a strong move that spends
  points of the arte gauge, not ki. The gauge fills by itself, and by
  `ARTE_PER_HIT` for each blow that lands. The rising edge throws a foe
  into the air. The tempest spins, and strikes all round four times.
- **Dodges, as in Tales of Arise.** No blow can hit a dodge from
  `DODGE_SAFE_FROM` to `DODGE_SAFE_TO` seconds into it. A blow that
  reaches a dodge before `DODGE_SAFE_FROM + PERFECT_WINDOW` is a perfect
  dodge. The dodger gets back the dodge's ki and `PERFECT_ARTE` points of
  the arte gauge. Its next attack within `COUNTER_SECONDS` is a counter,
  and does `COUNTER_BONUS` times its damage.
- **Guards.** A guard stops a blow from the front, within the guard's
  arc. A guard raised less than `FighterParameters.parry` before the blow
  parries it: the guard loses no ki, and the attacker loses the blow's ki
  and reels. The player parries within `PARRY` seconds. Some moves have armor: a blow on them does its damage, and does
  not make the fighter reel.
- **Combos.** The three light attacks chain. A press during a move waits,
  and its move starts at the move's chain point: after the active part
  and `CHAIN_SHARE` of the recovery. A dodge cuts the recovery of an
  attack short. Each blow that lands adds one to the combo, and each blow
  does `COMBO_STEP` more damage for each blow of the combo, up to
  `COMBO_CAP` blows. The combo ends `COMBO_KEEP` seconds after its last
  blow, or when the fighter is hit.

Each move has a start-up, an active part and a recovery. Only the active
part strikes. The times are for the middle stance:

| Move | Start-up | Active | Recovery | Reach | Arc | Damage | Ki damage | Ki | Arte points |
|---|---|---|---|---|---|---|---|---|---|
| `LIGHT_ONE` | 0.14 s | 0.10 s | 0.26 s | 2.0 m | 120 degrees | 30 | 8 | 9 | |
| `LIGHT_TWO` | 0.12 s | 0.10 s | 0.28 s | 2.0 m | 120 degrees | 33 | 9 | 9 | |
| `LIGHT_THREE` | 0.20 s | 0.12 s | 0.45 s | 2.3 m | 90 degrees | 54 | 16 | 12 | |
| `HEAVY` | 0.40 s | 0.14 s | 0.55 s | 2.5 m | 80 degrees | 90 | 30 | 22 | |
| `RISING_EDGE` | 0.16 s | 0.20 s | 0.45 s | 2.1 m | 100 degrees | 66 | 18 | | 2 |
| `TEMPEST` | 0.18 s | 0.48 s | 0.40 s | 2.6 m | 360 degrees | 27, four times | 7 | | 3 |
| `DODGE` | | 0.32 s | 0.16 s | | | | | 14 | |
"""

from controls.third_person_controls import wrap_angle, yaw_of
from core.ordinal import ordinal_valid
from extensions.vegetation.checks import require_between
from math.vector3 import Vector3
from std.math import atan2, sqrt
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

comptime MOVES = 11
"""How many moves there are, `FREE` among them."""
comptime DODGE_SAFE_FROM = Float32(0.02)
"""How far into a dodge no blow can hit it any more, in seconds."""
comptime DODGE_SAFE_TO = Float32(0.30)
"""How far into a dodge a blow can hit it again, in seconds."""
comptime PERFECT_WINDOW = Float32(0.15)
"""How long after `DODGE_SAFE_FROM` a blow that reaches a dodge makes a
perfect dodge, in seconds."""
comptime PERFECT_ARTE = Float32(1.0)
"""The points of the arte gauge that a perfect dodge gives."""
comptime COUNTER_SECONDS = Float32(1.2)
"""How long after a perfect dodge an attack is a counter, in seconds."""
comptime COUNTER_BONUS = Float32(2.0)
"""How many times its damage a counter does."""
comptime PARRY = Float32(0.15)
"""How long after the player raises a guard it parries a blow, in
seconds."""
comptime CRITICAL_BONUS = Float32(1.5)
"""How many times its damage a blow on a staggered fighter does."""
comptime PULSE_PERFECT = Float32(0.15)
"""How long after a swing a ki pulse gets back all its ki, in seconds."""
comptime PULSE_WINDOW = Float32(0.45)
"""How long after a swing a ki pulse can be made, in seconds."""
comptime PULSE_LATE = Float32(0.5)
"""The share of a swing's ki that a late ki pulse gets back."""
comptime GUARD_REGAIN = Float32(0.5)
"""The share of its usual pace at which ki comes back during a guard."""
comptime CHAIN_SHARE = Float32(0.3)
"""The share of a move's recovery after which a waiting move starts."""
comptime COMBO_STEP = Float32(0.02)
"""How much more damage each blow of a combo adds to the next blow."""
comptime COMBO_CAP = 25
"""The most blows of a combo that add damage."""
comptime COMBO_KEEP = Float32(2.5)
"""How long a combo lasts after its last blow, in seconds."""
comptime ARTE_PER_HIT = Float32(0.2)
"""The points of the arte gauge that each blow that lands gives."""
comptime REACH_HEIGHT = Float32(1.8)
"""How far above or below a swing a fighter can be and still be hit, in
meters."""


@fieldwise_init
struct CombatMove(Equatable, ImplicitlyCopyable, Writable):
    """What a fighter does, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the moves.

        Returns:
            True from `FREE` to `FALL`.
        """
        return ordinal_valid(self.value, MOVES - 1)


comptime FREE = CombatMove(0)
"""No move: the fighter walks, runs, jumps and guards."""
comptime LIGHT_ONE = CombatMove(1)
"""The first light attack: a cut from the right to the left."""
comptime LIGHT_TWO = CombatMove(2)
"""The second light attack: a backhand cut from the left to the right."""
comptime LIGHT_THREE = CombatMove(3)
"""The third light attack, which ends the chain: a cut down from over the
head."""
comptime HEAVY = CombatMove(4)
"""The heavy attack: a cut with both hands from high on the right."""
comptime RISING_EDGE = CombatMove(5)
"""An arte: a cut up from low, which throws the foe into the air."""
comptime TEMPEST = CombatMove(6)
"""An arte: a spin that strikes all round the fighter four times."""
comptime DODGE = CombatMove(7)
"""A quick step, which no blow can hit for a moment."""
comptime FLINCH = CombatMove(8)
"""A blow landed: the fighter reels for a moment."""
comptime STAGGER = CombatMove(9)
"""The fighter's ki ran out: it stands open, and blows on it are
critical."""
comptime FALL = CombatMove(10)
"""The fighter is defeated: it falls, and it stays down."""


@fieldwise_init
struct CombatStance(Equatable, ImplicitlyCopyable, Writable):
    """How a fighter holds its sword, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the stances.

        Returns:
            True for `HIGH_STANCE`, `MID_STANCE` and `LOW_STANCE`.
        """
        return ordinal_valid(self.value, 2)


comptime HIGH_STANCE = CombatStance(0)
"""The sword over the head: strong, slow and costly."""
comptime MID_STANCE = CombatStance(1)
"""The sword before the body: even, and the best guard."""
comptime LOW_STANCE = CombatStance(2)
"""The sword low: quick and cheap, and weaker."""


@fieldwise_init
struct StrikeOutcome(Equatable, ImplicitlyCopyable, Writable):
    """What a blow did, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is one of the outcomes.

        Returns:
            True from `IGNORED` to `DEFEATED`.
        """
        return ordinal_valid(self.value, 9)


comptime IGNORED = StrikeOutcome(0)
"""The fighter is already down: the blow does nothing."""
comptime EVADED = StrikeOutcome(1)
"""A dodge let the blow pass."""
comptime PERFECT_DODGE = StrikeOutcome(2)
"""A dodge let the blow pass at the last moment: see `PERFECT_WINDOW`."""
comptime BLOCKED = StrikeOutcome(3)
"""A guard took the blow on ki."""
comptime PARRIED = StrikeOutcome(4)
"""A fresh guard turned the blow, and the attacker reels."""
comptime GUARD_BREAK = StrikeOutcome(5)
"""A guard took the blow, and its ki ran out: the fighter staggers."""
comptime HIT = StrikeOutcome(6)
"""The blow landed."""
comptime CRITICAL = StrikeOutcome(7)
"""The blow landed on a staggered fighter."""
comptime KI_BREAK = StrikeOutcome(8)
"""The blow landed, and took the fighter's last ki: it staggers."""
comptime DEFEATED = StrikeOutcome(9)
"""The blow landed, and took the fighter's last health: it falls."""


def move_name(move: CombatMove) raises -> String:
    """Return a move's name, in capitals for the display.

    Args:
        move: The move.

    Returns:
        Such as "LIGHT 1", "HEAVY", "RISING EDGE" or "TEMPEST".

    Raises:
        Error: If the move is not one.
    """
    if not move.is_valid():
        raise Error("A combat move must be one of the eleven")
    var names: List[String] = [
        "FREE",
        "LIGHT 1",
        "LIGHT 2",
        "LIGHT 3",
        "HEAVY",
        "RISING EDGE",
        "TEMPEST",
        "DODGE",
        "FLINCH",
        "STAGGER",
        "FALL",
    ]
    return names[move.value]


def outcome_word(outcome: StrikeOutcome) raises -> String:
    """Return what the display says of an outcome, over the fighter.

    Args:
        outcome: The outcome.

    Returns:
        "PERFECT DODGE", "BLOCKED", "PARRY", "GUARD BREAK", "CRITICAL" or
        "BREAK", or an empty string for an outcome that shows its damage
        alone, or nothing.

    Raises:
        Error: If the outcome is not one.
    """
    if not outcome.is_valid():
        raise Error("A blow's outcome must be one of the ten")
    var words: List[String] = [
        "",
        "",
        "PERFECT DODGE",
        "BLOCKED",
        "PARRY",
        "GUARD BREAK",
        "",
        "CRITICAL",
        "BREAK",
        "",
    ]
    return words[outcome.value]


def is_attack(move: CombatMove) -> Bool:
    """Return whether a move strikes.

    Args:
        move: The move.

    Returns:
        True for the light and the heavy attacks and the artes.
    """
    return move.value >= LIGHT_ONE.value and move.value <= TEMPEST.value


def is_arte(move: CombatMove) -> Bool:
    """Return whether a move is an arte, which spends the arte gauge.

    Args:
        move: The move.

    Returns:
        True for `RISING_EDGE` and `TEMPEST`.
    """
    return move == RISING_EDGE or move == TEMPEST


def styled(move: CombatMove) -> Bool:
    """Return whether a fighter's stance changes a move.

    Args:
        move: The move.

    Returns:
        True for the light and the heavy attacks.
    """
    return move.value >= LIGHT_ONE.value and move.value <= HEAVY.value


def landed_blow(outcome: StrikeOutcome) -> Bool:
    """Return whether an outcome is a blow that landed.

    Args:
        outcome: The outcome.

    Returns:
        True for `HIT`, `CRITICAL`, `KI_BREAK` and `DEFEATED`.
    """
    return outcome.value >= HIT.value


def next_light(move: CombatMove) -> CombatMove:
    """Return the light attack that follows a move in the chain.

    Args:
        move: The move the fighter makes now.

    Returns:
        `LIGHT_TWO` after `LIGHT_ONE`, `LIGHT_THREE` after `LIGHT_TWO`,
        and `LIGHT_ONE` after any other move.
    """
    if move == LIGHT_ONE:
        return LIGHT_TWO
    if move == LIGHT_TWO:
        return LIGHT_THREE
    return LIGHT_ONE


@fieldwise_init
struct MoveData(ImplicitlyCopyable):
    """The times and the strength of a move, in the middle stance."""

    # How long the move takes to strike, strikes, and takes to end.
    var startup: Duration
    var active: Duration
    var recovery: Duration
    # How far the swing reaches from the fighter's middle, and the angle
    # of its arc round the fighter's heading.
    var reach: Length
    var arc: Angle
    # The health and the ki that a blow takes.
    var damage: Float32
    var ki_damage: Float32
    # The ki and the points of the arte gauge that the move spends.
    var ki_cost: Float32
    var arte_cost: Float32
    # How far the fighter moves forward over the start-up and the active
    # part. A dodge moves this far over its active part.
    var lunge: Length
    # How many times the active part strikes each fighter it reaches.
    var hits: Int
    # How fast a blow pushes the fighter it hits away, and throws it up.
    var knockback: Velocity
    var launch: Velocity


def _data(
    startup: Float32,
    active: Float32,
    recovery: Float32,
    reach: Float32 = 0,
    arc: Float32 = 0,
    damage: Float32 = 0,
    ki_damage: Float32 = 0,
    ki_cost: Float32 = 0,
    arte_cost: Float32 = 0,
    lunge: Float32 = 0,
    hits: Int = 0,
    knockback: Float32 = 0,
    launch: Float32 = 0,
) -> MoveData:
    """Return a move's data from seconds, meters, degrees and meters a
    second."""
    return MoveData(
        Duration(startup, SECOND),
        Duration(active, SECOND),
        Duration(recovery, SECOND),
        Length(reach, METER),
        Angle(arc, DEGREE),
        damage,
        ki_damage,
        ki_cost,
        arte_cost,
        Length(lunge, METER),
        hits,
        Velocity(knockback, METER_PER_SECOND),
        Velocity(launch, METER_PER_SECOND),
    )


def move_data(move: CombatMove) raises -> MoveData:
    """Return the times and the strength of a move, in the middle stance.

    Args:
        move: The move.

    Returns:
        The values in the table of the module's docstring. A flinch lasts
        0.4 seconds, a stagger 1.6 and a fall 2. `FREE` lasts no time.

    Raises:
        Error: If the move is not one.
    """
    if move == LIGHT_ONE:
        return _data(0.14, 0.1, 0.26, 2, 120, 30, 8, 9, 0, 0.35, 1, 1.5)
    if move == LIGHT_TWO:
        return _data(0.12, 0.1, 0.28, 2, 120, 33, 9, 9, 0, 0.35, 1, 1.5)
    if move == LIGHT_THREE:
        return _data(0.2, 0.12, 0.45, 2.3, 90, 54, 16, 12, 0, 0.6, 1, 4)
    if move == HEAVY:
        return _data(0.4, 0.14, 0.55, 2.5, 80, 90, 30, 22, 0, 0.8, 1, 5)
    if move == RISING_EDGE:
        return _data(0.16, 0.2, 0.45, 2.1, 100, 66, 18, 0, 2, 0.4, 1, 1, 6.5)
    if move == TEMPEST:
        return _data(0.18, 0.48, 0.4, 2.6, 360, 27, 7, 0, 3, 0, 4, 2.5)
    if move == DODGE:
        return _data(0, 0.32, 0.16, ki_cost=14, lunge=3.2)
    if move == FLINCH:
        return _data(0, 0, 0.4)
    if move == STAGGER:
        return _data(0, 0, 1.6)
    if move == FALL:
        return _data(0, 0, 2)
    if move == FREE:
        return _data(0, 0, 0)
    raise Error("A combat move must be one of the eleven")


def stance_power(stance: CombatStance) -> Float32:
    """Return how many times its damage and its ki damage a stance's
    light and heavy attacks do.

    Args:
        stance: The stance.

    Returns:
        1.3 high, 1 in the middle and 0.75 low.
    """
    if stance == HIGH_STANCE:
        return 1.3
    if stance == LOW_STANCE:
        return 0.75
    return 1


def stance_pace(stance: CombatStance) -> Float32:
    """Return how many times its time a stance's light or heavy attack
    takes.

    Args:
        stance: The stance.

    Returns:
        1.2 high, 1 in the middle and 0.8 low.
    """
    if stance == HIGH_STANCE:
        return 1.2
    if stance == LOW_STANCE:
        return 0.8
    return 1


def stance_cost(stance: CombatStance) -> Float32:
    """Return how many times its ki a stance's light attack, heavy attack
    or dodge spends.

    Args:
        stance: The stance.

    Returns:
        1.3 high, 1 in the middle and 0.7 low.
    """
    if stance == HIGH_STANCE:
        return 1.3
    if stance == LOW_STANCE:
        return 0.7
    return 1


def stance_guard(stance: CombatStance) -> Float32:
    """Return how many times a blow's ki damage a guard in a stance loses.

    Args:
        stance: The stance.

    Returns:
        1.2 high, 0.75 in the middle and 1 low.
    """
    if stance == HIGH_STANCE:
        return 1.2
    if stance == LOW_STANCE:
        return 1
    return 0.75


def stance_step(stance: CombatStance) -> Float32:
    """Return how many times its length a dodge in a stance goes.

    Args:
        stance: The stance.

    Returns:
        0.9 high, 1 in the middle and 1.15 low.
    """
    if stance == HIGH_STANCE:
        return 0.9
    if stance == LOW_STANCE:
        return 1.15
    return 1


def combo_bonus(combo: Int) -> Float32:
    """Return how many times its damage a blow of a combo does.

    Args:
        combo: How many blows of the combo landed before it.

    Returns:
        One plus `COMBO_STEP` for each blow, up to `COMBO_CAP` blows.
    """
    return 1 + COMBO_STEP * Float32(max(0, min(combo, COMBO_CAP)))


def faces(at: Vector3, heading: Angle, arc: Angle, toward: Vector3) -> Bool:
    """Return whether a point lies within an arc round a heading.

    Args:
        at: Where the one who looks stands. Its y is not used.
        heading: The way it faces, as a yaw: see `yaw_of`.
        arc: The angle of the arc, centered on the heading.
        toward: The point. A point on `at` lies within every arc.

    Returns:
        Whether the yaw from `at` to the point is within half the arc of
        the heading.
    """
    var dx = toward.x - at.x
    var dz = toward.z - at.z
    if dx * dx + dz * dz < 1.0e-8:
        return True
    var off = wrap_angle(
        Angle(
            yaw_of(Vector3(dx, 0, dz)).to(RADIAN) - heading.to(RADIAN), RADIAN
        )
    )
    return abs(off.to(RADIAN)) <= arc.to(RADIAN) / 2


def reaches(
    at: Vector3,
    heading: Angle,
    reach: Length,
    arc: Angle,
    target: Vector3,
    radius: Length,
) -> Bool:
    """Return whether a swing reaches a round target.

    Args:
        at: Where the swinging fighter's feet are.
        heading: The way it faces, as a yaw.
        reach: How far the swing reaches from its middle.
        arc: The angle of the swing's arc, centered on the heading.
        target: Where the target's feet are.
        radius: The target's radius.

    Returns:
        Whether the target's circle comes within `reach`, its feet are
        less than `REACH_HEIGHT` above or below, and some of its circle
        lies within the arc.
    """
    var dx = target.x - at.x
    var dz = target.z - at.z
    var gap = sqrt(dx * dx + dz * dz)
    var r = radius.to(METER)
    if gap > reach.to(METER) + r:
        return False
    if abs(target.y - at.y) > REACH_HEIGHT:
        return False
    # The target's own width widens the arc by the angle it fills.
    var widen = Angle(2 * atan2(r, gap), RADIAN)
    return faces(
        at, heading, Angle(arc.to(RADIAN) + widen.to(RADIAN), RADIAN), target
    )


@fieldwise_init
struct Swing(ImplicitlyCopyable):
    """The part of a move that strikes now: how far and how wide it
    reaches, and which of the move's hits it is."""

    var reach: Length
    var arc: Angle
    # Which of the move's hits strikes now, from 0.
    var slice: Int


@fieldwise_init
struct Blow(ImplicitlyCopyable):
    """What a swing does to a fighter it reaches."""

    var damage: Float32
    var ki_damage: Float32
    # How fast it pushes the fighter away from the attacker, and throws it
    # up.
    var knockback: Velocity
    var launch: Velocity


@fieldwise_init
struct Struck(ImplicitlyCopyable):
    """What a blow did to a fighter: the outcome, and the health and the
    ki it took. For `PARRIED`, `ki` is what the attacker loses."""

    var outcome: StrikeOutcome
    var damage: Float32
    var ki: Float32


struct FighterParameters(ImplicitlyCopyable):
    """How strong a fighter is: its health, its ki, its arte gauge and its
    blows."""

    # The most health, and the most ki.
    var health: Float32
    var ki: Float32
    # How fast ki comes back, in points a second, and how long after the
    # fighter last spent ki it starts to.
    var ki_rate: Frequency
    var ki_delay: Duration
    # The most points of the arte gauge, and how fast they come back, in
    # points a second.
    var arte_points: Float32
    var arte_rate: Frequency
    # How many times a move's damage and ki damage the fighter's blows do.
    var might: Float32
    # The arc in front of the fighter that its guard covers, and how long
    # after the guard is raised it parries a blow.
    var guard_arc: Angle
    var parry: Duration

    def __init__(out self):
        """Create the player: 500 health, 100 ki that comes back at 32 a
        second after 0.6 seconds, an arte gauge of 5 points that comes
        back at half a point a second, blows of the moves' own strength,
        and a guard of 140 degrees that parries for `PARRY` seconds."""
        self.health = 500
        self.ki = 100
        self.ki_rate = Frequency(32.0, PER_SECOND)
        self.ki_delay = Duration(0.6, SECOND)
        self.arte_points = 5
        self.arte_rate = Frequency(0.5, PER_SECOND)
        self.might = 1
        self.guard_arc = Angle(140.0, DEGREE)
        self.parry = Duration(PARRY, SECOND)

    def check(self) raises:
        """Refuse a fighter that cannot fight.

        Raises:
            Error: If the health, the ki or the might is not above zero
                and below a million; a rate or the arte gauge is negative
                or not below a million; the delay is negative or not below
                10,000 seconds; the guard's arc is not from 0 to 360
                degrees; or the parry is not from 0 to 10 seconds.
        """
        for value in [self.health, self.ki, self.might]:  # pragma: no branch
            if not (value > 0 and value < 1.0e6):
                raise Error(
                    "A fighter's health, ki and might must be above zero"
                    " and below a million"
                )
        for value in [  # pragma: no branch
            self.ki_rate.to(PER_SECOND),
            self.arte_points,
            self.arte_rate.to(PER_SECOND),
        ]:
            require_between(
                value,
                0,
                1.0e6,
                "A fighter's rates and arte gauge must be from 0 to a million",
            )
        require_between(
            self.ki_delay.to(SECOND),
            0,
            1.0e4,
            "A fighter's ki delay must be from 0 to 10,000 seconds",
        )
        require_between(
            self.guard_arc.to(DEGREE),
            0,
            360,
            "A fighter's guard must cover from 0 to 360 degrees",
        )
        require_between(
            self.parry.to(SECOND),
            0,
            10,
            "A fighter's parry must last from 0 to 10 seconds",
        )


struct Fighter(Copyable, Movable):
    """One fighter's health, ki and arte gauge, its stance, and the move
    it makes."""

    var parameters: FighterParameters
    var health: Float32
    var ki: Float32
    # The points of the arte gauge.
    var arte: Float32
    var stance: CombatStance
    var move: CombatMove
    # How far into the move the fighter is, in seconds, now and before
    # the last update.
    var clock: Float32
    var before: Float32
    # How many times its time the move takes: see `stance_pace`.
    var pace: Float32
    # The move that waits for the chain point, or `FREE` for none.
    var queued: CombatMove
    # Whether the fighter guards, and for how long, in seconds.
    var guarding: Bool
    var guard_age: Float32
    # How long ago the fighter last spent ki, in seconds; and the ki that
    # the move spent.
    var rest: Float32
    var spent: Float32
    # How long ago the last swing's active part ended, in seconds, or -1
    # when no ki pulse can be made; and the ki a pulse gets back.
    var pulse_age: Float32
    var pulse_ki: Float32
    # How long an attack is still a counter, in seconds; whether the move
    # is a counter; and whether its dodge was already perfect.
    var counter: Float32
    var countering: Bool
    var perfected: Bool
    # The targets that the move's present hit struck, and which hit that
    # is.
    var struck: List[Int]
    var slice: Int
    # How many blows of the combo landed, and how long ago the last did,
    # in seconds.
    var combo: Int
    var combo_age: Float32
    # Whether the fighter spent its last ki: it staggers when its move
    # ends.
    var winded: Bool

    def __init__(out self, parameters: FighterParameters) raises:
        """Create a fighter with full health, ki and arte gauge, in the
        middle stance, free.

        Args:
            parameters: How strong it is.

        Raises:
            Error: If `parameters.check` refuses a value.
        """
        parameters.check()
        self.parameters = parameters
        self.health = parameters.health
        self.ki = parameters.ki
        self.arte = parameters.arte_points
        self.stance = MID_STANCE
        self.move = FREE
        self.clock = 0
        self.before = 0
        self.pace = 1
        self.queued = FREE
        self.guarding = False
        self.guard_age = 0
        self.rest = 0
        self.spent = 0
        self.pulse_age = -1
        self.pulse_ki = 0
        self.counter = 0
        self.countering = False
        self.perfected = False
        self.struck = List[Int]()
        self.slice = -1
        self.combo = 0
        self.combo_age = 0
        self.winded = False

    def free(self) -> Bool:
        """Return whether the fighter makes no move, so it can walk.

        Returns:
            True when the move is `FREE`.
        """
        return self.move == FREE

    def defeated(self) -> Bool:
        """Return whether the fighter is down.

        Returns:
            True when the move is `FALL`.
        """
        return self.move == FALL

    def length(self) raises -> Float32:
        """Return how long the move lasts, in seconds, at its pace.

        Returns:
            The start-up, the active part and the recovery, added.

        Raises:
            Error: Never: the move is one.
        """
        var data = move_data(self.move)
        return (
            data.startup.to(SECOND)
            + data.active.to(SECOND)
            + data.recovery.to(SECOND)
        ) * self.pace

    def active_end(self) raises -> Float32:
        """Return how far into the move its active part ends, in seconds.

        Returns:
            The start-up and the active part, added, at the move's pace.

        Raises:
            Error: Never: the move is one.
        """
        var data = move_data(self.move)
        return (data.startup.to(SECOND) + data.active.to(SECOND)) * self.pace

    def chain_point(self) raises -> Float32:
        """Return how far into the move a waiting move starts, in seconds.

        Returns:
            The end of the active part, and `CHAIN_SHARE` of the recovery
            after it, at the move's pace.

        Raises:
            Error: Never: the move is one.
        """
        var data = move_data(self.move)
        return (
            self.active_end()
            + data.recovery.to(SECOND) * CHAIN_SHARE * self.pace
        )

    def invulnerable(self) -> Bool:
        """Return whether no blow can hit the fighter now.

        Returns:
            True from `DODGE_SAFE_FROM` to `DODGE_SAFE_TO` into a dodge.
        """
        return (
            self.move == DODGE
            and self.clock >= DODGE_SAFE_FROM
            and self.clock <= DODGE_SAFE_TO
        )

    def armored(self) raises -> Bool:
        """Return whether a blow that lands now does not make the fighter
        reel.

        Returns:
            True for a heavy attack or a tempest, until its active part
            ends.

        Raises:
            Error: Never: the move is one.
        """
        return (
            self.move == HEAVY or self.move == TEMPEST
        ) and self.clock < self.active_end()

    def ki_price(self, move: CombatMove) raises -> Float32:
        """Return the ki that a move spends in the fighter's stance.

        Args:
            move: The move.

        Returns:
            The move's ki, times `stance_cost` for a light attack, a
            heavy attack or a dodge.

        Raises:
            Error: If the move is not one.
        """
        var cost = move_data(move).ki_cost
        if styled(move) or move == DODGE:
            cost *= stance_cost(self.stance)
        return cost

    def drive(self) raises -> Velocity:
        """Return how fast the move carries the fighter along its heading,
        or along the dodge's way.

        Returns:
            For an attack, its lunge over its start-up and active part;
            for a dodge, its length in the stance over its active part.
            Zero after the active part, and for every other move.

        Raises:
            Error: Never: the move is one.
        """
        if not (is_attack(self.move) or self.move == DODGE):
            return Velocity(0.0, METER_PER_SECOND)
        var end = self.active_end()
        if self.clock >= end:
            return Velocity(0.0, METER_PER_SECOND)
        var data = move_data(self.move)
        var far = data.lunge.to(METER)
        var over = end
        if self.move == DODGE:
            far *= stance_step(self.stance)
            over -= data.startup.to(SECOND)
        return Velocity(far / over, METER_PER_SECOND)

    def _begin(mut self, move: CombatMove):
        """Start a move with no cost, at its start."""
        self.move = move
        self.clock = 0
        self.before = 0
        self.pace = stance_pace(self.stance) if styled(move) else 1
        self.queued = FREE
        self.guarding = False
        self.struck.clear()
        self.slice = -1
        self.countering = False
        self.perfected = False
        if is_attack(move) and self.counter > 0:
            self.countering = True
            self.counter = 0

    def _spend(mut self, cost: Float32):
        """Spend ki: a fighter that spends its last is winded."""
        self.spent = cost
        if cost <= 0:
            return
        self.ki -= cost
        self.rest = 0
        if self.ki <= 0:
            self.ki = 0
            self.winded = True

    def _start(mut self, move: CombatMove) raises -> Bool:
        """Start a move if the fighter has the ki and the arte points it
        spends; return whether it started."""
        var cost = self.ki_price(move)
        if cost > 0 and self.ki <= 0:
            return False
        var points = move_data(move).arte_cost
        if self.arte < points:
            return False
        self._begin(move)
        self.arte -= points
        self._spend(cost)
        return True

    def _finish(mut self):
        """End the move: a winded fighter staggers, and any other is free."""
        if self.winded:
            self.winded = False
            self._begin(STAGGER)
            return
        self._begin(FREE)

    def request(mut self, move: CombatMove) raises -> Bool:
        """Ask the fighter to make a move.

        A free fighter starts it at once, if it has the ki and the arte
        points. During an attack or a dodge, the move waits for the chain
        point; a dodge in an attack's recovery starts at once. A later
        request replaces a waiting one. A fighter that reels, staggers or
        is down cannot make a move.

        Args:
            move: An attack or `DODGE`.

        Returns:
            Whether the move started or waits.

        Raises:
            Error: If the move is not an attack or a dodge.
        """
        if not (is_attack(move) or move == DODGE):
            raise Error("A fighter can only ask for an attack or a dodge")
        if self.move == FREE:
            return self._start(move)
        if not (is_attack(self.move) or self.move == DODGE):
            return False
        if (
            move == DODGE
            and is_attack(self.move)
            and self.clock >= self.active_end()
        ):
            return self._start(move)
        self.queued = move
        return True

    def press_light(mut self) raises -> Bool:
        """Ask for the next light attack of the chain.

        Returns:
            Whether it started or waits: see `request`.

        Raises:
            Error: Never: a light attack is an attack.
        """
        return self.request(next_light(self.move))

    def hold_guard(mut self, held: Bool):
        """Guard while the guard button is held and the fighter is free.

        Args:
            held: Whether the guard button is held.
        """
        if not held:
            self.guarding = False
            return
        if self.move != FREE or self.guarding:
            return
        self.guarding = True
        self.guard_age = 0

    def pulse(mut self) -> Float32:
        """Make a ki pulse: get back the ki that the last swing spent.

        Returns:
            The ki it got back: the swing's ki within `PULSE_PERFECT`
            seconds of its active part's end, `PULSE_LATE` of it within
            `PULSE_WINDOW`, and zero otherwise. A pulse that gets ki back
            also catches the fighter's breath: it is not winded any more.
        """
        if self.pulse_age < 0:
            return 0
        var share = (
            Float32(1) if self.pulse_age <= PULSE_PERFECT else PULSE_LATE
        )
        var back = self.pulse_ki * share
        self.ki = min(self.parameters.ki, self.ki + back)
        self.pulse_age = -1
        if back > 0:
            self.winded = False
        return back

    def set_stance(mut self, stance: CombatStance) raises -> Bool:
        """Change the stance, while the fighter is free.

        Args:
            stance: The new stance.

        Returns:
            Whether the stance changed.

        Raises:
            Error: If the stance is not one.
        """
        if not stance.is_valid():
            raise Error("A combat stance must be high, middle or low")
        if self.move != FREE or stance == self.stance:
            return False
        self.stance = stance
        return True

    def update(mut self, delta: Duration) raises:
        """Move the fighter on by one frame.

        The move's clock runs. At the chain point a waiting move starts,
        and at its end the move ends. Ki comes back after the fighter's
        delay, at half pace while it guards. The arte gauge fills. The
        combo ends `COMBO_KEEP` after its last blow.

        Args:
            delta: The frame's time.

        Raises:
            Error: If the time is negative or above a billion seconds.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0 and seconds < 1.0e9):
            raise Error("A frame's time must not be negative or endless")
        if self.pulse_age >= 0:
            self.pulse_age += seconds
            if self.pulse_age > PULSE_WINDOW:
                self.pulse_age = -1
        self.before = self.clock
        if self.move != FREE:
            self.clock += seconds
            var swung = self.active_end()
            if (
                is_attack(self.move)
                and self.before < swung
                and self.clock >= swung
            ):
                self.pulse_age = self.clock - swung
                self.pulse_ki = self.spent
            if self.queued != FREE and self.clock >= self.chain_point():
                var next = self.queued
                self.queued = FREE
                _ = self._start(next)
            if self.move != FALL and self.clock >= self.length():
                self._finish()
        ref p = self.parameters
        self.rest += seconds
        if self.rest >= p.ki_delay.to(SECOND):
            var regain = p.ki_rate.to(PER_SECOND) * seconds
            if self.guarding:
                regain *= GUARD_REGAIN
            self.ki = min(p.ki, self.ki + regain)
        self.arte = min(
            p.arte_points, self.arte + p.arte_rate.to(PER_SECOND) * seconds
        )
        self.combo_age += seconds
        if self.combo_age > COMBO_KEEP:
            self.combo = 0
        self.counter = max(Float32(0), self.counter - seconds)
        self.guard_age += seconds

    def swing(self) raises -> Optional[Swing]:
        """Return the part of the move that strikes in the last update.

        Returns:
            The swing, if the move is an attack whose active part the last
            update reached; else None. Its slice is the hit of the active
            part that the update ended in, or the last.

        Raises:
            Error: Never: the move is one.
        """
        if not is_attack(self.move):
            return None
        var data = move_data(self.move)
        var start = data.startup.to(SECOND) * self.pace
        var end = self.active_end()
        if self.clock < start or self.before >= end:
            return None
        var share = (min(self.clock, end) - start) / (end - start)
        var slice = min(data.hits - 1, Int(share * Float32(data.hits)))
        return Swing(data.reach, data.arc, slice)

    def connect(mut self, target: Int) raises -> Optional[Blow]:
        """Return the blow that the swing gives a target it reaches.

        Each hit of a move strikes each target once.

        Args:
            target: Which target, as the game numbers them.

        Returns:
            The blow, or None if no swing strikes now, or the present hit
            already struck the target.

        Raises:
            Error: Never: the move is one.
        """
        var swing = self.swing()
        if not swing:
            return None
        var slice = swing.value().slice
        if slice != self.slice:
            self.slice = slice
            self.struck.clear()
        for index in self.struck:
            if index == target:
                return None
        self.struck.append(target)
        var data = move_data(self.move)
        var power = stance_power(self.stance) if styled(self.move) else 1
        var damage = (
            data.damage
            * self.parameters.might
            * power
            * combo_bonus(self.combo)
        )
        if self.countering:
            damage *= COUNTER_BONUS
        return Blow(
            damage,
            data.ki_damage * self.parameters.might * power,
            data.knockback,
            data.launch,
        )

    def receive(mut self, blow: Blow, front: Bool) raises -> Struck:
        """Take a blow.

        Args:
            blow: The blow.
            front: Whether the attacker stands within the guard's arc in
                front of the fighter: see `faces`.

        Returns:
            What the blow did. A dodge evades it. A guard takes it from the
            front on ki, or parries it when it was raised less than the
            fighter's parry before. Any other blow takes
            health and ki, and makes the fighter reel unless it has
            armor. A blow on a staggered fighter is critical, and takes no
            ki.

        Raises:
            Error: Never: each move is one.
        """
        if self.move == FALL:
            return Struck(IGNORED, 0, 0)
        if self.invulnerable():
            if (
                self.clock < DODGE_SAFE_FROM + PERFECT_WINDOW
                and not self.perfected
            ):
                self.perfected = True
                self.ki = min(self.parameters.ki, self.ki + self.spent)
                self.arte = min(
                    self.parameters.arte_points, self.arte + PERFECT_ARTE
                )
                self.counter = COUNTER_SECONDS
                return Struck(PERFECT_DODGE, 0, 0)
            return Struck(EVADED, 0, 0)
        if self.guarding and front:
            if self.guard_age < self.parameters.parry.to(SECOND):
                return Struck(PARRIED, 0, blow.ki_damage)
            var lost = blow.ki_damage * stance_guard(self.stance)
            self.ki -= lost
            self.rest = 0
            if self.ki <= 0:
                self.ki = 0
                self._begin(STAGGER)
                return Struck(GUARD_BREAK, 0, lost)
            return Struck(BLOCKED, 0, lost)
        self.combo = 0
        var damage = blow.damage
        var critical = self.move == STAGGER
        if critical:
            damage *= CRITICAL_BONUS
        self.health -= damage
        if self.health <= 0:
            self.health = 0
            self._begin(FALL)
            return Struck(DEFEATED, damage, 0)
        if critical:
            return Struck(CRITICAL, damage, 0)
        self.ki -= blow.ki_damage
        self.rest = 0
        if self.ki <= 0:
            self.ki = 0
            self._begin(STAGGER)
            return Struck(KI_BREAK, damage, blow.ki_damage)
        if not self.armored():
            self._begin(FLINCH)
        return Struck(HIT, damage, blow.ki_damage)

    def landed(mut self, struck: Struck):
        """Learn what the fighter's blow did.

        A blow that landed adds to the combo and fills the arte gauge. A
        parried blow costs the attacker the ki that `struck` names, and
        makes it reel, or stagger when its ki runs out.

        Args:
            struck: What the blow did.
        """
        if struck.outcome == PARRIED:
            self.ki -= struck.ki
            self.rest = 0
            if self.ki <= 0:
                self.ki = 0
                self._begin(STAGGER)
                return
            self._begin(FLINCH)
            return
        if landed_blow(struck.outcome):
            self.combo += 1
            self.combo_age = 0
            self.arte = min(
                self.parameters.arte_points, self.arte + ARTE_PER_HIT
            )

    def revive(mut self):
        """Stand the fighter up with full health, ki and arte gauge, free."""
        self.health = self.parameters.health
        self.ki = self.parameters.ki
        self.arte = self.parameters.arte_points
        self.winded = False
        self.combo = 0
        self.counter = 0
        self.pulse_age = -1
        self._begin(FREE)
