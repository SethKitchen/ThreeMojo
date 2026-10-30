# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Swordplay: the moves, the stances, ki, the arte gauge, guards, dodges
and what each blow does."""

from extensions.village.combat import (
    ARTE_PER_HIT,
    FINISHED,
    FINISH_SHARE,
    LIMIT,
    LIMIT_PER_BREAK,
    LIMIT_PER_HIT,
    LIMIT_PER_PARRY,
    LIMIT_PER_PERFECT,
    OVER_BONUS,
    OVER_SECONDS,
    BLOCKED,
    COMBO_KEEP,
    COMBO_STEP,
    COUNTER_BONUS,
    COUNTER_SECONDS,
    CRITICAL,
    CRITICAL_BONUS,
    CombatMove,
    CombatStance,
    DEFEATED,
    DODGE,
    EVADED,
    FALL,
    FLINCH,
    FREE,
    Fighter,
    FighterParameters,
    GUARD_BREAK,
    HEAVY,
    HIGH_STANCE,
    HIT,
    IGNORED,
    KI_BREAK,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    LOW_STANCE,
    MID_STANCE,
    StrikeOutcome,
    PARRIED,
    PERFECT_ARTE,
    PERFECT_DODGE,
    PULSE_LATE,
    RISING_EDGE,
    STAGGER,
    Struck,
    TEMPEST,
    Blow,
    combo_bonus,
    faces,
    is_arte,
    is_attack,
    landed_blow,
    move_data,
    move_name,
    next_light,
    outcome_word,
    reaches,
    stance_cost,
    stance_guard,
    stance_pace,
    stance_power,
    stance_step,
    styled,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
    Velocity,
)


def _fighter() raises -> Fighter:
    """Return a fighter with the player's strength."""
    return Fighter(FighterParameters())


def _run(mut fighter: Fighter, seconds: Float32) raises:
    """Move a fighter on by some time, in steps of a 120th of a second."""
    var steps = Int(seconds * 120 + 0.5)
    for _ in range(steps):
        fighter.update(Duration(Float32(1) / 120, SECOND))


def _step(mut fighter: Fighter, seconds: Float32) raises:
    """Move a fighter on by some time, in one step."""
    fighter.update(Duration(seconds, SECOND))


