# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's styles in a fight: swapping them, combos and the beat, the
jump that cuts a recovery, spells and arrows, mends, the sprint, strafing,
hard landings, combos a level teaches, and fighters posed less often far
off.

The player stands at the middle and faces -z. Dummies stand 1.5 meters
before them, three meters apart: see `tests/_village_arena.mojo`."""

from tests._village_arena import (
    Arena,
    arena_parameters,
    holds_text,
    popup_texts,
)
from extensions.village.battle import (
    CHEST,
    FAR_POSE,
    LANDING_SHAKE,
    SPRINT_REST,
    Person,
    pose_person,
)
from extensions.village.character import (
    Character,
    MoveInput,
    no_input,
    player_movement,
)
from extensions.village.combat import (
    Blow,
    PLUNGE,
    STAGGER,
    AIMED_SHOT,
    ARROW_RAIN,
    DODGE,
    FREE,
    HEAVY,
    LEAP_SHOT,
    LIGHT_ONE,
    LIGHT_TWO,
    MEND,
    NOVA,
    QUICK_SHOT,
    RISING_EDGE,
    SPELL_BLAST,
    SPELL_BOLT,
    VOLLEY,
)
from extensions.village.combos import (
    BEAT_BONUS,
    LAND_MASTERY,
    LIGHT_KEY,
    MAKE_MASTERY,
)
from extensions.village.missiles import ARROW, ORB, SPARK, SPARK_LIFE, Missile
from extensions.village.skills import PRACTICE_EXPERIENCE
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MAGIC,
    SWORD,
    FightingStyle,
)
from controls.third_person_controls import yaw_of
from math.vector3 import Vector3
from extensions.village.party import PartyRole
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Velocity,
)


def _button(light: Bool = False, heavy: Bool = False) -> MoveInput:
    """Return an input that holds the light or the heavy attack."""
    var input = no_input()
    input.light = light
    input.heavy = heavy
    return input


def test_the_fights_parameters_are_checked() raises:
    var p = arena_parameters(0, 0)
    p.check()
    p.styles = List[FightingStyle]()
    with assert_raises(contains="one to six"):
        p.check()
    p = arena_parameters(0, 0)
    for k in range(7):
        p.styles.append(FightingStyle(k % 6))
    with assert_raises(contains="one to six"):
        p.check()
    p = arena_parameters(0, 0)
    p.styles.append(SWORD)
    with assert_raises(contains="apart"):
        p.check()
    p = arena_parameters(0, 0)
    p.styles[0] = FightingStyle(9)
    with assert_raises(contains="apart"):
        p.check()
    p = arena_parameters(0, 0)
    p.specialty = FightingStyle(-1)
    with assert_raises(contains="specialty"):
        p.check()
    p = arena_parameters(0, 0, raid=True)
    p.raids.append(p.raids[0].copy())
    with assert_raises(contains="one raid"):
        p.check()
    p = arena_parameters(0, 0, raid=True)
    p.raids[0].raiders[0].role = PartyRole(9)
    with assert_raises(contains="role"):
        p.check()
    p = arena_parameters(0, 0)
    p.fight_reach = 4
    with assert_raises(contains="reach"):
        p.check()
    p.fight_reach = 2.0e4
    with assert_raises(contains="reach"):
        p.check()


def test_the_player_swaps_styles_while_free() raises:
    var styles: List[FightingStyle] = [SWORD, MAGIC, HAND_TO_HAND]
    var arena = Arena(arena_parameters(0, 1, styles=styles))
    assert_true(arena.battle.fighter.style == SWORD)
    var swap = no_input()
    swap.swap = True
    arena.press(swap)
    assert_true(arena.battle.fighter.style == MAGIC)
    assert_true(holds_text(arena.battle.notes, "MAGIC"))
    # In a move, the swap waits for nothing: it does not change.
    _ = arena.battle.fighter.request(SPELL_BOLT)
    arena.press(swap)
    assert_true(arena.battle.fighter.style == MAGIC)
    arena.run(1)
    arena.press(swap)
    arena.press(swap)
    assert_true(arena.battle.fighter.style == SWORD)
    # The book shows and hides.
    var book = no_input()
    book.book = True
    arena.press(book)
    assert_true(arena.battle.reading)
    arena.press(book)
    assert_false(arena.battle.reading)


def test_a_string_of_presses_makes_a_combos_finisher() raises:
    var arena = Arena(arena_parameters(0, 1))
    var light = _button(light=True)
    var heavy = _button(heavy=True)
    arena.tick(light)
    arena.tick(no_input())
    arena.tick(light)
    arena.tick(no_input())
    arena.tick(heavy)
    assert_true(holds_text(arena.battle.notes, "RISING STRIKE!"))
    var found = arena.battle.finisher
    assert_true(found >= 0)
    assert_equal(arena.battle.book.mastery[found], MAKE_MASTERY)
    assert_equal(len(arena.battle.tracker.keys), 0)
    # The finisher lands on the dummy, and that masters the combo more;
    # enough ranks the combo up, and says so.
    arena.battle.book.mastery[found] = 38
    arena.run(1.5)
    assert_equal(arena.battle.book.mastery[found], 38 + LAND_MASTERY)
    assert_true(holds_text(arena.battle.notes, "RISING STRIKE RANK 2!"))
    assert_true(arena.battle.trained[SWORD.value] >= PRACTICE_EXPERIENCE)
    # Another move begun ends the finisher.
    _ = arena.battle.fighter.request(LIGHT_ONE)
    arena.tick(no_input())
    assert_equal(arena.battle.finisher, -1)


def test_a_finisher_in_the_air_plunges_and_a_spent_one_waits() raises:
    var arena = Arena(arena_parameters(0, 1))
    arena.battle.levels[SWORD.value] = 2
    arena.tick(no_input())
    # A heavy finisher in the air is a plunge.
    arena.tick(_button(light=True))
    arena.tick(no_input())
    arena.player.grounded = False
    arena.player.position = Vector3(0, 3, 0)
    arena.tick(_button(heavy=True))
    assert_true(arena.battle.finisher >= 0)
    assert_true(arena.battle.finishing == PLUNGE)
    # A finisher that cannot start leaves the string as it is.
    var spent = Arena(arena_parameters(0, 1))
    spent.battle.fighter.move = STAGGER
    for k in range(3):
        spent.tick(_button(light=k < 2, heavy=k == 2), 0.01)
        spent.tick(no_input(), 0.01)
    assert_equal(spent.battle.finisher, -1)
    assert_equal(len(spent.battle.tracker.keys), 3)


def test_a_finisher_asked_for_as_a_move_begins_still_waits() raises:
    var arena = Arena(arena_parameters(0, 0))
    _ = arena.battle.book.teach(SWORD, 10)
    # A light attack begins; in the frame it is first seen, the heavy key
    # ends a combo. The finisher waits for the light attack's chain point.
    _ = arena.battle.fighter.request(LIGHT_ONE)
    arena.battle.tracker.press(LIGHT_KEY, False)
    arena.tick(_button(heavy=True))
    assert_true(arena.battle.fighter.move == LIGHT_ONE)
    assert_true(arena.battle.finisher >= 0)
    assert_true(arena.battle.fighter.queued == arena.battle.finishing)


def test_a_press_on_the_beat_hits_harder() raises:
    var arena = Arena(arena_parameters(0, 1))
    _ = arena.battle.fighter.request(LIGHT_ONE)
    arena.battle.fighter.clock = arena.battle.fighter.active_end()
    arena.tick(_button(light=True), 0.001)
    assert_almost_equal(arena.battle.beat, 0.001, atol=1e-4)
    assert_almost_equal(
        arena.battle.fighter.queued_boost, BEAT_BONUS, atol=1e-6
    )
    arena.run(0.3)
    assert_true(arena.battle.beat > 0.2)


def test_a_jump_cuts_a_recovery_short() raises:
    var arena = Arena(arena_parameters(0, 0))
    _ = arena.battle.fighter.request(LIGHT_ONE)
    arena.battle.fighter.clock = 0.3
    var jump = no_input()
    jump.jump = True
    arena.tick(jump)
    assert_true(arena.battle.fighter.free())
    assert_false(arena.player.grounded)
    assert_equal(len(arena.battle.tracker.keys), 1)
    # In the air, a jump cuts nothing short, and is no key.
    arena.tick(no_input())
    _ = arena.battle.fighter.request(LIGHT_ONE)
    arena.tick(jump)
    assert_false(arena.battle.fighter.free())
    assert_equal(len(arena.battle.tracker.keys), 1)
    # A jump in the wind-up does nothing to the move.
    var early = Arena(arena_parameters(0, 0))
    _ = early.battle.fighter.request(HEAVY)
    early.tick(jump)
    assert_true(early.battle.fighter.move == HEAVY)
    # A free jump is a key too.
    var free = Arena(arena_parameters(0, 0))
    free.tick(jump)
    assert_equal(len(free.battle.tracker.keys), 1)


def test_a_guard_tap_and_a_dodge_are_keys() raises:
    var arena = Arena(arena_parameters(0, 0))
    var guard = no_input()
    guard.guard = True
    arena.press(guard)
    arena.battle.drawn = True
    var dodge = no_input()
    dodge.dodge = True
    arena.press(dodge)
    assert_equal(len(arena.battle.tracker.keys), 2)
    # A special breaks the string.
    var rising = no_input()
    rising.rising = True
    arena.run(1)
    arena.press(rising)
    assert_equal(len(arena.battle.tracker.keys), 0)
    assert_true(holds_text(arena.battle.notes, "RISING EDGE!"))


def test_spells_fly_at_the_target_and_an_orb_bursts() raises:
    var styles: List[FightingStyle] = [MAGIC]
    var arena = Arena(arena_parameters(0, 3, styles=styles))
    assert_true(arena.battle.fighter.style == MAGIC)
    # Two dummies stand twelve meters off, a meter and a half apart; the
    # third stands out of an orb's burst.
    arena.battle.dummies[0].dummy.post.z = -12
    arena.battle.dummies[1].dummy.post.x = 1.5
    arena.battle.dummies[1].dummy.post.z = -12
    arena.battle.dummies[2].dummy.post.x = 9
    arena.battle.dummies[2].dummy.post.z = -12
    arena.tick(_button(light=True))
    assert_true(arena.battle.fighter.move == SPELL_BOLT)
    arena.run(0.25)
    assert_true(len(arena.battle.shots) >= 1)
    assert_true(arena.battle.shots[0].kind == SPARK)
    arena.run(0.6)
    assert_equal(len(arena.battle.shots), 0)
    assert_true(arena.battle.trained[MAGIC.value] >= PRACTICE_EXPERIENCE)
    # A blast's orb bursts on both dummies.
    arena.battle.trained[MAGIC.value] = 0
    arena.battle.lock = 0
    arena.run(0.5)
    arena.tick(_button(heavy=True))
    assert_true(arena.battle.fighter.move == SPELL_BLAST)
    arena.run(0.6)
    var orb = False
    for shot in arena.battle.shots:
        orb = orb or shot.kind == ORB
    assert_true(orb)
    arena.run(1)
    assert_true(arena.battle.trained[MAGIC.value] >= 2 * PRACTICE_EXPERIENCE)


def test_arrows_lob_pierce_fan_and_rain() raises:
    var styles: List[FightingStyle] = [ARCHERY]
    var arena = Arena(arena_parameters(0, 3, styles=styles))
    # The dummies stand in a line, ten meters off and more.
    for k in range(3):
        arena.battle.dummies[k].dummy.post.x = 0
        arena.battle.dummies[k].dummy.post.z = -10 - 3 * Float32(k)
    arena.tick(_button(light=True))
    assert_true(arena.battle.fighter.move == QUICK_SHOT)
    arena.run(0.2)
    assert_true(len(arena.battle.shots) == 1)
    assert_true(arena.battle.shots[0].kind == ARROW)
    arena.run(0.5)
    assert_equal(len(arena.battle.shots), 0)
    # An aimed shot passes on through.
    arena.run(0.5)
    arena.tick(_button(heavy=True))
    assert_true(arena.battle.fighter.move == AIMED_SHOT)
    arena.run(0.65)
    assert_equal(arena.battle.shots[0].pierce, 2)
    arena.run(1)
    # A volley sends a fan; a leap shot one arrow; a rain falls from high.
    arena.run(1)
    var whirl = no_input()
    whirl.whirlwind = True
    arena.press(whirl)
    assert_true(arena.battle.fighter.move == VOLLEY)
    arena.run(0.4)
    assert_true(len(arena.battle.shots) >= 4)
    arena.run(2)
    var rising = no_input()
    rising.rising = True
    arena.press(rising)
    assert_true(arena.battle.fighter.move == LEAP_SHOT)
    arena.run(2)
    arena.battle.fighter.special = 5
    var wave = no_input()
    wave.ground_wave = True
    arena.press(wave)
    assert_true(arena.battle.fighter.move == ARROW_RAIN)
    arena.run(0.4)
    var high = False
    for shot in arena.battle.shots:
        high = high or shot.at.y > 5
    assert_true(high)
    arena.run(2)
    assert_equal(len(arena.battle.shots), 0)


def test_a_shot_with_no_target_falls_to_the_ground() raises:
    var styles: List[FightingStyle] = [ARCHERY]
    var arena = Arena(arena_parameters(0, 0, styles=styles))
    arena.player.heading = Angle(3.0, RADIAN)
    arena.tick(_button(light=True))
    arena.run(0.25)
    assert_equal(len(arena.battle.shots), 1)
    arena.run(2)
    assert_equal(len(arena.battle.shots), 0)
    # A rain with no target falls before the player.
    arena.battle.fighter.special = 5
    var wave = no_input()
    wave.ground_wave = True
    arena.press(wave)
    arena.run(0.4)
    assert_true(len(arena.battle.shots) > 0)
    arena.run(2)
    assert_equal(len(arena.battle.shots), 0)


def test_with_no_warden_and_no_companion_a_spell_flies_alone() raises:
    var styles: List[FightingStyle] = [MAGIC]
    var arena = Arena(arena_parameters(0, 1, styles=styles))
    # A taunt with no warden does nothing.
    var taunt = no_input()
    taunt.taunt = True
    arena.press(taunt)
    assert_equal(arena.battle.taunt_wait, 0)
    # A mend heals the player alone.
    arena.battle.fighter.health = 100
    arena.battle._mend(arena.player)
    assert_true(arena.battle.fighter.health > 100)
    # A spell bolt with no target before the player flies on until its
    # life ends: the dummy behind does not draw it.
    arena.player.heading = Angle(3.0, RADIAN)
    arena.tick(_button(light=True))
    arena.run(0.3)
    assert_equal(len(arena.battle.shots), 1)
    arena.run(SPARK_LIFE + 0.5)
    assert_equal(len(arena.battle.shots), 0)


def test_a_shot_flies_on_past_a_target_that_fell() raises:
    var styles: List[FightingStyle] = [ARCHERY]
    var arena = Arena(arena_parameters(1, 1, styles=styles))
    # The dummy stands out of the arrow's way.
    arena.battle.dummies[0].dummy.post.x = 5
    arena.battle.lock = 0
    arena.tick(_button(light=True))
    for _ in range(20):
        if len(arena.battle.shots) > 0:
            break
        arena.tick(no_input())
    assert_equal(len(arena.battle.shots), 1)
    # The bandit falls as the arrow flies: it is not struck again.
    ref foe = arena.battle.foes[0]
    foe.down = 0
    var health = foe.fighter.health
    arena.run(0.5)
    assert_equal(arena.battle.foes[0].fighter.health, health)
    # An orb's burst on the dummy passes the fallen bandit by.
    var chest = arena.battle.target_at(1) + Vector3(0, CHEST, 0)
    var blow = Blow(
        10, 2, Velocity(0.0, METER_PER_SECOND), Velocity(0.0, METER_PER_SECOND)
    )
    var orb = Missile(ORB, chest, Vector3(0, 0, -1), -1, -1, blow)
    arena.battle.shots.clear()
    arena.battle.shots.append(orb^)
    arena.battle._send_shots(arena.scene, arena.player, arena.terrain, 0.01)
    assert_equal(len(arena.battle.shots), 0)
    assert_equal(arena.battle.foes[0].fighter.health, health)


def test_a_mend_heals_the_player_and_the_companion_near() raises:
    var styles: List[FightingStyle] = [MAGIC]
    var arena = Arena(arena_parameters(0, 0, ally=True, styles=styles))
    arena.battle.fighter.health = 100
    arena.battle.allies[0].fighter.health = 100
    var rising = no_input()
    rising.rising = True
    arena.press(rising)
    assert_true(arena.battle.fighter.move == MEND)
    arena.run(1)
    assert_true(arena.battle.fighter.health > 100)
    assert_true(arena.battle.allies[0].fighter.health > 100)
    assert_true(arena.battle.mended > 0)
    # A companion far off is not healed.
    var far = Arena(arena_parameters(0, 0, ally=True, styles=styles))
    far.battle.allies[0].character.position = Vector3(30, 0, 0)
    far.battle.allies[0].fighter.health = 100
    far.press(rising)
    far.run(1)
    assert_equal(far.battle.allies[0].fighter.health, 100)


def test_a_sprint_spends_stamina_and_a_tired_player_runs() raises:
    var arena = Arena(arena_parameters(0, 0))
    arena.player = Character(
        player_movement(), 0, 0, Angle(0.0, RADIAN), arena.terrain
    )
    var run = MoveInput(1, 0, 0, 0, True, False)
    arena.run(1.5, run)
    assert_true(arena.player.sprinting)
    assert_true(arena.battle.fighter.stamina < 100)
    arena.battle.fighter.stamina = 0
    arena.tick(run)
    assert_true(arena.player.tired)
    # It stays tired until its stamina comes back to the rest.
    arena.battle.fighter.stamina = 1
    arena.tick(run)
    assert_true(arena.player.tired)
    arena.battle.fighter.stamina = SPRINT_REST
    arena.tick(run)
    assert_false(arena.player.tired)


def test_a_locked_player_strafes_around_the_target() raises:
    var arena = Arena(arena_parameters(0, 1))
    var lock = no_input()
    lock.lock = True
    arena.press(lock)
    assert_equal(arena.battle.lock, 0)
    arena.run(1, MoveInput(0, 1, 0, 0, False, False))
    # It faces the dummy as it steps round.
    var to = arena.battle.target_at(0) - arena.player.position
    var off = abs(arena.player.heading.to(RADIAN) - yaw_of(to).to(RADIAN))
    assert_true(off < 0.3 or off > 6)


def test_a_hard_landing_shakes_the_camera() raises:
    var arena = Arena(arena_parameters(0, 0))
    arena.player = Character(
        player_movement(), 0, 0, Angle(0.0, RADIAN), arena.terrain
    )
    arena.player.grounded = False
    arena.player.position = Vector3(0, 6, 0)
    arena.battle.shake = 0
    arena.run(1.2)
    assert_true(arena.battle.shake > 0)
    assert_equal(arena.player.landed, 0)
    # In a move, the landing shakes it too.
    var moving = Arena(arena_parameters(0, 0))
    moving.player.landed = 12
    _ = moving.battle.fighter.request(HEAVY)
    moving.battle.shake = 0
    moving.tick(no_input(), 0.001)
    assert_true(moving.battle.shake >= LANDING_SHAKE)
    assert_equal(moving.player.landed, 0)


def test_a_level_teaches_its_combos_and_says_so() raises:
    var arena = Arena(arena_parameters(0, 0))
    arena.battle.levels[SWORD.value] = 4
    arena.tick(no_input())
    assert_true(holds_text(arena.battle.notes, "NEW COMBO: TEMPEST"))
    assert_true(holds_text(arena.battle.notes, "NEW COMBO: DASH CUT"))


def test_fists_and_spells_leave_no_blades_trail() raises:
    var styles: List[FightingStyle] = [HAND_TO_HAND]
    var arena = Arena(arena_parameters(0, 0, styles=styles))
    arena.tick(_button(light=True))
    arena.run(0.15)
    assert_equal(arena.battle.trail.shown, -1)
    # A spinning kick does.
    arena.run(1)
    arena.battle.fighter.special = 5
    var whirl = no_input()
    whirl.whirlwind = True
    arena.tick(whirl)
    arena.run(0.3)
    assert_true(arena.battle.trail.shown >= 0)
    var axe: List[FightingStyle] = [AXE]
    var chopper = Arena(arena_parameters(0, 0, styles=axe))
    chopper.tick(_button(light=True))
    chopper.run(0.15)
    assert_true(chopper.battle.trail.shown >= 0)


def test_a_far_body_is_posed_less_often() raises:
    var arena = Arena(arena_parameters(1, 0, 20))
    ref person = arena.battle.people[0]
    ref foe = arena.battle.foes[0]
    var step = Duration(0.05, SECOND)
    pose_person(
        arena.scene,
        person,
        foe.character,
        foe.fighter,
        True,
        step,
        False,
        False,
    )
    assert_almost_equal(person.unposed, 0.05, atol=1e-6)
    assert_equal(person.trail.shown, -1)
    pose_person(
        arena.scene, person, foe.character, foe.fighter, True, step, False, True
    )
    assert_equal(person.unposed, 0)
    pose_person(
        arena.scene, person, foe.character, foe.fighter, True, step, True, False
    )
    assert_equal(person.unposed, 0)
    # A fight with a short reach poses its far bandit every few frames.
    var near = arena_parameters(1, 0, 20)
    near.fight_reach = 5
    var short = Arena(near)
    for _ in range(FAR_POSE - 1):
        short.tick(no_input())
    assert_almost_equal(
        short.battle.people[0].unposed, 0.05 * Float32(FAR_POSE - 1), atol=1e-5
    )
    short.tick(no_input())
    assert_equal(short.battle.people[0].unposed, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
