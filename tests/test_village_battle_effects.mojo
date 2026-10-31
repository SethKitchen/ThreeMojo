# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The combos' effects in a fight: what each finisher's effect does to its
foe and the targets near, the wounds that bleed, the marks, and the
flashes that fade.

The player stands at the middle and faces -z. The bandit stands six
meters before them, and the dummies 1.5 meters before them, three meters
apart along x: see `tests/_village_arena.mojo`."""

from tests._village_arena import Arena, arena_parameters, popup_texts
from extensions.village.battle import (
    BLEED_SECONDS,
    BLEED_SHARE,
    CHAIN_TARGETS,
    DRAIN_SHARE,
    FLASH_SECONDS,
    LAUNCH_SPEED,
    MARK_BONUS,
    MARK_SECONDS,
    Battle,
    Wound,
)
from extensions.village.character import no_input
from extensions.village.combat import HIT, Blow, Struck
from extensions.village.combos import (
    BLEED,
    CHAIN,
    DRAIN,
    LAUNCH,
    MARK,
    NO_EFFECT,
    SHOCKWAVE,
    SUNDER,
    ComboEffect,
)
from extensions.village.missiles import SPARK
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import METER_PER_SECOND, Velocity


def _blow() -> Blow:
    """Return a finisher's blow of 40 damage."""
    return Blow(
        40, 10, Velocity(0.0, METER_PER_SECOND), Velocity(0.0, METER_PER_SECOND)
    )


def _struck() -> Struck:
    """Return a blow of 40 damage that landed."""
    return Struck(HIT, 40, 10)


def _finish(mut battle: Battle, effect: ComboEffect):
    """Make the battle's finisher the first combo with an effect."""
    for k in range(len(battle.book.combos)):
        if battle.book.combos[k].effect == effect:
            battle.finisher = k
            return


def _holds(texts: List[String], text: String) -> Int:
    """Return how many of the texts are a text."""
    var count = 0
    for t in texts:
        if t == text:
            count += 1
    return count


def test_a_finisher_launches_sunders_and_drains() raises:
    var arena = Arena(arena_parameters(1, 3))
    arena.tick(no_input())
    # With no effect, nothing more.
    _finish(arena.battle, NO_EFFECT)
    arena.battle._afflict(arena.scene, 1, _struck(), _blow())
    assert_equal(len(arena.battle.flashes), 0)
    # A launch throws a bandit up, and leaves a dummy where it stands.
    _finish(arena.battle, LAUNCH)
    arena.battle._afflict(arena.scene, 0, _struck(), _blow())
    ref bandit = arena.battle.foes[0].character
    assert_true(bandit.velocity.y >= LAUNCH_SPEED - 1.0e-4)
    assert_false(bandit.grounded)
    assert_true(_holds(popup_texts(arena.battle), "LAUNCH") == 1)
    arena.battle._afflict(arena.scene, 1, _struck(), _blow())
    assert_equal(len(arena.battle.flashes), 2)
    assert_true(arena.battle.flashes[0].effect == LAUNCH)
    # A sunder breaks the bandit's guard and empties its stamina.
    _finish(arena.battle, SUNDER)
    arena.battle.foes[0].fighter.hold_guard(True)
    arena.battle._afflict(arena.scene, 0, _struck(), _blow())
    assert_equal(arena.battle.foes[0].fighter.stamina, 0)
    assert_false(arena.battle.foes[0].fighter.guarding)
    arena.battle._afflict(arena.scene, 1, _struck(), _blow())
    # A drain heals the player by a share of the blow, up to their most;
    # its light runs to them.
    _finish(arena.battle, DRAIN)
    arena.battle.fighter.health = 100
    arena.battle._afflict(arena.scene, 1, _struck(), _blow())
    assert_almost_equal(
        arena.battle.fighter.health, 100 + 40 * DRAIN_SHARE, atol=1e-3
    )
    var light = arena.battle.flashes[len(arena.battle.flashes) - 1].copy()
    assert_true(light.effect == DRAIN)
    assert_true((light.to - light.at).length() > 0.5)
    var most = arena.battle.fighter.parameters.health
    arena.battle.fighter.health = most
    arena.battle._afflict(arena.scene, 1, _struck(), _blow())
    assert_equal(arena.battle.fighter.health, most)
    # Each flash fades.
    arena.battle._effects_step(FLASH_SECONDS)
    assert_equal(len(arena.battle.flashes), 0)


