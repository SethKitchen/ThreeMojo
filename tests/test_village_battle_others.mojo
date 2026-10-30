# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wolves, a raging foe, a sidestep, knife throwers, the plunge, the
ultimate, and the companion.

The player stands at the middle and faces -z. The dummy stands 1.5
meters before them, and the bandit 6 meters before them: see
`tests/_village_arena.mojo`."""

from tests._village_arena import (
    Arena,
    arena_parameters,
    holds_text,
    popup_texts,
    light_cut,
    stand_facing,
)
from extensions.village.battle import CHEST, Bolt, Knife
from extensions.village.character import no_input
from extensions.village.combat import (
    BLOCKED,
    CAST,
    FALL,
    DODGE,
    FLINCH,
    ULTIMATE,
    PLUNGE,
    RISING_EDGE,
)
from extensions.village.foes import CLOSING, CIRCLING, RETURNING
from extensions.village.skills import DEFEAT_EXPERIENCE
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import DEGREE, Angle


def test_wolves_close_in_bite_and_lie_down_when_felled() raises:
    var arena = Arena(arena_parameters(0, 0, 8, 3))
    assert_equal(len(arena.battle.foes), 3)
    assert_equal(len(arena.battle.pelts), 3)
    assert_true(arena.battle.foes[0].beast)
    assert_equal(arena.battle.node_of(1), arena.battle.pelts[1].node)
    assert_equal(len(arena.battle.movers()), 3)
    # They notice the player, close in, take turns and bite.
    arena.run(8)
    assert_true(arena.battle.fighter.health < 500)
    # A wolf felled gives no coins, but trains the sword; it lies on its
    # side, and comes back to the den.
    stand_facing(arena, 0)
    arena.battle.foes[0].fighter.move = FLINCH
    arena.battle.foes[0].fighter.health = 1
    arena.battle.fighter.revive()
    arena.battle.loot = 0
    arena.battle.trained = 0
    light_cut(arena)
    assert_true(arena.battle.foes[0].fighter.defeated())
    assert_equal(arena.battle.loot, 0)
    assert_true(arena.battle.trained >= DEFEAT_EXPERIENCE)
    var lying = arena.scene.node(arena.battle.pelts[0].node).quaternion
    assert_true(abs(lying.x) + abs(lying.z) > 0.5)
    arena.run(2.5)
    assert_true(arena.battle.foes[0].down < 0)


def test_a_foe_that_falls_below_its_rage_rages() raises:
    var arena = Arena(arena_parameters(1, 0))
    ref foe = arena.battle.foes[0]
    foe.character.position = Vector3(0, 0, -1.5)
    foe.character.heading = Angle(180.0, DEGREE)
    foe.fighter.parameters.rage = 0.5
    foe.fighter.health = 160
    var heavy = no_input()
    heavy.heavy = True
    arena.tick(heavy)
    arena.run(0.5)
    assert_true(arena.battle.foes[0].fighter.raging())
    assert_true(holds_text(popup_texts(arena.battle), "RAGE"))


def test_a_bandit_sidesteps_an_attack() raises:
    var arena = Arena(arena_parameters(1, 0))
    ref foe = arena.battle.foes[0]
    foe.character.position = Vector3(0, 0, -2)
    foe.character.heading = Angle(180.0, DEGREE)
    foe.brain.state = CIRCLING
    foe.brain.timer = 5
    # It answers every attack, and with a sidestep.
    foe.brain.wary = 100
    var light = no_input()
    light.light = True
    arena.tick(light)
    assert_true(arena.battle.foes[0].fighter.move == DODGE)
    arena.run(0.4)
    assert_true(abs(arena.battle.foes[0].character.position.x) > 1)
    # Its dodge does not slow the foes, as the player's does, even when a
    # blow reaches it at the last moment.
    assert_almost_equal(arena.battle.slow, 0, atol=1e-6)
    var late = Arena(arena_parameters(1, 0))
    ref dodger = late.battle.foes[0]
    dodger.character.position = Vector3(0, 0, -1.5)
    dodger.character.heading = Angle(180.0, DEGREE)
    _ = dodger.fighter.request(DODGE)
    dodger.fighter.clock = 0.02
    _ = late.battle.fighter.press_light()
    late.battle.fighter.clock = 0.13
    late.tick(no_input())
    assert_true(holds_text(popup_texts(late.battle), "PERFECT DODGE"))
    assert_almost_equal(late.battle.slow, 0, atol=1e-6)


def test_a_thrower_throws_knives_that_a_guard_blocks() raises:
    var arena = Arena(arena_parameters(1, 0, 8, thrower=True))
    arena.battle.foes[0].brain.state = CIRCLING
    arena.battle.foes[0].brain.timer = 0
    arena.run(1.2)
    # The knife flew to the player and struck.
    assert_almost_equal(arena.battle.fighter.health, 478, atol=1e-3)
    assert_equal(len(arena.battle.knives), 0)
    # A guard blocks the next.
    arena.battle.foes[0].brain.timer = 0
    var guard = no_input()
    guard.guard = True
    arena.run(1.2, guard)
    assert_almost_equal(arena.battle.fighter.health, 478, atol=1e-3)
    assert_true(holds_text(popup_texts(arena.battle), "BLOCKED"))
    # A knife thrown wide falls.
    var blow = arena.battle.foes[0].fighter.blow()
    var wide = Vector3(5, 1, 0)
    arena.battle.knives.append(Knife(wide, Vector3(1, 0, 0), wide, 0, blow, 0))
    arena.run(1.5, guard)
    assert_equal(len(arena.battle.knives), 0)


def test_a_heavy_attack_in_the_air_plunges() raises:
    var arena = Arena(arena_parameters(0, 1))
    var jump = no_input()
    jump.jump = True
    arena.tick(jump)
    arena.tick(no_input())
    assert_false(arena.player.grounded)
    var heavy = no_input()
    heavy.heavy = True
    arena.tick(heavy)
    assert_true(arena.battle.fighter.move == PLUNGE)
    assert_true(arena.player.velocity.y < -10 or arena.player.grounded)
    arena.run(0.5)
    assert_true(arena.player.grounded)
    assert_true(holds_text(popup_texts(arena.battle), "70"))


def test_over_limit_spends_itself_on_a_ultimate() raises:
    # Two dummies within the special's reach, and one beyond it.
    var arena = Arena(arena_parameters(0, 3))
    var both = no_input()
    both.ultimate = True
    both.rising = True
    both.whirlwind = True
    # Without a surge, its buttons make the rising edge.
    arena.press(both)
    assert_true(arena.battle.fighter.move == RISING_EDGE)
    arena.run(1.5)
    # In a surge, they make the ultimate, and the foes slow.
    arena.battle.fighter.over = 5
    var before = arena.battle.fighter.combo
    arena.press(both)
    assert_true(arena.battle.fighter.move == ULTIMATE)
    assert_true(holds_text(arena.battle.notes, "ULTIMATE!"))
    assert_true(arena.battle.slow > 0)
    assert_almost_equal(arena.battle.fighter.over, 0, atol=1e-6)
    arena.run(3)
    assert_true(arena.battle.fighter.free())
    # Six hits on each of the two dummies within its reach.
    assert_equal(arena.battle.fighter.combo - before, 12)
    # A player who reels cannot make it.
    arena.battle.notes.clear()
    arena.battle.fighter.over = 5
    arena.battle.fighter.move = FLINCH
    arena.battle.fighter.clock = 0
    arena.press(both)
    assert_false(holds_text(arena.battle.notes, "ULTIMATE!"))


def test_a_companion_casts_heals_and_makes_a_assist_attack() raises:
    var arena = Arena(arena_parameters(0, 1, ally=True))
    assert_equal(len(arena.battle.allies), 1)
    assert_equal(len(arena.battle.movers()), 2)
    # Out of a fight, she stays near the player; with nobody to cast at, a
    # call for the assist attack does nothing.
    var assist = no_input()
    assist.assist = True
    arena.press(assist)
    arena.run(1)
    assert_false(holds_text(arena.battle.notes, "ASSIST ATTACK!"))
    # Locked on the dummy, she casts bolts that strike it.
    var lock = no_input()
    lock.lock = True
    arena.press(lock)
    assert_equal(arena.battle.lock, 0)
    assert_equal(arena.battle.ally_target(arena.player.position), 0)
    arena.run(1)
    assert_true(holds_text(popup_texts(arena.battle), "28"))
    arena.run(2)
    assert_true(arena.battle.allies[0].mind.assist > 0)
    # Before her gauge is full, the assist button does nothing.
    arena.press(assist)
    assert_false(holds_text(arena.battle.notes, "ASSIST ATTACK!"))
    # She heals a wounded player.
    arena.battle.fighter.health = 100
    arena.run(1)
    assert_almost_equal(arena.battle.fighter.health, 175, atol=1e-3)
    assert_true(holds_text(arena.battle.notes, "YOUR COMPANION HEALS 75"))
    # With a full gauge, the assist button sends her assist attack.
    arena.battle.allies[0].mind.charge(1000)
    arena.press(assist)
    assert_true(holds_text(arena.battle.notes, "ASSIST ATTACK!"))
    assert_true(arena.battle.allies[0].fighter.move == CAST)
    # Let go of the lock in her cast: she casts at nobody.
    arena.battle.lock = -1
    arena.run(1)
    assert_true(holds_text(popup_texts(arena.battle), "70"))
    assert_equal(arena.battle.ally_target(arena.player.position), -1)


def test_a_bolt_fades_and_a_fallen_foe_takes_nothing() raises:
    var arena = Arena(arena_parameters(2, 0, 4, ally=True))
    ref b = arena.battle
    # Bandits at their posts, or going back, draw no casts; a fighting
    # one does, unless it is down.
    assert_equal(b.ally_target(arena.player.position), -1)
    b.foes[0].brain.state = RETURNING
    b.foes[1].brain.state = CLOSING
    assert_equal(b.ally_target(arena.player.position), 1)
    b.foes[0].brain.state = CLOSING
    assert_equal(b.ally_target(arena.player.position), 0)
    b.foes[0].down = 0
    assert_equal(b.ally_target(arena.player.position), 1)
    # A lock on a fallen foe draws no cast.
    b.lock = 0
    assert_equal(b.ally_target(arena.player.position), 1)
    b.lock = -1
    # A bolt at a fallen foe fades, and so does an old one; one that
    # strikes a foe as it falls does nothing, and fills no gauge.
    var faint = b.allies[0].fighter.blow()
    var at = b.target_at(1) + Vector3(0, CHEST, 0)
    b.bolts.append(Bolt(at, at, 0, faint, False, 0))
    b.bolts.append(Bolt(at, at, 1, faint, False, 5))
    b.foes[1].fighter.move = FALL
    b.bolts.append(Bolt(at, at, 1, faint, False, 0))
    arena.tick(no_input())
    assert_equal(len(arena.battle.bolts), 0)
    assert_almost_equal(arena.battle.allies[0].mind.assist, 0, atol=1e-6)
    assert_almost_equal(arena.battle.foes[1].fighter.health, 300, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
