# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's cuts against bandits: a defeat and a return, a guard
and a stagger, a broken attack, a fall, and a finish.

The player stands at the middle and faces -z. The dummy stands 1.5
meters before them, and the bandit 6 meters before them: see
`tests/_village_arena.mojo`."""

from tests._village_arena import (
    Arena,
    arena_parameters,
    holds_text,
    popup_texts,
    herb_seed,
    light_cut,
    stand_facing,
    stand_swinging,
)
from extensions.village.battle import HIT_STOP, SHAKE, LOOT
from extensions.village.character import no_input
from extensions.village.combat import (
    BLOCKED,
    FALL,
    CRITICAL,
    STAGGER,
    FLINCH,
    HEAVY,
    Blow,
)
from extensions.village.foes import (
    ALERTED,
    ATTACKING,
    CLOSING,
    GUARDING,
    RETREATING,
    RETURNING,
    POSTED,
)
from extensions.village.skills import BLOW_EXPERIENCE, DEFEAT_EXPERIENCE
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import DEGREE, METER_PER_SECOND, Angle, Velocity


def test_the_player_defeats_a_bandit_who_comes_back() raises:
    var arena = Arena(arena_parameters(1, 0))
    stand_swinging(arena, 0)
    ref foe = arena.battle.foes[0]
    foe.fighter.move = FLINCH
    foe.fighter.health = 1
    foe.brain.seed = herb_seed(True)
    arena.battle.lock = 0
    arena.battle.token = 0
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    arena.run(0.3)
    assert_true(arena.battle.foes[0].fighter.defeated())
    assert_equal(arena.battle.foes[0].down >= 0, True)
    assert_equal(arena.battle.lock, -1)
    assert_equal(arena.battle.token, -1)
    assert_false(arena.battle.standing(0))
    assert_almost_equal(arena.battle.obstacles()[0].radius, 0, atol=1e-6)
    assert_equal(arena.battle.loot, LOOT)
    assert_true(holds_text(arena.battle.notes, "+8 COINS +1 HERB"))
    assert_equal(arena.battle.found, 1)
    assert_equal(arena.battle.trained, BLOW_EXPERIENCE + DEFEAT_EXPERIENCE)
    arena.run(1.2)
    assert_false(arena.scene.node(arena.battle.node_of(0)).visible)
    arena.run(1.2)
    assert_true(arena.battle.foes[0].fighter.free())
    assert_true(arena.battle.foes[0].down < 0)
    assert_true(arena.scene.node(arena.battle.node_of(0)).visible)


def test_a_guard_blocks_a_cut_and_a_stagger_takes_a_critical() raises:
    var arena = Arena(arena_parameters(1, 0))
    stand_facing(arena)
    arena.battle.foes[0].brain.state = GUARDING
    arena.battle.foes[0].brain.timer = 5
    arena.battle.foes[0].fighter.hold_guard(True)
    light_cut(arena)
    assert_true(holds_text(popup_texts(arena.battle), "BLOCKED"))
    assert_almost_equal(arena.battle.foes[0].fighter.health, 300, atol=1e-6)
    var broken = Arena(arena_parameters(1, 0))
    stand_facing(broken)
    broken.battle.foes[0].brain.state = ALERTED
    broken.battle.foes[0].brain.timer = 5
    broken.battle.foes[0].fighter.move = STAGGER
    light_cut(broken)
    assert_true(holds_text(popup_texts(broken.battle), "CRITICAL"))


def test_a_cut_breaks_off_an_attack_and_fells_a_bandit() raises:
    var arena = Arena(arena_parameters(2, 0))
    stand_facing(arena)
    ref attacker = arena.battle.foes[0]
    attacker.brain.state = ATTACKING
    attacker.brain.plan = [HEAVY, HEAVY]
    arena.battle.token = 0
    light_cut(arena)
    assert_true(arena.battle.foes[0].brain.state == RETREATING)
    assert_equal(arena.battle.token, -1)
    # A bandit with no token and no lock on it falls.
    var fell = Arena(arena_parameters(1, 0))
    stand_facing(fell)
    fell.battle.foes[0].fighter.health = 1
    fell.battle.foes[0].brain.seed = herb_seed(False)
    light_cut(fell)
    assert_true(holds_text(fell.battle.notes, "+8 COINS"))
    assert_equal(fell.battle.found, 0)
    assert_true(fell.battle.foes[0].fighter.defeated())
    assert_equal(fell.battle.token, -1)
    assert_equal(fell.battle.lock, -1)
    # A fallen bandit cannot be locked on to.
    assert_equal(
        fell.battle.pick_lock(Vector3(0, 0, 0), Angle(0.0, DEGREE)), -1
    )


def test_a_fallen_player_comes_to_at_the_start() raises:
    # The second bandit stays at its post, 7 meters off.
    var arena = Arena(arena_parameters(2, 0))
    arena.battle.lock = 0
    # A bandit on its way to the player goes home when the player falls.
    arena.battle.foes[0].brain.state = CLOSING
    arena.battle.foes[0].character.position = Vector3(0, 0, -3)
    _ = arena.battle.fighter.receive(
        Blow(
            1000,
            0,
            Velocity(2.0, METER_PER_SECOND),
            Velocity(0.0, METER_PER_SECOND),
        ),
        False,
    )
    arena.battle.shove = Vector3(2, 0, 0)
    # A fallen player makes no move.
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    assert_true(arena.battle.fighter.defeated())
    assert_equal(arena.battle.lock, -1)
    assert_true(holds_text(arena.battle.notes, "YOU FALL"))
    assert_true(arena.battle.foes[0].brain.state == RETURNING)
    assert_true(arena.battle.foes[1].brain.state == POSTED)
    assert_true(arena.player.position.x > 0)
    arena.run(0.6)
    assert_true(arena.battle.fighter.free())
    assert_almost_equal(arena.player.position.x, 0, atol=1e-4)
    assert_true(holds_text(arena.battle.notes, "YOU COME TO BY THE TRAIL"))


def test_a_heavy_cut_finishes_a_broken_bandit() raises:
    var arena = Arena(arena_parameters(1, 0))
    stand_facing(arena)
    arena.battle.foes[0].brain.state = ALERTED
    arena.battle.foes[0].brain.timer = 5
    arena.battle.foes[0].fighter.move = STAGGER
    arena.battle.foes[0].fighter.health = 60
    var heavy = no_input()
    heavy.heavy = True
    arena.tick(heavy)
    var finished = False
    for _ in range(20):
        arena.tick(no_input())
        if arena.battle.foes[0].fighter.defeated():
            finished = True
            break
    assert_true(finished)
    assert_true(holds_text(popup_texts(arena.battle), "FINISHER"))
    assert_equal(arena.battle.loot, LOOT)
    assert_almost_equal(arena.battle.shake, 2 * SHAKE, atol=1e-6)
    assert_true(arena.battle.freeze > HIT_STOP)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