def test_a_wound_bleeds_and_never_fells() raises:
    var arena = Arena(arena_parameters(1, 3))
    _finish(arena.battle, BLEED)
    arena.battle._afflict(arena.scene, 0, _struck(), _blow())
    assert_equal(len(arena.battle.wounds), 1)
    var health = arena.battle.foes[0].fighter.health
    for _ in range(Int(BLEED_SECONDS / 0.05) + 2):
        arena.battle._effects_step(0.05)
    assert_equal(len(arena.battle.wounds), 0)
    var lost = health - arena.battle.foes[0].fighter.health
    assert_almost_equal(lost, 40 * BLEED_SHARE, atol=0.05)
    var numbers = len(popup_texts(arena.battle))
    assert_true(numbers >= 8)
    # A wound does not fell: the bandit keeps one point of health.
    arena.battle.foes[0].fighter.health = 2
    arena.battle.wounds.append(Wound(0, 1, 100, 0, 0))
    arena.battle._effects_step(0.6)
    assert_equal(arena.battle.foes[0].fighter.health, 1)
    # A wound on a dummy shows its numbers; one too slight shows none.
    arena.battle.wounds.clear()
    arena.battle.wounds.append(Wound(1, 0.5, 4, 0, 0))
    arena.battle.wounds.append(Wound(2, 0.5, 0.1, 0, 0))
    var before = len(popup_texts(arena.battle))
    arena.battle._effects_step(0.5)
    assert_equal(len(popup_texts(arena.battle)) - before, 1)
    # A fallen foe's wound stops.
    arena.battle.wounds.append(Wound(0, 1, 4, 0, 0))
    arena.battle.foes[0].down = 0
    arena.battle._effects_step(0.1)
    assert_equal(len(arena.battle.wounds), 0)


def test_a_shockwave_strikes_the_targets_near() raises:
    var arena = Arena(arena_parameters(1, 3))
    arena.tick(no_input())
    _finish(arena.battle, SHOCKWAVE)
    # From the middle dummy: the two beside it, three meters off, and not
    # the bandit, further.
    arena.battle._afflict(arena.scene, 2, _struck(), _blow())
    assert_equal(_holds(popup_texts(arena.battle), "20"), 2)
    # A fallen bandit is not struck.
    arena.battle.foes[0].down = 0
    arena.battle.foes[0].character.position = Vector3(3, 0, -1.5)
    arena.battle._afflict(arena.scene, 2, _struck(), _blow())
    assert_equal(_holds(popup_texts(arena.battle), "20"), 4)


def test_a_chain_leaps_to_the_targets_near() raises:
    var arena = Arena(arena_parameters(1, 3))
    arena.tick(no_input())
    _finish(arena.battle, CHAIN)
    # From the last dummy, sparks leap to the bandit and the two other
    # dummies, and no more.
    arena.battle._afflict(arena.scene, 3, _struck(), _blow())
    assert_equal(len(arena.battle.shots), CHAIN_TARGETS)
    for shot in arena.battle.shots:
        assert_true(shot.kind == SPARK)
        assert_true(shot.has_struck(3))
    var arcs = 0
    for flash in arena.battle.flashes:
        if flash.effect == CHAIN:
            arcs += 1
    assert_equal(arcs, CHAIN_TARGETS + 1)
    # Too far, or fallen, a target is not leapt to.
    arena.battle.shots.clear()
    arena.battle.foes[0].down = 0
    arena.battle.foes[0].character.position = Vector3(0, 0, -30)
    arena.battle.dummies[0].dummy.post.x = -30
    arena.tick(no_input())
    arena.battle.shots.clear()
    arena.battle._afflict(arena.scene, 3, _struck(), _blow())
    assert_equal(len(arena.battle.shots), 1)


def test_a_mark_makes_each_blow_on_it_stronger() raises:
    var arena = Arena(arena_parameters(0, 2))
    _finish(arena.battle, MARK)
    arena.battle._afflict(arena.scene, 0, _struck(), _blow())
    assert_equal(arena.battle.marks[0], MARK_SECONDS)
    var source = Vector3(0, 0, 0)
    var marked = arena.battle._strike(arena.scene, 0, _blow(), source)
    assert_almost_equal(marked.damage, 40 * MARK_BONUS, atol=1e-3)
    var plain = arena.battle._strike(arena.scene, 1, _blow(), source)
    assert_almost_equal(plain.damage, 40, atol=1e-3)
    # The mark runs out.
    arena.battle._effects_step(MARK_SECONDS)
    assert_equal(arena.battle.marks[0], 0)
    var after = arena.battle._strike(arena.scene, 0, _blow(), source)
    assert_almost_equal(after.damage, 40, atol=1e-3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
