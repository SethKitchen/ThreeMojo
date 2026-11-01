# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The basics of a fight on flat ground: presses, frames and blows, a
dummy, the lock, and a bandit's attacks against a guard, a parry and
a dodge.

The player stands at the middle and faces -z. The dummy stands 1.5
meters before them, and the bandit 6 meters before them: see
`tests/_village_arena.mojo`."""

from tests._village_arena import (
    Arena,
    arena_parameters,
    flat_ground,
    holds_text,
    popup_texts,
    stand_piercing,
    stand_swinging,
)
from extensions.village.battle import (
    BLOCK_PUSH,
    CALM_SECONDS,
    JUGGLE,
    SLOW_SECONDS,
    BattleParameters,
    pressed,
    push_of,
    throw_up,
)
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    no_input,
)
from extensions.village.combat import (
    BLOCKED,
    PIERCE,
    STAGGER,
    DODGE,
    EVADED,
    FLINCH,
    GUARD_BREAK,
    HIT,
    LIGHT_ONE,
    Blow,
    Struck,
)
from extensions.village.foes import Post, POSTED
from extensions.village.skills import PRACTICE_EXPERIENCE
from extensions.village.styles import SWORD
from math.vector3 import Vector3
from std.math import cos, sin
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
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Velocity,
)


def test_a_press_is_a_button_held_now_and_not_before() raises:
    var all = MoveInput(
        0.5,
        0.25,
        0,
        0,
        True,
        True,
        True,
        light=True,
        heavy=True,
        rising=True,
        whirlwind=True,
        ground_wave=True,
        dodge=True,
        guard=True,
        lock=True,
        high=True,
        middle=True,
        low=True,
        heal=True,
    )
    var none = no_input()
    var fresh = pressed(all, none)
    assert_almost_equal(fresh.forward, 0.5, atol=1e-6)
    for button in [
        fresh.run,
        fresh.jump,
        fresh.use,
        fresh.light,
        fresh.heavy,
        fresh.rising,
        fresh.whirlwind,
        fresh.ground_wave,
        fresh.dodge,
        fresh.guard,
        fresh.lock,
        fresh.high,
        fresh.middle,
        fresh.low,
        fresh.heal,
    ]:
        assert_true(button)
    for held in [pressed(all, all), pressed(none, all)]:
        for button in [
            held.run,
            held.jump,
            held.use,
            held.light,
            held.heavy,
            held.rising,
            held.whirlwind,
            held.ground_wave,
            held.dodge,
            held.guard,
            held.lock,
            held.high,
            held.middle,
            held.low,
            held.heal,
        ]:
            assert_false(button)


def test_a_fight_refuses_what_cannot_be_held() raises:
    BattleParameters().check()
    var p = BattleParameters()
    for k in range(17):
        p.posts.append(Post(Float32(k), 0, Angle(0.0, DEGREE)))
    with assert_raises(contains="16"):
        p.check()
    p = BattleParameters()
    for _ in range(17):
        p.bandits.append(p.bandits[0].copy())
    with assert_raises(contains="16"):
        p.check()
    p = BattleParameters()
    p.bandits[1].fighter.health = 0
    with assert_raises(contains="health"):
        p.check()
    p = BattleParameters()
    p.dens[0].fighter.health = 0
    with assert_raises(contains="health"):
        p.check()
    p = BattleParameters()
    p.allies[0].fighter.health = 0
    with assert_raises(contains="health"):
        p.check()
    p = BattleParameters()
    p.allies.append(p.allies[0].copy())
    with assert_raises(contains="one companion"):
        p.check()
    for count in [0, 9]:
        p = BattleParameters()
        p.dens[0].count = count
        with assert_raises(contains="den"):
            p.check()
    p = BattleParameters()
    for _ in range(4):
        p.dens.append(p.dens[0].copy())
    with assert_raises(contains="4 dens"):
        p.check()
    for phases in [0, 33]:
        p = BattleParameters()
        p.phases = phases
        with assert_raises(contains="poses"):
            p.check()
    for coarseness in [Float64(0.5), Float64(9)]:
        p = BattleParameters()
        p.coarseness = coarseness
        with assert_raises(contains="coarseness"):
            p.check()
    p = BattleParameters()
    p.revive = Duration(-1.0, SECOND)
    with assert_raises(contains="revive"):
        p.check()
    p = BattleParameters()
    p.respawn = Duration(2.0e4, SECOND)
    with assert_raises(contains="revive"):
        p.check()


def test_a_frame_must_have_a_time() raises:
    var arena = Arena(arena_parameters(0, 0))
    with assert_raises(contains="frame"):
        arena.tick(no_input(), -1)
    with assert_raises(contains="frame"):
        arena.tick(no_input(), 2.0e9)
    # With nobody to fight, there is nothing to lock on to.
    assert_equal(
        arena.battle.pick_lock(Vector3(0, 0, 0), Angle(0.0, DEGREE)), -1
    )


def test_a_blow_pushes_and_throws() raises:
    var way = Vector3(1, 0, 0)
    var blow = Blow(
        30,
        10,
        Velocity(4.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )
    assert_almost_equal(push_of(Struck(HIT, 30, 10), blow, way).x, 4, atol=1e-6)
    assert_almost_equal(
        push_of(Struck(BLOCKED, 0, 10), blow, way).x, 4 * BLOCK_PUSH, atol=1e-6
    )
    assert_almost_equal(
        push_of(Struck(GUARD_BREAK, 0, 10), blow, way).x,
        4 * BLOCK_PUSH,
        atol=1e-6,
    )
    assert_almost_equal(
        push_of(Struck(EVADED, 0, 0), blow, way).x, 0, atol=1e-6
    )
    var ground = flat_ground()
    var walker = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), ground
    )
    # A blow that does not land throws nothing; one that lands on a fighter
    # on the ground throws nothing either, unless it launches.
    throw_up(walker, Struck(BLOCKED, 0, 0), blow)
    throw_up(walker, Struck(HIT, 30, 10), blow)
    assert_true(walker.grounded)
    var launch = Blow(
        30,
        10,
        Velocity(1.0, METER_PER_SECOND),
        Velocity(6.5, METER_PER_SECOND),
    )
    throw_up(walker, Struck(HIT, 30, 10), launch)
    assert_false(walker.grounded)
    assert_almost_equal(walker.velocity.y, 6.5, atol=1e-6)
    # In the air, a blow keeps it up.
    walker.velocity.y = -2
    throw_up(walker, Struck(HIT, 30, 10), blow)
    assert_almost_equal(walker.velocity.y, JUGGLE, atol=1e-6)


def test_the_player_cuts_a_dummy() raises:
    # The bandit stands too far to notice, or to reach.
    var arena = Arena(arena_parameters(1, 1, 15))
    assert_equal(arena.battle.trained[SWORD.value], 0)
    assert_equal(len(arena.battle.dummies), 1)
    assert_equal(arena.battle.targets(), 2)
    assert_true(arena.battle.standing(1))
    assert_almost_equal(arena.battle.target_at(1).z, -1.5, atol=1e-6)
    assert_equal(len(arena.battle.movers()), 2)
    assert_almost_equal(arena.battle.obstacles()[1].radius, 0.35, atol=1e-6)
    assert_false(arena.battle.drawn)
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    assert_true(arena.battle.fighter.move == LIGHT_ONE)
    assert_true(arena.battle.drawn)
    arena.run(0.3)
    assert_equal(arena.battle.fighter.combo, 1)
    assert_true(holds_text(popup_texts(arena.battle), "30"))
    assert_equal(arena.battle.trained[SWORD.value], PRACTICE_EXPERIENCE)
    assert_almost_equal(arena.battle.foes[0].fighter.health, 300, atol=1e-6)
    assert_false(arena.battle.limited)
    # The dummy rocks, and keeps its health.
    var rocked = arena.battle.dummies[0].dummy.spin.length()
    assert_true(rocked > 0)
    assert_almost_equal(
        arena.battle.dummies[0].fighter.health,
        arena.battle.dummies[0].fighter.parameters.health,
        atol=1e-3,
    )
    # The numbers rise and go.
    arena.run(1.2)
    assert_equal(len(arena.battle.popups), 0)
    # With nothing to fight, the sword is sheathed.
    arena.run(CALM_SECONDS + 0.5)
    assert_false(arena.battle.drawn)


def test_the_lock_turns_the_camera_and_faces_the_player() raises:
    # The bandit stands too far to notice the player.
    var arena = Arena(arena_parameters(1, 1, 15))
    arena.view.yaw = Angle(90.0, DEGREE)
    # The dummy lies nearer the middle of the view than the bandit.
    assert_equal(
        arena.battle.pick_lock(Vector3(0, 0, 0), Angle(0.0, DEGREE)), 1
    )
    var lock = no_input()
    lock.lock = True
    arena.press(lock)
    assert_true(arena.battle.lock >= 0)
    arena.run(1)
    assert_true(abs(arena.view.yaw.to(DEGREE)) < 30)
    # Walking right, the locked player still faces the target.
    var right = no_input()
    right.right = 1
    arena.run(0.5, right)
    var toward = (
        arena.battle.target_at(arena.battle.lock) - arena.player.position
    )
    var h = arena.player.heading.to(RADIAN)
    var ahead = Vector3(-sin(h), 0, -cos(h))
    assert_true((toward.x * ahead.x + toward.z * ahead.z) > 0)
    # An attack turns to the locked target.
    assert_true(
        arena.battle.aim(
            arena.player.position, arena.player.heading, Vector3(0, 0, 0)
        )
    )
    arena.press(lock)
    assert_equal(arena.battle.lock, -1)
    # Near the bandit, it is the best, and the dummy after it is worse.
    assert_equal(
        arena.battle.pick_lock(Vector3(0, 0, -14), Angle(0.0, DEGREE)), 0
    )
    # A target behind the player is not aimed at.
    assert_false(
        arena.battle.aim(
            Vector3(0, 0, 0), Angle(180.0, DEGREE), Vector3(0, 0, 0)
        )
    )
    # Nothing in range: nothing to lock on to.
    assert_equal(
        arena.battle.pick_lock(Vector3(100, 0, 100), Angle(0.0, DEGREE)), -1
    )
    # Aim: the nearest before the player, else the stick, else nothing.
    var aim = arena.battle.aim(
        Vector3(0, 0, 0), Angle(0.0, DEGREE), Vector3(0, 0, 0)
    )
    assert_true(aim)
    var stick = arena.battle.aim(
        Vector3(50, 0, 50), Angle(0.0, DEGREE), Vector3(1, 0, 0)
    )
    assert_almost_equal(stick.value().to(DEGREE), -90, atol=1e-3)
    assert_false(
        arena.battle.aim(
            Vector3(50, 0, 50), Angle(0.0, DEGREE), Vector3(0, 0, 0)
        )
    )
    # A lock lets go when its target goes too far.
    arena.press(lock)
    assert_true(arena.battle.lock >= 0)
    arena.player.position = Vector3(40, 0, 40)
    arena.tick(no_input())
    assert_equal(arena.battle.lock, -1)


def test_a_bandit_comes_and_strikes_and_a_guard_blocks() raises:
    var arena = Arena(arena_parameters(1, 0))
    assert_equal(len(arena.battle.foes), 1)
    arena.run(9)
    # It noticed the player, took the token and struck.
    assert_true(arena.battle.foes[0].brain.state != POSTED)
    assert_true(arena.battle.fighter.health < 500)
    assert_true(arena.battle.drawn)
    # Locked on and guarding, the player takes its blows on stamina.
    var guard = no_input()
    guard.guard = True
    guard.lock = True
    var health = arena.battle.fighter.health
    var blocked = False
    for _ in range(200):
        arena.tick(guard)
        if holds_text(popup_texts(arena.battle), "BLOCKED"):
            blocked = True
    assert_true(blocked)
    assert_almost_equal(arena.battle.fighter.health, health, atol=1e-3)


def test_a_pierce_goes_through_a_guard_and_a_heavy_cut_counters_it() raises:
    var arena = Arena(arena_parameters(1, 0))
    stand_piercing(arena, 0.6)
    var guard = no_input()
    guard.guard = True
    for _ in range(6):
        arena.tick(guard)
    assert_true(arena.battle.fighter.health < 500)
    assert_false(holds_text(popup_texts(arena.battle), "PARRY"))
    assert_false(holds_text(popup_texts(arena.battle), "BLOCKED"))
    # A heavy cut that lands in the wind-up counters it.
    var counter = Arena(arena_parameters(1, 0))
    counter.battle.drawn = True
    stand_piercing(counter, 0.1)
    var heavy = no_input()
    heavy.heavy = True
    counter.tick(heavy)
    counter.run(0.5)
    assert_true(holds_text(popup_texts(counter.battle), "PIERCE BREAK"))
    assert_true(counter.battle.foes[0].fighter.move == STAGGER)
    assert_almost_equal(counter.battle.foes[0].fighter.stamina, 0, atol=1e-6)


def test_a_fresh_guard_parries_and_a_late_dodge_is_perfect() raises:
    var arena = Arena(arena_parameters(1, 0))
    stand_swinging(arena, 0.1)
    var guard = no_input()
    guard.guard = True
    arena.tick(guard)
    assert_true(holds_text(popup_texts(arena.battle), "PARRY"))
    assert_true(arena.battle.foes[0].fighter.move == FLINCH)
    var dodger = Arena(arena_parameters(1, 0))
    dodger.battle.drawn = True
    stand_swinging(dodger, 0.1)
    var dodge = no_input()
    dodge.dodge = True
    dodger.tick(dodge)
    assert_true(dodger.battle.fighter.move == DODGE)
    assert_true(holds_text(popup_texts(dodger.battle), "PERFECT DODGE"))
    assert_almost_equal(dodger.battle.slow, SLOW_SECONDS - 0.05, atol=1e-4)
    # The bandit moves slowly while the dodge's time lasts.
    var clock = dodger.battle.foes[0].fighter.clock
    dodger.tick(no_input())
    assert_true(dodger.battle.foes[0].fighter.clock - clock < 0.02)


def test_a_dodge_goes_the_way_of_the_stick_or_back() raises:
    var arena = Arena(arena_parameters(0, 0))
    # A sheathed sword does not dodge as the button goes down, and a long
    # hold does not roll as it comes up.
    var dodge = no_input()
    dodge.dodge = True
    arena.tick(dodge)
    assert_true(arena.battle.fighter.free())
    arena.run(0.5, dodge)
    arena.tick(no_input())
    assert_true(arena.battle.fighter.free())
    arena.battle.drawn = True
    dodge.right = 1
    arena.tick(dodge)
    assert_true(arena.battle.fighter.move == DODGE)
    arena.run(0.4)
    assert_true(arena.player.position.x > 2)
    var back = Arena(arena_parameters(0, 0))
    back.battle.drawn = True
    var plain = no_input()
    plain.dodge = True
    back.tick(plain)
    back.run(0.4)
    assert_true(back.player.position.z > 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