def _blow(damage: Float32, ki: Float32) -> Blow:
    """Return a blow that pushes and throws nothing."""
    return Blow(
        damage,
        ki,
        Velocity(0.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )


def test_each_kind_knows_its_values() raises:
    for value in [-1, 11]:
        assert_false(CombatMove(value).is_valid())
    for value in [0, 10]:
        assert_true(CombatMove(value).is_valid())
    for value in [-1, 3]:
        assert_false(CombatStance(value).is_valid())
    for value in [0, 2]:
        assert_true(CombatStance(value).is_valid())
    for value in [-1, 11]:
        assert_false(StrikeOutcome(value).is_valid())
    for value in [0, 10]:
        assert_true(StrikeOutcome(value).is_valid())


def test_moves_and_outcomes_have_names_for_the_display() raises:
    assert_equal(move_name(FREE), "FREE")
    assert_equal(move_name(LIGHT_TWO), "LIGHT 2")
    assert_equal(move_name(RISING_EDGE), "RISING EDGE")
    assert_equal(move_name(FALL), "FALL")
    with assert_raises(contains="eleven"):
        _ = move_name(CombatMove(11))
    assert_equal(outcome_word(PERFECT_DODGE), "PERFECT DODGE")
    assert_equal(outcome_word(PARRIED), "PARRY")
    assert_equal(outcome_word(GUARD_BREAK), "GUARD BREAK")
    assert_equal(outcome_word(KI_BREAK), "BREAK")
    assert_equal(outcome_word(HIT), "")
    assert_equal(outcome_word(FINISHED), "FINISHER")
    with assert_raises(contains="eleven"):
        _ = outcome_word(StrikeOutcome(-1))


def test_moves_are_sorted_into_attacks_artes_and_styles() raises:
    assert_false(is_attack(FREE))
    assert_true(is_attack(LIGHT_ONE))
    assert_true(is_attack(TEMPEST))
    assert_false(is_attack(DODGE))
    assert_true(is_arte(RISING_EDGE))
    assert_true(is_arte(TEMPEST))
    assert_false(is_arte(LIGHT_ONE))
    assert_false(styled(FREE))
    assert_true(styled(LIGHT_ONE))
    assert_true(styled(HEAVY))
    assert_false(styled(RISING_EDGE))
    assert_false(landed_blow(PARRIED))
    assert_true(landed_blow(HIT))
    assert_true(landed_blow(DEFEATED))
    assert_true(next_light(FREE) == LIGHT_ONE)
    assert_true(next_light(LIGHT_ONE) == LIGHT_TWO)
    assert_true(next_light(LIGHT_TWO) == LIGHT_THREE)
    assert_true(next_light(LIGHT_THREE) == LIGHT_ONE)


def test_each_move_has_its_times_and_its_strength() raises:
    var light = move_data(LIGHT_ONE)
    assert_almost_equal(light.startup.to(SECOND), 0.14, atol=1e-6)
    assert_almost_equal(light.reach.to(METER), 2, atol=1e-6)
    assert_almost_equal(light.arc.to(DEGREE), 120, atol=1e-4)
    assert_almost_equal(light.damage, 30, atol=1e-6)
    assert_equal(light.hits, 1)
    assert_almost_equal(move_data(LIGHT_TWO).damage, 33, atol=1e-6)
    assert_almost_equal(move_data(LIGHT_THREE).ki_cost, 12, atol=1e-6)
    assert_almost_equal(move_data(HEAVY).ki_damage, 30, atol=1e-6)
    var rising = move_data(RISING_EDGE)
    assert_almost_equal(rising.arte_cost, 2, atol=1e-6)
    assert_almost_equal(rising.launch.to(METER_PER_SECOND), 6.5, atol=1e-6)
    var tempest = move_data(TEMPEST)
    assert_equal(tempest.hits, 4)
    assert_almost_equal(tempest.arc.to(DEGREE), 360, atol=1e-4)
    var dodge = move_data(DODGE)
    assert_almost_equal(dodge.lunge.to(METER), 3.2, atol=1e-6)
    assert_almost_equal(dodge.ki_cost, 14, atol=1e-6)
    assert_equal(dodge.hits, 0)
    assert_almost_equal(move_data(FLINCH).recovery.to(SECOND), 0.4, atol=1e-6)
    assert_almost_equal(move_data(STAGGER).recovery.to(SECOND), 1.6, atol=1e-6)
    assert_almost_equal(move_data(FALL).recovery.to(SECOND), 2, atol=1e-6)
    assert_almost_equal(move_data(FREE).recovery.to(SECOND), 0, atol=1e-6)
    with assert_raises(contains="eleven"):
        _ = move_data(CombatMove(11))


def test_each_stance_changes_strength_pace_cost_guard_and_step() raises:
    assert_almost_equal(stance_power(HIGH_STANCE), 1.3, atol=1e-6)
    assert_almost_equal(stance_power(MID_STANCE), 1, atol=1e-6)
    assert_almost_equal(stance_power(LOW_STANCE), 0.75, atol=1e-6)
    assert_almost_equal(stance_pace(HIGH_STANCE), 1.2, atol=1e-6)
    assert_almost_equal(stance_pace(MID_STANCE), 1, atol=1e-6)
    assert_almost_equal(stance_pace(LOW_STANCE), 0.8, atol=1e-6)
    assert_almost_equal(stance_cost(HIGH_STANCE), 1.3, atol=1e-6)
    assert_almost_equal(stance_cost(MID_STANCE), 1, atol=1e-6)
    assert_almost_equal(stance_cost(LOW_STANCE), 0.7, atol=1e-6)
    assert_almost_equal(stance_guard(HIGH_STANCE), 1.2, atol=1e-6)
    assert_almost_equal(stance_guard(MID_STANCE), 0.75, atol=1e-6)
    assert_almost_equal(stance_guard(LOW_STANCE), 1, atol=1e-6)
    assert_almost_equal(stance_step(HIGH_STANCE), 0.9, atol=1e-6)
    assert_almost_equal(stance_step(MID_STANCE), 1, atol=1e-6)
    assert_almost_equal(stance_step(LOW_STANCE), 1.15, atol=1e-6)


def test_a_combo_adds_damage_up_to_its_cap() raises:
    assert_almost_equal(combo_bonus(0), 1, atol=1e-6)
    assert_almost_equal(combo_bonus(5), 1 + 5 * COMBO_STEP, atol=1e-6)
    assert_almost_equal(combo_bonus(100), 1.5, atol=1e-6)
    assert_almost_equal(combo_bonus(-3), 1, atol=1e-6)


def test_a_swing_reaches_what_stands_in_its_arc() raises:
    var at = Vector3(0, 0, 0)
    # Heading 0 faces -z.
    var ahead = Angle(0.0, DEGREE)
    var wide = Angle(90.0, DEGREE)
    assert_true(faces(at, ahead, wide, at))
    assert_true(faces(at, ahead, wide, Vector3(0, 0, -2)))
    assert_true(faces(at, ahead, wide, Vector3(-0.9, 0, -1)))
    assert_false(faces(at, ahead, wide, Vector3(-2, 0, -1)))
    assert_false(faces(at, ahead, wide, Vector3(0, 0, 2)))
    # Behind, across the wrap of the yaw.
    assert_true(faces(at, Angle(179.0, DEGREE), wide, Vector3(0.1, 0, 2)))
    var reach = Length(2.0, METER)
    var radius = Length(0.3, METER)
    assert_true(reaches(at, ahead, reach, wide, Vector3(0, 0, -2.2), radius))
    # Too far.
    assert_false(reaches(at, ahead, reach, wide, Vector3(0, 0, -2.4), radius))
    # Too high above.
    assert_false(reaches(at, ahead, reach, wide, Vector3(0, 2, -1), radius))
    # Behind.
    assert_false(reaches(at, ahead, reach, wide, Vector3(0, 0, 1.5), radius))
    # Its width brings a target at the arc's edge into it.
    var edge = Vector3(-1.1, 0, -1)
    assert_false(faces(at, ahead, wide, edge))
    assert_true(reaches(at, ahead, reach, wide, edge, radius))


def test_a_fighter_refuses_parameters_that_cannot_fight() raises:
    FighterParameters().check()
    var p = FighterParameters()
    p.health = 0
    with assert_raises(contains="above zero"):
        p.check()
    p = FighterParameters()
    p.might = 2.0e6
    with assert_raises(contains="above zero"):
        p.check()
    p = FighterParameters()
    p.ki_rate = Frequency(-1.0, PER_SECOND)
    with assert_raises(contains="rates"):
        p.check()
    p = FighterParameters()
    p.ki_delay = Duration(-1.0, SECOND)
    with assert_raises(contains="delay"):
        p.check()
    p = FighterParameters()
    p.guard_arc = Angle(400.0, DEGREE)
    with assert_raises(contains="guard"):
        _ = Fighter(p)
    p = FighterParameters()
    p.parry = Duration(-1.0, SECOND)
    with assert_raises(contains="parry"):
        p.check()


def test_three_light_attacks_chain_and_spend_ki() raises:
    var f = _fighter()
    assert_true(f.free())
    assert_true(f.press_light())
    assert_true(f.move == LIGHT_ONE)
    assert_false(f.free())
    assert_almost_equal(f.ki, 91, atol=1e-4)
    assert_almost_equal(f.length(), 0.5, atol=1e-5)
    assert_almost_equal(f.active_end(), 0.24, atol=1e-5)
    assert_almost_equal(f.chain_point(), 0.318, atol=1e-5)
    # A press during the move waits for the chain point.
    assert_true(f.press_light())
    assert_true(f.queued == LIGHT_TWO)
    _step(f, 0.3)
    assert_true(f.move == LIGHT_ONE)
    _step(f, 0.02)
    assert_true(f.move == LIGHT_TWO)
    assert_almost_equal(f.ki, 82, atol=1e-4)
    _ = f.press_light()
    _run(f, 0.4)
    assert_true(f.move == LIGHT_THREE)
    # After the third, the chain begins again.
    _ = f.press_light()
    assert_true(f.queued == LIGHT_ONE)
    _run(f, 0.6)
    assert_true(f.move == LIGHT_ONE)
    # A move with nothing waiting ends, and the fighter is free.
    _run(f, 0.6)
    assert_true(f.free())


def test_a_stance_changes_the_pace_the_ki_and_the_blow() raises:
    var f = _fighter()
    with assert_raises(contains="stance"):
        _ = f.set_stance(CombatStance(3))
    assert_false(f.set_stance(MID_STANCE))
    assert_true(f.set_stance(HIGH_STANCE))
    assert_true(f.request(HEAVY))
    # A stance does not change during a move.
    assert_false(f.set_stance(LOW_STANCE))
    assert_almost_equal(f.ki, 100 - 22 * 1.3, atol=1e-4)
    assert_almost_equal(f.length(), 1.09 * 1.2, atol=1e-5)
    assert_almost_equal(f.ki_price(DODGE), 14 * 1.3, atol=1e-4)
    # An arte costs no ki in any stance, and the stance does not slow it.
    assert_almost_equal(f.ki_price(RISING_EDGE), 0, atol=1e-6)
    _run(f, 0.5)
    var blow = f.connect(0)
    assert_true(blow)
    assert_almost_equal(blow.value().damage, 90 * 1.3, atol=1e-3)
    assert_almost_equal(blow.value().ki_damage, 30 * 1.3, atol=1e-3)
    _run(f, 1.0)
    assert_true(f.free())
    assert_true(f.set_stance(LOW_STANCE))
    _ = f.request(TEMPEST)
    assert_almost_equal(f.pace, 1, atol=1e-6)


def test_a_swing_strikes_each_target_once_a_hit() raises:
    var f = _fighter()
    assert_false(f.swing())
    _ = f.press_light()
    _step(f, 0.1)
    # Still winding up.
    assert_false(f.swing())
    assert_false(f.connect(1))
    _step(f, 0.05)
    var swing = f.swing()
    assert_true(swing)
    assert_almost_equal(swing.value().reach.to(METER), 2, atol=1e-6)
    assert_equal(swing.value().slice, 0)
    var blow = f.connect(1)
    assert_true(blow)
    assert_almost_equal(blow.value().damage, 30, atol=1e-4)
    assert_almost_equal(
        blow.value().knockback.to(METER_PER_SECOND), 1.5, atol=1e-6
    )
    # The same target is struck once; another is struck too.
    assert_false(f.connect(1))
    assert_true(f.connect(2))
    _step(f, 0.2)
    # The update reached the active part, so the swing still strikes.
    assert_true(f.swing())
    _step(f, 0.01)
    # The active part is over.
    assert_false(f.swing())
    # A tempest strikes the same target four times, once each hit.
    var t = _fighter()
    assert_true(t.request(TEMPEST))
    assert_almost_equal(t.arte, 2, atol=1e-5)
    var hits = 0
    for _ in range(120):
        t.update(Duration(Float32(1) / 120, SECOND))
        if t.connect(7):
            hits += 1
    assert_equal(hits, 4)
    # A slow frame that passes over the whole active part still strikes.
    var slow = _fighter()
    _ = slow.press_light()
    _step(slow, 0.4)
    assert_true(slow.connect(3))


def test_a_blow_grows_with_might_combo_and_counter() raises:
    var p = FighterParameters()
    p.might = 0.5
    var f = Fighter(p)
    f.combo = 10
    _ = f.press_light()
    _step(f, 0.15)
    var blow = f.connect(0)
    assert_almost_equal(
        blow.value().damage, 30 * 0.5 * (1 + 10 * COMBO_STEP), atol=1e-3
    )
    assert_almost_equal(blow.value().ki_damage, 4, atol=1e-4)
    var c = _fighter()
    c.counter = 1
    _ = c.press_light()
    assert_true(c.countering)
    assert_almost_equal(c.counter, 0, atol=1e-6)
    _step(c, 0.15)
    assert_almost_equal(
        c.connect(0).value().damage, 30 * COUNTER_BONUS, atol=1e-3
    )


def test_a_dodge_evades_and_a_late_one_is_perfect() raises:
    var f = _fighter()
    assert_true(f.request(DODGE))
    assert_almost_equal(f.ki, 86, atol=1e-4)
    # Not yet safe at its very start.
    assert_false(f.invulnerable())
    _step(f, 0.05)
    assert_true(f.invulnerable())
    var arte = f.arte
    var struck = f.receive(_blow(30, 10), True)
    assert_true(struck.outcome == PERFECT_DODGE)
    assert_almost_equal(f.ki, 100, atol=1e-4)
    assert_almost_equal(f.arte, min(Float32(5), arte + PERFECT_ARTE), atol=1e-4)
    assert_almost_equal(f.counter, COUNTER_SECONDS, atol=1e-6)
    # A dodge is perfect only once.
    assert_true(f.receive(_blow(30, 10), True).outcome == EVADED)
    var late = _fighter()
    _ = late.request(DODGE)
    _step(late, 0.25)
    assert_true(late.receive(_blow(30, 10), True).outcome == EVADED)
    _step(late, 0.1)
    assert_false(late.invulnerable())
    assert_true(late.receive(_blow(30, 10), True).outcome == HIT)
    # A free fighter is not safe.
    assert_false(_fighter().invulnerable())


def test_a_dodge_carries_the_fighter_and_cuts_an_attack_short() raises:
    var f = _fighter()
    assert_almost_equal(f.drive().to(METER_PER_SECOND), 0, atol=1e-6)
    _ = f.press_light()
    assert_almost_equal(f.drive().to(METER_PER_SECOND), 0.35 / 0.24, atol=1e-4)
    # A dodge in the start-up waits.
    assert_true(f.request(DODGE))
    assert_true(f.queued == DODGE)
    _step(f, 0.25)
    assert_almost_equal(f.drive().to(METER_PER_SECOND), 0, atol=1e-6)
    # A dodge in the recovery starts at once.
    assert_true(f.request(DODGE))
    assert_true(f.move == DODGE)
    assert_almost_equal(f.drive().to(METER_PER_SECOND), 10, atol=1e-4)
    # A dodge asked for during a dodge waits.
    assert_true(f.request(DODGE))
    assert_true(f.queued == DODGE)
    var low = _fighter()
    _ = low.set_stance(LOW_STANCE)
    _ = low.request(DODGE)
    assert_almost_equal(low.drive().to(METER_PER_SECOND), 11.5, atol=1e-3)
    assert_almost_equal(low.ki, 100 - 14 * 0.7, atol=1e-4)
    # A light attack asked for in a recovery waits for the chain point.
    var g = _fighter()
    _ = g.press_light()
    _step(g, 0.25)
    assert_true(g.press_light())
    assert_true(g.move == LIGHT_ONE)
    assert_true(g.queued == LIGHT_TWO)


def test_only_attacks_and_dodges_can_be_asked_for() raises:
    var f = _fighter()
    with assert_raises(contains="attack or a dodge"):
        _ = f.request(FLINCH)
    _ = f.receive(_blow(10, 5), False)
    assert_true(f.move == FLINCH)
    # A reeling fighter cannot move.
    assert_false(f.press_light())
    assert_false(f.request(DODGE))
    _run(f, 0.5)
    assert_true(f.free())


def test_a_guard_blocks_from_the_front_and_parries_when_fresh() raises:
    var f = _fighter()
    f.hold_guard(True)
    assert_true(f.guarding)
    # A fresh guard parries.
    var parried = f.receive(_blow(30, 12), True)
    assert_true(parried.outcome == PARRIED)
    assert_almost_equal(parried.ki, 12, atol=1e-6)
    assert_almost_equal(f.ki, 100, atol=1e-6)
    _step(f, 0.2)
    # Holding on does not raise it afresh.
    f.hold_guard(True)
    var blocked = f.receive(_blow(30, 12), True)
    assert_true(blocked.outcome == BLOCKED)
    assert_almost_equal(f.ki, 100 - 12 * 0.75, atol=1e-4)
    assert_almost_equal(f.health, 500, atol=1e-6)
    # From behind, the guard does not help.
    assert_true(f.receive(_blow(30, 12), False).outcome == HIT)
    assert_false(f.guarding)
    # A guard cannot be raised during a move.
    f.hold_guard(True)
    assert_false(f.guarding)
    _run(f, 0.5)
    f.hold_guard(True)
    assert_true(f.guarding)
    f.hold_guard(False)
    assert_false(f.guarding)
    # A fighter without a parry only blocks.
    var p = FighterParameters()
    p.parry = Duration(0.0, SECOND)
    var blocker = Fighter(p)
    blocker.hold_guard(True)
    assert_true(blocker.receive(_blow(30, 12), True).outcome == BLOCKED)
    # A guard whose ki runs out breaks.
    var g = _fighter()
    g.hold_guard(True)
    _step(g, 0.2)
    g.ki = 5
    var broken = g.receive(_blow(30, 12), True)
    assert_true(broken.outcome == GUARD_BREAK)
    assert_true(g.move == STAGGER)
    assert_almost_equal(g.ki, 0, atol=1e-6)


def test_a_parried_attacker_reels_or_staggers() raises:
    var f = _fighter()
    f.landed(Struck(PARRIED, 0, 12))
    assert_true(f.move == FLINCH)
    assert_almost_equal(f.ki, 88, atol=1e-4)
    var g = _fighter()
    g.ki = 5
    g.landed(Struck(PARRIED, 0, 12))
    assert_true(g.move == STAGGER)
    assert_almost_equal(g.ki, 0, atol=1e-6)
    # A blow that lands adds to the combo and fills the arte gauge.
    var h = _fighter()
    h.arte = 1
    h.landed(Struck(HIT, 30, 8))
    assert_equal(h.combo, 1)
    assert_almost_equal(h.arte, 1 + ARTE_PER_HIT, atol=1e-6)
    h.landed(Struck(BLOCKED, 0, 8))
    assert_equal(h.combo, 1)


def test_blows_wound_break_ki_and_defeat() raises:
    var f = _fighter()
    f.combo = 4
    var hit = f.receive(_blow(40, 20), False)
    assert_true(hit.outcome == HIT)
    assert_true(f.move == FLINCH)
    assert_equal(f.combo, 0)
    assert_almost_equal(f.health, 460, atol=1e-4)
    assert_almost_equal(f.ki, 80, atol=1e-4)
    # A blow that takes the last ki breaks it: the fighter staggers.
    f.ki = 10
    var broke = f.receive(_blow(40, 20), False)
    assert_true(broke.outcome == KI_BREAK)
    assert_true(f.move == STAGGER)
    # A blow on a staggered fighter is critical.
    var crit = f.receive(_blow(40, 20), False)
    assert_true(crit.outcome == CRITICAL)
    assert_almost_equal(crit.damage, 40 * CRITICAL_BONUS, atol=1e-4)
    assert_true(f.move == STAGGER)
    # The last health fells it, and a fallen fighter takes nothing more.
    var fell = f.receive(_blow(1000, 20), False)
    assert_true(fell.outcome == DEFEATED)
    assert_true(f.defeated())
    assert_almost_equal(f.health, 0, atol=1e-6)
    assert_true(f.receive(_blow(10, 1), False).outcome == IGNORED)
    # A fallen fighter stays down.
    _run(f, 3)
    assert_true(f.defeated())
    f.revive()
    assert_true(f.free())
    assert_almost_equal(f.health, 500, atol=1e-6)


def test_heavy_attacks_and_tempests_have_armor() raises:
    var f = _fighter()
    _ = f.request(HEAVY)
    assert_true(f.armored())
    assert_true(f.receive(_blow(10, 5), False).outcome == HIT)
    assert_true(f.move == HEAVY)
    _run(f, 0.6)
    assert_false(f.armored())
    var t = _fighter()
    _ = t.request(TEMPEST)
    assert_true(t.armored())
    var l = _fighter()
    _ = l.press_light()
    assert_false(l.armored())


def test_ki_comes_back_and_a_winded_fighter_staggers() raises:
    var f = _fighter()
    f.ki = 50
    f.rest = 0
    _step(f, 0.5)
    assert_almost_equal(f.ki, 50, atol=1e-6)
    _step(f, 0.5)
    assert_almost_equal(f.ki, 66, atol=1e-4)
    f.hold_guard(True)
    _step(f, 0.5)
    assert_almost_equal(f.ki, 74, atol=1e-4)
    _run(f, 5)
    assert_almost_equal(f.ki, 100, atol=1e-6)
    # Spending the last ki winds the fighter: it staggers after the move.
    f.hold_guard(False)
    f.ki = 5
    assert_true(f.press_light())
    assert_true(f.winded)
    assert_almost_equal(f.ki, 0, atol=1e-6)
    # With no ki, no costly move starts.
    _ = f.request(HEAVY)
    _run(f, 0.55)
    assert_true(f.move == STAGGER)
    assert_false(f.winded)
    var g = _fighter()
    g.ki = 0
    assert_false(g.press_light())
    # An arte costs no ki, and starts.
    assert_true(g.request(RISING_EDGE))
    # Without the points, an arte does not start.
    var h = _fighter()
    h.arte = 1
    assert_false(h.request(TEMPEST))
    assert_true(h.free())


def test_a_ki_pulse_gets_back_the_swings_ki() raises:
    var f = _fighter()
    assert_almost_equal(f.pulse(), 0, atol=1e-6)
    _ = f.request(HEAVY)
    _step(f, 0.6)
    assert_almost_equal(f.pulse_age, 0.06, atol=1e-5)
    assert_almost_equal(f.pulse(), 22, atol=1e-4)
    assert_almost_equal(f.ki, 100, atol=1e-4)
    # A pulse is made once.
    assert_almost_equal(f.pulse(), 0, atol=1e-6)
    # A late pulse gets back part of it.
    var late = _fighter()
    _ = late.request(HEAVY)
    _step(late, 0.55)
    _step(late, 0.3)
    assert_almost_equal(late.pulse(), 22 * PULSE_LATE, atol=1e-4)
    # Too late, there is none.
    var gone = _fighter()
    _ = gone.request(HEAVY)
    _step(gone, 0.55)
    _step(gone, 0.5)
    assert_almost_equal(gone.pulse_age, -1, atol=1e-6)
    # A pulse catches a winded fighter's breath.
    var w = _fighter()
    w.ki = 5
    _ = w.press_light()
    assert_true(w.winded)
    _step(w, 0.25)
    assert_true(w.pulse() > 0)
    assert_false(w.winded)
    _run(w, 0.4)
    assert_true(w.free())
    # An arte spends no ki, so its pulse gets none back and leaves the
    # breath as it was.
    var a = _fighter()
    _ = a.request(RISING_EDGE)
    a.winded = True
    _step(a, 0.4)
    assert_almost_equal(a.pulse(), 0, atol=1e-6)
    assert_true(a.winded)


def test_a_frame_moves_the_clocks_on() raises:
    var f = _fighter()
    with assert_raises(contains="frame"):
        _step(f, -1)
    with assert_raises(contains="frame"):
        _step(f, 2.0e9)
    f.combo = 3
    f.combo_age = 0
    f.counter = 1
    f.arte = 0
    _step(f, 1)
    assert_equal(f.combo, 3)
    assert_almost_equal(f.counter, 0, atol=1e-6)
    assert_almost_equal(f.arte, 0.5, atol=1e-5)
    _step(f, COMBO_KEEP)
    assert_equal(f.combo, 0)
    # A dodge's clock runs, and it makes no pulse.
    _ = f.request(DODGE)
    _step(f, 0.4)
    assert_almost_equal(f.pulse_age, -1, atol=1e-6)
    _step(f, 0.2)
    assert_true(f.free())


def test_over_limit_fills_and_unleashes() raises:
    var f = _fighter()
    # Each landed blow, break, parry and perfect dodge fills the gauge.
    f.landed(Struck(HIT, 30, 8))
    assert_almost_equal(f.limit, LIMIT_PER_HIT, atol=1e-6)
    f.landed(Struck(KI_BREAK, 30, 8))
    assert_almost_equal(f.limit, 2 * LIMIT_PER_HIT + LIMIT_PER_BREAK, atol=1e-5)
    f.landed(Struck(GUARD_BREAK, 0, 8))
    assert_almost_equal(
        f.limit, 2 * LIMIT_PER_HIT + 2 * LIMIT_PER_BREAK, atol=1e-5
    )
    f.hold_guard(True)
    _ = f.receive(_blow(30, 8), True)
    assert_almost_equal(
        f.limit,
        2 * LIMIT_PER_HIT + 2 * LIMIT_PER_BREAK + LIMIT_PER_PARRY,
        atol=1e-5,
    )
    f.hold_guard(False)
    var dodger = _fighter()
    _ = dodger.request(DODGE)
    _step(dodger, 0.05)
    _ = dodger.receive(_blow(30, 8), True)
    assert_almost_equal(dodger.limit, LIMIT_PER_PERFECT, atol=1e-5)
    # Full, the fighter goes Over Limit: a full arte gauge, armor, free
    # artes and stronger blows.
    f.arte = 0
    f.charge(LIMIT)
    assert_almost_equal(f.limit, 0, atol=1e-6)
    assert_almost_equal(f.over, OVER_SECONDS, atol=1e-6)
    assert_almost_equal(f.arte, 5, atol=1e-6)
    assert_true(f.armored())
    # Nothing fills it while it lasts.
    f.charge(50)
    assert_almost_equal(f.limit, 0, atol=1e-6)
    f.arte = 0
    f.combo = 0
    assert_true(f.request(TEMPEST))
    assert_almost_equal(f.arte, 0, atol=1e-6)
    _step(f, 0.25)
    assert_almost_equal(f.connect(0).value().damage, 27 * OVER_BONUS, atol=1e-3)
    _run(f, 1)
    # It ends.
    _step(f, OVER_SECONDS)
    assert_almost_equal(f.over, 0, atol=1e-6)
    assert_false(f.armored())
    # A fighter of no gain never fills it.
    var p = FighterParameters()
    p.limit_gain = 0
    var dull = Fighter(p)
    dull.charge(LIMIT)
    assert_almost_equal(dull.over, 0, atol=1e-6)
    p.limit_gain = -1
    with assert_raises(contains="limit"):
        p.check()
    f.limit = 50
    f.revive()
    assert_almost_equal(f.limit, 0, atol=1e-6)


def test_a_heavy_blow_finishes_a_staggered_weakened_fighter() raises:
    var finishing = Blow(
        90,
        30,
        Velocity(5.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
        True,
    )
    var f = _fighter()
    _ = f.receive(_blow(10, 200), False)
    assert_true(f.move == STAGGER)
    f.health = 500 * FINISH_SHARE
    var finished = f.receive(finishing, False)
    assert_true(finished.outcome == FINISHED)
    assert_almost_equal(finished.damage, 500 * FINISH_SHARE, atol=1e-3)
    assert_true(f.defeated())
    assert_true(landed_blow(FINISHED))
    # Too healthy, it is only critical.
    var g = _fighter()
    _ = g.receive(_blow(10, 200), False)
    assert_true(g.receive(finishing, False).outcome == CRITICAL)
    # A light blow does not finish.
    var h = _fighter()
    _ = h.receive(_blow(10, 200), False)
    h.health = 50
    assert_true(h.receive(_blow(10, 1), False).outcome == CRITICAL)
    # Nor does a heavy one on a fighter that stands.
    var k = _fighter()
    k.health = 150
    assert_true(k.receive(finishing, False).outcome == HIT)
    # A heavy attack's blow can finish; a light attack's cannot.
    var heavy = _fighter()
    _ = heavy.request(HEAVY)
    _step(heavy, 0.45)
    assert_true(heavy.connect(0).value().finish)
    var light = _fighter()
    _ = light.press_light()
    _step(light, 0.15)
    assert_false(light.connect(0).value().finish)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
